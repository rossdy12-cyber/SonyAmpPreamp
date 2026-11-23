import SwiftUI
import AVKit
import UIKit

// MARK: - Gothic Vampire TV Theme

enum TVGothicTheme {
    static let void      = Color(red: 0.020, green: 0.008, blue: 0.012) // #050203
    static let crypt     = Color(red: 0.071, green: 0.024, blue: 0.035) // #120609
    static let sepulchre = Color(red: 0.118, green: 0.039, blue: 0.059) // #1E0A0F
    static let tomb      = Color(red: 0.235, green: 0.071, blue: 0.098) // #3C1219
    static let bloodDeep = Color(red: 0.361, green: 0.039, blue: 0.094) // #5C0A18
    static let blood     = Color(red: 0.620, green: 0.059, blue: 0.157) // #9E0F28
    static let bloodHi   = Color(red: 0.831, green: 0.086, blue: 0.227) // #D4163A
    static let bone      = Color(red: 0.937, green: 0.894, blue: 0.882) // #EFE4E1
    static let ash       = Color(red: 0.620, green: 0.525, blue: 0.541) // #9E868A

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .serif)
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

struct TVGothicLancetArch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let spring = rect.minY + rect.height * 0.44
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: spring))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.10)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: spring),
            control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.10)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

struct TVGothicCathedralBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                TVGothicTheme.void

                RadialGradient(
                    colors: [TVGothicTheme.bloodDeep.opacity(0.55), TVGothicTheme.crypt.opacity(0.35), .clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: max(w, h) * 0.78
                )

                TVGothicLancetArch()
                    .stroke(TVGothicTheme.blood.opacity(0.16), lineWidth: 2)
                    .frame(width: w * 0.68, height: h * 0.88)
                    .position(x: w / 2, y: h * 0.55)

                Circle()
                    .stroke(TVGothicTheme.blood.opacity(0.14), lineWidth: 1.5)
                    .frame(width: min(w, h) * 0.34, height: min(w, h) * 0.34)
                    .position(x: w / 2, y: h * 0.36)
            }
        }
    }
}

struct TVGothicFocusButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    var active: Bool = false
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isFocused
                            ? LinearGradient(colors: [TVGothicTheme.bloodDeep, TVGothicTheme.sepulchre], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : (active
                                ? LinearGradient(colors: [TVGothicTheme.bloodDeep.opacity(0.75), TVGothicTheme.crypt], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [TVGothicTheme.sepulchre.opacity(0.88), TVGothicTheme.crypt.opacity(0.94)], startPoint: .top, endPoint: .bottom))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? TVGothicTheme.bloodHi : (active ? TVGothicTheme.blood : TVGothicTheme.tomb),
                        lineWidth: isFocused ? 3.5 : (active ? 2.0 : 1.2)
                    )
            )
            .shadow(color: isFocused ? TVGothicTheme.bloodHi.opacity(0.65) : .clear, radius: isFocused ? 22 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.04 : 1.0))
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

// MARK: - Models

struct YTVideoItem: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let channel: String
    let channelId: String?
    let duration: String
    let views: String
    let published: String?
    let thumbnailURL: String
}

struct SponsorSegment: Codable, Equatable {
    let start: Double
    let end: Double
    let category: String
}

struct YTChannelSub: Codable, Identifiable, Equatable {
    var id: String { channelId.isEmpty ? name : channelId }
    let channelId: String
    let name: String
}

struct YTFeedResponse: Codable {
    let ok: Bool
    let videos: [YTVideoItem]?
    let subscriptions: [YTChannelSub]?
}

struct YTStreamResponse: Codable {
    let ok: Bool
    let id: String?
    let title: String?
    let channel: String?
    let channelId: String?
    let duration: Int?
    let views: String?
    let description: String?
    let hls_url: String?
    let direct_url: String?
    let proxy_play_url: String?
    let mesh_play_url: String?
    let segments: [SponsorSegment]?
    let error: String?
}

// MARK: - ViewModel (Dual-Engine On-Device InnerTube iOS 4K60 HLS + TrueNAS Sync + SponsorBlock)

@MainActor
final class YouTubePlusTVViewModel: ObservableObject {
    @Published var selectedCategory: String = "trending"
    @Published var videos: [YTVideoItem] = []
    @Published var subscriptions: [YTChannelSub] = []
    @Published var searchQuery: String = ""
    @Published var isLoading: Bool = false
    @Published var statusBanner: String?

    // Player State
    @Published var activeVideo: YTVideoItem?
    @Published var activeStreamURL: URL?
    @Published var activeSegments: [SponsorSegment] = []
    @Published var isResolvingStream: Bool = false
    @Published var skippedToast: String?
    @Published var skippedCount: Int = 0
    @Published var skippedSecondsTotal: Int = 0

    // Settings
    @Published var sponsorBlockEnabled: Bool = true
    @Published var skipSponsors: Bool = true
    @Published var skipSelfPromo: Bool = true
    @Published var skipIntrosOutros: Bool = true
    @Published var prefer4KHDR: Bool = true
    @Published var defaultPlaybackRate: Float = 1.0

    private let serverBases = [
        "https://hs.nas-server.co.uk/ytplus-api",
        "http://100.64.0.4:18998/sidestore-api/ytplus",
        "http://100.85.127.42:18998/sidestore-api/ytplus"
    ]

    func loadCategory(_ category: String) async {
        selectedCategory = category
        if category == "search" {
            if !searchQuery.isEmpty {
                await performSearch(searchQuery)
            }
            return
        }
        isLoading = true
        defer { isLoading = false }

        // 1. Try TrueNAS server feed (which syncs subscriptions & watch history)
        for base in serverBases {
            guard let url = URL(string: "\(base)?action=feed&category=\(category)") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let decoded = try JSONDecoder().decode(YTFeedResponse.self, from: data)
                if decoded.ok, let vids = decoded.videos, !vids.isEmpty {
                    self.videos = vids
                    if let subs = decoded.subscriptions {
                        self.subscriptions = subs
                    }
                    return
                }
            } catch {
                continue
            }
        }

        // 2. Fallback: Direct On-Device InnerTube Search
        let fallbackQueries: [String: String] = [
            "trending": "4K HDR 60fps trending 2026",
            "subscriptions": "Marques Brownlee Linus Tech Tips Jeff Geerling Kurzgesagt",
            "gaming": "4K 60fps gameplay walkthrough review",
            "tech": "TrueNAS homelab networking self-hosted review",
            "music": "4K official music video live performance"
        ]
        let q = fallbackQueries[category] ?? "4K HDR 60fps"
        let directVids = await directInnerTubeSearch(query: q)
        if !directVids.isEmpty {
            self.videos = directVids
        }
    }

    func performSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let direct = await directInnerTubeSearch(query: trimmed)
        if !direct.isEmpty {
            self.videos = direct
            return
        }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        for base in serverBases {
            guard let url = URL(string: "\(base)?action=search&q=\(encoded)") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let decoded = try? JSONDecoder().decode(YTFeedResponse.self, from: data),
               let vids = decoded.videos {
                self.videos = vids
                return
            }
        }
    }

    func playVideo(_ item: YTVideoItem) async {
        isResolvingStream = true
        statusBanner = " Forging 4K60 Ad-Free Stream & SponsorBlock Map..."
        defer {
            isResolvingStream = false
            statusBanner = nil
        }

        async let sbTask = fetchSponsorBlockDirect(videoId: item.id)
        async let hlsTask = resolveDirectInnerTubeHLS(videoId: item.id)
        async let serverTask = resolveTrueNASStream(videoId: item.id)

        let directHLS = await hlsTask
        let sbSegments = await sbTask

        if let hls = directHLS, let url = URL(string: hls) {
            self.activeSegments = sbSegments
            self.activeStreamURL = url
            self.activeVideo = item
            // Notify TrueNAS in background to record watch history
            Task { _ = await serverTask }
            return
        }

        if let st = await serverTask {
            let candidates = [st.hls_url, st.proxy_play_url, st.direct_url].compactMap { $0 }.filter { !$0.isEmpty }
            if let first = candidates.first, let url = URL(string: first) {
                self.activeSegments = st.segments ?? sbSegments
                self.activeStreamURL = url
                self.activeVideo = item
                return
            }
        }

        statusBanner = "Could not resolve stream for \(item.title)"
    }

    func toggleSubscription(channel: String, channelId: String) async {
        for base in serverBases {
            guard let url = URL(string: base) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 6
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "action": "subscribe",
                "channel": channel,
                "channelId": channelId
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = root["message"] as? String {
                statusBanner = msg
                return
            }
        }
    }

    // MARK: - On-Device InnerTube iOS 4K60 HLS Resolver

    private func resolveDirectInnerTubeHLS(videoId: String) async -> String? {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") else { return nil }
        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "IOS",
                    "clientVersion": "20.10.4",
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone16,2",
                    "osName": "iOS",
                    "osVersion": "18.3.1.22D72",
                    "hl": "en",
                    "gl": "GB"
                ]
            ],
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_1 like Mac OS X;)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sd = root["streamingData"] as? [String: Any] else {
            return nil
        }
        if let hls = sd["hlsManifestUrl"] as? String, !hls.isEmpty {
            return hls
        }
        if let fmts = sd["formats"] as? [[String: Any]], let u = fmts.last?["url"] as? String {
            return u
        }
        return nil
    }

    private func resolveTrueNASStream(videoId: String) async -> YTStreamResponse? {
        for base in serverBases {
            guard let url = URL(string: "\(base)?action=stream&id=\(videoId)") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 12
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let decoded = try? JSONDecoder().decode(YTStreamResponse.self, from: data),
               decoded.ok {
                return decoded
            }
        }
        return nil
    }

    private func fetchSponsorBlockDirect(videoId: String) async -> [SponsorSegment] {
        let cats = "[\"sponsor\",\"selfpromo\",\"interaction\",\"intro\",\"outro\",\"music_offtopic\"]"
        let encCats = cats.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cats
        guard let url = URL(string: "https://sponsor.ajay.app/api/skipSegments?videoID=\(videoId)&categories=\(encCats)") else {
            return []
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3.5
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var result: [SponsorSegment] = []
        for item in arr {
            if let seg = item["segment"] as? [Double], seg.count == 2 {
                let cat = item["category"] as? String ?? "sponsor"
                result.append(SponsorSegment(start: seg[0], end: seg[1], category: cat))
            }
        }
        return result
    }

    private func directInnerTubeSearch(query: String) async -> [YTVideoItem] {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/search?prettyPrint=false") else { return [] }
        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20250220.01.00",
                    "hl": "en",
                    "gl": "GB"
                ]
            ],
            "query": query
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 6
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = ((root["contents"] as? [String: Any])?["twoColumnSearchResultsRenderer"] as? [String: Any])?["primaryContents"] as? [String: Any],
              let sections = (contents["sectionListRenderer"] as? [String: Any])?["contents"] as? [[String: Any]] else {
            return []
        }

        var items: [YTVideoItem] = []
        for sec in sections {
            guard let list = (sec["itemSectionRenderer"] as? [String: Any])?["contents"] as? [[String: Any]] else { continue }
            for entry in list {
                guard let vr = entry["videoRenderer"] as? [String: Any],
                      let vid = vr["videoId"] as? String else { continue }
                let titleRuns = ((vr["title"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
                let title = titleRuns.compactMap { $0["text"] as? String }.joined()
                let ownerRuns = ((vr["ownerText"] as? [String: Any])?["runs"] as? [[String: Any]]) ?? []
                let channel = (ownerRuns.first?["text"] as? String) ?? "YouTube"
                let dur = ((vr["lengthText"] as? [String: Any])?["simpleText"] as? String) ?? "4K"
                let views = ((vr["shortViewCountText"] as? [String: Any])?["simpleText"] as? String)
                    ?? ((vr["viewCountText"] as? [String: Any])?["simpleText"] as? String) ?? ""
                let pub = ((vr["publishedTimeText"] as? [String: Any])?["simpleText"] as? String) ?? ""
                items.append(
                    YTVideoItem(
                        id: vid,
                        title: title,
                        channel: channel,
                        channelId: "",
                        duration: dur,
                        views: views,
                        published: pub,
                        thumbnailURL: "https://i.ytimg.com/vi/\(vid)/hq720.jpg"
                    )
                )
                if items.count >= 24 { return items }
            }
        }
        return items
    }
}

// MARK: - Native tvOS AVPlayerViewController + SponsorBlock Engine

struct TVPlayerContainerView: View {
    @ObservedObject var vm: YouTubePlusTVViewModel
    let video: YTVideoItem
    let streamURL: URL
    let segments: [SponsorSegment]
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var timeObserverToken: Any?
    @State private var currentRate: Float = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let player = player {
                TVAVPlayerViewControllerBridge(player: player)
                    .ignoresSafeArea()
            } else {
                TVGothicTheme.void.ignoresSafeArea()
            }

            // Top-Right Gothic Vampire HUD Overlay (SponsorBlock Toast + Quick Controls)
            VStack(alignment: .trailing, spacing: 14) {
                HStack(spacing: 12) {
                    Button {
                        cycleSpeed()
                    } label: {
                        Text(String(format: "SPEED %.2gx", currentRate))
                            .font(TVGothicTheme.serif(18, weight: .bold))
                            .foregroundStyle(TVGothicTheme.bone)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(TVGothicFocusButtonStyle(active: currentRate != 1.0, cornerRadius: 10))

                    Button {
                        Task {
                            await vm.toggleSubscription(channel: video.channel, channelId: video.channelId ?? video.channel)
                        }
                    } label: {
                        Text("✠ BIND CHANNEL")
                            .font(TVGothicTheme.serif(18, weight: .bold))
                            .foregroundStyle(TVGothicTheme.bone)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(TVGothicFocusButtonStyle(active: false, cornerRadius: 10))

                    Button {
                        cleanupAndDismiss()
                    } label: {
                        Text("CLOSE ✕")
                            .font(TVGothicTheme.serif(18, weight: .bold))
                            .foregroundStyle(TVGothicTheme.bone)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(TVGothicFocusButtonStyle(active: true, cornerRadius: 10))
                }

                if let toast = vm.skippedToast {
                    HStack(spacing: 10) {
                        Text("✠")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(TVGothicTheme.bloodHi)
                        Text(toast)
                            .font(TVGothicTheme.serif(20, weight: .bold))
                            .foregroundStyle(TVGothicTheme.bone)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TVGothicTheme.bloodDeep.opacity(0.95))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(TVGothicTheme.bloodHi, lineWidth: 2)
                    )
                    .shadow(color: TVGothicTheme.bloodHi.opacity(0.6), radius: 16)
                }
            }
            .padding(42)
        }
        .onAppear {
            startPlayback()
        }
        .onDisappear {
            stopPlayback()
        }
        .onExitCommand {
            cleanupAndDismiss()
        }
    }

    private func startPlayback() {
        let item = AVPlayerItem(url: streamURL)
        if vm.prefer4KHDR {
            item.preferredMaximumResolution = CGSize(width: 3840, height: 2160)
        }
        let avPlayer = AVPlayer(playerItem: item)
        self.currentRate = vm.defaultPlaybackRate
        self.player = avPlayer
        avPlayer.playImmediately(atRate: vm.defaultPlaybackRate)

        let interval = CMTime(seconds: 0.4, preferredTimescale: 600)
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard vm.sponsorBlockEnabled else { return }
            let sec = time.seconds
            guard sec.isFinite && sec >= 0 else { return }
            for seg in segments {
                if !shouldSkipCategory(seg.category) { continue }
                if sec >= seg.start && sec < (seg.end - 0.6) {
                    let target = CMTime(seconds: seg.end + 0.1, preferredTimescale: 600)
                    avPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                    let saved = max(1, Int(seg.end - seg.start))
                    vm.skippedCount += 1
                    vm.skippedSecondsTotal += saved
                    vm.skippedToast = "BANISHED \(seg.category.uppercased()) (+\(saved)s)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                        if vm.skippedToast?.contains(seg.category.uppercased()) == true {
                            vm.skippedToast = nil
                        }
                    }
                    break
                }
            }
        }
    }

    private func shouldSkipCategory(_ cat: String) -> Bool {
        switch cat {
        case "sponsor": return vm.skipSponsors
        case "selfpromo", "interaction": return vm.skipSelfPromo
        case "intro", "outro", "music_offtopic": return vm.skipIntrosOutros
        default: return true
        }
    }

    private func cycleSpeed() {
        let rates: [Float] = [1.0, 1.25, 1.5, 2.0]
        if let idx = rates.firstIndex(of: currentRate) {
            currentRate = rates[(idx + 1) % rates.count]
        } else {
            currentRate = 1.0
        }
        player?.rate = currentRate
    }

    private func stopPlayback() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
    }

    private func cleanupAndDismiss() {
        stopPlayback()
        onDismiss()
    }
}

struct TVAVPlayerViewControllerBridge: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}

// MARK: - Main Apple TV Sanctuary View

struct YouTubePlusTVMainView: View {
    @StateObject private var vm = YouTubePlusTVViewModel()

    private let categories: [(id: String, icon: String, title: String)] = [
        ("trending", "flame.fill", "SANCTUM 4K"),
        ("subscriptions", "person.2.wave.2.fill", "COVEN SUBS"),
        ("search", "magnifyingglass", "SEARCH"),
        ("tech", "server.rack", "TECH & LAB"),
        ("gaming", "gamecontroller.fill", "GAMING 60FPS"),
        ("music", "music.note.tv.fill", "MUSIC"),
        ("history", "clock.arrow.circlepath", "CHRONICLE"),
        ("settings", "gearshape.fill", "RITES")
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 36),
        GridItem(.flexible(), spacing: 36),
        GridItem(.flexible(), spacing: 36)
    ]

    var body: some View {
        ZStack {
            TVGothicCathedralBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                headerBar
                navigationRibbon

                if let banner = vm.statusBanner {
                    HStack(spacing: 12) {
                        if vm.isResolvingStream {
                            ProgressView()
                                .tint(TVGothicTheme.bloodHi)
                        } else {
                            Text("✠")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(TVGothicTheme.bloodHi)
                        }
                        Text(banner)
                            .font(TVGothicTheme.serif(21, weight: .semibold))
                            .foregroundStyle(TVGothicTheme.bone)
                        Spacer()
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TVGothicTheme.bloodDeep.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(TVGothicTheme.bloodHi, lineWidth: 1.5)
                    )
                    .padding(.horizontal, 48)
                }

                if vm.selectedCategory == "settings" {
                    settingsView
                } else {
                    if vm.selectedCategory == "search" {
                        searchBarView
                    }

                    if vm.isLoading && vm.videos.isEmpty {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 16) {
                                ProgressView()
                                    .tint(TVGothicTheme.bloodHi)
                                    .scaleEffect(1.6)
                                Text("SUMMONING 4K60 STREAMS FROM THE SANCTUM...")
                                    .font(TVGothicTheme.serif(20, weight: .bold))
                                    .tracking(1.5)
                                    .foregroundStyle(TVGothicTheme.ash)
                            }
                            Spacer()
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 38) {
                                ForEach(vm.videos) { item in
                                    videoCard(item)
                                }
                            }
                            .padding(.horizontal, 48)
                            .padding(.vertical, 18)
                        }
                    }
                }
            }
            .padding(.top, 28)
        }
        .fullScreenCover(isPresented: Binding(
            get: { vm.activeVideo != nil && vm.activeStreamURL != nil },
            set: { if !$0 { vm.activeVideo = nil; vm.activeStreamURL = nil } }
        )) {
            if let vid = vm.activeVideo, let url = vm.activeStreamURL {
                TVPlayerContainerView(
                    vm: vm,
                    video: vid,
                    streamURL: url,
                    segments: vm.activeSegments
                ) {
                    vm.activeVideo = nil
                    vm.activeStreamURL = nil
                }
            }
        }
        .task {
            await vm.loadCategory("trending")
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center) {
            HStack(spacing: 14) {
                Text("✠")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(TVGothicTheme.bloodHi)
                Text("YOUTUBE+ TV")
                    .font(TVGothicTheme.display(38))
                    .tracking(2.5)
                    .foregroundStyle(TVGothicTheme.bone)
                Text("4K60 HDR · AD-FREE · SPONSORBLOCK")
                    .font(TVGothicTheme.serif(16, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(TVGothicTheme.bloodHi)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TVGothicTheme.bloodDeep.opacity(0.75))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(TVGothicTheme.bloodHi, lineWidth: 1.2)
                    )
            }

            Spacer()

            HStack(spacing: 18) {
                Text("SPONSORS BANISHED: \(vm.skippedCount) (\(vm.skippedSecondsTotal)s)")
                    .font(TVGothicTheme.serif(16, weight: .semibold))
                    .foregroundStyle(TVGothicTheme.ash)

                Button {
                    Task { await vm.loadCategory(vm.selectedCategory) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("REFRESH")
                    }
                    .font(TVGothicTheme.serif(17, weight: .bold))
                    .foregroundStyle(TVGothicTheme.bone)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(TVGothicFocusButtonStyle(active: false, cornerRadius: 10))
            }
        }
        .padding(.horizontal, 48)
    }

    private var navigationRibbon: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(categories, id: \.id) { cat in
                    let active = vm.selectedCategory == cat.id
                    Button {
                        Task { await vm.loadCategory(cat.id) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 19, weight: .bold))
                                .foregroundStyle(active ? TVGothicTheme.bloodHi : TVGothicTheme.ash)
                            Text(cat.title)
                                .font(TVGothicTheme.serif(18, weight: .bold))
                                .tracking(1.0)
                                .foregroundStyle(active ? TVGothicTheme.bone : TVGothicTheme.ash)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                    }
                    .buttonStyle(TVGothicFocusButtonStyle(active: active, cornerRadius: 12))
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 6)
        }
    }

    private var searchBarView: some View {
        HStack(spacing: 18) {
            TextField("Search YouTube 4K60 (Voice or Keyboard)...", text: $vm.searchQuery)
                .font(TVGothicTheme.serif(22, weight: .semibold))
                .onSubmit {
                    Task { await vm.performSearch(vm.searchQuery) }
                }

            Button {
                Task { await vm.performSearch(vm.searchQuery) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("SUMMON")
                }
                .font(TVGothicTheme.serif(20, weight: .bold))
                .foregroundStyle(TVGothicTheme.bone)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
            }
            .buttonStyle(TVGothicFocusButtonStyle(active: true, cornerRadius: 12))
        }
        .padding(.horizontal, 48)
    }

    private func videoCard(_ item: YTVideoItem) -> some View {
        Button {
            Task { await vm.playVideo(item) }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: item.thumbnailURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        default:
                            ZStack {
                                TVGothicTheme.crypt
                                Image(systemName: "play.tv.fill")
                                    .font(.system(size: 42))
                                    .foregroundStyle(TVGothicTheme.bloodHi.opacity(0.6))
                            }
                            .aspectRatio(16.0 / 9.0, contentMode: .fill)
                        }
                    }
                    .frame(height: 270)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(item.duration)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(TVGothicTheme.bone)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(TVGothicTheme.void.opacity(0.88))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(TVGothicTheme.bloodHi, lineWidth: 1)
                        )
                        .padding(12)
                }

                Text(item.title)
                    .font(TVGothicTheme.serif(20, weight: .bold))
                    .foregroundStyle(TVGothicTheme.bone)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 54, alignment: .topLeading)

                HStack {
                    Text(item.channel)
                        .font(TVGothicTheme.serif(16, weight: .semibold))
                        .foregroundStyle(TVGothicTheme.bloodHi)
                        .lineLimit(1)
                    Spacer()
                    Text([item.views, item.published].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(TVGothicTheme.serif(15))
                        .foregroundStyle(TVGothicTheme.ash)
                        .lineLimit(1)
                }
            }
            .padding(16)
        }
        .buttonStyle(TVGothicFocusButtonStyle(active: false, cornerRadius: 16))
    }

    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("✠ YOUTUBE+ TV SANCTUM RITES (SPONSORBLOCK & 4K60)")
                    .font(TVGothicTheme.display(26))
                    .foregroundStyle(TVGothicTheme.bone)

                settingToggleRow(
                    title: "SponsorBlock Auto-Skip Engine",
                    subtitle: "Automatically seeks past paid sponsor segments in real time via sponsor.ajay.app",
                    isOn: $vm.sponsorBlockEnabled
                )
                settingToggleRow(
                    title: "Banish Paid Sponsor Reads (sponsor)",
                    subtitle: "Skips third-party paid product placements",
                    isOn: $vm.skipSponsors
                )
                settingToggleRow(
                    title: "Banish Self-Promos & Subscribe Reminders (selfpromo / interaction)",
                    subtitle: "Skips merch plugs, Patreon begs, and like/subscribe reminders",
                    isOn: $vm.skipSelfPromo
                )
                settingToggleRow(
                    title: "Banish Filler Intros & Endcards (intro / outro)",
                    subtitle: "Skips title animations and end-screen overlays",
                    isOn: $vm.skipIntrosOutros
                )
                settingToggleRow(
                    title: "Force 4K60 Ultra HD / HDR10 Maximum Resolution",
                    subtitle: "Prefers 3840×2160 60fps HLS variants on Apple TV 4K",
                    isOn: $vm.prefer4KHDR
                )
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 20)
        }
    }

    private func settingToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(TVGothicTheme.serif(22, weight: .bold))
                        .foregroundStyle(TVGothicTheme.bone)
                    Text(subtitle)
                        .font(TVGothicTheme.serif(16))
                        .foregroundStyle(TVGothicTheme.ash)
                }
                Spacer()
                Text(isOn.wrappedValue ? "ACTIVE ✠" : "DISABLED")
                    .font(TVGothicTheme.serif(18, weight: .bold))
                    .foregroundStyle(isOn.wrappedValue ? TVGothicTheme.bloodHi : TVGothicTheme.ash)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isOn.wrappedValue ? TVGothicTheme.bloodDeep : TVGothicTheme.void)
                    )
            }
            .padding(22)
        }
        .buttonStyle(TVGothicFocusButtonStyle(active: isOn.wrappedValue, cornerRadius: 14))
    }
}

@main
struct YouTubePlusTVApp: App {
    var body: some Scene {
        WindowGroup {
            YouTubePlusTVMainView()
        }
    }
}
