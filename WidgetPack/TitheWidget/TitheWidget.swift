import WidgetKit
import SwiftUI
import AppIntents

struct TitheConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Tithe Offerings & Tribute"
    static var description = IntentDescription("Gothic Vampire PC game offerings & tribute countdown.")

    @Parameter(title: "Tribute Day of Month", default: 28)
    var paydayDay: Int

    init() {}
}

struct DealItem: Identifiable {
    let id: String
    let title: String
    let salePrice: String
    let savingsPct: Int
}

struct TitheEntry: TimelineEntry {
    let date: Date
    let daysToPayday: Int
    let deals: [DealItem]
}

struct TitheProvider: AppIntentTimelineProvider {
    typealias Intent = TitheConfigIntent
    typealias Entry = TitheEntry

    func placeholder(in context: Context) -> TitheEntry { sample(28) }
    func snapshot(for configuration: TitheConfigIntent, in context: Context) async -> TitheEntry {
        if context.isPreview { return sample(configuration.paydayDay) }
        return await load(configuration)
    }
    func timeline(for configuration: TitheConfigIntent, in context: Context) async -> Timeline<TitheEntry> {
        let entry = await load(configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60)))
    }

    private func calcDaysToPayday(_ targetDay: Int) -> Int {
        let cal = Calendar.current
        let now = Date()
        let curDay = cal.component(.day, from: now)
        let clamped = max(1, min(28, targetDay))
        if curDay <= clamped { return clamped - curDay }
        if let nextMonth = cal.date(byAdding: .month, value: 1, to: now),
           let targetDate = cal.date(from: DateComponents(year: cal.component(.year, from: nextMonth), month: cal.component(.month, from: nextMonth), day: clamped)) {
            return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: now), to: targetDate).day ?? 14)
        }
        return 14
    }

    private func load(_ cfg: TitheConfigIntent) async -> TitheEntry {
        let days = calcDaysToPayday(cfg.paydayDay)
        if let url = URL(string: "https://www.cheapshark.com/api/1.0/deals?pageSize=3&sortBy=Deal%20Rating"),
           let (data, resp) = try? await URLSession.shared.data(from: url),
           let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !arr.isEmpty {
            let parsed: [DealItem] = arr.prefix(3).enumerated().map { idx, d in
                let t = (d["title"] as? String) ?? "Featured Offering"
                let sp = (d["salePrice"] as? String) ?? "4.99"
                let savStr = (d["savings"] as? String) ?? "75"
                let sav = Int((Double(savStr) ?? 75.0).rounded())
                return DealItem(id: "\(idx)", title: t, salePrice: "£\(sp)", savingsPct: sav)
            }
            return TitheEntry(date: Date(), daysToPayday: days, deals: parsed)
        }
        return sample(cfg.paydayDay)
    }

    private func sample(_ paydayDay: Int) -> TitheEntry {
        TitheEntry(
            date: Date(),
            daysToPayday: calcDaysToPayday(paydayDay),
            deals: [
                DealItem(id: "1", title: "Baldur's Gate III", salePrice: "£39.99", savingsPct: 20),
                DealItem(id: "2", title: "Castlevania: Nocturne", salePrice: "£14.99", savingsPct: 60),
                DealItem(id: "3", title: "Elden Ring", salePrice: "£29.99", savingsPct: 40)
            ]
        )
    }
}

struct TitheWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TitheEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.daysToPayday)d").font(GothicTheme.serif(13, weight: .bold))
                    Text("TITHE").font(GothicTheme.serif(7, weight: .bold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("✠ Tithe · \(entry.daysToPayday)d to Tribute").font(GothicTheme.serif(13, weight: .bold))
                if let first = entry.deals.first {
                    Text(first.title).font(GothicTheme.serif(10)).lineLimit(1)
                    Text("\(first.salePrice) (-\(first.savingsPct)%)").font(GothicTheme.serif(9)).foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Text("✠ Tithe · Tribute in \(entry.daysToPayday)d")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            GothicHeader(title: "Tithe", rightText: "Tribute")
            Spacer(minLength: 0)
            Text("\(entry.daysToPayday)d")
                .font(GothicTheme.display(36))
                .foregroundStyle(GothicTheme.bone)
            Text("UNTIL TRIBUTE")
                .font(GothicTheme.serif(8.5, weight: .bold))
                .tracking(1)
                .foregroundStyle(GothicTheme.bloodHi)
            if let first = entry.deals.first {
                GothicOrnamentRule()
                Text(first.title)
                    .font(GothicTheme.serif(10.5, weight: .bold))
                    .foregroundStyle(GothicTheme.bone)
                    .lineLimit(1)
                Text("\(first.salePrice) · -\(first.savingsPct)%")
                    .font(GothicTheme.serif(9.5, weight: .semibold))
                    .foregroundStyle(GothicTheme.bloodHi)
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                GothicHeader(title: "Tithe")
                Spacer()
                Text("\(entry.daysToPayday)")
                    .font(GothicTheme.display(40))
                    .foregroundStyle(GothicTheme.bone)
                Text("DAYS TO TRIBUTE")
                    .font(GothicTheme.serif(8.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(GothicTheme.bloodHi)
                Spacer()
            }
            .frame(maxWidth: 108, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                GothicHeader(title: "Blood Offerings")
                ForEach(entry.deals) { d in
                    HStack {
                        Text(d.title)
                            .font(GothicTheme.serif(11, weight: .bold))
                            .foregroundStyle(GothicTheme.bone)
                            .lineLimit(1)
                        Spacer()
                        Text(d.salePrice)
                            .font(GothicTheme.serif(11, weight: .bold))
                            .foregroundStyle(GothicTheme.bone)
                        Text("-\(d.savingsPct)%")
                            .font(GothicTheme.serif(9.5, weight: .bold))
                            .foregroundStyle(GothicTheme.bloodHi)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .gothicPanel(active: false, corner: 5)
                }
            }
        }
    }
}

struct TitheWidget: Widget {
    let kind = "TitheWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TitheConfigIntent.self, provider: TitheProvider()) { entry in
            TitheWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GothicCathedralBackground()
                }
        }
        .configurationDisplayName("Tithe Offerings & Tribute")
        .description("Gothic Vampire payday countdown and live game deal offerings.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct TitheWidgetBundle: WidgetBundle {
    var body: some Widget {
        TitheWidget()
    }
}
