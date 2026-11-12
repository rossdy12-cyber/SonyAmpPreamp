import WidgetKit
import SwiftUI
import AppIntents
import UIKit

// ======================================================================
// MARK: - Widget 1: NAS health
// ======================================================================

struct NASConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "NAS health"
    static var description = IntentDescription("Pool, memory, temperature and services on your TrueNAS.")

    // Reachable over Tailscale. Change it in Edit Widget if your NAS address differs.
    @Parameter(title: "Status address", default: "http://100.85.127.42:18998/ops/status")
    var endpoint: String

    init() {}
}

struct NASService {
    let name: String
    let up: Bool
}

struct NASSnapshot {
    var hostname = "TrueNAS"
    var uptime = ""
    var memPercent = 0
    var cpuTempC = 0
    var poolPercent = 0
    var poolUsedGB = 0
    var poolTotalGB = 0
    var services: [NASService] = []
    var containersUp = 0
    var containersTotal = 0
}

enum NASFetchError: Error {
    case badAddress
    case badResponse
}

enum NASClient {
    private static func intValue(_ any: Any?) -> Int {
        return (any as? NSNumber)?.intValue ?? 0
    }

    private static func shortName(_ raw: String) -> String {
        let n = raw.replacingOccurrences(of: ".service", with: "")
        switch n {
        case "sidestore-ipa-receiver": return "Receiver"
        case "sidestore-tun": return "Tunnel"
        case "tailscaled": return "Tailscale"
        case "docker": return "Docker"
        default: return String(n.prefix(10))
        }
    }

    static func fetch(endpoint: String) async throws -> NASSnapshot {
        var e = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.isEmpty { throw NASFetchError.badAddress }
        if !e.contains("://") { e = "http://" + e }
        guard let url = URL(string: e) else { throw NASFetchError.badAddress }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("KeepwatchWidget/1.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NASFetchError.badResponse
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NASFetchError.badResponse
        }
        var s = NASSnapshot()
        s.hostname = (root["hostname"] as? String) ?? "TrueNAS"
        s.uptime = (root["uptime"] as? String) ?? ""
        s.memPercent = intValue(root["memPercent"])
        s.cpuTempC = intValue(root["cpuTempC"])
        s.poolPercent = intValue(root["poolPercent"])
        s.poolUsedGB = intValue(root["poolUsedGB"])
        s.poolTotalGB = intValue(root["poolTotalGB"])
        if let svcs = root["services"] as? [[String: Any]] {
            s.services = svcs.map { d in
                let name = (d["name"] as? String) ?? "service"
                let status = (d["status"] as? String) ?? ""
                return NASService(name: shortName(name), up: status == "active")
            }
        }
        if let cons = root["containers"] as? [[String: Any]] {
            s.containersTotal = cons.count
            s.containersUp = cons.filter { (($0["status"] as? String) ?? "").lowercased().hasPrefix("up") }.count
        }
        return s
    }
}

struct NASEntry: TimelineEntry {
    let date: Date
    let snapshot: NASSnapshot?
    let errorText: String?

    static var sample: NASEntry {
        var s = NASSnapshot()
        s.hostname = "nas-server"
        s.memPercent = 74
        s.cpuTempC = 46
        s.poolPercent = 82
        s.poolUsedGB = 12900
        s.poolTotalGB = 15600
        s.services = [NASService(name: "Receiver", up: true), NASService(name: "Docker", up: true),
                      NASService(name: "Tailscale", up: true), NASService(name: "Tunnel", up: true)]
        s.containersUp = 56
        s.containersTotal = 58
        return NASEntry(date: Date(), snapshot: s, errorText: nil)
    }
}

struct NASProvider: AppIntentTimelineProvider {
    typealias Intent = NASConfigIntent
    typealias Entry = NASEntry

    func placeholder(in context: Context) -> NASEntry { NASEntry.sample }

    func snapshot(for configuration: NASConfigIntent, in context: Context) async -> NASEntry {
        if context.isPreview { return NASEntry.sample }
        return await load(configuration)
    }

    func timeline(for configuration: NASConfigIntent, in context: Context) async -> Timeline<NASEntry> {
        let entry = await load(configuration)
        let next = Date().addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func load(_ config: NASConfigIntent) async -> NASEntry {
        do {
            let snap = try await NASClient.fetch(endpoint: config.endpoint)
            return NASEntry(date: Date(), snapshot: snap, errorText: nil)
        } catch {
            return NASEntry(date: Date(), snapshot: nil, errorText: "Can't reach the NAS. Is Tailscale connected?")
        }
    }
}

struct RingGauge: View {
    let fraction: Double
    let color: Color
    let title: String
    let valueText: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.14), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(valueText).font(.system(.caption, design: .rounded).weight(.bold))
            }
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct ServiceDots: View {
    let services: [NASService]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(services.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 3) {
                    Circle().fill(s.up ? Color.green : Color.red).frame(width: 6, height: 6)
                    Text(s.name).font(.caption2).lineLimit(1)
                }
            }
        }
    }
}

struct NASWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: NASEntry

    private func usageColor(_ pct: Int) -> Color {
        if pct >= 90 { return .red }
        if pct >= 80 { return .orange }
        return Color(red: 0.25, green: 0.85, blue: 0.5)
    }

    private func tempColor(_ c: Int) -> Color {
        if c >= 75 { return .red }
        if c >= 62 { return .orange }
        return Color(red: 0.25, green: 0.85, blue: 0.5)
    }

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(s.poolPercent), in: 0...100) {
                    Text("Pool")
                } currentValueLabel: {
                    Text("\(s.poolPercent)%")
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.hostname).font(.headline)
                    Text("Pool \(s.poolPercent)% · RAM \(s.memPercent)%").font(.caption)
                    Text("CPU \(s.cpuTempC)°C · \(s.containersUp)/\(s.containersTotal) up").font(.caption2)
                }
            case .systemMedium:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(s.hostname.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(s.containersUp)/\(s.containersTotal) containers").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 18) {
                        RingGauge(fraction: Double(s.poolPercent) / 100, color: usageColor(s.poolPercent),
                                  title: "Pool", valueText: "\(s.poolPercent)%")
                        RingGauge(fraction: Double(s.memPercent) / 100, color: usageColor(s.memPercent),
                                  title: "RAM", valueText: "\(s.memPercent)%")
                        RingGauge(fraction: Double(s.cpuTempC) / 100, color: tempColor(s.cpuTempC),
                                  title: "CPU", valueText: "\(s.cpuTempC)°")
                    }
                    .frame(maxHeight: 70)
                    ServiceDots(services: s.services)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.hostname.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        RingGauge(fraction: Double(s.poolPercent) / 100, color: usageColor(s.poolPercent),
                                  title: "Pool", valueText: "\(s.poolPercent)%")
                            .frame(width: 62, height: 70)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("RAM \(s.memPercent)%").font(.caption)
                            Text("CPU \(s.cpuTempC)°C").font(.caption)
                            Text("\(s.containersUp)/\(s.containersTotal) up").font(.caption)
                        }
                    }
                    ServiceDots(services: Array(s.services.prefix(3)))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("NAS offline").font(.headline)
                Text(entry.errorText ?? "").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct KeepwatchNASWidget: Widget {
    let kind = "KeepwatchNASWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: NASConfigIntent.self, provider: NASProvider()) { entry in
            NASWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.020, green: 0.008, blue: 0.012),
                                            Color(red: 0.110, green: 0.039, blue: 0.059)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("NAS health")
        .description("Pool usage, memory, CPU temperature and services on your TrueNAS.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// ======================================================================
// MARK: - Widget 2: Store updates
// ======================================================================

struct StoreItem: Identifiable {
    let id: String
    let name: String
    let version: String
    let date: Date?
    let iconData: Data?
}

struct StoreEntry: TimelineEntry {
    let date: Date
    let items: [StoreItem]
    let errorText: String?

    static var sample: StoreEntry {
        let now = Date()
        let items = [
            StoreItem(id: "a", name: "Crimson", version: "1.0.0", date: now, iconData: nil),
            StoreItem(id: "b", name: "Nocturne", version: "1.2.1", date: now.addingTimeInterval(-3600), iconData: nil),
            StoreItem(id: "c", name: "Prism", version: "1.1.0", date: now.addingTimeInterval(-7200), iconData: nil)
        ]
        return StoreEntry(date: now, items: items, errorText: nil)
    }
}

enum StoreLoader {
    static let catalogURL = "https://navidrome.nas-server.co.uk/sidestore/source.json"

    private static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: String(s.prefix(10))) { return d }
        return ISO8601DateFormatter().date(from: s)
    }

    private static func icon(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.setValue("KeepwatchWidget/1.0", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let img = UIImage(data: data) else { return nil }
            let thumb = img.preparingThumbnail(of: CGSize(width: 120, height: 120)) ?? img
            return thumb.pngData()
        } catch {
            return nil
        }
    }

    static func load() async -> StoreEntry {
        let now = Date()
        guard let url = URL(string: catalogURL) else {
            return StoreEntry(date: now, items: [], errorText: "Bad store address")
        }
        do {
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("KeepwatchWidget/1.0", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let apps = root["apps"] as? [[String: Any]] else {
                return StoreEntry(date: now, items: [], errorText: "Store unavailable")
            }
            var rows: [(name: String, bid: String, version: String, date: Date?, iconURL: String)] = []
            for a in apps {
                let name = (a["name"] as? String) ?? "App"
                let bid = (a["bundleIdentifier"] as? String) ?? name
                let versions = (a["versions"] as? [[String: Any]]) ?? []
                let v0 = versions.first ?? [:]
                let version = (v0["version"] as? String) ?? (a["version"] as? String) ?? ""
                let dateStr = (v0["date"] as? String) ?? (a["versionDate"] as? String) ?? ""
                rows.append((name, bid, version, parseDate(dateStr), (a["iconURL"] as? String) ?? ""))
            }
            rows.sort { l, r in
                let ld = l.date ?? Date.distantPast
                let rd = r.date ?? Date.distantPast
                if ld != rd { return ld > rd }
                return l.name < r.name
            }
            let top = Array(rows.prefix(6))
            var items: [StoreItem] = []
            for r in top {
                let data = await icon(r.iconURL)
                items.append(StoreItem(id: r.bid, name: r.name, version: r.version, date: r.date, iconData: data))
            }
            return StoreEntry(date: now, items: items, errorText: items.isEmpty ? "No apps listed" : nil)
        } catch {
            return StoreEntry(date: now, items: [], errorText: "Can't reach the store")
        }
    }
}

struct StoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> StoreEntry { StoreEntry.sample }

    func getSnapshot(in context: Context, completion: @escaping (StoreEntry) -> Void) {
        if context.isPreview {
            completion(StoreEntry.sample)
            return
        }
        Task { completion(await StoreLoader.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StoreEntry>) -> Void) {
        Task {
            let entry = await StoreLoader.load()
            let next = Date().addingTimeInterval(60 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct AppIconView: View {
    let item: StoreItem
    let size: CGFloat

    var body: some View {
        Group {
            if let d = item.iconData, let ui = UIImage(data: d) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "app.fill").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

struct StoreWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: StoreEntry

    private func ago(_ d: Date?) -> String {
        guard let d = d else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: d, relativeTo: Date())
    }

    private func row(_ item: StoreItem, iconSize: CGFloat) -> some View {
        HStack(spacing: 10) {
            AppIconView(item: item, size: iconSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("v\(item.version) · \(ago(item.date))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        if entry.items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Store").font(.headline)
                Text(entry.errorText ?? "").font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            switch family {
            case .systemMedium:
                VStack(alignment: .leading, spacing: 8) {
                    Text("LATEST IN YOUR STORE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(entry.items.prefix(3))) { item in
                        row(item, iconSize: 30)
                    }
                    Spacer(minLength: 0)
                }
            case .systemLarge:
                VStack(alignment: .leading, spacing: 10) {
                    Text("LATEST IN YOUR STORE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(entry.items.prefix(6))) { item in
                        row(item, iconSize: 38)
                    }
                    Spacer(minLength: 0)
                }
            default:
                let item = entry.items[0]
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEWEST").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    AppIconView(item: item, size: 46)
                    Text(item.name).font(.headline).lineLimit(1)
                    Text("v\(item.version) · \(ago(item.date))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct KeepwatchStoreWidget: Widget {
    let kind = "KeepwatchStoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StoreProvider()) { entry in
            StoreWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.020, green: 0.008, blue: 0.012),
                                            Color(red: 0.110, green: 0.039, blue: 0.059)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Store updates")
        .description("The newest apps and versions in your SideStore.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// ======================================================================
// MARK: - Bundle
// ======================================================================

@main
struct KeepwatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        KeepwatchNASWidget()
        KeepwatchStoreWidget()
    }
}
