import WidgetKit
import SwiftUI

struct VespersEntry: TimelineEntry {
    let date: Date
    let canonicalHour: String
    let latinMotto: String
    let nextHourText: String
}

struct VespersProvider: TimelineProvider {
    func placeholder(in context: Context) -> VespersEntry { makeEntry(for: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (VespersEntry) -> Void) {
        completion(makeEntry(for: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VespersEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(for: now)
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
    }

    private func makeEntry(for date: Date) -> VespersEntry {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 0..<5:
            return VespersEntry(date: date, canonicalHour: "MATINS", latinMotto: "In nocte vigilate", nextHourText: "Lauds at 05:00")
        case 5..<8:
            return VespersEntry(date: date, canonicalHour: "LAUDS", latinMotto: "Aurora lucis rutilat", nextHourText: "Terce at 09:00")
        case 8..<12:
            return VespersEntry(date: date, canonicalHour: "TERCE", latinMotto: "Nunc Sancte nobis Spiritus", nextHourText: "Sext at 12:00")
        case 12..<15:
            return VespersEntry(date: date, canonicalHour: "SEXT", latinMotto: "Rector potens, verax Deus", nextHourText: "None at 15:00")
        case 15..<18:
            return VespersEntry(date: date, canonicalHour: "NONE", latinMotto: "Rerum Deus tenax vigor", nextHourText: "Vespers at 18:00")
        case 18..<21:
            return VespersEntry(date: date, canonicalHour: "VESPERS", latinMotto: "Lucis Creator optime", nextHourText: "Compline at 21:00")
        default:
            return VespersEntry(date: date, canonicalHour: "COMPLINE", latinMotto: "Te lucis ante terminum", nextHourText: "Matins at 00:00")
        }
    }
}

struct VespersWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: VespersEntry

    private let crimson = Color(red: 0.86, green: 0.16, blue: 0.28)
    private let bone = Color(red: 0.94, green: 0.90, blue: 0.86)

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "bell.fill").font(.caption2)
                    Text(entry.canonicalHour.prefix(4)).font(.system(size: 11, weight: .bold, design: .serif))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Vespers · \(entry.canonicalHour)").font(.headline)
                Text(entry.latinMotto).font(.caption).italic()
                Text(entry.date, format: .dateTime.weekday(.wide).day().month()).font(.caption2).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("🕯 \(entry.canonicalHour) · \(entry.latinMotto)")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(crimson)
                Text("VESPERS").font(.system(size: 10, weight: .bold, design: .serif)).foregroundStyle(.secondary)
                Spacer()
            }
            Spacer(minLength: 0)
            Text(entry.canonicalHour)
                .font(.system(size: 22, weight: .black, design: .serif))
                .foregroundStyle(bone)
            Text(entry.latinMotto)
                .font(.system(size: 11, weight: .medium, design: .serif))
                .italic()
                .foregroundStyle(crimson)
            Spacer(minLength: 0)
            Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "flame.fill").foregroundStyle(crimson)
                    Text("VESPERS SANCTUM")
                        .font(.system(size: 10, weight: .bold, design: .serif))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.canonicalHour)
                    .font(.system(size: 28, weight: .black, design: .serif))
                    .foregroundStyle(bone)
                Text(entry.latinMotto)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(crimson)
                Spacer()
                Text(entry.nextHourText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.date, format: .dateTime.day())
                    .font(.system(size: 42, weight: .black, design: .serif))
                    .foregroundStyle(bone)
                Text(entry.date, format: .dateTime.weekday(.wide))
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(crimson)
                Text(entry.date, format: .dateTime.month(.wide))
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct VespersWidget: Widget {
    let kind = "VespersWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VespersProvider()) { entry in
            VespersWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.03, green: 0.01, blue: 0.015), Color(red: 0.12, green: 0.025, blue: 0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Vespers Canonical Calendar")
        .description("Gothic canonical hour, Latin motto, and calendar date.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct VespersWidgetBundle: WidgetBundle {
    var body: some Widget {
        VespersWidget()
    }
}
