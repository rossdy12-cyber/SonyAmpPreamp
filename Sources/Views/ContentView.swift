import SwiftUI
import AVKit
import UniformTypeIdentifiers

/// Native iOS AirPlay / Bluetooth / AirPods Pro 2 Route Picker
struct AudioRoutePickerButton: UIViewRepresentable {
    let tintColor: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = tintColor
        picker.activeTintColor = .systemGreen
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
    }
}

struct ContentView: View {
    @StateObject private var navidrome = NavidromeClient()
    @StateObject private var dspEngine = AudioPreampEngine()
    @StateObject private var acqClient = AcquisitionClient()
    @State private var selectedTab: Int = 0
    @State private var showFileImporter: Bool = false

    private let goldAccent = GothicTheme.bloodHi
    private let panelBg = GothicTheme.crypt
    private let deepBg = GothicTheme.void

    var body: some View {
        ZStack {
            deepBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Hardware USB-C DAC & AirPods Pro 2 Status Bar
                hardwareHeaderBar

                TabView(selection: $selectedTab) {
                    PreampRackView(dsp: dspEngine, goldAccent: goldAccent, panelBg: panelBg)
                        .tabItem {
                            Label(dspEngine.activeProfileMode == .airPodsPro2 ? "AirPods DSP" : "Sony DSP", systemImage: dspEngine.activeProfileMode == .airPodsPro2 ? "airpodspro" : "slider.vertical.3")
                        }
                        .tag(0)

                    YouTubeDSPView(dsp: dspEngine, goldAccent: goldAccent, panelBg: panelBg)
                        .tabItem {
                            Label("YouTube+ DSP", systemImage: "play.rectangle.fill")
                        }
                        .tag(1)

                    NavidromeLibraryView(navidrome: navidrome, dsp: dspEngine, goldAccent: goldAccent, panelBg: panelBg)
                        .tabItem {
                            Label("TrueNAS Hi-Fi", systemImage: "server.rack")
                        }
                        .tag(2)

                    SoulSeekrView(acq: acqClient, goldAccent: goldAccent, panelBg: panelBg)
                        .tabItem {
                            Label("SoulSeekr", systemImage: "arrow.down.doc.fill")
                        }
                        .tag(3)

                    LocalAndQueueView(navidrome: navidrome, dsp: dspEngine, showFileImporter: $showFileImporter, goldAccent: goldAccent, panelBg: panelBg)
                        .tabItem {
                            Label("Offline & Queue", systemImage: "arrow.down.circle.fill")
                        }
                        .tag(4)
                }
                .tint(goldAccent)

                if dspEngine.currentTrack != nil {
                    miniPlayerBar
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            dspEngine.navidromeClient = navidrome
            if !navidrome.isConnected {
                Task { await navidrome.pingAndLoadLibrary() }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .mp3, .wav, .aiff, .mpeg4Audio, UTType(filenameExtension: "flac") ?? .audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let items: [PlayableItem] = urls.map { url in
                    PlayableItem(
                        id: url.absoluteString,
                        title: url.deletingPathExtension().lastPathComponent,
                        artist: "Local Hi-Res File",
                        album: "iPhone Storage",
                        duration: 0,
                        qualityBadge: url.pathExtension.uppercased(),
                        localURL: url,
                        subsonicTrack: nil
                    )
                }
                if !items.isEmpty {
                    dspEngine.playQueue(items: items, startIndex: 0)
                }
            }
        }
    }

    private var hardwareHeaderBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: dspEngine.isAirPodsProConnected || dspEngine.activeProfileMode == .airPodsPro2 ? "airpodspro" : (dspEngine.isUSBDACConnected ? "cable.connector.horizontal" : "iphone.gen3"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor((dspEngine.isUSBDACConnected || dspEngine.isAirPodsProConnected) ? .white : goldAccent)
                    .padding(7)
                    .background((dspEngine.isUSBDACConnected || dspEngine.isAirPodsProConnected) ? goldAccent : Color.white.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(dspEngine.activeProfileMode == .airPodsPro2 ? "AIRPODS PRO 2 H2 DSP" : "SONY ES PRE-AMP")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(goldAccent)
                        Text("•")
                            .foregroundColor(.gray)
                        Text(String(format: "%.1f kHz 32-Bit", dspEngine.sampleRateHz / 1000.0))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Text(dspEngine.statusBanner)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor((dspEngine.isUSBDACConnected || dspEngine.isAirPodsProConnected) ? .green : .white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer()

                // Native iOS Route Picker for AirPods Pro 2 / USB-C / AirPlay
                AudioRoutePickerButton(tintColor: UIColor(goldAccent))
                    .frame(width: 28, height: 28)

                Button {
                    dspEngine.dspBypassed.toggle()
                } label: {
                    Text(dspEngine.dspBypassed ? "BYPASS" : "DSP ON")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(dspEngine.dspBypassed ? Color.gray.opacity(0.55) : goldAccent)
                        .cornerRadius(6)
                }
            }

            if selectedTab == 0 {
                // Instant Output Acoustic Mode Switcher: Sony ES Pre-Amp vs AirPods Pro 2 H2 Studio
                HStack(spacing: 8) {
                    Button {
                        dspEngine.switchProfileMode(.sonyAmp)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "hifispeaker.2.fill")
                                .font(.system(size: 11))
                            Text("Sony ES Line-Driver")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(dspEngine.activeProfileMode == .sonyAmp ? .black : .white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(dspEngine.activeProfileMode == .sonyAmp ? goldAccent : Color.white.opacity(0.08))
                        .cornerRadius(7)
                    }

                    Button {
                        dspEngine.switchProfileMode(.airPodsPro2)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "airpodspro")
                                .font(.system(size: 11))
                            Text("AirPods Pro 2 Sounding")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(dspEngine.activeProfileMode == .airPodsPro2 ? .black : .white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(dspEngine.activeProfileMode == .airPodsPro2 ? goldAccent : Color.white.opacity(0.08))
                        .cornerRadius(7)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(panelBg)
    }

    private func formatTime(_ sec: TimeInterval) -> String {
        guard sec.isFinite && sec > 0 else { return "0:00" }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d", m, s)
    }

    private var miniPlayerBar: some View {
        VStack(spacing: 5) {
            if let track = dspEngine.currentTrack {
                // Scrubbable progress bar + time labels
                HStack(spacing: 8) {
                    Text(formatTime(dspEngine.currentTime))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.gray)
                    Slider(
                        value: Binding(
                            get: { dspEngine.currentTime },
                            set: { dspEngine.seek(to: $0) }
                        ),
                        in: 0...max(1, dspEngine.duration)
                    )
                    .tint(goldAccent)
                    Text(formatTime(dspEngine.duration))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 14)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(track.artist)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                            Text(track.qualityBadge)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(goldAccent)
                                .cornerRadius(4)
                        }
                    }

                    Spacer()

                    Button {
                        dspEngine.isShuffleEnabled.toggle()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(dspEngine.isShuffleEnabled ? goldAccent : .gray)
                    }

                    Button { dspEngine.previousTrack() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                    }

                    Button { dspEngine.playPause() } label: {
                        Image(systemName: dspEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(goldAccent)
                    }

                    Button { dspEngine.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                    }

                    Button {
                        dspEngine.toggleRepeatMode()
                    } label: {
                        Image(systemName: dspEngine.repeatMode.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(dspEngine.repeatMode == .off ? .gray : goldAccent)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 6)
        .background(GothicTheme.sepulchre)
    }
}

// MARK: - TAB 1: SONY AMP PRE-AMP, AIRPODS PRO 2 H2 STUDIO & 10-BAND EQ RACK
struct PreampRackView: View {
    @ObservedObject var dsp: AudioPreampEngine
    let goldAccent: Color
    let panelBg: Color

    @State private var showSavePresetPrompt: Bool = false
    @State private var customPresetName: String = ""
    @State private var showSystemWideH2Sheet: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Live Stereo VU Meters, 12-Band Spectrum Analyzer & Voltage/SPL Estimator
                vuMeterAndVoltageCard

                // 2. Dedicated AirPods Pro 2 H2 Sounding & 3D Spatial Studio (shown first in AirPods Mode, or below in Sony Mode)
                if dsp.activeProfileMode == .airPodsPro2 {
                    airPodsPro2SoundingCard
                    presetsSection
                    tenBandEQCard
                    preampLineDriverCard
                } else {
                    preampLineDriverCard
                    presetsSection
                    airPodsPro2SoundingCard
                    tenBandEQCard
                }

                // 5. Instant Sony Amp & AirPods Pro 2 Calibration Generator
                calibrationGeneratorCard
            }
            .padding(14)
        }
        .alert("Save Custom DSP Preset", isPresented: $showSavePresetPrompt) {
            TextField("Preset Name (e.g. Ross AirPods Bass+)", text: $customPresetName)
            Button("Cancel", role: .cancel) { customPresetName = "" }
            Button("Save") {
                dsp.saveCurrentAsCustomPreset(name: customPresetName)
                customPresetName = ""
            }
        } message: {
            Text("Saves your current 10-band EQ, AirPods Pro 2 H2 sounding, stereo width, and preamp settings.")
        }
    }

    private var vuMeterAndVoltageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    dsp.activeProfileMode == .airPodsPro2 ? "H2 SPECTRUM & ACOUSTIC METER" : "LINE-OUT LEVEL & VU METER",
                    systemImage: "waveform.path.ecg.rectangle"
                )
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(goldAccent)

                Spacer()

                if dsp.activeProfileMode == .airPodsPro2 {
                    Text(String(format: "EST. HEADROOM: %.0f dB SPL", dsp.estimatedAirPodsSPL))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green)
                        .cornerRadius(4)
                } else {
                    Text(String(format: "EST. OUTPUT: %.2f Vrms", dsp.estimatedOutputVrms))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(dsp.estimatedOutputVrms >= 1.1 ? Color.green : goldAccent)
                        .cornerRadius(4)
                }
            }

            // Left / Right Bar Meters
            VStack(spacing: 6) {
                channelMeterRow(label: "L", level: dsp.leftLevel)
                channelMeterRow(label: "R", level: dsp.rightLevel)
            }

            // 12-Band Real-Time Spectrum Visualizer
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<dsp.spectrumBars.count, id: \.self) { idx in
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [goldAccent.opacity(0.65), goldAccent, .green],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(height: max(3, geo.size.height * CGFloat(dsp.spectrumBars[idx])))
                        }
                    }
                }
            }
            .frame(height: 34)
            .padding(.top, 2)

            HStack {
                Text(dsp.activeProfileMode == .airPodsPro2 ? "Route: \(dsp.outputDeviceName) • Stage: \(Int(dsp.stereoWidthPercent))%" : "UK/EU USB-C Cap: 0.50 Vrms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(dsp.limiterEngaged ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                    Text(dsp.softLimiterEnabled ? (dsp.limiterEngaged ? "PEAK LIMITER: PROTECTING" : "BRICKWALL LIMITER: ARMED") : "LIMITER OFF")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(dsp.limiterEngaged ? .orange : .green)
                }
            }
        }
        .padding(14)
        .background(panelBg)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(goldAccent.opacity(0.25), lineWidth: 1)
        )
    }

    private func channelMeterRow(label: String, level: Float) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(goldAccent)
                .frame(width: 14)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.6))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * CGFloat(level)))
                }
            }
            .frame(height: 11)
        }
    }

    // MARK: - AirPods Pro 2 H2 Sounding & 3D Spatial Mastering Card
    private var airPodsPro2SoundingCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("AIRPODS PRO 2 H2 SOUNDING & SPATIAL STUDIO", systemImage: "airpodspro")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(goldAccent)
                Spacer()
                Button("Harman Reset") {
                    if let harman = EQPreset.airPodsPro2Presets.first {
                        dsp.applyPreset(harman)
                    }
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(goldAccent)
            }

            // 1. 45 Hz H2 Sub-Bass Extension
            VStack(spacing: 4) {
                HStack {
                    Text("H2 Deep Sub-Bass Extension (45 Hz Low-Distortion Shelf)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                    Spacer()
                    Text(String(format: "%+.1f dB", dsp.airPodsSubBassDB))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(goldAccent)
                }
                Slider(value: $dsp.airPodsSubBassDB, in: 0.0...8.0, step: 0.5)
                    .tint(goldAccent)
            }

            // 2. 3.2 kHz Ear-Canal Pinna Vocal Presence Contour
            VStack(spacing: 4) {
                HStack {
                    Text("Ear-Canal Vocal & Pinna Presence (3.2 kHz Contour)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                    Spacer()
                    Text(String(format: "%+.1f dB", dsp.airPodsVocalPresenceDB))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(goldAccent)
                }
                Slider(value: $dsp.airPodsVocalPresenceDB, in: -4.0...6.0, step: 0.5)
                    .tint(goldAccent)
            }

            // 3. 14 kHz DSEE Harmonic Silk Air Restoration
            VStack(spacing: 4) {
                HStack {
                    Text("DSEE Extreme AAC Silk Air & Sparkle (14 kHz Shelf)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                    Spacer()
                    Text(String(format: "%+.1f dB", dsp.airPodsSilkAirDB))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(goldAccent)
                }
                Slider(value: $dsp.airPodsSilkAirDB, in: 0.0...6.0, step: 0.5)
                    .tint(goldAccent)
            }

            Divider().background(Color.white.opacity(0.15))

            // 4. Stereo Soundstage Widener & Crossfeed (50% - 150%)
            VStack(spacing: 4) {
                HStack {
                    Text("3D Stereo Soundstage Width (Crossfeed ↔ Wide Stage)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                    Spacer()
                    Text(String(format: "%.0f%%", dsp.stereoWidthPercent))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(goldAccent)
                }
                Slider(value: $dsp.stereoWidthPercent, in: 50.0...150.0, step: 5.0)
                    .tint(goldAccent)
            }

            // 5. Spatial Room Acoustics Wet/Dry + Room Model Selector
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Spatial Room Ambience (\(dsp.spatialRoomStyle.title))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                    Spacer()
                    Text(String(format: "%.0f%% Wet", dsp.spatialReverbMix))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(goldAccent)
                }
                Slider(value: $dsp.spatialReverbMix, in: 0.0...45.0, step: 1.0)
                    .tint(goldAccent)

                HStack(spacing: 6) {
                    ForEach(SpatialRoomStyle.allCases) { style in
                        let active = dsp.spatialRoomStyle == style
                        Button {
                            dsp.spatialRoomStyle = style
                        } label: {
                            Text(style.title)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(active ? .black : .white)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(active ? goldAccent : Color.white.opacity(0.08))
                                .cornerRadius(5)
                        }
                    }
                }
            }

            // 6. Left / Right Ear Trim Balance
            VStack(spacing: 4) {
                HStack {
                    Text("L / R Ear Balance Trim")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    if abs(dsp.stereoBalance) > 0.02 {
                        Button("Center") { dsp.stereoBalance = 0.0 }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(goldAccent)
                    }
                    Text(abs(dsp.stereoBalance) < 0.03 ? "CENTER" : (dsp.stereoBalance < 0 ? String(format: "L %.0f%%", abs(dsp.stereoBalance) * 100) : String(format: "R %.0f%%", dsp.stereoBalance * 100)))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(goldAccent)
                }
                Slider(value: $dsp.stereoBalance, in: -0.5...0.5, step: 0.02)
                    .tint(goldAccent)
            }

            Button {
                showSystemWideH2Sheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "airpodspro")
                    Text("Export Preset to iOS System-Wide AirPods H2 EQ")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(goldAccent)
                .cornerRadius(8)
            }
            .sheet(isPresented: $showSystemWideH2Sheet) {
                AirPodsSystemWideEQSheet(dsp: dsp, goldAccent: goldAccent, panelBg: panelBg)
            }
        }
        .padding(14)
        .background(panelBg)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(dsp.activeProfileMode == .airPodsPro2 ? goldAccent.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }

    private var preampLineDriverCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("SONY AMP LINE-DRIVER GAIN", systemImage: "dial.high.fill")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(goldAccent)
                Spacer()
                Toggle("Auto on USB-C", isOn: $dsp.autoEngageOnUSBDAC)
                    .labelsHidden()
                Text("Auto USB-C")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }

            // Main Pre-Amp Gain Slider (-6dB to +12dB)
            VStack(spacing: 4) {
                HStack {
                    Text("Pre-Amp Voltage / Headroom Gain")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%+.1f dB (%.2f Vrms)", dsp.preampGainDB, dsp.estimatedOutputVrms))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(goldAccent)
                }
                Slider(value: $dsp.preampGainDB, in: -6.0...12.0, step: 0.5)
                    .tint(goldAccent)

                // Quick Gain Step Buttons
                HStack(spacing: 6) {
                    ForEach([
                        ("0dB (0.5V)", Float(0.0)),
                        ("+1.5dB (H2)", Float(1.5)),
                        ("+6dB (1.0V)", Float(6.0)),
                        ("+7.5dB (Sony)", Float(7.5)),
                        ("+12dB (2.0V)", Float(12.0))
                    ], id: \.0) { label, val in
                        Button {
                            dsp.preampGainDB = val
                        } label: {
                            Text(label)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(abs(dsp.preampGainDB - val) < 0.3 ? .black : .white)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(abs(dsp.preampGainDB - val) < 0.3 ? goldAccent : Color.white.opacity(0.08))
                                .cornerRadius(5)
                        }
                    }
                }
            }

            Divider().background(Color.white.opacity(0.15))

            // Sony MegaBass 65Hz Exciter
            VStack(spacing: 4) {
                HStack {
                    Text("Sony MegaBass (65 Hz Upper-Sub Punch Shelf)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(String(format: "%+.1f dB", dsp.megaBassDB))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(goldAccent)
                }
                Slider(value: $dsp.megaBassDB, in: 0.0...8.0, step: 0.5)
                    .tint(goldAccent)
            }

            // Super-Tweeter 12kHz Brilliance
            VStack(spacing: 4) {
                HStack {
                    Text("Super-Tweeter Air (12 kHz Brilliance Shelf)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Text(String(format: "%+.1f dB", dsp.brillianceDB))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(goldAccent)
                }
                Slider(value: $dsp.brillianceDB, in: 0.0...6.0, step: 0.5)
                    .tint(goldAccent)
            }

            Toggle(isOn: $dsp.softLimiterEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CoreAudio Studio Brickwall Peak Limiter")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Prevents 0 dBFS digital clipping on heavy bass transients")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .tint(goldAccent)
        }
        .padding(14)
        .background(panelBg)
        .cornerRadius(12)
    }

    private var presetsSection: some View {
        let activePresets = dsp.activeProfileMode == .airPodsPro2 ? EQPreset.airPodsPro2Presets : EQPreset.sonyPresets

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    dsp.activeProfileMode == .airPodsPro2 ? "AIRPODS PRO 2 ACOUSTIC PRESETS" : "SONY AMP ACOUSTIC PRESETS",
                    systemImage: dsp.activeProfileMode == .airPodsPro2 ? "airpodspro" : "sparkles"
                )
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(goldAccent)

                Spacer()

                Button {
                    showSavePresetPrompt = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Save Custom")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(goldAccent)
                    .cornerRadius(6)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(activePresets) { preset in
                    presetCardButton(preset: preset, isCustom: false)
                }
            }

            if !dsp.customPresets.isEmpty {
                Divider().background(Color.white.opacity(0.15))
                Text("YOUR SAVED CUSTOM PRESETS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(goldAccent)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(dsp.customPresets) { preset in
                        presetCardButton(preset: preset, isCustom: true)
                    }
                }
            }
        }
        .padding(14)
        .background(panelBg)
        .cornerRadius(12)
    }

    private func presetCardButton(preset: EQPreset, isCustom: Bool) -> some View {
        let isSelected = dsp.selectedPresetId == preset.id
        return Button {
            dsp.applyPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: preset.icon)
                        .foregroundColor(isSelected ? .black : goldAccent)
                    Spacer()
                    if isCustom {
                        Button {
                            dsp.deleteCustomPreset(id: preset.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(isSelected ? .black : .red.opacity(0.85))
                        }
                    } else {
                        Text(preset.targetProfile == .airPodsPro2 ? String(format: "+%.1fdB Sub", preset.airPodsSubBassDB) : String(format: "%+.1fdB", preset.preampGainDB))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(isSelected ? .black.opacity(0.8) : goldAccent)
                    }
                }
                Text(preset.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isSelected ? .black : .white)
                    .lineLimit(1)
                Text(preset.subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .black.opacity(0.75) : .gray)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? goldAccent : Color.white.opacity(0.06))
            .cornerRadius(10)
        }
    }

    private var tenBandEQCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("10-BAND PARAMETRIC EQUALIZER", systemImage: "slider.vertical.3")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(goldAccent)
                Spacer()
                Button("Reset Flat") {
                    dsp.eqBands = Array(repeating: 0.0, count: 10)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(goldAccent)
            }

            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<10, id: \.self) { idx in
                    VStack(spacing: 6) {
                        Text(String(format: "%+.0f", dsp.eqBands[idx]))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(dsp.eqBands[idx] > 0 ? goldAccent : .gray)

                        GeometryReader { geo in
                            let height = geo.size.height
                            let norm = CGFloat((dsp.eqBands[idx] + 12.0) / 24.0)
                            ZStack(alignment: .bottom) {
                                Capsule()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: 8)
                                Capsule()
                                    .fill(goldAccent)
                                    .frame(width: 8, height: max(6, height * norm))
                            }
                            .frame(maxWidth: .infinity)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let ratio = Float(1.0 - min(max(0, value.location.y / height), 1.0))
                                        let db = (ratio * 24.0) - 12.0
                                        dsp.eqBands[idx] = (db * 2.0).rounded() / 2.0
                                    }
                            )
                        }
                        .frame(height: 130)

                        Text(EQPreset.frequencyLabels[idx])
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(panelBg)
        .cornerRadius(12)
    }

    private var calibrationGeneratorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("INSTANT SOUND CHECK & SPATIAL CALIBRATION", systemImage: "waveform.badge.magnifyingglass")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(goldAccent)

            Text("Test your AirPods Pro 2 45Hz H2 sub-bass & 3D stereo stage or Sony Amp 2V line-driver immediately:")
                .font(.system(size: 11))
                .foregroundColor(.gray)

            HStack(spacing: 6) {
                calButton(title: "AirPods 3D Test", mode: "cal_airpods_spatial", icon: "airpodspro")
                calButton(title: "50Hz Bass Pulse", mode: "cal_megabass", icon: "speaker.wave.3.fill")
                calButton(title: "Hi-Fi EQ Chord", mode: "cal_chord", icon: "pianokeys")
                calButton(title: "1kHz 2V Ref", mode: "cal_1khz", icon: "waveform")
            }
        }
        .padding(14)
        .background(panelBg)
        .cornerRadius(12)
    }

    private func calButton(title: String, mode: String, icon: String) -> some View {
        let active = dsp.isPlaying && dsp.currentTrack?.id == mode
        return Button {
            dsp.toggleCalibrationSignal(mode: mode)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: active ? "stop.circle.fill" : icon)
                    .font(.system(size: 15))
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundColor(active ? .black : .white)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(active ? goldAccent : Color.white.opacity(0.08))
            .cornerRadius(8)
        }
    }
}

// MARK: - TAB 2: TRUENAS NAVIDROME FLAC LIBRARY
struct NavidromeLibraryView: View {
    @ObservedObject var navidrome: NavidromeClient
    @ObservedObject var dsp: AudioPreampEngine
    let goldAccent: Color
    let panelBg: Color

    @State private var searchQuery: String = ""
    @State private var selectedArtist: SubsonicArtist?
    @State private var artistAlbums: [SubsonicAlbum] = []
    @State private var selectedAlbum: SubsonicAlbum?
    @State private var albumTracks: [SubsonicTrack] = []
    @State private var showServerConfig: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Server Connection Card
                    serverStatusCard

                    if navidrome.isConnected {
                        // Search Bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("Search 18,800+ FLAC tracks on TrueNAS...", text: $searchQuery)
                                .textInputAutocapitalization(.never)
                                .onSubmit {
                                    Task { await navidrome.search(query: searchQuery) }
                                }
                            if !searchQuery.isEmpty {
                                Button {
                                    searchQuery = ""
                                    navidrome.searchTracks = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(10)
                        .background(panelBg)
                        .cornerRadius(10)

                        if !navidrome.searchTracks.isEmpty {
                            trackListSection(title: "SEARCH RESULTS", tracks: navidrome.searchTracks)
                        }

                        if let album = selectedAlbum {
                            albumDetailSection(album: album)
                        } else if let artist = selectedArtist {
                            artistAlbumsSection(artist: artist)
                        } else {
                            if !navidrome.recentAlbums.isEmpty {
                                featuredAlbumsCarousel
                            }
                            artistsListSection
                        }
                    }
                }
                .padding(14)
            }
            .background(GothicTheme.void)
            .navigationTitle("TrueNAS Lossless")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var serverStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: navidrome.isConnected ? "checkmark.shield.fill" : "server.rack")
                    .foregroundColor(navidrome.isConnected ? .green : goldAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TrueNAS Navidrome Subsonic API")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(navidrome.serverURL) • User: \(navidrome.username)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                }
                Spacer()
                Button(showServerConfig || !navidrome.isConnected ? "Hide" : "Configure") {
                    showServerConfig.toggle()
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(goldAccent)
            }

            if showServerConfig || !navidrome.isConnected {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Button("SSL Domain (Recommended)") {
                            navidrome.serverURL = "https://navidrome.nas-server.co.uk"
                            Task { await navidrome.pingAndLoadLibrary() }
                        }
                        .font(.system(size: 10, weight: .bold))
                        .padding(6)
                        .background(goldAccent.opacity(0.25))
                        .cornerRadius(6)

                        Button("Tailscale (100.85.127.42)") {
                            navidrome.serverURL = "http://100.85.127.42:30043"
                        }
                        .font(.system(size: 10, weight: .bold))
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }

                    TextField("Server URL", text: $navidrome.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)

                    HStack(spacing: 8) {
                        TextField("Username", text: $navidrome.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 12))
                            .padding(8)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(6)

                        SecureField("Navidrome Password", text: $navidrome.password)
                            .font(.system(size: 12))
                            .padding(8)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(6)
                    }

                    Button {
                        Task { await navidrome.pingAndLoadLibrary() }
                    } label: {
                        HStack {
                            if navidrome.isLoading {
                                ProgressView().tint(.black)
                            }
                            Text(navidrome.isConnected ? "Reconnect & Refresh Library" : "Connect to TrueNAS Navidrome")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(goldAccent)
                        .cornerRadius(8)
                    }
                }
            }

            if let err = navidrome.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(panelBg)
        .cornerRadius(12)
    }

    private var featuredAlbumsCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FREQUENTLY PLAYED ALBUMS")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(goldAccent)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(navidrome.recentAlbums) { album in
                        Button {
                            selectedAlbum = album
                            Task {
                                albumTracks = await navidrome.fetchAlbumTracks(albumId: album.id)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 110, height: 110)
                                    Image(systemName: "opticaldisc.fill")
                                        .font(.system(size: 36))
                                        .foregroundColor(goldAccent.opacity(0.7))
                                }
                                Text(album.name)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(album.artist ?? "")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            .frame(width: 110)
                        }
                    }
                }
            }
        }
    }

    private var artistsListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ARTISTS (\(navidrome.artists.count))")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(goldAccent)

            LazyVStack(spacing: 6) {
                ForEach(navidrome.artists) { artist in
                    Button {
                        selectedArtist = artist
                        Task {
                            artistAlbums = await navidrome.fetchArtistAlbums(artistId: artist.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "music.mic")
                                .foregroundColor(goldAccent)
                            Text(artist.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            if let count = artist.albumCount {
                                Text("\(count) albums")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .padding(11)
                        .background(panelBg)
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private func artistAlbumsSection(artist: SubsonicArtist) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                selectedArtist = nil
                artistAlbums = []
            } label: {
                Label("All Artists", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(goldAccent)
            }

            Text(artist.name)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.white)

            ForEach(artistAlbums) { album in
                Button {
                    selectedAlbum = album
                    Task {
                        albumTracks = await navidrome.fetchAlbumTracks(albumId: album.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 22))
                            .foregroundColor(goldAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text("\(album.year.map(String.init) ?? "") • \(album.songCount ?? 0) tracks")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding(12)
                    .background(panelBg)
                    .cornerRadius(8)
                }
            }
        }
    }

    private func albumDetailSection(album: SubsonicAlbum) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    selectedAlbum = nil
                    albumTracks = []
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(goldAccent)
                }
                Spacer()
                if !albumTracks.isEmpty {
                    Button {
                        Task {
                            for t in albumTracks {
                                await navidrome.saveTrackOffline(t)
                            }
                        }
                    } label: {
                        Label("Cache Album Offline", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(goldAccent)
                            .cornerRadius(6)
                    }
                }
            }

            Text(album.name)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.white)
            Text(album.artist ?? "")
                .font(.system(size: 13))
                .foregroundColor(goldAccent)

            trackListSection(title: "ALBUM TRACKS (BIT-PERFECT RAW STREAM)", tracks: albumTracks)
        }
    }

    private func trackListSection(title: String, tracks: [SubsonicTrack]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(goldAccent)

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                let isOffline = navidrome.isTrackOffline(track)
                let isDownloading = navidrome.downloadingTrackIds.contains(track.id)

                HStack(spacing: 10) {
                    Button {
                        let playables = tracks.map { t in
                            PlayableItem(
                                id: t.id,
                                title: t.title,
                                artist: t.artist ?? "Unknown Artist",
                                album: t.album ?? "",
                                duration: TimeInterval(t.duration ?? 0),
                                qualityBadge: t.qualityBadge,
                                localURL: navidrome.isTrackOffline(t) ? navidrome.offlineFileURL(for: t) : nil,
                                subsonicTrack: t
                            )
                        }
                        dsp.playQueue(items: playables, startIndex: index)
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(track.track ?? (index + 1))")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("\(track.artist ?? "") • \(track.qualityBadge)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(goldAccent.opacity(0.85))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(track.formattedDuration)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }

                    Button {
                        if isOffline {
                            navidrome.removeOfflineTrack(track)
                        } else {
                            Task { await navidrome.saveTrackOffline(track) }
                        }
                    } label: {
                        if isDownloading {
                            ProgressView().tint(goldAccent)
                        } else {
                            Image(systemName: isOffline ? "checkmark.circle.fill" : "arrow.down.circle")
                                .font(.system(size: 18))
                                .foregroundColor(isOffline ? .green : goldAccent)
                        }
                    }
                }
                .padding(10)
                .background(panelBg)
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - TAB 5: OFFLINE HI-FI VAULT, LOCAL FILES & PLAYBACK QUEUE
struct LocalAndQueueView: View {
    @ObservedObject var navidrome: NavidromeClient
    @ObservedObject var dsp: AudioPreampEngine
    @Binding var showFileImporter: Bool
    let goldAccent: Color
    let panelBg: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Offline Cached FLAC/MP3 Vault
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("OFFLINE PINNED HI-FI VAULT (\(navidrome.offlineTracks.count))", systemImage: "internaldrive.fill")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(goldAccent)
                        Spacer()
                        Text(navidrome.offlineStorageSizeMB)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    if navidrome.offlineTracks.isEmpty {
                        Text("Tap the download icon next to any track or album in TrueNAS Hi-Fi to pin lossless FLAC/MP3 files for offline AirPods Pro 2 or Sony USB-C Pre-Amp playback.")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    } else {
                        Button {
                            let items = navidrome.offlineTracks.map { t in
                                PlayableItem(
                                    id: t.id,
                                    title: t.title,
                                    artist: t.artist ?? "Unknown Artist",
                                    album: t.album ?? "",
                                    duration: TimeInterval(t.duration ?? 0),
                                    qualityBadge: "OFFLINE • \(t.qualityBadge)",
                                    localURL: navidrome.offlineFileURL(for: t),
                                    subsonicTrack: t
                                )
                            }
                            dsp.playQueue(items: items, startIndex: 0)
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play All Offline Tracks (\(navidrome.offlineTracks.count))")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(goldAccent)
                            .cornerRadius(8)
                        }

                        ForEach(Array(navidrome.offlineTracks.enumerated()), id: \.element.id) { idx, t in
                            HStack {
                                Button {
                                    let items = navidrome.offlineTracks.map { tr in
                                        PlayableItem(
                                            id: tr.id,
                                            title: tr.title,
                                            artist: tr.artist ?? "Unknown Artist",
                                            album: tr.album ?? "",
                                            duration: TimeInterval(tr.duration ?? 0),
                                            qualityBadge: "OFFLINE • \(tr.qualityBadge)",
                                            localURL: navidrome.offlineFileURL(for: tr),
                                            subsonicTrack: tr
                                        )
                                    }
                                    dsp.playQueue(items: items, startIndex: idx)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.title)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text("\(t.artist ?? "") • \(t.qualityBadge)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.green)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Button {
                                    navidrome.removeOfflineTrack(t)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.35))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(14)
                .background(panelBg)
                .cornerRadius(12)

                // 2. Import Local Files
                VStack(alignment: .leading, spacing: 8) {
                    Label("IMPORT HI-RES AUDIO FILES", systemImage: "folder.fill.badge.plus")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(goldAccent)

                    Text("Load FLAC, WAV, ALAC, M4A, or MP3 files directly from the iPhone Files app, iCloud Drive, or SMB shares into the 32-bit Sony Amp & AirPods Pro 2 DSP:")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)

                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text("Open Audio Files from iPhone / Files App")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(goldAccent)
                        .cornerRadius(8)
                    }
                }
                .padding(14)
                .background(panelBg)
                .cornerRadius(12)

                // 3. Active Queue
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE PLAYBACK QUEUE (\(dsp.queue.count))")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(goldAccent)

                    if dsp.queue.isEmpty {
                        Text("No tracks in queue yet. Select tracks from TrueNAS Hi-Fi, play your Offline Vault, or run a calibration signal on Tab 1.")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(panelBg)
                            .cornerRadius(10)
                    } else {
                        ForEach(Array(dsp.queue.enumerated()), id: \.element.id) { idx, item in
                            Button {
                                dsp.playQueue(items: dsp.queue, startIndex: idx)
                            } label: {
                                HStack {
                                    Image(systemName: dsp.currentTrack?.id == item.id ? "speaker.wave.3.fill" : "music.note")
                                        .foregroundColor(dsp.currentTrack?.id == item.id ? goldAccent : .gray)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(dsp.currentTrack?.id == item.id ? goldAccent : .white)
                                        Text("\(item.artist) • \(item.qualityBadge)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(panelBg)
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}
