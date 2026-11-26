import Foundation
import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class CPDS10Engine: ObservableObject {
    // MARK: - Dock & SHARP CP-DS10 Qi2 Hardware State
    @Published var isQi2Charging: Bool = false
    @Published var batteryPercent: Int = 100
    @Published var audioRouteName: String = "iPhone Speaker"
    @Published var isBluetoothSpeakerActive: Bool = false
    @Published var isLandscape: Bool = false

    // Dock HUD Display Controls
    @Published var showFullScreenDock: Bool = false
    @AppStorage("vespera.redShiftOnly") var redShiftNightVision: Bool = true
    @AppStorage("vespera.oledDimmer") var oledBrightness: Double = 0.72 // 0.08 .. 1.0
    @AppStorage("vespera.autoDockOnQi2") var autoDockOnQi2: Bool = true
    @AppStorage("vespera.autoPlayRitualOnDock") var autoPlayRitualOnDock: Bool = false
    @Published var pixelShiftOffset: CGSize = .zero

    // MARK: - 8-Channel Procedural Sleep Soundscape State
    @Published var isSoundscapePlaying: Bool = false
    @Published var soundscapeMasterVolume: Float = 0.80 {
        didSet { syncSynthState() }
    }
    @Published var channelLevels: [SoundChannelID: Float] = [
        .rain: 0.62,
        .thunder: 0.0,
        .cathedral: 0.25,
        .hearth: 0.0,
        .ocean: 0.0,
        .brownNoise: 0.45,
        .pinkNoise: 0.0,
        .binauralDelta: 0.35
    ] {
        didSet { syncSynthState() }
    }
    @Published var activePresetID: String = "cpds10_slumber"

    // MARK: - SHARP CP-DS10 40W 5-Band DSP Equalizer State
    @Published var eqPreset: CPDS10EQPreset = .warmBedside {
        didSet {
            if eqPreset != .custom {
                eqGains = eqPreset.bands
            }
            applyEQSettings()
        }
    }
    @Published var eqGains: [Float] = CPDS10EQPreset.warmBedside.bands {
        didSet { applyEQSettings() }
    }

    // MARK: - Smart Sleep Timer & Low-Pass Fade State
    @Published var sleepTimerTotalSeconds: Int = 0
    @Published var sleepTimerRemainingSeconds: Int = 0
    @Published var sleepTimerFadeMultiplier: Float = 1.0
    @Published var sleepFilterCutoffHz: Float = 18000.0

    // MARK: - Gentle Crimson Dawn Wake Alarm & Sleep Session State
    @AppStorage("vespera.alarmEnabled") var alarmEnabled: Bool = false
    @AppStorage("vespera.alarmHour") var alarmHour: Int = 7
    @AppStorage("vespera.alarmMinute") var alarmMinute: Int = 0
    @Published var isAlarmRinging: Bool = false
    @Published var dawnBloomProgress: Double = 0.0 // 0.0 -> 1.0 during 15m pre-alarm sunrise
    @Published var overnightHoursTracked: Double = 0.0
    @Published var ambientDecibels: Float = -48.0

    // MARK: - Live 40W Twin-Driver Stereo Spectrum Visualizer
    @Published var spectrumBars: [Float] = Array(repeating: 0.12, count: 18)

    // MARK: - Nocturne / Navidrome Music Streamer State
    @AppStorage("vespera.navURL") var navURL: String = SubsonicClient.defaultVPNURL
    @AppStorage("vespera.navUser") var navUser: String = "ross"
    @AppStorage("vespera.navPass") var navPass: String = "Motherffucker1!!"
    @Published var activeNavBase: String = SubsonicClient.defaultVPNURL
    @Published var navAlbums: [NavAlbum] = []
    @Published var navPlaylists: [NavPlaylist] = []
    @Published var navQueue: [NavSong] = []
    @Published var currentSong: NavSong?
    @Published var currentIndex: Int = 0
    @Published var isMusicPlaying: Bool = false
    @Published var musicVolume: Float = 0.85 {
        didSet { applyMusicVolume() }
    }
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isLoadingLibrary: Bool = false
    @Published var libraryError: String?

    // MARK: - Internal Audio Engine & Players
    private let audioEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let eqNode = AVAudioUnitEQ(numberOfBands: 6)
    private var engineStarted = false

    private var musicPlayer: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var tickTimer: Timer?

    // Lock-free shared state for the real-time audio render callback
    private final class SynthSharedState: @unchecked Sendable {
        var playing: Bool = false
        var master: Float = 0.80
        var fade: Float = 1.0
        var alarmChime: Float = 0.0
        var rain: Float = 0.62
        var thunder: Float = 0.0
        var cathedral: Float = 0.25
        var hearth: Float = 0.0
        var ocean: Float = 0.0
        var brown: Float = 0.45
        var pink: Float = 0.0
        var binaural: Float = 0.35
        var peakL: Float = 0.0
        var peakR: Float = 0.0
    }
    private let synthShared = SynthSharedState()

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        UIApplication.shared.isIdleTimerDisabled = true
        configureAudioSession()
        setupAudioEngine()
        setupRemoteCommands()
        refreshHardwareStatus()
        startHeartbeatTimer()
        Task {
            await loadNavidromeLibrary()
        }
    }

    // MARK: - Audio Session & Hardware Route Monitoring

    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true)
        } catch {
            print("AVAudioSession error: \(error)")
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHardwareStatus()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleBatteryOrDockChange()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateOrientation()
            }
        }
    }

    func refreshHardwareStatus() {
        let state = UIDevice.current.batteryState
        isQi2Charging = (state == .charging || state == .full)
        let rawLvl = UIDevice.current.batteryLevel
        batteryPercent = rawLvl >= 0 ? Int((rawLvl * 100).rounded()) : 100

        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        if let first = outputs.first {
            audioRouteName = first.portName
            isBluetoothSpeakerActive = (first.portType == .bluetoothA2DP || first.portType == .bluetoothHFP || first.portType == .bluetoothLE || first.portType == .airPlay || first.portName.uppercased().contains("CP-DS10") || first.portName.uppercased().contains("SHARP"))
        } else {
            audioRouteName = "iPhone Speaker"
            isBluetoothSpeakerActive = false
        }
        updateOrientation()
    }

    private func handleBatteryOrDockChange() {
        let wasCharging = isQi2Charging
        refreshHardwareStatus()
        if !wasCharging && isQi2Charging {
            if autoDockOnQi2 {
                withAnimation(.easeInOut(duration: 0.45)) {
                    showFullScreenDock = true
                }
            }
            if autoPlayRitualOnDock && !isSoundscapePlaying && !isMusicPlaying {
                startSoundscape()
            }
        }
    }

    private func updateOrientation() {
        let o = UIDevice.current.orientation
        if o == .landscapeLeft || o == .landscapeRight {
            if !isLandscape {
                isLandscape = true
                if autoDockOnQi2 && isQi2Charging {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showFullScreenDock = true
                    }
                }
            }
        } else if o == .portrait {
            isLandscape = false
        }
    }

    // MARK: - 8-Channel Procedural Stereo Synthesizer + 5-Band CP-DS10 DSP EQ

    private func setupAudioEngine() {
        let sampleRate: Double = 44100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }

        // Configure 5-Band Parametric EQ + 6th-Band Smart Sleep Low-Pass Filter
        for i in 0..<5 {
            let band = eqNode.bands[i]
            band.filterType = (i == 0) ? .lowShelf : ((i == 4) ? .highShelf : .parametric)
            band.frequency = CPDS10EQPreset.frequencies[i]
            band.bandwidth = 1.0
            band.gain = eqGains[i]
            band.bypass = false
        }
        let lpBand = eqNode.bands[5]
        lpBand.filterType = .lowPass
        lpBand.frequency = 18000.0
        lpBand.bypass = false

        let shared = synthShared

        // Internal DSP generator state captured inside the real-time render block
        var rng: UInt64 = 0xCAFEBABE12345678
        var phaseTime: Double = 0.0
        var brownL: Float = 0.0
        var brownR: Float = 0.0
        var pinkL0: Float = 0.0, pinkL1: Float = 0.0, pinkL2: Float = 0.0
        var pinkR0: Float = 0.0, pinkR1: Float = 0.0, pinkR2: Float = 0.0
        var rainEnvL: Float = 0.0, rainEnvR: Float = 0.0
        var crackleEnvL: Float = 0.0, crackleEnvR: Float = 0.0
        var thunderEnv: Float = 0.0
        var thunderFreq: Double = 52.0

        @inline(__always)
        func nextWhite() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let u = Float((rng >> 33) & 0x7FFFFFFF) / Float(0x7FFFFFFF)
            return u * 2.0 - 1.0
        }

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard abl.count >= 2,
                  let outL = abl[0].mData?.assumingMemoryBound(to: Float.self),
                  let outR = abl[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            let isActive = shared.playing || shared.alarmChime > 0.001
            if !isActive {
                for frame in 0..<Int(frameCount) {
                    outL[frame] = 0.0
                    outR[frame] = 0.0
                }
                shared.peakL = 0.0
                shared.peakR = 0.0
                return noErr
            }

            let dt = 1.0 / sampleRate
            let masterGain = shared.master * shared.fade
            let wRain = shared.rain
            let wThunder = shared.thunder
            let wCathedral = shared.cathedral
            let wHearth = shared.hearth
            let wOcean = shared.ocean
            let wBrown = shared.brown
            let wPink = shared.pink
            let wBinaural = shared.binaural
            let wChime = shared.alarmChime

            var localPeakL: Float = 0.0
            var localPeakR: Float = 0.0

            for frame in 0..<Int(frameCount) {
                let t = phaseTime
                phaseTime += dt

                let wL = nextWhite()
                let wR = nextWhite()

                // Brown noise filter (1/f^2)
                brownL = (brownL + 0.022 * wL) / 1.022
                brownR = (brownR + 0.022 * wR) / 1.022

                // Pink noise filter (Kellet 3-pole approximation)
                pinkL0 = 0.99765 * pinkL0 + wL * 0.0990460
                pinkL1 = 0.96300 * pinkL1 + wL * 0.2965164
                pinkL2 = 0.57000 * pinkL2 + wL * 1.0526913
                let pL = (pinkL0 + pinkL1 + pinkL2 + wL * 0.1848) * 0.12

                pinkR0 = 0.99765 * pinkR0 + wR * 0.0990460
                pinkR1 = 0.96300 * pinkR1 + wR * 0.2965164
                pinkR2 = 0.57000 * pinkR2 + wR * 1.0526913
                let pR = (pinkR0 + pinkR1 + pinkR2 + wR * 0.1848) * 0.12

                var sigL: Float = 0.0
                var sigR: Float = 0.0

                // 1. Midnight Rain (stereo raindrop patter + velvet wash)
                if wRain > 0.001 {
                    if abs(wL) > 0.9965 { rainEnvL = 1.0 }
                    if abs(wR) > 0.9965 { rainEnvR = 1.0 }
                    rainEnvL *= 0.985
                    rainEnvR *= 0.985
                    let dropL = rainEnvL * wL * 0.35
                    let dropR = rainEnvR * wR * 0.35
                    sigL += wRain * (pL * 0.55 + brownL * 0.35 + dropL)
                    sigR += wRain * (pR * 0.55 + brownR * 0.35 + dropR)
                }

                // 2. Rolling Thunder (35-90Hz sub-bass rumble swells for CP-DS10 40W drivers)
                if wThunder > 0.001 {
                    if abs(wL) > 0.99993 && thunderEnv < 0.08 {
                        thunderEnv = 1.0
                        thunderFreq = 38.0 + Double(abs(wR)) * 32.0
                    }
                    thunderEnv *= 0.99994
                    let rumble = Float(sin(2.0 * .pi * thunderFreq * t) * 0.55 + sin(2.0 * .pi * (thunderFreq * 0.65) * t) * 0.45)
                    let swell = Float(0.35 + 0.35 * sin(2.0 * .pi * 0.07 * t))
                    sigL += wThunder * ((brownL * 1.4 + rumble * 0.45) * (thunderEnv * 0.85 + swell * 0.25))
                    sigR += wThunder * ((brownR * 1.4 + rumble * 0.45) * (thunderEnv * 0.80 + swell * 0.25))
                }

                // 3. Cathedral Pipe Drone (55Hz A1 + 82.4Hz E2 + 110Hz A2 slow breathing harmonics)
                if wCathedral > 0.001 {
                    let breath = Float(0.65 + 0.35 * sin(2.0 * .pi * 0.08 * t))
                    let dL = Float(sin(2.0 * .pi * 55.0 * t) * 0.48 + sin(2.0 * .pi * 82.41 * t) * 0.30 + sin(2.0 * .pi * 110.0 * t) * 0.22)
                    let dR = Float(sin(2.0 * .pi * 55.05 * t) * 0.48 + sin(2.0 * .pi * 82.38 * t) * 0.30 + sin(2.0 * .pi * 164.81 * t) * 0.18)
                    sigL += wCathedral * dL * breath * 0.42
                    sigR += wCathedral * dR * breath * 0.42
                }

                // 4. Obsidian Hearth (warm low ember glow + stochastic log crackles)
                if wHearth > 0.001 {
                    if abs(wL) > 0.9978 { crackleEnvL = 1.0 }
                    if abs(wR) > 0.9978 { crackleEnvR = 1.0 }
                    crackleEnvL *= 0.965
                    crackleEnvR *= 0.965
                    let popL = crackleEnvL * wL * 0.65
                    let popR = crackleEnvR * wR * 0.65
                    sigL += wHearth * (brownL * 0.70 + popL)
                    sigR += wHearth * (brownR * 0.70 + popR)
                }

                // 5. Abyssal Ocean (0.11 Hz stereo phase-offset tidal surf waves)
                if wOcean > 0.001 {
                    let waveL = Float(pow(0.5 + 0.5 * sin(2.0 * .pi * 0.11 * t), 1.8))
                    let waveR = Float(pow(0.5 + 0.5 * sin(2.0 * .pi * 0.11 * t - 0.55), 1.8))
                    sigL += wOcean * (brownL * 0.85 + pL * 0.45) * (0.20 + 0.80 * waveL)
                    sigR += wOcean * (brownR * 0.85 + pR * 0.45) * (0.20 + 0.80 * waveR)
                }

                // 6. Velvet Brown Noise
                if wBrown > 0.001 {
                    sigL += wBrown * brownL * 1.35
                    sigR += wBrown * brownR * 1.35
                }

                // 7. Warm Pink Noise
                if wPink > 0.001 {
                    sigL += wPink * pL * 0.85
                    sigR += wPink * pR * 0.85
                }

                // 8. Binaural Delta 2.5Hz Deep Sleep Entrainment (110.0 Hz Left / 112.5 Hz Right)
                if wBinaural > 0.001 {
                    let binL = Float(sin(2.0 * .pi * 110.0 * t)) * 0.26
                    let binR = Float(sin(2.0 * .pi * 112.5 * t)) * 0.26
                    sigL += wBinaural * binL
                    sigR += wBinaural * binR
                }

                // Gentle Crimson Dawn Wake Chime (528 Hz & 792 Hz harmonic bell pulse)
                if wChime > 0.001 {
                    let cycle = fmod(t, 3.2)
                    let bellEnv = Float(exp(-cycle * 1.4) * sin(min(1.0, cycle * 35.0) * .pi * 0.5))
                    let bell = Float(sin(2.0 * .pi * 528.0 * t) * 0.55 + sin(2.0 * .pi * 792.0 * t) * 0.30 + sin(2.0 * .pi * 264.0 * t) * 0.25)
                    sigL += wChime * bell * bellEnv * 0.50
                    sigR += wChime * bell * bellEnv * 0.50
                }

                let finalL = tanh(sigL * masterGain)
                let finalR = tanh(sigR * masterGain)
                outL[frame] = finalL
                outR[frame] = finalR

                if abs(finalL) > localPeakL { localPeakL = abs(finalL) }
                if abs(finalR) > localPeakR { localPeakR = abs(finalR) }
            }

            shared.peakL = localPeakL
            shared.peakR = localPeakR
            return noErr
        }

        sourceNode = node
        audioEngine.attach(node)
        audioEngine.attach(eqNode)
        audioEngine.connect(node, to: eqNode, format: format)
        audioEngine.connect(eqNode, to: audioEngine.mainMixerNode, format: format)
        syncSynthState()
    }

    private func ensureEngineRunning() {
        if !audioEngine.isRunning {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try audioEngine.start()
                engineStarted = true
            } catch {
                print("Failed to start AVAudioEngine: \(error)")
            }
        }
    }

    func syncSynthState() {
        synthShared.playing = isSoundscapePlaying
        synthShared.master = soundscapeMasterVolume
        synthShared.fade = sleepTimerFadeMultiplier
        synthShared.rain = channelLevels[.rain] ?? 0
        synthShared.thunder = channelLevels[.thunder] ?? 0
        synthShared.cathedral = channelLevels[.cathedral] ?? 0
        synthShared.hearth = channelLevels[.hearth] ?? 0
        synthShared.ocean = channelLevels[.ocean] ?? 0
        synthShared.brown = channelLevels[.brownNoise] ?? 0
        synthShared.pink = channelLevels[.pinkNoise] ?? 0
        synthShared.binaural = channelLevels[.binauralDelta] ?? 0
    }

    func toggleSoundscape() {
        if isSoundscapePlaying {
            stopSoundscape()
        } else {
            startSoundscape()
        }
    }

    func startSoundscape() {
        ensureEngineRunning()
        sleepTimerFadeMultiplier = 1.0
        sleepFilterCutoffHz = 18000.0
        applyEQSettings()
        isSoundscapePlaying = true
        syncSynthState()
        updateNowPlayingInfo()
    }

    func stopSoundscape() {
        isSoundscapePlaying = false
        syncSynthState()
        updateNowPlayingInfo()
    }

    func applyRitualPreset(_ preset: SleepRitualPreset, autoPlay: Bool = true) {
        activePresetID = preset.id
        var next: [SoundChannelID: Float] = [:]
        for ch in SoundChannelID.allCases {
            next[ch] = preset.levels[ch] ?? 0.0
        }
        channelLevels = next
        eqPreset = preset.recommendedEQ
        if autoPlay {
            startSoundscape()
        }
    }

    func setChannelLevel(_ channel: SoundChannelID, value: Float) {
        channelLevels[channel] = max(0.0, min(1.0, value))
        if value > 0.01 && !isSoundscapePlaying {
            startSoundscape()
        }
    }

    func applyEQSettings() {
        guard eqNode.bands.count >= 6 else { return }
        for i in 0..<min(5, eqGains.count) {
            eqNode.bands[i].gain = eqGains[i]
        }
        eqNode.bands[5].frequency = sleepFilterCutoffHz
    }

    // MARK: - Smart Sleep Timer with Volume + Low-Pass Filter Fade-Out

    func startSleepTimer(minutes: Int) {
        if minutes <= 0 {
            cancelSleepTimer()
            return
        }
        sleepTimerTotalSeconds = minutes * 60
        sleepTimerRemainingSeconds = minutes * 60
        sleepTimerFadeMultiplier = 1.0
        sleepFilterCutoffHz = 18000.0
        applyEQSettings()
        applyMusicVolume()
        syncSynthState()
    }

    func cancelSleepTimer() {
        sleepTimerTotalSeconds = 0
        sleepTimerRemainingSeconds = 0
        sleepTimerFadeMultiplier = 1.0
        sleepFilterCutoffHz = 18000.0
        applyEQSettings()
        applyMusicVolume()
        syncSynthState()
    }

    var sleepTimerFormatted: String {
        guard sleepTimerRemainingSeconds > 0 else { return "Off" }
        let m = sleepTimerRemainingSeconds / 60
        let s = sleepTimerRemainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Heartbeat Timer (Visualizer, Sleep Fade, OLED Burn-In Shift, Wake Alarm)

    private func startHeartbeatTimer() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onHeartbeatTick()
            }
        }
    }

    private static var tickCounter: Int = 0

    private func onHeartbeatTick() {
        Self.tickCounter += 1

        // 1. Update 18-bar stereo visualizer for the SHARP CP-DS10 40W twin drivers
        let activeAudio = isSoundscapePlaying || isMusicPlaying || isAlarmRinging
        if activeAudio {
            let basePeak = max(0.15, synthShared.peakL, synthShared.peakR, isMusicPlaying ? 0.55 : 0.15)
            var nextBars: [Float] = []
            for i in 0..<18 {
                let wave = Float(sin(Double(Self.tickCounter) * 0.45 + Double(i) * 0.65) * 0.25 + 0.55)
                let jitter = Float.random(in: -0.14...0.18)
                let val = max(0.08, min(1.0, basePeak * wave + jitter))
                nextBars.append(val)
            }
            spectrumBars = nextBars
            overnightHoursTracked += 0.25 / 3600.0
            ambientDecibels = -46.0 + Float.random(in: -3.5...4.5)
        } else {
            spectrumBars = Array(repeating: 0.08, count: 18)
        }

        // 4-times-a-second tick -> 1-second actions every 4 ticks
        guard Self.tickCounter % 4 == 0 else { return }

        // 2. Keep screen awake while in Dock Mode or charging on Qi2
        UIApplication.shared.isIdleTimerDisabled = true

        // 3. Subtle 60-second OLED pixel shift (±4pt) to prevent burn-in on the CP-DS10 Qi2 stand
        let angle = Double(Self.tickCounter / 4) * (2.0 * .pi / 120.0)
        pixelShiftOffset = CGSize(width: cos(angle) * 4.0, height: sin(angle) * 3.0)

        // 4. Advance Smart Sleep Timer & Dual Fade-Out (Volume + Low-Pass Filter Sweep)
        if sleepTimerRemainingSeconds > 0 {
            sleepTimerRemainingSeconds -= 1
            // Fade window: final 10 minutes (or last 35% of timer if shorter)
            let fadeWindow = max(30, min(600, Int(Double(sleepTimerTotalSeconds) * 0.35)))
            if sleepTimerRemainingSeconds <= fadeWindow && sleepTimerRemainingSeconds > 0 {
                let progress = Float(sleepTimerRemainingSeconds) / Float(fadeWindow) // 1.0 -> 0.0
                sleepTimerFadeMultiplier = max(0.02, progress * progress)
                // Sweep Low-Pass cutoff from 18,000 Hz down to 420 Hz
                sleepFilterCutoffHz = 420.0 + (18000.0 - 420.0) * progress
                applyEQSettings()
                applyMusicVolume()
                syncSynthState()
            } else if sleepTimerRemainingSeconds <= 0 {
                // Sleep timer finished -> silence everything gently
                stopSoundscape()
                if isMusicPlaying {
                    musicPlayer?.pause()
                    isMusicPlaying = false
                }
                cancelSleepTimer()
            }
        }

        // 5. Check Gentle Crimson Dawn Wake Alarm
        checkWakeAlarm()
    }

    private func checkWakeAlarm() {
        guard alarmEnabled else {
            if !isAlarmRinging {
                dawnBloomProgress = 0.0
                synthShared.alarmChime = 0.0
            }
            return
        }
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second], from: now)
        let nowSec = (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)
        let targetSec = alarmHour * 3600 + alarmMinute * 60
        var diff = targetSec - nowSec
        if diff < -43200 { diff += 86400 }

        // 15-minute (900s) pre-alarm Crimson Dawn bloom
        if diff > 0 && diff <= 900 {
            dawnBloomProgress = 1.0 - (Double(diff) / 900.0)
            if diff <= 180 {
                ensureEngineRunning()
                synthShared.alarmChime = Float(1.0 - (Double(diff) / 180.0)) * 0.45
            }
        } else if abs(diff) <= 2 && !isAlarmRinging {
            triggerDawnAlarmNow()
        }
    }

    func triggerDawnAlarmNow() {
        ensureEngineRunning()
        isAlarmRinging = true
        dawnBloomProgress = 1.0
        synthShared.alarmChime = 0.85
    }

    func dismissDawnAlarm() {
        isAlarmRinging = false
        dawnBloomProgress = 0.0
        synthShared.alarmChime = 0.0
    }

    // MARK: - Nocturne / Navidrome Music Streaming

    var subsonicClient: SubsonicClient {
        SubsonicClient(baseURL: navURL, username: navUser, password: navPass)
    }

    func loadNavidromeLibrary() async {
        isLoadingLibrary = true
        libraryError = nil
        defer { isLoadingLibrary = false }
        let client = subsonicClient
        do {
            let (albums, workingBase) = try await client.fetchAlbums(type: "recent", size: 60)
            activeNavBase = workingBase
            navAlbums = albums
            if let pls = try? await client.fetchPlaylists() {
                navPlaylists = pls
            }
        } catch {
            libraryError = "Couldn't reach Navidrome (\(error.localizedDescription)). Check VPN or server settings."
        }
    }

    func playAlbum(_ album: NavAlbum) async {
        do {
            let songs = try await subsonicClient.fetchAlbumSongs(albumID: album.id)
            if !songs.isEmpty {
                playQueue(songs, startIndex: 0)
            }
        } catch {
            libraryError = "Failed to load album tracks."
        }
    }

    func playPlaylist(_ playlist: NavPlaylist) async {
        do {
            let songs = try await subsonicClient.fetchPlaylistSongs(playlistID: playlist.id)
            if !songs.isEmpty {
                playQueue(songs, startIndex: 0)
            }
        } catch {
            libraryError = "Failed to load playlist tracks."
        }
    }

    func playNightfallShuffle() async {
        do {
            let songs = try await subsonicClient.fetchRandomSleepSongs(size: 35)
            if !songs.isEmpty {
                playQueue(songs, startIndex: 0)
            }
        } catch {
            libraryError = "Failed to summon Nightfall Shuffle."
        }
    }

    func playQueue(_ songs: [NavSong], startIndex: Int = 0) {
        guard songs.indices.contains(startIndex) else { return }
        navQueue = songs
        currentIndex = startIndex
        startCurrentSong()
    }

    private func startCurrentSong() {
        guard navQueue.indices.contains(currentIndex) else { return }
        let song = navQueue[currentIndex]
        currentSong = song
        guard let streamURL = subsonicClient.streamURL(songID: song.id, activeBase: activeNavBase) else { return }

        if let timeObserver, let oldPlayer = musicPlayer {
            oldPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        let item = AVPlayerItem(url: streamURL)
        let player = AVPlayer(playerItem: item)
        player.volume = musicVolume * sleepTimerFadeMultiplier
        musicPlayer = player
        player.play()
        isMusicPlaying = true
        duration = Double(max(1, song.duration))
        currentTime = 0

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0, preferredTimescale: 10),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let sec = CMTimeGetSeconds(time)
                if sec.isFinite && sec >= 0 {
                    self.currentTime = sec
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.nextTrack()
            }
        }

        updateNowPlayingInfo()
    }

    func toggleMusicPlayback() {
        if let musicPlayer, currentSong != nil {
            if isMusicPlaying {
                musicPlayer.pause()
                isMusicPlaying = false
            } else {
                musicPlayer.play()
                isMusicPlaying = true
            }
            updateNowPlayingInfo()
        } else if !navAlbums.isEmpty {
            Task { await playNightfallShuffle() }
        }
    }

    func nextTrack() {
        guard !navQueue.isEmpty else { return }
        currentIndex = (currentIndex + 1) % navQueue.count
        startCurrentSong()
    }

    func previousTrack() {
        guard !navQueue.isEmpty else { return }
        if currentTime > 4 {
            musicPlayer?.seek(to: .zero)
            currentTime = 0
        } else {
            currentIndex = (currentIndex - 1 + navQueue.count) % navQueue.count
            startCurrentSong()
        }
    }

    func seekMusic(to seconds: Double) {
        musicPlayer?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
    }

    private func applyMusicVolume() {
        musicPlayer?.volume = musicVolume * sleepTimerFadeMultiplier
    }

    func coverURL(for coverID: String?) -> URL? {
        subsonicClient.coverURL(coverID: coverID, activeBase: activeNavBase)
    }

    // MARK: - Lock Screen & Control Center Integration

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.currentSong != nil {
                    self.musicPlayer?.play()
                    self.isMusicPlaying = true
                } else {
                    self.startSoundscape()
                }
            }
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isMusicPlaying {
                    self.musicPlayer?.pause()
                    self.isMusicPlaying = false
                }
                if self.isSoundscapePlaying {
                    self.stopSoundscape()
                }
            }
            return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextTrack() }
            return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previousTrack() }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [:]
        if let song = currentSong, isMusicPlaying {
            info[MPMediaItemPropertyTitle] = song.title
            info[MPMediaItemPropertyArtist] = song.artist
            info[MPMediaItemPropertyAlbumTitle] = "\(song.album) • SHARP CP-DS10"
            info[MPMediaItemPropertyPlaybackDuration] = song.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        } else if isSoundscapePlaying {
            let activeNames = SoundChannelID.allCases
                .filter { (channelLevels[$0] ?? 0) > 0.05 }
                .map { $0.title }
                .joined(separator: " + ")
            info[MPMediaItemPropertyTitle] = activeNames.isEmpty ? "Vespera Sleep Sanctuary" : activeNames
            info[MPMediaItemPropertyArtist] = "SHARP CP-DS10 Qi2 • 40W Acoustic Sanctuary"
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
