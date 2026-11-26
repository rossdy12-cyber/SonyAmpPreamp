import SwiftUI
import UserNotifications
import UIKit

@MainActor
final class PushRegistration: ObservableObject {
    static let shared = PushRegistration()
    @Published private(set) var registered = false
    private var tokenHex: String?
    private var endpoint = ""
    private var pairingToken = ""
    private var enabled = false

    func configure(endpoint: String, pairingToken: String) {
        self.endpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        self.pairingToken = pairingToken
        enabled = UserDefaults.standard.bool(forKey: "pushAlertsEnabled")
        if enabled {
            UIApplication.shared.registerForRemoteNotifications()
            if let tokenHex { Task { await upload(tokenHex) } }
        }
    }

    func register() async {
        guard !endpoint.isEmpty, !pairingToken.isEmpty else { throw PushRegistrationError.bridgeUnavailable }
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { throw PushRegistrationError.permissionDenied }
            enabled = true
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            if let tokenHex {
                await upload(tokenHex)
                guard registered else { enabled = false; throw PushRegistrationError.pushUnavailable }
            }
            UserDefaults.standard.set(true, forKey: "pushAlertsEnabled")
        } catch { throw error }
    }

    func disable() async {
        enabled = false
        UserDefaults.standard.set(false, forKey: "pushAlertsEnabled")
        guard let tokenHex else { registered = false; return }
        await upload(tokenHex, enabled: false)
        registered = false
    }

    func receive(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        tokenHex = hex
        guard enabled else { return }
        await upload(hex)
    }

    private func upload(_ hex: String, enabled override: Bool? = nil) async {
        guard let url = URL(string: "\(endpoint)/v1/push/register"), endpoint.hasPrefix("https://") || endpoint.contains("100.64.0.4") else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(pairingToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["deviceToken": hex, "bundleId": "com.ross.forgelink", "enabled": override ?? enabled])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let status = response as? HTTPURLResponse, (200..<300).contains(status.statusCode) else { registered = false; return }
            let result = try? JSONDecoder().decode(PushResponse.self, from: data)
            registered = result?.enabled == true && result?.apnsEnabled == true
        } catch { registered = false }
    }
}

private struct PushResponse: Decodable { let registered: Bool?; let enabled: Bool?; let apnsEnabled: Bool?; let pushConfigured: Bool? }
enum PushRegistrationError: LocalizedError {
    case permissionDenied
    case bridgeUnavailable
    case pushUnavailable
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Allow ForgeLink notifications in iOS Settings, then try again."
        case .bridgeUnavailable: return "Connect ForgeLink to your TrueNAS bridge first."
        case .pushUnavailable: return "Push is not ready: the private notifier and a matching signed ForgeLink profile must both be enabled."
        }
    }
}

final class ForgeLinkAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushRegistration.shared.receive(deviceToken: deviceToken) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("ForgeLink APNs registration failed: %@", error.localizedDescription)
    }
}

@main
struct ForgeLinkApp: App {
    @UIApplicationDelegateAdaptor(ForgeLinkAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var push = PushRegistration.shared
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Forge.mint)
        }
    }
}

enum Forge {
    static let background = Color(red: 0.035, green: 0.051, blue: 0.075)
    static let surface = Color(red: 0.065, green: 0.086, blue: 0.118)
    static let mint = Color(red: 0.46, green: 0.96, blue: 0.74)
    static let secondary = Color(red: 0.55, green: 0.62, blue: 0.70)
    static func statusColor(_ status: String) -> Color {
        switch status {
        case "running": return mint
        case "succeeded", "dispatched": return .cyan
        case "failed": return .orange
        default: return secondary
        }
    }
}
extension View {
    func forgeCard() -> some View {
        self.padding(18).background(Forge.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.06), lineWidth: 1))
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            WorkspaceView().tabItem { Label("Workspace", systemImage: "square.stack.3d.up") }
            HistoryView().tabItem { Label("Runs", systemImage: "terminal") }
            ConnectionView().tabItem { Label("Connection", systemImage: "network") }
        }
        .toolbarBackground(Forge.background, for: .tabBar)
        .sheet(isPresented: $model.showSettings) { PairingView() }
        .alert("ForgeLink", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .task {
            if !model.endpoint.isEmpty && !model.token.isEmpty {
                push.configure(endpoint: model.endpoint, pairingToken: model.token)
                await model.connect()
            }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                if scenePhase == .active { await model.refresh() }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}

struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @State private var prompt = ""
    @State private var selectedRun: Run?
    @State private var pendingAction: SavedAction?
    @FocusState private var composing: Bool
    private var canSend: Bool {
        model.connected && !model.selectedProject.isEmpty && !model.selectedAgent.isEmpty && !model.projectBusy && !model.isSubmitting && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prompt.count <= 16000
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Label("FORGELINK", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 14, weight: .black, design: .monospaced)).tracking(2)
                        Spacer()
                        Circle().fill(model.connected ? Forge.mint : Forge.secondary).frame(width: 6, height: 6)
                        Text(model.connected ? "CONNECTED" : "OFFLINE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Forge.secondary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your desk.\nAnywhere.").font(.system(size: 40, weight: .bold, design: .rounded)).tracking(-1.5)
                        Text("Three agents. One command centre.").font(.subheadline).foregroundStyle(Forge.secondary)
                    }
                    if let info = model.status {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionLabel("01 / WORKSPACE")
                            if info.projects.isEmpty {
                                Text("Add a project path to the bridge configuration.").foregroundStyle(Forge.secondary)
                            } else {
                                Picker("Project", selection: $model.selectedProject) {
                                    ForEach(info.projects) { Text($0.name).tag($0.id) }
                                }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "externaldrive.connected.to.line.below")
                                Text(info.name)
                                Spacer()
                                Text("\(model.activeCount) active")
                            }.font(.caption).foregroundStyle(Forge.secondary)
                        }.forgeCard()
                        VStack(alignment: .leading, spacing: 14) {
                            sectionLabel("02 / PICK YOUR AGENT")
                            if info.agents.isEmpty {
                                Text("No agents enabled yet. Install and authenticate the CLI on your host, or configure a DeepAI webhook, then reconnect.").font(.subheadline).foregroundStyle(Forge.secondary)
                            }
                            ForEach(info.agents) { agent in
                                Button { model.selectedAgent = agent.id } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: agent.symbol).font(.title3).frame(width: 28).foregroundStyle(agent.id == "claude" ? Color.orange : agent.id == "antigravity" ? Color.cyan : Forge.mint)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(agent.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                            Text(agent.kind == "webhook" ? "Webhook handoff · results in desktop app" : "On your host · local CLI permissions")
                                                .font(.system(size: 11)).foregroundStyle(Forge.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: model.selectedAgent == agent.id ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(model.selectedAgent == agent.id ? Forge.mint : Forge.secondary)
                                    }.padding(14).background(model.selectedAgent == agent.id ? Forge.mint.opacity(0.06) : Forge.surface, in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(model.selectedAgent == agent.id ? Forge.mint.opacity(0.45) : .white.opacity(0.06)))
                                }.buttonStyle(.plain)
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel("03 / MAKE SOMETHING HAPPEN")
                            ZStack(alignment: .topLeading) {
                                if prompt.isEmpty { Text("Fix a bug, write a feature, investigate a failure…").foregroundStyle(Forge.secondary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                                TextEditor(text: $prompt).scrollContentBackground(.hidden).frame(minHeight: 120).focused($composing)
                            }
                            if prompt.count > 16000 { Text("Tasks are limited to 16,000 characters.").font(.caption).foregroundStyle(.orange) }
                            if model.projectBusy { Label("This workspace is busy. Open its active run below.", systemImage: "hourglass").font(.caption).foregroundStyle(.orange) }
                            Button {
                                composing = false
                                Task {
                                    if let run = await model.submit(prompt: prompt) { prompt = ""; selectedRun = run }
                                }
                            } label: {
                                HStack {
                                    if model.isSubmitting { ProgressView().tint(Forge.background) }
                                    Text(model.isSubmitting ? "Sending…" : "Send task").fontWeight(.bold)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }.padding(16).foregroundStyle(Forge.background)
                                    .background(canSend ? Forge.mint : Forge.secondary, in: RoundedRectangle(cornerRadius: 14))
                            }.disabled(!canSend)
                            Text("Tasks may edit files or run tools within your host’s configured permissions. Review changes before deploying.").font(.caption2).foregroundStyle(Forge.secondary)
                        }.forgeCard()
                        if let project = model.project, !project.actions.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionLabel("QUICK COMMANDS")
                                ForEach(project.actions) { action in
                                    Button { pendingAction = action } label: {
                                        HStack { Image(systemName: "play.fill").font(.caption); Text(action.name); Spacer(); Image(systemName: "chevron.right").font(.caption) }
                                            .padding(14).background(Forge.surface, in: RoundedRectangle(cornerRadius: 12))
                                    }.disabled(model.projectBusy || model.isSubmitting || !model.connected)
                                }
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "personalhotspot").font(.largeTitle).foregroundStyle(Forge.mint)
                            Text("Connect your command centre").font(.title3.bold())
                            Text("Pair with the bridge on TrueNAS or your development computer. Your code and agent logins stay there.").foregroundStyle(Forge.secondary)
                            Button(model.isConnecting ? "Connecting…" : "Pair a bridge") { model.showSettings = true }.buttonStyle(.borderedProminent)
                        }.forgeCard()
                    }
                    if !model.runs.isEmpty {
                        sectionLabel("RECENT ACTIVITY")
                        ForEach(Array(model.runs.prefix(4))) { run in
                            Button { selectedRun = run } label: { RunRow(run: run) }.buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                        Text("Code runs on your host. Not your phone.")
                    }.font(.caption2).foregroundStyle(Forge.secondary).frame(maxWidth: .infinity).padding(.bottom, 12)
                }.padding(22)
            }
            .background(Forge.background).toolbar(.hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.refresh() }
            .sheet(item: $selectedRun) { RunDetailView(runID: $0.id) }
            .confirmationDialog("Run \(pendingAction?.name ?? "command") on \(model.project?.name ?? "workspace")?", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
                if let action = pendingAction {
                    Button("Run command") { Task { if let run = await model.submit(action: action) { selectedRun = run } }; pendingAction = nil }
                }
                Button("Cancel", role: .cancel) { pendingAction = nil }
            } message: { Text("This executes the command saved by the bridge administrator.") }
        }
    }
    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.6).foregroundStyle(Forge.secondary)
    }
}

struct RunRow: View {
    let run: Run
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: run.isActive ? "waveform" : run.status == "failed" ? "exclamationmark.circle" : "terminal")
                .foregroundStyle(Forge.statusColor(run.status)).padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(run.title).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.white)
                Text("\(run.projectName) · \(run.agentName)").font(.caption).foregroundStyle(Forge.secondary)
                Text(run.dateLabel).font(.caption2).foregroundStyle(Forge.secondary)
            }
            Spacer(minLength: 0)
            Text(run.statusLabel).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Forge.statusColor(run.status))
        }.forgeCard()
    }
}
