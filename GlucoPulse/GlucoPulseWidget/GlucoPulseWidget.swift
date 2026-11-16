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
    static var title: LocalizedStringResource = "GlucoPulse T1D"
    static var description = IntentDescription("Live Dexcom G7 glucose, trend, 3h/6h graph, and Tandem t:slim X2 IOB telemetry.")

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

// MARK: - Data Models

struct Reading: Identifiable, Codable {
    let id: Double          // milliseconds since 1970
    let date: Date
    let mgdl: Double
    let direction: String
}

struct PumpSnapshot: Codable {
    var iobUnits: Double = 0
    var activeBasalRate: Double = 0
    var reservoirUnits: Double = 0
    var batteryPercent: Int = 0
    var controlIQMode: String = ""
    var lastBolusUnits: Double = 0
    var hasTelemetry: Bool {
        iobUnits > 0 || activeBasalRate > 0 || reservoirUnits > 0 || batteryPercent > 0
    }
}

enum GlucoseFetchError: Error {
    case badAddress
    case badResponse
}

enum NightscoutClient {
    private static let cachedReadingsKey = "glucopulse.widget.cachedReadings"
    private static let cachedPumpKey = "glucopulse.widget.cachedPump"

    static func saveCache(readings: [Reading], pump: PumpSnapshot) {
        if !readings.isEmpty, let data = try? JSONEncoder().encode(readings) {
            UserDefaults.standard.set(data, forKey: cachedReadingsKey)
        }
        if pump.hasTelemetry, let pdata = try? JSONEncoder().encode(pump) {
            UserDefaults.standard.set(pdata, forKey: cachedPumpKey)
        }
    }

    static func loadCachedReadings() -> [Reading] {
        guard let data = UserDefaults.standard.data(forKey: cachedReadingsKey),
              let arr = try? JSONDecoder().decode([Reading].self, from: data) else { return [] }
        return arr
    }

    static func loadCachedPump() -> PumpSnapshot {
        guard let data = UserDefaults.standard.data(forKey: cachedPumpKey),
              let p = try? JSONDecoder().decode(PumpSnapshot.self, from: data) else { return PumpSnapshot() }
        return p
    }

    static func normalizeBase(_ raw: String) -> String {
        var b = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { b = "http://100.85.127.42:1337" }
        if !b.contains("://") { b = "http://" + b }
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }

    static func bridgeBase(from nsBase: String) -> String {
        if nsBase.hasSuffix(":1337") {
            return String(nsBase.dropLast(5)) + ":1338"
        }
        return "http://100.85.127.42:1338"
    }

    static func recent(base: String, count: Int = 72) async throws -> [Reading] {
        let b = normalizeBase(base)
        guard let url = URL(string: "\(b)/api/v1/entries.json?count=\(count)") else {
            throw GlucoseFetchError.badAddress
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("GlucoPulseWidget/2.4", forHTTPHeaderField: "User-Agent")
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
            let dir = (e["direction"] as? String) ?? "Flat"
            out.append(Reading(id: ms, date: Date(timeIntervalSince1970: ms / 1000.0), mgdl: sgv, direction: dir))
        }
        return out.sorted { $0.date < $1.date }
    }

    static func fetchPump(base: String) async -> PumpSnapshot {
        let b = normalizeBase(base)
        let bridge = bridgeBase(from: b)
        var snap = PumpSnapshot()

        // 1. Try direct BLE pump telemetry cached on TrueNAS Bridge (:1338/api/ble-devicestatus)
        if let bridgeURL = URL(string: "\(bridge)/api/ble-devicestatus") {
            var req = URLRequest(url: bridgeURL, timeoutInterval: 5)
            req.setValue("GlucoPulseWidget/2.4", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               !json.isEmpty {
                snap.iobUnits = (json["iobUnits"] as? NSNumber)?.doubleValue ?? 0
                snap.activeBasalRate = (json["activeBasalRate"] as? NSNumber)?.doubleValue ?? 0
                snap.reservoirUnits = (json["reservoirUnits"] as? NSNumber)?.doubleValue ?? 0
                snap.batteryPercent = (json["batteryPercent"] as? NSNumber)?.intValue ?? 0
                snap.controlIQMode = (json["controlIQMode"] as? String) ?? "Control-IQ"
                snap.lastBolusUnits = (json["lastBolusUnits"] as? NSNumber)?.doubleValue ?? 0
                if snap.hasTelemetry { return snap }
            }
        }

        // 2. Fallback to Nightscout /api/v1/devicestatus.json
        if let nsURL = URL(string: "\(b)/api/v1/devicestatus.json?count=3") {
            var req = URLRequest(url: nsURL, timeoutInterval: 5)
            req.setValue("GlucoPulseWidget/2.4", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for entry in arr {
                    if let pump = entry["pump"] as? [String: Any] {
                        if let iobDict = pump["iob"] as? [String: Any] {
                            snap.iobUnits = (iobDict["bolusiob"] as? NSNumber)?.doubleValue
                                ?? (iobDict["iob"] as? NSNumber)?.doubleValue ?? 0
                        }
                        snap.reservoirUnits = (pump["reservoir"] as? NSNumber)?.doubleValue ?? 0
                        if let batt = pump["battery"] as? [String: Any] {
                            snap.batteryPercent = (batt["percent"] as? NSNumber)?.intValue ?? 0
                        }
                        if let st = pump["status"] as? [String: Any] {
                            snap.controlIQMode = (st["status"] as? String) ?? "Control-IQ"
                            snap.activeBasalRate = (st["activeBasalRate"] as? NSNumber)?.doubleValue ?? 0
                        }
                        if snap.hasTelemetry { return snap }
                    }
                }
            }
        }

        return loadCachedPump()
    }
}

struct GlucoseEntry: TimelineEntry {
    let date: Date
    let configuration: GlucoseConfigIntent
    let readings: [Reading]
    let pump: PumpSnapshot
    let errorText: String?

    var latest: Reading? { readings.last }

    var previous: Reading? {
        guard let l = latest else { return nil }
        return readings.reversed().first { l.date.timeIntervalSince($0.date) >= 180 && l.date.timeIntervalSince($0.date) <= 900 }
    }

    var deltaText: String {
        guard let l = latest, let p = previous else { return "" }
        let diffMgdl = l.mgdl - p.mgdl
        if configuration.unit == .mmolL {
            let diffMmol = diffMgdl / 18.0182
            return String(format: "%+.1f", diffMmol)
        } else {
            return String(format: "%+.0f", diffMgdl)
        }
    }

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

    var timeInRangePercent: Int {
        guard !readings.isEmpty else { return 0 }
        let inRange = readings.filter { $0.mgdl >= lowMgdl && $0.mgdl <= highMgdl }.count
        return Int((Double(inRange) / Double(readings.count) * 100.0).rounded())
    }

    var averageText: String {
        guard !readings.isEmpty else { return "--" }
        let avg = readings.map { $0.mgdl }.reduce(0, +) / Double(readings.count)
        return valueText(avg)
    }

    func readings(lastHours: Double) -> [Reading] {
        let cutoff = (latest?.date ?? date).addingTimeInterval(-lastHours * 3600)
        let sub = readings.filter { $0.date >= cutoff }
        return sub.isEmpty ? Array(readings.suffix(36)) : sub
    }

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
        default: return "→"
        }
    }

    func color(for r: Reading) -> Color {
        if isStale { return .gray }
        let mmol = r.mgdl / 18.0182
        if mmol < 3.0 || mmol > 13.9 { return Color(red: 0.96, green: 0.24, blue: 0.32) }
        if r.mgdl < lowMgdl { return Color(red: 0.98, green: 0.36, blue: 0.36) }
        if r.mgdl > highMgdl { return Color(red: 0.98, green: 0.68, blue: 0.16) }
        return Color(red: 0.18, green: 0.86, blue: 0.48)
    }

    static func sample(_ config: GlucoseConfigIntent) -> GlucoseEntry {
        let now = Date()
        var rs: [Reading] = []
        for i in 0..<36 {
            let t = now.addingTimeInterval(Double(i - 35) * 300)
            let v = 122.0 + 28.0 * sin(Double(i) / 5.0)
            rs.append(Reading(id: t.timeIntervalSince1970 * 1000, date: t, mgdl: v, direction: "Flat"))
        }
        let pump = PumpSnapshot(iobUnits: 1.45, activeBasalRate: 0.85, reservoirUnits: 152, batteryPercent: 85, controlIQMode: "Control-IQ Active", lastBolusUnits: 2.8)
        return GlucoseEntry(date: now, configuration: config, readings: rs, pump: pump, errorText: nil)
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
        async let pumpTask = NightscoutClient.fetchPump(base: config.nightscoutURL)
        do {
            let rs = try await NightscoutClient.recent(base: config.nightscoutURL, count: 72)
            let pump = await pumpTask
            NightscoutClient.saveCache(readings: rs, pump: pump)
            let finalReadings = rs.isEmpty ? NightscoutClient.loadCachedReadings() : rs
            return GlucoseEntry(
                date: now,
                configuration: config,
                readings: finalReadings,
                pump: pump,
                errorText: finalReadings.isEmpty ? "Waiting for G7 BLE / Nightscout" : nil
            )
        } catch {
            let cached = NightscoutClient.loadCachedReadings()
            let pump = await pumpTask
            return GlucoseEntry(
                date: now,
                configuration: config,
                readings: cached,
                pump: pump,
                errorText: cached.isEmpty ? "Offline · Check Tailscale / Nightscout" : nil
            )
        }
    }
}

// MARK: - Sparkline View

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
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.green.opacity(0.14))
                    .frame(width: geo.size.width, height: max(bandBottom - bandTop, 1))
                    .position(x: geo.size.width / 2, y: (bandTop + bandBottom) / 2)

                Path { p in
                    for (i, q) in pts.enumerated() {
                        if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                if let last = pts.last {
                    Circle()
                        .fill(lineColor)
                        .frame(width: 7, height: 7)
                        .position(last)
                }
            }
        }
    }
}

// MARK: - Widget Views

struct GlucoseWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: GlucoseEntry

    private let cyanColor = Color(red: 0.45, green: 0.78, blue: 0.96)

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
        case .systemLarge:
            largeView
        default:
            smallView
        }
    }

    private var noData: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("GlucoPulse").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text("No reading").font(.headline).foregroundStyle(.white)
            Text(entry.errorText ?? "Open GlucoPulse to sync")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(entry.isStale ? Color.yellow : Color.green)
                    .frame(width: 6, height: 6)
                Text("DEXCOM G7")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.agoText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if let l = entry.latest {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(entry.valueText(l.mgdl))
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(entry.arrow(l.direction))
                        .font(.system(size: 22, weight: .bold))
                }
                .foregroundStyle(entry.color(for: l))

                HStack(spacing: 4) {
                    if !entry.deltaText.isEmpty {
                        Text("\(entry.deltaText) \(entry.unitText)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    } else {
                        Text(entry.unitText)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Sparkline(
                    readings: entry.readings(lastHours: 2.0),
                    lowMgdl: entry.lowMgdl,
                    highMgdl: entry.highMgdl,
                    lineColor: entry.color(for: l)
                )
                .frame(height: 26)
                .padding(.top, 2)

                if entry.pump.hasTelemetry {
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(cyanColor)
                        Text(String(format: "IOB %.2fU", entry.pump.iobUnits))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(cyanColor)
                        Spacer()
                        if entry.pump.batteryPercent > 0 {
                            Text("\(entry.pump.batteryPercent)%")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Spacer()
                noData
                Spacer()
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.isStale ? Color.yellow : Color.green)
                        .frame(width: 6, height: 6)
                    Text("GLUCOPULSE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let l = entry.latest {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(entry.valueText(l.mgdl))
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(entry.arrow(l.direction))
                            .font(.system(size: 22, weight: .bold))
                    }
                    .foregroundStyle(entry.color(for: l))

                    Text("\(entry.deltaText.isEmpty ? entry.unitText : "\(entry.deltaText) \(entry.unitText)") · \(entry.agoText)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if entry.pump.hasTelemetry {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Label(String(format: "%.2f U", entry.pump.iobUnits), systemImage: "syringe.fill")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(cyanColor)
                                if entry.pump.activeBasalRate > 0 {
                                    Text(String(format: "%.2f U/h", entry.pump.activeBasalRate))
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.purple)
                                }
                            }
                            HStack(spacing: 6) {
                                if entry.pump.reservoirUnits > 0 {
                                    Text("\(Int(entry.pump.reservoirUnits))U cart")
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                                if entry.pump.batteryPercent > 0 {
                                    Text("⚡\(entry.pump.batteryPercent)%")
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text("TIR \(entry.timeInRangePercent)% · Avg \(entry.averageText)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(cyanColor)
                    }
                } else {
                    noData
                }
            }
            .frame(maxWidth: 138, alignment: .leading)

            if let l = entry.latest {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("LAST 3 HOURS")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("TIR \(entry.timeInRangePercent)%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                    }
                    Sparkline(
                        readings: entry.readings(lastHours: 3.0),
                        lowMgdl: entry.lowMgdl,
                        highMgdl: entry.highMgdl,
                        lineColor: entry.color(for: l)
                    )
                }
            }
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let l = entry.latest {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(entry.isStale ? Color.yellow : Color.green)
                                .frame(width: 7, height: 7)
                            Text("DEXCOM G7 + T:SLIM X2")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(entry.valueText(l.mgdl))
                                .font(.system(size: 46, weight: .black, design: .rounded))
                            Text(entry.arrow(l.direction))
                                .font(.system(size: 26, weight: .bold))
                            Text(entry.unitText)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(entry.color(for: l))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        if !entry.deltaText.isEmpty {
                            Text("\(entry.deltaText) \(entry.unitText)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        Text(entry.agoText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("TIR \(entry.timeInRangePercent)% · Avg \(entry.averageText)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("LAST 6 HOURS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Sparkline(
                        readings: entry.readings(lastHours: 6.0),
                        lowMgdl: entry.lowMgdl,
                        highMgdl: entry.highMgdl,
                        lineColor: entry.color(for: l)
                    )
                }
                .frame(maxHeight: .infinity)

                if entry.pump.hasTelemetry {
                    HStack(spacing: 10) {
                        statPill(title: "ACTIVE IOB", value: String(format: "%.2f U", entry.pump.iobUnits), color: cyanColor)
                        statPill(title: "BASAL", value: String(format: "%.2f U/h", entry.pump.activeBasalRate), color: .purple)
                        statPill(title: "CARTRIDGE", value: "\(Int(entry.pump.reservoirUnits)) U", color: .green)
                        statPill(title: "BATTERY", value: "\(entry.pump.batteryPercent)%", color: .mint)
                    }
                }
            } else {
                Spacer()
                noData
                Spacer()
            }
        }
    }

    private func statPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let l = entry.latest {
                VStack(spacing: -1) {
                    Text("\(entry.valueText(l.mgdl))\(entry.arrow(l.direction))")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.6)
                    if entry.pump.iobUnits > 0 {
                        Text(String(format: "%.1fU", entry.pump.iobUnits))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(entry.agoText)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
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
                    Text("\(entry.valueText(l.mgdl)) \(entry.arrow(l.direction))")
                        .font(.system(.headline, design: .rounded).weight(.black))
                    if entry.pump.iobUnits > 0 {
                        Text(String(format: "IOB %.1fU", entry.pump.iobUnits))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    } else {
                        Text("\(entry.unitText) · \(entry.agoText)")
                            .font(.caption2)
                    }
                }
                Sparkline(
                    readings: entry.readings(lastHours: 3.0),
                    lowMgdl: entry.lowMgdl,
                    highMgdl: entry.highMgdl,
                    lineColor: .white
                )
                .frame(height: 22)
            } else {
                Text("GlucoPulse: no data")
            }
        }
    }

    private var inlineView: some View {
        if let l = entry.latest {
            let iobPart = entry.pump.iobUnits > 0 ? String(format: " · IOB %.1fU", entry.pump.iobUnits) : ""
            return Text("🩸 \(entry.valueText(l.mgdl)) \(entry.arrow(l.direction)) (\(entry.agoText))\(iobPart)")
        }
        return Text("GlucoPulse: no data")
    }
}

// MARK: - Widget Definition

struct GlucoPulseGlucoseWidget: Widget {
    let kind = "GlucoPulseGlucoseWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: GlucoseConfigIntent.self, provider: GlucoseProvider()) { entry in
            GlucoseWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.03, green: 0.015, blue: 0.025),
                            Color(red: 0.11, green: 0.035, blue: 0.065)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("GlucoPulse T1D")
        .description("Live Dexcom G7 glucose, trend arrow, 3h/6h graph, and Tandem t:slim X2 IOB telemetry.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

@main
struct GlucoPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        GlucoPulseGlucoseWidget()
    }
}
