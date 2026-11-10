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
    @Published var uploadToken: String = "ss-deploy-9f8e7d6c5b4a3f2e1d0c"
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
        NetRadarNode(id: "ssl-hub", name: "Cloudflare / NPM SSL Hub", category: "HTTPS Public", urlString: "https://navidrome.nas-server.co.uk/sidestore/source.json", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "truenas-ops", name: "TrueNAS Ops & Git Daemon", category: "Tailscale :18998", urlString: "http://100.85.127.42:18998/ops/status", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "navidrome", name: "Navidrome Hi-Fi Subsonic", category: "Tailscale :30043", urlString: "http://100.85.127.42:30043", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "nightscout", name: "GlucoPulse Nightscout CGM", category: "Tailscale :1337", urlString: "http://100.85.127.42:1337/api/v1/status.json", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "tconnect", name: "Tandem t:slim Sync Portal", category: "Tailscale :1338", urlString: "http://100.85.127.42:1338", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "slskd", name: "SoulSeekr (slskd P2P)", category: "Tailscale :5030", urlString: "http://100.85.127.42:5030", latencyMs: nil, isOnline: true, statusText: "Ready"),
        NetRadarNode(id: "lidarr", name: "Encore (Lidarr Music)", category: "Tailscale :30071", urlString: "http://100.85.127.42:30071", latencyMs: nil, isOnline: true, statusText: "Ready")
    ]

    init() {
        let saved = UserDefaults.standard.string(forKey: "kw.ops.url") ?? ""
        self.opsEndpointURL = saved.isEmpty ? "https://navidrome.nas-server.co.uk/sidestore-upload" : saved
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
        // Try primary URL first, fallback to Tailscale direct :18998
        let candidates = [
            "\(opsEndpointURL)?ops=status",
            "http://100.85.127.42:18998/ops/status",
            "https://navidrome.nas-server.co.uk/sidestore-upload?ops=status"
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
            "\(opsEndpointURL)?ops=action&action=\(action)&target=\(encodedTarget)",
            "http://100.85.127.42:18998/ops/action?action=\(action)&target=\(encodedTarget)"
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
        guard let url = URL(string: "https://navidrome.nas-server.co.uk/sidestore/source.json") else { return }
        do {
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("SideStore/0.7.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let apps = root["apps"] as? [[String: Any]] else { return }
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
        } catch {}
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
