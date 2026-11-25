import WidgetKit
import SwiftUI
import HealthKit

// MARK: - Gothic palette

private let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
private let bloodDim = Color(red: 0.48, green: 0.05, blue: 0.13)
private let ashText = Color(red: 0.96, green: 0.89, blue: 0.91)
private let ashDim = Color(red: 0.69, green: 0.53, blue: 0.56)
private let cryptBgTop = Color(red: 0.06, green: 0.01, blue: 0.03)
private let cryptBgBottom = Color(red: 0.02, green: 0.004, blue: 0.012)

// MARK: - Entry

struct PulseEntry: TimelineEntry {
    let date: Date
    let steps: Double
    let heartRate: Double
    let restingHR: Double
    let hrv: Double
    let spo2: Double
    let sleepHours: Double
    let activeEnergy: Double
    let authorized: Bool

    static func placeholder() -> PulseEntry {
        PulseEntry(date: Date(), steps: 8432, heartRate: 72, restingHR: 58, hrv: 42, spo2: 0.98, sleepHours: 7.3, activeEnergy: 420, authorized: true)
    }

    static func empty() -> PulseEntry {
        PulseEntry(date: Date(), steps: 0, heartRate: 0, restingHR: 0, hrv: 0, spo2: 0, sleepHours: 0, activeEnergy: 0, authorized: false)
    }
}

// MARK: - HealthKit reader

enum WidgetHealthReader {
    static let store = HKHealthStore()

    static func readMetrics() async -> PulseEntry {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .empty()
        }

        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis)
        ]

        // Request/share not needed in widget; status depends on host app authorization.
        // We attempt reads regardless - unauthorized types return 0.
        let authorized = await requestReadAccess(readTypes)

        async let steps = sumToday(.stepCount, unit: .count())
        async let heartRate = latestSample(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let restingHR = latestSample(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrv = latestSample(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let spo2 = latestSample(.oxygenSaturation, unit: .percent())
        async let activeEnergy = sumToday(.activeEnergyBurned, unit: .kilocalorie())
        async let sleepHours = lastNightSleepHours()

        return PulseEntry(
            date: Date(),
            steps: await steps,
            heartRate: await heartRate,
            restingHR: await restingHR,
            hrv: await hrv,
            spo2: await spo2,
            sleepHours: await sleepHours,
            activeEnergy: await activeEnergy,
            authorized: authorized
        )
    }

    private static func requestReadAccess(_ types: Set<HKObjectType>) async -> Bool {
        await withCheckedContinuation { cont in
            store.requestAuthorization(toShare: [], read: types) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }

    private static func sumToday(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        let type = HKQuantityType(id)
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stat, _ in
                cont.resume(returning: stat?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    private static func latestSample(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        let type = HKQuantityType(id)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0
                cont.resume(returning: v)
            }
            store.execute(q)
        }
    }

    private static func lastNightSleepHours() async -> Double {
        let type = HKCategoryType(.sleepAnalysis)
        let cal = Calendar.current
        let start = cal.date(byAdding: .hour, value: -20, to: Date())!
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 200, sortDescriptors: [sort]) { _, samples, _ in
                var mins = 0.0
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                ]
                for s in (samples as? [HKCategorySample]) ?? [] {
                    if asleepValues.contains(s.value) {
                        mins += s.endDate.timeIntervalSince(s.startDate) / 60.0
                    }
                }
                cont.resume(returning: mins / 60.0)
            }
            store.execute(q)
        }
    }
}

// MARK: - Timeline

struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry { .placeholder() }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder())
            return
        }
        Task {
            completion(await WidgetHealthReader.readMetrics())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        Task {
            let entry = await WidgetHealthReader.readMetrics()
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: - Views

struct MetricBlock: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(ashDim)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundColor(ashText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(ashDim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PulselineWidgetSmall: View {
    let entry: PulseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PULSLINE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                Spacer()
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundColor(crimson)
            }

            if !entry.authorized && entry.steps == 0 && entry.heartRate == 0 {
                Spacer()
                Text("Open Pulseline\nto grant Health access")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(ashDim)
                    .multilineTextAlignment(.leading)
                Spacer()
            } else {
                Spacer(minLength: 0)
                MetricBlock(label: "STEPS", value: entry.steps > 0 ? "\(Int(entry.steps))" : "—", unit: "")
                HStack(spacing: 8) {
                    MetricBlock(label: "HR", value: entry.heartRate > 0 ? "\(Int(entry.heartRate))" : "—", unit: "bpm")
                    MetricBlock(label: "HRV", value: entry.hrv > 0 ? "\(Int(entry.hrv))" : "—", unit: "ms")
                }
                MetricBlock(label: "SLEEP", value: entry.sleepHours > 0 ? String(format: "%.1f", entry.sleepHours) : "—", unit: "h")
            }
        }
    }
}

struct PulselineWidgetMedium: View {
    let entry: PulseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PULSLINE")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(ashDim)
            }

            if !entry.authorized && entry.steps == 0 && entry.heartRate == 0 {
                Spacer()
                Text("Open Pulseline to grant Health access")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(ashDim)
                Spacer()
            } else {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        MetricBlock(label: "STEPS", value: entry.steps > 0 ? "\(Int(entry.steps))" : "—", unit: "")
                        MetricBlock(label: "ENERGY", value: entry.activeEnergy > 0 ? "\(Int(entry.activeEnergy))" : "—", unit: "kcal")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        MetricBlock(label: "HEART", value: entry.heartRate > 0 ? "\(Int(entry.heartRate))" : "—", unit: "bpm")
                        MetricBlock(label: "RESTING", value: entry.restingHR > 0 ? "\(Int(entry.restingHR))" : "—", unit: "bpm")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        MetricBlock(label: "HRV", value: entry.hrv > 0 ? "\(Int(entry.hrv))" : "—", unit: "ms")
                        MetricBlock(label: "SPO2", value: entry.spo2 > 0 ? String(format: "%.0f", entry.spo2 * 100) : "—", unit: "%")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        MetricBlock(label: "SLEEP", value: entry.sleepHours > 0 ? String(format: "%.1f", entry.sleepHours) : "—", unit: "h")
                        MetricBlock(label: "STATE", value: entry.heartRate > 0 ? "LIVE" : "IDLE", unit: "")
                    }
                }
            }
        }
    }
}

struct PulselineWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: PulseEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                PulselineWidgetMedium(entry: entry)
            default:
                PulselineWidgetSmall(entry: entry)
            }
        }
    }
}

// MARK: - Widget

struct PulselineWidget: Widget {
    let kind = "PulselineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseProvider()) { entry in
            PulselineWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [cryptBgTop, cryptBgBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Pulseline")
        .description("Your vital signs from the crypt — steps, heart, sleep, HRV.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PulselineWidgetBundle: WidgetBundle {
    var body: some Widget {
        PulselineWidget()
    }
}
