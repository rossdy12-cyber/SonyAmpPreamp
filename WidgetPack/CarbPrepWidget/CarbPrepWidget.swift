import WidgetKit
import SwiftUI
import AppIntents

struct CarbPrepConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "CarbPrep Elixir Calculus"
    static var description = IntentDescription("Gothic Vampire T1D meal bolus calculator using live Nightscout glucose & IOB.")

    @Parameter(title: "Carb Ratio (1U per Xg)", default: 10.0)
    var icrGramsPerUnit: Double

    @Parameter(title: "Correction Factor (1U drops mmol/L)", default: 2.5)
    var isfMmolPerUnit: Double

    @Parameter(title: "Target Glucose (mmol/L)", default: 5.5)
    var targetMmol: Double

    init() {}
}

struct CarbPrepEntry: TimelineEntry {
    let date: Date
    let config: CarbPrepConfigIntent
    let currentMmol: Double
    let iobUnits: Double

    func bolusFor(carbs: Double) -> Double {
        let icr = max(1.0, config.icrGramsPerUnit)
        let isf = max(0.5, config.isfMmolPerUnit)
        let mealUnits = carbs / icr
        let corrUnits = max(0.0, (currentMmol - config.targetMmol) / isf - iobUnits)
        return max(0.0, mealUnits + corrUnits)
    }
}

struct CarbPrepProvider: AppIntentTimelineProvider {
    typealias Intent = CarbPrepConfigIntent
    typealias Entry = CarbPrepEntry

    func placeholder(in context: Context) -> CarbPrepEntry {
        CarbPrepEntry(date: Date(), config: CarbPrepConfigIntent(), currentMmol: 6.4, iobUnits: 0.8)
    }
    func snapshot(for configuration: CarbPrepConfigIntent, in context: Context) async -> CarbPrepEntry {
        await load(configuration)
    }
    func timeline(for configuration: CarbPrepConfigIntent, in context: Context) async -> Timeline<CarbPrepEntry> {
        let entry = await load(configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(5 * 60)))
    }

    private func load(_ cfg: CarbPrepConfigIntent) async -> CarbPrepEntry {
        var mmol = 6.4
        var iob = 0.0
        if let u = URL(string: "http://100.85.127.42:1337/api/v1/entries.json?count=1"),
           let (d, _) = try? await URLSession.shared.data(from: u),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]],
           let sgv = (arr.first?["sgv"] as? NSNumber)?.doubleValue, sgv > 0 {
            mmol = sgv / 18.0182
        }
        if let u2 = URL(string: "http://100.85.127.42:1338/api/ble-devicestatus"),
           let (d2, _) = try? await URLSession.shared.data(from: u2),
           let json = try? JSONSerialization.jsonObject(with: d2) as? [String: Any],
           let bIob = (json["iobUnits"] as? NSNumber)?.doubleValue {
            iob = bIob
        }
        return CarbPrepEntry(date: Date(), config: cfg, currentMmol: mmol, iobUnits: iob)
    }
}

struct CarbPrepWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CarbPrepEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("30g").font(GothicTheme.serif(9))
                    Text(String(format: "%.1fU", entry.bolusFor(carbs: 30))).font(GothicTheme.serif(12, weight: .bold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "✠ CarbPrep · BG %.1f", entry.currentMmol)).font(GothicTheme.serif(13, weight: .bold))
                Text(String(format: "20g: %.1fU · 40g: %.1fU · 60g: %.1fU", entry.bolusFor(carbs: 20), entry.bolusFor(carbs: 40), entry.bolusFor(carbs: 60)))
                    .font(GothicTheme.serif(10))
                Text(String(format: "ICR 1:%.0fg · IOB %.1fU", entry.config.icrGramsPerUnit, entry.iobUnits))
                    .font(GothicTheme.serif(9)).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text(String(format: "✠ 30g=%.1fU · 60g=%.1fU (BG %.1f)", entry.bolusFor(carbs: 30), entry.bolusFor(carbs: 60), entry.currentMmol))
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            GothicHeader(title: "CarbPrep", rightText: String(format: "%.1f", entry.currentMmol))
            Text(String(format: "ICR 1:%.0fg · IOB %.1fU", entry.config.icrGramsPerUnit, entry.iobUnits))
                .font(GothicTheme.serif(9.5, weight: .semibold))
                .italic()
                .foregroundStyle(GothicTheme.bloodHi)
            Spacer(minLength: 0)
            VStack(spacing: 3.5) {
                carbRow(grams: 20)
                carbRow(grams: 40)
                carbRow(grams: 60)
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 7) {
            GothicHeader(title: "CarbPrep · Sanguine Bolus Rite", rightText: String(format: "BG %.1f · IOB %.2fU", entry.currentMmol, entry.iobUnits))
            HStack(spacing: 7) {
                carbCard(grams: 15)
                carbCard(grams: 30)
                carbCard(grams: 45)
                carbCard(grams: 60)
                carbCard(grams: 80)
            }
            GothicOrnamentRule()
            Text(String(format: "Ratio 1U : %.0fg · Correction 1U : %.1f mmol/L (Target %.1f)", entry.config.icrGramsPerUnit, entry.config.isfMmolPerUnit, entry.config.targetMmol))
                .font(GothicTheme.serif(9.5))
                .italic()
                .foregroundStyle(GothicTheme.ash)
                .lineLimit(1)
        }
    }

    private func carbRow(grams: Int) -> some View {
        HStack {
            Text("\(grams)g Offering")
                .font(GothicTheme.serif(10, weight: .semibold))
                .foregroundStyle(GothicTheme.bone)
            Spacer()
            Text(String(format: "%.1f U", entry.bolusFor(carbs: Double(grams))))
                .font(GothicTheme.serif(11, weight: .bold))
                .foregroundStyle(GothicTheme.bloodHi)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .gothicPanel(active: false, corner: 5)
    }

    private func carbCard(grams: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(grams)g")
                .font(GothicTheme.serif(10.5, weight: .bold))
                .foregroundStyle(GothicTheme.ash)
            Text(String(format: "%.1fU", entry.bolusFor(carbs: Double(grams))))
                .font(GothicTheme.display(16))
                .foregroundStyle(GothicTheme.bone)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .gothicPanel(active: true, corner: 6)
    }
}

struct CarbPrepWidget: Widget {
    let kind = "CarbPrepWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CarbPrepConfigIntent.self, provider: CarbPrepProvider()) { entry in
            CarbPrepWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GothicCathedralBackground()
                }
        }
        .configurationDisplayName("CarbPrep Sanguine Bolus")
        .description("Gothic Vampire T1D meal bolus calculator factoring in ICR, ISF, live BG & IOB.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct CarbPrepWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarbPrepWidget()
    }
}
