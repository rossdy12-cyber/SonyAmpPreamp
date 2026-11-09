import Foundation
import AVFoundation
import AudioToolbox
import MediaPlayer
import Combine

struct PlayableItem: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let qualityBadge: String
    let localURL: URL?
    let subsonicTrack: SubsonicTrack?
}

@MainActor
final class AudioPreampEngine: ObservableObject {
    // MARK: - Published Route & Hardware State
    @Published var isUSBDACConnected: Bool = false
    @Published var activePortName: String = "iPhone Built-In Speaker"
    @Published var activePortType: String = "Speaker"
    @Published var sampleRateHz: Double = 48000.0
    @Published var autoEngageOnUSBDAC: Bool = true {
        didSet { UserDefaults.standard.set(autoEngageOnUSBDAC, forKey: "auto_engage_usb_dac") }
    }
    @Published var lineDriverActive: Bool = false

    // MARK: - Published DSP Parameters
    @Published var selectedPresetId: String = "sony_line_driver"
    @Published var preampGainDB: Float = 7.5 {
        didSet { updateDSPParameters() }
    }
    @Published var megaBassDB: Float = 2.5 {
        didSet { updateDSPParameters() }
    }
    @Published var brillianceDB: Float = 1.5 {
        didSet { updateDSPParameters() }
    }
    @Published var softLimiterEnabled: Bool = true {
        didSet { updateDSPParameters() }
    }
    @Published var eqBands: [Float] = [3.5, 3.0, 1.5, 0.5, 0.0, 0.0, 0.5, 1.0, 1.5, 2.0] {
        didSet { updateDSPParameters() }
    }
    @Published var dspBypassed: Bool = false {
        didSet { updateDSPParameters() }
    }

    // MARK: - Published Playback & Meter State
    @Published var isPlaying: Bool = false
    @Published var isLoadingTrack: Bool = false
    @Published var currentTrack: PlayableItem?
    @Published var queue: [PlayableItem] = []
    @Published var currentIndex: Int = 0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var leftLevel: Float = 0.0
    @Published var rightLevel: Float = 0.0
    @Published var limiterEngaged: Bool = false
    @Published var statusBanner: String = "Ready — Plug in USB-C to 3.5mm Adapter for Auto Sony Amp Boost"

    // MARK: - CoreAudio / AVAudioEngine Nodes
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let parametricEQ = AVAudioUnitEQ(numberOfBands: 10)
    private let exciterEQ = AVAudioUnitEQ(numberOfBands: 2)
    private let peakLimiter: AVAudioUnitEffect
    private let meterMixer = AVAudioMixerNode()

    private var currentAudioFile: AVAudioFile?
    private var seekFrameOffset: AVAudioFramePosition = 0
    private var totalFrames: AVAudioFramePosition = 0
    private var fileSampleRate: Double = 48000.0
    private var progressTimer: Timer?
    private var scheduleGeneration: Int = 0
    private var isTestTonePlaying: Bool = false

    weak var navidromeClient: NavidromeClient?

    init() {
        let limiterDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        self.peakLimiter = AVAudioUnitEffect(audioComponentDescription: limiterDesc)

        if UserDefaults.standard.object(forKey: "auto_engage_usb_dac") != nil {
            self.autoEngageOnUSBDAC = UserDefaults.standard.bool(forKey: "auto_engage_usb_dac")
        }

        setupAudioSession()
        setupAudioEngineGraph()
        setupRouteChangeNotifications()
        setupRemoteTransportControls()
        evaluateCurrentAudioRoute(reason: "App Launch")
    }

    // MARK: - Audio Session & USB-C DAC Auto-Detection
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try session.setPreferredSampleRate(48000.0)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            print("AVAudioSession setup error: \(error)")
        }
    }

    private func setupRouteChangeNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch reason {
                case .newDeviceAvailable:
                    self.evaluateCurrentAudioRoute(reason: "USB-C / 3.5mm Audio Connected")
                case .oldDeviceUnavailable:
                    self.playPause(forcePause: true)
                    self.evaluateCurrentAudioRoute(reason: "Audio Cable Disconnected")
                default:
                    self.evaluateCurrentAudioRoute(reason: "Route Updated")
                }
            }
        }
    }

    func evaluateCurrentAudioRoute(reason: String) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        self.sampleRateHz = session.sampleRate > 0 ? session.sampleRate : 48000.0

        var detectedExternalDAC = false
        var portTitle = "iPhone Built-In Speaker"
        var portKind = "Speaker"

        for output in outputs {
            portTitle = output.portName
            switch output.portType {
            case .usbAudio:
                detectedExternalDAC = true
                portKind = "USB-C Digital DAC"
            case .headphones:
                detectedExternalDAC = true
                portKind = "3.5mm Headphone / Line Adapter"
            case .lineOut:
                detectedExternalDAC = true
                portKind = "Analog Line-Out"
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                portKind = "Bluetooth Audio"
            case .airPlay:
                portKind = "AirPlay"
            default:
                portKind = output.portType.rawValue
            }
        }

        self.activePortName = portTitle
        self.activePortType = portKind
        self.isUSBDACConnected = detectedExternalDAC

        if detectedExternalDAC && autoEngageOnUSBDAC {
            if !lineDriverActive {
                lineDriverActive = true
                if let preset = EQPreset.builtInPresets.first(where: { $0.id == selectedPresetId }) ?? EQPreset.builtInPresets.first {
                    applyPreset(preset)
                }
            }
            self.statusBanner = "SONY AMP LINE-DRIVER ACTIVE • \(portTitle) (\(Int(sampleRateHz / 1000))kHz)"
        } else if !detectedExternalDAC && autoEngageOnUSBDAC {
            if lineDriverActive {
                lineDriverActive = false
                // Protect built-in iPhone speakers from +8dB line-driver boost when unplugged
                self.preampGainDB = 0.0
            }
            self.statusBanner = "Internal Speaker Mode • Plug in USB-C to 3.5mm for Auto +7.5 dB Amp Boost"
        }

        if !engine.isRunning {
            try? engine.start()
        }
    }

    // MARK: - AVAudioEngine 32-Bit Float DSP Graph
    private func setupAudioEngineGraph() {
        engine.attach(playerNode)
        engine.attach(parametricEQ)
        engine.attach(exciterEQ)
        engine.attach(peakLimiter)
        engine.attach(meterMixer)

        // Configure 10-band ISO Parametric EQ
        for i in 0..<10 {
            let band = parametricEQ.bands[i]
            band.frequency = EQPreset.frequencies[i]
            band.bandwidth = 1.0
            if i == 0 {
                band.filterType = .lowShelf
            } else if i == 9 {
                band.filterType = .highShelf
            } else {
                band.filterType = .parametric
            }
            band.gain = eqBands[i]
            band.bypass = false
        }

        // Configure 2-band Sony MegaBass & Super-Tweeter Brilliance Exciter
        let subBand = exciterEQ.bands[0]
        subBand.filterType = .lowShelf
        subBand.frequency = 65.0
        subBand.bandwidth = 0.8
        subBand.gain = megaBassDB
        subBand.bypass = false

        let airBand = exciterEQ.bands[1]
        airBand.filterType = .highShelf
        airBand.frequency = 12000.0
        airBand.bandwidth = 0.9
        airBand.gain = brillianceDB
        airBand.bypass = false

        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(playerNode, to: parametricEQ, format: format)
        engine.connect(parametricEQ, to: exciterEQ, format: format)
        engine.connect(exciterEQ, to: peakLimiter, format: format)
        engine.connect(peakLimiter, to: meterMixer, format: format)
        engine.connect(meterMixer, to: engine.mainMixerNode, format: format)

        installLevelMeterTap()
        updateDSPParameters()

        do {
            try engine.start()
        } catch {
            print("Failed to start AVAudioEngine: \(error)")
        }
    }

    func applyPreset(_ preset: EQPreset) {
        self.selectedPresetId = preset.id
        self.preampGainDB = preset.preampGainDB
        self.megaBassDB = preset.megaBassDB
        self.brillianceDB = preset.brillianceDB
        self.softLimiterEnabled = preset.softLimiterEnabled
        self.eqBands = preset.bands
        self.lineDriverActive = preset.preampGainDB > 0.5
        updateDSPParameters()
    }

    private func updateDSPParameters() {
        parametricEQ.bypass = dspBypassed
        exciterEQ.bypass = dspBypassed
        peakLimiter.bypass = dspBypassed || !softLimiterEnabled

        parametricEQ.globalGain = dspBypassed ? 0.0 : preampGainDB
        for i in 0..<min(10, eqBands.count) {
            parametricEQ.bands[i].gain = dspBypassed ? 0.0 : eqBands[i]
        }

        exciterEQ.bands[0].gain = dspBypassed ? 0.0 : megaBassDB
        exciterEQ.bands[1].gain = dspBypassed ? 0.0 : brillianceDB
    }

    /// Estimates equivalent output voltage into the Sony Amp RCA line-in based on the UK/EU 0.5Vrms USB-C cap + Preamp Boost
    var estimatedOutputVrms: Float {
        let baseVoltage: Float = 0.50 // UK/EU Apple USB-C dongle hardware cap (0.5 Vrms)
        let effectiveGain = dspBypassed ? 0.0 : preampGainDB
        let multiplier = powf(10.0, effectiveGain / 20.0)
        return min(2.1, baseVoltage * multiplier)
    }

    // MARK: - Real-Time Stereo VU Meter Tap
    private func installLevelMeterTap() {
        meterMixer.removeTap(onBus: 0)
        let format = meterMixer.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { return }

        meterMixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            let leftPtr = channelData[0]
            let rightPtr = buffer.format.channelCount > 1 ? channelData[1] : channelData[0]

            var sumL: Float = 0
            var sumR: Float = 0
            var peak: Float = 0

            for i in 0..<frameLength {
                let sL = abs(leftPtr[i])
                let sR = abs(rightPtr[i])
                sumL += sL * sL
                sumR += sR * sR
                if sL > peak { peak = sL }
                if sR > peak { peak = sR }
            }

            let rmsL = sqrt(sumL / Float(frameLength))
            let rmsR = sqrt(sumR / Float(frameLength))

            // Map -50 dBFS ... 0 dBFS to 0.0 ... 1.0 UI meter scale
            let dbL = 20.0 * log10(max(rmsL, 0.00001))
            let dbR = 20.0 * log10(max(rmsR, 0.00001))
            let normL = max(0.0, min(1.0, (dbL + 48.0) / 48.0))
            let normR = max(0.0, min(1.0, (dbR + 48.0) / 48.0))
            let isLimiting = peak >= 0.94

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isPlaying {
                    self.leftLevel = self.leftLevel * 0.4 + normL * 0.6
                    self.rightLevel = self.rightLevel * 0.4 + normR * 0.6
                    self.limiterEngaged = isLimiting && self.softLimiterEnabled
                } else {
                    self.leftLevel = 0.0
                    self.rightLevel = 0.0
                    self.limiterEngaged = false
                }
            }
        }
    }

    // MARK: - Playback & Queue Management
    func playQueue(items: [PlayableItem], startIndex: Int = 0) {
        guard !items.isEmpty, startIndex >= 0, startIndex < items.count else { return }
        self.queue = items
        self.currentIndex = startIndex
        Task {
            await loadAndPlay(item: items[startIndex])
        }
    }

    func loadAndPlay(item: PlayableItem) async {
        isLoadingTrack = true
        isTestTonePlaying = false
        currentTrack = item
        stopCurrentPlayback()

        do {
            let fileURL: URL
            if let local = item.localURL {
                fileURL = local
            } else if let track = item.subsonicTrack, let client = navidromeClient {
                statusBanner = "Streaming Bit-Perfect \(track.qualityBadge) from TrueNAS..."
                fileURL = try await client.downloadTrackForDSP(track: track)
            } else {
                isLoadingTrack = false
                return
            }

            let scoped = fileURL.startAccessingSecurityScopedResource()
            defer {
                if scoped { fileURL.stopAccessingSecurityScopedResource() }
            }

            let audioFile = try AVAudioFile(forReading: fileURL)
            self.currentAudioFile = audioFile
            self.totalFrames = audioFile.length
            self.fileSampleRate = audioFile.processingFormat.sampleRate
            self.duration = Double(totalFrames) / max(1.0, fileSampleRate)
            self.seekFrameOffset = 0
            self.currentTime = 0

            if !engine.isRunning {
                try engine.start()
            }

            scheduleCurrentFile(fromFrame: 0)
            playerNode.play()
            isPlaying = true
            isLoadingTrack = false
            evaluateCurrentAudioRoute(reason: "Track Started")
            startProgressTimer()
            updateNowPlayingInfo()
        } catch {
            isLoadingTrack = false
            statusBanner = "Playback Error: \(error.localizedDescription)"
        }
    }

    private func scheduleCurrentFile(fromFrame startFrame: AVAudioFramePosition) {
        guard let audioFile = currentAudioFile else { return }
        let remainingFrames = audioFile.length - startFrame
        guard remainingFrames > 0 else { return }

        scheduleGeneration += 1
        let expectedGen = scheduleGeneration

        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.scheduleGeneration == expectedGen else { return }
                if self.isPlaying && !self.isTestTonePlaying {
                    self.nextTrack()
                }
            }
        }
    }

    func playPause(forcePause: Bool = false) {
        if forcePause || isPlaying {
            playerNode.pause()
            isPlaying = false
            progressTimer?.invalidate()
        } else {
            if !engine.isRunning {
                try? engine.start()
            }
            if currentAudioFile != nil || isTestTonePlaying {
                playerNode.play()
                isPlaying = true
                startProgressTimer()
            }
        }
        updateNowPlayingInfo()
    }

    func seek(to seconds: TimeInterval) {
        guard let audioFile = currentAudioFile, !isTestTonePlaying else { return }
        let targetFrame = AVAudioFramePosition(max(0, min(seconds, duration)) * fileSampleRate)
        let wasPlaying = isPlaying

        scheduleGeneration += 1
        playerNode.stop()
        seekFrameOffset = targetFrame
        currentTime = seconds
        scheduleCurrentFile(fromFrame: targetFrame)
        if wasPlaying {
            playerNode.play()
        }
        updateNowPlayingInfo()
    }

    func nextTrack() {
        guard !queue.isEmpty else {
            stopCurrentPlayback()
            return
        }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            Task { await loadAndPlay(item: queue[currentIndex]) }
        } else {
            stopCurrentPlayback()
        }
    }

    func previousTrack() {
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty, currentIndex > 0 else {
            seek(to: 0)
            return
        }
        currentIndex -= 1
        Task { await loadAndPlay(item: queue[currentIndex]) }
    }

    func stopCurrentPlayback() {
        scheduleGeneration += 1
        playerNode.stop()
        isPlaying = false
        isTestTonePlaying = false
        leftLevel = 0
        rightLevel = 0
        progressTimer?.invalidate()
    }

    // MARK: - Built-in Sony Amp Line-Level Calibration Synthesizer
    func toggleCalibrationSignal(mode: String) {
        if isTestTonePlaying && currentTrack?.id == mode {
            stopCurrentPlayback()
            currentTrack = nil
            return
        }

        stopCurrentPlayback()
        if !engine.isRunning {
            try? engine.start()
        }

        let format = engine.outputNode.inputFormat(forBus: 0)
        let sr = Float(format.sampleRate > 0 ? format.sampleRate : 48000)
        let seconds: Float = 4.0
        let frameCount = AVAudioFrameCount(sr * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let channels = Int(format.channelCount)
        for frame in 0..<Int(frameCount) {
            let t = Float(frame) / sr
            var sample: Float = 0.0

            switch mode {
            case "cal_1khz":
                // Pure 1 kHz -10 dBFS line-level reference sine wave
                sample = 0.316 * sinf(2.0 * .pi * 1000.0 * t)
            case "cal_megabass":
                // Rhythmic 50 Hz + 100 Hz sub-bass pulse to test Sony Amp bass slam
                let env = 0.5 * (1.0 - cosf(2.0 * .pi * 1.5 * t))
                sample = 0.35 * env * (sinf(2.0 * .pi * 50.0 * t) + 0.6 * sinf(2.0 * .pi * 100.0 * t) + 0.25 * sinf(2.0 * .pi * 220.0 * t))
            default:
                // Full-spectrum warm harmonic chord (55Hz, 110Hz, 220Hz, 440Hz, 880Hz, 1760Hz, 3520Hz, 7040Hz)
                let freqs: [Float] = [55, 110, 165, 220, 330, 440, 880, 1760, 3520, 7040, 12000]
                for (idx, f) in freqs.enumerated() {
                    let amp = 0.18 / Float(idx + 1)
                    sample += amp * sinf(2.0 * .pi * f * t)
                }
            }

            for ch in 0..<channels {
                buffer.floatChannelData?[ch][frame] = sample
            }
        }

        let titleMap: [String: String] = [
            "cal_1khz": "1 kHz Line-Level Reference (2V Calibrator)",
            "cal_megabass": "50 Hz Sub-Bass Punch Test Loop",
            "cal_chord": "Full-Spectrum Hi-Fi Reference Chord"
        ]

        currentTrack = PlayableItem(
            id: mode,
            title: titleMap[mode] ?? "Sony Amp Reference Signal",
            artist: "Built-In 32-Bit DSP Signal Generator",
            album: "Sony Amp Calibration Suite",
            duration: Double(seconds),
            qualityBadge: "32-BIT FLOAT PCM • 48kHz",
            localURL: nil,
            subsonicTrack: nil
        )
        duration = Double(seconds)
        currentTime = 0
        isTestTonePlaying = true
        isPlaying = true

        playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        playerNode.play()
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPlaying, !self.isTestTonePlaying else { return }
                if let nodeTime = self.playerNode.lastRenderTime,
                   let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) {
                    let currentFrame = self.seekFrameOffset + playerTime.sampleTime
                    self.currentTime = min(self.duration, max(0, Double(currentFrame) / max(1.0, self.fileSampleRate)))
                }
            }
        }
    }

    // MARK: - Lock Screen & Control Center Integration
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPause(forcePause: false) }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPause(forcePause: true) }
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextTrack() }
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previousTrack() }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
