import WidgetKit
import SwiftUI
import AppIntents

struct NASConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Keepwatch Citadel"
    static var description = IntentDescription("Gothic Vampire TrueNAS pool, thermal, memory & container guard.")

    @Parameter(title: "Status address", default: "http://100.85.127.42:18998/ops/status")
    var endpoint: String

    init() {}
}

struct NASSnapshot {
    var hostname = "TrueNAS"
    var memPercent = 72
    var cpuTempC = 44
    var poolPercent = 81
    var containersUp = 56
    var containersTotal = 58
}

struct NASEntry: TimelineEntry {
    let date: Date
    let snapshot: NASSnapshot
}

struct NASProvider: AppIntentTimelineProvider {
    typealias Intent = NASConfigIntent
    typealias Entry = NASEntry

    func placeholder(in context: Context) -> NASEntry { NASEntry(date: Date(), snapshot: NASSnapshot()) }
    func snapshot(for configuration: NASConfigIntent, in context: Context) async -> NASEntry {
        await load(configuration)
    }
    func timeline(for configuration: NASConfigIntent, in context: Context) async -> Timeline<NASEntry> {
        let entry = await load(configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(10 * 60)))
    }

    private func load(_ cfg: NASConfigIntent) async -> NASEntry {
        var s = NASSnapshot()
        if let url = URL(string: cfg.endpoint),
           let (data, resp) = try? await URLSession.shared.data(from: url),
           let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            s.hostname = (root["hostname"] as? String) ?? "TrueNAS"
            s.memPercent = (root["memPercent"] as? NSNumber)?.intValue ?? 72
            s.cpuTempC = (root["cpuTempC"] as? NSNumber)?.intValue ?? 44
            s.poolPercent = (root["poolPercent"] as? NSNumber)?.intValue ?? 81
            if let cons = root["containers"] as? [[String: Any]] {
                s.containersTotal = cons.count
                s.containersUp = cons.filter { (($0["status"] as? String) ?? "").lowercased().hasPrefix("up") }.count
            }
        }
        return NASEntry(date: Date(), snapshot: s)
    }
}

struct KeepwatchWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: NASEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("✠").font(.caption2)
                    Text("\(entry.snapshot.poolPercent)%").font(GothicTheme.serif(12, weight: .bold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("✠ Keepwatch · \(entry.snapshot.hostname)").font(GothicTheme.serif(13, weight: .bold))
                Text("Pool \(entry.snapshot.poolPercent)% · RAM \(entry.snapshot.memPercent)% · \(entry.snapshot.cpuTempC)°C").font(GothicTheme.serif(10))
                Text("\(entry.snapshot.containersUp)/\(entry.snapshot.containersTotal) Sanctum Vessels").font(GothicTheme.serif(9)).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("✠ NAS \(entry.snapshot.poolPercent)% · \(entry.snapshot.cpuTempC)°C · \(entry.snapshot.containersUp)/\(entry.snapshot.containersTotal)")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 5) {
            GothicHeader(title: "Keepwatch", rightText: "\(entry.snapshot.cpuTempC)°C")
            Spacer(minLength: 0)
            Text("\(entry.snapshot.containersUp)/\(entry.snapshot.containersTotal)")
                .font(GothicTheme.display(32))
                .foregroundStyle(GothicTheme.bone)
            Text("VESSELS RISEN")
                .font(GothicTheme.serif(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(GothicTheme.bloodHi)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                pill("POOL", "\(entry.snapshot.poolPercent)%")
                pill("RAM", "\(entry.snapshot.memPercent)%")
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 7) {
            GothicHeader(title: "Keepwatch Citadel · \(entry.snapshot.hostname)", rightText: "\(entry.snapshot.containersUp)/\(entry.snapshot.containersTotal) Active")
            HStack(spacing: 8) {
                metricBox("ZFS POOL", "\(entry.snapshot.poolPercent)%")
                metricBox("MEMORY", "\(entry.snapshot.memPercent)%")
                metricBox("CORE TEMP", "\(entry.snapshot.cpuTempC)°C")
                metricBox("VESSELS", "\(entry.snapshot.containersUp)")
            }
            GothicOrnamentRule()
            Text("All TrueNAS ZFS pools, Tailscale tunnels & Stark Store daemons guarded.")
                .font(GothicTheme.serif(10))
                .italic()
                .foregroundStyle(GothicTheme.ash)
                .lineLimit(1)
        }
    }

    private func pill(_ k: String, _ v: String) -> some View {
        HStack(spacing: 4) {
            Text(k).font(GothicTheme.serif(8.5, weight: .bold)).foregroundStyle(GothicTheme.ash)
            Spacer(minLength: 0)
            Text(v).font(GothicTheme.serif(10, weight: .bold)).foregroundStyle(GothicTheme.bone)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .gothicPanel(active: true, corner: 5)
    }

    private func metricBox(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(GothicTheme.serif(8, weight: .bold))
                .foregroundStyle(GothicTheme.ash)
            Text(value)
                .font(GothicTheme.display(20))
                .foregroundStyle(GothicTheme.bone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .gothicPanel(active: true, corner: 7)
    }
}

struct KeepwatchNASWidget: Widget {
    let kind = "KeepwatchNASWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: NASConfigIntent.self, provider: NASProvider()) { entry in
            KeepwatchWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GothicCathedralBackground()
                }
        }
        .configurationDisplayName("Keepwatch Citadel")
        .description("Gothic Vampire TrueNAS ZFS pool, thermal & container guard.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct KeepwatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        KeepwatchNASWidget()
    }
}
