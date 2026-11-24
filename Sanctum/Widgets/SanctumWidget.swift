import WidgetKit
import SwiftUI

struct SanctumWidgetEntry: TimelineEntry {
    let date: Date
    let mmol: Double
    let arrow: String
    let pumpStatus: String
    let iob: Double
    let tvMode: String
    let freeDiskGB: Double
    let trendingCount: Int
}

struct SanctumWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SanctumWidgetEntry {
        SanctumWidgetEntry(date: Date(), mmol: 9.1, arrow: "→", pumpStatus: "Control-IQ Active", iob: 0.0, tvMode: "BEDSIDE", freeDiskGB: 2445.0, trendingCount: 16)
    }

    func getSnapshot(in context: Context, completion: @escaping (SanctumWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SanctumWidgetEntry>) -> Void) {
        let url = URL(string: "https://hs.nas-server.co.uk/sidestore-api/sanctum-hub?op=overview")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var entry = placeholder(in: context)
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let t1d = json["t1d"] as? [String: Any] ?? [:]
                let dl = json["downloads"] as? [String: Any] ?? [:]
                let br = json["bridge"] as? [String: Any] ?? [:]
                let disc = json["discover"] as? [String: Any] ?? [:]
                let tr = disc["trending"] as? [[String: Any]] ?? []
                entry = SanctumWidgetEntry(
                    date: Date(),
                    mmol: t1d["mmol"] as? Double ?? 9.1,
                    arrow: t1d["arrow"] as? String ?? "→",
                    pumpStatus: t1d["pumpStatus"] as? String ?? "Control-IQ Active",
                    iob: t1d["iob"] as? Double ?? 0.0,
                    tvMode: (br["tvMode"] as? String ?? "overview").uppercased(),
                    freeDiskGB: dl["freeDiskGB"] as? Double ?? 2445.0,
                    trendingCount: tr.count
                )
            }
            let next = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }.resume()
    }
}

struct SanctumWidgetView: View {
    var entry: SanctumWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            GothicCathedralBackground()
            VStack(alignment: .leading, spacing: 6) {
                GothicHeader(title: "SANCTUM", rightText: "TV: \(entry.tvMode)")
                Spacer(minLength: 2)
                if family == .systemSmall {
                    Text(String(format: "%.1f %@", entry.mmol, entry.arrow))
                        .font(GothicTheme.display(26))
                        .foregroundStyle(GothicTheme.bloodHi)
                    Text("DEXCOM G7 · mmol/L")
                        .font(GothicTheme.serif(9.5, weight: .bold))
                        .foregroundStyle(GothicTheme.ash)
                    HStack(spacing: 4) {
                        Text(String(format: "IOB %.1fU", entry.iob))
                            .font(GothicTheme.serif(9, weight: .bold))
                            .foregroundStyle(GothicTheme.bone)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .gothicPanel(active: true)
                        Text(String(format: "%.1fTB", entry.freeDiskGB / 1000.0))
                            .font(GothicTheme.serif(9, weight: .bold))
                            .foregroundStyle(GothicTheme.bone)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .gothicPanel()
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(format: "%.1f %@", entry.mmol, entry.arrow))
                                .font(GothicTheme.display(30))
                                .foregroundStyle(GothicTheme.bloodHi)
                            Text("DEXCOM G7 · \(entry.pumpStatus)")
                                .font(GothicTheme.serif(10, weight: .semibold))
                                .foregroundStyle(GothicTheme.ash)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text("APPLE TV · \(entry.tvMode)")
                                .font(GothicTheme.serif(9.5, weight: .bold))
                                .foregroundStyle(GothicTheme.bone)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .gothicPanel(active: true)
                            Text(String(format: "IOB %.2f U · ZFS %.0f GB", entry.iob, entry.freeDiskGB))
                                .font(GothicTheme.serif(9.5, weight: .bold))
                                .foregroundStyle(GothicTheme.bone)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .gothicPanel()
                        }
                    }
                }
            }
            .padding(12)
        }
        .containerBackground(for: .widget) {
            GothicTheme.void
        }
    }
}

@main
struct SanctumWidgetBundle: WidgetBundle {
    var body: some Widget {
        SanctumHomeWidget()
    }
}

struct SanctumHomeWidget: Widget {
    let kind: String = "SanctumHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SanctumWidgetProvider()) { entry in
            SanctumWidgetView(entry: entry)
        }
        .configurationDisplayName("Sanctum Command & TV Bridge")
        .description("Live Nightscout T1D glucose, TrueNAS ZFS storage, and Bedroom Apple TV mode.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
