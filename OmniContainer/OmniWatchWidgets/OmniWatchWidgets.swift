import WidgetKit
import SwiftUI
import Foundation

struct JarvisComplicationEntry: TimelineEntry {
    let date: Date
    let status: String
    let bgMmol: String
    let trendArrow: String
    let iobUnits: String
    let nextPaydayDays: Int
}

struct JarvisComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> JarvisComplicationEntry {
        JarvisComplicationEntry(date: Date(), status: "NOMINAL", bgMmol: "5.8", trendArrow: "→", iobUnits: "1.2U", nextPaydayDays: 11)
    }

    func getSnapshot(in context: Context, completion: @escaping (JarvisComplicationEntry) -> Void) {
        completion(JarvisComplicationEntry(date: Date(), status: "NOMINAL", bgMmol: "5.8", trendArrow: "→", iobUnits: "1.2U", nextPaydayDays: 11))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JarvisComplicationEntry>) -> Void) {
        Task {
            var bgStr = "--"
            var arrow = "→"
            var iobStr = "0.0U"
            if let u = URL(string: "http://100.85.127.42:1337/api/v1/entries/sgv.json?count=1"),
               let (data, _) = try? await URLSession.shared.data(from: u),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = arr.first,
               let sgv = first["sgv"] as? Int, sgv > 0 {
                bgStr = String(format: "%.1f", Double(sgv) / 18.0182)
                let dir = (first["direction"] as? String ?? "Flat").lowercased()
                switch dir {
                case "doubleup": arrow = "↑↑"
                case "singleup": arrow = "↑"
                case "fortyfiveup": arrow = "↗"
                case "fortyfivedown": arrow = "↘"
                case "singledown": arrow = "↓"
                case "doubledown": arrow = "↓↓"
                default: arrow = "→"
                }
            }
            if let u2 = URL(string: "http://100.85.127.42:1337/api/v1/devicestatus.json?count=1"),
               let (d2, _) = try? await URLSession.shared.data(from: u2),
               let arr2 = try? JSONSerialization.jsonObject(with: d2) as? [[String: Any]],
               let pump = arr2.first?["pump"] as? [String: Any],
               let iobDict = pump["iob"] as? [String: Any],
               let iobVal = iobDict["bolusiob"] as? Double ?? iobDict["iob"] as? Double {
                iobStr = String(format: "%.1fU", iobVal)
            }
            let entry = JarvisComplicationEntry(date: Date(), status: "NOMINAL", bgMmol: bgStr, trendArrow: arrow, iobUnits: iobStr, nextPaydayDays: 11)
            let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct JarvisComplicationView: View {
    var entry: JarvisComplicationProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.bgMmol)\(entry.trendArrow)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                    Text(entry.iobUnits)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.path.ecg").foregroundColor(.green)
                    Text("BG \(entry.bgMmol)\(entry.trendArrow) mmol/L").font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(.green)
                }
                Text("Tandem IOB: \(entry.iobUnits) • 🔓 PC Ready")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.cyan)
                Text("J.A.R.V.I.S. & NAS: \(entry.status)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        case .accessoryInline:
            Text("🩸 \(entry.bgMmol)\(entry.trendArrow) (\(entry.iobUnits)) • ⚡ J.A.R.V.I.S.")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Text("\(entry.bgMmol)\(entry.trendArrow)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
            }
        }
    }
}

@main
struct OmniWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        JarvisWristWidget()
    }
}

struct JarvisWristWidget: Widget {
    let kind: String = "JarvisWristWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JarvisComplicationProvider()) { entry in
            JarvisComplicationView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("J.A.R.V.I.S. & GlucoPulse HUD")
        .description("Live Dexcom G7 Glucose, Trend Arrow, Tandem IOB, PC Unlock & J.A.R.V.I.S. Voice.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}
