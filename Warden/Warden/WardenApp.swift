import SwiftUI
import Network
import WatchConnectivity

// MARK: - Theme

enum WardenTheme {
    static let bg = Color(red: 0.04, green: 0.02, blue: 0.03)
    static let panel = Color(red: 0.10, green: 0.04, blue: 0.06)
    static let panel2 = Color(red: 0.14, green: 0.06, blue: 0.08)
    static let crimson = Color(red: 0.72, green: 0.07, blue: 0.18)
    static let rose = Color(red: 0.92, green: 0.28, blue: 0.38)
    static let ember = Color(red: 1.0, green: 0.45, blue: 0.25)
    static let text = Color(red: 0.95, green: 0.91, blue: 0.92)
    static let muted = Color(red: 0.62, green: 0.54, blue: 0.56)
    static let ok = Color(red: 0.35, green: 0.82, blue: 0.55)
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let danger = Color(red: 0.95, green: 0.25, blue: 0.30)
}

// MARK: - Model

enum PCPlatform: String, Codable, CaseIterable, Identifiable {
    case windows = "Windows"
    case linux = "Linux"
    var id: String { rawValue }
    var icon: String { self == .windows ? "desktopcomputer" : "terminal.fill" }
}

struct PCTarget: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var subtitle: String
    var host: String            // IP or Tailscale hostname
    var bridgePort: Int         // HTTP bridge/control port
    var macAddress: String      // for WOL reference/display
    var platform: PCPlatform
    var wakeURL: String         // optional explicit URL; empty = default
    var unlockURL: String       // optional explicit URL; empty = default
    var lockURL: String         // optional explicit URL; empty = default
    var wolBridgeHost: String   // host that can send WOL/ping (e.g. TrueNAS)
    var wolBridgePort: Int
    var unlockSecret: String    // optional PIN/password sent to bridge; stored locally

    static let homeDefault = PCTarget(
        name: "Home PC (Aether-PC)",
        subtitle: "Home Gaming & Workstation · 100.64.0.8",
        host: "100.64.0.8",
        bridgePort: 9090,
        macAddress: "B8:FB:B3:C6:0E:7D",
        platform: .windows,
        wakeURL: "http://100.64.0.8:9090/api/power/wake",
        unlockURL: "http://100.64.0.8:9090/api/power/unlock?pin={pin}",
        lockURL: "http://100.64.0.8:9090/api/power/lock",
        wolBridgeHost: "100.64.0.4",
        wolBridgePort: 9092,
        unlockSecret: ""
    )

    static let workDefault = PCTarget(
        name: "Work PC (ROSS-DYMOND-PC)",
        subtitle: "Work Workstation · 100.64.0.3",
        host: "100.64.0.3",
        bridgePort: 9090,
        macAddress: "2C:56:DC:39:E5:DC",
        platform: .windows,
        wakeURL: "http://100.64.0.3:9090/api/power/wake",
        unlockURL: "http://100.64.0.3:9090/api/power/unlock?pin={pin}",
        lockURL: "http://100.64.0.3:9090/api/power/lock",
        wolBridgeHost: "100.64.0.4",
        wolBridgePort: 9092,
        unlockSecret: ""
    )
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    let date: Date
    let target: String
    let action: String
    let detail: String
    let ok: Bool
}

// MARK: - Store

@MainActor
final class WardenStore: NSObject, ObservableObject {
    @Published var targets: [PCTarget] = []
    @Published var selectedID: UUID?
    @Published var isBusy = false
    @Published var statusBanner = "Ready."
    @Published var lastSeen: [UUID: Date] = [:]
    @Published var log: [ActivityEntry] = []

    private let defaultsKey = "warden.targets.v1"
    private let selectedKey = "warden.selected.v1"
    private var wcSession: WCSession?

    override init() {
        super.init()
        load()
        setupWatchConnectivity()
    }

    var selected: PCTarget? {
        targets.first(where: { $0.id == selectedID }) ?? targets.first
    }

    func select(_ target: PCTarget) {
        selectedID = target.id
        UserDefaults.standard.set(target.id.uuidString, forKey: selectedKey)
        pushToWatch()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           var decoded = try? JSONDecoder().decode([PCTarget].self, from: data),
           !decoded.isEmpty {
            // Auto-migrate legacy 100.102.4.54 defaults to actual Headscale IPs (100.64.0.8 & 100.64.0.3)
            var migrated = false
            for idx in decoded.indices {
                if decoded[idx].host == "100.102.4.54" {
                    if decoded[idx].name.lowercased().contains("home") {
                        let keepId = decoded[idx].id
                        let keepPin = decoded[idx].unlockSecret
                        decoded[idx] = .homeDefault
                        decoded[idx].id = keepId
                        decoded[idx].unlockSecret = keepPin
                    } else {
                        let keepId = decoded[idx].id
                        let keepPin = decoded[idx].unlockSecret
                        decoded[idx] = .workDefault
                        decoded[idx].id = keepId
                        decoded[idx].unlockSecret = keepPin
                    }
                    migrated = true
                }
            }
            targets = decoded
            if migrated { save() }
        } else {
            targets = [.homeDefault, .workDefault]
        }
        if let sid = UserDefaults.standard.string(forKey: selectedKey),
           let uuid = UUID(uuidString: sid),
           targets.contains(where: { $0.id == uuid }) {
            selectedID = uuid
        } else {
            selectedID = targets.first?.id
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        if let selectedID { UserDefaults.standard.set(selectedID.uuidString, forKey: selectedKey) }
        pushToWatch()
    }

    func addTarget() {
        let t = PCTarget(name: "New PC", subtitle: "Tap to configure", host: "100.x.x.x", bridgePort: 9090, macAddress: "", platform: .windows, wakeURL: "", unlockURL: "", lockURL: "", wolBridgeHost: "100.85.127.42", wolBridgePort: 9092, unlockSecret: "")
        targets.append(t)
        selectedID = t.id
        save()
    }

    func delete(_ target: PCTarget) {
        targets.removeAll { $0.id == target.id }
        if selectedID == target.id { selectedID = targets.first?.id }
        if targets.isEmpty { targets = [.homeDefault]; selectedID = targets.first?.id }
        save()
    }

    func move(from: IndexSet, to: Int) {
        targets.move(fromOffsets: from, toOffset: to)
        save()
    }

    func update(_ target: PCTarget) {
        if let idx = targets.firstIndex(where: { $0.id == target.id }) {
            targets[idx] = target
            save()
        }
    }

    // MARK: - Logging

    private func record(_ target: PCTarget, action: String, detail: String, ok: Bool) {
        let entry = ActivityEntry(date: Date(), target: target.name, action: action, detail: detail, ok: ok)
        log.insert(entry, at: 0)
        if log.count > 50 { log = Array(log.prefix(50)) }
        statusBanner = detail
    }

    // MARK: - Networking helpers

    private func httpGet(_ urlString: String, timeout: TimeInterval = 6) async -> (Bool, String) {
        guard let url = URL(string: urlString) else { return (false, "Bad URL") }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (code >= 200 && code < 300, body.isEmpty ? "HTTP \(code)" : String(body.prefix(200)))
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func httpPostJSON(_ urlString: String, json: [String: Any], timeout: TimeInterval = 8) async -> (Bool, String) {
        guard let url = URL(string: urlString) else { return (false, "Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: json)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (code >= 200 && code < 300, body.isEmpty ? "HTTP \(code)" : String(body.prefix(200)))
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func bridgeExec(host: String, port: Int, command: String, timeout: Int = 8) async -> (Bool, String) {
        await httpPostJSON("http://\(host):\(port)/api/antigravity/exec", json: ["command": command, "timeout": timeout])
    }

    // MARK: - Actions

    func ping(_ target: PCTarget) async {
        isBusy = true
        defer { isBusy = false }
        // Try bridge state endpoint, then exec ping fallback via WOL bridge
        let stateURL = "http://\(target.host):\(target.bridgePort)/api/antigravity/state"
        let (ok, body) = await httpGet(stateURL, timeout: 4)
        if ok {
            lastSeen[target.id] = Date()
            record(target, action: "Ping", detail: "Online — \(body)", ok: true)
            return
        }
        // Fallback: ask WOL bridge to ping
        if !target.wolBridgeHost.isEmpty {
            let (ok2, out) = await bridgeExec(host: target.wolBridgeHost, port: target.wolBridgePort, command: "ping -c 1 -W 2 \(target.host) >/dev/null 2>&1 && echo ONLINE || echo OFFLINE", timeout: 6)
            if ok2 && out.uppercased().contains("ONLINE") {
                lastSeen[target.id] = Date()
                record(target, action: "Ping", detail: "Reachable via Tailscale/LAN", ok: true)
                return
            }
        }
        record(target, action: "Ping", detail: "No response — \(body)", ok: false)
    }

    func wake(_ target: PCTarget) async {
        isBusy = true
        defer { isBusy = false }
        var messages: [String] = []

        // Explicit wake URL
        if !target.wakeURL.isEmpty {
            let (ok, body) = await httpGet(target.wakeURL, timeout: 6)
            messages.append(ok ? "Wake URL OK" : "Wake URL: \(body)")
        }

        // Platform-specific bridge wake endpoints (DeskSwitch-compatible)
        if target.platform == .windows {
            let (ok1, _) = await httpGet("http://\(target.host):9095/wake", timeout: 4)
            if ok1 { messages.append("9095/wake OK") }
            let (ok2, _) = await httpGet("http://\(target.host):\(target.bridgePort)/api/power/wake", timeout: 4)
            if ok2 { messages.append("power/wake OK") }
        } else {
            let (ok, _) = await bridgeExec(host: target.host, port: target.bridgePort, command: "loginctl unlock-sessions; DISPLAY=:0 xset dpms force on 2>/dev/null; kscreen-doctor --dpms on 2>/dev/null; qdbus org.freedesktop.ScreenSaver /ScreenSaver SetActive false 2>/dev/null", timeout: 6)
            if ok { messages.append("Linux wake cmd OK") }
        }

        // WOL via bridge agent (TrueNAS always-on)
        if !target.wolBridgeHost.isEmpty {
            var wolCmd = "echo 'Wake requested for \(target.name) (\(target.host))'"
            if !target.macAddress.trimmingCharacters(in: .whitespaces).isEmpty {
                let mac = target.macAddress.trimmingCharacters(in: .whitespaces)
                wolCmd = "python3 -c \"import socket,binascii;mac=binascii.unhexlify('\(mac.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: ""))');s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1);s.sendto(b'\\xff'*6+mac*16,('<broadcast>',9));print('WOL sent')\" 2>&1 || wakeonlan \(mac) 2>&1 || etherwake \(mac) 2>&1; echo 'WOL dispatched for \(target.name)'"
            } else {
                wolCmd = "ping -c 1 -W 2 \(target.host) >/dev/null 2>&1 && echo '\(target.host) already awake' || echo 'No MAC set; ping dispatched from bridge to \(target.host)'"
            }
            let (ok, out) = await bridgeExec(host: target.wolBridgeHost, port: target.wolBridgePort, command: wolCmd, timeout: 8)
            messages.append(ok ? "Bridge: \(out)" : "Bridge: \(out)")
        }

        let detail = messages.isEmpty ? "Wake sent." : messages.joined(separator: " · ")
        record(target, action: "Wake", detail: detail, ok: true)
    }

    func unlock(_ target: PCTarget) async {
        isBusy = true
        defer { isBusy = false }
        var messages: [String] = []

        // Explicit unlock URL
        if !target.unlockURL.isEmpty {
            let url = target.unlockURL.replacingOccurrences(of: "{pin}", with: target.unlockSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
            let (ok, body) = await httpGet(url, timeout: 6)
            messages.append(ok ? "Unlock URL OK" : "Unlock URL: \(body)")
        }

        if target.platform == .windows {
            let pin = target.unlockSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let (ok1, body1) = await httpGet("http://\(target.host):\(target.bridgePort)/api/power/unlock?pin=\(pin)", timeout: 6)
            messages.append(ok1 ? "Bridge unlock OK" : "Bridge unlock: \(body1)")
            let (ok2, _) = await httpGet("http://\(target.host):9095/wake", timeout: 4)
            if ok2 { messages.append("Wake screen OK") }
            // Fallback: send F15 to nudge lock screen
            let (ok3, _) = await bridgeExec(host: target.host, port: target.bridgePort, command: "powershell -Command \"$w = New-Object -ComObject WScript.Shell; $w.SendKeys('{F15}')\"", timeout: 5)
            if ok3 { messages.append("F15 nudge sent") }
        } else {
            let cmd = "loginctl unlock-sessions; for s in $(loginctl list-sessions --no-legend | awk '{print $1}'); do loginctl unlock-session $s; done; DISPLAY=:0 xset dpms force on 2>/dev/null; qdbus org.freedesktop.ScreenSaver /ScreenSaver SetActive false 2>/dev/null; dbus-send --session --dest=org.freedesktop.ScreenSaver --type=method_call /ScreenSaver org.freedesktop.ScreenSaver.SetActive boolean:false 2>/dev/null; kscreen-doctor --dpms on 2>/dev/null"
            let (ok, body) = await bridgeExec(host: target.host, port: target.bridgePort, command: cmd, timeout: 8)
            messages.append(ok ? "Linux unlock OK" : "Linux unlock: \(body)")
            let (ok2, _) = await httpGet("http://\(target.host):\(target.bridgePort)/api/power/bazzite/unlock", timeout: 4)
            if ok2 { messages.append("bazzite/unlock OK") }
        }

        let detail = messages.isEmpty ? "Unlock sent." : messages.joined(separator: " · ")
        record(target, action: "Unlock", detail: "🔓 \(detail)", ok: true)
    }

    func lock(_ target: PCTarget) async {
        isBusy = true
        defer { isBusy = false }
        if !target.lockURL.isEmpty {
            let (ok, body) = await httpGet(target.lockURL, timeout: 6)
            record(target, action: "Lock", detail: ok ? "🔒 Lock URL OK" : "Lock URL: \(body)", ok: ok)
            return
        }
        if target.platform == .windows {
            let (ok, body) = await bridgeExec(host: target.host, port: target.bridgePort, command: "rundll32.exe user32.dll,LockWorkStation", timeout: 6)
            record(target, action: "Lock", detail: ok ? "🔒 Windows locked" : "Lock failed: \(body)", ok: ok)
        } else {
            let (ok, body) = await bridgeExec(host: target.host, port: target.bridgePort, command: "loginctl lock-sessions; qdbus org.freedesktop.ScreenSaver /ScreenSaver Lock 2>/dev/null; dbus-send --session --dest=org.freedesktop.ScreenSaver --type=method_call /ScreenSaver org.freedesktop.ScreenSaver.Lock 2>/dev/null", timeout: 6)
            record(target, action: "Lock", detail: ok ? "🔒 Linux locked" : "Lock failed: \(body)", ok: ok)
        }
    }

    func sleep(_ target: PCTarget) async {
        isBusy = true
        defer { isBusy = false }
        if target.platform == .windows {
            let (ok, body) = await bridgeExec(host: target.host, port: target.bridgePort, command: "rundll32.exe powrprof.dll,SetSuspendState 0,1,0", timeout: 6)
            record(target, action: "Sleep", detail: ok ? "Sleep sent" : "Sleep failed: \(body)", ok: ok)
        } else {
            let (ok, body) = await bridgeExec(host: target.host, port: target.bridgePort, command: "systemctl suspend", timeout: 6)
            record(target, action: "Sleep", detail: ok ? "Sleep sent" : "Sleep failed: \(body)", ok: ok)
        }
    }

    // MARK: - Watch Connectivity

    func setupWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        wcSession = session
    }

    func pushToWatch() {
        guard let session = wcSession else { return }
        let payload: [[String: Any]] = targets.map { t in
            [
                "id": t.id.uuidString,
                "name": t.name,
                "subtitle": t.subtitle,
                "host": t.host,
                "bridgePort": t.bridgePort,
                "macAddress": t.macAddress,
                "platform": t.platform.rawValue,
                "wakeURL": t.wakeURL,
                "unlockURL": t.unlockURL,
                "lockURL": t.lockURL,
                "wolBridgeHost": t.wolBridgeHost,
                "wolBridgePort": t.wolBridgePort,
                "unlockSecret": t.unlockSecret
            ]
        }
        let context: [String: Any] = ["targets": payload, "selected": selectedID?.uuidString ?? ""]
        try? session.updateApplicationContext(context)
        if session.isReachable {
            session.sendMessage(context, replyHandler: nil, errorHandler: nil)
        }
    }
}

extension WardenStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if activationState == .activated { self.pushToWatch() }
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleWatchMessage(message)
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleWatchMessage(userInfo)
    }
    nonisolated private func handleWatchMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String,
              let idStr = message["targetID"] as? String,
              let uuid = UUID(uuidString: idStr) else { return }
        Task { @MainActor in
            guard let target = self.targets.first(where: { $0.id == uuid }) else { return }
            switch action {
            case "unlock": await self.unlock(target)
            case "lock": await self.lock(target)
            case "wake": await self.wake(target)
            case "ping": await self.ping(target)
            case "sleep": await self.sleep(target)
            default: break
            }
        }
    }
}

// MARK: - UI

@main
struct WardenApp: App {
    @StateObject private var store = WardenStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: WardenStore
    var body: some View {
        TabView {
            ControlDeckView()
                .tabItem { Label("Warden", systemImage: "lock.shield.fill") }
            TargetsView()
                .tabItem { Label("PCs", systemImage: "desktopcomputer") }
            LogView()
                .tabItem { Label("Log", systemImage: "scroll.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(WardenTheme.rose)
    }
}

struct ControlDeckView: View {
    @EnvironmentObject var store: WardenStore

    var body: some View {
        NavigationStack {
            ZStack {
                WardenTheme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        if let target = store.selected {
                            targetCard(target)
                            actionGrid(target)
                            detailsCard(target)
                        } else {
                            Text("No PC configured. Add one in PCs tab.")
                                .foregroundColor(WardenTheme.muted)
                                .padding()
                        }
                        statusCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Warden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isBusy { ProgressView().tint(WardenTheme.rose) }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PC UNLOCK & CONTROL")
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundColor(WardenTheme.rose)
            Text("Home and work, from your wrist or pocket.")
                .font(.subheadline)
                .foregroundColor(WardenTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func targetCard(_ target: PCTarget) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: target.platform.icon)
                    .font(.title2)
                    .foregroundColor(WardenTheme.rose)
                    .frame(width: 42, height: 42)
                    .background(WardenTheme.crimson.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name).font(.headline).foregroundColor(WardenTheme.text)
                    Text(target.subtitle).font(.caption).foregroundColor(WardenTheme.muted)
                }
                Spacer()
                Menu {
                    ForEach(store.targets) { t in
                        Button {
                            store.select(t)
                        } label: {
                            Label(t.name, systemImage: t.id == target.id ? "checkmark" : t.platform.icon)
                        }
                    }
                } label: {
                    Label("Switch", systemImage: "arrow.left.arrow.right")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(WardenTheme.panel2)
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 10) {
                pill(icon: "network", text: target.host)
                pill(icon: "antenna.radiowaves.left.and.right", text: ":\(target.bridgePort)")
                if let seen = store.lastSeen[target.id] {
                    pill(icon: "clock", text: seen.formatted(date: .omitted, time: .shortened))
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(WardenTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(WardenTheme.crimson.opacity(0.35), lineWidth: 1))
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2.monospaced())
        }
        .foregroundColor(WardenTheme.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(WardenTheme.bg.opacity(0.6))
        .clipShape(Capsule())
    }

    private func actionGrid(_ target: PCTarget) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            actionButton("Unlock", icon: "lock.open.fill", color: WardenTheme.ok) {
                Task { await store.unlock(target) }
            }
            actionButton("Wake", icon: "bolt.fill", color: WardenTheme.ember) {
                Task { await store.wake(target) }
            }
            actionButton("Lock", icon: "lock.fill", color: WardenTheme.rose) {
                Task { await store.lock(target) }
            }
            actionButton("Sleep", icon: "moon.fill", color: WardenTheme.muted) {
                Task { await store.sleep(target) }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.title2.bold())
                Text(title).font(.headline)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(RoundedRectangle(cornerRadius: 16).fill(WardenTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy)
    }

    private func detailsCard(_ target: PCTarget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONNECTION")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundColor(WardenTheme.muted)
            detailRow("Platform", target.platform.rawValue)
            detailRow("Bridge", "\(target.host):\(target.bridgePort)")
            detailRow("WOL Bridge", target.wolBridgeHost.isEmpty ? "Not set" : "\(target.wolBridgeHost):\(target.wolBridgePort)")
            detailRow("MAC", target.macAddress.isEmpty ? "Not set" : target.macAddress)
            Button {
                Task { await store.ping(target) }
            } label: {
                Label("Ping / Check Status", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(WardenTheme.panel2)
                    .foregroundColor(WardenTheme.text)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(WardenTheme.panel))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(WardenTheme.muted)
            Spacer()
            Text(value).foregroundColor(WardenTheme.text).monospaced()
        }
        .font(.caption)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATUS")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundColor(WardenTheme.muted)
            Text(store.statusBanner)
                .font(.footnote)
                .foregroundColor(WardenTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(WardenTheme.panel))
    }
}

struct TargetsView: View {
    @EnvironmentObject var store: WardenStore
    @State private var editing: PCTarget?

    var body: some View {
        NavigationStack {
            ZStack {
                WardenTheme.bg.ignoresSafeArea()
                List {
                    ForEach(store.targets) { target in
                        Button { editing = target } label: {
                            HStack(spacing: 12) {
                                Image(systemName: target.platform.icon)
                                    .foregroundColor(WardenTheme.rose)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.name).foregroundColor(WardenTheme.text)
                                    Text("\(target.host):\(target.bridgePort)")
                                        .font(.caption.monospaced())
                                        .foregroundColor(WardenTheme.muted)
                                }
                                Spacer()
                                if store.selectedID == target.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(WardenTheme.ok)
                                }
                            }
                        }
                        .listRowBackground(WardenTheme.panel)
                    }
                    .onDelete { idx in
                        for i in idx { store.delete(store.targets[i]) }
                    }
                    .onMove(perform: store.move)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("PCs")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton().tint(WardenTheme.rose) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.addTarget(); editing = store.targets.last } label: {
                        Image(systemName: "plus")
                    }.tint(WardenTheme.rose)
                }
            }
            .sheet(item: $editing) { target in
                TargetEditorView(target: target)
                    .environmentObject(store)
            }
        }
    }
}

struct TargetEditorView: View {
    @EnvironmentObject var store: WardenStore
    @Environment(\.dismiss) var dismiss
    @State var target: PCTarget

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $target.name)
                    TextField("Subtitle", text: $target.subtitle)
                    Picker("Platform", selection: $target.platform) {
                        ForEach(PCPlatform.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                }
                Section("Connection") {
                    TextField("Host / IP / Tailscale", text: $target.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Bridge Port", value: $target.bridgePort, format: .number)
                        .keyboardType(.numberPad)
                    TextField("MAC Address (optional)", text: $target.macAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Wake / Unlock / Lock URLs (optional overrides)") {
                    TextField("Wake URL", text: $target.wakeURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Unlock URL ({pin} placeholder)", text: $target.unlockURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Lock URL", text: $target.lockURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Unlock Secret / PIN", text: $target.unlockSecret)
                }
                Section("WOL / Always-on Bridge") {
                    TextField("Bridge Host (e.g. TrueNAS)", text: $target.wolBridgeHost)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Bridge Port", value: $target.wolBridgePort, format: .number)
                        .keyboardType(.numberPad)
                }
                Section {
                    Button("Use as Selected PC") { store.select(target); store.update(target); dismiss() }
                    Button("Delete PC", role: .destructive) { store.delete(target); dismiss() }
                }
            }
            .navigationTitle("Edit PC")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.update(target); dismiss() }.bold()
                }
            }
        }
    }
}

struct LogView: View {
    @EnvironmentObject var store: WardenStore
    var body: some View {
        NavigationStack {
            ZStack {
                WardenTheme.bg.ignoresSafeArea()
                if store.log.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "scroll").font(.largeTitle).foregroundColor(WardenTheme.muted)
                        Text("No actions yet").foregroundColor(WardenTheme.muted)
                    }
                } else {
                    List(store.log) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: entry.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(entry.ok ? WardenTheme.ok : WardenTheme.danger)
                                Text(entry.action).font(.headline).foregroundColor(WardenTheme.text)
                                Text(entry.target).font(.caption).foregroundColor(WardenTheme.rose)
                                Spacer()
                                Text(entry.date.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2).foregroundColor(WardenTheme.muted)
                            }
                            Text(entry.detail)
                                .font(.caption)
                                .foregroundColor(WardenTheme.muted)
                                .lineLimit(3)
                        }
                        .listRowBackground(WardenTheme.panel)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Log")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: WardenStore
    var body: some View {
        NavigationStack {
            ZStack {
                WardenTheme.bg.ignoresSafeArea()
                Form {
                    Section("About Warden") {
                        Text("Warden unlocks and controls your PCs over LAN/Tailscale using HTTP bridge endpoints. Configure each PC with its host, bridge port, and optional unlock URL/PIN.")
                            .font(.footnote)
                            .foregroundColor(WardenTheme.muted)
                    }
                    Section("Bridge Compatibility") {
                        Label("Windows: /api/power/unlock?pin=...", systemImage: "desktopcomputer")
                        Label("Windows wake: /wake on port 9095", systemImage: "bolt.fill")
                        Label("Linux: loginctl unlock-session via bridge exec", systemImage: "terminal.fill")
                        Label("WOL/Bridge: TrueNAS agent exec on port 9092", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    Section("Watch") {
                        Text("Install the Warden watch app from the iPhone Watch app after installing Warden. The watch uses the saved PC targets and can send unlock/wake/lock commands over the network.")
                            .font(.footnote)
                            .foregroundColor(WardenTheme.muted)
                    }
                    Section("Defaults") {
                        Button("Reset to Home + Work Defaults", role: .destructive) {
                            store.targets = [.homeDefault, .workDefault]
                            store.selectedID = store.targets.first?.id
                            store.save()
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
        }
    }
}
