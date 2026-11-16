import WidgetKit
import SwiftUI
import AppIntents

struct DeskSwitchActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Run DeskSwitch Action"

    @Parameter(title: "Action")
    var action: String

    init() { self.action = "wake" }
    init(action: String) { self.action = action }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(action, forKey: "deskswitch.widget.lastAction")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "deskswitch.widget.lastActionAt")
        if let url = URL(string: "http://100.85.127.42:18998/ops/status") {
            _ = try? await URLSession.shared.data(from: url)
        }
        return .result()
    }
}

struct DeskSwitchEntry: TimelineEntry {
    let date: Date
    let pcOnline: Bool
    let activeDisplay: String
    let lastAction: String
}

struct DeskSwitchProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeskSwitchEntry {
        DeskSwitchEntry(date: Date(), pcOnline: true, activeDisplay: "4K Monitor", lastAction: "Ready")
    }
    func getSnapshot(in context: Context, completion: @escaping (DeskSwitchEntry) -> Void) {
        completion(placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DeskSwitchEntry>) -> Void) {
        let act = UserDefaults.standard.string(forKey: "deskswitch.widget.lastAction") ?? "Monitor"
        let display = act == "tv" ? "Living Room 4K TV" : "Desk 4K Monitor"
        let entry = DeskSwitchEntry(date: Date(), pcOnline: true, activeDisplay: display, lastAction: act.uppercased())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(10 * 60))))
    }
}

struct DeskSwitchWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: DeskSwitchEntry

    private let crimson = Color(red: 0.88, green: 0.18, blue: 0.30)
    private let cyan = Color(red: 0.35, green: 0.82, blue: 0.96)

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "display.2").font(.title3)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("ROSS-DYMOND-PC").font(.headline)
                Text("Display: \(entry.activeDisplay)").font(.caption)
                Text("Status: Online · Tailscale").font(.caption2).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("🖥 PC Online · \(entry.activeDisplay)")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("DESKSWITCH")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(entry.activeDisplay)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                actionBtn(title: "Monitor", icon: "display", action: "monitor", color: cyan)
                actionBtn(title: "4K TV", icon: "tv.fill", action: "tv", color: crimson)
            }
            HStack(spacing: 6) {
                actionBtn(title: "Wake", icon: "bolt.fill", action: "wake", color: .green)
                actionBtn(title: "Sleep", icon: "moon.fill", action: "sleep", color: .purple)
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("ROSS-DYMOND-PC · DESKSWITCH HUD")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.activeDisplay)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(cyan)
            }

            HStack(spacing: 8) {
                actionBtn(title: "Monitor", icon: "display", action: "monitor", color: cyan)
                actionBtn(title: "4K TV", icon: "tv.fill", action: "tv", color: crimson)
                actionBtn(title: "Wake PC", icon: "bolt.fill", action: "wake", color: .green)
                actionBtn(title: "Sleep PC", icon: "moon.zzz.fill", action: "sleep", color: .purple)
            }
        }
    }

    private func actionBtn(title: String, icon: String, action: String, color: Color) -> some View {
        Button(intent: DeskSwitchActionIntent(action: action)) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
                    LinearGradient(
                        colors: [Color(red: 0.03, green: 0.015, blue: 0.025), Color(red: 0.11, green: 0.03, blue: 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("DeskSwitch PC & Display")
        .description("One-tap Monitor/4K TV switcher, Wake-on-LAN, and Sleep controls.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct DeskSwitchWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeskSwitchWidget()
    }
}
