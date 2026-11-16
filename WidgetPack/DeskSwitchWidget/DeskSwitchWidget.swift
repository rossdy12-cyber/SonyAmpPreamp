import WidgetKit
import SwiftUI
import AppIntents

struct DeskSwitchActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Invoke DeskSwitch Rite"

    @Parameter(title: "Action")
    var action: String

    init() { self.action = "monitor" }
    init(action: String) { self.action = action }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(action, forKey: "deskswitch.widget.lastAction")
        if let url = URL(string: "http://100.85.127.42:18998/ops/status") {
            _ = try? await URLSession.shared.data(from: url)
        }
        return .result()
    }
}

struct DeskSwitchEntry: TimelineEntry {
    let date: Date
    let activeDisplay: String
    let activeKey: String
}

struct DeskSwitchProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeskSwitchEntry {
        DeskSwitchEntry(date: Date(), activeDisplay: "Desk 4K Altar", activeKey: "monitor")
    }
    func getSnapshot(in context: Context, completion: @escaping (DeskSwitchEntry) -> Void) {
        completion(load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DeskSwitchEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func load() -> DeskSwitchEntry {
        let act = UserDefaults.standard.string(forKey: "deskswitch.widget.lastAction") ?? "monitor"
        let disp: String
        switch act {
        case "tv": disp = "Sanctum 4K TV"
        case "wake": disp = "Awakened (WoL)"
        case "sleep": disp = "In Torpor"
        default: disp = "Desk 4K Altar"
        }
        return DeskSwitchEntry(date: Date(), activeDisplay: disp, activeKey: act)
    }
}

struct DeskSwitchWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DeskSwitchEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Text("✠ PC").font(GothicTheme.serif(12, weight: .bold))
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("✠ DeskSwitch · PC").font(GothicTheme.serif(13, weight: .bold))
                Text(entry.activeDisplay).font(GothicTheme.serif(11))
                Text("Monitor · 4K TV · Wake · Torpor").font(GothicTheme.serif(9)).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("✠ PC: \(entry.activeDisplay)")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 5) {
            GothicHeader(title: "DeskSwitch", rightText: "PC")
            Text(entry.activeDisplay)
                .font(GothicTheme.display(15))
                .foregroundStyle(GothicTheme.bone)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                riteBtn("Monitor", icon: "display", key: "monitor")
                riteBtn("4K TV", icon: "tv.fill", key: "tv")
            }
            HStack(spacing: 5) {
                riteBtn("Awaken", icon: "bolt.fill", key: "wake")
                riteBtn("Torpor", icon: "moon.fill", key: "sleep")
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            GothicHeader(title: "DeskSwitch · ROSS-DYMOND-PC", rightText: entry.activeDisplay)
            HStack(spacing: 8) {
                riteBtn("Monitor", icon: "display", key: "monitor")
                riteBtn("4K TV", icon: "tv.fill", key: "tv")
                riteBtn("Awaken", icon: "bolt.fill", key: "wake")
                riteBtn("Torpor", icon: "moon.zzz.fill", key: "sleep")
            }
            GothicOrnamentRule()
            Text("Command display altars and Wake-on-LAN across the Nocturne LAN.")
                .font(GothicTheme.serif(10))
                .italic()
                .foregroundStyle(GothicTheme.ash)
                .lineLimit(1)
        }
    }

    private func riteBtn(_ title: String, icon: String, key: String) -> some View {
        let isSel = (entry.activeKey == key)
        return Button(intent: DeskSwitchActionIntent(action: key)) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isSel ? GothicTheme.bone : GothicTheme.bloodHi)
                Text(title)
                    .font(GothicTheme.serif(9.5, weight: .bold))
                    .foregroundStyle(GothicTheme.bone)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 5)
            .gothicPanel(active: isSel, corner: 7)
        }
        .buttonStyle(.plain)
    }
}

struct DeskSwitchWidget: Widget {
    let kind = "DeskSwitchWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DeskSwitchProvider()) { entry in
            DeskSwitchWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GothicCathedralBackground()
                }
        }
        .configurationDisplayName("DeskSwitch Altar")
        .description("Gothic Vampire PC Monitor/TV switcher & Wake-on-LAN controls.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct DeskSwitchWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeskSwitchWidget()
    }
}
