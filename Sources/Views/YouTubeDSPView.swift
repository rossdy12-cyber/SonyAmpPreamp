import SwiftUI
import UIKit

struct YouTubeTrackItem: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let channel: String
    let duration: Int
    let thumbnail: String

    var formattedDuration: String {
        guard duration > 0 else { return "LIVE / MIX" }
        let h = duration / 3600
        let m = (duration % 3600) / 60
        let s = duration % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    func toPlayableItem() -> PlayableItem {
        PlayableItem(
            id: "yt_\(id)",
            title: title,
            artist: channel,
            album: "YouTube+ 32-Bit CoreAudio DSP",
            duration: TimeInterval(duration),
            qualityBadge: "YT M4A • 32-BIT DSP",
            localURL: nil,
            subsonicTrack: nil,
            youTubeVideoId: id,
            thumbnailURL: thumbnail
        )
    }
}

struct YouTubeSearchResponse: Codable {
    let ok: Bool
    let query: String?
    let tracks: [YouTubeTrackItem]
}

@MainActor
final class YouTubeNativeClient: ObservableObject {
    @Published var tracks: [YouTubeTrackItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var activeCategory: String = "Phonk 2026"
    @Published var toastMessage: String?

    private var hasLoadedInitial = false

    func loadInitialIfNeeded() {
        guard !hasLoadedInitial else { return }
        hasLoadedInitial = true
        Task { await search(query: "Phonk 2026") }
    }

    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // If user pasted a direct YouTube URL, extract the 11-char video ID
        if let vid = Self.extractVideoID(from: trimmed) {
            let directTrack = YouTubeTrackItem(
                id: vid,
                title: "YouTube Track (\(vid))",
                channel: "Direct YouTube Stream",
                duration: 0,
                thumbnail: "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg"
            )
            tracks.insert(directTrack, at: 0)
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://navidrome.nas-server.co.uk/sidestore-api/yt-search?q=\(encoded)") else {
            errorMessage = "Invalid search query"
            return
        }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 25
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            if decoded.ok {
                self.tracks = decoded.tracks
            } else {
                self.errorMessage = "Search returned no results"
            }
        } catch {
            self.errorMessage = "Search error: \(error.localizedDescription)"
        }
    }

    func showToast(_ text: String) {
        toastMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.toastMessage == text {
                self.toastMessage = nil
            }
        }
    }

    static func extractVideoID(from input: String) -> String? {
        if input.contains("youtube.com") || input.contains("youtu.be") {
            if let url = URL(string: input), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, v.count == 11 {
                    return v
                }
                let pathParts = url.pathComponents.filter { $0 != "/" }
                if let last = pathParts.last, last.count == 11 {
                    return last
                }
            }
        }
        return nil
    }
}

// MARK: - TAB 2: NATIVE YOUTUBE+ HI-FI DSP BROWSER & NON-INTERRUPTIVE QUEUE
struct YouTubeDSPView: View {
    @ObservedObject var dsp: AudioPreampEngine
    let goldAccent: Color
    let panelBg: Color

    @StateObject private var ytClient = YouTubeNativeClient()
    @State private var searchQuery: String = ""
    @State private var showSystemWideSheet: Bool = false
    @State private var showActiveQueueSheet: Bool = false

    private let quickCategories = [
        ("Phonk 2026", "Phonk 2026"),
        ("Nightcore", "Nightcore"),
        ("Rock & Metal", "Heavy Metal Rock"),
        ("Bass Test", "Subwoofer 45Hz Bass Test"),
        ("Drum & Bass", "Drum and Bass"),
        ("Synthwave", "Dark Synthwave")
    ]

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 1. Search Bar + Active Queue Button (Never interrupts current playback!)
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(goldAccent)
                            TextField("Search YouTube songs, mixes, or paste URL...", text: $searchQuery)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .submitLabel(.search)
                                .onSubmit {
                                    Task { await ytClient.search(query: searchQuery) }
                                }
                            if !searchQuery.isEmpty {
                                Button {
                                    searchQuery = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(10)
                        .background(panelBg)
                        .cornerRadius(10)

                        Button {
                            showActiveQueueSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet.rectangle.portrait.fill")
                                Text("\(dsp.queue.count)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(goldAccent)
                            .cornerRadius(10)
                        }
                    }

                    // 2. Quick Vibe / Genre Discovery Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(quickCategories, id: \.0) { label, query in
                                let isSelected = ytClient.activeCategory == label
                                Button {
                                    ytClient.activeCategory = label
                                    searchQuery = label
                                    Task { await ytClient.search(query: query) }
                                } label: {
                                    Text(label)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(isSelected ? .black : .white)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? goldAccent : panelBg)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }

                    // 3. Instant DSP Preset Switcher Strip (Real 32-Bit CoreAudio Engine!)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            let presets = dsp.activeProfileMode == .airPodsPro2 ? EQPreset.airPodsPro2Presets : EQPreset.sonyPresets
                            ForEach(presets) { preset in
                                let selected = dsp.selectedPresetId == preset.id
                                Button {
                                    dsp.applyPreset(preset)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: preset.icon)
                                            .font(.system(size: 10))
                                        Text(preset.name)
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundColor(selected ? .black : goldAccent)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(selected ? goldAccent : Color.white.opacity(0.07))
                                    .cornerRadius(6)
                                }
                            }

                            Button {
                                showSystemWideSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "airpodspro")
                                        .font(.system(size: 10))
                                    Text("iOS H2 EQ")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(6)
                            }
                        }
                    }

                    // 4. Status Banner: Ad-Free Native CoreAudio Stream + Background Play
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text("AD-FREE COREAUDIO 32-BIT DSP • LOCK-SCREEN BACKGROUND PLAY ACTIVE")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(.green)
                        Spacer()
                        if ytClient.isLoading || dsp.isLoadingTrack {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(goldAccent)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(8)

                    if let err = ytClient.errorMessage {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }

                    // 5. Full-Height Scrollable Track List with Play Now, Play Next & + Queue
                    LazyVStack(spacing: 8) {
                        ForEach(Array(ytClient.tracks.enumerated()), id: \.element.id) { index, track in
                            let isCurrent = dsp.currentTrack?.youTubeVideoId == track.id
                            HStack(spacing: 10) {
                                // Tap main area -> Play Now (and load remaining results as Up Next queue)
                                Button {
                                    let playables = ytClient.tracks.map { $0.toPlayableItem() }
                                    dsp.playQueue(items: playables, startIndex: index)
                                } label: {
                                    HStack(spacing: 10) {
                                        ZStack(alignment: .bottomTrailing) {
                                            AsyncImage(url: URL(string: track.thumbnail)) { phase in
                                                if let img = phase.image {
                                                    img.resizable().aspectRatio(contentMode: .fill)
                                                } else {
                                                    Rectangle().fill(Color.white.opacity(0.08))
                                                        .overlay(Image(systemName: "play.rectangle.fill").foregroundColor(goldAccent))
                                                }
                                            }
                                            .frame(width: 84, height: 50)
                                            .clipShape(RoundedRectangle(cornerRadius: 7))

                                            Text(track.formattedDuration)
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(Color.black.opacity(0.8))
                                                .cornerRadius(3)
                                                .padding(3)
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(track.title)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(isCurrent ? goldAccent : .white)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)

                                            Text(track.channel)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.gray)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 2)
                                    }
                                }

                                // Non-Interruptive Queue Buttons: Play Next & Add to Queue
                                HStack(spacing: 6) {
                                    Button {
                                        dsp.playNext(track.toPlayableItem())
                                        ytClient.showToast("Playing Next: \(track.title)")
                                    } label: {
                                        VStack(spacing: 2) {
                                            Image(systemName: "text.insert")
                                                .font(.system(size: 13, weight: .bold))
                                            Text("Next")
                                                .font(.system(size: 8, weight: .bold))
                                        }
                                        .foregroundColor(goldAccent)
                                        .frame(width: 36, height: 42)
                                        .background(Color.white.opacity(0.07))
                                        .cornerRadius(7)
                                    }

                                    Button {
                                        dsp.appendToQueue(track.toPlayableItem())
                                        ytClient.showToast("Added to Queue: \(track.title)")
                                    } label: {
                                        VStack(spacing: 2) {
                                            Image(systemName: "text.badge.plus")
                                                .font(.system(size: 13, weight: .bold))
                                            Text("+Queue")
                                                .font(.system(size: 8, weight: .bold))
                                        }
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 42)
                                        .background(Color.white.opacity(0.07))
                                        .cornerRadius(7)
                                    }
                                }
                            }
                            .padding(8)
                            .background(isCurrent ? goldAccent.opacity(0.14) : panelBg)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isCurrent ? goldAccent.opacity(0.6) : Color.clear, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(12)
            }

            if let toast = ytClient.toastMessage {
                Text(toast)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(goldAccent)
                    .cornerRadius(20)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(GothicTheme.void)
        .onAppear {
            ytClient.loadInitialIfNeeded()
        }
        .sheet(isPresented: $showSystemWideSheet) {
            AirPodsSystemWideEQSheet(dsp: dsp, goldAccent: goldAccent, panelBg: panelBg)
        }
        .sheet(isPresented: $showActiveQueueSheet) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if dsp.queue.isEmpty {
                            Text("Your playback queue is empty. Tap 'Next' or '+Queue' on any YouTube or TrueNAS track to line up songs without stopping playback.")
                                .font(.system(size: 13))
                                .foregroundColor(.gray)
                                .padding()
                        } else {
                            ForEach(Array(dsp.queue.enumerated()), id: \.offset) { idx, item in
                                HStack {
                                    Button {
                                        dsp.playQueue(items: dsp.queue, startIndex: idx)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: idx == dsp.currentQueueIndex ? "speaker.wave.3.fill" : "music.note")
                                                .foregroundColor(idx == dsp.currentQueueIndex ? goldAccent : .gray)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.title)
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundColor(idx == dsp.currentQueueIndex ? goldAccent : .white)
                                                    .lineLimit(1)
                                                Text("\(item.artist) • \(item.qualityBadge)")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                        }
                                    }
                                    if idx != dsp.currentQueueIndex {
                                        Button {
                                            dsp.queue.remove(at: idx)
                                            if idx < dsp.currentQueueIndex {
                                                dsp.currentQueueIndex -= 1
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 12))
                                                .foregroundColor(.red.opacity(0.8))
                                        }
                                    }
                                }
                                .padding(10)
                                .background(panelBg)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(14)
                }
                .background(GothicTheme.void)
                .navigationTitle("Up Next Queue (\(dsp.queue.count))")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showActiveQueueSheet = false }
                            .foregroundColor(goldAccent)
                    }
                }
            }
        }
    }
}

// MARK: - iOS System-Wide AirPods Pro 2 H2 Hardware EQ / Audiogram Exporter Sheet
struct AirPodsSystemWideEQSheet: View {
    @ObservedObject var dsp: AudioPreampEngine
    let goldAccent: Color
    let panelBg: Color
    @Environment(\.dismiss) private var dismiss
    @State private var copiedToast: Bool = false

    private let audiogramFreqs: [(String, Int)] = [
        ("125 Hz (Sub/Bass)", 1),
        ("250 Hz (Low-Mid)", 3),
        ("500 Hz (Warmth)", 4),
        ("1 kHz (Center)", 5),
        ("2 kHz (Vocal)", 6),
        ("4 kHz (Pinna Presence)", 7),
        ("8 kHz (Treble Air)", 8)
    ]

    private func computedAudiogramDBHL(bandIndex: Int) -> Float {
        let eqGain = dsp.eqBands[bandIndex]
        let subAdd: Float = bandIndex <= 1 ? (dsp.airPodsSubBassDB * 0.65 + dsp.megaBassDB * 0.45) : 0.0
        let pinnaAdd: Float = (bandIndex == 6 || bandIndex == 7) ? dsp.airPodsVocalPresenceDB * 0.75 : 0.0
        let airAdd: Float = bandIndex >= 8 ? (dsp.airPodsSilkAirDB * 0.8 + dsp.brillianceDB * 0.5) : 0.0
        let totalBoost = eqGain + subAdd + pinnaAdd + airAdd
        let baseHL: Float = 15.0 + totalBoost * 2.5
        return max(0.0, min(55.0, (baseHL * 2.0).rounded() / 2.0))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("AIRPODS PRO 2 H2 HARDWARE SYSTEM-WIDE EQ", systemImage: "airpodspro")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(goldAccent)
                        Text("You can also write your active preset onto your AirPods Pro 2 H2 chip via iOS Headphone Accommodations so it stays active in every app on your iPhone (Spotify, Netflix, TikTok, Apple Music).")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(14)
                    .background(panelBg)
                    .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTIVE PRESET AUDIOGRAM TABLE (dB HL)")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(goldAccent)

                        ForEach(audiogramFreqs, id: \.0) { label, idx in
                            let hl = computedAudiogramDBHL(bandIndex: idx)
                            HStack {
                                Text(label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(String(format: "L: %.0f dB HL   R: %.0f dB HL", hl, hl))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(goldAccent)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.black.opacity(0.35))
                            .cornerRadius(8)
                        }
                    }
                    .padding(14)
                    .background(panelBg)
                    .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            var lines = ["AirPods Pro 2 H2 Custom Audiogram (\(dsp.selectedPresetId)):"]
                            for (label, idx) in audiogramFreqs {
                                let hl = computedAudiogramDBHL(bandIndex: idx)
                                lines.append("\(label): \(Int(hl)) dB HL")
                            }
                            UIPasteboard.general.string = lines.joined(separator: "\n")
                            copiedToast = true
                        } label: {
                            HStack {
                                Image(systemName: copiedToast ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                Text(copiedToast ? "Copied Audiogram Table to Clipboard!" : "Copy Audiogram Values to Clipboard")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(goldAccent)
                            .cornerRadius(8)
                        }

                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "gearshape.fill")
                                Text("Open iOS Settings → Accessibility → Audio & Visual")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(14)
                    .background(panelBg)
                    .cornerRadius(12)
                }
                .padding(14)
            }
            .background(GothicTheme.void)
            .navigationTitle("System-Wide AirPods EQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(goldAccent)
                }
            }
        }
    }
}
