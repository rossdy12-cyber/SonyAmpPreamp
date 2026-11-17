import SwiftUI
import UIKit
import AVFoundation
import Darwin
import WidgetKit

// MARK: - Models (honest telemetry only)

struct BatterySample: Codable, Identifiable {
    var id: UUID = UUID()
    let timestamp: Date
    let level: Int
    let isCharging: Bool
}

struct TrueNASSocketInfo: Codable, Identifiable {
    var id: String { "\(local)->\(remote)" }
    let state: String
    let local: String
    let remote: String
    let service: String?
}

struct JellyfinSessionInfo: Codable, Identifiable {
    let id: String
    let client: String?
    let device: String?
    let nowPlaying: String?
    let isTranscoding: Bool?
    let remoteIp: String?
}

struct ServerBatteryAuditResponse: Codable {
    let ok: Bool
    let mode: String?
    let iphoneTailscaleIp: String?
    let activeTrueNasSockets: Int?
    let sockets: [TrueNASSocketInfo]?
    let socketsClosed: Int?
    let jellyfinSessions: [JellyfinSessionInfo]?
    let transcodesKilled: Int?
    let cloudWorkersCleared: Int?
}

struct RadioInterfaceMetric: Identifiable {
    var id: String { category }
    let category: String
    let interfaceNames: String
    let icon: String
    let rxBytesPerSec: Double
    let txBytesPerSec: Double
    let packetsPerSec: Double
    let totalMegabytes: Double
    let isActive: Bool
}

enum ObservationSeverity {
    case good, info, warn, bad

    var color: Color {
        switch self {
        case .good:  return Color(red: 0.30, green: 0.78, blue: 0.42)
        case .info:  return Color(red: 0.45, green: 0.62, blue: 0.95)
        case .warn:  return Color(red: 0.98, green: 0.75, blue: 0.18)
        case .bad:   return Color(red: 0.98, green: 0.28, blue: 0.36)
        }
    }

    var label: String {
        switch self {
        case .good:  return "OK"
        case .info:  return "INFO"
        case .warn:  return "WATCH"
        case .bad:   return "DRAIN"
        }
    }
}

enum ObservationAction {
    case dimScreen
    case nasCleanup
    case openLowPowerSettings
    case openBatterySettings
    case openBackgroundRefreshSettings
}

struct BatteryObservation: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let severity: ObservationSeverity
    let actionLabel: String?
    let action: ObservationAction?
    let isActionable: Bool
}

// MARK: - Honest Telemetry Engine

@MainActor
final class VoltGuardEngine: ObservableObject {
    // Battery core (all real: UIDevice APIs)
    @Published var batteryPercent: Int = 85
    @Published var batteryStateText: String = "Discharging"
    @Published var isCharging: Bool = false
    @Published var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var thermalStateText: String = "Nominal"
    @Published var thermalLevel: Int = 0

    // Screen (real)
    @Published var screenBrightness: Double = 0.5
    @Published var maxRefreshHz: Int = UIScreen.main.maximumFramesPerSecond

    // Measured drain (real: computed from actual battery level deltas)
    @Published var measuredDrainPerHour: Double? = nil          // %/hr over the recent window
    @Published var measurementWindowMinutes: Int = 0
    @Published var estimatedMinutesRemaining: Int? = nil
    @Published var sessionDrainPercent: Double? = nil           // since VoltGuard opened
    @Published var isMeasuring: Bool = true

    // NAS & radios (real server/network data)
    @Published var radios: [RadioInterfaceMetric] = []
    @Published var serverSockets: [TrueNASSocketInfo] = []
    @Published var jellyfinSessions: [JellyfinSessionInfo] = []
    @Published var serverReachable: Bool = false
    @Published var lastAuditAt: Date? = nil
    @Published var lastFixResult: String? = nil

    // Observations & fixes
    @Published var observations: [BatteryObservation] = []
    @Published var history: [BatterySample] = []
    @Published var isFixingAll: Bool = false
    @Published var fixStatusBanner: String? = nil
    @Published var fixLogSteps: [String] = []
    @Published var previousBrightness: Double? = nil
    @Published var autoGuardEnabled: Bool = (UserDefaults.standard.object(forKey: "voltguard.nasGuard.enabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoGuardEnabled, forKey: "voltguard.nasGuard.enabled") }
    }

    private var timer: Timer? = nil
    private var lastGuardPassAt: Date = .distantPast
    private var prevNetSnapshot: [String: (ibytes: UInt64, obytes: UInt64, ipkts: UInt64, opkts: UInt64)] = [:]
    private var prevNetTime: Date? = nil
    private var sessionStartLevel: Int = 100
    private let historyKey = "voltguard.battery.history.v2"

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        loadHistory()
        sampleTelemetry()
        recomputeMeasurements()
        Task { await pollTrueNasaudit(fixMode: false) }

        // 30s cadence: battery deltas only move meaningfully at that scale, and a 30s
        // timer costs a fraction of what a 5s timer does. Real honesty includes our own footprint.
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.sampleTelemetry()
                self.recomputeMeasurements()
                if self.autoGuardEnabled, Date().timeIntervalSince(self.lastGuardPassAt) > 600 {
                    await self.runGuardPass(auto: true)
                }
            }
        }

        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.sampleTelemetry()
                self.recomputeMeasurements()
                Task { await self.pollTrueNasaudit(fixMode: false) }
            }
        }
    }

    // MARK: Sampling (all values are direct OS reads)

    func sampleTelemetry() {
        let rawLevel = UIDevice.current.batteryLevel
        if rawLevel >= 0 {
            batteryPercent = Int((rawLevel * 100.0).rounded())
        }
        switch UIDevice.current.batteryState {
        case .charging:
            batteryStateText = "Charging"
            isCharging = true
        case .full:
            batteryStateText = "Full (AC Power)"
            isCharging = true
        case .unplugged:
            batteryStateText = "Discharging"
            isCharging = false
        default:
            batteryStateText = "Monitoring"
            isCharging = false
        }

        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        screenBrightness = Double(UIScreen.main.brightness)
        maxRefreshHz = UIScreen.main.maximumFramesPerSecond

        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            thermalStateText = "Nominal"
            thermalLevel = 0
        case .fair:
            thermalStateText = "Warm"
            thermalLevel = 1
        case .serious:
            thermalStateText = "Hot"
            thermalLevel = 2
        case .critical:
            thermalStateText = "Critical"
            thermalLevel = 3
        @unknown default:
            thermalStateText = "Nominal"
            thermalLevel = 0
        }

        recordBatterySampleIfNeeded()
        sampleNetworkInterfaces()
        recomputeObservations()
    }

    // MARK: Measured drain math (the honest core)

    private func recordBatterySampleIfNeeded() {
        let now = Date()
        if let last = history.last {
            let same = last.level == batteryPercent && last.isCharging == isCharging
            if same && now.timeIntervalSince(last.timestamp) < 60 { return }
        } else {
            sessionStartLevel = batteryPercent
        }
        history.append(BatterySample(timestamp: now, level: batteryPercent, isCharging: isCharging))
        if history.count > 288 {  // ~6h of 60s-granularity samples
            history.removeFirst(history.count - 288)
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let saved = try? JSONDecoder().decode([BatterySample].self, from: data) else {
            history = []
            return
        }
        // Drop samples older than 12h so the measurement window stays fresh
        let cutoff = Date().addingTimeInterval(-12 * 3600)
        history = saved.filter { $0.timestamp > cutoff }
        sessionStartLevel = history.first?.level ?? batteryPercent
    }

    private func recomputeMeasurements() {
        // Short window: last ~20 minutes, discharging samples only
        let now = Date()
        let recent = history.filter { now.timeIntervalSince($0.timestamp) <= 20 * 60 && !$0.isCharging }
        if recent.count >= 2,
           let first = recent.first, let last = recent.last,
           last.level < first.level {
            let hours = now.timeIntervalSince(first.timestamp) / 3600.0
            if hours >= 0.08 {  // need ≥ ~5 min of real data
                let drop = Double(first.level - last.level)
                measuredDrainPerHour = drop / hours
                measurementWindowMinutes = Int(now.timeIntervalSince(first.timestamp) / 60.0)
                isMeasuring = false
            } else {
                isMeasuring = true
            }
        } else {
            isMeasuring = true
        }

        if let rate = measuredDrainPerHour, rate > 0.01 {
            estimatedMinutesRemaining = Int((Double(batteryPercent) / rate) * 60.0)
        } else {
            estimatedMinutesRemaining = nil
        }

        // Session drift: since VoltGuard opened (only meaningful while discharging)
        if let start = history.first(where: { now.timeIntervalSince($0.timestamp) < 12 * 3600 }), !isCharging,
           start.level > batteryPercent {
            sessionDrainPercent = Double(start.level - batteryPercent)
        } else {
            sessionDrainPercent = nil
        }
    }

    // MARK: Observations (only claims backed by a real reading)

    private func recomputeObservations() {
        var list: [BatteryObservation] = []

        // 1. Measured drain rate — the headline honest metric
        if let rate = measuredDrainPerHour {
            let sev: ObservationSeverity = rate >= 12 ? .bad : (rate >= 7 ? .warn : .good)
            list.append(BatteryObservation(
                id: "measured_drain",
                title: "Measured drain: \(String(format: "%.1f", rate))% per hour",
                subtitle: "From \(measurementWindowMinutes) min of real battery-level samples",
                detail: rate >= 7
                    ? "This is genuinely high for an iPhone. Check Settings → Battery to see which app used the most power in that window."
                    : "This is a normal-to-good discharge rate. Nothing abnormal is measurable right now.",
                icon: "chart.line.uptrend.xyaxis",
                severity: sev,
                actionLabel: rate >= 7 ? "Open Battery Usage" : nil,
                action: rate >= 7 ? .openBatterySettings : nil,
                isActionable: rate >= 7
            ))
        } else if isCharging {
            list.append(BatteryObservation(
                id: "charging",
                title: "Charging — drain measurement paused",
                subtitle: "Levels rise while plugged in, so %/hr is not computed",
                detail: "Unplug to resume real drain measurement.",
                icon: "bolt.fill",
                severity: .info,
                actionLabel: nil, action: nil, isActionable: false
            ))
        } else {
            list.append(BatteryObservation(
                id: "measuring",
                title: "Measuring real drain…",
                subtitle: "Needs ≥5 min of discharge samples",
                detail: "VoltGuard now reports only measured data. Keep the app open a few minutes and a real %/hr figure appears here.",
                icon: "hourglass",
                severity: .info,
                actionLabel: nil, action: nil, isActionable: false
            ))
        }

        // 2. Active Jellyfin transcode to this device — genuinely expensive (server CPU + steady video stream)
        let transcodeToPhone = jellyfinSessions.filter { $0.isTranscoding == true }
        if !transcodeToPhone.isEmpty {
            let names = transcodeToPhone.compactMap { $0.nowPlaying ?? $0.client }.joined(separator: ", ")
            list.append(BatteryObservation(
                id: "nas_transcode",
                title: "Jellyfin is transcoding \(transcodeToPhone.count) stream(s) to this iPhone",
                subtitle: names.isEmpty ? "Active server transcode detected" : names,
                detail: "A live transcode keeps the radio and video pipeline busy on both ends — this is one of the few drains we can actually stop.",
                icon: "play.rectangle.on.rectangle",
                severity: .bad,
                actionLabel: "Stop Transcodes",
                action: .nasCleanup,
                isActionable: true
            ))
        }

        // 3. Idle NAS sockets — real but small; state it accurately
        let idleSockets = serverSockets.count
        if idleSockets > 0 {
            list.append(BatteryObservation(
                id: "nas_sockets",
                title: "\(idleSockets) open connection(s) to TrueNAS",
                subtitle: "Idle TCP sockets — minor effect, kept in check by NAS Guard",
                detail: "Persistent sockets to your NAS cause only occasional radio wake-ups. NAS Guard closes the ones on streaming ports.",
                icon: "arrow.left.arrow.right",
                severity: idleSockets >= 4 ? .warn : .info,
                actionLabel: "Drop Idle Sockets",
                action: .nasCleanup,
                isActionable: true
            ))
        }

        // 4. Screen brightness — the one app-fixable drain with real impact
        if screenBrightness > 0.45 && !isCharging {
            list.append(BatteryObservation(
                id: "brightness",
                title: "Screen at \(Int((screenBrightness * 100).rounded()))% brightness",
                subtitle: "OLED draw scales steeply with brightness",
                detail: "Dimming to ~38% is the single most effective in-app fix. You can undo it afterwards.",
                icon: "sun.max.fill",
                severity: screenBrightness > 0.7 ? .warn : .info,
                actionLabel: "Dim to 38%",
                action: .dimScreen,
                isActionable: true
            ))
        }

        // 5. Low Power Mode at low battery
        if !isLowPowerMode && batteryPercent <= 35 {
            list.append(BatteryObservation(
                id: "low_power",
                title: "Low Power Mode is off at \(batteryPercent)% battery",
                subtitle: "iOS-side: caps background refresh & 60Hz",
                detail: "VoltGuard can't toggle it directly (Apple doesn't allow that), but we can open the right Settings page.",
                icon: "battery.25",
                severity: batteryPercent <= 20 ? .warn : .info,
                actionLabel: "Open Low Power",
                action: .openLowPowerSettings,
                isActionable: true
            ))
        }

        // 6. Thermal — real reading, real meaning
        if thermalLevel >= 2 {
            list.append(BatteryObservation(
                id: "thermal",
                title: "Device running hot (\(thermalStateText))",
                subtitle: "Heat usually means something is working hard",
                detail: "A hot iPhone is often charging + navigating/streaming. Let it cool; heat itself accelerates battery wear.",
                icon: "thermometer.high",
                severity: thermalLevel == 3 ? .bad : .warn,
                actionLabel: nil, action: nil, isActionable: false
            ))
        }

        // 7. Honesty note — always visible, always true
        list.append(BatteryObservation(
            id: "honesty_note",
            title: "iOS controls per-app battery use, not apps",
            subtitle: "What VoltGuard can & can't do",
            detail: "Apple doesn't let any app throttle other apps or read their power draw. VoltGuard shows real measurements and fixes what's genuinely fixable (screen, NAS streams/sockets). For per-app drain, use Settings → Battery.",
            icon: "info.circle",
            severity: .info,
            actionLabel: "Settings → Battery",
            action: .openBatterySettings,
            isActionable: true
        ))

        let order: [ObservationSeverity] = [.bad, .warn, .info, .good]
        observations = list.sorted { a, b in
            let ai = order.firstIndex(of: a.severity) ?? 9
            let bi = order.firstIndex(of: b.severity) ?? 9
            if ai != bi { return ai < bi }
            return a.id < b.id
        }
    }

    // MARK: Fixes (each does exactly what its label says)

    func dimToOptimal() {
        if screenBrightness > 0.40 {
            previousBrightness = screenBrightness
            UIScreen.main.brightness = 0.38
            screenBrightness = 0.38
            fixStatusBanner = "Screen dimmed to 38% — real OLED power reduction applied"
            recomputeObservations()
        }
    }

    func restorePreviousBrightness() {
        guard let prev = previousBrightness else { return }
        UIScreen.main.brightness = CGFloat(prev)
        screenBrightness = prev
        previousBrightness = nil
        fixStatusBanner = "Restored previous brightness (\(Int((prev * 100).rounded()))%)"
        recomputeObservations()
    }

    func executeObservationAction(_ observation: BatteryObservation) {
        Task {
            switch observation.action {
            case .dimScreen:
                dimToOptimal()
            case .nasCleanup:
                await runGuardPass(auto: false)
            case .openLowPowerSettings:
                openSystemSettings(path: "App-Prefs:root=BATTERY_USAGE")
            case .openBatterySettings:
                openSystemSettings(path: "App-Prefs:root=BATTERY_USAGE")
            case .openBackgroundRefreshSettings:
                openSystemSettings(path: "App-Prefs:root=General&path=AUTO_BATTERY")
            case nil:
                break
            }
        }
    }

    func executeFixAll() {
        guard !isFixingAll else { return }
        isFixingAll = true
        fixLogSteps = []

        Task {
            // Step 1: real screen fix if brightness is high
            if screenBrightness > 0.40 {
                let oldPct = Int((screenBrightness * 100).rounded())
                dimToOptimal()
                fixLogSteps.append("✓ Screen dimmed \(oldPct)% → 38% (real OLED reduction)")
            } else {
                fixLogSteps.append("✓ Screen already ≤40% — no change needed")
            }
            try? await Task.sleep(nanoseconds: 250_000_000)

            // Step 2: real server-side cleanup
            let beforeSockets = serverSockets.count
            let beforeTranscodes = jellyfinSessions.filter { $0.isTranscoding == true }.count
            await runGuardPass(auto: false)
            fixLogSteps.append("✓ NAS cleanup: \(max(0, beforeSockets - serverSockets.count)) socket(s) closed, \(max(0, beforeTranscodes - jellyfinSessions.filter { $0.isTranscoding == true }.count)) transcode(s) stopped")

            fixStatusBanner = "Real fixes applied — the rest is in iOS Settings, not apps"
            recomputeObservations()
            isFixingAll = false
        }
    }

    // MARK: NAS Guard (real: audits & cleans the TrueNAS side)

    func runGuardPass(auto: Bool) async {
        lastGuardPassAt = Date()
        await pollTrueNasaudit(fixMode: true)
        let stopped = jellyfinSessions.filter { $0.isTranscoding == true }.count
        let closed = serverSockets.count
        if !auto {
            fixStatusBanner = "NAS pass done: \(stopped) transcode stream(s) still active, \(closed) socket(s) remain"
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func pollTrueNasaudit(fixMode: Bool) async {
        let urls = [
            "http://100.85.127.42:18998/sidestore-api/\(fixMode ? "battery-fix" : "battery-audit")",
            "https://navidrome.nas-server.co.uk/sidestore-api/\(fixMode ? "battery-fix" : "battery-audit")"
        ]
        for uStr in urls {
            guard let url = URL(string: uStr) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 6.0
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    let decoded = try JSONDecoder().decode(ServerBatteryAuditResponse.self, from: data)
                    serverReachable = true
                    serverSockets = decoded.sockets ?? []
                    jellyfinSessions = decoded.jellyfinSessions ?? []
                    lastAuditAt = Date()
                    recomputeObservations()
                    return
                }
            } catch {
                continue
            }
        }
        serverReachable = false
        recomputeObservations()
    }

    // MARK: POSIX getifaddrs radio telemetry (real byte counters)

    private func sampleNetworkInterfaces() {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return }
        defer { freeifaddrs(firstAddr) }

        var grouped: [String: (names: Set<String>, ibytes: UInt64, obytes: UInt64, ipkts: UInt64, opkts: UInt64)] = [
            "Wi-Fi (en0)": ([], 0, 0, 0, 0),
            "Tailscale / VPN (utun)": ([], 0, 0, 0, 0),
            "Cellular (pdp_ip)": ([], 0, 0, 0, 0),
            "AirDrop / AWDL": ([], 0, 0, 0, 0)
        ]

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let cur = ptr {
            let name = String(cString: cur.pointee.ifa_name)
            if let addr = cur.pointee.ifa_addr, Int32(addr.pointee.sa_family) == AF_LINK,
               let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                let ib = UInt64(data.pointee.ifi_ibytes)
                let ob = UInt64(data.pointee.ifi_obytes)
                let ip = UInt64(data.pointee.ifi_ipackets)
                let op = UInt64(data.pointee.ifi_opackets)

                let bucket: String?
                if name == "en0" {
                    bucket = "Wi-Fi (en0)"
                } else if name.hasPrefix("utun") {
                    bucket = "Tailscale / VPN (utun)"
                } else if name.hasPrefix("pdp_ip") {
                    bucket = "Cellular (pdp_ip)"
                } else if name.hasPrefix("awdl") || name.hasPrefix("llw") {
                    bucket = "AirDrop / AWDL"
                } else {
                    bucket = nil
                }

                if let b = bucket, var entry = grouped[b] {
                    entry.names.insert(name)
                    entry.ibytes &+= ib
                    entry.obytes &+= ob
                    entry.ipkts &+= ip
                    entry.opkts &+= op
                    grouped[b] = entry
                }
            }
            ptr = cur.pointee.ifa_next
        }

        let now = Date()
        let dt = prevNetTime.map { max(5.0, now.timeIntervalSince($0)) } ?? 30.0
        var out: [RadioInterfaceMetric] = []

        let order: [(String, String)] = [
            ("Wi-Fi (en0)", "wifi"),
            ("Tailscale / VPN (utun)", "network.badge.shield.half.filled"),
            ("Cellular (pdp_ip)", "antenna.radiowaves.left.and.right"),
            ("AirDrop / AWDL", "dot.radiowaves.left.and.right")
        ]

        for (cat, icon) in order {
            guard let cur = grouped[cat] else { continue }
            var rxRate = 0.0
            var txRate = 0.0
            var pktRate = 0.0
            if let prev = prevNetSnapshot[cat] {
                let dIn = cur.ibytes >= prev.ibytes ? (cur.ibytes - prev.ibytes) : 0
                let dOut = cur.obytes >= prev.obytes ? (cur.obytes - prev.obytes) : 0
                let dPkt = (cur.ipkts + cur.opkts) >= (prev.ipkts + prev.opkts)
                    ? ((cur.ipkts + cur.opkts) - (prev.ipkts + prev.opkts)) : 0
                rxRate = Double(dIn) / dt
                txRate = Double(dOut) / dt
                pktRate = Double(dPkt) / dt
            }
            prevNetSnapshot[cat] = (cur.ibytes, cur.obytes, cur.ipkts, cur.opkts)
            let totalMB = Double(cur.ibytes + cur.obytes) / (1024.0 * 1024.0)
            let namesList = cur.names.sorted().joined(separator: ", ")
            out.append(RadioInterfaceMetric(
                category: cat,
                interfaceNames: namesList.isEmpty ? "idle" : namesList,
                icon: icon,
                rxBytesPerSec: rxRate,
                txBytesPerSec: txRate,
                packetsPerSec: pktRate,
                totalMegabytes: totalMB,
                isActive: pktRate > 1.0
            ))
        }
        prevNetTime = now
        radios = out
    }

    func openSystemSettings(path: String) {
        let candidates = [path, path.replacingOccurrences(of: "App-Prefs:", with: "prefs:"), UIApplication.openSettingsURLString]
        for c in candidates {
            if let u = URL(string: c), UIApplication.shared.canOpenURL(u) {
                UIApplication.shared.open(u)
                return
            }
        }
    }
}

// MARK: - Main App & Views

@main
struct VoltGuardApp: App {
    @StateObject private var engine = VoltGuardEngine()

    var body: some Scene {
        WindowGroup {
            VoltGuardRootView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}

struct VoltGuardRootView: View {
    @EnvironmentObject var engine: VoltGuardEngine
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MonitorView()
                .tabItem { Label("Monitor", systemImage: "bolt.shield.fill") }
                .tag(0)

            RadiosAndServerView()
                .tabItem { Label("NAS & Radios", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(1)

            DrainTrendView()
                .tabItem { Label("Trend", systemImage: "chart.xyaxis.line") }
                .tag(2)
        }
        .tint(Color(red: 0.83, green: 0.09, blue: 0.23))
    }
}

// MARK: - Tab 1: Monitor

struct MonitorView: View {
    @EnvironmentObject var engine: VoltGuardEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    BatteryHeroCard()
                    RealFixesCard()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("WHAT'S REALLY HAPPENING", systemImage: "eye.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(red: 0.83, green: 0.09, blue: 0.23))
                            Spacer()
                            Text(engine.isCharging ? "charging" : "discharging")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        ForEach(engine.observations) { observation in
                            ObservationRowCard(observation: observation)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.02, green: 0.008, blue: 0.012).ignoresSafeArea())
            .navigationTitle("VoltGuard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        engine.sampleTelemetry()
                        Task { await engine.pollTrueNasaudit(fixMode: false) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

struct BatteryHeroCard: View {
    @EnvironmentObject var engine: VoltGuardEngine

    var drainColor: Color {
        guard let rate = engine.measuredDrainPerHour else { return .gray }
        if rate >= 12 { return Color(red: 0.98, green: 0.28, blue: 0.36) }
        if rate >= 7 { return Color(red: 0.98, green: 0.75, blue: 0.18) }
        return Color(red: 0.30, green: 0.78, blue: 0.42)
    }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 12)
                    .frame(width: 108, height: 108)

                Circle()
                    .trim(from: 0, to: CGFloat(max(0.04, Double(engine.batteryPercent) / 100.0)))
                    .stroke(
                        AngularGradient(
                            colors: [drainColor.opacity(0.7), drainColor],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 108, height: 108)

                VStack(spacing: 2) {
                    Text("\(engine.batteryPercent)%")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(engine.batteryStateText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(drainColor)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if engine.isCharging {
                    Label("Charging — drain paused", systemImage: "bolt.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                } else if let rate = engine.measuredDrainPerHour {
                    Label(String(format: "%.1f%% per hour (measured)", rate), systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("over the last \(engine.measurementWindowMinutes) min of real samples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Measuring real drain…", systemImage: "hourglass")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("needs ≥5 min of discharge data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !engine.isCharging, let mins = engine.estimatedMinutesRemaining {
                    Text("≈ \(mins / 60)h \(mins % 60)m remaining at this rate")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let drift = engine.sessionDrainPercent {
                    Text("Session so far: −\(String(format: "%.0f", drift))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.07, green: 0.024, blue: 0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(drainColor.opacity(0.32), lineWidth: 1)
                )
        )
    }
}

struct RealFixesCard: View {
    @EnvironmentObject var engine: VoltGuardEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title3)
                    .foregroundStyle(Color(red: 0.86, green: 0.14, blue: 0.28))
                VStack(alignment: .leading, spacing: 2) {
                    Text("REAL FIXES ONLY")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.white)
                    Text("Screen brightness + TrueNAS streams/sockets. No simulated results.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $engine.autoGuardEnabled)
                    .labelsHidden()
                    .tint(Color(red: 0.83, green: 0.09, blue: 0.23))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.024, blue: 0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(red: 0.83, green: 0.09, blue: 0.23).opacity(0.45), lineWidth: 1)
                    )
            )

            Button {
                engine.executeFixAll()
            } label: {
                HStack(spacing: 12) {
                    if engine.isFixingAll {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.title3.weight(.bold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.isFixingAll ? "APPLYING REAL FIXES..." : "APPLY REAL FIXES")
                            .font(.headline.weight(.heavy))
                        Text("Dims screen if it's bright • stops stuck NAS transcodes & drops idle sockets")
                            .font(.caption2)
                            .opacity(0.88)
                    }
                    Spacer()
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.86, green: 0.12, blue: 0.26),
                            Color(red: 0.55, green: 0.05, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color(red: 0.83, green: 0.09, blue: 0.23).opacity(0.35), radius: 12, y: 4)
            }
            .disabled(engine.isFixingAll)

            if engine.autoGuardEnabled {
                Text("NAS Guard is on: every 10 min it stops orphaned Jellyfin transcodes and closes idle streaming sockets.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let banner = engine.fixStatusBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.86, green: 0.12, blue: 0.26))
                    Text(banner)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                    Spacer()
                    if engine.previousBrightness != nil {
                        Button("Undo Dim") {
                            engine.restorePreviousBrightness()
                        }
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !engine.fixLogSteps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(engine.fixLogSteps, id: \.self) { step in
                        Text(step)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Color(red: 0.94, green: 0.89, blue: 0.88))
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

struct ObservationRowCard: View {
    @EnvironmentObject var engine: VoltGuardEngine
    let observation: BatteryObservation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(observation.severity.color.opacity(0.16))
                        .frame(width: 42, height: 42)
                    Image(systemName: observation.icon)
                        .font(.headline)
                        .foregroundStyle(observation.severity.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(observation.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text(observation.severity.label)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(observation.severity.color.opacity(0.18))
                            .foregroundStyle(observation.severity.color)
                            .clipShape(Capsule())
                    }

                    Text(observation.subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(observation.severity.color)
                }
            }

            Text(observation.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if observation.isActionable, let label = observation.actionLabel, observation.action != nil {
                HStack {
                    Spacer()
                    Button {
                        engine.executeObservationAction(observation)
                    } label: {
                        Text(label)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.83, green: 0.09, blue: 0.23))
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.07, green: 0.024, blue: 0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(observation.severity.color.opacity(0.26), lineWidth: 1)
                )
        )
    }
}

// MARK: - Tab 2: NAS & Radios

struct RadiosAndServerView: View {
    @EnvironmentObject var engine: VoltGuardEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("REAL RADIO INTERFACES (LIVE BYTE COUNTERS)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(red: 0.83, green: 0.09, blue: 0.23))
                            Spacer()
                            Text("30s refresh")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(engine.radios) { radio in
                            HStack(spacing: 12) {
                                Image(systemName: radio.icon)
                                    .font(.title3)
                                    .foregroundStyle(radio.isActive ? Color(red: 0.98, green: 0.75, blue: 0.18) : Color(red: 0.83, green: 0.09, blue: 0.23))
                                    .frame(width: 34)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(radio.category)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white)
                                    Text("Interfaces: \(radio.interfaceNames) • Total: \(String(format: "%.1f MB", radio.totalMegabytes))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(String(format: "%.1f pkt/s", radio.packetsPerSec))
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(radio.isActive ? Color(red: 0.98, green: 0.75, blue: 0.18) : .gray)
                                    Text(String(format: "↓%.1f ↑%.1f KB/s", radio.rxBytesPerSec / 1024.0, radio.txBytesPerSec / 1024.0))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(red: 0.07, green: 0.024, blue: 0.035))
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("TRUENAS CONNECTIONS & JELLYFIN SESSIONS")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(red: 0.83, green: 0.09, blue: 0.23))
                            Spacer()
                            Button("Clean Up Now") {
                                Task { await engine.runGuardPass(auto: false) }
                            }
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.83, green: 0.09, blue: 0.23))
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                        }

                        if !engine.serverReachable {
                            HStack(spacing: 10) {
                                Image(systemName: "wifi.slash")
                                    .foregroundStyle(.orange)
                                Text("TrueNAS unreachable — the NAS Guard endpoint responds over Tailscale or your home network.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.07, green: 0.024, blue: 0.035)))
                        }

                        if engine.jellyfinSessions.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.42))
                                Text("No active Jellyfin sessions — nothing transcoding to your iPhone.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.07, green: 0.024, blue: 0.035)))
                        } else {
                            ForEach(engine.jellyfinSessions) { session in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(session.nowPlaying ?? session.client ?? "Jellyfin Session")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                        Text("\(session.device ?? "") • \(session.client ?? "")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if session.isTranscoding == true {
                                        Text("TRANSCODING")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color(red: 0.98, green: 0.28, blue: 0.36).opacity(0.2))
                                            .foregroundStyle(Color(red: 0.98, green: 0.28, blue: 0.36))
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.07, green: 0.024, blue: 0.035)))
                            }
                        }

                        if !engine.serverSockets.isEmpty {
                            ForEach(engine.serverSockets) { sock in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(sock.service ?? "TrueNAS Socket")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.white)
                                        Text("\(sock.local) ↔ \(sock.remote)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(sock.state)
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.08))
                                        .foregroundStyle(.secondary)
                                        .clipShape(Capsule())
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.07, green: 0.024, blue: 0.035)))
                            }
                        }

                        if let audited = engine.lastAuditAt {
                            Text("Last NAS audit: \(audited, style: .time)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.02, green: 0.008, blue: 0.012).ignoresSafeArea())
            .navigationTitle("NAS & Radios")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Tab 3: Drain Trend (real samples)

struct DrainTrendView: View {
    @EnvironmentObject var engine: VoltGuardEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(engine.measuredDrainPerHour.map { String(format: "%.1f%%/hr", $0) } ?? "--")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(red: 0.83, green: 0.09, blue: 0.23))
                            Text("Measured discharge rate (last 20 min window)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(engine.history.count)")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text("real samples stored (6h)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.07, green: 0.024, blue: 0.035)))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("BATTERY LEVEL LOG (REAL READINGS)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(red: 0.83, green: 0.09, blue: 0.23))

                        ForEach(engine.history.suffix(20).reversed()) { pt in
                            HStack {
                                Text(pt.timestamp, style: .time)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(pt.isCharging ? "⚡ charging" : "on battery")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(pt.level)%")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.07, green: 0.024, blue: 0.035)))
                        }

                        if engine.history.isEmpty {
                            Text("No samples yet — keep the app open and the log will build from real battery readings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(14)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.02, green: 0.008, blue: 0.012).ignoresSafeArea())
            .navigationTitle("Drain Trend")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
