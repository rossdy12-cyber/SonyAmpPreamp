import SwiftUI
import UIKit
import BackgroundTasks
import UserNotifications

// MARK: - Models

struct StoreVersion: Codable {
    let version: String
    let date: String?
    let localizedDescription: String?
    let downloadURL: String?
    let size: Int?
    let minOSVersion: String?
}

struct StoreApp: Codable, Identifiable {
    let name: String
    let bundleIdentifier: String
    var id: String { bundleIdentifier }
    let subtitle: String?
    let localizedDescription: String?
    let developerName: String?
    let iconURL: String?
    let tintColor: String?
    let version: String
    let versionDate: String?
    let downloadURL: String?
    let size: Int?
    let versions: [StoreVersion]?
}

struct StoreSource: Codable {
    let name: String?
    let apps: [StoreApp]?
}

// MARK: - Store client

final class StoreClient {
    static let shared = StoreClient()
    static let base = "https://navidrome.nas-server.co.uk"

    func slugify(_ bundleId: String) -> String {
        bundleId.lowercased().map { ($0.isLetter || $0.isNumber) ? String($0) : "_" }.joined()
    }

    /// POSTs the login form and captures the 303 Location header to extract the 32-hex account key.
    func login(username: String, password: String) async throws -> String {
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        var req = URLRequest(url: URL(string: Self.base + "/sidestore-api/login")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let delegate = RedirectCapture()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw StoreError.badResponse }
        if http.statusCode == 401 || http.statusCode == 429 {
            throw StoreError.badCredentials
        }
        guard let location = delegate.capturedLocation,
              let key = StoreClient.extractKey(from: location) else {
            throw StoreError.badCredentials
        }
        return key
    }

    /// Extracts a 32-hex key from either a bare key or a full store URL.
    static func extractKey(from text: String) -> String? {
        if let m = text.range(of: "[0-9a-f]{32}", options: .regularExpression) {
            return String(text[m])
        }
        return nil
    }

    func fetchSource(key: String) async throws -> StoreSource {
        let url = URL(string: Self.base + "/sidestore-api/source/\(key).json")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw StoreError.badKey
        }
        return try JSONDecoder().decode(StoreSource.self, from: data)
    }

    func manifestURL(key: String, bundleId: String) -> String {
        "\(Self.base)/sidestore-api/dl/\(key)/\(slugify(bundleId)).plist"
    }

    func otaURL(key: String, bundleId: String) -> URL? {
        let m = manifestURL(key: key, bundleId: bundleId)
        let quoted = m.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? m
        return URL(string: "itms-services://?action=download-manifest&url=\(quoted)")
    }

    enum StoreError: LocalizedError {
        case badCredentials
        case badKey
        case badResponse

        var errorDescription: String? {
            switch self {
            case .badCredentials: return "Wrong username or password (or too many attempts — wait a few minutes)."
            case .badKey: return "Store key rejected — sign in again in Settings."
            case .badResponse: return "The store didn't respond as expected."
            }
        }
    }
}

final class RedirectCapture: NSObject, URLSessionDelegate {
    var capturedLocation: String?

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        capturedLocation = response.value(forHTTPHeaderField: "Location")
        completionHandler(nil)  // stop following; we only want the key out of the Location header
    }
}

// MARK: - Update engine

final class UpdateEngine: ObservableObject {
    static let shared = UpdateEngine()
    static let taskIdentifier = "app.starkstore.client.refresh"

    @Published var apps: [StoreApp] = []
    @Published var updates: [StoreApp] = []
    @Published var lastChecked: Date? = nil
    @Published var isLoading = false
    @Published var statusMessage: String? = nil
    @Published var autoNotify: Bool = (UserDefaults.standard.object(forKey: "starkstore.autonotify") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoNotify, forKey: "starkstore.autonotify") }
    }

    private init() {}

    var key: String? { UserDefaults.standard.string(forKey: "starkstore.key") }
    var username: String? { UserDefaults.standard.string(forKey: "starkstore.username") }

    /// Install log: bundleId -> version the store app last triggered an install for.
    func installedVersion(for bid: String) -> String? {
        UserDefaults.standard.string(forKey: "starkstore.installed.\(bid)")
    }

    func recordInstall(app: StoreApp) {
        UserDefaults.standard.set(app.version, forKey: "starkstore.installed.\(app.bundleIdentifier)")
        recomputeUpdates()
    }

    func forgetInstall(app: StoreApp) {
        UserDefaults.standard.removeObject(forKey: "starkstore.installed.\(app.bundleIdentifier)")
        recomputeUpdates()
    }

    static func versionIsNewer(_ candidate: String, than current: String) -> Bool {
        let c = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let cur = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(c.count, cur.count) {
            let a = i < c.count ? c[i] : 0
            let b = i < cur.count ? cur[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    func recomputeUpdates() {
        updates = apps.filter { app in
            guard let installed = installedVersion(for: app.bundleIdentifier) else { return false }
            return Self.versionIsNewer(app.version, than: installed)
        }
    }

    func signIn(username: String, password: String) async throws {
        let key = try await StoreClient.shared.login(username: username, password: password)
        guard let k = StoreClient.extractKey(from: key) else { throw StoreClient.StoreError.badCredentials }
        UserDefaults.standard.set(k, forKey: "starkstore.key")
        UserDefaults.standard.set(username, forKey: "starkstore.username")
        try await refresh()
        await requestNotificationAuthorization()
        scheduleBackgroundRefresh()
    }

    func signInWithKey(_ rawKey: String) async throws {
        guard let k = StoreClient.extractKey(from: rawKey) else { throw StoreClient.StoreError.badKey }
        UserDefaults.standard.set(k, forKey: "starkstore.key")
        try await refresh()
        await requestNotificationAuthorization()
        scheduleBackgroundRefresh()
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: "starkstore.key")
        UserDefaults.standard.removeObject(forKey: "starkstore.username")
        apps = []
        updates = []
        statusMessage = "Signed out."
    }

    @discardableResult
    func refresh() async -> Bool {
        guard let key = key else {
            statusMessage = "Not signed in."
            return false
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let src = try await StoreClient.shared.fetchSource(key: key)
            apps = (src.apps ?? []).sorted { $0.name.lowercased() < $1.name.lowercased() }
            recomputeUpdates()
            lastChecked = Date()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "starkstore.lastCheckEpoch")
            let newCount = updates.count
            statusMessage = apps.isEmpty ? "Store returned no apps." : "Store synced — \(apps.count) apps, \(newCount) update(s) available"
            if autoNotify && newCount > 0 {
                await postUpdateNotification(updates: updates)
            }
            return true
        } catch {
            statusMessage = "Sync failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            return false
        }
    }

    func install(_ app: StoreApp) {
        guard let key = key, let url = StoreClient.shared.otaURL(key: key, bundleId: app.bundleIdentifier) else { return }
        recordInstall(app: app)
        UIApplication.shared.open(url)
    }

    // MARK: Local notifications

    func requestNotificationAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func postUpdateNotification(updates: [StoreApp]) async {
        let names = updates.prefix(3).map { "\($0.name) v\($0.version)" }.joined(separator: ", ")
        let extra = updates.count > 3 ? " +\(updates.count - 3) more" : ""
        let content = UNMutableNotificationContent()
        content.title = "🦇 \(updates.count) app update\(updates.count == 1 ? "" : "s") await you in the crypt"
        content.body = names + extra + " — tap to install"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "starkstore.updates", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    // MARK: Background refresh

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskScheduler rejects submissions in some states (e.g. simulator); harmless.
        }
    }

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            let engine = UpdateEngine.shared
            Task { @MainActor in
                let ok = await engine.refresh()
                engine.scheduleBackgroundRefresh()
                task.setTaskCompleted(success: ok)
            }
        }
    }
}

// MARK: - Gothic theme

enum Gothic {
    static let bg = Color(red: 0.027, green: 0.016, blue: 0.02)
    static let card = Color(red: 0.086, green: 0.031, blue: 0.04)
    static let cardAlt = Color(red: 0.11, green: 0.045, blue: 0.055)
    static let crimson = Color(red: 0.863, green: 0.078, blue: 0.235)   // #DC143C
    static let blood = Color(red: 0.42, green: 0.02, blue: 0.08)
    static let parchment = Color(red: 0.91, green: 0.88, blue: 0.84)
    static let ash = Color(red: 0.659, green: 0.596, blue: 0.502)       // #A89880
    static let moon = Color(red: 0.55, green: 0.62, blue: 0.78)

    static let cardStroke = Color(red: 0.23, green: 0.04, blue: 0.06)
}

struct GothicCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Gothic.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Gothic.cardStroke, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func gothicCard() -> some View { modifier(GothicCard()) }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .heavy))
            .tracking(2.5)
            .foregroundStyle(Gothic.crimson)
            .textCase(.uppercase)
    }
}

// MARK: - App

@main
struct StarkStoreApp: App {
    @StateObject private var engine = UpdateEngine.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UpdateEngine.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                engine.scheduleBackgroundRefresh()
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var engine: UpdateEngine
    @State private var showOnboarding = false

    var body: some View {
        TabView {
            StoreListView().tabItem { Label("Catacomb", systemImage: "books.vertical.fill") }
            UpdatesView().tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Gothic.crimson)
        .onAppear {
            if engine.key == nil {
                showOnboarding = true
            } else {
                Task { await engine.refresh() }
            }
        }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            if engine.key == nil { showOnboarding = true }  // can't use the store without a key
        }) {
            OnboardingView()
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var engine: UpdateEngine
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Int = 0  // 0 = username/password, 1 = paste key
    @State private var username = ""
    @State private var password = ""
    @State private var keyText = ""
    @State private var busy = false
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Gothic.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 10) {
                            Image(systemName: "moon.stars.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(
                                    LinearGradient(colors: [Gothic.crimson, Gothic.blood], startPoint: .top, endPoint: .bottom)
                                )
                            Text("STARK STORE")
                                .font(.system(size: 26, weight: .heavy))
                                .tracking(6)
                                .foregroundStyle(Gothic.parchment)
                            Text("Your personal crypt of apps")
                                .font(.caption)
                                .foregroundStyle(Gothic.ash)
                        }
                        .padding(.top, 30)

                        Picker("", selection: $mode) {
                            Text("Sign in").tag(0)
                            Text("Paste key").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .tint(Gothic.crimson)

                        if mode == 0 {
                            VStack(spacing: 10) {
                                TextField("Username", text: $username)
                                    .textContentType(.username)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Gothic.cardAlt))
                                    .foregroundStyle(Gothic.parchment)
                                SecureField("Password", text: $password)
                                    .textContentType(.password)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Gothic.cardAlt))
                                    .foregroundStyle(Gothic.parchment)
                            }
                            Text("Your Stark Store web account (the one for the store sign-in page).")
                                .font(.caption2)
                                .foregroundStyle(Gothic.ash)
                        } else {
                            TextField("Paste your personal store link or 32-char key", text: $keyText)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Gothic.cardAlt))
                                .foregroundStyle(Gothic.parchment)
                            Text("Your personal store page URL contains the key — e.g. …/sidestore-api/store/xxxxxxxx…. Open that bookmarked page in Safari and copy the whole link.")
                                .font(.caption2)
                                .foregroundStyle(Gothic.ash)
                        }

                        Button {
                            busy = true
                            errorText = nil
                            Task {
                                do {
                                    if mode == 0 {
                                        try await engine.signIn(username: username, password: password)
                                    } else {
                                        try await engine.signInWithKey(keyText)
                                    }
                                    dismiss()
                                } catch {
                                    errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                }
                                busy = false
                            }
                        } label: {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Text("ENTER THE CRYPT")
                                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                                    .tracking(2)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(LinearGradient(colors: [Gothic.crimson, Gothic.blood], startPoint: .leading, endPoint: .trailing))
                            )
                        }
                        .disabled(busy || (mode == 0 ? username.isEmpty || password.isEmpty : keyText.isEmpty))

                        if let errorText = errorText {
                            Text(errorText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Gothic.crimson)
                                .multilineTextAlignment(.center)
                        }

                        Text("Once inside, Stark Store checks for app updates in the background and notifies you — every install still needs one tap, because iOS requires it.")
                            .font(.caption2)
                            .foregroundStyle(Gothic.ash)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 30)
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                        .foregroundStyle(Gothic.ash)
                }
            }
        }
    }
}

// MARK: - Store list

struct StoreListView: View {
    @EnvironmentObject var engine: UpdateEngine
    @State private var query = ""

    var filtered: [StoreApp] {
        guard !query.isEmpty else { return engine.apps }
        return engine.apps.filter {
            $0.name.lowercased().contains(query.lowercased()) ||
            ($0.subtitle ?? "").lowercased().contains(query.lowercased()) ||
            $0.bundleIdentifier.lowercased().contains(query.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Gothic.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(Gothic.ash)
                            TextField("Search the catacomb…", text: $query)
                                .autocorrectionDisabled()
                                .foregroundStyle(Gothic.parchment)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Gothic.cardAlt))

                        if engine.isLoading && engine.apps.isEmpty {
                            ProgressView("Awakening the crypt…")
                                .tint(Gothic.crimson)
                                .padding(.top, 60)
                        } else if engine.apps.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "books.vertical")
                                    .font(.largeTitle)
                                    .foregroundStyle(Gothic.ash)
                                Text("No apps loaded")
                                    .font(.headline)
                                    .foregroundStyle(Gothic.parchment)
                                Text("Check your sign-in in Settings.")
                                    .font(.caption)
                                    .foregroundStyle(Gothic.ash)
                            }
                            .padding(.top, 60)
                        } else {
                            ForEach(filtered) { app in
                                AppRow(app: app)
                            }
                        }

                        if let msg = engine.statusMessage {
                            Text(msg)
                                .font(.caption2)
                                .foregroundStyle(Gothic.ash)
                                .padding(.top, 8)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Stark Store")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await engine.refresh() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if engine.updates.count > 0 {
                        Text("\(engine.updates.count)")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Gothic.crimson))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

struct AppRow: View {
    @EnvironmentObject var engine: UpdateEngine
    let app: StoreApp

    private var installedVersion: String? { engine.installedVersion(for: app.bundleIdentifier) }
    private var hasUpdate: Bool {
        guard let installed = installedVersion else { return false }
        return UpdateEngine.versionIsNewer(app.version, than: installed)
    }

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(url: app.iconURL, name: app.name)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Gothic.parchment)
                Text(app.subtitle ?? app.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(Gothic.ash)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("v\(app.version)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Gothic.ash)
                    if let installed = installedVersion {
                        if hasUpdate {
                            Label("update", systemImage: "arrow.up.circle.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Gothic.crimson)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color(red: 0.3, green: 0.6, blue: 0.35))
                        }
                        Text("(installed v\(installed))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Gothic.ash)
                    }
                }
            }

            Spacer()

            Button {
                engine.install(app)
            } label: {
                Text(installedVersion == nil ? "GET" : (hasUpdate ? "UPDATE" : "REDO"))
                    .font(.caption.weight(.heavy))
                    .tracking(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(
                            hasUpdate
                            ? LinearGradient(colors: [Gothic.crimson, Gothic.blood], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Gothic.cardAlt, Gothic.cardAlt], startPoint: .leading, endPoint: .trailing)
                        )
                    )
                    .overlay(Capsule().stroke(Gothic.cardStroke, lineWidth: 1))
                    .foregroundStyle(hasUpdate ? .white : Gothic.parchment)
            }
        }
        .gothicCard()
    }
}

struct AppIconView: View {
    let url: String?
    let name: String

    var body: some View {
        Group {
            if let url = url, let u = URL(string: url) {
                AsyncImage(url: u) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Gothic.cardStroke, lineWidth: 1))
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Gothic.cardAlt)
            Text(String(name.prefix(1)).uppercased())
                .font(.title3.weight(.heavy))
                .foregroundStyle(Gothic.crimson)
        }
    }
}

// MARK: - Updates

struct UpdatesView: View {
    @EnvironmentObject var engine: UpdateEngine

    var body: some View {
        NavigationStack {
            ZStack {
                Gothic.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(engine.updates.isEmpty ? "All apps current" : "\(engine.updates.count) update\(engine.updates.count == 1 ? "" : "s") available")
                                    .font(.title3.weight(.heavy))
                                    .foregroundStyle(Gothic.parchment)
                                if let last = engine.lastChecked {
                                    Text("Last synced \(last.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(Gothic.ash)
                                }
                            }
                            Spacer()
                            Button {
                                Task { await engine.refresh() }
                            } label: {
                                HStack(spacing: 6) {
                                    if engine.isLoading {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Sync")
                                        .font(.caption.weight(.heavy))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Gothic.crimson))
                                .foregroundStyle(.white)
                            }
                            .disabled(engine.isLoading || engine.key == nil)
                        }
                        .gothicCard()

                        Toggle(isOn: $engine.autoNotify) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AUTO-UPDATE ALERTS")
                                    .font(.caption.weight(.heavy))
                                    .tracking(1.5)
                                    .foregroundStyle(Gothic.crimson)
                                Text("Local notification when new versions are found (background sync + manual sync).")
                                    .font(.caption2)
                                    .foregroundStyle(Gothic.ash)
                            }
                        }
                        .tint(Gothic.crimson)
                        .gothicCard()

                        if engine.updates.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "moon.zzz.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(Gothic.ash)
                                Text("The crypt is quiet")
                                    .font(.headline)
                                    .foregroundStyle(Gothic.parchment)
                                Text("Updates for apps you installed through Stark Store will appear here. iOS runs the background check a few times a day; use Sync for an instant check.")
                                    .font(.caption)
                                    .foregroundStyle(Gothic.ash)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 50)
                        } else {
                            ForEach(engine.updates) { app in
                                UpdateRow(app: app)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Updates")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct UpdateRow: View {
    @EnvironmentObject var engine: UpdateEngine
    let app: StoreApp

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(url: app.iconURL, name: app.name)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Gothic.parchment)
                HStack(spacing: 4) {
                    Text("v\(engine.installedVersion(for: app.bundleIdentifier) ?? "?")")
                        .strikethrough()
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Gothic.ash)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(Gothic.ash)
                    Text("v\(app.version)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Gothic.crimson)
                }
                if let note = app.versions?.first?.localizedDescription, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Gothic.ash)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button {
                engine.install(app)
            } label: {
                Text("INSTALL")
                    .font(.caption.weight(.heavy))
                    .tracking(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(LinearGradient(colors: [Gothic.crimson, Gothic.blood], startPoint: .leading, endPoint: .trailing)))
                    .foregroundStyle(.white)
            }
        }
        .gothicCard()
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var engine: UpdateEngine
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            ZStack {
                Gothic.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Account")
                            HStack {
                                Image(systemName: "person.crop.circle.badge.moon")
                                    .font(.title3)
                                    .foregroundStyle(Gothic.crimson)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(engine.username ?? "Signed in with a store key")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Gothic.parchment)
                                    Text("key …" + (engine.key?.suffix(8) ?? "—"))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(Gothic.ash)
                                }
                                Spacer()
                                Button {
                                    Task { await engine.refresh() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundStyle(Gothic.crimson)
                                }
                            }
                            Button {
                                showOnboarding = true
                            } label: {
                                Text("Re-sign in / change key")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Gothic.cardAlt))
                                    .foregroundStyle(Gothic.parchment)
                            }
                        }
                        .gothicCard()

                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Installed via Stark Store")
                            if engine.apps.isEmpty {
                                Text("Nothing recorded yet — versions are remembered when you install from this app.")
                                    .font(.caption)
                                    .foregroundStyle(Gothic.ash)
                            } else {
                                ForEach(engine.apps.filter { engine.installedVersion(for: $0.bundleIdentifier) != nil }) { app in
                                    HStack {
                                        Text(app.name)
                                            .font(.subheadline)
                                            .foregroundStyle(Gothic.parchment)
                                        Spacer()
                                        Text("v\(engine.installedVersion(for: app.bundleIdentifier) ?? "?")")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(Gothic.ash)
                                        Button {
                                            engine.forgetInstall(app: app)
                                        } label: {
                                            Image(systemName: "eye.slash")
                                                .font(.caption2)
                                                .foregroundStyle(Gothic.ash)
                                        }
                                    }
                                }
                                Text("Tap the eye to stop tracking an app (e.g. you updated it from elsewhere).")
                                    .font(.caption2)
                                    .foregroundStyle(Gothic.ash)
                            }
                        }
                        .gothicCard()

                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "The fine print")
                            Text("iOS requires a user tap for every install — no app can silently update another. Stark Store gets as close as allowed: background sync, instant alerts, and one-tap OTA installs.")
                                .font(.caption)
                                .foregroundStyle(Gothic.ash)
                            Text("Server: \(StoreClient.base)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(Gothic.ash)
                        }
                        .gothicCard()

                        Button {
                            engine.signOut()
                        } label: {
                            Label("Sign out", systemImage: "moon.stars.slash")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Gothic.crimson)
                        }
                        .padding(.top, 8)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showOnboarding) {
                OnboardingView()
            }
        }
    }
}
