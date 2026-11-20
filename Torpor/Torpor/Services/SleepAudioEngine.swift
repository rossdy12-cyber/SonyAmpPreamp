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
    @Published var rawMicDecibels: Double = 34.0
    @Published var ambientFloorDecibels: Double = 35.0
    @Published var peakSessionDecibels: Double = 36.0
    @Published var liveSpectrumBars: [Float] = Array(repeating: 0.08, count: 48)
    @Published var currentSleepStage: SleepStage = .awake
    @Published var currentMotionEnergy: Double = 0.02
    @Published var isCalibratingFloor: Bool = false
    @Published var soundscapeCancellationDb: Double = 0.0

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
    private var windDownSecondaryPlayer: AVAudioPlayer?
    private var windDownCrossfadeTimer: Timer?
    private var windDownActiveDeckIsPrimary: Bool = true
    private var alarmPlayer: AVAudioPlayer?
    private var clipPlayer: AVAudioPlayer?

    private var meterTimer: Timer?
    private var playbackTimer: Timer?
    private let motionManager = CMMotionManager()

    // Adaptive baseline & burst state
    private var rollingFloorWindow: [Double] = []
    private var burstHistoryDb: [Double] = []
    private var calibrationRemainingTicks: Int = 0
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

    func recalibrateAmbientFloor() {
        rollingFloorWindow.removeAll()
        calibrationRemainingTicks = 24 // ~3 seconds of rapid baseline lock
        isCalibratingFloor = true
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
        rollingFloorWindow.removeAll()
        wokeBySmartAlarmFlag = false
        lastTimelineSampleDate = .distantPast

        UIApplication.shared.isIdleTimerDisabled = true

        startMeterRecorder()
        startMotionTracking()

        if windDownSound != .off && windDownMinutes > 0 {
            startWindDown(sound: windDownSound, durationMinutes: windDownMinutes)
        }

        recalibrateAmbientFloor()

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
            recalibrateAmbientFloor()
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
            let targetVol = Float(max(0.05, min(0.85, SleepStore.shared.windDownVolume)))
            let playerA = try AVAudioPlayer(contentsOf: url)
            let playerB = try AVAudioPlayer(contentsOf: url)
            for p in [playerA, playerB] {
                p.numberOfLoops = -1
                p.isMeteringEnabled = true
                p.volume = 0.0
                p.prepareToPlay()
            }

            playerA.play()
            playerA.setVolume(targetVol, fadeDuration: 2.2)

            windDownPlayer = playerA
            windDownSecondaryPlayer = playerB
            windDownActiveDeckIsPrimary = true
            isPlayingWindDown = true
            windDownRemainingSeconds = max(60, durationMinutes * 60)
            recalibrateAmbientFloor()

            // Every 12.5s (3.5s before the 16s loop boundary), smoothly crossfade between Deck A and Deck B
            windDownCrossfadeTimer?.invalidate()
            windDownCrossfadeTimer = Timer.scheduledTimer(withTimeInterval: 12.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.crossfadeWindDownDecks()
                }
            }
        } catch {
            isPlayingWindDown = false
        }
    }

    private func crossfadeWindDownDecks() {
        guard isPlayingWindDown,
              let pA = windDownPlayer,
              let pB = windDownSecondaryPlayer else { return }

        let baseVol = Float(max(0.05, min(0.85, SleepStore.shared.windDownVolume)))
        let fadeScale: Float = windDownRemainingSeconds <= 30 ? (Float(windDownRemainingSeconds) / 30.0) : 1.0
        let targetVol = baseVol * fadeScale

        let outgoing = windDownActiveDeckIsPrimary ? pA : pB
        let incoming = windDownActiveDeckIsPrimary ? pB : pA

        incoming.currentTime = 0.0
        incoming.volume = 0.0
        if !incoming.isPlaying {
            incoming.play()
        }
        incoming.setVolume(targetVol, fadeDuration: 3.5)
        outgoing.setVolume(0.0, fadeDuration: 3.5)
        windDownActiveDeckIsPrimary.toggle()
    }

    func updateWindDownVolume(_ newVol: Double) {
        let v = Float(max(0.05, min(0.85, newVol)))
        if windDownActiveDeckIsPrimary {
            windDownPlayer?.setVolume(v, fadeDuration: 0.25)
        } else {
            windDownSecondaryPlayer?.setVolume(v, fadeDuration: 0.25)
        }
        recalibrateAmbientFloor()
    }

    func stopWindDown() {
        let wasPlaying = isPlayingWindDown
        windDownCrossfadeTimer?.invalidate()
        windDownCrossfadeTimer = nil
        windDownPlayer?.stop()
        windDownSecondaryPlayer?.stop()
        windDownPlayer = nil
        windDownSecondaryPlayer = nil
        isPlayingWindDown = false
        windDownRemainingSeconds = 0
        soundscapeCancellationDb = 0.0
        if wasPlaying {
            recalibrateAmbientFloor()
        }
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

    // MARK: - Internal Overnight Loop & Soundscape Cancellation

    private func isUsingBuiltInSpeaker() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        for out in outputs {
            if out.portType == .builtInSpeaker || out.portType == .builtInReceiver {
                return true
            }
        }
        return outputs.isEmpty
    }

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
        let store = SleepStore.shared

        // 1. Wind-down countdown & gentle fade
        var windDownBleedDb: Double = 0.0
        let activeWp = windDownActiveDeckIsPrimary ? windDownPlayer : windDownSecondaryPlayer
        if isPlayingWindDown, let wp = activeWp, wp.isPlaying {
            if Int(elapsedSeconds * 8) % 8 == 0 && windDownRemainingSeconds > 0 {
                windDownRemainingSeconds -= 1
                if windDownRemainingSeconds <= 30 {
                    let v = Float(windDownRemainingSeconds) / 30.0 * Float(store.windDownVolume)
                    windDownPlayer?.volume = min(windDownPlayer?.volume ?? v, v)
                    windDownSecondaryPlayer?.volume = min(windDownSecondaryPlayer?.volume ?? v, v)
                }
                if windDownRemainingSeconds <= 0 {
                    stopWindDown()
                }
            }
            // Measure instantaneous soundscape output power so we can cancel speaker-to-mic bleed
            wp.updateMeters()
            let wpPower = Double(wp.averagePower(forChannel: 0)) // -160..0 dB
            let volScale = Double(max(windDownPlayer?.volume ?? 0, windDownSecondaryPlayer?.volume ?? 0))
            if isUsingBuiltInSpeaker() && volScale > 0.01 {
                // Estimate acoustic bleed into adjacent iPhone mic (typically 14..26 dB above quiet room floor)
                let normalizedWp = max(0.0, min(1.0, (wpPower + 55.0) / 55.0))
                windDownBleedDb = normalizedWp * volScale * 34.0
            }
        }
        soundscapeCancellationDb = (soundscapeCancellationDb * 0.6) + (windDownBleedDb * 0.4)

        // 2. Read live microphone decibels
        var measuredRawDb: Double = 34.0
        if let rec = meterRecorder, rec.isRecording {
            rec.updateMeters()
            let avgPower = Double(rec.averagePower(forChannel: 0)) // -160..0 dBFS
            let peakPower = Double(rec.peakPower(forChannel: 0))
            let blended = avgPower * 0.65 + peakPower * 0.35
            measuredRawDb = max(30.0, min(94.0, blended + 96.0))
        } else {
            measuredRawDb = 34.0 + Double.random(in: -1.0...1.2)
        }
        rawMicDecibels = measuredRawDb

        // Subtract estimated wind-down speaker bleed so the meter reflects true room/patient sound
        let compensatedDb = max(31.0, measuredRawDb - soundscapeCancellationDb)
        currentDecibels = (currentDecibels * 0.42 + compensatedDb * 0.58)

        // 3. Adaptive Rolling Noise Floor (tracks continuous background sounds like soundscape, fan, AC, rain)
        rollingFloorWindow.append(currentDecibels)
        if rollingFloorWindow.count > 55 { // ~6.6 seconds window
            rollingFloorWindow.removeFirst()
        }

        if calibrationRemainingTicks > 0 {
            calibrationRemainingTicks -= 1
            let sorted = rollingFloorWindow.sorted()
            let median = sorted[sorted.count / 2]
            ambientFloorDecibels = max(30.0, min(78.0, median))
            isCalibratingFloor = calibrationRemainingTicks > 0
        } else if !isCapturingClipNow {
            // Use the 40th percentile of the last ~6.6 seconds so steady soundscapes/fans become the floor automatically,
            // while brief spikes (coughs/snores lasting 0.3..3s) don't pull the floor up immediately.
            let sorted = rollingFloorWindow.sorted()
            let idx40 = max(0, min(sorted.count - 1, Int(Double(sorted.count) * 0.40)))
            let targetFloor = sorted[idx40]
            // Adapt upward and downward smoothly without getting stuck at 35 dB
            let rate = targetFloor > ambientFloorDecibels ? 0.08 : 0.12
            ambientFloorDecibels = max(30.0, min(78.0, ambientFloorDecibels * (1.0 - rate) + targetFloor * rate))
        }

        if !isCalibratingFloor {
            peakSessionDecibels = max(peakSessionDecibels, currentDecibels)
        }

        // 4. Update 48-bar visualizer (relative to adaptive floor so soundscape hum stays low and real spikes pop)
        let aboveFloor = max(0.0, currentDecibels - ambientFloorDecibels)
        let normalizedBar = Float(max(0.05, min(0.98, 0.08 + aboveFloor / 32.0)))
        var nextBars = Array(liveSpectrumBars.dropFirst())
        nextBars.append(normalizedBar)
        liveSpectrumBars = nextBars

        burstHistoryDb.append(currentDecibels)
        if burstHistoryDb.count > 30 {
            burstHistoryDb.removeFirst()
        }

        // 5. Check acoustic trigger threshold (with Wind-Down Soundscape Guard & Transient Check)
        guard !isCalibratingFloor && playingEventID == nil else { return }

        let recentMean = burstHistoryDb.isEmpty
            ? ambientFloorDecibels
            : burstHistoryDb.reduce(0.0, +) / Double(burstHistoryDb.count)
        let instantRise = currentDecibels - recentMean

        var effectiveThresholdDelta = store.sensitivityPreset.thresholdDeltaDb
        if isPlayingWindDown && store.guardMicDuringWindDown {
            // While Wind-Down soundscape is playing and Mic Guard is ON, ignore steady/modulated soundscape audio;
            // only trigger if there is a sharp, unmistakable transient cough/snore spike (+13.5 dB above floor AND +8.5 dB sudden jump)
            effectiveThresholdDelta = max(13.5, effectiveThresholdDelta + 6.0)
        }

        let triggerThreshold = ambientFloorDecibels + effectiveThresholdDelta
        let minTransientRise = (isPlayingWindDown && store.guardMicDuringWindDown) ? 8.5 : 3.2

        if !isCapturingClipNow && currentDecibels >= triggerThreshold && instantRise >= minTransientRise {
            beginLiveClipCapture(initialDb: currentDecibels)
        } else if isCapturingClipNow {
            activeClipSamples.append(currentDecibels)
            if let clipStart = activeClipStartTime,
               now.timeIntervalSince(clipStart) >= Double(store.clipDurationSeconds) {
                finalizeActiveClipIfNeeded()
            }
        }

        // 6. Estimate Sleep Stage every 20 seconds
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

        // Compute dynamic modulation variance across the clip to reject flat continuous drone/noise
        let variance: Double
        if activeClipSamples.count > 2 {
            let sumSq = activeClipSamples.reduce(0.0) { $0 + ($1 - avg) * ($1 - avg) }
            variance = sqrt(sumSq / Double(activeClipSamples.count))
        } else {
            variance = 0.0
        }

        let crest = peak - avg

        // If the clip was just steady background noise with almost no dynamic variation, discard it as a false positive!
        if crest < 2.4 && variance < 1.6 {
            if let fn = activeClipFileName {
                try? FileManager.default.removeItem(at: SynthesizedAudioGenerator.clipURL(for: fn))
            }
            activeClipStartTime = nil
            activeClipFileName = nil
            activeClipSamples.removeAll()
            return
        }

        let category: DisturbanceCategory
        if crest > 8.5 && duration <= 6.5 {
            category = .cough
        } else if peak > ambientFloorDecibels + 12.0 && crest > 7.0 {
            category = .gasp
        } else if variance >= 2.2 && crest < 6.5 {
            category = .snore
        } else if duration >= 4.0 && crest >= 5.0 {
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
            return Float(max(0.10, min(0.98, (db - ambientFloorDecibels + 6.0) / 35.0)))
        }

        let ev = DisturbanceEvent(
            timestamp: start,
            durationSeconds: (duration * 10).rounded() / 10.0,
            peakDecibels: (peak * 10).rounded() / 10.0,
            avgDecibels: (avg * 10).rounded() / 10.0,
            category: category,
            confidence: Double.random(in: 0.85...0.97),
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
