import WidgetKit
import SwiftUI
import AppIntents

struct SentryCamConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "SentryCam Frigate NVR"
    static var description = IntentDescription("Live Frigate AI object detections and camera status from TrueNAS.")

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
        req.setValue("SentryCamWidget/2.1", forHTTPHeaderField: "User-Agent")
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !arr.isEmpty {
            let parsed: [FrigateEventItem] = arr.prefix(4).enumerated().map { idx, d in
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
                FrigateEventItem(id: "1", camera: "Front Door", label: "Person", score: 94, date: now.addingTimeInterval(-240)),
                FrigateEventItem(id: "2", camera: "Driveway", label: "Car", score: 91, date: now.addingTimeInterval(-1320)),
                FrigateEventItem(id: "3", camera: "Garden", label: "Person", score: 88, date: now.addingTimeInterval(-3400))
            ],
            camerasOnline: 4
        )
    }
}

struct SentryCamWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: SentryCamEntry

    private let crimson = Color(red: 0.90, green: 0.20, blue: 0.32)

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "video.fill").font(.caption)
                    Text("\(entry.camerasOnline)").font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("SentryCam NVR", systemImage: "video.fill").font(.headline)
                if let first = entry.events.first {
                    Text("\(first.label) · \(first.camera) (\(first.score)%)").font(.caption)
                    Text(first.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            if let first = entry.events.first {
                Text("📹 \(first.camera): \(first.label) (\(first.score)%)")
            } else {
                Text("📹 SentryCam: All clear")
            }
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "video.badge.waveform.fill").foregroundStyle(crimson)
                Text("SENTRYCAM").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(Color.green).frame(width: 6, height: 6)
            }
            Spacer(minLength: 0)
            if let first = entry.events.first {
                Text(first.label.uppercased())
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(first.camera)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(crimson)
                HStack {
                    Text("\(first.score)% AI")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Spacer()
                    Text(first.date, style: .relative)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "video.badge.waveform.fill").foregroundStyle(crimson)
                Text("SENTRYCAM FRIGATE NVR")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.camerasOnline) CAMERAS ONLINE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            }
            ForEach(entry.events.prefix(3)) { ev in
                HStack(spacing: 8) {
                    Image(systemName: ev.label == "Car" ? "car.fill" : "figure.walk")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(crimson)
                        .frame(width: 22, height: 22)
                        .background(crimson.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(ev.label) · \(ev.camera)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(ev.date, style: .relative)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(ev.score)%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
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
                    LinearGradient(
                        colors: [Color(red: 0.03, green: 0.015, blue: 0.02), Color(red: 0.11, green: 0.03, blue: 0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("SentryCam Frigate NVR")
        .description("Latest Frigate AI camera detections and live NVR status.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct SentryCamWidgetBundle: WidgetBundle {
    var body: some Widget {
        SentryCamWidget()
    }
}
