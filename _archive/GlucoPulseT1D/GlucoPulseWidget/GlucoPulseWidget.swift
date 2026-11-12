import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration (long-press the widget -> Edit Widget)

enum GlucoseUnitChoice: String, AppEnum {
    case mmolL
    case mgdL

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Glucose unit"
    static var caseDisplayRepresentations: [GlucoseUnitChoice: DisplayRepresentation] = [
        .mmolL: "mmol/L",
        .mgdL: "mg/dL"
    ]
}

struct GlucoseConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Glucose"
    static var description = IntentDescription("Latest glucose reading from your Nightscout server.")

    @Parameter(title: "Nightscout address", default: "http://100.85.127.42:1337")
    var nightscoutURL: String

    @Parameter(title: "Unit", default: .mmolL)
    var unit: GlucoseUnitChoice

    @Parameter(title: "Low below (mmol/L)", default: 3.9)
    var lowMmol: Double

    @Parameter(title: "High above (mmol/L)", default: 10.0)
    var highMmol: Double

    init() {}
}

// MARK: - Data

struct Reading: Identifiable {
    let id: Double          // milliseconds since 1970, unique per reading
    let date: Date
    let mgdl: Double
    let direction: String
}

enum GlucoseFetchError: Error {
    case badAddress
    case badResponse
}

enum NightscoutClient {
    /// Most recent readings, oldest first. Nightscout returns mg/dL in "sgv".
    static func recent(base: String, count: Int = 40) async throws -> [Reading] {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { throw GlucoseFetchError.badAddress }
        if !b.contains("://") { b = "http://" + b }
        while b.hasSuffix("/") { b.removeLast() }
        guard let url = URL(string: "\(b)/api/v1/entries.json?count=\(count)") else {
            throw GlucoseFetchError.badAddress
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("GlucoPulseWidget/1.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GlucoseFetchError.badResponse
        }
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw GlucoseFetchError.badResponse
        }
        var out: [Reading] = []
        for e in arr {
            guard let sgv = (e["sgv"] as? NSNumber)?.doubleValue,
                  let ms = (e["date"] as? NSNumber)?.doubleValue,
                  sgv > 0 else { continue }
            let dir = (e["direction"] as? String) ?? ""
            out.append(Reading(id: ms, date: Date(timeIntervalSince1970: ms / 1000.0), mgdl: sgv, direction: dir))
        }
        return out.sorted { $0.date < $1.date }
    }
}

struct GlucoseEntry: TimelineEntry {
    let date: Date
    let configuration: GlucoseConfigIntent
    let readings: [Reading]
    let errorText: String?

    var latest: Reading? { readings.last }

    var isStale: Bool {
        guard let l = latest else { return true }
        return date.timeIntervalSince(l.date) > 15 * 60
    }

    var agoText: String {
        guard let l = latest else { return "" }
        let m = max(0, Int(date.timeIntervalSince(l.date) / 60))
        return m < 1 ? "now" : "\(m)m ago"
    }

    var unitText: String { configuration.unit == .mmolL ? "mmol/L" : "mg/dL" }

    var lowMgdl: Double { configuration.lowMmol * 18.0182 }
    var highMgdl: Double { configuration.highMmol * 18.0182 }

    func valueText(_ mgdl: Double) -> String {
        if configuration.unit == .mmolL {
            return String(format: "%.1f", mgdl / 18.0182)
        }
        return String(format: "%.0f", mgdl)
    }

    func arrow(_ direction: String) -> String {
        switch direction {
        case "DoubleUp": return "⇈"
        case "SingleUp": return "↑"
        case "FortyFiveUp": return "↗"
        case "Flat": return "→"
        case "FortyFiveDown": return "↘"
        case "SingleDown": return "↓"
        case "DoubleDown": return "⇊"
        default: return ""
        }
    }

    func color(for r: Reading) -> Color {
        if isStale { return .gray }
        let mmol = r.mgdl / 18.0182
        if mmol < 3.0 || mmol > 13.9 { return .red }
        if r.mgdl < lowMgdl { return Color(red: 1.0, green: 0.35, blue: 0.3) }
        if r.mgdl > highMgdl { return .orange }
        return Color(red: 0.25, green: 0.85, blue: 0.5)
    }

    static func sample(_ config: GlucoseConfigIntent) -> GlucoseEntry {
        let now = Date()
        var rs: [Reading] = []
        for i in 0..<36 {
            let t = now.addingTimeInterval(Double(i - 35) * 300)
            let v = 126.0 + 40.0 * sin(Double(i) / 5.0)
            rs.append(Reading(id: t.timeIntervalSince1970 * 1000, date: t, mgdl: v, direction: "Flat"))
        }
        return GlucoseEntry(date: now, configuration: config, readings: rs, errorText: nil)
    }
}

// MARK: - Provider

struct GlucoseProvider: AppIntentTimelineProvider {
    typealias Intent = GlucoseConfigIntent
    typealias Entry = GlucoseEntry

    func placeholder(in context: Context) -> GlucoseEntry {
        GlucoseEntry.sample(GlucoseConfigIntent())
    }

    func snapshot(for configuration: GlucoseConfigIntent, in context: Context) async -> GlucoseEntry {
        if context.isPreview { return GlucoseEntry.sample(configuration) }
        return await load(configuration)
    }

    func timeline(for configuration: GlucoseConfigIntent, in context: Context) async -> Timeline<GlucoseEntry> {
        let entry = await load(configuration)
        let next = Date().addingTimeInterval(5 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func load(_ config: GlucoseConfigIntent) async -> GlucoseEntry {
        let now = Date()
        do {
            let rs = try await NightscoutClient.recent(base: config.nightscoutURL)
            return GlucoseEntry(date: now, configuration: config, readings: rs,
                                errorText: rs.isEmpty ? "No readings yet" : nil)
        } catch {
            return GlucoseEntry(date: now, configuration: config, readings: [],
                                errorText: "Can't reach Nightscout. Is Tailscale connected?")
        }
    }
}

// MARK: - Views

struct Sparkline: View {
    let readings: [Reading]
    let lowMgdl: Double
    let highMgdl: Double
    let lineColor: Color

    private var lo: Double { min(readings.map { $0.mgdl }.min() ?? lowMgdl, lowMgdl) - 10 }
    private var hi: Double { max(readings.map { $0.mgdl }.max() ?? highMgdl, highMgdl) + 10 }

    private func yFor(_ mgdl: Double, height: CGFloat) -> CGFloat {
        let span = max(hi - lo, 1)
        return height - CGFloat((mgdl - lo) / span) * height
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard let first = readings.first, let last = readings.last else { return [] }
        let t0 = first.date.timeIntervalSince1970
        let tspan = max(last.date.timeIntervalSince1970 - t0, 1)
        return readings.map { r in
            let x = CGFloat((r.date.timeIntervalSince1970 - t0) / tspan) * size.width
            return CGPoint(x: x, y: yFor(r.mgdl, height: size.height))
        }
    }

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            let bandTop = yFor(highMgdl, height: geo.size.height)
            let bandBottom = yFor(lowMgdl, height: geo.size.height)
            ZStack {
                Rectangle()
                    .fill(Color.green.opacity(0.16))
                    .frame(width: geo.size.width, height: max(bandBottom - bandTop, 1))
                    .position(x: geo.size.width / 2, y: (bandTop + bandBottom) / 2)
                Path { p in
                    for (i, q) in pts.enumerated() {
                        if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(lineColor).frame(width: 7, height: 7).position(last)
                }
            }
        }
    }
}

struct GlucoseWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: GlucoseEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            inlineView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var noData: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No data").font(.headline)
            Text(entry.errorText ?? "").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("GLUCOSE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if entry.isStale && entry.latest != nil {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.yellow)
                }
            }
            Spacer(minLength: 0)
            if let l = entry.latest {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.valueText(l.mgdl))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(entry.arrow(l.direction)).font(.title2.weight(.semibold))
                }
                .foregroundStyle(entry.color(for: l))
                Text("\(entry.unitText) · \(entry.agoText)").font(.caption2).foregroundStyle(.secondary)
            } else {
                noData
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            smallView.frame(maxWidth: 130, alignment: .leading)
            if let l = entry.latest {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LAST 3 HOURS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Sparkline(readings: entry.readings, lowMgdl: entry.lowMgdl,
                              highMgdl: entry.highMgdl, lineColor: entry.color(for: l))
                }
            }
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let l = entry.latest {
                VStack(spacing: 0) {
                    Text(entry.valueText(l.mgdl)).font(.system(.title3, design: .rounded).weight(.bold))
                    Text(entry.arrow(l.direction)).font(.caption)
                }
            } else {
                Text("--")
            }
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let l = entry.latest {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.valueText(l.mgdl)).font(.system(.title2, design: .rounded).weight(.bold))
                    Text(entry.arrow(l.direction)).font(.headline)
                    Text("\(entry.unitText) · \(entry.agoText)").font(.caption2)
                }
                Sparkline(readings: entry.readings, lowMgdl: entry.lowMgdl,
                          highMgdl: entry.highMgdl, lineColor: .white)
                    .frame(height: 22)
            } else {
                Text("Glucose: no data")
            }
        }
    }

    private var inlineView: some View {
        if let l = entry.latest {
            return Text("\(entry.valueText(l.mgdl)) \(entry.arrow(l.direction)) \(entry.agoText)")
        }
        return Text("Glucose: no data")
    }
}

// MARK: - Widget

struct GlucoPulseGlucoseWidget: Widget {
    let kind = "GlucoPulseGlucoseWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: GlucoseConfigIntent.self, provider: GlucoseProvider()) { entry in
            GlucoseWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.020, green: 0.008, blue: 0.012),
                                            Color(red: 0.110, green: 0.039, blue: 0.059)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Glucose")
        .description("Latest glucose from your Nightscout server, with trend and a 3-hour graph.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct GlucoPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        GlucoPulseGlucoseWidget()
    }
}
