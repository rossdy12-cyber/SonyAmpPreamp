import WidgetKit
import SwiftUI
import AppIntents

struct CarbPrepConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "CarbPrep T1D Bolus HUD"
    static var description = IntentDescription("Instant T1D meal bolus calculator using your ICR, ISF, and live Nightscout glucose.")

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

    private let crimson = Color(red: 0.90, green: 0.20, blue: 0.32)
    private let cyan = Color(red: 0.38, green: 0.82, blue: 0.96)

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("30g").font(.caption2)
                    Text(String(format: "%.1fU", entry.bolusFor(carbs: 30))).font(.system(size: 12, weight: .black, design: .rounded))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "CarbPrep · BG %.1f mmol/L", entry.currentMmol)).font(.headline)
                Text(String(format: "20g: %.1fU · 40g: %.1fU · 60g: %.1fU", entry.bolusFor(carbs: 20), entry.bolusFor(carbs: 40), entry.bolusFor(carbs: 60)))
                    .font(.caption)
                Text(String(format: "ICR 1:%.0fg · IOB %.1fU", entry.config.icrGramsPerUnit, entry.iobUnits))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text(String(format: "🍽 30g=%.1fU · 60g=%.1fU (BG %.1f)", entry.bolusFor(carbs: 30), entry.bolusFor(carbs: 60), entry.currentMmol))
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "fork.knife").foregroundStyle(crimson)
                Text("CARBPREP").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", entry.currentMmol))
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.green)
            }
            Text(String(format: "ICR 1:%.0fg · IOB %.1fU", entry.config.icrGramsPerUnit, entry.iobUnits))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(cyan)

            Spacer(minLength: 2)

            VStack(spacing: 4) {
                carbRow(grams: 20)
                carbRow(grams: 40)
                carbRow(grams: 60)
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fork.knife").foregroundStyle(crimson)
                Text("CARBPREP T1D MEAL BOLUS CALCULATOR")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "BG %.1f mmol/L · IOB %.2fU", entry.currentMmol, entry.iobUnits))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            }

            HStack(spacing: 8) {
                carbCard(grams: 15)
                carbCard(grams: 30)
                carbCard(grams: 45)
                carbCard(grams: 60)
                carbCard(grams: 80)
            }

            Text(String(format: "Ratio 1U : %.0fg carbs · Correction 1U : %.1f mmol/L (Target %.1f)", entry.config.icrGramsPerUnit, entry.config.isfMmolPerUnit, entry.config.targetMmol))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func carbRow(grams: Int) -> some View {
        HStack {
            Text("\(grams)g Carbs")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text(String(format: "%.1f U", entry.bolusFor(carbs: Double(grams))))
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(cyan)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private func carbCard(grams: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(grams)g")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(String(format: "%.1fU", entry.bolusFor(carbs: Double(grams))))
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(cyan)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CarbPrepWidget: Widget {
    let kind = "CarbPrepWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CarbPrepConfigIntent.self, provider: CarbPrepProvider()) { entry in
            CarbPrepWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.03, green: 0.015, blue: 0.02), Color(red: 0.11, green: 0.03, blue: 0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("CarbPrep T1D Bolus")
        .description("Instant meal bolus guide factoring in your ICR, ISF, live glucose, and active IOB.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct CarbPrepWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarbPrepWidget()
    }
}
