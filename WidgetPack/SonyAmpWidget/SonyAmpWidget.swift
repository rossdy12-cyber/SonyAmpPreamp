import WidgetKit
import SwiftUI
import AppIntents

struct SelectDSPPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Select AirPods Pro 2 H2 DSP Preset"

    @Parameter(title: "Preset Name")
    var presetName: String

    init() { self.presetName = "Sub-Slam" }
    init(presetName: String) { self.presetName = presetName }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(presetName, forKey: "sonyamp.widget.preset")
        return .result()
    }
}

struct SonyAmpEntry: TimelineEntry {
    let date: Date
    let activePreset: String
    let subBassDB: String
    let dseeAirDB: String
    let stageWidth: String
}

struct SonyAmpProvider: TimelineProvider {
    func placeholder(in context: Context) -> SonyAmpEntry { load() }
    func getSnapshot(in context: Context, completion: @escaping (SonyAmpEntry) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SonyAmpEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func load() -> SonyAmpEntry {
        let p = UserDefaults.standard.string(forKey: "sonyamp.widget.preset") ?? "Sub-Slam"
        switch p {
        case "Harman Ref":
            return SonyAmpEntry(date: Date(), activePreset: "Harman Reference", subBassDB: "+3.5 dB", dseeAirDB: "+2.5 dB", stageWidth: "115%")
        case "Spatial 3D":
            return SonyAmpEntry(date: Date(), activePreset: "Cathedral 3D Stage", subBassDB: "+4.0 dB", dseeAirDB: "+4.0 dB", stageWidth: "140%")
        case "Sony ES":
            return SonyAmpEntry(date: Date(), activePreset: "Sony ES Pre-Amp", subBassDB: "+5.0 dB", dseeAirDB: "+3.0 dB", stageWidth: "120%")
        default:
            return SonyAmpEntry(date: Date(), activePreset: "H2 45Hz Sub-Slam", subBassDB: "+7.5 dB", dseeAirDB: "+3.5 dB", stageWidth: "125%")
        }
    }
}

struct SonyAmpWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: SonyAmpEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Text("✠ H2").font(GothicTheme.serif(12, weight: .bold))
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("✠ Sony ES & H2 DSP").font(GothicTheme.serif(13, weight: .bold))
                Text(entry.activePreset).font(GothicTheme.serif(11))
                Text("45Hz \(entry.subBassDB) · Air \(entry.dseeAirDB) · 32-Bit").font(GothicTheme.serif(9)).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("✠ \(entry.activePreset) (\(entry.subBassDB))")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            GothicHeader(title: "Nocturne DSP", rightText: "32-Bit")
            Text(entry.activePreset)
                .font(GothicTheme.display(15))
                .foregroundStyle(GothicTheme.bone)
                .lineLimit(1)
            Text("Sub \(entry.subBassDB) · Air \(entry.dseeAirDB)")
                .font(GothicTheme.serif(9.5, weight: .semibold))
                .italic()
                .foregroundStyle(GothicTheme.bloodHi)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                presetBtn("Sub-Slam")
                presetBtn("Harman Ref")
            }
            HStack(spacing: 4) {
                presetBtn("Spatial 3D")
                presetBtn("Sony ES")
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 7) {
            GothicHeader(title: "Sony ES & AirPods Pro 2 H2 Choir", rightText: "48kHz / 32-Bit")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.activePreset)
                        .font(GothicTheme.display(20))
                        .foregroundStyle(GothicTheme.bone)
                    Text("45Hz Sub \(entry.subBassDB) · 14kHz DSEE Silk \(entry.dseeAirDB) · Stage \(entry.stageWidth)")
                        .font(GothicTheme.serif(10.5, weight: .semibold))
                        .italic()
                        .foregroundStyle(GothicTheme.bloodHi)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                presetBtn("Sub-Slam")
                presetBtn("Harman Ref")
                presetBtn("Spatial 3D")
                presetBtn("Sony ES")
            }
        }
    }

    private func presetBtn(_ title: String) -> some View {
        let isSel = entry.activePreset.lowercased().contains(title.prefix(4).lowercased())
            || (title == "Spatial 3D" && entry.activePreset.contains("Cathedral"))
        return Button(intent: SelectDSPPresetIntent(presetName: title)) {
            Text(title)
                .font(GothicTheme.serif(9.5, weight: .bold))
                .foregroundStyle(GothicTheme.bone)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .gothicPanel(active: isSel, corner: 6)
        }
        .buttonStyle(.plain)
    }
}

struct SonyAmpWidget: Widget {
    let kind = "SonyAmpWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SonyAmpProvider()) { entry in
            SonyAmpWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GothicCathedralBackground()
                }
        }
        .configurationDisplayName("Sony Amp & AirPods H2 Choir")
        .description("Gothic Vampire 32-Bit H2 DSP preset switcher.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct SonyAmpWidgetBundle: WidgetBundle {
    var body: some Widget {
        SonyAmpWidget()
    }
}
