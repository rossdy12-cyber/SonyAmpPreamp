import WidgetKit
import SwiftUI
import AppIntents

struct SelectDSPPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Select AirPods Pro 2 H2 DSP Preset"

    @Parameter(title: "Preset Name")
    var presetName: String

    init() { self.presetName = "AirPods Pro 2 Harman Ref" }
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
    func placeholder(in context: Context) -> SonyAmpEntry {
        load()
    }
    func getSnapshot(in context: Context, completion: @escaping (SonyAmpEntry) -> Void) {
        completion(load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SonyAmpEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func load() -> SonyAmpEntry {
        let p = UserDefaults.standard.string(forKey: "sonyamp.widget.preset") ?? "AirPods Pro 2 H2 Sub-Slam"
        switch p {
        case "Harman Ref":
            return SonyAmpEntry(date: Date(), activePreset: "Harman Reference", subBassDB: "+3.5 dB", dseeAirDB: "+2.5 dB", stageWidth: "115%")
        case "Spatial 3D":
            return SonyAmpEntry(date: Date(), activePreset: "Spatial 3D Stage", subBassDB: "+4.0 dB", dseeAirDB: "+4.0 dB", stageWidth: "140%")
        case "Sony ES":
            return SonyAmpEntry(date: Date(), activePreset: "Sony ES Line-Driver", subBassDB: "+5.0 dB", dseeAirDB: "+3.0 dB", stageWidth: "120%")
        default:
            return SonyAmpEntry(date: Date(), activePreset: "H2 45Hz Sub-Slam", subBassDB: "+7.5 dB", dseeAirDB: "+3.5 dB", stageWidth: "125%")
        }
    }
}

struct SonyAmpWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: SonyAmpEntry

    private let crimson = Color(red: 0.92, green: 0.18, blue: 0.32)

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "airpodspro").font(.title3)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("AirPods Pro 2 H2 DSP", systemImage: "airpodspro").font(.headline)
                Text(entry.activePreset).font(.caption)
                Text("45Hz \(entry.subBassDB) · Air \(entry.dseeAirDB) · 32-Bit").font(.caption2).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("🎧 \(entry.activePreset) (\(entry.subBassDB))")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "airpodspro").foregroundStyle(crimson)
                Text("H2 32-BIT DSP").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
            }
            Text(entry.activePreset)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("Sub \(entry.subBassDB) · Air \(entry.dseeAirDB)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(crimson)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                presetBtn("Sub-Slam")
                presetBtn("Harman Ref")
            }
            HStack(spacing: 5) {
                presetBtn("Spatial 3D")
                presetBtn("Sony ES")
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "airpodspro").foregroundStyle(crimson)
                Text("SONY ES & AIRPODS PRO 2 H2 SOUNDING")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("48kHz / 32-BIT")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.green)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.activePreset)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("45Hz Sub \(entry.subBassDB) · 14kHz DSEE Air \(entry.dseeAirDB) · Stage \(entry.stageWidth)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(crimson)
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
        let isSel = entry.activePreset.lowercased().contains(title.prefix(6).lowercased())
        return Button(intent: SelectDSPPresetIntent(presetName: title)) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSel ? crimson : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
                    LinearGradient(
                        colors: [Color(red: 0.04, green: 0.01, blue: 0.02), Color(red: 0.13, green: 0.03, blue: 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Sony Amp & AirPods H2 DSP")
        .description("Switch AirPods Pro 2 H2 32-Bit DSP presets and launch YouTube+ DSP.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct SonyAmpWidgetBundle: WidgetBundle {
    var body: some Widget {
        SonyAmpWidget()
    }
}
