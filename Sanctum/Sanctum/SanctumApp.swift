import SwiftUI

// MARK: - Models

struct SanctumGlucosePoint: Identifiable, Codable {
    var id: Int { ts }
    let mmol: Double
    let mgdl: Int
    let ts: Int
}

struct SanctumT1D: Codable {
    var mmol: Double = 9.1
    var mgdl: Int = 163
    var deltaMmol: Double = 0.0
    var direction: String = "Flat"
    var arrow: String = "→"
    var updatedAgo: String = "Just now"
    var status: String = "IN RANGE"
    var iob: Double = 0.0
    var bolusIob: Double = 0.0
    var basalRate: Double = 0.85
    var pumpStatus: String = "Control-IQ Active"
    var pumpBattery: Int = 85
    var reservoir: Double = 140
    var history: [SanctumGlucosePoint] = []
}

struct SanctumArrItem: Identifiable, Codable {
    let id: String
    let source: String
    let title: String
    let quality: String
    let status: String
    let indexer: String
    let sizeMB: Int
    let progress: Int
}

struct SanctumMeTubeItem: Identifiable, Codable {
    let id: String
    let title: String
    var url: String? = ""
    var format: String? = "mp4"
    var quality: String? = "best"
    let status: String
}

struct SanctumDownloads: Codable {
    var speedMBs: Double = 0.0
    var avgSpeedMBs: Double = 14.6
    var remainingMB: Int = 0
    var downloadedTotalGB: Double = 1548.5
    var downloadedMonthGB: Double = 1428.7
    var downloadedTodayMB: Int = 2828
    var freeDiskGB: Double = 2445.0
    var paused: Bool = false
    var arrQueue: [SanctumArrItem] = []
    var metubeDone: [SanctumMeTubeItem] = []
    var metubeQueue: [SanctumMeTubeItem] = []
}

struct SanctumMediaItem: Identifiable, Codable, Equatable {
    let id: Int
    let mediaType: String
    let title: String
    let year: String
    let rating: Double
    let overview: String
    let posterURL: String
    let backdropURL: String
    var status: String
}

struct SanctumDiscover: Codable {
    var trending: [SanctumMediaItem] = []
}

struct SanctumCamera: Identifiable, Codable {
    let id: String
    let name: String
    let ip: String
    let hasPTZ: Bool
    let snapURL: String
}

struct SanctumTrueNASInfo: Codable {
    var hostname: String = "TrueNAS-SCALE"
    var ip: String = "100.64.0.4"
    var cpuPercent: Double = 12.5
    var ramPercent: Double = 58.2
    var poolName: String = "storage_pool"
    var poolStatus: String = "ONLINE"
    var containersRunning: Int = 68
    var appleTvIP: String = "192.168.0.62"
    var appleTvName: String = "Bedroom Apple TV 4K"
    var appleTvPaired: Bool = true
}

struct SanctumAlertBanner: Codable, Equatable {
    let id: String
    let title: String
    let message: String
    let timestamp: Int
}

struct SanctumBridgeState: Codable {
    var tvMode: String = "overview"
    var pinnedCamera: String = "both"
    var bedsideDim: Double = 0.20
    var alertBanner: SanctumAlertBanner? = nil
    var spotlight: SanctumMediaItem? = nil
    var lastInstallStatus: String? = "Ready"
    var updatedAt: Int? = 0
}

struct SanctumOverviewResponse: Codable {
    let ok: Bool
    let timestamp: Int?
    let t1d: SanctumT1D
    let downloads: SanctumDownloads
    let discover: SanctumDiscover
    let cameras: [SanctumCamera]
    let truenas: SanctumTrueNASInfo
    let bridge: SanctumBridgeState
}

struct SanctumSearchResponse: Codable {
    let ok: Bool
    let results: [SanctumMediaItem]
}

// MARK: - Gothic Cathedral Palette

enum SanctumTheme {
    static let voidBG = Color(red: 0.024, green: 0.024, blue: 0.035)
    static let cardBG = Color(red: 0.055, green: 0.039, blue: 0.068)
    static let raisedBG = Color(red: 0.086, green: 0.055, blue: 0.102)
    static let crimson = Color(red: 0.882, green: 0.114, blue: 0.282)
    static let darkCrimson = Color(red: 0.545, green: 0.067, blue: 0.180)
    static let gold = Color(red: 0.961, green: 0.620, blue: 0.043)
    static let emerald = Color(red: 0.063, green: 0.725, blue: 0.506)
    static let ivory = Color(red: 0.965, green: 0.945, blue: 0.925)
    static let ash = Color(red: 0.640, green: 0.595, blue: 0.625)
}

// MARK: - Shared ViewModel

@MainActor
final class SanctumStore: ObservableObject {
    @Published var t1d = SanctumT1D()
    @Published var downloads = SanctumDownloads()
    @Published var trending: [SanctumMediaItem] = []
    @Published var searchResults: [SanctumMediaItem] = []
    @Published var cameras: [SanctumCamera] = [
        SanctumCamera(id: "tapo_c200", name: "Living Room PTZ (Tapo C200)", ip: "192.168.0.41", hasPTZ: true, snapURL: "https://hs.nas-server.co.uk/sidestore-api/sanctum-hub?op=camera_snap&cam=tapo_c200"),
        SanctumCamera(id: "bike_camera", name: "Bike Area (Ezviz HD)", ip: "192.168.0.157", hasPTZ: false, snapURL: "https://hs.nas-server.co.uk/sidestore-api/sanctum-hub?op=camera_snap&cam=bike_camera")
    ]
    @Published var truenas = SanctumTrueNASInfo()
    @Published var bridge = SanctumBridgeState()
    @Published var cameraTick: Int = 0
    @Published var toastMessage: String? = nil
    @Published var activeAlertBanner: SanctumAlertBanner? = nil
    @Published var lastSeenAlertId: String = ""
    @Published var isSearching: Bool = false

    private let endpoints = [
        "https://hs.nas-server.co.uk/sidestore-api/sanctum-hub",
        "http://100.64.0.4:18998/sidestore-api/sanctum-hub"
    ]
    private var activeEndpointIndex = 0
    private var pollTimer: Timer?
    private var camTimer: Timer?

    var currentBaseURL: String {
        endpoints[activeEndpointIndex]
    }

    func startPolling(interval: TimeInterval) {
        Task { await refreshOverview() }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.refreshOverview()
            }
        }
        camTimer?.invalidate()
        camTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.cameraTick &+= 1
            }
        }
    }

    func refreshOverview() async {
        for offset in 0..<endpoints.count {
            let idx = (activeEndpointIndex + offset) % endpoints.count
            let base = endpoints[idx]
            guard let url = URL(string: "\(base)?op=overview") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 4.0
            req.setValue("Sanctum/1.0", forHTTPHeaderField: "User-Agent")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    let decoded = try JSONDecoder().decode(SanctumOverviewResponse.self, from: data)
                    if decoded.ok {
                        activeEndpointIndex = idx
                        self.t1d = decoded.t1d
                        self.downloads = decoded.downloads
                        if !decoded.discover.trending.isEmpty {
                            self.trending = decoded.discover.trending
                        }
                        if !decoded.cameras.isEmpty {
                            self.cameras = decoded.cameras
                        }
                        self.truenas = decoded.truenas
                        self.bridge = decoded.bridge

                        if let banner = decoded.bridge.alertBanner,
                           banner.id != self.lastSeenAlertId,
                           Int(Date().timeIntervalSince1970) - banner.timestamp < 30 {
                            self.lastSeenAlertId = banner.id
                            withAnimation(.spring()) {
                                self.activeAlertBanner = banner
                            }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 7_500_000_000)
                                if self.activeAlertBanner?.id == banner.id {
                                    withAnimation { self.activeAlertBanner = nil }
                                }
                            }
                        }
                        return
                    }
                }
            } catch {
                continue
            }
        }
    }

    func showToast(_ msg: String) {
        withAnimation { self.toastMessage = msg }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self.toastMessage == msg {
                withAnimation { self.toastMessage = nil }
            }
        }
    }

    func postAction(_ payload: [String: Any], toast: String? = nil) async {
        guard let url = URL(string: currentBaseURL),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Sanctum/1.0", forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        req.timeoutInterval = 6.0
        do {
            let _ = try await URLSession.shared.data(for: req)
            if let t = toast {
                showToast(t)
            }
            await refreshOverview()
        } catch {
            showToast("Action failed: \(error.localizedDescription)")
        }
    }

    func setTVMode(_ mode: String) {
        bridge.tvMode = mode
        Task {
            await postAction(["op": "set_bridge", "tvMode": mode], toast: "Bedroom TV → \(mode.uppercased())")
        }
    }

    func setBedsideDim(_ dim: Double) {
        bridge.bedsideDim = dim
        Task {
            await postAction(["op": "set_bridge", "bedsideDim": dim])
        }
    }

    func setPinnedCamera(_ cam: String) {
        bridge.pinnedCamera = cam
        Task {
            await postAction(["op": "set_bridge", "pinnedCamera": cam, "tvMode": "cameras"], toast: "Pinned \(cam) on Bedroom TV")
        }
    }

    func sendTVDecree(title: String, message: String) {
        Task {
            await postAction(["op": "set_bridge", "alertTitle": title, "alertMessage": message], toast: "Sent Decree to Bedroom TV")
        }
    }

    func spotlightOnTV(_ item: SanctumMediaItem) {
        let dict: [String: Any] = [
            "id": item.id,
            "mediaType": item.mediaType,
            "title": item.title,
            "year": item.year,
            "rating": item.rating,
            "overview": item.overview,
            "posterURL": item.posterURL,
            "backdropURL": item.backdropURL,
            "status": item.status
        ]
        Task {
            await postAction(["op": "set_bridge", "spotlight": dict, "tvMode": "cinema"], toast: "Beamed \(item.title) to Bedroom TV")
        }
    }

    func requestMedia(_ item: SanctumMediaItem) {
        Task {
            await postAction([
                "op": "request_media",
                "mediaId": item.id,
                "mediaType": item.mediaType,
                "title": item.title
            ], toast: "Requested \(item.title) on TrueNAS")
        }
    }

    func addMeTube(url: String, format: String = "mp4") {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            await postAction([
                "op": "metube_add",
                "url": url,
                "format": format,
                "quality": "best"
            ], toast: "Archiving to TrueNAS MeTube")
        }
    }

    func toggleNZBGet() {
        Task {
            await postAction(["op": "nzbget_toggle"], toast: downloads.paused ? "Resumed NZBGet" : "Paused NZBGet")
        }
    }

    func movePTZ(_ dir: String) {
        Task {
            await postAction(["op": "ptz", "dir": dir], toast: "PTZ → \(dir.uppercased())")
        }
    }

    func installTVApp(_ appKey: String) {
        Task {
            await postAction(["op": "install_tv_app", "app": appKey], toast: "Pushing \(appKey.uppercased()) TV to Bedroom Apple TV...")
        }
    }

    func searchMedia(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        guard let enc = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(currentBaseURL)?op=search&q=\(enc)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5.0
        req.setValue("Sanctum/1.0", forHTTPHeaderField: "User-Agent")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let decoded = try? JSONDecoder().decode(SanctumSearchResponse.self, from: data) {
            self.searchResults = decoded.results
        }
    }
}

// MARK: - Shared UI Components

struct SanctumGlucoseSparkline: View {
    let points: [SanctumGlucosePoint]
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            let vals = points.map(\.mmol)
            let minV = min(3.5, (vals.min() ?? 4.0) - 0.5)
            let maxV = max(13.0, (vals.max() ?? 10.0) + 0.5)
            let span = max(1.0, maxV - minV)

            ZStack {
                // Target range band (4.0 - 10.0 mmol/L)
                let yTop = geo.size.height * (1.0 - CGFloat((10.0 - minV) / span))
                let yBot = geo.size.height * (1.0 - CGFloat((4.0 - minV) / span))
                Rectangle()
                    .fill(SanctumTheme.emerald.opacity(0.10))
                    .frame(height: max(4, yBot - yTop))
                    .position(x: geo.size.width / 2, y: (yTop + yBot) / 2)

                if points.count > 1 {
                    Path { path in
                        for (idx, pt) in points.enumerated() {
                            let x = geo.size.width * CGFloat(idx) / CGFloat(max(1, points.count - 1))
                            let y = geo.size.height * (1.0 - CGFloat((pt.mmol - minV) / span))
                            if idx == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(colors: [SanctumTheme.gold, SanctumTheme.crimson], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                    )

                    ForEach(Array(points.enumerated()), id: \.offset) { idx, pt in
                        let x = geo.size.width * CGFloat(idx) / CGFloat(max(1, points.count - 1))
                        let y = geo.size.height * (1.0 - CGFloat((pt.mmol - minV) / span))
                        Circle()
                            .fill(pt.mmol > 10.0 ? SanctumTheme.gold : (pt.mmol < 4.0 ? SanctumTheme.crimson : SanctumTheme.emerald))
                            .frame(width: idx == points.count - 1 ? 10 : 6, height: idx == points.count - 1 ? 10 : 6)
                            .position(x: x, y: y)
                    }
                } else {
                    Text("Awaiting Dexcom G7 telemetry...")
                        .font(.caption)
                        .foregroundColor(SanctumTheme.ash)
                }
            }
        }
        .frame(height: height)
    }
}

struct SanctumLiveCameraView: View {
    let camera: SanctumCamera
    let tick: Int
    let height: CGFloat

    var body: some View {
        let sep = camera.snapURL.contains("?") ? "&" : "?"
        let liveURL = URL(string: "\(camera.snapURL)\(sep)t=\(tick / 2)")
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)

            if let url = liveURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color.black
                            ProgressView().tint(SanctumTheme.crimson)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(SanctumTheme.crimson)
                    .frame(width: 8, height: 8)
                Text(camera.name.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundColor(SanctumTheme.ivory)
                Spacer()
                Text(camera.ip)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(SanctumTheme.gold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.72))
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SanctumTheme.crimson.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - App Entry

@main
struct SanctumApp: App {
    @StateObject private var store = SanctumStore()

    var body: some Scene {
        WindowGroup {
            #if os(tvOS)
            SanctumTVRootView(store: store)
                .preferredColorScheme(.dark)
                .onAppear { store.startPolling(interval: 2.0) }
            #else
            SanctumIOSRootView(store: store)
                .preferredColorScheme(.dark)
                .onAppear { store.startPolling(interval: 4.0) }
            #endif
        }
    }
}

#if os(tvOS)
// MARK: - tvOS Big-Screen Apple TV 4K Interface

struct SanctumTVRootView: View {
    @ObservedObject var store: SanctumStore
    @State private var searchText: String = ""

    private let modes: [(id: String, label: String, icon: String)] = [
        ("overview", "SANCTUM WALL", "square.grid.2x2.fill"),
        ("bedside", "BEDSIDE HUD", "moon.stars.fill"),
        ("cinema", "CINEMA SEEKER", "film.stack.fill"),
        ("cameras", "SENTRY NVR", "video.fill"),
        ("downloads", "PIPELINE", "arrow.down.circle.fill")
    ]

    var body: some View {
        ZStack {
            SanctumTheme.voidBG.ignoresSafeArea()

            VStack(spacing: 18) {
                // Top Cathedral Header & Mode Switcher
                HStack(spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "flame.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(SanctumTheme.crimson)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SANCTUM TV")
                                .font(.system(size: 28, weight: .black, design: .serif))
                                .foregroundColor(SanctumTheme.ivory)
                            Text("TRUENAS SCALE · IPHONE BRIDGE LIVE")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(SanctumTheme.gold)
                        }
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        ForEach(modes, id: \.id) { m in
                            Button {
                                store.setTVMode(m.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: m.icon)
                                    Text(m.label)
                                        .font(.system(size: 16, weight: .bold, design: .serif))
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(store.bridge.tvMode == m.id ? SanctumTheme.crimson : SanctumTheme.cardBG)
                                )
                                .foregroundColor(SanctumTheme.ivory)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)

                // Active Mode Content
                Group {
                    switch store.bridge.tvMode {
                    case "bedside":
                        SanctumTVBedsideView(store: store)
                    case "cinema":
                        SanctumTVCinemaView(store: store, searchText: $searchText)
                    case "cameras":
                        SanctumTVCamerasView(store: store)
                    case "downloads":
                        SanctumTVDownloadsView(store: store)
                    default:
                        SanctumTVOverviewWall(store: store)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 24)
            }

            // OLED Dimmer Overlay when in Bedside mode
            if store.bridge.tvMode == "bedside" && store.bridge.bedsideDim > 0.01 {
                Color.black
                    .opacity(min(0.85, max(0.0, store.bridge.bedsideDim)))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Live Alert Decree Banner Overlay from iPhone
            if let alert = store.activeAlertBanner {
                VStack {
                    HStack(spacing: 18) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 34))
                            .foregroundColor(SanctumTheme.gold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alert.title.uppercased())
                                .font(.system(size: 22, weight: .black, design: .serif))
                                .foregroundColor(SanctumTheme.gold)
                            Text(alert.message)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(SanctumTheme.ivory)
                        }
                        Spacer()
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(SanctumTheme.raisedBG)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(SanctumTheme.crimson, lineWidth: 2)
                            )
                    )
                    .shadow(color: SanctumTheme.crimson.opacity(0.6), radius: 24)
                    .padding(.horizontal, 80)
                    .padding(.top, 30)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

struct SanctumTVOverviewWall: View {
    @ObservedObject var store: SanctumStore

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                // Top-Left: Nightscout T1D Blood Glucose & Tandem Pump Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("DEXCOM G7 & TANDEM t:slim X2", systemImage: "waveform.path.ecg")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundColor(SanctumTheme.gold)
                        Spacer()
                        Text(store.t1d.updatedAgo.uppercased())
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(SanctumTheme.ash)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text(String(format: "%.1f %@", store.t1d.mmol, store.t1d.arrow))
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundColor(store.t1d.mmol > 10.0 ? SanctumTheme.gold : (store.t1d.mmol < 4.0 ? SanctumTheme.crimson : SanctumTheme.emerald))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%+.1f mmol/L · %d mg/dL", store.t1d.deltaMmol, store.t1d.mgdl))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(SanctumTheme.ivory)
                            Text("\(store.t1d.pumpStatus) · IOB \(String(format: "%.2f U", store.t1d.iob)) · Bat \(store.t1d.pumpBattery)%")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(SanctumTheme.ash)
                        }
                        Spacer()
                    }
                    SanctumGlucoseSparkline(points: store.t1d.history, height: 110)
                }
                .padding(22)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 18).fill(SanctumTheme.cardBG))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(SanctumTheme.crimson.opacity(0.35), lineWidth: 1))

                // Top-Right: Live Dual Frigate Security Cameras
                HStack(spacing: 14) {
                    ForEach(store.cameras) { cam in
                        SanctumLiveCameraView(camera: cam, tick: store.cameraTick, height: 245)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 20) {
                // Bottom-Left: NZBGet + Arr Queue + TrueNAS ZFS Summary
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("USENET & *ARR PIPELINE", systemImage: "externaldrive.fill.badge.wifi")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundColor(SanctumTheme.crimson)
                        Spacer()
                        Text(String(format: "ZFS %.0f GB FREE · %d CONTAINERS", store.downloads.freeDiskGB, store.truenas.containersRunning))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(SanctumTheme.emerald)
                    }
                    HStack(spacing: 22) {
                        VStack(alignment: .leading) {
                            Text(String(format: "%.1f MB/s", store.downloads.avgSpeedMBs))
                                .font(.system(size: 28, weight: .black, design: .monospaced))
                                .foregroundColor(SanctumTheme.ivory)
                            Text("AVG USENET RATE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(SanctumTheme.ash)
                        }
                        VStack(alignment: .leading) {
                            Text(String(format: "%.1f TB", store.downloads.downloadedMonthGB / 1024.0))
                                .font(.system(size: 28, weight: .black, design: .monospaced))
                                .foregroundColor(SanctumTheme.gold)
                            Text("THIS MONTH")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(SanctumTheme.ash)
                        }
                        VStack(alignment: .leading) {
                            Text("\(store.downloads.arrQueue.count) ITEMS")
                                .font(.system(size: 28, weight: .black, design: .monospaced))
                                .foregroundColor(SanctumTheme.crimson)
                            Text("SONARR / RADARR")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(SanctumTheme.ash)
                        }
                    }
                    ForEach(store.downloads.arrQueue.prefix(3)) { item in
                        HStack {
                            Text(item.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(SanctumTheme.ivory)
                                .lineLimit(1)
                            Spacer()
                            Text(item.quality)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(SanctumTheme.gold)
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 18).fill(SanctumTheme.cardBG))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(SanctumTheme.crimson.opacity(0.35), lineWidth: 1))

                // Bottom-Right: Jellyseerr Trending Quick Strip
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("JELLYSEERR TRENDING · CLICK TO REQUEST", systemImage: "sparkles.tv.fill")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundColor(SanctumTheme.gold)
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(store.trending.prefix(8)) { media in
                                Button {
                                    store.requestMedia(media)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        AsyncImage(url: URL(string: media.posterURL)) { phase in
                                            if let img = phase.image {
                                                img.resizable().scaledToFill()
                                            } else {
                                                Color.black
                                            }
                                        }
                                        .frame(width: 115, height: 155)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        Text(media.title)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(SanctumTheme.ivory)
                                            .frame(width: 115, alignment: .leading)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 18).fill(SanctumTheme.cardBG))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(SanctumTheme.crimson.opacity(0.35), lineWidth: 1))
            }
        }
    }
}

struct SanctumTVBedsideView: View {
    @ObservedObject var store: SanctumStore

    var body: some View {
        HStack(spacing: 28) {
            // Left: Giant Bedside Glucose + Sparkline + Pump Status
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(Date(), style: .time)
                        .font(.system(size: 46, weight: .black, design: .serif))
                        .foregroundColor(SanctumTheme.ivory)
                    Spacer()
                    Text("OLED BEDSIDE SANCTUM · \(store.t1d.updatedAgo.uppercased())")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(SanctumTheme.gold)
                }

                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Text(String(format: "%.1f %@", store.t1d.mmol, store.t1d.arrow))
                        .font(.system(size: 118, weight: .black, design: .rounded))
                        .foregroundColor(store.t1d.mmol > 10.0 ? SanctumTheme.gold : (store.t1d.mmol < 4.0 ? SanctumTheme.crimson : SanctumTheme.emerald))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: "DELTA %+.1f mmol/L", store.t1d.deltaMmol))
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(SanctumTheme.ivory)
                        Text("\(store.t1d.mgdl) mg/dL · \(store.t1d.status)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(SanctumTheme.crimson)
                    }
                }

                SanctumGlucoseSparkline(points: store.t1d.history, height: 190)

                HStack(spacing: 18) {
                    ForEach([
                        ("TANDEM PUMP", store.t1d.pumpStatus),
                        ("ACTIVE IOB", String(format: "%.2f U", store.t1d.iob)),
                        ("PUMP BATTERY", "\(store.t1d.pumpBattery)%"),
                        ("RESERVOIR", String(format: "%.0f U", store.t1d.reservoir))
                    ], id: \.0) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.0)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(SanctumTheme.ash)
                            Text(item.1)
                                .font(.system(size: 20, weight: .black, design: .serif))
                                .foregroundColor(SanctumTheme.gold)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(SanctumTheme.raisedBG))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 22).fill(SanctumTheme.cardBG))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(SanctumTheme.crimson.opacity(0.45), lineWidth: 1.5))

            // Right: Live Nightstand Security Cameras Stack
            VStack(spacing: 18) {
                ForEach(store.cameras) { cam in
                    SanctumLiveCameraView(camera: cam, tick: store.cameraTick, height: 270)
                }
            }
            .frame(width: 520)
        }
    }
}

struct SanctumTVCinemaView: View {
    @ObservedObject var store: SanctumStore
    @Binding var searchText: String

    var body: some View {
        let hero = store.bridge.spotlight ?? store.trending.first
        VStack(alignment: .leading, spacing: 18) {
            if let h = hero {
                HStack(spacing: 24) {
                    AsyncImage(url: URL(string: h.posterURL)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            Color.black
                        }
                    }
                    .frame(width: 170, height: 245)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("SPOTLIGHT ON BEDROOM TV")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(SanctumTheme.crimson))
                            Text("\(h.mediaType.uppercased()) · \(h.year) · ★ \(String(format: "%.1f", h.rating)) · \(h.status.uppercased())")
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundColor(SanctumTheme.gold)
                        }
                        Text(h.title)
                            .font(.system(size: 36, weight: .black, design: .serif))
                            .foregroundColor(SanctumTheme.ivory)
                        Text(h.overview)
                            .font(.system(size: 16))
                            .foregroundColor(SanctumTheme.ash)
                            .lineLimit(3)
                        Button {
                            store.requestMedia(h)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.down.to.line.circle.fill")
                                Text("REQUEST ON TRUENAS (JELLYSEERR → RADARR/SONARR)")
                                    .font(.system(size: 16, weight: .black, design: .serif))
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(SanctumTheme.crimson))
                            .foregroundColor(SanctumTheme.ivory)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(22)
                .background(RoundedRectangle(cornerRadius: 20).fill(SanctumTheme.cardBG))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(SanctumTheme.crimson.opacity(0.45), lineWidth: 1))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(store.trending) { item in
                        Button {
                            store.spotlightOnTV(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncImage(url: URL(string: item.posterURL)) { phase in
                                    if let img = phase.image {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Color.black
                                    }
                                }
                                .frame(width: 155, height: 225)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(item.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(SanctumTheme.ivory)
                                    .frame(width: 155, alignment: .leading)
                                    .lineLimit(1)
                                Text("\(item.year) · \(item.status)")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(SanctumTheme.gold)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct SanctumTVCamerasView: View {
    @ObservedObject var store: SanctumStore

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 20) {
                ForEach(store.cameras) { cam in
                    if store.bridge.pinnedCamera == "both" || store.bridge.pinnedCamera == cam.id {
                        SanctumLiveCameraView(camera: cam, tick: store.cameraTick, height: 470)
                    }
                }
            }

            HStack(spacing: 16) {
                Text("TAPO C200 PTZ & LAYOUT:")
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundColor(SanctumTheme.gold)
                ForEach([
                    ("left", "PAN LEFT", "arrow.left"),
                    ("right", "PAN RIGHT", "arrow.right"),
                    ("up", "TILT UP", "arrow.up"),
                    ("down", "TILT DOWN", "arrow.down")
                ], id: \.0) { btn in
                    Button {
                        store.movePTZ(btn.0)
                    } label: {
                        Label(btn.1, systemImage: btn.2)
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(SanctumTheme.cardBG))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                ForEach([("both", "DUAL SPLIT"), ("tapo_c200", "LIVING ROOM FULL"), ("bike_camera", "BIKE AREA FULL")], id: \.0) { mode in
                    Button {
                        store.setPinnedCamera(mode.0)
                    } label: {
                        Text(mode.1)
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(store.bridge.pinnedCamera == mode.0 ? SanctumTheme.crimson : SanctumTheme.cardBG))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SanctumTVDownloadsView: View {
    @ObservedObject var store: SanctumStore

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("NZBGET & SONARR / RADARR QUEUE")
                        .font(.system(size: 20, weight: .black, design: .serif))
                        .foregroundColor(SanctumTheme.gold)
                    Spacer()
                    Button {
                        store.toggleNZBGet()
                    } label: {
                        Text(store.downloads.paused ? "RESUME NZBGET" : "PAUSE NZBGET")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(SanctumTheme.crimson))
                    }
                    .buttonStyle(.plain)
                }

                ForEach(store.downloads.arrQueue) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(SanctumTheme.ivory)
                                .lineLimit(1)
                            Text("\(item.source) · \(item.quality) · \(item.indexer) · \(item.sizeMB) MB")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(SanctumTheme.ash)
                        }
                        Spacer()
                        Text("\(item.progress)%")
                            .font(.system(size: 18, weight: .black, design: .monospaced))
                            .foregroundColor(SanctumTheme.emerald)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(SanctumTheme.raisedBG))
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(SanctumTheme.cardBG))

            VStack(alignment: .leading, spacing: 14) {
                Text("METUBE ARCHIVED STREAMS ON TRUENAS")
                    .font(.system(size: 20, weight: .black, design: .serif))
                    .foregroundColor(SanctumTheme.crimson)
                ForEach(store.downloads.metubeDone) { video in
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(SanctumTheme.crimson)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(video.title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(SanctumTheme.ivory)
                                .lineLimit(1)
                            Text("\((video.format ?? "mp4").uppercased()) · \((video.quality ?? "best").uppercased()) · \(video.status.uppercased())")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(SanctumTheme.gold)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(SanctumTheme.raisedBG))
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18).fill(SanctumTheme.cardBG))
        }
    }
}

#else
// MARK: - iOS iPhone Companion & TV Bridge Interface

struct SanctumIOSRootView: View {
    @ObservedObject var store: SanctumStore
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                SanctumIOSTVBridgeTab(store: store)
                    .tabItem { Label("TV Bridge", systemImage: "tv.and.mediabox") }
                    .tag(0)

                SanctumIOSSeekerTab(store: store)
                    .tabItem { Label("Seeker", systemImage: "film.stack.fill") }
                    .tag(1)

                SanctumIOSPipelineTab(store: store)
                    .tabItem { Label("Pipeline", systemImage: "arrow.down.circle.fill") }
                    .tag(2)

                SanctumIOSNightscoutTab(store: store)
                    .tabItem { Label("Nightscout", systemImage: "waveform.path.ecg") }
                    .tag(3)

                SanctumIOSSentryTab(store: store)
                    .tabItem { Label("Sentry", systemImage: "video.fill") }
                    .tag(4)
            }
            .tint(SanctumTheme.crimson)

            if let toast = store.toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundColor(SanctumTheme.ivory)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(SanctumTheme.crimson))
                    .shadow(color: .black.opacity(0.5), radius: 10)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

struct SanctumIOSTVBridgeTab: View {
    @ObservedObject var store: SanctumStore
    @State private var decreeTitle: String = "SANCTUM ALERT"
    @State private var decreeMessage: String = ""

    private let tvModes: [(String, String, String, String)] = [
        ("overview", "Sanctum 4-Quadrant Wall", "Glucose, Dual Cameras, Usenet & Cinema", "square.grid.2x2.fill"),
        ("bedside", "OLED Bedside T1D & Cameras", "Giant Nightstand CGM + Pump + Cameras", "moon.stars.fill"),
        ("cinema", "Cinema Seeker & Spotlight", "Jellyseerr Discovery & Fullscreen Hero", "film.stack.fill"),
        ("cameras", "Sentry Dual-Camera Wall", "Live Tapo C200 PTZ & Ezviz Bike Feed", "video.fill"),
        ("downloads", "Usenet & MeTube Wall", "NZBGet Speed, Sonarr Queue & MeTube", "arrow.down.circle.fill")
    ]

    private let tvApps: [(String, String, String)] = [
        ("sanctum", "Sanctum TV", "Unified Wall, Bedside T1D & Phone Bridge"),
        ("hearth", "Hearth TV", "Jellyfin Cinema & Navidrome Audio Hub"),
        ("immich", "Immich TV", "4K Photo Memories & Slideshow Vault"),
        ("sentrycam", "SentryCam TV", "Frigate Dual Security Wall & PTZ"),
        ("keepwatch", "Keepwatch TV", "TrueNAS ZFS, Docker & Ops Deck"),
        ("starkstore", "Stark Store TV", "Gothic App Catalog & Signing Status"),
        ("youtubeplus", "YouTube+ TV", "Ad-Free 4K60 HDR & SponsorBlock")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Banner
                    HStack(spacing: 14) {
                        Image(systemName: "appletv.fill")
                            .font(.system(size: 36))
                            .foregroundColor(SanctumTheme.crimson)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.truenas.appleTvName.uppercased())
                                .font(.system(size: 16, weight: .black, design: .serif))
                                .foregroundColor(SanctumTheme.ivory)
                            Text("IP \(store.truenas.appleTvIP) · MODE: \(store.bridge.tvMode.uppercased())")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(SanctumTheme.gold)
                        }
                        Spacer()
                        Circle()
                            .fill(SanctumTheme.emerald)
                            .frame(width: 10, height: 10)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(SanctumTheme.cardBG))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(SanctumTheme.crimson.opacity(0.4), lineWidth: 1))

                    // 1-Tap Bedroom Apple TV Screen Mode Switcher
                    Text("SWITCH BEDROOM APPLE TV SCREEN MODE")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(SanctumTheme.gold)

                    ForEach(tvModes, id: \.0) { mode in
                        Button {
                            store.setTVMode(mode.0)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: mode.3)
                                    .font(.system(size: 22))
                                    .foregroundColor(store.bridge.tvMode == mode.0 ? SanctumTheme.ivory : SanctumTheme.crimson)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.1)
                                        .font(.system(size: 15, weight: .bold, design: .serif))
                                        .foregroundColor(SanctumTheme.ivory)
                                    Text(mode.2)
                                        .font(.system(size: 12))
                                        .foregroundColor(SanctumTheme.ash)
                                }
                                Spacer()
                                if store.bridge.tvMode == mode.0 {
                                    Text("LIVE ON TV")
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(SanctumTheme.crimson))
                                        .foregroundColor(SanctumTheme.ivory)
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(store.bridge.tvMode == mode.0 ? SanctumTheme.raisedBG : SanctumTheme.cardBG))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(store.bridge.tvMode == mode.0 ? SanctumTheme.crimson : SanctumTheme.crimson.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    // Bedside OLED Night Dimmer Slider
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("BEDSIDE TV OLED NIGHT DIMMER", systemImage: "moon.zzz.fill")
                                .font(.system(size: 13, weight: .bold, design: .serif))
                                .foregroundColor(SanctumTheme.gold)
                            Spacer()
                            Text("\(Int(store.bridge.bedsideDim * 100))% DIM")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(SanctumTheme.ivory)
                        }
                        Slider(value: Binding(
                            get: { store.bridge.bedsideDim },
                            set: { store.setBedsideDim($0) }
                        ), in: 0.0...0.85, step: 0.05)
                        .tint(SanctumTheme.crimson)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(SanctumTheme.cardBG))

                    // Flash Decree Alert Banner to Apple TV
                    VStack(alignment: .leading, spacing: 10) {
                        Label("FLASH DECREE BANNER ON APPLE TV", systemImage: "bell.badge.waveform.fill")
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .foregroundColor(SanctumTheme.crimson)

                        TextField("Message to display on Bedroom Apple TV...", text: $decreeMessage)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 8) {
                            Button {
                                let msg = decreeMessage.isEmpty ? "Check Dexcom G7 (\(String(format: "%.1f", store.t1d.mmol)) mmol/L \(store.t1d.arrow))" : decreeMessage
                                store.sendTVDecree(title: decreeTitle, message: msg)
                                decreeMessage = ""
                            } label: {
                                Text("Flash on Bedroom TV")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(SanctumTheme.crimson))
                                    .foregroundColor(SanctumTheme.ivory)
                            }
                            Button {
                                store.sendTVDecree(title: "T1D GLUCOSE CHECK", message: "Dexcom G7: \(String(format: "%.1f", store.t1d.mmol)) mmol/L \(store.t1d.arrow) · IOB \(String(format: "%.2f", store.t1d.iob))U")
                            } label: {
                                Text("Beam CGM")
                                    .font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(SanctumTheme.raisedBG))
                                    .foregroundColor(SanctumTheme.gold)
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(SanctumTheme.cardBG))

                    // Wireless Apple TV App Installer (TrueNAS atvloadly)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("WIRELESS APPLE TV APP INSTALLER", systemImage: "arrow.up.doc.on.clipboard")
                                .font(.system(size: 13, weight: .bold, design: .serif))
                                .foregroundColor(SanctumTheme.gold)
                            Spacer()
                        }
                        if let st = store.bridge.lastInstallStatus {
                            Text("Status: \(st)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(SanctumTheme.emerald)
                        }
                        ForEach(tvApps, id: \.0) { app in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.1)
                                        .font(.system(size: 14, weight: .bold, design: .serif))
                                        .foregroundColor(SanctumTheme.ivory)
                                    Text(app.2)
                                        .font(.system(size: 11))
                                        .foregroundColor(SanctumTheme.ash)
                                }
                                Spacer()
                                Button {
                                    store.installTVApp(app.0)
                                } label: {
                                    Text("Push to TV")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(SanctumTheme.crimson))
                                        .foregroundColor(SanctumTheme.ivory)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(SanctumTheme.cardBG))
                }
                .padding(16)
            }
            .background(SanctumTheme.voidBG.ignoresSafeArea())
            .navigationTitle("Sanctum TV Bridge")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SanctumIOSSeekerTab: View {
    @ObservedObject var store: SanctumStore
    @State private var query: String = ""

    var displayedItems: [SanctumMediaItem] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? store.trending : store.searchResults
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(SanctumTheme.crimson)
                        TextField("Search Movies & TV Shows (Jellyseerr)...", text: $query)
                            .onSubmit {
                                Task { await store.searchMedia(query) }
                            }
                        if !query.isEmpty {
                            Button {
                                query = ""
                                store.searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(SanctumTheme.ash)
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(SanctumTheme.cardBG))

                    ForEach(displayedItems) { item in
                        HStack(alignment: .top, spacing: 14) {
                            AsyncImage(url: URL(string: item.posterURL)) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                } else {
                                    Color.black
                                }
                            }
                            .frame(width: 85, height: 126)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.mediaType.uppercased())
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(SanctumTheme.crimson))
                                    Text("\(item.year) · ★ \(String(format: "%.1f", item.rating))")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(SanctumTheme.gold)
                                    Spacer()
                                    Text(item.status)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(item.status == "Available" ? SanctumTheme.emerald : SanctumTheme.ash)
                                }
                                Text(item.title)
                                    .font(.system(size: 16, weight: .bold, design: .serif))
                                    .foregroundColor(SanctumTheme.ivory)
                                    .lineLimit(1)
                                Text(item.overview)
                                    .font(.system(size: 12))
                                    .foregroundColor(SanctumTheme.ash)
                                    .lineLimit(2)

                                HStack(spacing: 8) {
                                    Button {
                                        store.requestMedia(item)
                                    } label: {
                                        Label("Request", systemImage: "arrow.down.circle.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(Capsule().fill(SanctumTheme.crimson))
                                            .foregroundColor(SanctumTheme.ivory)
                                    }
                                    Button {
                                        store.spotlightOnTV(item)
                                    } label: {
                                        Label("Beam to TV", systemImage: "tv.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(Capsule().fill(SanctumTheme.raisedBG))
                                            .foregroundColor(SanctumTheme.gold)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(SanctumTheme.cardBG))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SanctumTheme.crimson.opacity(0.25), lineWidth: 1))
                    }
                }
                .padding(16)
            }
            .background(SanctumTheme.voidBG.ignoresSafeArea())
            .navigationTitle("Cinema Seeker")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SanctumIOSPipelineTab: View {
    @ObservedObject var store: SanctumStore
    @State private var videoURL: String = ""
    @State private var videoFormat: String = "mp4"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // NZBGet Summary Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("NZBGET USENET ENGINE", systemImage: "bolt.horizontal.circle.fill")
                                .font(.system(size: 13, weight: .black, design: .serif))
                                .foregroundColor(SanctumTheme.gold)
                            Spacer()
                            Button {
                                store.toggleNZBGet()
                            } label: {
                                Text(store.downloads.paused ? "RESUME" : "PAUSE")
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(SanctumTheme.crimson))
                                    .foregroundColor(SanctumTheme.ivory)
                            }
                        }
                        HStack(spacing: 16) {
                            VStack(alignment: .leading) {
                                Text(String(format: "%.1f MB/s", store.downloads.avgSpeedMBs))
                                    .font(.system(size: 22, weight: .black, design: .monospaced))
                                    .foregroundColor(SanctumTheme.ivory)
                                Text("AVG SPEED")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(SanctumTheme.ash)
                            }
                            VStack(alignment: .leading) {
                                Text(String(format: "%.1f TB", store.downloads.downloadedMonthGB / 1024.0))
                                    .font(.system(size: 22, weight: .black, design: .monospaced))
                                    .foregroundColor(SanctumTheme.gold)
                                Text("MONTH")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(SanctumTheme.ash)
                            }
                            VStack(alignment: .leading) {
                                Text(String(format: "%.2f TB", store.downloads.freeDiskGB / 1024.0))
                                    .font(.system(size: 22, weight: .black, design: .monospaced))
                                    .foregroundColor(SanctumTheme.emerald)
                                Text("ZFS FREE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(SanctumTheme.ash)
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(SanctumTheme.cardBG))

                    // MeTube Video/YouTube Archiver to TrueNAS
                    VStack(alignment: .leading, spacing: 10) {
                        Label("METUBE STREAM ARCHIVER TO TRUENAS", systemImage: "play.square.stack.fill")
                            .font(.system(size: 13, weight: .black, design: .serif))
                            .foregroundColor(SanctumTheme.crimson)
                        TextField("Paste YouTube / Video URL to archive on NAS...", text: $videoURL)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Picker("Format", selection: $videoFormat) {
                                Text("MP4 Video").tag("mp4")
                                Text("MP3 Audio").tag("mp3")
                            }
                            .pickerStyle(.segmented)
                            Button {
                                store.addMeTube(url: videoURL, format: videoFormat)
                                videoURL = ""
                            } label: {
                                Text("Archive")
                                    .font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(SanctumTheme.crimson))
                                    .foregroundColor(SanctumTheme.ivory)
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(SanctumTheme.cardBG))

                    // Sonarr / Radarr Active Queue
                    Text("SONARR / RADARR ACTIVE QUEUE (\(store.downloads.arrQueue.count))")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(SanctumTheme.gold)

                    ForEach(store.downloads.arrQueue) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(SanctumTheme.ivory)
                                .lineLimit(2)
                            HStack {
                                Text("\(item.source) · \(item.quality) · \(item.indexer)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(SanctumTheme.gold)
                                Spacer()
                                Text("\(item.sizeMB) MB · \(item.progress)%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(SanctumTheme.emerald)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(SanctumTheme.cardBG))
                    }

                    // MeTube Recent Completed
                    Text("METUBE ARCHIVED VIDEOS (\(store.downloads.metubeDone.count))")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(SanctumTheme.crimson)

                    ForEach(store.downloads.metubeDone) { item in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(SanctumTheme.emerald)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(SanctumTheme.ivory)
                                    .lineLimit(1)
                                Text("\((item.format ?? "mp4").uppercased()) · \(item.status.uppercased())")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(SanctumTheme.ash)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(SanctumTheme.cardBG))
                    }
                }
                .padding(16)
            }
            .background(SanctumTheme.voidBG.ignoresSafeArea())
            .navigationTitle("Acquisition Pipeline")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SanctumIOSNightscoutTab: View {
    @ObservedObject var store: SanctumStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("DEXCOM G7 DIRECT BLE", systemImage: "drop.fill")
                                .font(.system(size: 13, weight: .black, design: .serif))
                                .foregroundColor(SanctumTheme.crimson)
                            Spacer()
                            Text(store.t1d.updatedAgo.uppercased())
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(SanctumTheme.gold)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(String(format: "%.1f %@", store.t1d.mmol, store.t1d.arrow))
                                .font(.system(size: 62, weight: .black, design: .rounded))
                                .foregroundColor(store.t1d.mmol > 10.0 ? SanctumTheme.gold : (store.t1d.mmol < 4.0 ? SanctumTheme.crimson : SanctumTheme.emerald))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(format: "%+.1f mmol/L", store.t1d.deltaMmol))
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(SanctumTheme.ivory)
                                Text("\(store.t1d.mgdl) mg/dL · \(store.t1d.status)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(SanctumTheme.ash)
                            }
                        }

                        SanctumGlucoseSparkline(points: store.t1d.history, height: 160)
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 18).fill(SanctumTheme.cardBG))

                    // Tandem t:slim X2 Pump Telemetry
                    VStack(alignment: .leading, spacing: 10) {
                        Label("TANDEM t:slim X2 · TCONNECTSYNC", systemImage: "heart.text.square.fill")
                            .font(.system(size: 13, weight: .black, design: .serif))
                            .foregroundColor(SanctumTheme.gold)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach([
                                ("CONTROL-IQ", store.t1d.pumpStatus),
                                ("ACTIVE IOB", String(format: "%.2f U", store.t1d.iob)),
                                ("PUMP BATTERY", "\(store.t1d.pumpBattery)%"),
                                ("RESERVOIR", String(format: "%.0f U", store.t1d.reservoir))
                            ], id: \.0) { stat in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stat.0)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(SanctumTheme.ash)
                                    Text(stat.1)
                                        .font(.system(size: 16, weight: .black, design: .serif))
                                        .foregroundColor(SanctumTheme.ivory)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(SanctumTheme.raisedBG))
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(SanctumTheme.cardBG))

                    Button {
                        store.setTVMode("bedside")
                    } label: {
                        HStack {
                            Image(systemName: "moon.stars.fill")
                            Text("PROJECT OLED BEDSIDE HUD TO BEDROOM TV")
                                .font(.system(size: 14, weight: .black, design: .serif))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(SanctumTheme.crimson))
                        .foregroundColor(SanctumTheme.ivory)
                    }
                }
                .padding(16)
            }
            .background(SanctumTheme.voidBG.ignoresSafeArea())
            .navigationTitle("Nightscout T1D")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SanctumIOSSentryTab: View {
    @ObservedObject var store: SanctumStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(store.cameras) { cam in
                        VStack(alignment: .leading, spacing: 10) {
                            SanctumLiveCameraView(camera: cam, tick: store.cameraTick, height: 215)
                            HStack {
                                Button {
                                    store.setPinnedCamera(cam.id)
                                } label: {
                                    Label("Pin Fullscreen on Bedroom TV", systemImage: "tv.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(SanctumTheme.crimson))
                                        .foregroundColor(SanctumTheme.ivory)
                                }
                                Spacer()
                                Button {
                                    store.setPinnedCamera("both")
                                } label: {
                                    Text("Dual Split on TV")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(SanctumTheme.raisedBG))
                                        .foregroundColor(SanctumTheme.gold)
                                }
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(SanctumTheme.cardBG))
                    }

                    // Tapo C200 PTZ Directional Controller
                    VStack(alignment: .leading, spacing: 12) {
                        Label("TAPO C200 LIVING ROOM PTZ CONTROL", systemImage: "dpad.fill")
                            .font(.system(size: 13, weight: .black, design: .serif))
                            .foregroundColor(SanctumTheme.gold)

                        HStack(spacing: 10) {
                            ForEach([
                                ("left", "Left", "arrow.left"),
                                ("up", "Up", "arrow.up"),
                                ("down", "Down", "arrow.down"),
                                ("right", "Right", "arrow.right")
                            ], id: \.0) { btn in
                                Button {
                                    store.movePTZ(btn.0)
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: btn.2)
                                            .font(.system(size: 18, weight: .bold))
                                        Text(btn.1)
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(SanctumTheme.raisedBG))
                                    .foregroundColor(SanctumTheme.ivory)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(SanctumTheme.cardBG))
                }
                .padding(16)
            }
            .background(SanctumTheme.voidBG.ignoresSafeArea())
            .navigationTitle("Sentry Cameras")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
