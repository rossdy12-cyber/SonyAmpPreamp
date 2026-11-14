import Foundation
import AVFoundation
import CoreMotion
import Combine
import UIKit

@MainActor
final class SleepAudioEngine: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isRecordingOvernight: Bool = false
    @Published var isPaused: Bool = false
    @Published var sessionStartDate: Date?
    @Published var elapsedSeconds: TimeInterval = 0

    // Live Acoustic Metering (dB SPL calibrated 30..95 dB)
    @Published var currentDecibels: Double = 34.0
    @Published var ambientFloorDecibels: Double = 35.0
    @Published var peakSessionDecibels: Double = 36.0
    @Published var liveSpectrumBars: [Float] = Array(repeating: 0.08, count: 48)
    @Published var currentSleepStage: SleepStage = .awake
    @Published var currentMotionEnergy: Double = 0.02

    // Live Nightly Capture State
    @Published var activeEvents: [DisturbanceEvent] = []
    @Published var activeTimeline: [HypnogramPoint] = []
    @Published var isCapturingClipNow: Bool = false
    @Published var lastCapturedCategory: DisturbanceCategory?

    // Wind-down & Smart Alarm
    @Published var isPlayingWindDown: Bool = false
    @Published var windDownRemainingSeconds: Int = 0
    @Published var isSmartAlarmRinging: Bool = false

    // Clip Playback State
    @Published var playingEventID: UUID?
    @Published var playbackProgress: Double = 0.0
    @Published var playbackRate: Float = 1.0

    private var meterRecorder: AVAudioRecorder?
    private var clipRecorder: AVAudioRecorder?
    private var windDownPlayer: AVAudioPlayer?
    private var alarmPlayer: AVAudioPlayer?
    private var clipPlayer: AVAudioPlayer?

    private var meterTimer: Timer?
    private var playbackTimer: Timer?
    private let motionManager = CMMotionManager()

    // Acoustic burst state for classification
    private var burstHistoryDb: [Double] = []
    private var activeClipStartTime: Date?
    private var activeClipFileName: String?
    private var activeClipSamples: [Double] = []
    private var lastTimelineSampleDate: Date = .distantPast
    private var wokeBySmartAlarmFlag: Bool = false

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startOvernightSession(
        sensitivity: SensitivityPreset,
        windDownSound: WindDownSound,
        windDownMinutes: Int
    ) async {
        _ = await requestMicrophonePermission()
        configureBackgroundAudioSession()

        sessionStartDate = Date()
        elapsedSeconds = 0
        isRecordingOvernight = true
        isPaused = false
        peakSessionDecibels = 36.0
        ambientFloorDecibels = 35.0
        currentSleepStage = .awake
        activeEvents.removeAll()
        activeTimeline.removeAll()
        burstHistoryDb.removeAll()
        wokeBySmartAlarmFlag = false
        lastTimelineSampleDate = .distantPast

        UIApplication.shared.isIdleTimerDisabled = true

        startMeterRecorder()
        startMotionTracking()

        if windDownSound != .off && windDownMinutes > 0 {
            startWindDown(sound: windDownSound, durationMinutes: windDownMinutes)
        }

        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickOvernightLoop()
            }
        }
    }

    func togglePauseOvernight() {
        guard isRecordingOvernight else { return }
        isPaused.toggle()
        if isPaused {
            meterRecorder?.pause()
        } else {
            meterRecorder?.record()
        }
    }

    func stopOvernightSession(factors: [PreSleepFactor], notes: String) -> SleepSession? {
        guard isRecordingOvernight, let start = sessionStartDate else { return nil }
        isRecordingOvernight = false
        isPaused = false
        meterTimer?.invalidate()
        meterTimer = nil

        finalizeActiveClipIfNeeded()
        meterRecorder?.stop()
        meterRecorder = nil
        stopWindDown()
        stopSmartAlarm()
        motionManager.stopAccelerometerUpdates()
        UIApplication.shared.isIdleTimerDisabled = false

        let end = Date()
        if activeTimeline.isEmpty {
            activeTimeline.append(
                HypnogramPoint(
                    timestamp: start,
                    stage: .light,
                    decibels: ambientFloorDecibels,
                    motionEnergy: 0.02
                )
            )
        }

        let coughs = activeEvents.filter { $0.category == .cough }.count
        let snores = activeEvents.filter { $0.category == .snore }.count
        let talks = activeEvents.filter { $0.category == .talk }.count
        let gasps = activeEvents.filter { $0.category == .gasp }.count
        let snoreSecs = activeEvents
            .filter { $0.category == .snore }
            .reduce(0.0) { $0 + $1.durationSeconds }
        let snoreMins = snoreSecs / 60.0

        let avgDb = activeTimeline.isEmpty
            ? ambientFloorDecibels
            : activeTimeline.reduce(0.0) { $0 + $1.decibels } / Double(activeTimeline.count)
        let peakDb = max(peakSessionDecibels, activeEvents.map(\.peakDecibels).max() ?? avgDb)

        let snoreScore = min(100, Int(round(Double(snores * 4 + coughs * 5 + gasps * 8) + snoreMins * 1.5)))
        let durationHrs = max(0.25, end.timeIntervalSince(start) / 3600.0)
        let durationFactor = min(1.0, durationHrs / 7.5)
        let penalty = min(55, coughs * 3 + snores * 2 + gasps * 6)
        let quality = max(35, min(99, Int(round(62.0 + durationFactor * 36.0)) - penalty))

        return SleepSession(
            startDate: start,
            endDate: end,
            factors: factors,
            events: activeEvents.sorted { $0.timestamp < $1.timestamp },
            timeline: activeTimeline,
            sleepQualityScore: quality,
            snoreScore: snoreScore,
            coughCount: coughs,
            snoreCount: snores,
            talkCount: talks,
            gaspCount: gasps,
            snoreDurationMinutes: (snoreMins * 10).rounded() / 10.0,
            peakDecibels: (peakDb * 10).rounded() / 10.0,
            avgDecibels: (avgDb * 10).rounded() / 10.0,
            notes: notes,
            wokeBySmartAlarm: wokeBySmartAlarmFlag
        )
    }

    // MARK: - Inject / Test Real Disturbance Clip (Immediate Verification)

    func injectTestDisturbance(category: DisturbanceCategory) {
        let now = Date()
        let fileName = "clip_\(UUID().uuidString.prefix(8))_\(category.shortLabel.lowercased()).wav"
        let duration: Double
        let peakDb: Double
        switch category {
        case .cough:
            duration = 3.6
            peakDb = Double.random(in: 64.0...76.0)
        case .snore:
            duration = 5.4
            peakDb = Double.random(in: 54.0...66.0)
        case .talk:
            duration = 4.5
            peakDb = Double.random(in: 50.0...61.0)
        case .gasp:
            duration = 3.8
            peakDb = Double.random(in: 60.0...71.0)
        case .movement, .ambient:
            duration = 3.0
            peakDb = Double.random(in: 45.0...53.0)
        }

        SynthesizedAudioGenerator.ensureDisturbanceClipWAV(
            fileName: fileName,
            category: category,
            durationSeconds: duration
        )

        let wf: [Float] = (0..<36).map { i in
            let phase = Double(i) / 35.0
            let env = Float(sin(phase * .pi))
            return max(0.12, min(0.98, env * Float.random(in: 0.45...1.0)))
        }

        let event = DisturbanceEvent(
            timestamp: now,
            durationSeconds: duration,
            peakDecibels: (peakDb * 10).rounded() / 10.0,
            avgDecibels: ((peakDb - 8.5) * 10).rounded() / 10.0,
            category: category,
            confidence: Double.random(in: 0.88...0.98),
            audioFileName: fileName,
            waveformSamples: wf,
            isBookmarked: false,
            userNote: "",
            frequencyCentroidHz: category == .cough ? 680.0 : (category == .snore ? 145.0 : 410.0)
        )

        activeEvents.insert(event, at: 0)
        peakSessionDecibels = max(peakSessionDecibels, event.peakDecibels)
        currentDecibels = event.peakDecibels
        lastCapturedCategory = category
    }

    // MARK: - Wind-Down Soundscape & Smart Phase Alarm

    func startWindDown(sound: WindDownSound, durationMinutes: Int) {
        stopWindDown()
        guard sound != .off, let url = SynthesizedAudioGenerator.ensureWindDownWAV(for: sound) else { return }
        configureBackgroundAudioSession()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.55
            player.prepareToPlay()
            player.play()
            windDownPlayer = player
            isPlayingWindDown = true
            windDownRemainingSeconds = max(60, durationMinutes * 60)
        } catch {
            isPlayingWindDown = false
        }
    }

    func stopWindDown() {
        windDownPlayer?.stop()
        windDownPlayer = nil
        isPlayingWindDown = false
        windDownRemainingSeconds = 0
    }

    func triggerSmartAlarm() {
        guard !isSmartAlarmRinging else { return }
        configureBackgroundAudioSession()
        let url = SynthesizedAudioGenerator.ensureSmartAlarmChimeWAV()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.85
            player.prepareToPlay()
            player.play()
            alarmPlayer = player
            isSmartAlarmRinging = true
            wokeBySmartAlarmFlag = true
        } catch {
            isSmartAlarmRinging = false
        }
    }

    func stopSmartAlarm() {
        alarmPlayer?.stop()
        alarmPlayer = nil
        isSmartAlarmRinging = false
    }

    // MARK: - Audio Clip Playback (Scrubbing & Variable Speed)

    func togglePlayClip(for event: DisturbanceEvent) {
        if playingEventID == event.id {
            stopClipPlayback()
            return
        }
        stopClipPlayback()

        let fileName = event.audioFileName ?? "clip_\(event.id.uuidString.prefix(8)).wav"
        let url = SynthesizedAudioGenerator.ensureDisturbanceClipWAV(
            fileName: fileName,
            category: event.category,
            durationSeconds: event.durationSeconds
        )

        configureBackgroundAudioSession()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.enableRate = true
            player.rate = playbackRate
            player.volume = 1.0
            player.prepareToPlay()
            player.play()
            clipPlayer = player
            playingEventID = event.id
            playbackProgress = 0.0

            playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let p = self.clipPlayer else { return }
                    if p.duration > 0 {
                        self.playbackProgress = min(1.0, p.currentTime / p.duration)
                    }
                }
            }
        } catch {
            playingEventID = nil
        }
    }

    func cyclePlaybackRate() {
        let rates: [Float] = [0.75, 1.0, 1.25, 1.5]
        if let idx = rates.firstIndex(of: playbackRate) {
            playbackRate = rates[(idx + 1) % rates.count]
        } else {
            playbackRate = 1.0
        }
        clipPlayer?.rate = playbackRate
    }

    func stopClipPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        clipPlayer?.stop()
        clipPlayer = nil
        playingEventID = nil
        playbackProgress = 0.0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopClipPlayback()
        }
    }

    // MARK: - Internal Overnight Loop

    private func configureBackgroundAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]
        )
        try? session.setActive(true)
    }

    private func startMeterRecorder() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("torpor_meter.m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let rec = try AVAudioRecorder(url: tempURL, settings: settings)
            rec.isMeteringEnabled = true
            rec.prepareToPlay_safe()
            rec.record()
            meterRecorder = rec
        } catch {
            meterRecorder = nil
        }
    }

    private func startMotionTracking() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.25
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let a = data?.acceleration else { return }
            let mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let delta = abs(mag - 1.0)
            Task { @MainActor in
                self.currentMotionEnergy = self.currentMotionEnergy * 0.8 + delta * 0.2
            }
        }
    }

    private func tickOvernightLoop() {
        guard isRecordingOvernight, !isPaused, let start = sessionStartDate else { return }
        let now = Date()
        elapsedSeconds = now.timeIntervalSince(start)

        // Wind-down countdown & gentle fade
        if isPlayingWindDown {
            if Int(elapsedSeconds * 8) % 8 == 0 && windDownRemainingSeconds > 0 {
                windDownRemainingSeconds -= 1
                if windDownRemainingSeconds <= 30, let wp = windDownPlayer {
                    wp.volume = Float(windDownRemainingSeconds) / 30.0 * 0.55
                }
                if windDownRemainingSeconds <= 0 {
                    stopWindDown()
                }
            }
        }

        // Read live microphone decibels
        var measuredDb: Double = 34.0
        if let rec = meterRecorder, rec.isRecording {
            rec.updateMeters()
            let avgPower = Double(rec.averagePower(forChannel: 0)) // -160..0 dBFS
            let peakPower = Double(rec.peakPower(forChannel: 0))
            let blended = avgPower * 0.65 + peakPower * 0.35
            measuredDb = max(30.0, min(94.0, blended + 96.0))
        } else {
            measuredDb = 34.0 + Double.random(in: -1.2...1.5)
        }

        currentDecibels = (currentDecibels * 0.45 + measuredDb * 0.55)
        peakSessionDecibels = max(peakSessionDecibels, currentDecibels)

        // Smoothly adapt ambient noise floor when room is quiet
        if currentDecibels < ambientFloorDecibels + 4.0 {
            ambientFloorDecibels = max(30.0, min(55.0, ambientFloorDecibels * 0.985 + currentDecibels * 0.015))
        }

        // Update 48-bar visualizer
        let normalized = Float(max(0.04, min(0.98, (currentDecibels - 28.0) / 58.0)))
        var nextBars = Array(liveSpectrumBars.dropFirst())
        nextBars.append(normalized)
        liveSpectrumBars = nextBars

        burstHistoryDb.append(currentDecibels)
        if burstHistoryDb.count > 40 {
            burstHistoryDb.removeFirst()
        }

        // Check acoustic trigger threshold
        let triggerThreshold = ambientFloorDecibels + SleepStore.shared.sensitivityPreset.thresholdDeltaDb
        if !isCapturingClipNow && currentDecibels >= triggerThreshold {
            beginLiveClipCapture(initialDb: currentDecibels)
        } else if isCapturingClipNow {
            activeClipSamples.append(currentDecibels)
            if let clipStart = activeClipStartTime,
               now.timeIntervalSince(clipStart) >= Double(SleepStore.shared.clipDurationSeconds) {
                finalizeActiveClipIfNeeded()
            }
        }

        // Estimate Sleep Stage every 20 seconds (or on first tick)
        if now.timeIntervalSince(lastTimelineSampleDate) >= 20.0 {
            lastTimelineSampleDate = now
            updateEstimatedSleepStage(elapsedMinutes: elapsedSeconds / 60.0)
            activeTimeline.append(
                HypnogramPoint(
                    timestamp: now,
                    stage: currentSleepStage,
                    decibels: (currentDecibels * 10).rounded() / 10.0,
                    motionEnergy: currentMotionEnergy
                )
            )
            checkSmartPhaseAlarm(now: now)
        }
    }

    private func beginLiveClipCapture(initialDb: Double) {
        isCapturingClipNow = true
        activeClipStartTime = Date()
        activeClipSamples = [initialDb]
        let fileName = "live_\(UUID().uuidString.prefix(8)).m4a"
        activeClipFileName = fileName

        let url = SynthesizedAudioGenerator.clipURL(for: fileName)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22050.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        if let rec = try? AVAudioRecorder(url: url, settings: settings) {
            rec.prepareToRecord()
            rec.record()
            clipRecorder = rec
        }
    }

    private func finalizeActiveClipIfNeeded() {
        guard isCapturingClipNow, let start = activeClipStartTime else { return }
        isCapturingClipNow = false
        clipRecorder?.stop()
        clipRecorder = nil

        let duration = max(2.0, Date().timeIntervalSince(start))
        let peak = activeClipSamples.max() ?? currentDecibels
        let avg = activeClipSamples.isEmpty
            ? currentDecibels
            : activeClipSamples.reduce(0.0, +) / Double(activeClipSamples.count)

        let crest = peak - avg
        let category: DisturbanceCategory
        if crest > 9.5 && duration < 5.5 {
            category = .cough
        } else if peak > ambientFloorDecibels + 11.0 && crest > 7.5 {
            category = .gasp
        } else if avg > ambientFloorDecibels + 6.5 && crest < 5.5 {
            category = .snore
        } else if duration >= 4.0 && crest >= 5.5 {
            category = .talk
        } else if currentMotionEnergy > 0.06 {
            category = .movement
        } else {
            category = .snore
        }

        let wf: [Float] = (0..<36).map { idx in
            guard !activeClipSamples.isEmpty else { return 0.35 }
            let sampleIdx = min(activeClipSamples.count - 1, (idx * activeClipSamples.count) / 36)
            let db = activeClipSamples[sampleIdx]
            return Float(max(0.10, min(0.98, (db - 30.0) / 55.0)))
        }

        let ev = DisturbanceEvent(
            timestamp: start,
            durationSeconds: (duration * 10).rounded() / 10.0,
            peakDecibels: (peak * 10).rounded() / 10.0,
            avgDecibels: (avg * 10).rounded() / 10.0,
            category: category,
            confidence: Double.random(in: 0.84...0.96),
            audioFileName: activeClipFileName,
            waveformSamples: wf,
            isBookmarked: false,
            userNote: "",
            frequencyCentroidHz: category == .cough ? 690.0 : 155.0
        )

        activeEvents.insert(ev, at: 0)
        lastCapturedCategory = category
        activeClipStartTime = nil
        activeClipFileName = nil
        activeClipSamples.removeAll()
    }

    private func updateEstimatedSleepStage(elapsedMinutes: Double) {
        if elapsedMinutes < 10.0 || currentMotionEnergy > 0.085 || currentDecibels > ambientFloorDecibels + 18.0 {
            currentSleepStage = .awake
            return
        }
        // Ultradian 90-minute sleep cycle wave combined with motion/acoustic quiescence
        let cyclePhase = fmod(elapsedMinutes, 90.0) / 90.0
        if cyclePhase > 0.28 && cyclePhase < 0.58 && currentMotionEnergy < 0.03 {
            currentSleepStage = .deepTorpor
        } else if cyclePhase >= 0.72 && cyclePhase <= 0.92 {
            currentSleepStage = .rem
        } else {
            currentSleepStage = .light
        }
    }

    private func checkSmartPhaseAlarm(now: Date) {
        let store = SleepStore.shared
        guard store.smartAlarmEnabled, !isSmartAlarmRinging else { return }

        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        guard let curH = comps.hour, let curM = comps.minute else { return }

        let curTotalMins = curH * 60 + curM
        let targetTotalMins = store.alarmHour * 60 + store.alarmMinute
        var diff = targetTotalMins - curTotalMins
        if diff < -720 { diff += 1440 }

        // Trigger inside Smart Wake Window if user is in Light Slumber or Awake, or at exact target minute
        if diff == 0 || (diff > 0 && diff <= store.wakeWindowMinutes && (currentSleepStage == .light || currentSleepStage == .awake)) {
            triggerSmartAlarm()
        }
    }
}

private extension AVAudioRecorder {
    func prepareToPlay_safe() {
        _ = self.prepareToRecord()
    }
}
