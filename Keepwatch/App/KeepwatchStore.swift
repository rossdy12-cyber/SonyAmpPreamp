import Foundation
import SwiftUI

struct SystemdServiceStatus: Identifiable, Codable {
    var id: String { name }
    let name: String
    let label: String
    let status: String
}

struct DockerContainerItem: Identifiable, Codable {
    var id: String { name }
    let name: String
    let status: String
    let image: String
}

struct TrueNASOpsPayload: Codable {
    let hostname: String
    let timestamp: String
    let loadAvg: String
    let uptime: String
    let memUsedGB: Double
    let memTotalGB: Double
    let memPercent: Int
    let cpuTempC: Int
    let poolUsedGB: Int
    let poolTotalGB: Int
    let poolFreeGB: Int
    let poolPercent: Int
    let services: [SystemdServiceStatus]
    let containers: [DockerContainerItem]
    let buildLogTail: String
}

struct NetRadarNode: Identifiable {
    let id: String
    let name: String
    let category: String
    let urlString: String
    var latencyMs: Int?
    var isOnline: Bool
    var statusText: String
}

struct SideStoreAppItem: Identifiable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let subtitle: String
    let version: String
    let date: String
    let sizeBytes: Int
    let downloadURL: String
    let iconURL: String
}

@MainActor
final class KeepwatchStore: ObservableObject {
    @Published var opsEndpointURL: String {
        didSet { UserDefaults.standard.set(opsEndpointURL, forKey: "kw.ops.url") }
    }
    @Published var uploadToken: String = ""
    @Published var isLoading: Bool = false
    @Published var lastActionBanner: String = ""

    @Published var hostname: String = "nas-server.co.uk (TrueNAS SCALE)"
    @Published var timestamp: String = "--:--"
    @Published var loadAvg: String = "1.42 / 1.38 / 1.30"
    @Published var uptime: String = "9 days, 10 hours"
    @Published var memUsedGB: Double = 28.4
    @Published var memTotalGB: Double = 31.3
    @Published var memPercent: Int = 90
    @Published var cpuTempC: Int = 42
    @Published var poolUsedGB: Int = 715
    @Published var poolTotalGB: Int = 2242
    @Published var poolFreeGB: Int = 1527
    @Published var poolPercent: Int = 32

    @Published var services: [SystemdServiceStatus] = [
        SystemdServiceStatus(name: "sidestore-tun.service", label: "SideStore 10.7.0.1 Tailscale Reflector", status: "active"),
        SystemdServiceStatus(name: "sidestore-ipa-receiver.service", label: "SideStore Git & IPA Auto-Publisher", status: "active"),
        SystemdServiceStatus(name: "tailscaled.service", label: "Tailscale Mesh VPN (100.85.127.42)", status: "active"),
        SystemdServiceStatus(name: "docker.service", label: "TrueNAS Docker Container Engine", status: "active")
    ]
    @Published var containers: [DockerContainerItem] = []
    @Published var buildLogTail: String = "Waiting for telemetry..."
    @Published var repoApps: [SideStoreAppItem] = []
    @Published var radarNodes: [NetRadarNode] = [
        NetRadarNode(id: "headscale-hub", name: "BloodMesh Headscale Hub", category: "HTTPS Public", urlString: "https://hs.nas-server.co.uk/sanctum-api?key=bm-sanctum-7f9a3e2c8b41d0e5a6f1c9b2d8e4a7f0&action=status", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "truenas-ops", name: "TrueNAS Ops & Git Daemon", category: "Headscale :18998", urlString: "http://100.64.0.4:18998/ops/status", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "appletv-engine", name: "Apple TV Wireless Installer", category: "Headscale :5533", urlString: "http://100.64.0.4:5533/api/version", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "jellyfin", name: "Hearth Jellyfin 4K Cinema", category: "Headscale :30013", urlString: "http://100.64.0.4:30013/System/Info/Public", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "navidrome", name: "Navidrome Hi-Fi Subsonic", category: "Headscale :30043", urlString: "http://100.64.0.4:30043", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "immich", name: "Reliquary Immich 4K Photos", category: "Headscale :30041", urlString: "http://100.64.0.4:30041/api/server/ping", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "nightscout", name: "GlucoPulse Nightscout CGM", category: "Headscale :1337", urlString: "http://100.64.0.4:1337/api/v1/status.json", latencyMs: nil, isOnline: true, statusText: "Ready")
    ]

    init() {
        let saved = UserDefaults.standard.string(forKey: "kw.ops.url") ?? ""
        self.opsEndpointURL = saved.isEmpty ? "http://100.64.0.4:18998/ops/status" : saved
        Task {
            await refreshAll()
        }
    }

    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }
        await fetchTrueNASOps()
        await fetchSideStoreRepo()
    }

    func fetchTrueNASOps() async {
        // Try primary URL first, fallback to Headscale direct :18998
        let candidates = [
            "http://100.64.0.4:18998/ops/status",
            "https://hs.nas-server.co.uk/sidestore-api/ops/status",
            "http://100.85.127.42:18998/ops/status",
            "\(opsEndpointURL)?ops=status"
        ]
        for urlStr in candidates {
            guard let url = URL(string: urlStr) else { continue }
            do {
                var req = URLRequest(url: url, timeoutInterval: 8)
                req.setValue("SideStore/0.7.0", forHTTPHeaderField: "User-Agent")
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let decoded = try? JSONDecoder().decode(TrueNASOpsPayload.self, from: data) {
                    self.hostname = decoded.hostname
                    self.timestamp = decoded.timestamp
                    self.loadAvg = decoded.loadAvg
                    self.uptime = decoded.uptime
                    self.memUsedGB = decoded.memUsedGB
                    self.memTotalGB = decoded.memTotalGB
                    self.memPercent = decoded.memPercent
                    self.cpuTempC = decoded.cpuTempC
                    self.poolUsedGB = decoded.poolUsedGB
                    self.poolTotalGB = decoded.poolTotalGB
                    self.poolFreeGB = decoded.poolFreeGB
                    self.poolPercent = decoded.poolPercent
                    self.services = decoded.services
                    self.containers = decoded.containers
                    if !decoded.buildLogTail.isEmpty {
                        self.buildLogTail = decoded.buildLogTail
                    }
                    return
                }
            } catch {}
        }
    }

    func performOpsAction(action: String, target: String = "") async {
        let encodedTarget = target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? target
        let candidates = [
            "http://100.64.0.4:18998/ops/action?action=\(action)&target=\(encodedTarget)",
            "http://100.85.127.42:18998/ops/action?action=\(action)&target=\(encodedTarget)",
            "\(opsEndpointURL)?ops=action&action=\(action)&target=\(encodedTarget)"
        ]
        for urlStr in candidates {
            guard let url = URL(string: urlStr) else { continue }
            do {
                var req = URLRequest(url: url, timeoutInterval: 15)
                req.httpMethod = "POST"
                req.setValue("SideStore/0.7.0", forHTTPHeaderField: "User-Agent")
                req.setValue(uploadToken, forHTTPHeaderField: "X-Upload-Token")
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = obj["message"] as? String {
                    lastActionBanner = msg
                    await fetchTrueNASOps()
                    return
                }
            } catch {}
        }
        lastActionBanner = "Action sent (\(action) \(target))"
    }

    func fetchSideStoreRepo() async {
        let urls = [
            "https://hs.nas-server.co.uk/sidestore/source.json",
            "http://100.64.0.4:18998/sidestore/source.json"
        ]
        for u in urls {
            guard let url = URL(string: u) else { continue }
            do {
                var req = URLRequest(url: url, timeoutInterval: 10)
                req.setValue("SideStore/0.7.0", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let apps = root["apps"] as? [[String: Any]] else { continue }
                var parsed: [SideStoreAppItem] = []
                for a in apps {
                    let name = a["name"] as? String ?? "App"
                    let bid = a["bundleIdentifier"] as? String ?? UUID().uuidString
                    let sub = a["subtitle"] as? String ?? ""
                    let icon = a["iconURL"] as? String ?? ""
                    let vers = a["versions"] as? [[String: Any]] ?? []
                    let v0 = vers.first ?? [:]
                    parsed.append(SideStoreAppItem(
                        name: name,
                        bundleIdentifier: bid,
                        subtitle: sub,
                        version: v0["version"] as? String ?? "1.0",
                        date: v0["date"] as? String ?? "",
                        sizeBytes: v0["size"] as? Int ?? 0,
                        downloadURL: v0["downloadURL"] as? String ?? "",
                        iconURL: icon
                    ))
                }
                repoApps = parsed
                return
            } catch {}
        }
    }

    func runNetRadarSweep() async {
        for idx in radarNodes.indices {
            let urlStr = radarNodes[idx].urlString
            guard let url = URL(string: urlStr) else { continue }
            let start = Date()
            do {
                var req = URLRequest(url: url, timeoutInterval: 4)
                req.setValue("SideStore/0.7.0", forHTTPHeaderField: "User-Agent")
                let (_, resp) = try await URLSession.shared.data(for: req)
                let ms = max(1, Int((Date().timeIntervalSince(start) * 1000.0).rounded()))
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
                radarNodes[idx].latencyMs = ms
                radarNodes[idx].isOnline = (200..<500).contains(code)
                radarNodes[idx].statusText = "HTTP \(code) • \(ms) ms"
            } catch {
                radarNodes[idx].latencyMs = nil
                radarNodes[idx].isOnline = false
                radarNodes[idx].statusText = "Offline / Check Tailscale"
            }
        }
    }
}
