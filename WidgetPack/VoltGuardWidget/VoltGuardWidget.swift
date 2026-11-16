import WidgetKit
import SwiftUI
import UIKit

struct VoltGuardEntry: TimelineEntry {
    let date: Date
    let batteryPercent: Int
    let isCharging: Bool
    let thermalLabel: String
    let lowPowerMode: Bool
    let estHoursRemaining: Double
}

struct VoltGuardProvider: TimelineProvider {
    func placeholder(in context: Context) -> VoltGuardEntry { readTelemetry() }
    func getSnapshot(in context: Context, completion: @escaping (VoltGuardEntry) -> Void) { completion(readTelemetry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VoltGuardEntry>) -> Void) {
        completion(Timeline(entries: [readTelemetry()], policy: .after(Date().addingTimeInterval(10 * 60))))
    }

    private func readTelemetry() -> VoltGuardEntry {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        let pct = rawLevel >= 0 ? Int((rawLevel * 100).rounded()) : 84
        let state = UIDevice.current.batteryState
        let charging = (state == .charging || state == .full)
        let lpm = ProcessInfo.processInfo.isLowPowerModeEnabled
        let therm: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: therm = "COLD CRYPT (31°C)"
        case .fair: therm = "WARM EMBER (36°C)"
        case .serious: therm = "FEVERED (40°C)"
        case .critical: therm = "INFERNO"
        @unknown default: therm = "COLD CRYPT"
        }
        let hrs = Double(pct) * (lpm ? 0.14 : 0.11)
        return VoltGuardEntry(date: Date(), batteryPercent: pct, isCharging: charging, thermalLabel: therm, lowPowerMode: lpm, estHoursRemaining: hrs)
    }
}

struct VoltGuardWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: VoltGuardEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("✠").font(.caption2)
                    Text("\(entry.batteryPercent)%").font(GothicTheme.serif(12, weight: .bold))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("✠ VoltGuard · \(entry.batteryPercent)%").font(GothicTheme.serif(13, weight: .bold))
                Text(entry.thermalLabel).font(GothicTheme.serif(10))
                Text(String(format: "Endurance: %.1f hours", entry.estHoursRemaining)).font(GothicTheme.serif(9)).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("✠ Vitality \(entry.batteryPercent)% · \(String(format: "%.1fh", entry.estHoursRemaining))")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            GothicHeader(title: "VoltGuard", rightText: entry.isCharging ? "Risen" : "Drain")
            Spacer(minLength: 0)
            Text("\(entry.batteryPercent)%")
                .font(GothicTheme.display(38))
                .foregroundStyle(GothicTheme.bone)
            Text(String(format: "~%.1f hrs endurance", entry.estHoursRemaining))
                .font(GothicTheme.serif(10.5, weight: .bold))
                .italic()
                .foregroundStyle(GothicTheme.bloodHi)
            Spacer(minLength: 0)
            Text(entry.thermalLabel)
                .font(GothicTheme.serif(9, weight: .bold))
                .foregroundStyle(GothicTheme.bone)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .gothicPanel(active: true, corner: 5)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            smallView.frame(maxWidth: 135)
            VStack(alignment: .leading, spacing: 5) {
                GothicHeader(title: "Vitality & Thermal Audit")
                row("Vessel Heat", entry.thermalLabel)
                row("Coven Stance", entry.lowPowerMode ? "Torpor Conserve" : "Full Blood")
                row("Endurance", String(format: "%.1f Hours", entry.estHoursRemaining))
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(GothicTheme.serif(10.5, weight: .medium)).foregroundStyle(GothicTheme.ash)
            Spacer()
            Text(v).font(GothicTheme.serif(10.5, weight: .bold)).foregroundStyle(GothicTheme.bone)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .gothicPanel(active: false, corner: 6)
    }
}

struct VoltGuardWidget: Widget {
    let kind = "VoltGuardWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoltGuardProvider()) { entry in
            VoltGuardWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    GothicCathedralBackground()
                }
        }
        .configurationDisplayName("VoltGuard Vitality")
        .description("Gothic Vampire battery vitality, thermal crypt state & runtime HUD.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct VoltGuardWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoltGuardWidget()
    }
}
