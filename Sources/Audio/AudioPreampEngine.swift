import Foundation
import AVFoundation
import MediaPlayer
import Combine

enum PlaybackRepeatMode: String, CaseIterable {
    case off = "Off"
    case all = "Repeat All"
    case one = "Repeat One"

    var icon: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

struct PlayableItem: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let qualityBadge: String
    let localURL: URL?
    let subsonicTrack: SubsonicTrack?
    var youTubeVideoId: String? = nil
    var thumbnailURL: String? = nil
}

/// Real-time 32-bit Floating-Point Pre-Amp, 10-Band Parametric EQ, AirPods Pro 2 H2 Sounding Studio,
/// Spatial Room Reverb, and Peak Limiter Engine
@MainActor
final class AudioPreampEngine: ObservableObject {
    // MARK: - Published Hardware & Route State
    @Published var outputDeviceName: String = "iPhone Speaker"
    @Published var outputPortType: String = "Built-In"
    @Published var isUSBDACConnected: Bool = false
    @Published var isAirPodsProConnected: Bool = false
    @Published var isBluetoothAudioConnected: Bool = false
    @Published var activeProfileMode: PresetDeviceProfile = .sonyAmp
    @Published var autoEngageOnUSBDAC: Bool = true
    @Published var sampleRateHz: Double = 48000.0
    @Published var statusBanner: String = "Ready • Connect AirPods Pro 2 or USB-C Sony Amp"

    // MARK: - Published Pre-Amp & EQ State
    /// Pre-amp gain in dB (-6.0 dB to +12.0 dB). +7.5 dB lifts a 0.5Vrms UK/EU cap to ~1.2Vrms Sony line level.
    @Published var preampGainDB: Float = 7.5 {
        didSet { applyDSPParameters() }
    }
    /// Extra 65 Hz sub-bass harmonic shelf (0.0 to +8.0 dB)
    @Published var megaBassDB: Float = 3.5 {
        didSet { applyDSPParameters() }
    }
    /// Extra 12 kHz air/brilliance shelf (0.0 to +6.0 dB)
    @Published var brillianceDB: Float = 2.0 {
        didSet { applyDSPParameters() }
    }
    /// 10-band Parametric EQ gains (-12 dB to +12 dB)
    @Published var eqBands: [Float] = EQPreset.sonyPresets[0].bands {
        didSet { applyDSPParameters() }
    }
    @Published var softLimiterEnabled: Bool = true {
        didSet { applyDSPParameters() }
    }
    @Published var dspBypassed: Bool = false {
        didSet { applyDSPParameters() }
    }
    @Published var selectedPresetId: String = "sony_line_driver"

    // MARK: - Published AirPods Pro 2 H2 Sounding & Spatial Studio Controls
    /// 45 Hz H2 low-distortion sub-bass extension shelf (0.0 to +8.0 dB)
    @Published var airPodsSubBassDB: Float = 4.0 {
        didSet { applyDSPParameters() }
    }
    /// 3.2 kHz ear-canal pinna presence contour (-4.0 to +6.0 dB)
    @Published var airPodsVocalPresenceDB: Float = 2.0 {
        didSet { applyDSPParameters() }
    }
    /// 14 kHz DSEE-style AAC high-frequency harmonic air restoration (0.0 to +6.0 dB)
    @Published var airPodsSilkAirDB: Float = 3.5 {
        didSet { applyDSPParameters() }
    }
    /// Stereo soundstage width: 50% (Crossfeed/Intimate) ... 100% (Natural) ... 150% (Wide Concert Stage)
    @Published var stereoWidthPercent: Float = 115.0 {
        didSet { applyDSPParameters() }
    }
    /// Spatial room ambience wet/dry mix (0% to 45%)
    @Published var spatialReverbMix: Float = 6.0 {
        didSet { applyDSPParameters() }
    }
    /// Acoustic room model for Spatial Reverb
    @Published var spatialRoomStyle: SpatialRoomStyle = .studioBooth {
        didSet { applyDSPParameters() }
    }
    /// Left / Right ear trim balance (-1.0 Left ... 0.0 Center ... +1.0 Right)
    @Published var stereoBalance: Float = 0.0 {
        didSet { applyDSPParameters() }
    }
    /// Custom user-saved presets persisted in UserDefaults
    @Published var customPresets: [EQPreset] = []

    // MARK: - Published Playback & Transport State
    @Published var isPlaying: Bool = false
    @Published var isLoadingTrack: Bool = false
    @Published var currentTrack: PlayableItem?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var queue: [PlayableItem] = []
    @Published var currentQueueIndex: Int = -1
    @Published var isShuffleEnabled: Bool = false
    @Published var repeatMode: PlaybackRepeatMode = .off

    // MARK: - Live Stereo VU Meters, 12-Band Spectrum & Voltage Readout
    @Published var leftLevel: Float = 0.0
    @Published var rightLevel: Float = 0.0
    @Published var peakDBFS: Float = -60.0
    @Published var limiterEngaged: Bool = false
    @Published var spectrumBars: [Float] = Array(repeating: 0.05, count: 12)

    // MARK: - CoreAudio / AVAudioEngine Graph
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let inputMixer = AVAudioMixerNode()
    private let parametricEQ = AVAudioUnitEQ(numberOfBands: 10)
    private let exciterEQ = AVAudioUnitEQ(numberOfBands: 2)
    private let airPodsH2EQ = AVAudioUnitEQ(numberOfBands: 3)
    private let spatialReverb = AVAudioUnitReverb()
    private let peakLimiter = AVAudioUnitEffect(
        audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    )
    private let meterMixer = AVAudioMixerNode()

    private var currentAudioFile: AVAudioFile?
    private var seekFrameOffset: AVAudioFramePosition = 0
    private var totalFrames: AVAudioFramePosition = 0
    private var fileSampleRate: Double = 44100.0
    private var progressTimer: Timer?
    private var scheduleGeneration: Int = 0
    private var savedSonyPresetId: String = "sony_line_driver"
    private var savedAirPodsPresetId: String = "airpods_pro2_harman"
    private let customPresetsKey = "sony_dsp_custom_presets_v22"

    weak var navidromeClient: NavidromeClient?

    init() {
        loadCustomPresets()
        setupAudioSession()
        setupAudioGraph()
        setupRemoteTransportControls()
        observeRouteChanges()
        evaluateCurrentAudioRoute()
        applyDSPParameters()
        startProgressTimer()
    }

    // MARK: - Estimated Output Voltage (Vrms)
    /// UK/EU Apple USB-C dongle base output is ~0.50 Vrms at 0 dBFS.
    var estimatedOutputVrms: Float {
        let baseVrms: Float = 0.50
        let linearGain = powf(10.0, (dspBypassed ? 0.0 : preampGainDB) / 20.0)
        return min(baseVrms * linearGain, 2.10)
    }

    /// Estimated AirPods Pro 2 acoustic headroom / SPL character
    var estimatedAirPodsSPL: Float {
        let baseSPL: Float = 82.0
        let subContribution = airPodsSubBassDB * 0.45
        let gainContribution = preampGainDB * 0.65
        let meterBoost = ((leftLevel + rightLevel) * 0.5) * 14.0
        return min(102.0, max(60.0, baseSPL + subContribution + gainContribution + meterBoost))
    }

    // MARK: - 1. Audio Session & USB-C / AirPods Pro 2 Auto-Detection
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Note: .playback automatically supports Bluetooth A2DP & AirPlay; passing non-empty options
            // alongside policy: .longFormAudio throws OSStatus -50 (kAudio_ParamError) and breaks background audio!
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        } catch {
            try? session.setCategory(.playback, mode: .default, options: [])
        }
        try? session.setPreferredSampleRate(48000.0)
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true, options: [])
        sampleRateHz = session.sampleRate
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateCurrentAudioRoute()
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let typeVal = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optVal = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                if typeVal == AVAudioSession.InterruptionType.ended.rawValue {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self.startEngineIfNeeded()
                    if let optVal, AVAudioSession.InterruptionOptions(rawValue: optVal).contains(.shouldResume) {
                        self.playerNode.play()
                        self.isPlaying = true
                    }
                }
            }
        }
    }

    func evaluateCurrentAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        sampleRateHz = session.sampleRate

        guard let output = session.currentRoute.outputs.first else {
            outputDeviceName = "No Output"
            outputPortType = "None"
            isUSBDACConnected = false
            isAirPodsProConnected = false
            isBluetoothAudioConnected = false
            return
        }

        outputDeviceName = output.portName
        let portNameLower = output.portName.lowercased()

        switch output.portType {
        case .usbAudio:
            outputPortType = "USB-C DAC / AUX"
            isUSBDACConnected = true
            isAirPodsProConnected = false
            isBluetoothAudioConnected = false
        case .headphones, .lineOut:
            outputPortType = "3.5mm Line-Out"
            isUSBDACConnected = true
            isAirPodsProConnected = false
            isBluetoothAudioConnected = false
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            isUSBDACConnected = false
            isBluetoothAudioConnected = true
            if portNameLower.contains("airpods") || portNameLower.contains("beats") {
                outputPortType = "AirPods Pro 2 • H2 DSP"
                isAirPodsProConnected = true
            } else {
                outputPortType = "Bluetooth Hi-Fi Audio"
                isAirPodsProConnected = true
            }
        case .airPlay:
            outputPortType = "AirPlay Lossless"
            isUSBDACConnected = false
            isAirPodsProConnected = false
            isBluetoothAudioConnected = false
        default:
            outputPortType = "iPhone Speaker"
            isUSBDACConnected = false
            isAirPodsProConnected = false
            isBluetoothAudioConnected = false
        }

        if isAirPodsProConnected {
            // Only auto-apply the profile preset when the device profile actually
            // changes. Route-change notifications fire frequently while AirPods are
            // connected (single-bud use, AAC renegotiation); re-applying the preset
            // each time silently reverts the user's manual slider adjustments.
            if activeProfileMode != .airPodsPro2 {
                activeProfileMode = .airPodsPro2
                if let preset = allPresets.first(where: { $0.id == savedAirPodsPresetId }) ?? EQPreset.airPodsPro2Presets.first {
                    applyPreset(preset, updateSavedSelection: false)
                }
            }
            statusBanner = "AirPods Pro 2 Active (\(output.portName)) • H2 Sub-Bass & Spatial DSP Engaged"
        } else if isUSBDACConnected {
            if activeProfileMode != .sonyAmp {
                activeProfileMode = .sonyAmp
                if autoEngageOnUSBDAC {
                    if let preset = allPresets.first(where: { $0.id == savedSonyPresetId }) ?? EQPreset.sonyPresets.first {
                        applyPreset(preset, updateSavedSelection: false)
                    }
                }
            }
            statusBanner = "USB-C Line-Out Active (\(output.portName)) • Sony ES Line-Driver Engaged"
        } else {
            statusBanner = "Route: \(output.portName) • Tap AirPods Pro 2 or Sony ES Mode below"
        }
    }

    func switchProfileMode(_ mode: PresetDeviceProfile) {
        activeProfileMode = mode
        switch mode {
        case .airPodsPro2:
            if let preset = allPresets.first(where: { $0.id == savedAirPodsPresetId }) ?? EQPreset.airPodsPro2Presets.first {
                applyPreset(preset)
            }
            statusBanner = "AirPods Pro 2 H2 Sounding Studio Active • 45Hz Sub-Bass + 3.2kHz Pinna + 14kHz DSEE Air"
        case .sonyAmp:
            if let preset = allPresets.first(where: { $0.id == savedSonyPresetId }) ?? EQPreset.sonyPresets.first {
                applyPreset(preset)
            }
            statusBanner = "Sony ES Line-Driver Active • +\(String(format: "%.1f", preampGainDB)) dB (\(String(format: "%.2f", estimatedOutputVrms)) Vrms)"
        case .custom:
            if let preset = customPresets.first {
                applyPreset(preset)
            }
        }
    }

    // MARK: - 2. Build 32-Bit Float AVAudioEngine Graph
    private func setupAudioGraph() {
        engine.attach(playerNode)
        engine.attach(inputMixer)
        engine.attach(parametricEQ)
        engine.attach(exciterEQ)
        engine.attach(airPodsH2EQ)
        engine.attach(spatialReverb)
        engine.attach(peakLimiter)
        engine.attach(meterMixer)

        // Configure 10-band ISO Parametric EQ
        for (index, freq) in EQPreset.frequencies.enumerated() {
            let band = parametricEQ.bands[index]
            if index == 0 {
                band.filterType = .lowShelf
            } else if index == EQPreset.frequencies.count - 1 {
                band.filterType = .highShelf
            } else {
                band.filterType = .parametric
            }
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = eqBands[index]
            band.bypass = false
        }

        // Configure 2-band Sony MegaBass (65 Hz) & Super-Tweeter Brilliance (12 kHz)
        let bassBand = exciterEQ.bands[0]
        bassBand.filterType = .lowShelf
        bassBand.frequency = 65.0
        bassBand.bandwidth = 0.9
        bassBand.gain = megaBassDB
        bassBand.bypass = false

        let airBand = exciterEQ.bands[1]
        airBand.filterType = .highShelf
        airBand.frequency = 12000.0
        airBand.bandwidth = 0.9
        airBand.gain = brillianceDB
        airBand.bypass = false

        // Configure 3-band AirPods Pro 2 H2 Custom Sounding Stage:
        // Band 0: 45 Hz H2 Sub-Bass Driver Extension Shelf
        let h2SubBand = airPodsH2EQ.bands[0]
        h2SubBand.filterType = .lowShelf
        h2SubBand.frequency = 45.0
        h2SubBand.bandwidth = 0.85
        h2SubBand.gain = airPodsSubBassDB
        h2SubBand.bypass = false

        // Band 1: 3.2 kHz Ear-Canal Pinna Vocal Presence Sculptor
        let h2PinnaBand = airPodsH2EQ.bands[1]
        h2PinnaBand.filterType = .parametric
        h2PinnaBand.frequency = 3200.0
        h2PinnaBand.bandwidth = 1.1
        h2PinnaBand.gain = airPodsVocalPresenceDB
        h2PinnaBand.bypass = false

        // Band 2: 14 kHz DSEE AAC High-Frequency Silk Air Restoration
        let h2SilkBand = airPodsH2EQ.bands[2]
        h2SilkBand.filterType = .highShelf
        h2SilkBand.frequency = 14000.0
        h2SilkBand.bandwidth = 0.8
        h2SilkBand.gain = airPodsSilkAirDB
        h2SilkBand.bypass = false

        // Configure Spatial Room Reverb
        spatialReverb.loadFactoryPreset(spatialRoomStyle.avPreset)
        spatialReverb.wetDryMix = spatialReverbMix

        // Apple's PeakLimiter defaults use a 24 ms release, which combined with a
        // hot pre-amp constantly pumps and produces a harsh, compressed ("tinny")
        // character. Use a much longer release and a transparent attack instead.
        if let limiterTree = peakLimiter.auAudioUnit.parameterTree {
            limiterTree.parameter(withAddress: 0)?.value = 0.003   // attackTime (s)
            limiterTree.parameter(withAddress: 1)?.value = 0.25    // decayTime (s), default 0.024
            limiterTree.parameter(withAddress: 2)?.value = 0.0     // preGain (dB)
        }

        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: inputMixer, format: format)
        engine.connect(inputMixer, to: parametricEQ, format: format)
        engine.connect(parametricEQ, to: exciterEQ, format: format)
        engine.connect(exciterEQ, to: airPodsH2EQ, format: format)
        engine.connect(airPodsH2EQ, to: spatialReverb, format: format)
        engine.connect(spatialReverb, to: peakLimiter, format: format)
        engine.connect(peakLimiter, to: meterMixer, format: format)
        engine.connect(meterMixer, to: engine.mainMixerNode, format: format)

        installLevelMeterTap()
        startEngineIfNeeded()
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            statusBanner = "Engine start error: \(error.localizedDescription)"
        }
    }

    // MARK: - 3. Apply Pre-Amp Gain, 10-Band EQ, AirPods Pro 2 H2 & Spatial Parameters
    func applyDSPParameters() {
        playerNode.pan = max(-1.0, min(1.0, stereoBalance))

        if dspBypassed {
            parametricEQ.bypass = true
            exciterEQ.bypass = true
            airPodsH2EQ.bypass = true
            spatialReverb.wetDryMix = 0.0
            peakLimiter.bypass = true
            parametricEQ.globalGain = 0.0
            inputMixer.outputVolume = 1.0
            return
        }

        parametricEQ.bypass = false
        exciterEQ.bypass = false
        airPodsH2EQ.bypass = false
        peakLimiter.bypass = !softLimiterEnabled

        // Stereo width compensation and preamp headroom
        let widthFactor = max(0.5, min(1.5, stereoWidthPercent / 100.0))
        let widthTrimDB: Float = widthFactor > 1.15 ? (widthFactor - 1.0) * 1.8 : 0.0

        // Apply main Pre-Amp boost (-6 dB to +12 dB)
        parametricEQ.globalGain = max(-12.0, min(15.0, preampGainDB + widthTrimDB))
        inputMixer.outputVolume = 1.0

        for i in 0..<min(10, eqBands.count) {
            // Subtle Mid-Side / Stage presence curve adjustment when stereo width is expanded or crossfed
            var bandGain = eqBands[i]
            if widthFactor > 1.05 && (i == 6 || i == 7 || i == 8) {
                bandGain += (widthFactor - 1.0) * 2.2
            } else if widthFactor < 0.95 && (i == 7 || i == 8) {
                bandGain -= (1.0 - widthFactor) * 1.5
            }
            parametricEQ.bands[i].gain = max(-12.0, min(12.0, bandGain))
            parametricEQ.bands[i].bypass = false
        }

        exciterEQ.bands[0].gain = megaBassDB
        exciterEQ.bands[1].gain = brillianceDB

        airPodsH2EQ.bands[0].gain = airPodsSubBassDB
        airPodsH2EQ.bands[1].gain = airPodsVocalPresenceDB
        airPodsH2EQ.bands[2].gain = airPodsSilkAirDB

        spatialReverb.loadFactoryPreset(spatialRoomStyle.avPreset)
        spatialReverb.wetDryMix = max(0.0, min(45.0, spatialReverbMix))
    }

    var allPresets: [EQPreset] {
        EQPreset.builtInPresets + customPresets
    }

    func applyPreset(_ preset: EQPreset, updateSavedSelection: Bool = true) {
        selectedPresetId = preset.id
        if updateSavedSelection {
            if preset.targetProfile == .airPodsPro2 {
                savedAirPodsPresetId = preset.id
            } else if preset.targetProfile == .sonyAmp {
                savedSonyPresetId = preset.id
            }
        }
        preampGainDB = preset.preampGainDB
        megaBassDB = preset.megaBassDB
        brillianceDB = preset.brillianceDB
        eqBands = preset.bands
        airPodsSubBassDB = preset.airPodsSubBassDB
        airPodsVocalPresenceDB = preset.airPodsVocalPresenceDB
        airPodsSilkAirDB = preset.airPodsSilkAirDB
        stereoWidthPercent = preset.stereoWidthPercent
        spatialReverbMix = preset.spatialReverbMix
        spatialRoomStyle = preset.spatialRoomStyle
        applyDSPParameters()
    }

    // MARK: - Custom User Presets Persistence
    func saveCurrentAsCustomPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = EQPreset(
            id: "custom_\( Int(Date().timeIntervalSince1970) )",
            name: trimmed,
            subtitle: activeProfileMode == .airPodsPro2 ? "Custom AirPods Pro 2 Sounding" : "Custom Sony ES Line-Driver",
            icon: activeProfileMode == .airPodsPro2 ? "airpodspro" : "slider.horizontal.3",
            targetProfile: .custom,
            preampGainDB: preampGainDB,
            megaBassDB: megaBassDB,
            brillianceDB: brillianceDB,
            bands: eqBands,
            airPodsSubBassDB: airPodsSubBassDB,
            airPodsVocalPresenceDB: airPodsVocalPresenceDB,
            airPodsSilkAirDB: airPodsSilkAirDB,
            stereoWidthPercent: stereoWidthPercent,
            spatialReverbMix: spatialReverbMix,
            spatialRoomStyle: spatialRoomStyle
        )
        customPresets.insert(preset, at: 0)
        selectedPresetId = preset.id
        persistCustomPresets()
        statusBanner = "Saved Custom Preset: \"\(trimmed)\""
    }

    func deleteCustomPreset(id: String) {
        customPresets.removeAll { $0.id == id }
        persistCustomPresets()
    }

    private func persistCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: customPresetsKey)
        }
    }

    private func loadCustomPresets() {
        guard let data = UserDefaults.standard.data(forKey: customPresetsKey),
              let decoded = try? JSONDecoder().decode([EQPreset].self, from: data) else {
            return
        }
        customPresets = decoded
    }

    // MARK: - 4. Real-Time Stereo VU Meter & 12-Band Spectrum Tap
    private func installLevelMeterTap() {
        let format = meterMixer.outputFormat(forBus: 0)
        meterMixer.removeTap(onBus: 0)
        meterMixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            let channelCount = Int(buffer.format.channelCount)

            var sumL: Float = 0
            var sumR: Float = 0
            var peak: Float = 0

            let leftPtr = channelData[0]
            let rightPtr = channelCount > 1 ? channelData[1] : channelData[0]

            let strideStep = max(1, frameLength / 256)
            var count: Float = 0
            for i in stride(from: 0, to: frameLength, by: strideStep) {
                let sL = leftPtr[i]
                let sR = rightPtr[i]
                sumL += sL * sL
                sumR += sR * sR
                let absMax = max(abs(sL), abs(sR))
                if absMax > peak { peak = absMax }
                count += 1
            }

            let rmsL = sqrtf(sumL / max(1, count))
            let rmsR = sqrtf(sumR / max(1, count))
            let dbPeak = 20.0 * log10f(max(peak, 0.00001))

            let normL = max(0.0, min(1.0, (20.0 * log10f(max(rmsL, 0.0001)) + 50.0) / 50.0))
            let normR = max(0.0, min(1.0, (20.0 * log10f(max(rmsR, 0.0001)) + 50.0) / 50.0))
            let avgEnergy = (normL + normR) * 0.5

            // Compute 12-band animated spectral energy bars shaped by the active EQ + H2 Sub-Bass & Silk Air
            var bars = [Float](repeating: 0.05, count: 12)
            let chunkSize = max(1, frameLength / 12)
            for b in 0..<12 {
                let start = min(frameLength - 1, b * chunkSize)
                var bandEnergy: Float = 0
                let samplesToRead = min(16, frameLength - start)
                for k in 0..<samplesToRead {
                    let s = leftPtr[start + k]
                    let prev = (start + k > 0) ? leftPtr[start + k - 1] : s
                    // Weight low bands toward smooth amplitude, high bands toward zero-crossing / diff energy
                    let highWeight = Float(b) / 11.0
                    let component = (1.0 - highWeight) * abs(s) + highWeight * abs(s - prev) * 2.2
                    bandEnergy += component
                }
                bandEnergy /= Float(max(1, samplesToRead))
                let visualLevel = min(1.0, max(0.06, avgEnergy * 0.55 + sqrtf(bandEnergy) * 0.85))
                bars[b] = visualLevel
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.leftLevel = self.leftLevel * 0.55 + normL * 0.45
                self.rightLevel = self.rightLevel * 0.55 + normR * 0.45
                self.peakDBFS = dbPeak
                self.limiterEngaged = dbPeak > -1.2
                for i in 0..<12 {
                    self.spectrumBars[i] = self.spectrumBars[i] * 0.5 + bars[i] * 0.5
                }
            }
        }
    }

    // MARK: - 5. Built-In Sony Amp & AirPods Pro 2 Calibration Signal Generator
    func toggleCalibrationSignal(mode: String) {
        if isPlaying && currentTrack?.id == mode {
            stop()
            return
        }

        let title: String
        switch mode {
        case "cal_megabass":
            title = "Sony 50Hz MegaBass Sub-Harmonic Test"
        case "cal_1khz":
            title = "1 kHz 0 dBFS Line-Level Reference (2.0V Check)"
        case "cal_airpods_spatial":
            title = "AirPods Pro 2 H2 45Hz Sub + 3D Soundstage Test"
        default:
            title = "Sony ES Warm Stereo Mastering Chord"
        }

        do {
            let url = try buildCalibrationWAV(mode: mode, durationSeconds: 12.0)
            let item = PlayableItem(
                id: mode,
                title: title,
                artist: activeProfileMode == .airPodsPro2 ? "AirPods Pro 2 H2 Studio Generator" : "Sony ES Signal Generator",
                album: "Built-In Hardware Verification",
                duration: 12.0,
                qualityBadge: "48kHz / 32-BIT DSP",
                localURL: url,
                subsonicTrack: nil
            )
            playQueue(items: [item], startIndex: 0)
        } catch {
            statusBanner = "Generator error: \(error.localizedDescription)"
        }
    }

    private func buildCalibrationWAV(mode: String, durationSeconds: Double) throws -> URL {
        let sr = 48000.0
        let totalSamples = Int(sr * durationSeconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples)) else {
            throw NSError(domain: "SonyPreamp", code: -1, userInfo: [NSLocalizedDescriptionKey: "Buffer alloc failed"])
        }
        buffer.frameLength = AVAudioFrameCount(totalSamples)

        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for i in 0..<totalSamples {
            let t = Double(i) / sr
            let env = min(1.0, t / 0.15) * min(1.0, (durationSeconds - t) / 0.25)

            switch mode {
            case "cal_megabass":
                let pulse = 0.5 + 0.5 * sin(2.0 * .pi * 1.5 * t)
                let sub = 0.55 * sin(2.0 * .pi * 50.0 * t) * pulse
                let punch = 0.20 * sin(2.0 * .pi * 100.0 * t) * pulse
                let air = 0.08 * sin(2.0 * .pi * 440.0 * t)
                left[i] = Float((sub + punch + air) * env)
                right[i] = Float((sub + punch + air * 0.95) * env)

            case "cal_1khz":
                let s = 0.707 * sin(2.0 * .pi * 1000.0 * t) * env
                left[i] = Float(s)
                right[i] = Float(s)

            case "cal_airpods_spatial":
                // 45 Hz H2 sub-bass foundation + panning stereo harmonic arpeggio (3.2 kHz & 14 kHz overtones)
                let sub45 = 0.45 * sin(2.0 * .pi * 45.0 * t) * (0.65 + 0.35 * sin(2.0 * .pi * 1.0 * t))
                let panOsc = sin(2.0 * .pi * 0.35 * t) // Smooth L <-> R spatial sweep
                let leftGain = 0.5 * (1.0 - panOsc * 0.75)
                let rightGain = 0.5 * (1.0 + panOsc * 0.75)
                let vocalPinna = 0.22 * sin(2.0 * .pi * 440.0 * t) + 0.14 * sin(2.0 * .pi * 3200.0 * t)
                let silkShimmer = 0.08 * sin(2.0 * .pi * 12500.0 * t) * (0.5 + 0.5 * cos(2.0 * .pi * 2.5 * t))
                left[i] = Float((sub45 + (vocalPinna + silkShimmer) * leftGain) * env)
                right[i] = Float((sub45 + (vocalPinna + silkShimmer) * rightGain) * env)

            default:
                let bass = 0.35 * sin(2.0 * .pi * 55.0 * t) * (0.6 + 0.4 * sin(2.0 * .pi * 2.0 * t))
                let n1 = 0.18 * sin(2.0 * .pi * 220.0 * t)
                let n2 = 0.15 * sin(2.0 * .pi * 277.18 * t)
                let n3 = 0.14 * sin(2.0 * .pi * 329.63 * t)
                let n4 = 0.10 * sin(2.0 * .pi * 415.30 * t)
                let shimmer = 0.05 * sin(2.0 * .pi * 659.25 * t)
                left[i] = Float((bass + n1 + n2 + n3 + shimmer) * env)
                right[i] = Float((bass + n1 + n3 + n4 + shimmer) * env)
            }
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(mode).wav")
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        let outFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try outFile.write(from: buffer)
        return tempURL
    }

    // MARK: - 6. Queue & Track Playback (Local Files + Navidrome Lossless + YouTube Native DSP Streams)
    func playQueue(items: [PlayableItem], startIndex: Int = 0) {
        guard !items.isEmpty, startIndex >= 0, startIndex < items.count else { return }
        queue = items
        currentQueueIndex = startIndex
        loadAndPlay(item: items[startIndex])
    }

    /// Inserts a track immediately after the currently playing song without interrupting playback
    func playNext(_ item: PlayableItem) {
        if queue.isEmpty || currentTrack == nil {
            playQueue(items: [item], startIndex: 0)
            return
        }
        let insertIdx = min(queue.count, max(0, currentQueueIndex + 1))
        queue.insert(item, at: insertIdx)
        statusBanner = "Up Next: \(item.title)"
        prebufferYouTubeIfNeeded(item)
    }

    /// Appends a track to the end of the active playback queue without interrupting playback
    func appendToQueue(_ item: PlayableItem) {
        if queue.isEmpty || currentTrack == nil {
            playQueue(items: [item], startIndex: 0)
            return
        }
        queue.append(item)
        statusBanner = "Added to Queue (#\(queue.count)): \(item.title)"
        if queue.count == currentQueueIndex + 2 {
            prebufferYouTubeIfNeeded(item)
        }
    }

    private func youTubeCacheURL(for videoId: String) -> URL {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("YouTubeDSPCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir.appendingPathComponent("yt_\(videoId).m4a")
    }

    func downloadYouTubeTrackForDSP(videoId: String) async throws -> URL {
        let localURL = youTubeCacheURL(for: videoId)
        if FileManager.default.fileExists(atPath: localURL.path),
           let sz = try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           sz > 4096 {
            return localURL
        }
        guard let streamURL = URL(string: "https://navidrome.nas-server.co.uk/sidestore-api/yt-stream?v=\(videoId)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: streamURL)
        req.timeoutInterval = 60
        let (tempURL, resp) = try await URLSession.shared.download(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "YouTubeDSP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        return localURL
    }

    func prebufferYouTubeIfNeeded(_ item: PlayableItem) {
        guard let vid = item.youTubeVideoId else { return }
        Task.detached(priority: .utility) {
            let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("YouTubeDSPCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let localURL = cacheDir.appendingPathComponent("yt_\(vid).m4a")
            if FileManager.default.fileExists(atPath: localURL.path) { return }
            guard let streamURL = URL(string: "https://navidrome.nas-server.co.uk/sidestore-api/yt-stream?v=\(vid)") else { return }
            var req = URLRequest(url: streamURL)
            req.timeoutInterval = 60
            if let (tempURL, resp) = try? await URLSession.shared.download(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200 {
                try? FileManager.default.removeItem(at: localURL)
                try? FileManager.default.moveItem(at: tempURL, to: localURL)
            }
        }
    }

    func loadAndPlay(item: PlayableItem) {
        currentTrack = item
        isLoadingTrack = true

        if let localURL = item.localURL, FileManager.default.fileExists(atPath: localURL.path) {
            playLocalFile(url: localURL, item: item)
            return
        }

        if let localURL = item.localURL {
            let scoped = localURL.startAccessingSecurityScopedResource()
            defer {
                if scoped { localURL.stopAccessingSecurityScopedResource() }
            }
            let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent(localURL.lastPathComponent)
            try? FileManager.default.removeItem(at: tempCopy)
            if (try? FileManager.default.copyItem(at: localURL, to: tempCopy)) != nil {
                playLocalFile(url: tempCopy, item: item)
                return
            }
        }

        if let ytId = item.youTubeVideoId {
            let cached = youTubeCacheURL(for: ytId)
            if FileManager.default.fileExists(atPath: cached.path),
               let sz = try? cached.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               sz > 4096 {
                playLocalFile(url: cached, item: item)
                return
            }
            statusBanner = "Extracting Ad-Free YouTube Audio (\(item.title)) into 32-Bit DSP..."
            let reqGen = scheduleGeneration + 1
            Task {
                do {
                    let downloadedURL = try await downloadYouTubeTrackForDSP(videoId: ytId)
                    await MainActor.run {
                        guard self.currentTrack?.id == item.id || self.scheduleGeneration < reqGen else { return }
                        self.playLocalFile(url: downloadedURL, item: item)
                    }
                } catch {
                    await MainActor.run {
                        self.isLoadingTrack = false
                        self.statusBanner = "YouTube stream error: \(error.localizedDescription)"
                    }
                }
            }
            return
        }

        if let subTrack = item.subsonicTrack, let client = navidromeClient {
            statusBanner = "Buffering \(subTrack.title) (\(subTrack.qualityBadge)) from TrueNAS..."
            Task {
                do {
                    let cachedURL = try await client.downloadTrackForDSP(track: subTrack)
                    await MainActor.run {
                        self.playLocalFile(url: cachedURL, item: item)
                    }
                } catch {
                    await MainActor.run {
                        self.isLoadingTrack = false
                        self.statusBanner = "Stream error: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            isLoadingTrack = false
            statusBanner = "Unable to resolve audio source for \(item.title)"
        }
    }

    private func playLocalFile(url: URL, item: PlayableItem) {
        do {
            setupAudioSession()
            startEngineIfNeeded()

            let audioFile = try AVAudioFile(forReading: url)
            currentAudioFile = audioFile
            totalFrames = audioFile.length
            fileSampleRate = audioFile.processingFormat.sampleRate
            duration = Double(totalFrames) / max(1.0, fileSampleRate)
            seekFrameOffset = 0
            currentTime = 0

            scheduleGeneration += 1
            let gen = scheduleGeneration

            playerNode.stop()
            playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.scheduleGeneration == gen else { return }
                    self.handleTrackFinished()
                }
            }
            applyDSPParameters()
            playerNode.play()
            isPlaying = true
            isLoadingTrack = false
            if activeProfileMode == .airPodsPro2 {
                statusBanner = "Playing: \(item.title) • AirPods Pro 2 H2 DSP (+\(String(format: "%.1f", airPodsSubBassDB))dB Sub)"
            } else {
                statusBanner = "Playing: \(item.title) • +\(String(format: "%.1f", preampGainDB)) dB (\(String(format: "%.2f", estimatedOutputVrms)) Vrms)"
            }
            updateNowPlayingMetadata()
            if currentQueueIndex + 1 < queue.count {
                prebufferYouTubeIfNeeded(queue[currentQueueIndex + 1])
            }
        } catch {
            isLoadingTrack = false
            statusBanner = "Decode error: \(error.localizedDescription)"
        }
    }

    func playPause() {
        guard currentAudioFile != nil else {
            if let first = queue.first {
                loadAndPlay(item: first)
            } else {
                toggleCalibrationSignal(mode: activeProfileMode == .airPodsPro2 ? "cal_airpods_spatial" : "cal_chord")
            }
            return
        }
        startEngineIfNeeded()
        if isPlaying {
            playerNode.pause()
            isPlaying = false
        } else {
            playerNode.play()
            isPlaying = true
        }
        updateNowPlayingMetadata()
    }

    func stop() {
        scheduleGeneration += 1
        playerNode.stop()
        isPlaying = false
        currentTime = 0
        seekFrameOffset = 0
        leftLevel = 0
        rightLevel = 0
    }

    func seek(to seconds: TimeInterval) {
        guard let file = currentAudioFile else { return }
        let clamped = max(0, min(seconds, duration - 0.1))
        let targetFrame = AVAudioFramePosition(clamped * fileSampleRate)
        let remainingFrames = AVAudioFrameCount(max(0, totalFrames - targetFrame))
        guard remainingFrames > 100 else { return }

        scheduleGeneration += 1
        let gen = scheduleGeneration
        let wasPlaying = isPlaying

        playerNode.stop()
        seekFrameOffset = targetFrame
        currentTime = clamped

        playerNode.scheduleSegment(
            file,
            startingFrame: targetFrame,
            frameCount: remainingFrames,
            at: nil
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.scheduleGeneration == gen else { return }
                self.handleTrackFinished()
            }
        }

        if wasPlaying {
            playerNode.play()
            isPlaying = true
        }
        updateNowPlayingMetadata()
    }

    func toggleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func nextTrack() {
        guard !queue.isEmpty else { return }
        if isShuffleEnabled && queue.count > 1 {
            var randomIdx = Int.random(in: 0..<queue.count)
            if randomIdx == currentQueueIndex {
                randomIdx = (currentQueueIndex + 1) % queue.count
            }
            currentQueueIndex = randomIdx
            loadAndPlay(item: queue[currentQueueIndex])
            return
        }
        if currentQueueIndex + 1 < queue.count {
            currentQueueIndex += 1
            loadAndPlay(item: queue[currentQueueIndex])
        } else if repeatMode == .all {
            currentQueueIndex = 0
            loadAndPlay(item: queue[0])
        }
    }

    func previousTrack() {
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty, currentQueueIndex - 1 >= 0 else {
            seek(to: 0)
            return
        }
        currentQueueIndex -= 1
        loadAndPlay(item: queue[currentQueueIndex])
    }

    private func handleTrackFinished() {
        if repeatMode == .one, let current = currentTrack {
            loadAndPlay(item: current)
            return
        }
        if isShuffleEnabled && queue.count > 1 {
            nextTrack()
            return
        }
        if currentQueueIndex + 1 < queue.count {
            currentQueueIndex += 1
            loadAndPlay(item: queue[currentQueueIndex])
        } else if repeatMode == .all, !queue.isEmpty {
            currentQueueIndex = 0
            loadAndPlay(item: queue[0])
        } else {
            isPlaying = false
            currentTime = 0
            leftLevel = 0
            rightLevel = 0
        }
    }

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                if let nodeTime = self.playerNode.lastRenderTime,
                   let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) {
                    let currentFrame = self.seekFrameOffset + playerTime.sampleTime
                    let sec = Double(currentFrame) / max(1.0, self.fileSampleRate)
                    self.currentTime = max(0, min(self.duration, sec))
                }
            }
        }
    }

    // MARK: - 7. iOS Lock Screen & Control Center Integration
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPause() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPause() }
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

    private func updateNowPlayingMetadata() {
        guard let track = currentTrack else { return }
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.artist
        info[MPMediaItemPropertyAlbumTitle] = track.album
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
