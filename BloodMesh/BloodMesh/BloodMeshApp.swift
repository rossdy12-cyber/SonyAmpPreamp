import SwiftUI
import WidgetKit
import UIKit
import Network
import NetworkExtension
import Darwin

// MARK: - Models

struct HeadscaleHealth: Codable {
    let status: String
    let server_url: String
    let server_ip: String
    let truenas_mesh_ip: String
    let router_mesh_ip: String
    let pc_mesh_ip: String
    let iphone_mesh_ip: String
    let derp_region: Int
    let derp_code: String
    let derp_name: String
    let stun_port: Int
    let magic_dns_domain: String
    let version: String
}

struct HeadscaleSummary: Codable {
    let total_nodes: Int
    let online_nodes: Int
    let serving_routes: [String]
    let lan_subnet_active: Bool
    let sidestore_tun_active: Bool
    let exit_node_name: String
    let exit_node_online: Bool
}

struct HeadscaleNode: Codable, Identifiable {
    let id: Int
    let name: String
    let given_name: String
    let fqdn: String
    let user: String
    let role: String
    let ip_addresses: [String]
    let ipv4: String
    let ipv6: String
    let online: Bool
    let tags: [String]
    let approved_routes: [String]
    let available_routes: [String]
    let subnet_routes: [String]
    let is_exit_node: Bool
    let exit_node_approved: Bool
    let last_seen_epoch: Int
    let last_seen_ago_sec: Int
    let created_epoch: Int
}

struct HeadscaleStatusResponse: Codable {
    let ok: Bool
    let timestamp: Int?
    let message: String?
    let error: String?
    let health: HeadscaleHealth?
    let summary: HeadscaleSummary?
    let nodes: [HeadscaleNode]?
    let preauth_keys_count: Int?
}

struct PreAuthKeyResponse: Codable {
    let ok: Bool
    let key: String?
    let expiration: String?
    let reusable: Bool?
    let tags: [String]?
    let command: String?
    let error: String?
}

struct LocalTunnelTelemetry {
    var isSealed: Bool = false
    var interfaceName: String = "utun"
    var ipv4: String = "100.64.0.1"
    var ipv6: String = "fd7a:115c:a1e0::1"
    var rxBytes: UInt64 = 0
    var txBytes: UInt64 = 0
    var wifiOrCellIP: String = "—"
}

struct ProbeTarget: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let host: String
    let port: UInt16
    var latencyMs: Int?
    var reachable: Bool?
}

// MARK: - Local iOS utun Interface Telemetry Inspector

enum iOSTunnelScanner {
    static func scan() -> LocalTunnelTelemetry {
        var result = LocalTunnelTelemetry()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return result
        }
        defer { freeifaddrs(ifaddr) }

        var utunByteMap: [String: (rx: UInt64, tx: UInt64)] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = first

        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let name = String(cString: current.pointee.ifa_name)

            if isUp, let addr = current.pointee.ifa_addr {
                let fam = Int32(addr.pointee.sa_family)
                if fam == AF_LINK, let data = current.pointee.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                    utunByteMap[name] = (UInt64(ifData.ifi_ibytes), UInt64(ifData.ifi_obytes))
                } else if fam == AF_INET {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: host)
                        if ip.hasPrefix("100.64.") || ip.hasPrefix("100.") {
                            result.isSealed = true
                            result.interfaceName = name
                            result.ipv4 = ip
                        } else if (name == "en0" || name == "pdp_ip0") && !ip.hasPrefix("127.") {
                            result.wifiOrCellIP = "\(ip) (\(name))"
                        }
                    }
                } else if fam == AF_INET6 {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip6 = String(cString: host)
                        if ip6.lowercased().hasPrefix("fd7a:115c:a1e0:") {
                            result.ipv6 = ip6.components(separatedBy: "%").first ?? ip6
                            if !result.isSealed {
                                result.isSealed = true
                                result.interfaceName = name
                            }
                        }
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }

        if let bytes = utunByteMap[result.interfaceName] {
            result.rxBytes = bytes.rx
            result.txBytes = bytes.tx
        }
        return result
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024.0)
    }
}

// MARK: - ViewModel (with Native NETunnelProviderManager Control)

@MainActor
final class BloodMeshViewModel: ObservableObject {
    @Published var localTunnel = iOSTunnelScanner.scan()
    @Published var vpnStatus: NEVPNStatus = .invalid
    @Published var exitNodeEnabled: Bool = false
    @Published var onDemandEnabled: Bool = false
    @Published var providerRxBytes: UInt64 = 0
    @Published var providerTxBytes: UInt64 = 0

    @Published var health: HeadscaleHealth?
    @Published var summary: HeadscaleSummary?
    @Published var nodes: [HeadscaleNode] = []
    @Published var preauthKeyCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var bannerMessage: String?
    @Published var isErrorBanner: Bool = false

    // Registration & Key Forge
    @Published var authReqInput: String = ""
    @Published var registerUser: String = "ross" // "ross", "mo", "lauren"
    @Published var selectedUserFilter: String = "all" // "all", "ross", "mo", "lauren", "infra"
    @Published var forgeRole: String = "ross" // "ross", "mo", "lauren", "tag:server", "tag:router"
    @Published var forgeExpiration: String = "24h"
    @Published var forgeReusable: Bool = true
    @Published var forgedKey: PreAuthKeyResponse?

    // Rename dialog
    @Published var renamingNode: HeadscaleNode?
    @Published var renameText: String = ""

    // Latency Probes
    @Published var probes: [ProbeTarget] = [
        ProbeTarget(id: "derp", title: "Headscale Control & DERP 999", subtitle: "hs.nas-server.co.uk:443", host: "hs.nas-server.co.uk", port: 443),
        ProbeTarget(id: "truenas", title: "TrueNAS Sanctum (Mesh)", subtitle: "100.64.0.4:18998", host: "100.64.0.4", port: 18998),
        ProbeTarget(id: "router_mesh", title: "ASUS Router (Mesh)", subtitle: "100.64.0.2:26", host: "100.64.0.2", port: 26),
        ProbeTarget(id: "router_lan", title: "ASUS Router (Home LAN Subnet)", subtitle: "192.168.0.116:26", host: "192.168.0.116", port: 26),
        ProbeTarget(id: "sidestore", title: "SideStore Signing TUN", subtitle: "10.7.0.1:18998", host: "10.7.0.1", port: 18998)
    ]

    private var tunnelManager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var telemetryTimer: Timer?

    private let tunnelBundleId = "com.ross.bloodmesh.tunnel"
    private let endpoints = [
        "https://hs.nas-server.co.uk/sanctum-api",
        "http://100.64.0.4:18998/sidestore-api/headscale"
    ]

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            Task { @MainActor in
                guard let self = self else { return }
                if let conn = notif.object as? NEVPNConnection {
                    self.vpnStatus = conn.status
                } else if let mgr = self.tunnelManager {
                    self.vpnStatus = mgr.connection.status
                }
                self.localTunnel = iOSTunnelScanner.scan()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }

        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollProviderTelemetry()
            }
        }
    }

    var isTunnelConnected: Bool {
        vpnStatus == .connected || localTunnel.isSealed
    }

    var vpnStatusText: String {
        switch vpnStatus {
        case .connected: return "BLOODLINE VPN SEALED"
        case .connecting: return "FORGING BLOODLINE..."
        case .reasserting: return "REASSERTING SEAL..."
        case .disconnecting: return "SEVERING TUNNEL..."
        case .disconnected: return localTunnel.isSealed ? "EXTERNAL UTUN ACTIVE" : "TUNNEL SEVERED"
        case .invalid: return localTunnel.isSealed ? "EXTERNAL UTUN ACTIVE" : "READY TO CONSECRATE VPN"
        @unknown default: return "TUNNEL STANDBY"
        }
    }

    func loadOrConfigureVPNManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let existing = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleId
            }) ?? managers.first {
                self.tunnelManager = existing
                self.vpnStatus = existing.connection.status
                self.onDemandEnabled = existing.isOnDemandEnabled
                if let proto = existing.protocolConfiguration as? NETunnelProviderProtocol,
                   let cfgExit = proto.providerConfiguration?["exitNodeEnabled"] as? Bool {
                    self.exitNodeEnabled = cfgExit
                }
            }
        } catch {
            // Will create when user taps Seal VPN
        }
    }

    private func ensureConfiguredManager() async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let mgr = managers.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleId
        }) ?? managers.first ?? NETunnelProviderManager()

        let proto = (mgr.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleId
        proto.serverAddress = "hs.nas-server.co.uk (38.9.96.58:41642)"
        proto.providerConfiguration = [
            "exitNodeEnabled": exitNodeEnabled,
            "serverIP": "38.9.96.58",
            "serverPort": 41642,
            "magicDNSDomain": "mesh.internal"
        ]
        mgr.protocolConfiguration = proto
        mgr.localizedDescription = "BloodMesh ✠ Headscale Sanctum"
        mgr.isEnabled = true
        mgr.isOnDemandEnabled = onDemandEnabled
        if onDemandEnabled {
            let connectRule = NEOnDemandRuleConnect()
            connectRule.interfaceTypeMatch = .any
            mgr.onDemandRules = [connectRule]
        } else {
            mgr.onDemandRules = []
        }

        try await mgr.saveToPreferences()
        try await mgr.loadFromPreferences()
        self.tunnelManager = mgr
        self.vpnStatus = mgr.connection.status
        return mgr
    }

    func toggleVPNTunnel() async {
        do {
            let mgr = try await ensureConfiguredManager()
            if mgr.connection.status == .connected || mgr.connection.status == .connecting {
                if mgr.isOnDemandEnabled {
                    onDemandEnabled = false
                    mgr.isOnDemandEnabled = false
                    try? await mgr.saveToPreferences()
                }
                mgr.connection.stopVPNTunnel()
                showBanner("BloodMesh VPN tunnel severed.", error: false)
            } else {
                let opts: [String: NSObject] = [
                    "exitNode": NSNumber(value: exitNodeEnabled)
                ]
                try mgr.connection.startVPNTunnel(options: opts)
                showBanner("BloodMesh native Packet Tunnel activated (100.64.0.1).", error: false)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                localTunnel = iOSTunnelScanner.scan()
                runLatencyProbes()
                await refreshAll()
            }
        } catch {
            showBanner("VPN Engine Error: \(error.localizedDescription)", error: true)
        }
    }

    func applyExitNodeOrOnDemandChange() async {
        do {
            let mgr = try await ensureConfiguredManager()
            if mgr.connection.status == .connected {
                mgr.connection.stopVPNTunnel()
                try? await Task.sleep(nanoseconds: 500_000_000)
                try mgr.connection.startVPNTunnel(options: ["exitNode": NSNumber(value: exitNodeEnabled)])
                showBanner("Re-sealed tunnel (Exit Node: \(exitNodeEnabled ? "ON" : "OFF")).", error: false)
            } else {
                showBanner("Saved VPN configuration.", error: false)
            }
        } catch {
            showBanner("Failed to save VPN preferences: \(error.localizedDescription)", error: true)
        }
    }

    func pollProviderTelemetry() {
        localTunnel = iOSTunnelScanner.scan()
        guard let session = tunnelManager?.connection as? NETunnelProviderSession,
              session.status == .connected else { return }
        let msg = try? JSONSerialization.data(withJSONObject: ["cmd": "stats"])
        guard let msg = msg else { return }
        try? session.sendProviderMessage(msg) { [weak self] data in
            guard let data = data,
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let rx = (dict["rxBytes"] as? NSNumber)?.uint64Value ?? 0
            let tx = (dict["txBytes"] as? NSNumber)?.uint64Value ?? 0
            Task { @MainActor in
                self?.providerRxBytes = rx
                self?.providerTxBytes = tx
            }
        }
    }

    func refreshAll() async {
        localTunnel = iOSTunnelScanner.scan()
        isLoading = true
        defer { isLoading = false }

        for base in endpoints {
            guard let url = URL(string: "\(base)?action=status") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            req.setValue("close", forHTTPHeaderField: "Connection")
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let decoded = try JSONDecoder().decode(HeadscaleStatusResponse.self, from: data)
                if decoded.ok {
                    applyStatus(decoded)
                    WidgetCenter.shared.reloadAllTimelines()
                    return
                }
            } catch {
                continue
            }
        }
    }

    private func applyStatus(_ resp: HeadscaleStatusResponse) {
        if let h = resp.health { self.health = h }
        if let s = resp.summary { self.summary = s }
        if let n = resp.nodes { self.nodes = n }
        if let c = resp.preauth_keys_count { self.preauthKeyCount = c }
        if let msg = resp.message, !msg.isEmpty {
            showBanner(msg, error: false)
        }
    }

    func showBanner(_ text: String, error: Bool) {
        bannerMessage = text
        isErrorBanner = error
    }

    func postAction(_ payload: [String: Any]) async {
        isLoading = true
        defer { isLoading = false }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        for base in endpoints {
            guard let url = URL(string: base) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 10
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("close", forHTTPHeaderField: "Connection")
            req.httpBody = bodyData

            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let decoded = try JSONDecoder().decode(HeadscaleStatusResponse.self, from: data)
                if decoded.ok {
                    applyStatus(decoded)
                    WidgetCenter.shared.reloadAllTimelines()
                } else {
                    showBanner(decoded.error ?? "Headscale rejected the rite.", error: true)
                }
                return
            } catch {
                continue
            }
        }
        showBanner("Could not reach Headscale Sanctum API.", error: true)
    }

    func consecrateDevice() async {
        let trimmed = authReqInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showBanner("Paste an hskey-authreq-... string or registration URL first.", error: true)
            return
        }
        await postAction([
            "action": "register",
            "auth_id": trimmed,
            "user": registerUser
        ])
        if !isErrorBanner {
            authReqInput = ""
        }
    }

    func forgePreAuthKey() async {
        isLoading = true
        defer { isLoading = false }

        let isTag = forgeRole.hasPrefix("tag:")
        let userTarget = isTag ? "ross" : forgeRole
        let tags: [String] = isTag ? [forgeRole] : []
        let payload: [String: Any] = [
            "action": "preauthkey",
            "user": userTarget,
            "reusable": forgeReusable,
            "expiration": forgeExpiration,
            "tags": tags
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        for base in endpoints {
            guard let url = URL(string: base) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 10
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("close", forHTTPHeaderField: "Connection")
            req.httpBody = bodyData

            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let decoded = try JSONDecoder().decode(PreAuthKeyResponse.self, from: data)
                if decoded.ok {
                    forgedKey = decoded
                    showBanner("Forged new Pre-Auth Key (\(forgeExpiration)).", error: false)
                } else {
                    showBanner(decoded.error ?? "Failed to forge key.", error: true)
                }
                return
            } catch {
                continue
            }
        }
        showBanner("Failed to contact Headscale Key Forge.", error: true)
    }

    func toggleRoute(node: HeadscaleNode, route: String) async {
        var current = Set(node.approved_routes)
        if current.contains(route) {
            current.remove(route)
            if route == "0.0.0.0/0" { current.remove("::/0") }
        } else {
            current.insert(route)
            if route == "0.0.0.0/0" && node.available_routes.contains("::/0") {
                current.insert("::/0")
            }
        }
        await postAction([
            "action": "approve_routes",
            "node_id": node.id,
            "routes": Array(current)
        ])
    }

    func approveAllRoutes(node: HeadscaleNode) async {
        await postAction([
            "action": "approve_routes",
            "node_id": node.id,
            "routes": node.available_routes
        ])
    }

    func renameNode(_ node: HeadscaleNode, to newName: String) async {
        await postAction([
            "action": "rename_node",
            "node_id": node.id,
            "new_name": newName
        ])
    }

    func immortalizeNode(_ node: HeadscaleNode) async {
        await postAction([
            "action": "expire_node",
            "node_id": node.id,
            "disable": true
        ])
    }

    func expireNode(_ node: HeadscaleNode) async {
        await postAction([
            "action": "expire_node",
            "node_id": node.id,
            "disable": false
        ])
    }

    func banishNode(_ node: HeadscaleNode) async {
        await postAction([
            "action": "delete_node",
            "node_id": node.id
        ])
    }

    func runLatencyProbes() {
        localTunnel = iOSTunnelScanner.scan()
        for idx in probes.indices {
            let target = probes[idx]
            probes[idx].latencyMs = nil
            probes[idx].reachable = nil
            probeTCP(host: target.host, port: target.port) { [weak self] ok, ms in
                Task { @MainActor in
                    guard let self = self, idx < self.probes.count else { return }
                    self.probes[idx].reachable = ok
                    self.probes[idx].latencyMs = ms
                }
            }
        }
    }

    private nonisolated func probeTCP(host: String, port: UInt16, completion: @escaping @Sendable (Bool, Int?) -> Void) {
        let start = Date()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(false, nil)
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let box = ProbeStateBox()

        let queue = DispatchQueue(label: "com.ross.bloodmesh.probe.\(host).\(port)")
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if box.tryComplete() {
                    let ms = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
                    conn.cancel()
                    completion(true, ms)
                }
            case .failed, .cancelled:
                if box.tryComplete() {
                    conn.cancel()
                    completion(false, nil)
                }
            default:
                break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2.8) {
            if box.tryComplete() {
                conn.cancel()
                completion(false, nil)
            }
        }
    }
}

final class ProbeStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// MARK: - Root Gothic Vampire View

struct BloodMeshRootView: View {
    @StateObject private var vm = BloodMeshViewModel()
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            GothicCathedralBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topCathedralBar

                if let banner = vm.bannerMessage {
                    HStack(spacing: 8) {
                        Text("✠")
                            .foregroundStyle(vm.isErrorBanner ? GothicTheme.scarlet : GothicTheme.bloodHi)
                        Text(banner)
                            .font(GothicTheme.serif(12, weight: .semibold))
                            .foregroundStyle(GothicTheme.bone)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            vm.bannerMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(GothicTheme.ash)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .gothicPanel(active: !vm.isErrorBanner, corner: 10)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                TabView(selection: $selectedTab) {
                    SanctumTunnelTab(vm: vm)
                        .tag(0)
                    CovenNodesTab(vm: vm)
                        .tag(1)
                    ConsecrationRitesTab(vm: vm)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                customGothicTabBar
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await vm.loadOrConfigureVPNManager()
            await vm.refreshAll()
            vm.runLatencyProbes()
        }
        .alert("Rename Coven Node", isPresented: Binding(
            get: { vm.renamingNode != nil },
            set: { if !$0 { vm.renamingNode = nil } }
        )) {
            TextField("New hostname", text: $vm.renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { vm.renamingNode = nil }
            Button("Consecrate Name") {
                if let node = vm.renamingNode {
                    let targetName = vm.renameText
                    vm.renamingNode = nil
                    Task { await vm.renameNode(node, to: targetName) }
                }
            }
        } message: {
            Text("Enter a new MagicDNS hostname for \(vm.renamingNode?.given_name ?? "node") (.mesh.internal).")
        }
    }

    private var topCathedralBar: some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("✠")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(GothicTheme.bloodHi)
                        Text("BLOODMESH")
                            .font(GothicTheme.display(22))
                            .tracking(2.0)
                            .foregroundStyle(GothicTheme.bone)
                    }
                    Text("STANDALONE NATIVE VPN · HS.NAS-SERVER.CO.UK")
                        .font(GothicTheme.serif(9.5, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(GothicTheme.ash)
                }

                Spacer()

                Button {
                    Task {
                        await vm.refreshAll()
                        vm.runLatencyProbes()
                    }
                } label: {
                    HStack(spacing: 5) {
                        if vm.isLoading {
                            ProgressView()
                                .tint(GothicTheme.bloodHi)
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text("SYNC")
                            .font(GothicTheme.serif(10, weight: .bold))
                            .tracking(1)
                    }
                    .foregroundStyle(GothicTheme.bone)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .gothicPanel(active: vm.isTunnelConnected, corner: 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            GothicOrnamentRule()
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 6)
    }

    private var customGothicTabBar: some View {
        HStack(spacing: 10) {
            tabButton(index: 0, icon: "shield.lefthalf.filled", title: "SANCTUM")
            tabButton(index: 1, icon: "point.3.connected.trianglepath.dotted", title: "COVEN (\(vm.nodes.count))")
            tabButton(index: 2, icon: "key.radiowaves.forward.fill", title: "RITES & KEYS")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(GothicTheme.void.opacity(0.94))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(GothicTheme.blood.opacity(0.45))
                .frame(height: 0.8)
        }
    }

    private func tabButton(index: Int, icon: String, title: String) -> some View {
        let active = selectedTab == index
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(active ? GothicTheme.bloodHi : GothicTheme.ash)
                Text(title)
                    .font(GothicTheme.serif(10.5, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(active ? GothicTheme.bone : GothicTheme.ash)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .gothicPanel(active: active, corner: 9)
        }
    }
}

// MARK: - Tab 1: Sanctum Native Packet Tunnel & Latency Telemetry

struct SanctumTunnelTab: View {
    @ObservedObject var vm: BloodMeshViewModel

    private var isSealed: Bool {
        vm.isTunnelConnected
    }

    private var rxDisplay: String {
        let b = max(vm.providerRxBytes, vm.localTunnel.rxBytes)
        return iOSTunnelScanner.formatBytes(b)
    }

    private var txDisplay: String {
        let b = max(vm.providerTxBytes, vm.localTunnel.txBytes)
        return iOSTunnelScanner.formatBytes(b)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                tunnelHeroCard
                vpnConfigurationTogglesCard
                meshRoutesSummaryCard
                latencyProbesCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var tunnelHeroCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isSealed ? GothicTheme.bloodHi : GothicTheme.ash)
                        .frame(width: 9, height: 9)
                        .shadow(color: isSealed ? GothicTheme.bloodHi : .clear, radius: 6)
                    Text(vm.vpnStatusText)
                        .font(GothicTheme.serif(11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(isSealed ? GothicTheme.bloodHi : GothicTheme.ash)
                }
                Spacer()
                Text(vm.localTunnel.interfaceName.uppercased())
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(GothicTheme.bone)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .gothicPanel(active: isSealed, corner: 5)
            }

            // Interactive Gothic Rose VPN Power Button
            Button {
                Task { await vm.toggleVPNTunnel() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(GothicTheme.blood.opacity(0.45), lineWidth: 1.4)
                        .frame(width: 146, height: 146)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    isSealed ? GothicTheme.bloodDeep.opacity(0.92) : GothicTheme.crypt,
                                    GothicTheme.void
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 72
                            )
                        )
                        .frame(width: 132, height: 132)
                        .overlay(
                            Circle()
                                .strokeBorder(isSealed ? GothicTheme.bloodHi : GothicTheme.tomb, lineWidth: 2.0)
                        )
                        .shadow(color: isSealed ? GothicTheme.bloodHi.opacity(0.45) : .clear, radius: 14)

                    VStack(spacing: 3) {
                        Image(systemName: isSealed ? "lock.shield.fill" : "power")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(isSealed ? GothicTheme.bloodHi : GothicTheme.ash)
                        Text(vm.localTunnel.ipv4)
                            .font(GothicTheme.display(20))
                            .foregroundStyle(GothicTheme.bone)
                        Text(isSealed ? "TAP TO SEVER" : "TAP TO SEAL VPN")
                            .font(GothicTheme.serif(9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(isSealed ? GothicTheme.bloodHi : GothicTheme.ash)
                    }
                }
            }
            .padding(.vertical, 2)

            // Master Action Button
            Button {
                Task { await vm.toggleVPNTunnel() }
            } label: {
                HStack(spacing: 8) {
                    Spacer()
                    Image(systemName: isSealed ? "bolt.slash.fill" : "bolt.shield.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GothicTheme.bloodHi)
                    Text(isSealed ? "✠ SEVER BLOODLINE VPN TUNNEL ✠" : "✠ SEAL BLOODLINE VPN TUNNEL ✠")
                        .font(GothicTheme.serif(11.5, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(GothicTheme.bone)
                    Spacer()
                }
                .padding(.vertical, 12)
                .gothicPanel(active: !isSealed, corner: 10)
            }

            // Telemetry Grid
            HStack(spacing: 8) {
                telemetryPill(label: "MAGICDNS", value: "ross-iphone.mesh.internal")
                telemetryPill(label: "CIPHER", value: "ChaCha20-Poly1305 :41642")
            }

            HStack(spacing: 8) {
                telemetryPill(label: "TUNNEL RX", value: rxDisplay)
                telemetryPill(label: "TUNNEL TX", value: txDisplay)
                telemetryPill(label: "CARRIER IP", value: vm.localTunnel.wifiOrCellIP)
            }
        }
        .padding(14)
        .gothicPanel(active: isSealed, corner: 14)
    }

    private func telemetryPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(GothicTheme.serif(8.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(GothicTheme.ash)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(GothicTheme.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .gothicPanel(active: false, corner: 8)
    }

    private var vpnConfigurationTogglesCard: some View {
        HStack(spacing: 10) {
            Button {
                vm.exitNodeEnabled.toggle()
                Task { await vm.applyExitNodeOrOnDemandChange() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: vm.exitNodeEnabled ? "globe.europe.africa.fill" : "network")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(vm.exitNodeEnabled ? GothicTheme.bloodHi : GothicTheme.ash)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(vm.exitNodeEnabled ? "EXIT NODE: ON" : "SPLIT TUNNEL")
                            .font(GothicTheme.serif(10, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(GothicTheme.bone)
                        Text(vm.exitNodeEnabled ? "Full 0.0.0.0/0 Traffic" : "Mesh + 192.168.0.x + 10.7.x")
                            .font(GothicTheme.serif(8.5))
                            .foregroundStyle(GothicTheme.ash)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .gothicPanel(active: vm.exitNodeEnabled, corner: 10)
            }

            Button {
                vm.onDemandEnabled.toggle()
                Task { await vm.applyExitNodeOrOnDemandChange() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: vm.onDemandEnabled ? "infinity.circle.fill" : "circle.dashed")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(vm.onDemandEnabled ? GothicTheme.bloodHi : GothicTheme.ash)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(vm.onDemandEnabled ? "ALWAYS-ON: ON" : "ALWAYS-ON: OFF")
                            .font(GothicTheme.serif(10, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(GothicTheme.bone)
                        Text("iOS Auto-Connect Rule")
                            .font(GothicTheme.serif(8.5))
                            .foregroundStyle(GothicTheme.ash)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
                .gothicPanel(active: vm.onDemandEnabled, corner: 10)
            }
        }
    }

    private var meshRoutesSummaryCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            GothicHeader(
                title: "ACTIVE BLOODLINE KERNEL ROUTES",
                rightText: "\(vm.summary?.online_nodes ?? 4)/\(vm.summary?.total_nodes ?? 4) ONLINE"
            )

            HStack(spacing: 8) {
                routeStatusCard(
                    title: "HOME LAN SUBNET",
                    route: "192.168.0.0/24",
                    via: "via asus-router",
                    active: vm.summary?.lan_subnet_active ?? true
                )
                routeStatusCard(
                    title: "HEADSCALE MESH",
                    route: "100.64.0.0/10",
                    via: "bmtun0 <-> tailscale0",
                    active: true
                )
                routeStatusCard(
                    title: "SIDESTORE TUN",
                    route: "10.7.0.1/32",
                    via: "via truenas-scale",
                    active: vm.summary?.sidestore_tun_active ?? true
                )
            }
        }
        .padding(13)
        .gothicPanel(active: false, corner: 12)
    }

    private func routeStatusCard(title: String, route: String, via: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(active ? GothicTheme.bloodHi : GothicTheme.ash)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(GothicTheme.serif(8, weight: .bold))
                    .foregroundStyle(GothicTheme.ash)
                    .lineLimit(1)
            }
            Text(route)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(GothicTheme.bone)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(via)
                .font(GothicTheme.serif(8.5))
                .italic()
                .foregroundStyle(GothicTheme.bloodHi)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .gothicPanel(active: active, corner: 8)
    }

    private var latencyProbesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                GothicHeader(title: "LIVE SANCTUM LATENCY PROBES")
                Button {
                    vm.runLatencyProbes()
                } label: {
                    Text("PULSE")
                        .font(GothicTheme.serif(9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(GothicTheme.bone)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .gothicPanel(active: true, corner: 6)
                }
            }

            ForEach(vm.probes) { p in
                HStack(spacing: 10) {
                    Circle()
                        .fill(p.reachable == true ? GothicTheme.bloodHi : (p.reachable == false ? GothicTheme.ash.opacity(0.4) : GothicTheme.blood))
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.title)
                            .font(GothicTheme.serif(11.5, weight: .bold))
                            .foregroundStyle(GothicTheme.bone)
                        Text(p.subtitle)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(GothicTheme.ash)
                    }
                    Spacer()
                    if let ms = p.latencyMs {
                        Text("\(ms) ms")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(GothicTheme.bloodHi)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .gothicPanel(active: true, corner: 6)
                    } else if p.reachable == false {
                        Text("UNREACHABLE")
                            .font(GothicTheme.serif(8.5, weight: .bold))
                            .foregroundStyle(GothicTheme.ash)
                    } else {
                        ProgressView()
                            .tint(GothicTheme.bloodHi)
                            .scaleEffect(0.65)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .gothicPanel(active: false, corner: 8)
            }
        }
        .padding(13)
        .gothicPanel(active: false, corner: 12)
    }
}

// MARK: - Tab 2: Coven Nodes & Interactive Subnet Route Altar

struct CovenNodesTab: View {
    @ObservedObject var vm: BloodMeshViewModel

    private var filteredNodes: [HeadscaleNode] {
        switch vm.selectedUserFilter {
        case "ross", "mo", "lauren":
            return vm.nodes.filter { $0.user.lowercased() == vm.selectedUserFilter }
        case "infra":
            return vm.nodes.filter { !$0.tags.isEmpty || $0.user == "tagged-devices" }
        default:
            return vm.nodes
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ownerFilterBar

                ForEach(filteredNodes) { node in
                    nodeCard(node)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var ownerFilterBar: some View {
        HStack(spacing: 6) {
            ForEach([
                ("all", "ALL"),
                ("ross", "ROSS"),
                ("mo", "MO"),
                ("lauren", "LAUREN"),
                ("infra", "INFRA")
            ], id: \.0) { key, title in
                let active = vm.selectedUserFilter == key
                Button {
                    vm.selectedUserFilter = key
                } label: {
                    Text(title)
                        .font(GothicTheme.serif(9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(active ? GothicTheme.bone : GothicTheme.ash)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .gothicPanel(active: active, corner: 6)
                }
            }
        }
    }

    private func roleIcon(_ role: String) -> String {
        switch role {
        case "iphone": return "iphone.gen3"
        case "router": return "wifi.router.fill"
        case "server": return "externaldrive.fill.badge.timemachine"
        case "pc": return "desktopcomputer"
        default: return "network"
        }
    }

    private func formatAgo(_ seconds: Int) -> String {
        if seconds < 60 { return "Just now" }
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m ago" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h ago" }
        return "\(hrs / 24)d ago"
    }

    private func nodeCard(_ node: HeadscaleNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(node.online ? GothicTheme.bloodDeep : GothicTheme.crypt)
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(node.online ? GothicTheme.bloodHi : GothicTheme.tomb, lineWidth: 1)
                        )
                    Image(systemName: roleIcon(node.role))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GothicTheme.bone)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(node.given_name.uppercased())
                            .font(GothicTheme.serif(13, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(GothicTheme.bone)
                        Text(node.user == "tagged-devices" ? "INFRA" : node.user.uppercased())
                            .font(GothicTheme.serif(8.5, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(GothicTheme.bone)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .gothicPanel(active: true, corner: 4)
                        ForEach(node.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(GothicTheme.bloodHi)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .gothicPanel(active: false, corner: 4)
                        }
                    }
                    Text(node.fqdn)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(GothicTheme.ash)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(node.online ? GothicTheme.bloodHi : GothicTheme.ash.opacity(0.4))
                            .frame(width: 7, height: 7)
                        Text(node.online ? "ONLINE" : "OFFLINE")
                            .font(GothicTheme.serif(9.5, weight: .bold))
                            .foregroundStyle(node.online ? GothicTheme.bloodHi : GothicTheme.ash)
                    }
                    Text("ID #\(node.id) · \(formatAgo(node.last_seen_ago_sec))")
                        .font(GothicTheme.serif(8.5))
                        .foregroundStyle(GothicTheme.ash)
                }
            }

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = node.ipv4
                    vm.showBanner("Copied \(node.ipv4) to clipboard.", error: false)
                } label: {
                    HStack(spacing: 5) {
                        Text("IPv4")
                            .font(GothicTheme.serif(8.5, weight: .bold))
                            .foregroundStyle(GothicTheme.ash)
                        Text(node.ipv4)
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(GothicTheme.bone)
                        Spacer()
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(GothicTheme.bloodHi)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .gothicPanel(active: false, corner: 7)
                }

                Button {
                    UIPasteboard.general.string = node.fqdn
                    vm.showBanner("Copied \(node.fqdn) to clipboard.", error: false)
                } label: {
                    HStack(spacing: 5) {
                        Text("DNS")
                            .font(GothicTheme.serif(8.5, weight: .bold))
                            .foregroundStyle(GothicTheme.ash)
                        Text(node.given_name)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(GothicTheme.bone)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(GothicTheme.bloodHi)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .gothicPanel(active: false, corner: 7)
                }
            }

            if !node.available_routes.isEmpty || !node.approved_routes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("ADVERTISED SUBNET & EXIT ROUTES (TAP TO TOGGLE)")
                            .font(GothicTheme.serif(8.5, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(GothicTheme.ash)
                        Spacer()
                        Button {
                            Task { await vm.approveAllRoutes(node: node) }
                        } label: {
                            Text("APPROVE ALL")
                                .font(GothicTheme.serif(8, weight: .bold))
                                .foregroundStyle(GothicTheme.bloodHi)
                        }
                    }

                    let allRoutes = Array(Set(node.available_routes + node.approved_routes)).sorted()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(allRoutes, id: \.self) { route in
                                let isApproved = node.approved_routes.contains(route)
                                Button {
                                    Task { await vm.toggleRoute(node: node, route: route) }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: isApproved ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(isApproved ? GothicTheme.bloodHi : GothicTheme.ash)
                                        Text(route == "0.0.0.0/0" ? "EXIT NODE (0.0.0.0/0)" : route)
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(GothicTheme.bone)
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5.5)
                                    .gothicPanel(active: isApproved, corner: 6)
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    vm.renameText = node.given_name
                    vm.renamingNode = node
                } label: {
                    Label("RENAME", systemImage: "pencil")
                        .font(GothicTheme.serif(9, weight: .bold))
                        .foregroundStyle(GothicTheme.bone)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .gothicPanel(active: false, corner: 6)
                }

                Button {
                    Task { await vm.immortalizeNode(node) }
                } label: {
                    Label("IMMORTALIZE", systemImage: "infinity")
                        .font(GothicTheme.serif(9, weight: .bold))
                        .foregroundStyle(GothicTheme.bone)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .gothicPanel(active: false, corner: 6)
                }

                Menu {
                    Button("Expire Node Key (Force Re-Auth)", role: .destructive) {
                        Task { await vm.expireNode(node) }
                    }
                    Button("Banish Node from Headscale", role: .destructive) {
                        Task { await vm.banishNode(node) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis")
                        Text("RITES")
                    }
                    .font(GothicTheme.serif(9, weight: .bold))
                    .foregroundStyle(GothicTheme.bloodHi)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .gothicPanel(active: false, corner: 6)
                }
            }
        }
        .padding(13)
        .gothicPanel(active: node.online && node.role == "iphone", corner: 12)
    }
}

// MARK: - Tab 3: Consecration Rites & Pre-Auth Key Forge

struct ConsecrationRitesTab: View {
    @ObservedObject var vm: BloodMeshViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                authRegisterCard
                preAuthKeyForgeCard
                serverSanctumInfoCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var authRegisterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            GothicHeader(
                title: "CONSECRATE NEW DEVICE (AUTH REGISTER)",
                rightText: "OWNER: \(vm.registerUser.uppercased())"
            )

            Text("Select whose device this is (Ross, Mo, or Lauren), then paste the hskey-authreq-... token or registration URL to bind it to their user.")
                .font(GothicTheme.serif(11))
                .foregroundStyle(GothicTheme.ash)

            HStack(spacing: 6) {
                ForEach(["ross", "mo", "lauren"], id: \.self) { usr in
                    let active = vm.registerUser == usr
                    Button {
                        vm.registerUser = usr
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(active ? GothicTheme.bloodHi : GothicTheme.ash)
                            Text(usr.uppercased())
                                .font(GothicTheme.serif(9.5, weight: .bold))
                                .tracking(0.7)
                                .foregroundStyle(active ? GothicTheme.bone : GothicTheme.ash)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .gothicPanel(active: active, corner: 6)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("hskey-authreq-... or registration URL", text: $vm.authReqInput)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(GothicTheme.bone)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .gothicPanel(active: false, corner: 8)

                Button {
                    if let clip = UIPasteboard.general.string {
                        vm.authReqInput = clip
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GothicTheme.bone)
                        .padding(10)
                        .gothicPanel(active: false, corner: 8)
                }
            }

            Button {
                Task { await vm.consecrateDevice() }
            } label: {
                HStack {
                    Spacer()
                    Text("✠ CONSECRATE & BIND DEVICE ✠")
                        .font(GothicTheme.serif(11.5, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(GothicTheme.bone)
                    Spacer()
                }
                .padding(.vertical, 11)
                .gothicPanel(active: true, corner: 9)
            }
        }
        .padding(14)
        .gothicPanel(active: false, corner: 12)
    }

    private var preAuthKeyForgeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            GothicHeader(
                title: "PRE-AUTH KEY FORGE",
                rightText: "\(vm.preauthKeyCount) ACTIVE KEYS"
            )

            Text("Forge a reusable or one-time pre-authentication key for PCs, TrueNAS servers, or subnet routers.")
                .font(GothicTheme.serif(11))
                .foregroundStyle(GothicTheme.ash)

            HStack(spacing: 6) {
                roleChoice(title: "ROSS", value: "ross")
                roleChoice(title: "MO", value: "mo")
                roleChoice(title: "LAUREN", value: "lauren")
                roleChoice(title: "SERVER", value: "tag:server")
                roleChoice(title: "ROUTER", value: "tag:router")
            }

            HStack(spacing: 6) {
                ForEach(["1h", "24h", "168h", "2160h"], id: \.self) { exp in
                    let label = exp == "168h" ? "7 DAYS" : (exp == "2160h" ? "90 DAYS" : exp.uppercased())
                    Button {
                        vm.forgeExpiration = exp
                    } label: {
                        Text(label)
                            .font(GothicTheme.serif(9.5, weight: .bold))
                            .foregroundStyle(vm.forgeExpiration == exp ? GothicTheme.bone : GothicTheme.ash)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .gothicPanel(active: vm.forgeExpiration == exp, corner: 6)
                    }
                }
            }

            Button {
                Task { await vm.forgePreAuthKey() }
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "flame.fill")
                        .foregroundStyle(GothicTheme.bloodHi)
                    Text("FORGE HEADSCALE PRE-AUTH KEY")
                        .font(GothicTheme.serif(11.5, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(GothicTheme.bone)
                    Spacer()
                }
                .padding(.vertical, 11)
                .gothicPanel(active: true, corner: 9)
            }

            if let forged = vm.forgedKey, let key = forged.key {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FORGED KEY (\(forged.expiration ?? "24h"))")
                        .font(GothicTheme.serif(9, weight: .bold))
                        .foregroundStyle(GothicTheme.bloodHi)

                    Text(key)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(GothicTheme.bone)
                        .lineLimit(2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gothicPanel(active: false, corner: 6)

                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = key
                            vm.showBanner("Copied Pre-Auth Key to clipboard.", error: false)
                        } label: {
                            Label("COPY KEY", systemImage: "key.fill")
                                .font(GothicTheme.serif(9.5, weight: .bold))
                                .foregroundStyle(GothicTheme.bone)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .gothicPanel(active: true, corner: 7)
                        }

                        if let cmd = forged.command {
                            Button {
                                UIPasteboard.general.string = cmd
                                vm.showBanner("Copied full 'tailscale up' command to clipboard.", error: false)
                            } label: {
                                Label("COPY CLI COMMAND", systemImage: "terminal.fill")
                                    .font(GothicTheme.serif(9.5, weight: .bold))
                                    .foregroundStyle(GothicTheme.bone)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .gothicPanel(active: false, corner: 7)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .gothicPanel(active: false, corner: 12)
    }

    private func roleChoice(title: String, value: String) -> some View {
        let active = vm.forgeRole == value
        return Button {
            vm.forgeRole = value
        } label: {
            Text(title)
                .font(GothicTheme.serif(8.5, weight: .bold))
                .foregroundStyle(active ? GothicTheme.bone : GothicTheme.ash)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .gothicPanel(active: active, corner: 6)
        }
    }

    private var serverSanctumInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            GothicHeader(
                title: "SANCTUM ARCHITECTURE",
                rightText: "HEADSCALE v\(vm.health?.version ?? "0.29.7")"
            )

            infoRow("Native Tunnel Engine", "BloodMeshTunnel (NEPacketTunnel)")
            infoRow("AEAD Cipher & Port", "ChaCha20-Poly1305 · UDP :41642")
            infoRow("MagicDNS Resolver", "100.100.100.100 (mesh.internal)")
            infoRow("TrueNAS Mesh Gateway", "100.64.0.4 (truenas-scale.mesh.internal)")
            infoRow("Home Router Gateway", "100.64.0.2 (192.168.0.0/24 + Exit Node)")
        }
        .padding(14)
        .gothicPanel(active: false, corner: 12)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(GothicTheme.serif(10.5, weight: .semibold))
                .foregroundStyle(GothicTheme.ash)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(GothicTheme.bone)
        }
    }
}

@main
struct BloodMeshApp: App {
    var body: some Scene {
        WindowGroup {
            BloodMeshRootView()
        }
    }
}
