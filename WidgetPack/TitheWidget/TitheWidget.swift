import WidgetKit
import SwiftUI
import AppIntents

struct TitheConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Tithe Offerings & Payday"
    static var description = IntentDescription("Live PC game deals & payday countdown.")

    @Parameter(title: "Payday Day of Month", default: 28)
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
        if curDay <= clamped {
            return clamped - curDay
        }
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
                let t = (d["title"] as? String) ?? "Featured Offer"
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
                DealItem(id: "1", title: "Baldur's Gate 3", salePrice: "£39.99", savingsPct: 20),
                DealItem(id: "2", title: "Cyberpunk 2077", salePrice: "£24.99", savingsPct: 50),
                DealItem(id: "3", title: "Elden Ring", salePrice: "£29.99", savingsPct: 40)
            ]
        )
    }
}

struct TitheWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TitheEntry

    private let crimson = Color(red: 0.88, green: 0.16, blue: 0.28)
    private let bone = Color(red: 0.94, green: 0.90, blue: 0.86)

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.daysToPayday)d").font(.system(size: 14, weight: .black, design: .rounded))
                    Text("PAYDAY").font(.system(size: 7, weight: .bold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Tithe · Payday in \(entry.daysToPayday)d").font(.headline)
                if let first = entry.deals.first {
                    Text("\(first.title)").font(.caption).lineLimit(1)
                    Text("\(first.salePrice) (-\(first.savingsPct)%)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Text("🩸 Tithe · Payday in \(entry.daysToPayday)d")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "seal.fill").foregroundStyle(crimson)
                Text("TITHE").font(.system(size: 10, weight: .bold, design: .serif)).foregroundStyle(.secondary)
                Spacer()
            }
            Spacer(minLength: 0)
            Text("\(entry.daysToPayday)d")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(bone)
            Text("UNTIL PAYDAY")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(crimson)
            if let first = entry.deals.first {
                Divider().background(crimson.opacity(0.4))
                Text(first.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(first.salePrice) · -\(first.savingsPct)%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TITHE")
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.daysToPayday)")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(bone)
                Text("DAYS TO PAYDAY")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(crimson)
                Spacer()
            }
            .frame(maxWidth: 105, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("TOP OFFERINGS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                ForEach(entry.deals) { d in
                    HStack {
                        Text(d.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(bone)
                            .lineLimit(1)
                        Spacer()
                        Text(d.salePrice)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("-\(d.savingsPct)%")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                    }
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
                    LinearGradient(
                        colors: [Color(red: 0.03, green: 0.01, blue: 0.015), Color(red: 0.12, green: 0.025, blue: 0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Tithe Offerings & Payday")
        .description("Payday countdown and live PC game deal offerings.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct TitheWidgetBundle: WidgetBundle {
    var body: some Widget {
        TitheWidget()
    }
}
