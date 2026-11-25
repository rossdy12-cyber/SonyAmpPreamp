import SwiftUI
import WatchKit
import WatchConnectivity

struct WardenTarget: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var subtitle: String
    var host: String
    var bridgePort: Int
    var macAddress: String
    var platform: String
    var wakeURL: String
    var unlockURL: String
    var lockURL: String
    var wolBridgeHost: String
    var wolBridgePort: Int
    var unlockSecret: String

    static let empty = WardenTarget(id: "", name: "No PC", subtitle: "Open Warden on iPhone", host: "", bridgePort: 9090, macAddress: "", platform: "Windows", wakeURL: "", unlockURL: "", lockURL: "", wolBridgeHost: "", wolBridgePort: 9092, unlockSecret: "")
}

@MainActor
final class WatchStore: NSObject, ObservableObject {
    @Published var targets: [WardenTarget] = []
    @Published var selectedID: String = ""
    @Published var status: String = "Ready"
    @Published var busy = false

    private let key = "warden.watch.targets"
    private let selKey = "warden.watch.selected"

    override init() {
        super.init()
        loadCache()
        setupWC()
    }

    var selected: WardenTarget? { targets.first(where: { $0.id == selectedID }) ?? targets.first }

    func loadCache() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([WardenTarget].self, from: data), !decoded.isEmpty {
            targets = decoded
        }
        selectedID = UserDefaults.standard.string(forKey: selKey) ?? targets.first?.id ?? ""
    }

    func saveCache() {
        if let data = try? JSONEncoder().encode(targets) { UserDefaults.standard.set(data, forKey: key) }
        UserDefaults.standard.set(selectedID, forKey: selKey)
    }

    func apply(context: [String: Any]) {
        guard let arr = context["targets"] as? [[String: Any]] else { return }
        let mapped: [WardenTarget] = arr.compactMap { d in
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            return WardenTarget(
                id: id,
                name: name,
                subtitle: d["subtitle"] as? String ?? "",
                host: d["host"] as? String ?? "",
                bridgePort: d["bridgePort"] as? Int ?? 9090,
                macAddress: d["macAddress"] as? String ?? "",
                platform: d["platform"] as? String ?? "Windows",
                wakeURL: d["wakeURL"] as? String ?? "",
                unlockURL: d["unlockURL"] as? String ?? "",
                lockURL: d["lockURL"] as? String ?? "",
                wolBridgeHost: d["wolBridgeHost"] as? String ?? "",
                wolBridgePort: d["wolBridgePort"] as? Int ?? 9092,
                unlockSecret: d["unlockSecret"] as? String ?? ""
            )
        }
        if !mapped.isEmpty {
            targets = mapped
            let sel = context["selected"] as? String ?? ""
            if targets.contains(where: { $0.id == sel }) { selectedID = sel }
            else if !targets.contains(where: { $0.id == selectedID }) { selectedID = targets.first?.id ?? "" }
            saveCache()
        }
    }

    func setupWC() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    func sendAction(_ action: String, target: WardenTarget) {
        // Prefer direct HTTP for reliability; also notify iPhone
        busy = true
        status = "\(action.capitalized)..."
        Task {
            await perform(action: action, target: target)
            busy = false
        }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["action": action, "targetID": target.id], replyHandler: nil, errorHandler: nil)
        } else {
            WCSession.default.transferUserInfo(["action": action, "targetID": target.id])
        }
    }

    private func httpGet(_ urlString: String, timeout: TimeInterval = 6) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var req = URLRequest(url: url); req.timeoutInterval = timeout
        let ok = (try? await URLSession.shared.data(for: req)) != nil
        return ok
    }

    private func bridgeExec(host: String, port: Int, command: String) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/api/antigravity/exec") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": command, "timeout": 8])
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return ((resp as? HTTPURLResponse)?.statusCode ?? 0) < 400
        } catch { return false }
    }

    func perform(action: String, target: WardenTarget) async {
        let isWin = target.platform.lowercased().contains("win")
        var ok = false
        switch action {
        case "unlock":
            if !target.unlockURL.isEmpty {
                let url = target.unlockURL.replacingOccurrences(of: "{pin}", with: target.unlockSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
                ok = await httpGet(url)
            }
            if isWin {
                let pin = target.unlockSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                ok = await httpGet("http://\(target.host):\(target.bridgePort)/api/power/unlock?pin=\(pin)") || ok
                _ = await httpGet("http://\(target.host):9095/wake")
            } else {
                let cmd = "loginctl unlock-sessions; for s in $(loginctl list-sessions --no-legend | awk '{print $1}'); do loginctl unlock-session $s; done; DISPLAY=:0 xset dpms force on 2>/dev/null"
                ok = await bridgeExec(host: target.host, port: target.bridgePort, command: cmd) || ok
            }
            status = ok ? "🔓 Unlocked" : "🔓 Unlock sent"
        case "lock":
            if !target.lockURL.isEmpty { ok = await httpGet(target.lockURL) }
            else if isWin { ok = await bridgeExec(host: target.host, port: target.bridgePort, command: "rundll32.exe user32.dll,LockWorkStation") }
            else { ok = await bridgeExec(host: target.host, port: target.bridgePort, command: "loginctl lock-sessions") }
            status = ok ? "🔒 Locked" : "🔒 Lock sent"
        case "wake":
            if !target.wakeURL.isEmpty { ok = await httpGet(target.wakeURL) }
            if isWin { ok = await httpGet("http://\(target.host):9095/wake") || ok }
            else { ok = await bridgeExec(host: target.host, port: target.bridgePort, command: "DISPLAY=:0 xset dpms force on 2>/dev/null; loginctl unlock-sessions") || ok }
            if !target.wolBridgeHost.isEmpty {
                let cmd = "ping -c 1 -W 2 \(target.host) >/dev/null 2>&1 && echo awake || echo wake-requested"
                _ = await bridgeExec(host: target.wolBridgeHost, port: target.wolBridgePort, command: cmd)
            }
            status = ok ? "⚡ Wake sent" : "⚡ Wake requested"
        default:
            status = "Unknown action"
        }
        WKInterfaceDevice.current().play(.success)
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if activationState == .activated {
                self.apply(context: session.receivedApplicationContext)
            }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in self.apply(context: applicationContext) }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in self.apply(context: message) }
    }
}

@main
struct WardenWatchApp: App {
    @StateObject private var store = WatchStore()
    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(store)
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject var store: WatchStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if store.targets.isEmpty {
                        Text("Open Warden on iPhone to sync PCs.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else {
                        targetPicker
                        if let t = store.selected {
                            actionButtons(t)
                        }
                    }
                    Text(store.status)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    if store.busy { ProgressView() }
                }
                .padding(.horizontal, 6)
            }
            .navigationTitle("Warden")
        }
    }

    private var targetPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.targets) { t in
                    Button {
                        store.selectedID = t.id
                        store.saveCache()
                    } label: {
                        Text(t.name)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(store.selectedID == t.id ? Color(red: 0.72, green: 0.07, blue: 0.18) : Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func actionButtons(_ t: WardenTarget) -> some View {
        VStack(spacing: 8) {
            Button {
                store.sendAction("unlock", target: t)
            } label: {
                Label("Unlock", systemImage: "lock.open.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.20, green: 0.55, blue: 0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                store.sendAction("wake", target: t)
            } label: {
                Label("Wake", systemImage: "bolt.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.75, green: 0.35, blue: 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    store.sendAction("lock", target: t)
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.55, green: 0.08, blue: 0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            Text(t.host)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
    }
}
