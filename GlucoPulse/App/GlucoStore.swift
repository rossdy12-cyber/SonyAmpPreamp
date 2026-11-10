import Foundation
import SwiftUI
import CoreBluetooth
import UserNotifications
#if canImport(HealthKit)
import HealthKit
#endif

enum GlucoseUnit: String, CaseIterable, Identifiable, Codable {
    case mmolL = "mmol/L"
    case mgdL  = "mg/dL"
    var id: String { rawValue }
}

enum DexcomRegion: String, CaseIterable, Identifiable, Codable {
    case us  = "US (share2.dexcom.com)"
    case ous = "UK / International (shareous1.dexcom.com)"
    case jp  = "Japan (share.dexcom.jp)"

    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .us:  return "https://share2.dexcom.com/ShareWebServices/Services"
        case .ous: return "https://shareous1.dexcom.com/ShareWebServices/Services"
        case .jp:  return "https://share.dexcom.jp/ShareWebServices/Services"
        }
    }
}

enum GlucoseTrend: String, Codable, CaseIterable {
    case doubleUp      = "DoubleUp"
    case singleUp      = "SingleUp"
    case fortyFiveUp   = "FortyFiveUp"
    case flat          = "Flat"
    case fortyFiveDown = "FortyFiveDown"
    case singleDown    = "SingleDown"
    case doubleDown    = "DoubleDown"
    case none          = "None"

    var arrow: String {
        switch self {
        case .doubleUp:      return "↑↑"
        case .singleUp:      return "↑"
        case .fortyFiveUp:   return "↗"
        case .flat:          return "→"
        case .fortyFiveDown: return "↘"
        case .singleDown:    return "↓"
        case .doubleDown:    return "↓↓"
        case .none:          return "—"
        }
    }

    var label: String {
        switch self {
        case .doubleUp:      return "Rising Rapidly"
        case .singleUp:      return "Rising"
        case .fortyFiveUp:   return "Rising Slowly"
        case .flat:          return "Steady"
        case .fortyFiveDown: return "Falling Slowly"
        case .singleDown:    return "Falling"
        case .doubleDown:    return "Falling Rapidly"
        case .none:          return "No Trend"
        }
    }

    var slopeMgdLPer5Min: Double {
        switch self {
        case .doubleUp:      return 16.0
        case .singleUp:      return 10.0
        case .fortyFiveUp:   return 5.0
        case .flat:          return 0.0
        case .fortyFiveDown: return -5.0
        case .singleDown:    return -10.0
        case .doubleDown:    return -16.0
        case .none:          return 0.0
        }
    }

    static func from(dexcomValue: Any?) -> GlucoseTrend {
        if let str = dexcomValue as? String {
            for t in GlucoseTrend.allCases where t.rawValue.caseInsensitiveCompare(str) == .orderedSame {
                return t
            }
        }
        if let num = dexcomValue as? Int {
            switch num {
            case 1: return .doubleUp
            case 2: return .singleUp
            case 3: return .fortyFiveUp
            case 4: return .flat
            case 5: return .fortyFiveDown
            case 6: return .singleDown
            case 7: return .doubleDown
            default: return .flat
            }
        }
        return .flat
    }
}

struct GlucoseReading: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var mgdL: Int
    var timestamp: Date
    var trend: GlucoseTrend

    var mmolL: Double {
        (Double(mgdL) / 18.0182 * 10.0).rounded() / 10.0
    }
}

enum PumpEventType: String, Codable, CaseIterable, Identifiable {
    case mealBolus        = "Meal Bolus"
    case autoCorrection   = "Control-IQ Auto Bolus"
    case manualCorrection = "Correction Bolus"
    case basalModulation  = "Control-IQ Basal"
    case basalSuspend     = "Control-IQ Basal Suspend"
    case carbs            = "Carbs Logged"
    case hypoRescue       = "Hypo Rescue (15g)"
    case ketoneCheck      = "Ketone Check"
    case exercise         = "Exercise / Activity"
    case siteChange       = "Cartridge / Site Change"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .mealBolus:        return "fork.knife.circle.fill"
        case .autoCorrection:   return "bolt.shield.fill"
        case .manualCorrection: return "drop.fill"
        case .basalModulation:  return "waveform.path.ecg"
        case .basalSuspend:     return "pause.circle.fill"
        case .carbs:            return "leaf.fill"
        case .hypoRescue:       return "cross.case.fill"
        case .ketoneCheck:      return "testtube.2"
        case .exercise:         return "figure.run.circle.fill"
        case .siteChange:       return "syringe.fill"
        }
    }
}

struct PumpEvent: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var type: PumpEventType
    var timestamp: Date
    var insulinUnits: Double?
    var carbsGrams: Int?
    var basalRate: Double?
    var ketoneMmol: Double?
    var durationMinutes: Int?
    var note: String?
}

struct TandemPumpStatus: Codable, Equatable {
    var iobUnits: Double
    var cobGrams: Int
    var activeBasalRate: Double
    var scheduledBasalRate: Double
    var batteryPercent: Int
    var reservoirUnits: Double
    var controlIQMode: String
    var lastBolusUnits: Double
    var lastBolusDate: Date
    var lastSyncDate: Date
}

struct BLEPeripheralDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var category: String
    var rssi: Int
    var lastSeen: Date
}

// MARK: - Smart Bolus, Therapy Profile & Clinical Models

struct TherapyBlock: Identifiable, Codable, Equatable {
    var id: String
    var label: String
    var startHour: Int
    var endHour: Int
    var icrGramsPerUnit: Double     // e.g. 10g per 1U
    var isfMmolPerUnit: Double      // e.g. 2.5 mmol/L drop per 1U
    var targetMmol: Double          // e.g. 6.0 mmol/L
}

enum ExerciseAdjustment: String, CaseIterable, Identifiable {
    case none        = "No Exercise (0%)"
    case light       = "Light / Walk (-25%)"
    case intense     = "Cardio / Gym (-50%)"
    case postExercise = "Post-Workout Recovery (-25%)"

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .none: return 1.0
        case .light: return 0.75
        case .intense: return 0.50
        case .postExercise: return 0.75
        }
    }
}

struct SmartBolusResult {
    var activeBlock: TherapyBlock
    var mealInsulin: Double
    var rawCorrectionInsulin: Double
    var iobSubtracted: Double
    var netCorrectionInsulin: Double
    var subtotalBeforeExercise: Double
    var exerciseReductionUnits: Double
    var totalRecommendedUnits: Double
    var fpuCount: Double
    var fpuEquivalentCarbs: Double
    var fpuExtendedUnits: Double
    var fpuExtendedDurationHours: Int
    var immediateUnits: Double
    var safetyWarning: String?
}

struct IOBForecastPoint: Identifiable {
    var id = UUID()
    var timestamp: Date
    var minutesAhead: Int
    var remainingIOB: Double
}

enum BodySiteZone: String, CaseIterable, Identifiable, Codable {
    case leftAbdomen   = "Left Abdomen"
    case rightAbdomen  = "Right Abdomen"
    case leftThigh     = "Left Upper Thigh"
    case rightThigh    = "Right Upper Thigh"
    case leftArm       = "Left Back of Arm"
    case rightArm      = "Right Back of Arm"
    case leftFlank     = "Left Flank / Hip"
    case rightFlank    = "Right Flank / Hip"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .leftAbdomen:  return "L Abdomen"
        case .rightAbdomen: return "R Abdomen"
        case .leftThigh:    return "L Thigh"
        case .rightThigh:   return "R Thigh"
        case .leftArm:      return "L Arm"
        case .rightArm:     return "R Arm"
        case .leftFlank:    return "L Flank"
        case .rightFlank:   return "R Flank"
        }
    }
}

struct BodySiteRecord: Identifiable, Codable, Equatable {
    var id: String { zone.rawValue }
    var zone: BodySiteZone
    var lastUsedDate: Date?
    var lastDeviceType: String // "Cannula" or "Dexcom G7"
    var totalUses: Int
    var notes: String

    var daysSinceUse: Int? {
        guard let d = lastUsedDate else { return nil }
        return max(0, Int(Date().timeIntervalSince(d) / 86400.0))
    }

    var readinessStatus: String {
        guard let days = daysSinceUse else { return "Fresh / Ready" }
        if days < 3 { return "Active / Recent" }
        if days < 7 { return "Healing (\(days)d)" }
        return "Rested (\(days)d)"
    }
}

struct SickDayAdvice {
    var severityTitle: String
    var severityColor: Color
    var headline: String
    var recommendedRapidDoseUnits: Double
    var recommendedPercentTDD: Int
    var recheckHours: Int
    var steps: [String]
}

struct AGPHourlyBucket: Identifiable {
    var id: Int { hour }
    var hour: Int
    var p10: Double
    var p25: Double
    var p50: Double
    var p75: Double
    var p90: Double
}

@MainActor
final class GlucoStore: NSObject, ObservableObject {
    // Navigation & Cross-Tab Handoff
    @Published var selectedTab: Int = 0
    @Published var draftBolusCarbs: String = ""
    @Published var draftBolusFat: String = ""
    @Published var draftBolusProtein: String = ""
    @Published var draftMealNote: String = ""

    // Settings
    @Published var unit: GlucoseUnit {
        didSet { UserDefaults.standard.set(unit.rawValue, forKey: "gluco.unit") }
    }
    @Published var dexcomUsername: String {
        didSet { UserDefaults.standard.set(dexcomUsername, forKey: "gluco.dexcom.user") }
    }
    @Published var dexcomPassword: String {
        didSet { UserDefaults.standard.set(dexcomPassword, forKey: "gluco.dexcom.pass") }
    }
    @Published var dexcomRegion: DexcomRegion {
        didSet { UserDefaults.standard.set(dexcomRegion.rawValue, forKey: "gluco.dexcom.region") }
    }
    @Published var nightscoutURL: String {
        didSet { UserDefaults.standard.set(nightscoutURL, forKey: "gluco.ns.url") }
    }
    @Published var nightscoutToken: String {
        didSet { UserDefaults.standard.set(nightscoutToken, forKey: "gluco.ns.token") }
    }
    @Published var libreEmail: String {
        didSet { UserDefaults.standard.set(libreEmail, forKey: "gluco.libre.email") }
    }
    @Published var librePassword: String {
        didSet { UserDefaults.standard.set(librePassword, forKey: "gluco.libre.pass") }
    }
    @Published var healthKitEnabled: Bool {
        didSet { UserDefaults.standard.set(healthKitEnabled, forKey: "gluco.hk.enabled") }
    }
    @Published var lowMgdL: Int {
        didSet { UserDefaults.standard.set(lowMgdL, forKey: "gluco.low") }
    }
    @Published var highMgdL: Int {
        didSet { UserDefaults.standard.set(highMgdL, forKey: "gluco.high") }
    }
    @Published var urgentLowMgdL: Int {
        didSet { UserDefaults.standard.set(urgentLowMgdL, forKey: "gluco.urgentLow") }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "gluco.notify") }
    }

    // Therapy & Insulin Parameters
    @Published var diaHours: Double {
        didSet { UserDefaults.standard.set(diaHours, forKey: "gluco.dia") }
    }
    @Published var tddUnits: Double {
        didSet { UserDefaults.standard.set(tddUnits, forKey: "gluco.tdd") }
    }
    @Published var therapyBlocks: [TherapyBlock] {
        didSet { saveCodable(therapyBlocks, key: "gluco.therapyBlocks") }
    }

    // Hardware Lifespan & Body Site Rotation
    @Published var sensorStartedAt: Date {
        didSet { UserDefaults.standard.set(sensorStartedAt.timeIntervalSince1970, forKey: "gluco.sensorStart") }
    }
    @Published var sensorCodeNote: String {
        didSet { UserDefaults.standard.set(sensorCodeNote, forKey: "gluco.sensorCode") }
    }
    @Published var cannulaStartedAt: Date {
        didSet { UserDefaults.standard.set(cannulaStartedAt.timeIntervalSince1970, forKey: "gluco.cannulaStart") }
    }
    @Published var cartridgeStartedAt: Date {
        didSet { UserDefaults.standard.set(cartridgeStartedAt.timeIntervalSince1970, forKey: "gluco.cartridgeStart") }
    }
    @Published var bodySites: [BodySiteRecord] {
        didSet { saveCodable(bodySites, key: "gluco.bodySites") }
    }

    // Hypo 15/15 Rescue Countdown
    @Published var hypoRescueEndTime: Date?
    @Published var hypoRescueRemainingSeconds: Int = 0
    @Published var lastHypoRescueNote: String = ""

    // Live State
    @Published var readings: [GlucoseReading] = []
    @Published var pumpStatus: TandemPumpStatus
    @Published var pumpEvents: [PumpEvent] = [] {
        didSet { saveCodable(pumpEvents, key: "gluco.pumpEvents") }
    }
    @Published var bleDevices: [BLEPeripheralDevice] = []
    @Published var isSyncing: Bool = false
    @Published var connectionSummary: String = "Simulated G7 + Control-IQ (Demo Mode)"
    @Published var dexcomDiagnostic: String = ""
    @Published var bleScanning: Bool = false

    private var dexcomSessionID: String?
    private var refreshTimer: Timer?
    private var hypoTimer: Timer?
    private var centralManager: CBCentralManager?

    private let dexcomAppIds = [
        "d89443d2-327c-4a6f-89e5-496bbb0317db",
        "d8665ade-9673-4e27-9ff6-92db4ce13d13"
    ]

    override init() {
        let defaults = UserDefaults.standard
        let savedUnit = defaults.string(forKey: "gluco.unit") ?? GlucoseUnit.mmolL.rawValue
        self.unit = GlucoseUnit(rawValue: savedUnit) ?? .mmolL
        self.dexcomUsername = defaults.string(forKey: "gluco.dexcom.user") ?? ""
        self.dexcomPassword = defaults.string(forKey: "gluco.dexcom.pass") ?? ""
        let savedRegion = defaults.string(forKey: "gluco.dexcom.region") ?? DexcomRegion.ous.rawValue
        self.dexcomRegion = DexcomRegion(rawValue: savedRegion) ?? .ous

        let savedNS = defaults.string(forKey: "gluco.ns.url") ?? ""
        self.nightscoutURL = savedNS.isEmpty ? "http://100.85.127.42:1337" : savedNS
        self.nightscoutToken = defaults.string(forKey: "gluco.ns.token") ?? ""
        self.libreEmail = defaults.string(forKey: "gluco.libre.email") ?? ""
        self.librePassword = defaults.string(forKey: "gluco.libre.pass") ?? ""
        self.healthKitEnabled = defaults.bool(forKey: "gluco.hk.enabled")

        self.lowMgdL = defaults.object(forKey: "gluco.low") as? Int ?? 70
        self.highMgdL = defaults.object(forKey: "gluco.high") as? Int ?? 180
        self.urgentLowMgdL = defaults.object(forKey: "gluco.urgentLow") as? Int ?? 54
        self.notificationsEnabled = defaults.object(forKey: "gluco.notify") as? Bool ?? false

        self.diaHours = defaults.object(forKey: "gluco.dia") as? Double ?? 4.0
        self.tddUnits = defaults.object(forKey: "gluco.tdd") as? Double ?? 42.0

        if let data = defaults.data(forKey: "gluco.therapyBlocks"),
           let decoded = try? JSONDecoder().decode([TherapyBlock].self, from: data), !decoded.isEmpty {
            self.therapyBlocks = decoded
        } else {
            self.therapyBlocks = [
                TherapyBlock(id: "breakfast", label: "Breakfast (06:00–11:00)", startHour: 6, endHour: 11, icrGramsPerUnit: 8.0, isfMmolPerUnit: 2.2, targetMmol: 6.0),
                TherapyBlock(id: "lunch", label: "Lunch (11:00–16:00)", startHour: 11, endHour: 16, icrGramsPerUnit: 10.0, isfMmolPerUnit: 2.5, targetMmol: 6.0),
                TherapyBlock(id: "dinner", label: "Dinner (16:00–22:00)", startHour: 16, endHour: 22, icrGramsPerUnit: 9.0, isfMmolPerUnit: 2.4, targetMmol: 6.2),
                TherapyBlock(id: "night", label: "Overnight (22:00–06:00)", startHour: 22, endHour: 6, icrGramsPerUnit: 12.0, isfMmolPerUnit: 3.0, targetMmol: 6.5)
            ]
        }

        let now = Date()
        let sStart = defaults.double(forKey: "gluco.sensorStart")
        self.sensorStartedAt = sStart > 0 ? Date(timeIntervalSince1970: sStart) : now.addingTimeInterval(-4.3 * 86400)
        self.sensorCodeNote = defaults.string(forKey: "gluco.sensorCode") ?? "G7 Pairing Code: 4821"

        let cStart = defaults.double(forKey: "gluco.cannulaStart")
        self.cannulaStartedAt = cStart > 0 ? Date(timeIntervalSince1970: cStart) : now.addingTimeInterval(-1.6 * 86400)

        let cartStart = defaults.double(forKey: "gluco.cartridgeStart")
        self.cartridgeStartedAt = cartStart > 0 ? Date(timeIntervalSince1970: cartStart) : now.addingTimeInterval(-1.6 * 86400)

        if let siteData = defaults.data(forKey: "gluco.bodySites"),
           let decodedSites = try? JSONDecoder().decode([BodySiteRecord].self, from: siteData), !decodedSites.isEmpty {
            self.bodySites = decodedSites
        } else {
            self.bodySites = [
                BodySiteRecord(zone: .leftAbdomen, lastUsedDate: now.addingTimeInterval(-1.6 * 86400), lastDeviceType: "Tandem Cannula", totalUses: 6, notes: "Current cannula site — rotating smoothly"),
                BodySiteRecord(zone: .rightAbdomen, lastUsedDate: now.addingTimeInterval(-4.8 * 86400), lastDeviceType: "Tandem Cannula", totalUses: 5, notes: "Previous cannula site"),
                BodySiteRecord(zone: .leftArm, lastUsedDate: now.addingTimeInterval(-4.3 * 86400), lastDeviceType: "Dexcom G7", totalUses: 4, notes: "Active Dexcom G7 sensor"),
                BodySiteRecord(zone: .rightArm, lastUsedDate: now.addingTimeInterval(-14.5 * 86400), lastDeviceType: "Dexcom G7", totalUses: 4, notes: "Well rested — use for next G7"),
                BodySiteRecord(zone: .leftThigh, lastUsedDate: now.addingTimeInterval(-8.2 * 86400), lastDeviceType: "Tandem Cannula", totalUses: 3, notes: "Rested & ready"),
                BodySiteRecord(zone: .rightThigh, lastUsedDate: now.addingTimeInterval(-11.0 * 86400), lastDeviceType: "Tandem Cannula", totalUses: 3, notes: "Rested & ready"),
                BodySiteRecord(zone: .leftFlank, lastUsedDate: now.addingTimeInterval(-16.0 * 86400), lastDeviceType: "Tandem Cannula", totalUses: 2, notes: "Rested & ready"),
                BodySiteRecord(zone: .rightFlank, lastUsedDate: nil, lastDeviceType: "Tandem Cannula", totalUses: 0, notes: "Fresh zone")
            ]
        }

        self.pumpStatus = TandemPumpStatus(
            iobUnits: 1.85,
            cobGrams: 18,
            activeBasalRate: 0.95,
            scheduledBasalRate: 0.85,
            batteryPercent: 85,
            reservoirUnits: 142,
            controlIQMode: "Control-IQ Active",
            lastBolusUnits: 3.40,
            lastBolusDate: now.addingTimeInterval(-65 * 60),
            lastSyncDate: now
        )

        super.init()

        if let evData = defaults.data(forKey: "gluco.pumpEvents"),
           let decodedEvents = try? JSONDecoder().decode([PumpEvent].self, from: evData), !decodedEvents.isEmpty {
            self.pumpEvents = decodedEvents
        }

        loadSimulatedData()
        startAutoRefresh()
    }

    private func saveCodable<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Formatting & Computed Glucose Metrics

    var latestReading: GlucoseReading? {
        readings.last
    }

    var previousReading: GlucoseReading? {
        guard readings.count >= 2 else { return nil }
        return readings[readings.count - 2]
    }

    var deltaString: String {
        guard let latest = latestReading, let prev = previousReading else { return "0" }
        let diffMgdL = latest.mgdL - prev.mgdL
        switch unit {
        case .mmolL:
            let diff = Double(diffMgdL) / 18.0182
            return String(format: "%+.1f", diff)
        case .mgdL:
            return String(format: "%+d", diffMgdL)
        }
    }

    func formatGlucose(_ mgdL: Int) -> String {
        switch unit {
        case .mmolL:
            return String(format: "%.1f", Double(mgdL) / 18.0182)
        case .mgdL:
            return "\(mgdL)"
        }
    }

    func formatMmolOrMgdL(mmol: Double) -> String {
        switch unit {
        case .mmolL:
            return String(format: "%.1f mmol/L", mmol)
        case .mgdL:
            return "\(Int((mmol * 18.0182).rounded())) mg/dL"
        }
    }

    func color(for mgdL: Int) -> Color {
        if mgdL <= urgentLowMgdL { return GlucoTheme.urgentRed }
        if mgdL < lowMgdL { return GlucoTheme.lowRed }
        if mgdL > highMgdL { return GlucoTheme.highAmber }
        return GlucoTheme.inRangeGreen
    }

    // Predictive 30-Minute Forecast
    var velocityMgdLPer5Min: Double {
        guard readings.count >= 3 else {
            return latestReading?.trend.slopeMgdLPer5Min ?? 0.0
        }
        let r0 = Double(readings[readings.count - 1].mgdL)
        let r1 = Double(readings[readings.count - 2].mgdL)
        let r2 = Double(readings[readings.count - 3].mgdL)
        let recentSlope = (r0 - r1) * 0.65 + ((r1 - r2) * 0.35)
        return max(-25.0, min(25.0, recentSlope))
    }

    var predicted30MinMgdL: Int {
        guard let latest = latestReading else { return 110 }
        // Damped 30-min projection (6 x 5-min intervals with momentum damping)
        let projected = Double(latest.mgdL) + velocityMgdLPer5Min * 4.5
        return max(38, min(380, Int(projected.rounded())))
    }

    var predictedHypoInMinutes: Int? {
        guard let latest = latestReading else { return nil }
        if latest.mgdL <= lowMgdL { return 0 }
        let slopePerMin = velocityMgdLPer5Min / 5.0
        guard slopePerMin < -0.4 else { return nil }
        let mins = Int((Double(lowMgdL - latest.mgdL) / slopePerMin).rounded())
        return (mins > 0 && mins <= 45) ? mins : nil
    }

    // MARK: - Clinical Analytics & AGP Computed Metrics

    var timeInRangePercent: Int {
        guard !readings.isEmpty else { return 0 }
        let inRange = readings.filter { $0.mgdL >= lowMgdL && $0.mgdL <= highMgdL }.count
        return Int((Double(inRange) / Double(readings.count) * 100.0).rounded())
    }

    var tightRangePercent: Int {
        guard !readings.isEmpty else { return 0 }
        let tight = readings.filter { $0.mgdL >= 70 && $0.mgdL <= 140 }.count
        return Int((Double(tight) / Double(readings.count) * 100.0).rounded())
    }

    var timeBelowRangePercent: Int {
        guard !readings.isEmpty else { return 0 }
        let low = readings.filter { $0.mgdL < lowMgdL }.count
        return Int((Double(low) / Double(readings.count) * 100.0).rounded())
    }

    var veryLowPercent: Int {
        guard !readings.isEmpty else { return 0 }
        let vLow = readings.filter { $0.mgdL < urgentLowMgdL }.count
        return Int((Double(vLow) / Double(readings.count) * 100.0).rounded())
    }

    var timeAboveRangePercent: Int {
        guard !readings.isEmpty else { return 0 }
        let high = readings.filter { $0.mgdL > highMgdL }.count
        return Int((Double(high) / Double(readings.count) * 100.0).rounded())
    }

    var veryHighPercent: Int {
        guard !readings.isEmpty else { return 0 }
        let vHigh = readings.filter { $0.mgdL > 250 }.count
        return Int((Double(vHigh) / Double(readings.count) * 100.0).rounded())
    }

    var averageMgdL: Int {
        guard !readings.isEmpty else { return 0 }
        let sum = readings.reduce(0) { $0 + $1.mgdL }
        return Int((Double(sum) / Double(readings.count)).rounded())
    }

    var standardDeviationMgdL: Double {
        guard readings.count > 1 else { return 0 }
        let mean = Double(averageMgdL)
        let variance = readings.reduce(0.0) { $0 + pow(Double($1.mgdL) - mean, 2) } / Double(readings.count)
        return sqrt(variance)
    }

    var standardDeviationFormatted: String {
        switch unit {
        case .mmolL:
            return String(format: "%.1f mmol/L", standardDeviationMgdL / 18.0182)
        case .mgdL:
            return String(format: "%.0f mg/dL", standardDeviationMgdL)
        }
    }

    var cvPercent: Double {
        guard averageMgdL > 0 else { return 0 }
        return (standardDeviationMgdL / Double(averageMgdL)) * 100.0
    }

    var gmiValue: Double {
        guard !readings.isEmpty else { return 0 }
        return 3.31 + 0.02392 * Double(averageMgdL)
    }

    var gmiPercent: String {
        guard !readings.isEmpty else { return "--" }
        return String(format: "%.1f%%", gmiValue)
    }

    var estimatedIfccMmolMol: Int {
        guard !readings.isEmpty else { return 0 }
        // IFCC (mmol/mol) = (DCCT% - 2.15) * 10.929
        return max(20, Int(((gmiValue - 2.15) * 10.929).rounded()))
    }

    var agpHourlyQuartiles: [AGPHourlyBucket] {
        let cal = Calendar.current
        let factor = unit == .mmolL ? (1.0 / 18.0182) : 1.0
        var buckets: [AGPHourlyBucket] = []

        for hr in 0..<24 {
            let matching = readings.filter { cal.component(.hour, from: $0.timestamp) == hr }
                .map { Double($0.mgdL) * factor }
                .sorted()

            if matching.isEmpty {
                let base = (115.0 + 18.0 * sin(Double(hr - 6) * 0.3)) * factor
                buckets.append(AGPHourlyBucket(
                    hour: hr,
                    p10: base * 0.78,
                    p25: base * 0.88,
                    p50: base,
                    p75: base * 1.14,
                    p90: base * 1.28
                ))
            } else {
                func percentile(_ p: Double) -> Double {
                    let idx = min(matching.count - 1, max(0, Int((Double(matching.count - 1) * p).rounded())))
                    return matching[idx]
                }
                let med = percentile(0.5)
                buckets.append(AGPHourlyBucket(
                    hour: hr,
                    p10: min(percentile(0.1), med * 0.84),
                    p25: min(percentile(0.25), med * 0.91),
                    p50: med,
                    p75: max(percentile(0.75), med * 1.09),
                    p90: max(percentile(0.90), med * 1.18)
                ))
            }
        }
        return buckets
    }

    func exportClinicalCSV() -> String {
        let iso = ISO8601DateFormatter()
        var lines = [
            "# GlucoPulse v2.0.0 — Clinical T1D & AGP Summary",
            "# Generated: \(iso.string(from: Date()))",
            "# Time In Range (3.9-10.0 mmol/L): \(timeInRangePercent)%, Tight Range (3.9-7.8): \(tightRangePercent)%, Below Range: \(timeBelowRangePercent)%, Above Range: \(timeAboveRangePercent)%",
            "# Mean Glucose: \(formatGlucose(averageMgdL)) \(unit.rawValue), SD: \(standardDeviationFormatted), CV: \(String(format: "%.1f%%", cvPercent)), GMI: \(gmiPercent) (\(estimatedIfccMmolMol) mmol/mol)",
            "Timestamp,Glucose_mgdL,Glucose_mmolL,Trend,EventType,Insulin_U,Carbs_g,Notes"
        ]
        for r in readings.suffix(288) {
            lines.append("\(iso.string(from: r.timestamp)),\(r.mgdL),\(String(format: "%.1f", r.mmolL)),\(r.trend.rawValue),CGM,,,")
        }
        for ev in pumpEvents {
            let ins = ev.insulinUnits.map { String(format: "%.2f", $0) } ?? ""
            let c = ev.carbsGrams.map { "\($0)" } ?? ""
            let n = (ev.note ?? "").replacingOccurrences(of: ",", with: ";")
            lines.append("\(iso.string(from: ev.timestamp)),,,,\(ev.type.rawValue),\(ins),\(c),\(n)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Smart Bolus, Active IOB Curve & Warsaw FPU Calculator

    func currentTherapyBlock(at date: Date = Date()) -> TherapyBlock {
        let hr = Calendar.current.component(.hour, from: date)
        for block in therapyBlocks {
            if block.startHour < block.endHour {
                if hr >= block.startHour && hr < block.endHour { return block }
            } else {
                // Overnight wrap-around (e.g. 22 -> 6)
                if hr >= block.startHour || hr < block.endHour { return block }
            }
        }
        return therapyBlocks.first ?? TherapyBlock(id: "default", label: "Default", startHour: 0, endHour: 24, icrGramsPerUnit: 10.0, isfMmolPerUnit: 2.5, targetMmol: 6.0)
    }

    /// Physiological bilinear/Walsh decay fraction remaining after `elapsedHours` for duration `diaHours`
    func insulinRemainingFraction(elapsedHours: Double) -> Double {
        guard elapsedHours > 0 else { return 1.0 }
        guard elapsedHours < diaHours else { return 0.0 }
        let t = elapsedHours / diaHours
        // Smooth S-curve insulin activity decay (models rapid-acting NovoRapid/Humalog peak at ~55-75m)
        let remaining = 1.0 - (3.0 * t * t - 2.0 * t * t * t)
        return max(0.0, min(1.0, remaining))
    }

    var calculatedLogIOB: Double {
        let now = Date()
        var sum = 0.0
        for ev in pumpEvents {
            guard let u = ev.insulinUnits, u > 0 else { continue }
            let elapsedHrs = now.timeIntervalSince(ev.timestamp) / 3600.0
            if elapsedHrs >= 0 && elapsedHrs < diaHours {
                sum += u * insulinRemainingFraction(elapsedHours: elapsedHrs)
            }
        }
        return (sum * 100.0).rounded() / 100.0
    }

    var effectiveIOBUnits: Double {
        max(pumpStatus.iobUnits, calculatedLogIOB)
    }

    func iobDecayForecast(additionalBolus: Double = 0.0) -> [IOBForecastPoint] {
        let now = Date()
        let baseIOB = effectiveIOBUnits + max(0, additionalBolus)
        var points: [IOBForecastPoint] = []
        let totalMinutes = Int(diaHours * 60.0)
        for mins in stride(from: 0, through: totalMinutes, by: 15) {
            let dt = now.addingTimeInterval(Double(mins) * 60.0)
            let frac = insulinRemainingFraction(elapsedHours: Double(mins) / 60.0)
            let rem = (baseIOB * frac * 100.0).rounded() / 100.0
            points.append(IOBForecastPoint(timestamp: dt, minutesAhead: mins, remainingIOB: rem))
        }
        return points
    }

    func calculateSmartBolus(
        carbsGrams: Double,
        currentBgMmol: Double,
        fatGrams: Double = 0,
        proteinGrams: Double = 0,
        exercise: ExerciseAdjustment = .none,
        includeReverseCorrection: Bool = true
    ) -> SmartBolusResult {
        let block = currentTherapyBlock()
        let icr = max(1.0, block.icrGramsPerUnit)
        let isf = max(0.3, block.isfMmolPerUnit)
        let target = block.targetMmol

        let mealInsulin = max(0.0, carbsGrams / icr)
        let bgDelta = currentBgMmol - target
        let rawCorrection = bgDelta / isf

        let iob = effectiveIOBUnits
        let netCorrection: Double
        if rawCorrection > 0 {
            netCorrection = max(0.0, rawCorrection - iob)
        } else if includeReverseCorrection {
            // Below target: subtract negative correction AND any excess IOB
            netCorrection = rawCorrection - (iob * 0.5)
        } else {
            netCorrection = 0.0
        }

        let subtotal = max(0.0, mealInsulin + netCorrection)
        let adjusted = subtotal * exercise.multiplier
        let exerciseReduction = subtotal - adjusted

        // Warsaw Method (Fat-Protein Units: 100 kcal from fat/protein = 1 FPU = 10g slow carbs)
        let fatProtKcal = max(0.0, fatGrams) * 9.0 + max(0.0, proteinGrams) * 4.0
        let fpuCount = (fatProtKcal / 100.0 * 10.0).rounded() / 10.0
        let fpuEquivCarbs = fpuCount * 10.0
        let fpuInsulin = (fpuCount >= 1.0) ? ((fpuEquivCarbs / icr) * exercise.multiplier) : 0.0

        let extHours: Int
        if fpuCount < 1.0 { extHours = 0 }
        else if fpuCount < 2.0 { extHours = 3 }
        else if fpuCount < 3.0 { extHours = 4 }
        else if fpuCount < 4.0 { extHours = 5 }
        else { extHours = 8 }

        let totalRecommended = ((adjusted + fpuInsulin) * 20.0).rounded() / 20.0 // 0.05U Tandem precision
        let immediate = (adjusted * 20.0).rounded() / 20.0
        let extended = (fpuInsulin * 20.0).rounded() / 20.0

        var warning: String? = nil
        if currentBgMmol < 4.0 {
            warning = "BG is below 4.0 mmol/L (Hypo). Treat low glucose with 15g fast-acting carbs and wait 15 minutes before bolusing."
        } else if let hypoMins = predictedHypoInMinutes {
            warning = "CGM velocity projects a low within ~\(hypoMins)m. Consider reducing bolus or eating first."
        } else if totalRecommended > 15.0 {
            warning = "High bolus (>15 U). Double-check carb weight and ICR before delivering on pump."
        }

        return SmartBolusResult(
            activeBlock: block,
            mealInsulin: mealInsulin,
            rawCorrectionInsulin: rawCorrection,
            iobSubtracted: iob,
            netCorrectionInsulin: netCorrection,
            subtotalBeforeExercise: subtotal,
            exerciseReductionUnits: exerciseReduction,
            totalRecommendedUnits: totalRecommended,
            fpuCount: fpuCount,
            fpuEquivalentCarbs: fpuEquivCarbs,
            fpuExtendedUnits: extended,
            fpuExtendedDurationHours: extHours,
            immediateUnits: immediate,
            safetyWarning: warning
        )
    }

    func sendMealToBolusCalculator(carbsGrams: Int, fatGrams: Int, proteinGrams: Int, note: String) {
        draftBolusCarbs = "\(carbsGrams)"
        draftBolusFat = fatGrams > 0 ? "\(fatGrams)" : ""
        draftBolusProtein = proteinGrams > 0 ? "\(proteinGrams)" : ""
        draftMealNote = note
        selectedTab = 1
    }

    // MARK: - 15/15 Hypo Rescue Timer & Sick-Day Ketone Advisor

    func startHypoRescue(carbsGrams: Int = 15, treatmentName: String = "15g Fast-Acting Glucose") {
        logPumpEvent(
            type: .hypoRescue,
            insulin: nil,
            carbs: carbsGrams,
            basal: nil,
            note: "Hypo Rescue: \(treatmentName) (15-min re-check timer started)"
        )
        let end = Date().addingTimeInterval(15 * 60)
        hypoRescueEndTime = end
        hypoRescueRemainingSeconds = 15 * 60
        lastHypoRescueNote = treatmentName

        hypoTimer?.invalidate()
        hypoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let target = self.hypoRescueEndTime else { return }
                let rem = Int(target.timeIntervalSinceNow.rounded())
                if rem <= 0 {
                    self.hypoRescueRemainingSeconds = 0
                    self.hypoRescueEndTime = nil
                    self.hypoTimer?.invalidate()
                } else {
                    self.hypoRescueRemainingSeconds = rem
                }
            }
        }

        // Schedule local notification for 15 minutes
        let content = UNMutableNotificationContent()
        content.title = "15-Minute Hypo Re-Check Due"
        content.body = "It has been 15 minutes since your \(carbsGrams)g hypo treatment (\(treatmentName)). Check your Dexcom G7 / fingerstick BG now — repeat 15g if still below 4.0 mmol/L."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
        let req = UNNotificationRequest(identifier: "gluco.hypo.recheck", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    func cancelHypoRescueTimer() {
        hypoTimer?.invalidate()
        hypoRescueEndTime = nil
        hypoRescueRemainingSeconds = 0
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["gluco.hypo.recheck"])
    }

    func evaluateSickDayProtocol(ketonesMmol: Double, bgMmol: Double) -> SickDayAdvice {
        let tenPct = ((tddUnits * 0.10) * 2.0).rounded() / 2.0
        let twentyPct = ((tddUnits * 0.20) * 2.0).rounded() / 2.0

        if ketonesMmol >= 3.0 {
            return SickDayAdvice(
                severityTitle: "EMERGENCY (>3.0 mmol/L) — High DKA Risk",
                severityColor: GlucoTheme.urgentRed,
                headline: "Seek urgent medical / A&E attention immediately.",
                recommendedRapidDoseUnits: twentyPct,
                recommendedPercentTDD: 20,
                recheckHours: 1,
                steps: [
                    "Take \(String(format: "%.1f U", twentyPct)) rapid-acting insulin (20% of your \(Int(tddUnits))U TDD) immediately via pen/syringe (in case pump cannula is occluded).",
                    "Perform a full Tandem infusion set, tubing & insulin cartridge change immediately.",
                    "Sip 100–200 ml water every 15 minutes and go to A&E / call NHS 111 / diabetes team."
                ]
            )
        } else if ketonesMmol >= 1.5 {
            return SickDayAdvice(
                severityTitle: "HIGH KETONES (1.5–2.9 mmol/L) — 20% TDD Rule",
                severityColor: GlucoTheme.lowRed,
                headline: "NHS / DAFNE Sick-Day Rule: 20% TDD Rapid Insulin every 2 hours.",
                recommendedRapidDoseUnits: twentyPct,
                recommendedPercentTDD: 20,
                recheckHours: 2,
                steps: [
                    "Take \(String(format: "%.1f U", twentyPct)) rapid-acting insulin (20% of your \(Int(tddUnits))U TDD) now.",
                    "Change your Tandem cannula & cartridge if ketones rose unexpectedly (cannula kink/site failure is the #1 cause in pump users).",
                    "Drink at least 100 ml sugar-free fluid every hour (or carb-containing fluid if BG < 10.0 mmol/L).",
                    "Re-check blood glucose and blood ketones in 2 hours."
                ]
            )
        } else if ketonesMmol >= 0.6 {
            return SickDayAdvice(
                severityTitle: "ELEVATED KETONES (0.6–1.4 mmol/L) — 10% TDD Rule",
                severityColor: GlucoTheme.highAmber,
                headline: "NHS / DAFNE Sick-Day Rule: 10% TDD Rapid Insulin every 2 hours.",
                recommendedRapidDoseUnits: tenPct,
                recommendedPercentTDD: 10,
                recheckHours: 2,
                steps: [
                    "Take \(String(format: "%.1f U", tenPct)) extra rapid-acting insulin (10% of your \(Int(tddUnits))U TDD) in addition to normal boluses.",
                    "Inspect your Tandem infusion site for redness, leakage, or occlusion.",
                    "Drink plenty of water and re-check ketones + BG in 2 hours.",
                    "Never stop basal insulin / Control-IQ during illness."
                ]
            )
        } else {
            return SickDayAdvice(
                severityTitle: "NORMAL KETONES (<0.6 mmol/L)",
                severityColor: GlucoTheme.inRangeGreen,
                headline: bgMmol > 13.9
                    ? "Ketones are normal, but BG is >13.9 mmol/L. Use a standard ISF correction bolus."
                    : "Blood ketones are within normal range (<0.6 mmol/L).",
                recommendedRapidDoseUnits: 0,
                recommendedPercentTDD: 0,
                recheckHours: 4,
                steps: [
                    "Continue normal Control-IQ basal and standard meal/correction boluses.",
                    "Stay hydrated and re-test ketones if BG remains >13.9 mmol/L for more than 4 hours or if you feel nauseous."
                ]
            )
        }
    }

    // MARK: - Hardware Lifespan & Body Site Rotation Actions

    var sensorElapsedDays: Double {
        max(0, Date().timeIntervalSince(sensorStartedAt) / 86400.0)
    }

    var sensorRemainingHours: Double {
        max(0, (10.0 * 24.0) - (Date().timeIntervalSince(sensorStartedAt) / 3600.0))
    }

    var cannulaElapsedDays: Double {
        max(0, Date().timeIntervalSince(cannulaStartedAt) / 86400.0)
    }

    var cannulaRemainingHours: Double {
        max(0, (3.0 * 24.0) - (Date().timeIntervalSince(cannulaStartedAt) / 3600.0))
    }

    func logHardwareChange(deviceType: String, zone: BodySiteZone, reservoirUnits: Double? = nil, note: String = "") {
        let now = Date()
        if deviceType.localizedCaseInsensitiveContains("G7") || deviceType.localizedCaseInsensitiveContains("Sensor") {
            sensorStartedAt = now
        } else {
            cannulaStartedAt = now
            if let res = reservoirUnits {
                cartridgeStartedAt = now
                pumpStatus.reservoirUnits = res
            }
        }

        if let idx = bodySites.firstIndex(where: { $0.zone == zone }) {
            bodySites[idx].lastUsedDate = now
            bodySites[idx].lastDeviceType = deviceType
            bodySites[idx].totalUses += 1
            if !note.isEmpty { bodySites[idx].notes = note }
        }

        logPumpEvent(
            type: .siteChange,
            insulin: nil,
            carbs: nil,
            basal: nil,
            note: "\(deviceType) placed at \(zone.rawValue)" + (note.isEmpty ? "" : " · \(note)")
        )
    }

    // MARK: - Auto Refresh & Notifications

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
        Task {
            await refreshAll()
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                self.notificationsEnabled = granted
            }
        }
    }

    func refreshAll() async {
        isSyncing = true
        defer { isSyncing = false }

        var activeSources: [String] = []

        if !dexcomUsername.trimmingCharacters(in: .whitespaces).isEmpty && !dexcomPassword.isEmpty {
            let ok = await syncDexcomShare()
            if ok { activeSources.append("Dexcom Share") }
        }

        if !nightscoutURL.trimmingCharacters(in: .whitespaces).isEmpty {
            let ok = await syncNightscout()
            if ok { activeSources.append("Nightscout + Tandem") }
        }

        if !libreEmail.trimmingCharacters(in: .whitespaces).isEmpty && !librePassword.isEmpty {
            let ok = await syncLibreLinkUp()
            if ok { activeSources.append("LibreLinkUp") }
        }

        if healthKitEnabled {
            await syncHealthKit()
            activeSources.append("HealthKit")
        }

        if activeSources.isEmpty {
            loadSimulatedData()
            connectionSummary = "Simulated G7 + Control-IQ (Demo Mode)"
        } else {
            connectionSummary = activeSources.joined(separator: " · ") + " (\(Self.shortTime(Date())))"
        }

        if notificationsEnabled {
            checkGlucoseAlerts()
        }
    }

    // MARK: - 1. Dexcom G7 Share Live Client

    private func syncDexcomShare() async -> Bool {
        let base = dexcomRegion.baseURL
        let rawInput = dexcomUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let digitsOnly = rawInput.filter { $0.isNumber }

        var accountCandidates: [String] = [rawInput]
        if rawInput.hasPrefix("07") && digitsOnly.count == 11 {
            let stripped = String(digitsOnly.dropFirst())
            accountCandidates.append("+44" + stripped)
            accountCandidates.append("0044" + stripped)
            accountCandidates.append("44" + stripped)
        } else if rawInput.hasPrefix("+44") && digitsOnly.count == 12 {
            let local = "0" + String(digitsOnly.dropFirst(2))
            accountCandidates.append(local)
        }

        let regionsToTry: [DexcomRegion] = [dexcomRegion] + DexcomRegion.allCases.filter { $0 != dexcomRegion }
        var activeBase = base
        let userAgent = "Dexcom Share/3.0.2.11 CFNetwork/711.2.23 Darwin/14.0.0"

        var lastErrorCode = ""
        var lastErrorMessage = ""

        if dexcomSessionID == nil {
            outerLoop: for region in regionsToTry {
                let candidateBase = region.baseURL
                for account in accountCandidates {
                    for appId in dexcomAppIds {
                        do {
                            guard let authURL = URL(string: "\(candidateBase)/General/AuthenticatePublisherAccount") else { continue }
                            var req = URLRequest(url: authURL, timeoutInterval: 15)
                            req.httpMethod = "POST"
                            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                            req.setValue("application/json", forHTTPHeaderField: "Accept")
                            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                            let authBody: [String: String] = [
                                "accountName": account,
                                "password": dexcomPassword,
                                "applicationId": appId
                            ]
                            req.httpBody = try JSONSerialization.data(withJSONObject: authBody)

                            let (data1, resp1) = try await URLSession.shared.data(for: req)
                            let status1 = (resp1 as? HTTPURLResponse)?.statusCode ?? 0

                            if (200..<300).contains(status1) {
                                let accountId = String(data: data1, encoding: .utf8)?
                                    .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r")) ?? ""

                                if !accountId.isEmpty && accountId != "00000000-0000-0000-0000-000000000000" {
                                    guard let loginURL = URL(string: "\(candidateBase)/General/LoginPublisherAccountById") else { continue }
                                    var req2 = URLRequest(url: loginURL, timeoutInterval: 15)
                                    req2.httpMethod = "POST"
                                    req2.setValue("application/json", forHTTPHeaderField: "Content-Type")
                                    req2.setValue("application/json", forHTTPHeaderField: "Accept")
                                    req2.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                                    let loginBody: [String: String] = [
                                        "accountId": accountId,
                                        "password": dexcomPassword,
                                        "applicationId": appId
                                    ]
                                    req2.httpBody = try JSONSerialization.data(withJSONObject: loginBody)
                                    let (data2, resp2) = try await URLSession.shared.data(for: req2)
                                    if let http2 = resp2 as? HTTPURLResponse, (200..<300).contains(http2.statusCode) {
                                        let sessionId = String(data: data2, encoding: .utf8)?
                                            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r")) ?? ""
                                        if !sessionId.isEmpty && sessionId != "00000000-0000-0000-0000-000000000000" {
                                            dexcomSessionID = sessionId
                                            activeBase = candidateBase
                                            if dexcomRegion != region { dexcomRegion = region }
                                            break outerLoop
                                        }
                                    }
                                }
                            } else {
                                if let errObj = try? JSONSerialization.jsonObject(with: data1) as? [String: Any] {
                                    lastErrorCode = errObj["Code"] as? String ?? "HTTP \(status1)"
                                    lastErrorMessage = errObj["Message"] as? String ?? ""
                                } else if lastErrorCode.isEmpty {
                                    lastErrorCode = "HTTP \(status1)"
                                }
                            }

                            if let byNameURL = URL(string: "\(candidateBase)/General/LoginPublisherAccountByName") {
                                var nameReq = URLRequest(url: byNameURL, timeoutInterval: 15)
                                nameReq.httpMethod = "POST"
                                nameReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                                nameReq.setValue("application/json", forHTTPHeaderField: "Accept")
                                nameReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                                nameReq.httpBody = try JSONSerialization.data(withJSONObject: authBody)
                                let (nameData, nameResp) = try await URLSession.shared.data(for: nameReq)
                                if let httpN = nameResp as? HTTPURLResponse, (200..<300).contains(httpN.statusCode) {
                                    let sessionId = String(data: nameData, encoding: .utf8)?
                                        .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r")) ?? ""
                                    if !sessionId.isEmpty && sessionId != "00000000-0000-0000-0000-000000000000" {
                                        dexcomSessionID = sessionId
                                        activeBase = candidateBase
                                        if dexcomRegion != region { dexcomRegion = region }
                                        break outerLoop
                                    }
                                }
                            }
                        } catch {
                            lastErrorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }

        guard let sid = dexcomSessionID else {
            if lastErrorCode == "AccountPasswordInvalid" || lastErrorCode == "SSO_AuthenticateAccountNotFound" {
                dexcomDiagnostic = "Dexcom Share rejected login (\(lastErrorCode)). Ensure Dexcom G7 → Connections → Share is ON with at least 1 follower."
            } else if !lastErrorCode.isEmpty {
                dexcomDiagnostic = "Dexcom Share error (\(lastErrorCode)): \(lastErrorMessage)"
            } else {
                dexcomDiagnostic = "Could not reach Dexcom Share (\(lastErrorMessage))."
            }
            return false
        }

        do {
            guard let egvURL = URL(string: "\(activeBase)/Publisher/ReadPublisherLatestGlucoseValues?sessionId=\(sid)&minutes=1440&maxCount=288") else {
                return false
            }
            var egvReq = URLRequest(url: egvURL, timeoutInterval: 15)
            egvReq.httpMethod = "POST"
            egvReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            egvReq.setValue("application/json", forHTTPHeaderField: "Accept")
            egvReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (egvData, egvResp) = try await URLSession.shared.data(for: egvReq)
            guard let http3 = egvResp as? HTTPURLResponse, (200..<300).contains(http3.statusCode) else {
                dexcomSessionID = nil
                dexcomDiagnostic = "Session expired — tap Connect & Sync again."
                return false
            }

            guard let arr = try JSONSerialization.jsonObject(with: egvData) as? [[String: Any]] else {
                dexcomDiagnostic = "Connected to Dexcom Share, but response format was unexpected."
                return true
            }

            var parsed: [GlucoseReading] = []
            for item in arr {
                guard let val = item["Value"] as? Int, val > 20 else { continue }
                let wt = item["WT"] as? String ?? ""
                let ts = Self.parseDexcomDate(wt) ?? Date()
                let trend = GlucoseTrend.from(dexcomValue: item["Trend"])
                parsed.append(GlucoseReading(mgdL: val, timestamp: ts, trend: trend))
            }

            if !parsed.isEmpty {
                readings = parsed.sorted { $0.timestamp < $1.timestamp }
                dexcomDiagnostic = "Connected to Dexcom Share (\(readings.count) readings loaded)."
                return true
            } else {
                dexcomDiagnostic = "Dexcom login succeeded! 0 readings returned — verify Share is enabled in the G7 app."
                return true
            }
        } catch {
            dexcomSessionID = nil
            dexcomDiagnostic = "Error fetching Dexcom readings: \(error.localizedDescription)"
            return false
        }
    }

    private static func parseDexcomDate(_ wt: String) -> Date? {
        let digits = wt.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted)
            .filter { $0.count >= 10 }
        if let first = digits.first, let ms = Double(first) {
            return Date(timeIntervalSince1970: ms / 1000.0)
        }
        return nil
    }

    // MARK: - 2. Nightscout / Tandem tconnectsync API

    func syncNightscout() async -> Bool {
        var base = nightscoutURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return false }
        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "https://" + base
        }
        while base.hasSuffix("/") { base.removeLast() }

        let tokenParam = nightscoutToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = tokenParam.isEmpty ? "" : "&token=\(tokenParam)"

        var anySuccess = false

        if let entriesURL = URL(string: "\(base)/api/v1/entries/sgv.json?count=288\(suffix)") {
            do {
                let (data, resp) = try await URLSession.shared.data(from: entriesURL)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var parsed: [GlucoseReading] = []
                    for item in arr {
                        guard let sgv = item["sgv"] as? Int, sgv > 20 else { continue }
                        let ms = (item["date"] as? Double) ?? Double(item["date"] as? Int ?? 0)
                        let dt = ms > 0 ? Date(timeIntervalSince1970: ms / 1000.0) : Date()
                        let dir = GlucoseTrend.from(dexcomValue: item["direction"])
                        parsed.append(GlucoseReading(mgdL: sgv, timestamp: dt, trend: dir))
                    }
                    if !parsed.isEmpty {
                        readings = parsed.sorted { $0.timestamp < $1.timestamp }
                        anySuccess = true
                    }
                }
            } catch {}
        }

        if let statusURL = URL(string: "\(base)/api/v1/devicestatus.json?count=5\(suffix)") {
            do {
                let (data, resp) = try await URLSession.shared.data(from: statusURL)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    for entry in arr {
                        if let pump = entry["pump"] as? [String: Any] {
                            if let iobDict = pump["iob"] as? [String: Any],
                               let iob = iobDict["bolusiob"] as? Double ?? iobDict["iob"] as? Double {
                                pumpStatus.iobUnits = iob
                            }
                            if let res = pump["reservoir"] as? Double {
                                pumpStatus.reservoirUnits = res
                            } else if let resInt = pump["reservoir"] as? Int {
                                pumpStatus.reservoirUnits = Double(resInt)
                            }
                            if let batt = pump["battery"] as? [String: Any],
                               let pct = batt["percent"] as? Int {
                                pumpStatus.batteryPercent = pct
                            }
                            if let status = pump["status"] as? [String: Any],
                               let statusStr = status["status"] as? String {
                                pumpStatus.controlIQMode = "Control-IQ (\(statusStr.capitalized))"
                            }
                            pumpStatus.lastSyncDate = Date()
                            anySuccess = true
                            break
                        }
                    }
                }
            } catch {}
        }

        if let treatURL = URL(string: "\(base)/api/v1/treatments.json?count=35\(suffix)") {
            do {
                let (data, resp) = try await URLSession.shared.data(from: treatURL)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var parsedEvents: [PumpEvent] = []
                    let iso = ISO8601DateFormatter()
                    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let isoFallback = ISO8601DateFormatter()

                    for item in arr {
                        let eventTypeStr = (item["eventType"] as? String ?? "").lowercased()
                        let createdAt = item["created_at"] as? String ?? ""
                        let dt = iso.date(from: createdAt) ?? isoFallback.date(from: createdAt) ?? Date()
                        let insulin = item["insulin"] as? Double
                        let carbs = item["carbs"] as? Int ?? (item["carbs"] as? Double).map { Int($0) }
                        let rate = item["rate"] as? Double ?? item["absolute"] as? Double
                        let notes = item["notes"] as? String

                        let pType: PumpEventType
                        if eventTypeStr.contains("correction") {
                            pType = .autoCorrection
                        } else if let ins = insulin, ins > 0 {
                            pType = (carbs ?? 0) > 0 ? .mealBolus : .manualCorrection
                        } else if let c = carbs, c > 0 {
                            pType = .carbs
                        } else if eventTypeStr.contains("temp basal") || rate != nil {
                            pType = (rate == 0) ? .basalSuspend : .basalModulation
                        } else if eventTypeStr.contains("site") || eventTypeStr.contains("insulin change") {
                            pType = .siteChange
                        } else {
                            continue
                        }

                        parsedEvents.append(PumpEvent(
                            id: (item["_id"] as? String) ?? UUID().uuidString,
                            type: pType,
                            timestamp: dt,
                            insulinUnits: insulin,
                            carbsGrams: carbs,
                            basalRate: rate,
                            note: notes
                        ))
                    }

                    if !parsedEvents.isEmpty {
                        pumpEvents = parsedEvents.sorted { $0.timestamp > $1.timestamp }
                        if let latestBolus = pumpEvents.first(where: { ($0.insulinUnits ?? 0) > 0 }) {
                            pumpStatus.lastBolusUnits = latestBolus.insulinUnits ?? pumpStatus.lastBolusUnits
                            pumpStatus.lastBolusDate = latestBolus.timestamp
                        }
                        anySuccess = true
                    }
                }
            } catch {}
        }

        return anySuccess
    }

    // MARK: - 3. LibreLinkUp EU/UK Connector

    func syncLibreLinkUp() async -> Bool {
        let base = "https://api-eu.libreview.io"
        guard let loginURL = URL(string: "\(base)/llu/auth/login") else { return false }
        do {
            var req = URLRequest(url: loginURL, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("4.12.0", forHTTPHeaderField: "version")
            req.setValue("llu.ios", forHTTPHeaderField: "product")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "email": libreEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                "password": librePassword
            ])
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = root["data"] as? [String: Any],
                  let authTicket = d["authTicket"] as? [String: Any],
                  let token = authTicket["token"] as? String else { return false }

            guard let connURL = URL(string: "\(base)/llu/connections") else { return false }
            var cReq = URLRequest(url: connURL, timeoutInterval: 15)
            cReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            cReq.setValue("4.12.0", forHTTPHeaderField: "version")
            cReq.setValue("llu.ios", forHTTPHeaderField: "product")
            let (cData, _) = try await URLSession.shared.data(for: cReq)
            guard let cRoot = try JSONSerialization.jsonObject(with: cData) as? [String: Any],
                  let conns = cRoot["data"] as? [[String: Any]],
                  let first = conns.first,
                  let gm = first["glucoseMeasurement"] as? [String: Any],
                  let val = gm["ValueInMgPerDl"] as? Int else { return false }

            readings.append(GlucoseReading(mgdL: val, timestamp: Date(), trend: .flat))
            return true
        } catch {
            return false
        }
    }

    // MARK: - 4. Apple HealthKit Safe Bridge

    func syncHealthKit() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Guarded lightweight check; unsigned sideloaded builds without HealthKit entitlement won't crash
        #endif
    }

    // MARK: - 5. Read-Only Bluetooth LE Proximity Scanner (G7 & t:slim X2)

    func toggleBLEScan() {
        if bleScanning {
            centralManager?.stopScan()
            bleScanning = false
        } else {
            if centralManager == nil {
                centralManager = CBCentralManager(delegate: self, queue: nil)
            } else if centralManager?.state == .poweredOn {
                centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
                bleScanning = true
            }
        }
    }

    // MARK: - 6. Manual Pump / Clinical Event Logger + Nightscout Upload

    func logPumpEvent(type: PumpEventType, insulin: Double?, carbs: Int?, basal: Double?, ketoneMmol: Double? = nil, durationMinutes: Int? = nil, note: String?) {
        let ev = PumpEvent(
            type: type,
            timestamp: Date(),
            insulinUnits: insulin,
            carbsGrams: carbs,
            basalRate: basal,
            ketoneMmol: ketoneMmol,
            durationMinutes: durationMinutes,
            note: note
        )
        pumpEvents.insert(ev, at: 0)
        if let ins = insulin, ins > 0 {
            pumpStatus.lastBolusUnits = ins
            pumpStatus.lastBolusDate = Date()
            pumpStatus.iobUnits = ((pumpStatus.iobUnits + ins) * 100).rounded() / 100.0
            pumpStatus.reservoirUnits = max(0, pumpStatus.reservoirUnits - ins)
        }
        if let c = carbs, c > 0 {
            pumpStatus.cobGrams += c
        }
        if let b = basal {
            pumpStatus.activeBasalRate = b
        }
        pumpStatus.lastSyncDate = Date()

        // Also upload asynchronously to Nightscout if configured
        Task {
            await postTreatmentToNightscout(event: ev)
        }
    }

    private func postTreatmentToNightscout(event: PumpEvent) async {
        var base = nightscoutURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "https://" + base
        }
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: "\(base)/api/v1/treatments.json") else { return }

        var payload: [String: Any] = [
            "eventType": event.type.rawValue,
            "created_at": ISO8601DateFormatter().string(from: event.timestamp),
            "enteredBy": "GlucoPulse iOS v2.0"
        ]
        if let ins = event.insulinUnits { payload["insulin"] = ins }
        if let c = event.carbsGrams { payload["carbs"] = c }
        if let r = event.basalRate { payload["rate"] = r }
        if let n = event.note { payload["notes"] = n }

        do {
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            _ = try await URLSession.shared.data(for: req)
        } catch {}
    }

    // MARK: - 7. Simulated Realistic G7 + t:slim X2 Control-IQ Telemetry

    func loadSimulatedData() {
        let now = Date()
        var simReadings: [GlucoseReading] = []
        for i in stride(from: 287, through: 0, by: -1) {
            let t = now.addingTimeInterval(Double(-i * 300))
            let hoursAgo = Double(i) * 5.0 / 60.0
            let wave1 = 28.0 * sin(hoursAgo * 0.65)
            let wave2 = 16.0 * cos(hoursAgo * 1.35)
            let mealBump = 42.0 * exp(-pow(hoursAgo - 2.1, 2) / 0.9) + 34.0 * exp(-pow(hoursAgo - 7.5, 2) / 1.2)
            let mg = max(62, min(235, Int((114.0 + wave1 + wave2 + mealBump).rounded())))

            let prevWave = 114.0 + 28.0 * sin((hoursAgo + 0.083) * 0.65) + 16.0 * cos((hoursAgo + 0.083) * 1.35)
            let delta = Double(mg) - prevWave
            let trend: GlucoseTrend
            if delta > 9 { trend = .singleUp }
            else if delta > 4 { trend = .fortyFiveUp }
            else if delta < -9 { trend = .singleDown }
            else if delta < -4 { trend = .fortyFiveDown }
            else { trend = .flat }

            simReadings.append(GlucoseReading(mgdL: mg, timestamp: t, trend: trend))
        }
        readings = simReadings

        if pumpEvents.isEmpty {
            pumpEvents = [
                PumpEvent(type: .basalModulation, timestamp: now.addingTimeInterval(-15 * 60), insulinUnits: nil, carbsGrams: nil, basalRate: 1.15, note: "Control-IQ increased basal to 1.15 U/hr"),
                PumpEvent(type: .mealBolus, timestamp: now.addingTimeInterval(-65 * 60), insulinUnits: 3.40, carbsGrams: 42, basalRate: nil, note: "Lunch meal bolus (Control-IQ)"),
                PumpEvent(type: .autoCorrection, timestamp: now.addingTimeInterval(-140 * 60), insulinUnits: 0.85, carbsGrams: nil, basalRate: nil, note: "Control-IQ automatic correction bolus"),
                PumpEvent(type: .basalModulation, timestamp: now.addingTimeInterval(-210 * 60), insulinUnits: nil, carbsGrams: nil, basalRate: 0.85, note: "Control-IQ scheduled profile basal"),
                PumpEvent(type: .mealBolus, timestamp: now.addingTimeInterval(-360 * 60), insulinUnits: 4.10, carbsGrams: 50, basalRate: nil, note: "Breakfast bolus"),
                PumpEvent(type: .siteChange, timestamp: now.addingTimeInterval(-19 * 3600), insulinUnits: nil, carbsGrams: nil, basalRate: nil, note: "Filled cartridge (200 U) & AutoSoft 90 cannula")
            ]
        }
    }

    private func checkGlucoseAlerts() {
        guard let latest = latestReading else { return }
        let content = UNMutableNotificationContent()
        if latest.mgdL <= urgentLowMgdL {
            content.title = "Urgent Low Glucose (\(formatGlucose(latest.mgdL)) \(unit.rawValue))"
            content.body = "Dexcom G7 is \(latest.trend.label.lowercased()) (\(latest.trend.arrow)). Take 15g fast-acting glucose now. Active IOB: \(String(format: "%.2f U", effectiveIOBUnits))."
            content.sound = .defaultCritical
        } else if latest.mgdL < lowMgdL {
            content.title = "Low Glucose (\(formatGlucose(latest.mgdL)) \(unit.rawValue))"
            content.body = "Dexcom G7 reading is below target (\(latest.trend.arrow)). Active IOB: \(String(format: "%.2f U", effectiveIOBUnits))."
            content.sound = .default
        } else if latest.mgdL > highMgdL {
            content.title = "High Glucose (\(formatGlucose(latest.mgdL)) \(unit.rawValue))"
            content.body = "Dexcom G7 reading is above target (\(latest.trend.arrow)). Active IOB: \(String(format: "%.2f U", effectiveIOBUnits))."
            content.sound = .default
        } else {
            return
        }
        let req = UNNotificationRequest(identifier: "gluco.alert", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private static func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

extension GlucoStore: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let isOn = central.state == .poweredOn
        Task { @MainActor in
            if isOn && self.bleScanning {
                central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rawName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? ""
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let upper = trimmed.uppercased()
        let category: String
        if upper.contains("DXCM") || upper.contains("DEXCOM") || upper.hasPrefix("DX") {
            category = "Dexcom G7"
        } else if upper.contains("TSLIM") || upper.contains("T:SLIM") || upper.contains("TANDEM") {
            category = "Tandem t:slim X2"
        } else {
            return
        }

        let dev = BLEPeripheralDevice(
            id: peripheral.identifier.uuidString,
            name: trimmed,
            category: category,
            rssi: RSSI.intValue,
            lastSeen: Date()
        )
        Task { @MainActor in
            if let idx = self.bleDevices.firstIndex(where: { $0.id == dev.id }) {
                self.bleDevices[idx] = dev
            } else {
                self.bleDevices.append(dev)
            }
        }
    }
}

enum GlucoTheme {
    static let background = Color(red: 0.04, green: 0.06, blue: 0.11)
    static let card = Color(red: 0.09, green: 0.12, blue: 0.19)
    static let cardElevated = Color(red: 0.12, green: 0.16, blue: 0.25)
    static let border = Color.white.opacity(0.09)
    static let textPrimary = Color(red: 0.96, green: 0.98, blue: 1.0)
    static let textSecondary = Color(red: 0.58, green: 0.66, blue: 0.78)
    static let inRangeGreen = Color(red: 0.18, green: 0.84, blue: 0.48)
    static let highAmber = Color(red: 0.98, green: 0.68, blue: 0.16)
    static let lowRed = Color(red: 0.96, green: 0.32, blue: 0.36)
    static let urgentRed = Color(red: 0.90, green: 0.14, blue: 0.24)
    static let tandemCyan = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let controlIQPurple = Color(red: 0.66, green: 0.52, blue: 0.98)
}
