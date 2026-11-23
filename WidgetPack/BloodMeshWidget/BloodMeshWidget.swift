import WidgetKit
import SwiftUI
import Darwin

struct BloodMeshNodeSummary: Codable, Identifiable {
    let id: Int
    let name: String
    let given_name: String
    let ipv4: String
    let online: Bool
    let role: String
    let subnet_routes: [String]
    let is_exit_node: Bool
    let exit_node_approved: Bool
}

struct BloodMeshEntry: TimelineEntry {
    let date: Date
    let tunnelSealed: Bool
    let localTunnelIP: String
    let tunnelInterface: String
    let onlineNodes: Int
    let totalNodes: Int
    let lanRouteActive: Bool
    let exitNodeActive: Bool
    let sideStoreRouteActive: Bool
    let derpLatencyMs: Int
    let nodes: [BloodMeshNodeSummary]
}

enum LocalTunnelInspector {
    static func inspect() -> (sealed: Bool, ip: String, iface: String) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return (false, "100.64.0.1", "utun")
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let name = String(cString: current.pointee.ifa_name)
            if isUp, let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if ip.hasPrefix("100.64.") || ip.hasPrefix("100.") {
                        return (true, ip, name)
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }
        return (false, "100.64.0.1", "utun")
    }
}

struct BloodMeshProvider: TimelineProvider {
    func placeholder(in context: Context) -> BloodMeshEntry {
        defaultEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (BloodMeshEntry) -> Void) {
        fetchEntry { completion($0) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BloodMeshEntry>) -> Void) {
        fetchEntry { entry in
            let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func defaultEntry(date: Date) -> BloodMeshEntry {
        let local = LocalTunnelInspector.inspect()
        return BloodMeshEntry(
            date: date,
            tunnelSealed: local.sealed,
            localTunnelIP: local.ip,
            tunnelInterface: local.iface,
            onlineNodes: 4,
            totalNodes: 4,
            lanRouteActive: true,
            exitNodeActive: true,
            sideStoreRouteActive: true,
            derpLatencyMs: 24,
            nodes: [
                BloodMeshNodeSummary(id: 1, name: "Ross Iphone", given_name: "ross-iphone", ipv4: "100.64.0.1", online: true, role: "iphone", subnet_routes: [], is_exit_node: false, exit_node_approved: false),
                BloodMeshNodeSummary(id: 2, name: "asus-router", given_name: "asus-router", ipv4: "100.64.0.2", online: true, role: "router", subnet_routes: ["192.168.0.0/24", "0.0.0.0/0"], is_exit_node: true, exit_node_approved: true),
                BloodMeshNodeSummary(id: 3, name: "DESKTOP-81E1RF4", given_name: "desktop-81e1rf4", ipv4: "100.64.0.3", online: true, role: "pc", subnet_routes: [], is_exit_node: false, exit_node_approved: false),
                BloodMeshNodeSummary(id: 4, name: "truenas-scale", given_name: "truenas-scale", ipv4: "100.64.0.4", online: true, role: "server", subnet_routes: ["10.7.0.1/32"], is_exit_node: false, exit_node_approved: false)
            ]
        )
    }

    private func fetchEntry(completion: @escaping (BloodMeshEntry) -> Void) {
        let local = LocalTunnelInspector.inspect()
        let start = Date()
        guard let url = URL(string: "https://hs.nas-server.co.uk/sanctum-api?action=status") else {
            completion(defaultEntry(date: Date()))
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("close", forHTTPHeaderField: "Connection")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            let elapsedMs = max(8, min(999, Int(Date().timeIntervalSince(start) * 1000.0)))
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let summary = root["summary"] as? [String: Any],
                  let rawNodes = root["nodes"] as? [[String: Any]] else {
                completion(defaultEntry(date: Date()))
                return
            }

            let total = summary["total_nodes"] as? Int ?? rawNodes.count
            let online = summary["online_nodes"] as? Int ?? total
            let lanActive = summary["lan_subnet_active"] as? Bool ?? true
            let exitActive = summary["exit_node_online"] as? Bool ?? true
            let ssActive = summary["sidestore_tun_active"] as? Bool ?? true

            var parsedNodes: [BloodMeshNodeSummary] = []
            for n in rawNodes {
                parsedNodes.append(
                    BloodMeshNodeSummary(
                        id: n["id"] as? Int ?? 0,
                        name: n["name"] as? String ?? "Node",
                        given_name: n["given_name"] as? String ?? "node",
                        ipv4: n["ipv4"] as? String ?? "",
                        online: n["online"] as? Bool ?? false,
                        role: n["role"] as? String ?? "peer",
                        subnet_routes: n["subnet_routes"] as? [String] ?? [],
                        is_exit_node: n["is_exit_node"] as? Bool ?? false,
                        exit_node_approved: n["exit_node_approved"] as? Bool ?? false
                    )
                )
            }

            let iphoneOnline = parsedNodes.first(where: { $0.role == "iphone" })?.online ?? false
            completion(
                BloodMeshEntry(
                    date: Date(),
                    tunnelSealed: local.sealed || iphoneOnline,
                    localTunnelIP: local.ip,
                    tunnelInterface: local.iface,
                    onlineNodes: online,
                    totalNodes: max(1, total),
                    lanRouteActive: lanActive,
                    exitNodeActive: exitActive,
                    sideStoreRouteActive: ssActive,
                    derpLatencyMs: elapsedMs,
                    nodes: parsedNodes
                )
            )
        }.resume()
    }
}

struct BloodMeshWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: BloodMeshEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumView
            } else {
                smallView
            }
        }
        .containerBackground(for: .widget) {
            GothicCathedralBackground()
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 5) {
            GothicHeader(
                title: "BLOODMESH",
                rightText: entry.tunnelSealed ? "SEALED" : "SEVERED"
            )

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Circle()
                    .fill(entry.tunnelSealed ? GothicTheme.bloodHi : GothicTheme.ash)
                    .frame(width: 7, height: 7)
                    .shadow(color: entry.tunnelSealed ? GothicTheme.bloodHi : .clear, radius: 4)
                Text(entry.localTunnelIP)
                    .font(GothicTheme.display(20))
                    .foregroundStyle(GothicTheme.bone)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
            }

            Text("\(entry.onlineNodes)/\(entry.totalNodes) Coven Nodes · \(entry.derpLatencyMs)ms")
                .font(GothicTheme.serif(10, weight: .medium))
                .italic()
                .foregroundStyle(GothicTheme.bloodHi)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text(entry.lanRouteActive ? "LAN 192.168.0.x" : "MESH ONLY")
                    .font(GothicTheme.serif(8.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(GothicTheme.bone)
                Spacer(minLength: 2)
                Text("DERP 999")
                    .font(GothicTheme.serif(8, weight: .semibold))
                    .foregroundStyle(GothicTheme.ash)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .gothicPanel(active: entry.tunnelSealed, corner: 6)
        }
        .padding(11)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            GothicHeader(
                title: "BLOODMESH ✠ HEADSCALE SANCTUM",
                rightText: "hs.nas-server.co.uk · \(entry.derpLatencyMs)ms"
            )

            HStack(spacing: 10) {
                // Left column: iPhone tunnel seal
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(entry.tunnelSealed ? GothicTheme.bloodHi : GothicTheme.ash)
                            .frame(width: 8, height: 8)
                            .shadow(color: entry.tunnelSealed ? GothicTheme.bloodHi : .clear, radius: 4)
                        Text(entry.tunnelSealed ? "BLOODLINE SEALED" : "TUNNEL SEVERED")
                            .font(GothicTheme.serif(8.5, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(entry.tunnelSealed ? GothicTheme.bloodHi : GothicTheme.ash)
                    }

                    Text(entry.localTunnelIP)
                        .font(GothicTheme.display(21))
                        .foregroundStyle(GothicTheme.bone)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)

                    Text("mesh.internal · \(entry.onlineNodes)/\(entry.totalNodes) online")
                        .font(GothicTheme.serif(9.5, weight: .medium))
                        .italic()
                        .foregroundStyle(GothicTheme.ash)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        badge("LAN .0/24", active: entry.lanRouteActive)
                        badge("EXIT", active: entry.exitNodeActive)
                        badge("10.7.0.1", active: entry.sideStoreRouteActive)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right column: 4 Coven Nodes
                VStack(alignment: .leading, spacing: 3.5) {
                    ForEach(entry.nodes.prefix(4)) { node in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(node.online ? GothicTheme.bloodHi : GothicTheme.ash.opacity(0.4))
                                .frame(width: 5.5, height: 5.5)
                            Text(node.given_name)
                                .font(GothicTheme.serif(9.5, weight: .bold))
                                .foregroundStyle(GothicTheme.bone)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(node.ipv4)
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(GothicTheme.ash)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .gothicPanel(active: node.online && node.role == "iphone", corner: 5)
                    }
                }
                .frame(width: 155)
            }
        }
        .padding(11)
    }

    private func badge(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(GothicTheme.serif(7.5, weight: .bold))
            .foregroundStyle(active ? GothicTheme.bone : GothicTheme.ash)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .gothicPanel(active: active, corner: 4)
    }
}

@main
struct BloodMeshWidget: Widget {
    let kind: String = "BloodMeshWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BloodMeshProvider()) { entry in
            BloodMeshWidgetView(entry: entry)
        }
        .configurationDisplayName("BloodMesh Headscale VPN")
        .description("Gothic Vampire Headscale VPN tunnel seal, live mesh nodes, and home LAN route telemetry.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
