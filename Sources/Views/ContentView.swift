import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var navidrome = NavidromeClient()
    @StateObject private var dspEngine = AudioPreampEngine()
    @State private var selectedTab: Int = 0
    @State private var showFileImporter: Bool = false

    private let goldAccent = Color(red: 0.93, green: 0.74, blue: 0.32)
    private let panelBg = Color(red: 0.11, green: 0.12, blue: 0.14)
    private let deepBg = Color(red: 0.06, green: 0.06, blue: 0.08)

    var body: some View {
        ZStack {
            deepBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Hardware USB-C DAC Status Bar
                hardwareHeaderBar

                TabView(selection: $selectedTab) {
                    PreampRackView(dsp: dspEngine, goldAccent: goldAccent, panelBg: panelBg)
                        .tabItem {
                            Label("Sony Amp DSP", systemImage: "slider.vertical.3")
                        }
                        .tag(0)

                    NavidromeLibraryView(navidrome: navidrome, dsp: dspEngine, goldAccent: goldAccent, panelBg: panelBg)
                        .tabItem {
                            Label("TrueNAS Hi-Fi", systemImage: "server.rack")
                        }
                        .tag(1)

                    LocalAndQueueView(dsp: dspEngine, showFileImporter: $showFileImporter, goldAccent: goldAccent, panelBg: panelBg)
                        .tabItem {
                            Label("Files & Queue", systemImage: "music.note.list")
                        }
                        .tag(2)
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
            if !navidrome.password.isEmpty && !navidrome.isConnected {
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
                Image(systemName: dspEngine.isUSBDACConnected ? "cable.connector.horizontal" : "iphone.gen3")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(dspEngine.isUSBDACConnected ? .black : goldAccent)
                    .padding(7)
                    .background(dspEngine.isUSBDACConnected ? goldAccent : Color.white.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("SONY ES PRE-AMP")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(goldAccent)
                        Text("•")
                            .foregroundColor(.gray)
                        Text(String(format: "%.1f kHz 32-Bit DSP", dspEngine.sampleRateHz / 1000.0))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Text(dspEngine.statusBanner)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(dspEngine.isUSBDACConnected ? .green : .white.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    dspEngine.dspBypassed.toggle()
                } label: {
                    Text(dspEngine.dspBypassed ? "BYPASSED" : "DSP ON")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(dspEngine.dspBypassed ? .white : .black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(dspEngine.dspBypassed ? Color.red.opacity(0.8) : goldAccent)
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(panelBg)
        }
    }

    private var miniPlayerBar: some View {
        VStack(spacing: 6) {
            if let track = dspEngine.currentTrack {
                // Scrubbable progress bar
                Slider(
                    value: Binding(
                        get: { dspEngine.currentTime },
                        set: { dspEngine.seek(to: $0) }
                    ),
                    in: 0...max(1, dspEngine.duration)
                )
                .tint(goldAccent)
                .padding(.horizontal, 14)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(track.artist)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                            Text(track.qualityBadge)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(goldAccent)
                                .cornerRadius(4)
                        }
                    }

                    Spacer()

                    Button { dspEngine.previousTrack() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }

                    Button { dspEngine.playPause() } label: {
                        Image(systemName: dspEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(goldAccent)
                    }

                    Button { dspEngine.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 6)
        .background(Color(red: 0.14, green: 0.15, blue: 0.18))
    }
}

// MARK: - TAB 1: SONY AMP PRE-AMP & 10-BAND EQ RACK
struct PreampRackView: View {
    @ObservedObject var dsp: AudioPreampEngine
    let goldAccent: Color
    let panelBg: Color

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Live Stereo VU Meters & Voltage Estimator Card
                vuMeterAndVoltageCard

                // 2. USB-C Auto-Detection & Pre-Amp Line-Driver Gain Boost
                preampLineDriverCard

                // 3. One-Tap Sony Amp Presets
                presetsSection

                // 4. 10-Band Parametric Equalizer
                tenBandEQCard

                // 5. Instant Sony Amp Calibration & Bass Test Generator
                calibrationGeneratorCard
            }
            .padding(14)
        }
    }

    private var vuMeterAndVoltageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LINE-OUT LEVEL & VU METER", systemImage: "waveform.path.ecg.rectangle")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(goldAccent)
                Spacer()
                Text(String(format: "EST. OUTPUT: %.2f Vrms", dsp.estimatedOutputVrms))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(dsp.estimatedOutputVrms >= 1.1 ? Color.green : goldAccent)
                    .cornerRadius(4)
            }

            // Left / Right Bar Meters
            VStack(spacing: 6) {
                channelMeterRow(label: "L", level: dsp.leftLevel)
                channelMeterRow(label: "R", level: dsp.rightLevel)
            }

            HStack {
                Text("UK/EU USB-C Cap: 0.50 Vrms")
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
            .frame(height: 12)
        }
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
                    Text("Pre-Amp Voltage Gain")
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
                        ("+6dB (1.0V)", Float(6.0)),
                        ("+7.5dB (Sony)", Float(7.5)),
                        ("+9.5dB (1.5V)", Float(9.5)),
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
                    Text("Sony MegaBass (65 Hz Sub-Harmonic Shelf)")
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
        VStack(alignment: .leading, spacing: 10) {
            Label("SONY AMP ACOUSTIC PRESETS", systemImage: "sparkles")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(goldAccent)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(EQPreset.builtInPresets) { preset in
                    let isSelected = dsp.selectedPresetId == preset.id
                    Button {
                        dsp.applyPreset(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: preset.icon)
                                    .foregroundColor(isSelected ? .black : goldAccent)
                                Spacer()
                                Text(String(format: "%+.1fdB", preset.preampGainDB))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(isSelected ? .black.opacity(0.8) : goldAccent)
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
            }
        }
        .padding(14)
        .background(panelBg)
        .cornerRadius(12)
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
            Label("INSTANT SONY AMP SOUND CHECK & CALIBRATION", systemImage: "waveform.badge.magnifyingglass")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(goldAccent)

            Text("Test your USB-C to 3.5mm cable and Sony Amp line-level boost immediately without loading a song:")
                .font(.system(size: 11))
                .foregroundColor(.gray)

            HStack(spacing: 8) {
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
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 10, weight: .bold))
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
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
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
                        Button("Tailscale (100.85.127.42)") {
                            navidrome.serverURL = "http://100.85.127.42:30043"
                        }
                        .font(.system(size: 10, weight: .bold))
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)

                        Button("Home LAN (192.168.0.x)") {
                            navidrome.serverURL = "http://192.168.0.10:30043"
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
            Button {
                selectedAlbum = nil
                albumTracks = []
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(goldAccent)
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
                Button {
                    let playables = tracks.map { t in
                        PlayableItem(
                            id: t.id,
                            title: t.title,
                            artist: t.artist ?? "Unknown Artist",
                            album: t.album ?? "",
                            duration: TimeInterval(t.duration ?? 0),
                            qualityBadge: t.qualityBadge,
                            localURL: nil,
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
                    .padding(10)
                    .background(panelBg)
                    .cornerRadius(8)
                }
            }
        }
    }
}

// MARK: - TAB 3: LOCAL FILES & PLAYBACK QUEUE
struct LocalAndQueueView: View {
    @ObservedObject var dsp: AudioPreampEngine
    @Binding var showFileImporter: Bool
    let goldAccent: Color
    let panelBg: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("IMPORT HI-RES AUDIO FILES", systemImage: "folder.fill.badge.plus")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(goldAccent)

                    Text("Load FLAC, WAV, ALAC, M4A, or MP3 files directly from the iPhone Files app, iCloud Drive, or SMB shares into the 32-bit Sony Amp Pre-Amp DSP:")
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE PLAYBACK QUEUE (\(dsp.queue.count))")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(goldAccent)

                    if dsp.queue.isEmpty {
                        Text("No tracks in queue yet. Select tracks from TrueNAS Hi-Fi, import local files, or run a Sony Amp Calibration signal on Tab 1.")
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
