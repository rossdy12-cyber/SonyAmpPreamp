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
        completion(Timeline(entries: [makeEntry(for: now)], policy: .after(now.addingTimeInterval(30 * 60))))
    }

    private func makeEntry(for date: Date) -> VespersEntry {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 0..<5:
            return VespersEntry(date: date, canonicalHour: "MATINS", latinMotto: "In nocte vigilate", nextHourText: "Lauds · V Hora")
        case 5..<8:
            return VespersEntry(date: date, canonicalHour: "LAUDS", latinMotto: "Aurora lucis rutilat", nextHourText: "Terce · IX Hora")
        case 8..<12:
            return VespersEntry(date: date, canonicalHour: "TERCE", latinMotto: "Nunc Sancte nobis Spiritus", nextHourText: "Sext · XII Hora")
        case 12..<15:
            return VespersEntry(date: date, canonicalHour: "SEXT", latinMotto: "Rector potens, verax Deus", nextHourText: "None · XV Hora")
        case 15..<18:
            return VespersEntry(date: date, canonicalHour: "NONE", latinMotto: "Rerum Deus tenax vigor", nextHourText: "Vespers · XVIII Hora")
        case 18..<21:
            return VespersEntry(date: date, canonicalHour: "VESPERS", latinMotto: "Lucis Creator optime", nextHourText: "Compline · XXI Hora")
        default:
            return VespersEntry(date: date, canonicalHour: "COMPLINE", latinMotto: "Te lucis ante terminum", nextHourText: "Matins · Media Nocte")
        }
    }
}

struct VespersWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: VespersEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("✠").font(.caption2)
                    Text(entry.canonicalHour.prefix(4)).font(GothicTheme.serif(11, weight: .bold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("✠ Vespers · \(entry.canonicalHour)").font(GothicTheme.serif(13, weight: .bold))
                Text(entry.latinMotto).font(GothicTheme.serif(10)).italic()
                Text(entry.date, format: .dateTime.weekday(.wide).day().month()).font(GothicTheme.serif(9)).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("✠ \(entry.canonicalHour) · \(entry.latinMotto)")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            GothicHeader(title: "Vespers")
            Spacer(minLength: 0)
            Text(entry.canonicalHour)
                .font(GothicTheme.display(22))
                .foregroundStyle(GothicTheme.bone)
            Text(entry.latinMotto)
                .font(GothicTheme.serif(10.5, weight: .medium))
                .italic()
                .foregroundStyle(GothicTheme.bloodHi)
            Spacer(minLength: 0)
            GothicOrnamentRule()
            Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(GothicTheme.serif(10.5, weight: .bold))
                .foregroundStyle(GothicTheme.bone)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                GothicHeader(title: "Vespers · Liturgia Horarum")
                Spacer()
                Text(entry.canonicalHour)
                    .font(GothicTheme.display(28))
                    .foregroundStyle(GothicTheme.bone)
                Text(entry.latinMotto)
                    .font(GothicTheme.serif(12.5, weight: .medium))
                    .italic()
                    .foregroundStyle(GothicTheme.bloodHi)
                Spacer()
                Text(entry.nextHourText)
                    .font(GothicTheme.serif(10, weight: .bold))
                    .foregroundStyle(GothicTheme.ash)
            }
            Spacer()
            VStack(alignment: .center, spacing: 2) {
                Text(entry.date, format: .dateTime.day())
                    .font(GothicTheme.display(36))
                    .foregroundStyle(GothicTheme.bone)
                Text(entry.date, format: .dateTime.weekday(.wide))
                    .font(GothicTheme.serif(11, weight: .bold))
                    .foregroundStyle(GothicTheme.bloodHi)
                Text(entry.date, format: .dateTime.month(.wide))
                    .font(GothicTheme.serif(10))
                    .foregroundStyle(GothicTheme.ash)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .gothicPanel(active: true, corner: 8)
        }
    }
}

struct VespersWidget: Widget {
    let kind = "VespersWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VespersProvider()) { entry in
            VespersWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GothicCathedralBackground()
                }
        }
        .configurationDisplayName("Vespers Canonical Calendar")
        .description("Gothic Vampire canonical hour, Latin motto, and sanctum date.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct VespersWidgetBundle: WidgetBundle {
    var body: some Widget {
        VespersWidget()
    }
}
