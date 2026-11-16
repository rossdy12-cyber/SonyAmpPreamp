import WidgetKit
import SwiftUI
import AppIntents

struct SentryCamConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "SentryCam Night Watch"
    static var description = IntentDescription("Gothic Vampire Frigate NVR AI detections & perimeter watch.")

    @Parameter(title: "Frigate URL", default: "http://100.85.127.42:5000")
    var frigateURL: String

    init() {}
}

struct FrigateEventItem: Identifiable {
    let id: String
    let camera: String
    let label: String
    let score: Int
    let date: Date
}

struct SentryCamEntry: TimelineEntry {
    let date: Date
    let events: [FrigateEventItem]
    let camerasOnline: Int
}

struct SentryCamProvider: AppIntentTimelineProvider {
    typealias Intent = SentryCamConfigIntent
    typealias Entry = SentryCamEntry

    func placeholder(in context: Context) -> SentryCamEntry { sample() }
    func snapshot(for configuration: SentryCamConfigIntent, in context: Context) async -> SentryCamEntry {
        if context.isPreview { return sample() }
        return await load(configuration)
    }
    func timeline(for configuration: SentryCamConfigIntent, in context: Context) async -> Timeline<SentryCamEntry> {
        let entry = await load(configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(5 * 60)))
    }

    private func load(_ cfg: SentryCamConfigIntent) async -> SentryCamEntry {
        var base = cfg.frigateURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "http://100.85.127.42:5000" }
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: "\(base)/api/events?limit=4&include_thumbnails=0") else { return sample() }
        var req = URLRequest(url: url, timeoutInterval: 6)
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !arr.isEmpty {
            let parsed: [FrigateEventItem] = arr.prefix(3).enumerated().map { idx, d in
                let id = (d["id"] as? String) ?? "\(idx)"
                let cam = ((d["camera"] as? String) ?? "front_door").replacingOccurrences(of: "_", with: " ").capitalized
                let lbl = ((d["label"] as? String) ?? "person").capitalized
                let topScore = ((d["top_score"] as? NSNumber)?.doubleValue ?? (d["score"] as? NSNumber)?.doubleValue ?? 0.92) * 100.0
                let ts = (d["start_time"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
                return FrigateEventItem(id: id, camera: cam, label: lbl, score: Int(topScore.rounded()), date: Date(timeIntervalSince1970: ts))
            }
            return SentryCamEntry(date: Date(), events: parsed, camerasOnline: 4)
        }
        return sample()
    }

    private func sample() -> SentryCamEntry {
        let now = Date()
        return SentryCamEntry(
            date: now,
            events: [
                FrigateEventItem(id: "1", camera: "Front Gate", label: "Mortal", score: 94, date: now.addingTimeInterval(-240)),
                FrigateEventItem(id: "2", camera: "Courtyard", label: "Carriage", score: 91, date: now.addingTimeInterval(-1320)),
                FrigateEventItem(id: "3", camera: "Sanctum Garden", label: "Mortal", score: 88, date: now.addingTimeInterval(-3400))
            ],
            camerasOnline: 4
        )
    }
}

struct SentryCamWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: SentryCamEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("✠").font(.caption2)
                    Text("\(entry.camerasOnline)👁").font(GothicTheme.serif(11, weight: .bold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("✠ SentryCam Watch").font(GothicTheme.serif(13, weight: .bold))
                if let first = entry.events.first {
                    Text("\(first.label) · \(first.camera) (\(first.score)%)").font(GothicTheme.serif(10))
                    Text(first.date, style: .relative).font(GothicTheme.serif(9)).foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            if let first = entry.events.first {
                Text("✠ \(first.camera): \(first.label) (\(first.score)%)")
            } else {
                Text("✠ SentryCam: All quiet")
            }
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            GothicHeader(title: "SentryCam", rightText: "\(entry.camerasOnline) Eyes")
            Spacer(minLength: 0)
            if let first = entry.events.first {
                Text(first.label.uppercased())
                    .font(GothicTheme.display(22))
                    .foregroundStyle(GothicTheme.bone)
                    .lineLimit(1)
                Text(first.camera)
                    .font(GothicTheme.serif(12, weight: .bold))
                    .foregroundStyle(GothicTheme.bloodHi)
                Spacer(minLength: 0)
                HStack {
                    Text("\(first.score)% Omen")
                        .font(GothicTheme.serif(9.5, weight: .bold))
                        .foregroundStyle(GothicTheme.bone)
                    Spacer()
                    Text(first.date, style: .relative)
                        .font(GothicTheme.serif(9, weight: .medium))
                        .foregroundStyle(GothicTheme.ash)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .gothicPanel(active: true, corner: 5)
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 5) {
            GothicHeader(title: "SentryCam · Night Watch", rightText: "\(entry.camerasOnline) Wards Active")
            ForEach(entry.events.prefix(3)) { ev in
                HStack(spacing: 8) {
                    Text("✠")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GothicTheme.bloodHi)
                    Text("\(ev.label) · \(ev.camera)")
                        .font(GothicTheme.serif(11.5, weight: .bold))
                        .foregroundStyle(GothicTheme.bone)
                        .lineLimit(1)
                    Spacer()
                    Text(ev.date, style: .relative)
                        .font(GothicTheme.serif(9.5))
                        .foregroundStyle(GothicTheme.ash)
                    Text("\(ev.score)%")
                        .font(GothicTheme.serif(10, weight: .bold))
                        .foregroundStyle(GothicTheme.bloodHi)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .gothicPanel(active: false, corner: 6)
            }
        }
    }
}

struct SentryCamWidget: Widget {
    let kind = "SentryCamWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SentryCamConfigIntent.self, provider: SentryCamProvider()) { entry in
            SentryCamWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GothicCathedralBackground()
                }
        }
        .configurationDisplayName("SentryCam Night Watch")
        .description("Gothic Vampire Frigate NVR AI detections & perimeter watch.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct SentryCamWidgetBundle: WidgetBundle {
    var body: some Widget {
        SentryCamWidget()
    }
}
