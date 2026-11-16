import WidgetKit
import SwiftUI
import AppIntents

struct TorporConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Torpor Sleep & Smart Alarm"
    static var description = IntentDescription("Smart REM/Light phase alarm window, acoustic snore/disturbance monitor, and sleep stage summary.")

    @Parameter(title: "Target Wake Time", default: "07:00")
    var wakeTime: String

    @Parameter(title: "Smart Phase Window (min)", default: 20)
    var windowMinutes: Int

    @Parameter(title: "Soundscape", default: "Cathedral Rain")
    var soundscape: String

    init() {}
}

struct ToggleTorporArmIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Torpor Overnight Guard"
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
    let eventsCaught: Int
}

struct TorporProvider: AppIntentTimelineProvider {
    typealias Intent = TorporConfigIntent
    typealias Entry = TorporEntry

    func placeholder(in context: Context) -> TorporEntry {
        sample(TorporConfigIntent())
    }

    func snapshot(for configuration: TorporConfigIntent, in context: Context) async -> TorporEntry {
        sample(configuration)
    }

    func timeline(for configuration: TorporConfigIntent, in context: Context) async -> Timeline<TorporEntry> {
        let entry = sample(configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func sample(_ cfg: TorporConfigIntent) -> TorporEntry {
        let armed = UserDefaults.standard.object(forKey: "torpor.widget.armed") as? Bool ?? true
        return TorporEntry(
            date: Date(),
            config: cfg,
            isArmed: armed,
            noiseFloorDB: 33,
            sleepScore: 86,
            deepMinutes: 112,
            remMinutes: 98,
            lightMinutes: 230,
            eventsCaught: 2
        )
    }
}

struct TorporWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TorporEntry

    private let crimson = Color(red: 0.86, green: 0.16, blue: 0.28)
    private let violet = Color(red: 0.62, green: 0.42, blue: 0.92)
    private let bone = Color(red: 0.94, green: 0.90, blue: 0.88)

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "moon.zzz.fill").font(.caption)
                    Text(entry.config.wakeTime).font(.system(size: 11, weight: .bold, design: .rounded))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "moon.stars.fill")
                    Text("Torpor · \(entry.config.wakeTime)").font(.headline)
                }
                Text("Smart \(entry.config.windowMinutes)m · Score \(entry.sleepScore)%")
                    .font(.caption2)
                Text("Deep \(entry.deepMinutes)m · REM \(entry.remMinutes)m · \(entry.noiseFloorDB) dBA")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("🌙 Torpor \(entry.config.wakeTime) (±\(entry.config.windowMinutes)m) · \(entry.sleepScore)%")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(crimson)
                Text("TORPOR")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(entry.isArmed ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
            }

            Spacer(minLength: 0)

            Text(entry.config.wakeTime)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(bone)
            Text("Smart Phase · -\(entry.config.windowMinutes)m window")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer(minLength: 2)

            HStack(spacing: 6) {
                Button(intent: ToggleTorporArmIntent()) {
                    HStack(spacing: 4) {
                        Image(systemName: entry.isArmed ? "waveform.badge.mic" : "mic.slash")
                            .font(.system(size: 10, weight: .bold))
                        Text(entry.isArmed ? "Guard Armed (\(entry.noiseFloorDB)dB)" : "Guard Paused")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .background(entry.isArmed ? crimson.opacity(0.85) : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            smallView.frame(maxWidth: 145)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LAST TORPOR SESSION")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(entry.sleepScore)%")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.green)
                }

                stageBar(label: "Deep Torpor", mins: entry.deepMinutes, total: 440, color: crimson)
                stageBar(label: "REM Dream", mins: entry.remMinutes, total: 440, color: violet)
                stageBar(label: "Light Sleep", mins: entry.lightMinutes, total: 440, color: .cyan)

                HStack {
                    Label(entry.config.soundscape, systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(bone.opacity(0.85))
                    Spacer()
                    Text("\(entry.eventsCaught) clips")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(crimson)
                }
            }
        }
    }

    private func stageBar(label: String, mins: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text("\(mins / 60)h \(mins % 60)m").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(Double(mins) / Double(total), 1.0)))
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
                    LinearGradient(
                        colors: [Color(red: 0.03, green: 0.01, blue: 0.02), Color(red: 0.12, green: 0.03, blue: 0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Torpor Sleep & Alarm")
        .description("Smart REM/Light phase alarm, acoustic snore guard toggle, and sleep stage summary.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct TorporWidgetBundle: WidgetBundle {
    var body: some Widget {
        TorporWidget()
    }
}
