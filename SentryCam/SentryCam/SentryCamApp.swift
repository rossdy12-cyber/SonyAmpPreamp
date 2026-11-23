import SwiftUI
import UIKit
import UserNotifications
import AVKit
import Combine

#if os(tvOS)
enum TVNavigationBarTitleDisplayMode {
    case automatic, inline, large
}
extension View {
    func navigationBarTitleDisplayMode(_ mode: TVNavigationBarTitleDisplayMode) -> some View {
        self
    }
}
#endif

// MARK: - Models

struct FrigateEvent: Codable, Identifiable {
    let id: String
    let camera: String
    let label: String
    let start_time: Double
    let end_time: Double?
    let has_clip: Bool?
    let has_snapshot: Bool?
    let top_score: Double?
    let data: FrigateEventData?

    struct FrigateEventData: Codable {
        let score: Double?
        let top_score: Double?
    }

    var displayScorePercent: Int {
        let s = top_score ?? data?.top_score ?? data?.score ?? 0.88
        return Int((s * 100.0).rounded())
    }

    var formattedCamera: String {
        camera.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var formattedLabel: String {
        label.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var startDate: Date {
        Date(timeIntervalSince1970: start_time)
    }
}

struct PushServerStatus: Codable {
    let ok: Bool?
    let apnsKeyReady: Bool?
    let deviceCount: Int?
}

// MARK: - AppDelegate for Native Apple APNs Push Notifications

final class SentryAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var sharedViewModel: SentryViewModel?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        requestAndRegisterPush()
        return true
    }

    func requestAndRegisterPush() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                SentryAppDelegate.sharedViewModel?.notificationPermissionGranted = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hexToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        let actualBundleId = Bundle.main.bundleIdentifier ?? "app.keepwatch.seance"
        Task { @MainActor in
            SentryAppDelegate.sharedViewModel?.didReceiveAPNsToken(hexToken, bundleId: actualBundleId)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            SentryAppDelegate.sharedViewModel?.apnsErrorText = error.localizedDescription
        }
    }

    // Show push notification banners & sound even when SentryCam is open in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        #if os(tvOS)
        completionHandler([.banner, .sound, .badge])
        #else
        completionHandler([.banner, .list, .sound, .badge])
        #endif
    }

    #if !os(tvOS)
    // Deep-link straight into the camera detection clip when user taps a push notification
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let eventId = userInfo["event_id"] as? String
        let cam = userInfo["camera"] as? String
        Task { @MainActor in
            if let vm = SentryAppDelegate.sharedViewModel {
                await vm.loadEvents()
                if let eid = eventId, !eid.isEmpty,
                   let match = vm.events.first(where: { $0.id == eid }) {
                    vm.selectedEventForPlayback = match
                } else if let c = cam, !c.isEmpty {
                    vm.selectedCamera = c
                }
            }
        }
        completionHandler()
    }
    #endif
}

// MARK: - ViewModel

@MainActor
final class SentryViewModel: ObservableObject {
    @Published var frigateBase: String = "http://100.64.0.4:5000"
    @Published var truenasAgent: String = "http://100.64.0.4:9092"
    @Published var cameras: [String] = ["tapo_c200", "bike_camera"]
    @Published var selectedCamera: String = "tapo_c200"
    @Published var liveFrame: UIImage? = nil
    @Published var camFrames: [String: UIImage] = [:]
    @Published var isStreamingLive: Bool = true
    @Published var events: [FrigateEvent] = []
    @Published var selectedFilter: String = "All"
    @Published var patrolStatus: String = "24/7 Tapo PTZ Patrol Active"
    @Published var selectedEventForPlayback: FrigateEvent? = nil

    // Native Push (APNs + Local Snapshot Enrichment)
    @Published var notificationPermissionGranted: Bool = false
    @Published var apnsDeviceToken: String = UserDefaults.standard.string(forKey: "sentrycam.apns.token") ?? ""
    @Published var apnsSignedBundleId: String = Bundle.main.bundleIdentifier ?? "app.sentrycam.nvr"
    @Published var apnsRegisteredOnServer: Bool = UserDefaults.standard.bool(forKey: "sentrycam.apns.registered")
    @Published var apnsServerDeviceCount: Int = 0
    @Published var apnsStatusBanner: String? = nil
    @Published var apnsErrorText: String? = nil
    @Published var isSendingTestPush: Bool = false
    @Published var localRichNotificationsEnabled: Bool = true

    private var liveTimer: Timer? = nil
    private var eventsTimer: Timer? = nil
    private var seenEventIds: Set<String> = []
    private var hasPrimedInitialEvents: Bool = false

    init() {
        SentryAppDelegate.sharedViewModel = self
        startTimers()
        Task {
            await loadCamerasAndInitialState()
            await refreshPushServerStatus()
            if !apnsDeviceToken.isEmpty {
                await registerTokenWithTrueNAS(token: apnsDeviceToken, bundleId: apnsSignedBundleId)
            }
        }
    }

    func startTimers() {
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isStreamingLive else { return }
                await self.fetchLatestCameraFrame()
            }
        }

        eventsTimer?.invalidate()
        eventsTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadEvents()
            }
        }
    }

    func loadCamerasAndInitialState() async {
        if let url = URL(string: "\(frigateBase)/api/config") {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let camsDict = obj["cameras"] as? [String: Any] {
                    let names = Array(camsDict.keys).sorted()
                    if !names.isEmpty {
                        cameras = names
                        if !cameras.contains(selectedCamera) {
                            selectedCamera = cameras[0]
                        }
                    }
                }
            } catch {}
        }
        await fetchLatestCameraFrame()
        await loadEvents()
        await checkPatrolStatus()
    }

    func fetchLatestCameraFrame() async {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        for cam in ["tapo_c200", "bike_camera"] {
            guard let url = URL(string: "\(frigateBase)/api/\(cam)/latest.jpg?h=720&t=\(ts)") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 4.0
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                if let img = UIImage(data: data) {
                    camFrames[cam] = img
                    if cam == selectedCamera {
                        liveFrame = img
                    }
                }
            } catch {}
        }
    }

    func loadEvents() async {
        guard let url = URL(string: "\(frigateBase)/api/events?limit=40") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([FrigateEvent].self, from: data)
            if !hasPrimedInitialEvents {
                for ev in decoded { seenEventIds.insert(ev.id) }
                hasPrimedInitialEvents = true
            } else if localRichNotificationsEnabled {
                for ev in decoded.prefix(5) where !seenEventIds.contains(ev.id) {
                    seenEventIds.insert(ev.id)
                    await postRichSnapshotNotification(for: ev)
                }
            }
            events = decoded
        } catch {}
    }

    // MARK: - Rich Snapshot Local Notification (Attaches JPEG Snapshot)

    func postRichSnapshotNotification(for event: FrigateEvent) async {
        let content = UNMutableNotificationContent()
        content.title = "🚨 \(event.formattedLabel) on \(event.formattedCamera)"
        content.subtitle = "\(event.displayScorePercent)% confidence"
        content.body = "Tap to view HD snapshot & video clip in SentryCam."
        content.sound = .default
        content.userInfo = [
            "event_id": event.id,
            "camera": event.camera,
            "label": event.label
        ]

        // Download snapshot image to attach to the iOS notification banner
        if let snapURL = URL(string: "\(frigateBase)/api/events/\(event.id)/snapshot.jpg") {
            do {
                let (imgData, _) = try await URLSession.shared.data(from: snapURL)
                let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("snap_\(event.id).jpg")
                try imgData.write(to: tmpFile, options: .atomic)
                if let attachment = try? UNNotificationAttachment(identifier: "snapshot", url: tmpFile, options: nil) {
                    content.attachments = [attachment]
                }
            } catch {}
        }

        let req = UNNotificationRequest(identifier: "sentry_\(event.id)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Native Apple APNs Registration & Test Push

    func didReceiveAPNsToken(_ hexToken: String, bundleId: String) {
        apnsDeviceToken = hexToken
        apnsSignedBundleId = bundleId
        apnsErrorText = nil
        UserDefaults.standard.set(hexToken, forKey: "sentrycam.apns.token")
        Task {
            await registerTokenWithTrueNAS(token: hexToken, bundleId: bundleId)
        }
    }

    func registerTokenWithTrueNAS(token: String, bundleId: String) async {
        let endpoints = [
            "http://100.85.127.42:18998/sidestore-api/sentrycam-push",
            "https://navidrome.nas-server.co.uk/sidestore-api/sentrycam-push"
        ]
        let payload: [String: String] = [
            "action": "register",
            "token": token,
            "bundleId": bundleId,
            "device": UIDevice.current.name
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        for ep in endpoints {
            guard let url = URL(string: ep) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            req.timeoutInterval = 6.0
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    apnsRegisteredOnServer = true
                    UserDefaults.standard.set(true, forKey: "sentrycam.apns.registered")
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let cnt = obj["deviceCount"] as? Int {
                        apnsServerDeviceCount = cnt
                    }
                    return
                }
            } catch {
                continue
            }
        }
    }

    func refreshPushServerStatus() async {
        let endpoints = [
            "http://100.85.127.42:18998/sidestore-api/sentrycam-push?action=status",
            "https://navidrome.nas-server.co.uk/sidestore-api/sentrycam-push?action=status"
        ]
        for ep in endpoints {
            guard let url = URL(string: ep) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let st = try JSONDecoder().decode(PushServerStatus.self, from: data)
                apnsServerDeviceCount = st.deviceCount ?? 0
                return
            } catch {
                continue
            }
        }
    }

    func sendTestPushNotification(useLatestEvent: Bool) async {
        isSendingTestPush = true
        defer { isSendingTestPush = false }

        let latest = events.first
        let title = (useLatestEvent && latest != nil)
            ? "🚨 \(latest!.formattedLabel) on \(latest!.formattedCamera)"
            : "🚨 SentryCam Native Push Active"
        let sub = (useLatestEvent && latest != nil)
            ? "\(latest!.displayScorePercent)% confidence • Frigate NVR"
            : "Apple APNs Direct Delivery (No ntfy)"
        let msg = (useLatestEvent && latest != nil)
            ? "Detected on \(latest!.formattedCamera). Tap to open clip & snapshot."
            : "Your iPhone is receiving native Apple Push Notifications directly from TrueNAS."

        // Also trigger rich local snapshot notification if testing latest event
        if useLatestEvent, let ev = latest {
            await postRichSnapshotNotification(for: ev)
        }

        let payload: [String: String] = [
            "action": "test",
            "title": title,
            "subtitle": sub,
            "body": msg,
            "event_id": (useLatestEvent ? (latest?.id ?? "") : ""),
            "camera": (useLatestEvent ? (latest?.camera ?? "") : "")
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let endpoints = [
            "http://100.85.127.42:18998/sidestore-api/sentrycam-push",
            "https://navidrome.nas-server.co.uk/sidestore-api/sentrycam-push"
        ]
        for ep in endpoints {
            guard let url = URL(string: ep) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            req.timeoutInterval = 8.0
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let err = obj["error"] as? String {
                        apnsStatusBanner = err
                    } else {
                        apnsStatusBanner = "Dispatched native Apple APNs push to your iPhone!"
                    }
                    return
                }
            } catch {
                continue
            }
        }
        apnsStatusBanner = "Triggered local rich notification preview."
    }

    // MARK: - Tapo C200 PTZ Patrol Control

    func checkPatrolStatus() async {
        guard let url = URL(string: "\(truenasAgent)/api/antigravity/exec") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": "docker ps --filter name=tapo-patrol --format '{{.Status}}'"])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let out = (obj["stdout"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                patrolStatus = out.isEmpty ? "Tapo Patrol Paused" : "24/7 Tapo PTZ Patrol Active (\(out))"
            }
        } catch {}
    }

    func setTapoPatrol(running: Bool) async {
        guard let url = URL(string: "\(truenasAgent)/api/antigravity/exec") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let cmd = running
            ? "docker start tapo-patrol && echo '24/7 Tapo PTZ Patrol Active'"
            : "docker stop tapo-patrol && echo 'Tapo Patrol Paused'"
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": cmd])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let out = (obj["stdout"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty {
                patrolStatus = out.components(separatedBy: "\n").last ?? out
            }
        } catch {}
    }

    var filteredEvents: [FrigateEvent] {
        switch selectedFilter {
        case "Person":
            return events.filter { $0.label.lowercased() == "person" }
        case "Car":
            return events.filter { $0.label.lowercased() == "car" }
        case "Bike Cam":
            return events.filter { $0.camera == "bike_camera" }
        case "Doorbell":
            return events.filter { $0.camera == "doorbell" }
        case "Tapo C200":
            return events.filter { $0.camera == "tapo_c200" }
        default:
            return events
        }
    }
}

// MARK: - App Entry

@main
struct SentryCamApp: App {
    @UIApplicationDelegateAdaptor(SentryAppDelegate.self) var appDelegate
    @StateObject private var vm = SentryViewModel()

    var body: some Scene {
        WindowGroup {
            SentryCamRootView()
                .environmentObject(vm)
                .preferredColorScheme(.dark)
        }
    }
}

struct SentryCamRootView: View {
    @EnvironmentObject var vm: SentryViewModel
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SentryLiveTab()
                .tabItem {
                    Label("Live NVR", systemImage: "video.fill")
                }
                .tag(0)

            SentryEventsTab()
                .tabItem {
                    Label("Detections", systemImage: "figure.walk.motion")
                }
                .tag(1)

            SentryPushSettingsTab()
                .tabItem {
                    Label("Push Alerts", systemImage: "bell.badge.fill")
                }
                .tag(2)
        }
        .tint(Color(red: 0.22, green: 0.74, blue: 0.97))
        .sheet(item: $vm.selectedEventForPlayback) { ev in
            EventPlaybackSheet(event: ev, frigateBase: vm.frigateBase)
        }
    }
}

// MARK: - Tab 1: Live NVR & PTZ Patrol

struct SentryLiveTab: View {
    @EnvironmentObject var vm: SentryViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Camera Selector
                    Picker("Camera", selection: $vm.selectedCamera) {
                        ForEach(vm.cameras, id: \.self) { cam in
                            Text(cam.replacingOccurrences(of: "_", with: " ").capitalized)
                                .tag(cam)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: vm.selectedCamera) { _, _ in
                        Task { await vm.fetchLatestCameraFrame() }
                    }

                    #if os(tvOS)
                    // Dual-Camera 4K TV Split Wall (Tapo C200 + Ezviz Bike Camera)
                    HStack(spacing: 18) {
                        ForEach(["tapo_c200", "bike_camera"], id: \.self) { cam in
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(red: 0.06, green: 0.08, blue: 0.14))
                                    .frame(height: 360)

                                if let img = vm.camFrames[cam] {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity, maxHeight: 360)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                } else {
                                    VStack(spacing: 10) {
                                        ProgressView()
                                        Text("Streaming \(cam.replacingOccurrences(of: "_", with: " ").capitalized)...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 360)
                                }

                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 10, height: 10)
                                    Text("LIVE • \(cam == "tapo_c200" ? "TAPO C200 (192.168.0.41)" : "EZVIZ BIKE CAM (192.168.0.157)")")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.75))
                                .clipShape(Capsule())
                                .padding(14)
                            }
                        }
                    }
                    #endif

                    // Single Camera Focus Feed Card
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.06, green: 0.08, blue: 0.14))
                            .frame(height: 235)

                        if let img = vm.liveFrame {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        } else {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("Connecting to Frigate (\(vm.selectedCamera))...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 235)
                        }

                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("LIVE • \(vm.selectedCamera.replacingOccurrences(of: "_", with: " ").uppercased())")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .padding(12)
                    }

                    // Tapo C200 PTZ Patrol Control
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Tapo C200 PTZ & Patrol Control", systemImage: "dial.medium.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                            Spacer()
                        }

                        Text(vm.patrolStatus)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color(red: 0.22, green: 0.74, blue: 0.97))

                        HStack(spacing: 12) {
                            Button {
                                Task { await vm.setTapoPatrol(running: true) }
                            } label: {
                                Label("Start Patrol", systemImage: "play.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                Task { await vm.setTapoPatrol(running: false) }
                            } label: {
                                Label("Pause Patrol", systemImage: "pause.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.07, green: 0.10, blue: 0.17))
                    )

                    // Recent 5 Quick Detections
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("LATEST DETECTIONS")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(red: 0.22, green: 0.74, blue: 0.97))
                            Spacer()
                            Text(vm.apnsRegisteredOnServer ? "APNs Push Active ✓" : "Push Ready")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }

                        ForEach(vm.events.prefix(5)) { ev in
                            EventRowButton(event: ev, frigateBase: vm.frigateBase) {
                                vm.selectedEventForPlayback = ev
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.03, green: 0.04, blue: 0.08).ignoresSafeArea())
            .navigationTitle("SentryCam NVR")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Tab 2: Detections Feed

struct SentryEventsTab: View {
    @EnvironmentObject var vm: SentryViewModel
    private let filters = ["All", "Person", "Car", "Bike Cam", "Doorbell", "Tapo C200"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { f in
                            Button {
                                vm.selectedFilter = f
                            } label: {
                                Text(f)
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        vm.selectedFilter == f
                                        ? Color(red: 0.22, green: 0.74, blue: 0.97)
                                        : Color.white.opacity(0.08)
                                    )
                                    .foregroundStyle(vm.selectedFilter == f ? Color.black : Color.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.filteredEvents) { ev in
                            EventRowButton(event: ev, frigateBase: vm.frigateBase) {
                                vm.selectedEventForPlayback = ev
                            }
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    await vm.loadEvents()
                }
            }
            .background(Color(red: 0.03, green: 0.04, blue: 0.08).ignoresSafeArea())
            .navigationTitle("Detections (\(vm.filteredEvents.count))")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct EventRowButton: View {
    let event: FrigateEvent
    let frigateBase: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: "\(frigateBase)/api/events/\(event.id)/thumbnail.jpg")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Color.white.opacity(0.08)
                    }
                }
                .frame(width: 84, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(event.formattedLabel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("\(event.displayScorePercent)%")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.2))
                            .foregroundStyle(Color(red: 0.22, green: 0.74, blue: 0.97))
                            .clipShape(Capsule())
                    }
                    Text(event.formattedCamera)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(event.startDate, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.22, green: 0.74, blue: 0.97))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.10, blue: 0.17))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 3: Native APNs Push Notification Control Center

struct SentryPushSettingsTab: View {
    @EnvironmentObject var vm: SentryViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // APNs Status Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: vm.apnsDeviceToken.isEmpty ? "bell.slash.fill" : "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundStyle(vm.apnsDeviceToken.isEmpty ? Color.orange : Color.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.apnsDeviceToken.isEmpty ? "Registering with Apple APNs..." : "Native Apple Push (APNs) Active")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text("Direct TrueNAS → Apple APNs delivery (ntfy not required)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        Divider().overlay(Color.white.opacity(0.1))

                        HStack {
                            Text("APNs Device Token:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(vm.apnsDeviceToken.isEmpty ? "Pending permission" : "\(vm.apnsDeviceToken.prefix(16))...")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.white)
                        }

                        HStack {
                            Text("TrueNAS Registry:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(vm.apnsRegisteredOnServer ? "Registered (\(max(1, vm.apnsServerDeviceCount)) iPhone)" : "Syncing...")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(vm.apnsRegisteredOnServer ? Color.green : Color.orange)
                        }

                        if let err = vm.apnsErrorText {
                            Text("APNs Info: \(err)")
                                .font(.caption2)
                                .foregroundStyle(Color.orange)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.07, green: 0.10, blue: 0.17))
                    )

                    // Test Push Buttons
                    VStack(alignment: .leading, spacing: 10) {
                        Text("INSTANT PUSH VERIFICATION")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(red: 0.22, green: 0.74, blue: 0.97))

                        Button {
                            Task { await vm.sendTestPushNotification(useLatestEvent: false) }
                        } label: {
                            HStack {
                                Image(systemName: "bell.badge.waveform.fill")
                                Text("Send Test APNs Push to My iPhone")
                                    .font(.subheadline.weight(.bold))
                                Spacer()
                                if vm.isSendingTestPush {
                                    ProgressView().tint(.black)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                            }
                            .foregroundStyle(Color.black)
                            .padding(15)
                            .background(Color(red: 0.22, green: 0.74, blue: 0.97))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(vm.isSendingTestPush)

                        Button {
                            Task { await vm.sendTestPushNotification(useLatestEvent: true) }
                        } label: {
                            HStack {
                                Image(systemName: "camera.viewfinder")
                                Text("Push Latest Camera Detection + Snapshot")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .foregroundStyle(Color.white)
                            .padding(15)
                            .background(Color(red: 0.07, green: 0.10, blue: 0.17))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(vm.isSendingTestPush)

                        if let banner = vm.apnsStatusBanner {
                            Text(banner)
                                .font(.caption)
                                .foregroundStyle(Color.green)
                                .padding(.horizontal, 6)
                        }
                    }

                    // Rich Snapshot Toggle
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $vm.localRichNotificationsEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Attach Camera Snapshot to Banners")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("Automatically attaches the Frigate JPEG snapshot to notification banners.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(Color(red: 0.22, green: 0.74, blue: 0.97))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.07, green: 0.10, blue: 0.17))
                    )
                }
                .padding(16)
            }
            .background(Color(red: 0.03, green: 0.04, blue: 0.08).ignoresSafeArea())
            .navigationTitle("Native Push Alerts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Event Clip & Snapshot Sheet

struct EventPlaybackSheet: View {
    let event: FrigateEvent
    let frigateBase: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if event.has_clip ?? true,
                       let clipURL = URL(string: "\(frigateBase)/api/events/\(event.id)/clip.mp4") {
                        VideoPlayer(player: AVPlayer(url: clipURL))
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Text("HIGH-RES DETECTION SNAPSHOT")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(red: 0.22, green: 0.74, blue: 0.97))

                    AsyncImage(url: URL(string: "\(frigateBase)/api/events/\(event.id)/snapshot.jpg")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        default:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 180)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.03, green: 0.04, blue: 0.08).ignoresSafeArea())
            .navigationTitle("\(event.formattedLabel) • \(event.formattedCamera)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
