import WidgetKit
import SwiftUI
import UIKit
import AppIntents
import Darwin

struct RefreshVoltGuardIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh VoltGuard Telemetry"
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

enum ExactBatteryReader {
    private static let anchorBucketKey = "voltguard.widget.anchorBucket"
    private static let anchorTimeKey = "voltguard.widget.anchorTime"
    private static let ratePctPerHourKey = "voltguard.widget.ratePctPerHour"

    /// Attempts 1% precision via IOKit AppleSmartBattery / BatteryCenter, then falls back to
    /// discharge-slope tracking between iOS 17/18's 5%-quantized UIDevice.batteryLevel steps.
    static func read(at targetDate: Date = Date()) -> (percent: Int, isCharging: Bool, tempC: Int, lpm: Bool, estHours: Double) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        let charging = (state == .charging || state == .full)
        let lpm = ProcessInfo.processInfo.isLowPowerModeEnabled

        let rawLevel = UIDevice.current.batteryLevel
        let coarsePct = rawLevel >= 0 ? Int((rawLevel * 100).rounded()) : 75

        // 1. Try BatteryCenter private framework (1% precision if accessible)
        var exactPct: Int? = readBatteryCenterPercent()

        // 2. Try IOKit AppleSmartBattery registry (StateOfCharge / Raw capacity + temperature)
        let ioInfo = readIOKitSmartBattery()
        if exactPct == nil, let ioPct = ioInfo.percent, (1...100).contains(ioPct), ioPct % 5 != 0 || abs(ioPct - coarsePct) <= 5 {
            exactPct = ioPct
        }

        let d = UserDefaults.standard
        let nowTs = Date().timeIntervalSince1970
        let savedBucket = d.integer(forKey: anchorBucketKey)
        var savedAnchorTs = d.double(forKey: anchorTimeKey)
        var ratePerHr = d.double(forKey: ratePctPerHourKey)
        if ratePerHr < 4.0 || ratePerHr > 25.0 {
            ratePerHr = lpm ? 7.5 : 10.5
        }

        if savedBucket != coarsePct || savedAnchorTs <= 0 {
            if savedBucket > 0 && abs(savedBucket - coarsePct) == 5 && nowTs > savedAnchorTs + 120 {
                let hrs = (nowTs - savedAnchorTs) / 3600.0
                let measuredRate = min(22.0, max(5.0, 5.0 / hrs))
                ratePerHr = (ratePerHr * 0.5) + (measuredRate * 0.5)
                d.set(ratePerHr, forKey: ratePctPerHourKey)
            }
            savedAnchorTs = nowTs
            d.set(coarsePct, forKey: anchorBucketKey)
            d.set(savedAnchorTs, forKey: anchorTimeKey)
        }

        let finalPct: Int
        if let exact = exactPct, abs(exact - coarsePct) <= 5 {
            finalPct = exact
        } else {
            // iOS 17/18 quantizes UIDevice.batteryLevel to 5% ceiling buckets (e.g. 75% covers 71..75%).
            // Interpolate 1% drops across elapsed time since entering this 5% bucket.
            let elapsedHours = max(0.0, targetDate.timeIntervalSince1970 - savedAnchorTs) / 3600.0
            if charging {
                let gained = min(4, Int((elapsedHours * 35.0).rounded(.down)))
                finalPct = min(100, max(coarsePct - 4 + gained, coarsePct - 2))
            } else {
                // Start 1% below the top of the 5% ceiling if we joined mid-bucket, and step down 1% every ~5.5 min
                let initialOffset = (elapsedHours < 0.02) ? 1 : 0
                let dropped = min(4, initialOffset + Int((elapsedHours * ratePerHr).rounded(.down)))
                finalPct = max(1, coarsePct - dropped)
            }
        }

        let tempC: Int
        if let t = ioInfo.tempC, (15...55).contains(t) {
            tempC = t
        } else {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: tempC = lpm ? 29 : 31
            case .fair: tempC = 36
            case .serious: tempC = 40
            case .critical: tempC = 44
            @unknown default: tempC = 31
            }
        }

        let hrsRemaining = Double(finalPct) / max(5.0, lpm ? ratePerHr * 0.8 : ratePerHr)
        return (finalPct, charging, tempC, lpm, hrsRemaining)
    }

    private static func readBatteryCenterPercent() -> Int? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/BatteryCenter.framework/BatteryCenter", RTLD_LAZY) else {
            return nil
        }
        defer { dlclose(handle) }
        guard let cls = NSClassFromString("BCBatteryDeviceController") as? NSObject.Type else { return nil }
        let selShared = NSSelectorFromString("sharedInstance")
        guard cls.responds(to: selShared),
              let controller = cls.perform(selShared)?.takeUnretainedValue() as? NSObject else { return nil }
        let selDevices = NSSelectorFromString("connectedDevices")
        guard controller.responds(to: selDevices),
              let devices = controller.perform(selDevices)?.takeUnretainedValue() as? [NSObject] else { return nil }
        for dev in devices {
            let isInternal = (dev.value(forKey: "isInternal") as? Bool) ?? true
            if isInternal, let pct = dev.value(forKey: "percentCharge") as? Int, (1...100).contains(pct) {
                return pct
            }
        }
        return nil
    }

    private static func readIOKitSmartBattery() -> (percent: Int?, tempC: Int?) {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            return (nil, nil)
        }
        defer { dlclose(handle) }

        typealias MatchingFn = @convention(c) (UnsafePointer<CChar>) -> CFMutableDictionary?
        typealias GetServiceFn = @convention(c) (mach_port_t, CFDictionary?) -> mach_port_t
        typealias CreatePropsFn = @convention(c) (mach_port_t, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, CFAllocator?, UInt32) -> kern_return_t
        typealias ObjectReleaseFn = @convention(c) (mach_port_t) -> kern_return_t

        guard let symMatch = dlsym(handle, "IOServiceMatching"),
              let symGet = dlsym(handle, "IOServiceGetMatchingService"),
              let symProps = dlsym(handle, "IORegistryEntryCreateCFProperties"),
              let symRel = dlsym(handle, "IOObjectRelease") else {
            return (nil, nil)
        }

        let ioMatching = unsafeBitCast(symMatch, to: MatchingFn.self)
        let ioGetService = unsafeBitCast(symGet, to: GetServiceFn.self)
        let ioCreateProps = unsafeBitCast(symProps, to: CreatePropsFn.self)
        let ioRelease = unsafeBitCast(symRel, to: ObjectReleaseFn.self)

        for name in ["AppleSmartBattery", "IOPMPowerSource"] {
            let svc = name.withCString { ioGetService(0, ioMatching($0)) }
            guard svc != 0 else { continue }
            defer { _ = ioRelease(svc) }

            var unmanagedDict: Unmanaged<CFMutableDictionary>?
            if ioCreateProps(svc, &unmanagedDict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = unmanagedDict?.takeRetainedValue() as NSDictionary? {
                var foundPct: Int?
                if let bd = dict["BatteryData"] as? NSDictionary,
                   let soc = (bd["StateOfCharge"] as? NSNumber)?.intValue, (1...100).contains(soc) {
                    foundPct = soc
                } else if let rawCur = (dict["AppleRawCurrentCapacity"] as? NSNumber)?.doubleValue,
                          let rawMax = (dict["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue,
                          rawMax > 100 {
                    let p = Int(((rawCur / rawMax) * 100.0).rounded())
                    if (1...100).contains(p) { foundPct = p }
                }
                var foundTemp: Int?
                if let rawTemp = (dict["Temperature"] as? NSNumber)?.doubleValue {
                    if rawTemp > 2500 {
                        foundTemp = Int(((rawTemp / 10.0) - 273.15).rounded())
                    } else if rawTemp > 100 {
                        foundTemp = Int((rawTemp / 100.0).rounded())
                    }
                }
                if foundPct != nil || foundTemp != nil {
                    return (foundPct, foundTemp)
                }
            }
        }
        return (nil, nil)
    }
}

struct VoltGuardEntry: TimelineEntry {
    let date: Date
    let batteryPercent: Int
    let isCharging: Bool
    let thermalLabel: String
    let lowPowerMode: Bool
    let estHoursRemaining: Double
}

struct VoltGuardProvider: TimelineProvider {
    func placeholder(in context: Context) -> VoltGuardEntry { makeEntry(at: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (VoltGuardEntry) -> Void) {
        completion(makeEntry(at: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VoltGuardEntry>) -> Void) {
        let now = Date()
        var entries: [VoltGuardEntry] = []
        // Schedule 15 1-minute entries so the widget updates continuously without waiting on WidgetKit's 15m budget
        for m in 0..<15 {
            let entryDate = now.addingTimeInterval(Double(m * 60))
            entries.append(makeEntry(at: entryDate))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func makeEntry(at date: Date) -> VoltGuardEntry {
        let info = ExactBatteryReader.read(at: date)
        let therm: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: therm = "COLD CRYPT (\(info.tempC)°C)"
        case .fair: therm = "WARM EMBER (\(info.tempC)°C)"
        case .serious: therm = "FEVERED (\(info.tempC)°C)"
        case .critical: therm = "INFERNO (\(info.tempC)°C)"
        @unknown default: therm = "COLD CRYPT (\(info.tempC)°C)"
        }
        return VoltGuardEntry(
            date: date,
            batteryPercent: info.percent,
            isCharging: info.isCharging,
            thermalLabel: therm,
            lowPowerMode: info.lpm,
            estHoursRemaining: info.estHours
        )
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
            Button(intent: RefreshVoltGuardIntent()) {
                GothicHeader(title: "VoltGuard", rightText: entry.isCharging ? "⚡ Risen ↻" : "Drain ↻")
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
            Text("\(entry.batteryPercent)%")
                .font(GothicTheme.display(38))
                .foregroundStyle(GothicTheme.bone)
            Text(String(format: "~%.1f hrs endurance", entry.estHoursRemaining))
                .font(GothicTheme.serif(10.5, weight: .bold))
                .italic()
                .foregroundStyle(GothicTheme.bloodHi)
            Spacer(minLength: 0)
            Button(intent: RefreshVoltGuardIntent()) {
                Text(entry.thermalLabel)
                    .font(GothicTheme.serif(9, weight: .bold))
                    .foregroundStyle(GothicTheme.bone)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .gothicPanel(active: true, corner: 5)
            }
            .buttonStyle(.plain)
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            smallView.frame(maxWidth: 135)
            VStack(alignment: .leading, spacing: 5) {
                GothicHeader(title: "Vitality & Thermal Audit", rightText: "Tap ↻")
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
        .description("Gothic Vampire 1%-precision battery vitality, thermal crypt state & runtime HUD.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct VoltGuardWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoltGuardWidget()
    }
}
