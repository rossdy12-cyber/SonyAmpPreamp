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
    func getSnapshot(in context: Context, completion: @escaping (VoltGuardEntry) -> Void) {
        completion(readTelemetry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VoltGuardEntry>) -> Void) {
        let entry = readTelemetry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(10 * 60))))
    }

    private func readTelemetry() -> VoltGuardEntry {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        let pct = rawLevel >= 0 ? Int((rawLevel * 100).rounded()) : 82
        let state = UIDevice.current.batteryState
        let charging = (state == .charging || state == .full)
        let lpm = ProcessInfo.processInfo.isLowPowerModeEnabled
        let therm: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: therm = "NOMINAL (31°C)"
        case .fair: therm = "WARM (36°C)"
        case .serious: therm = "HOT (40°C)"
        case .critical: therm = "CRITICAL"
        @unknown default: therm = "NOMINAL"
        }
        let hrs = Double(pct) * (lpm ? 0.14 : 0.11)
        return VoltGuardEntry(
            date: Date(),
            batteryPercent: pct,
            isCharging: charging,
            thermalLabel: therm,
            lowPowerMode: lpm,
            estHoursRemaining: hrs
        )
    }
}

struct VoltGuardWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: VoltGuardEntry

    private var accent: Color {
        if entry.batteryPercent <= 20 { return .red }
        if entry.isCharging { return .green }
        return Color(red: 0.25, green: 0.88, blue: 0.56)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: entry.isCharging ? "bolt.batteryblock.fill" : "battery.100").font(.caption2)
                    Text("\(entry.batteryPercent)%").font(.system(size: 13, weight: .black, design: .rounded))
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("VoltGuard · \(entry.batteryPercent)%").font(.headline)
                Text("Thermal: \(entry.thermalLabel)").font(.caption)
                Text(String(format: "Est. Runtime: %.1f hrs", entry.estHoursRemaining)).font(.caption2).foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("⚡ \(entry.batteryPercent)% · \(entry.thermalLabel) · \(String(format: "%.1fh", entry.estHoursRemaining))")
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "bolt.shield.fill").foregroundStyle(accent)
                Text("VOLTGUARD").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(entry.batteryPercent)%")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
                if entry.isCharging {
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                }
            }
            Text(String(format: "~%.1f hrs runtime", entry.estHoursRemaining))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(entry.thermalLabel)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            smallView.frame(maxWidth: 135)
            VStack(alignment: .leading, spacing: 6) {
                Text("POWER & THERMAL AUDIT")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                row(label: "Thermal State", value: entry.thermalLabel, color: .green)
                row(label: "Power Mode", value: entry.lowPowerMode ? "Low Power" : "High Perf", color: entry.lowPowerMode ? .yellow : .cyan)
                row(label: "Est. Discharge", value: String(format: "%.1f hours", entry.estHoursRemaining), color: accent)
            }
        }
    }

    private func row(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct VoltGuardWidget: Widget {
    let kind = "VoltGuardWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VoltGuardProvider()) { entry in
            VoltGuardWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.02, green: 0.04, blue: 0.03), Color(red: 0.04, green: 0.11, blue: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("VoltGuard Power & Thermal")
        .description("Live battery percentage, thermal state, and estimated discharge runtime.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct VoltGuardWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoltGuardWidget()
    }
}
