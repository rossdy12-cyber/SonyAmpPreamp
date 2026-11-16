import WidgetKit
import SwiftUI
import AppIntents

struct TorporConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Torpor Slumber Sanctum"
    static var description = IntentDescription("Gothic Vampire Smart Phase Alarm & Acoustic Night Watch.")

    @Parameter(title: "Target Awakening", default: "07:00")
    var wakeTime: String

    @Parameter(title: "Phase Window (min)", default: 20)
    var windowMinutes: Int

    @Parameter(title: "Nocturne Soundscape", default: "Cathedral Rain")
    var soundscape: String

    init() {}
}

struct ToggleTorporArmIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Torpor Night Watch"
    func perform() async throws -> some IntentResult {
        let cur = UserDefaults.standard.bool(forKey: "torpor.widget.armed")
        UserDefaults.standard.set(!cur, forKey: "torpor.widget.armed")
        return .result()
    }
}

struct TorporEntry: TimelineEntry {
    let date: Date
    let config: TorporConfigIntent
    let isArmed: Bool
    let noiseFloorDB: Int
    let sleepScore: Int
    let deepMinutes: Int
    let remMinutes: Int
    let lightMinutes: Int
}

struct TorporProvider: AppIntentTimelineProvider {
    typealias Intent = TorporConfigIntent
    typealias Entry = TorporEntry

    func placeholder(in context: Context) -> TorporEntry { sample(TorporConfigIntent()) }
    func snapshot(for configuration: TorporConfigIntent, in context: Context) async -> TorporEntry { sample(configuration) }
    func timeline(for configuration: TorporConfigIntent, in context: Context) async -> Timeline<TorporEntry> {
        Timeline(entries: [sample(configuration)], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func sample(_ cfg: TorporConfigIntent) -> TorporEntry {
        let armed = UserDefaults.standard.object(forKey: "torpor.widget.armed") as? Bool ?? true
        return TorporEntry(date: Date(), config: cfg, isArmed: armed, noiseFloorDB: 33, sleepScore: 88, deepMinutes: 118, remMinutes: 96, lightMinutes: 224)
    }
}

struct TorporWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TorporEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("✠").font(.caption2)
                    Text(entry.config.wakeTime).font(GothicTheme.serif(11, weight: .bold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("✠ Torpor · \(entry.config.wakeTime)").font(GothicTheme.serif(13, weight: .bold))
                Text("Window -\(entry.config.windowMinutes)m · \(entry.sleepScore)% Rest").font(GothicTheme.serif(10))
                Text("Deep \(entry.deepMinutes)m · REM \(entry.remMinutes)m · \(entry.noiseFloorDB)dBA").font(GothicTheme.serif(9)).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("✠ Torpor \(entry.config.wakeTime) · \(entry.sleepScore)%")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            GothicHeader(title: "Torpor", rightText: "\(entry.noiseFloorDB) dBA")
            Spacer(minLength: 0)
            Text(entry.config.wakeTime)
                .font(GothicTheme.display(34))
                .foregroundStyle(GothicTheme.bone)
            Text("Awakening · -\(entry.config.windowMinutes)m")
                .font(GothicTheme.serif(10, weight: .medium))
                .italic()
                .foregroundStyle(GothicTheme.ash)
            Spacer(minLength: 2)
            Button(intent: ToggleTorporArmIntent()) {
                HStack(spacing: 4) {
                    Text("✠")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GothicTheme.bloodHi)
                    Text(entry.isArmed ? "VIGIL ARMED" : "VIGIL DORMANT")
                        .font(GothicTheme.serif(9.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(GothicTheme.bone)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .gothicPanel(active: entry.isArmed, corner: 6)
            }
            .buttonStyle(.plain)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            smallView.frame(maxWidth: 138)
            VStack(alignment: .leading, spacing: 6) {
                GothicHeader(title: "Slumber Crypt", rightText: "\(entry.sleepScore)%")
                stageBar("Deep Torpor", mins: entry.deepMinutes, total: 440, color: GothicTheme.bloodHi)
                stageBar("Sanguine REM", mins: entry.remMinutes, total: 440, color: GothicTheme.blood)
                stageBar("Shadow Light", mins: entry.lightMinutes, total: 440, color: GothicTheme.bone.opacity(0.75))
                Text("♫ \(entry.config.soundscape)")
                    .font(GothicTheme.serif(10, weight: .medium))
                    .italic()
                    .foregroundStyle(GothicTheme.ash)
            }
        }
    }

    private func stageBar(_ label: String, mins: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(GothicTheme.serif(10, weight: .medium)).foregroundStyle(GothicTheme.bone)
                Spacer()
                Text("\(mins / 60)h \(mins % 60)m").font(GothicTheme.serif(10, weight: .bold)).foregroundStyle(GothicTheme.bloodHi)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(GothicTheme.crypt)
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: geo.size.width * CGFloat(min(Double(mins) / Double(total), 1.0)))
                }
            }
            .frame(height: 5)
        }
    }
}

struct TorporWidget: Widget {
    let kind = "TorporWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TorporConfigIntent.self, provider: TorporProvider()) { entry in
            TorporWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GothicCathedralBackground()
                }
        }
        .configurationDisplayName("Torpor Slumber Sanctum")
        .description("Gothic Vampire Smart Phase Alarm & Acoustic Night Watch.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct TorporWidgetBundle: WidgetBundle {
    var body: some Widget {
        TorporWidget()
    }
}
