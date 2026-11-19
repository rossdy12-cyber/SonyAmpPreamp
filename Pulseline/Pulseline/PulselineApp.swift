import SwiftUI
import HealthKit
import Charts

// ============================================================
//  PULSLINE — Bevel-style Apple Health explorer, gothic edition
//  Everything reads on-device HealthKit data. Nothing leaves
//  the phone.
// ============================================================

let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
let bloodDim = Color(red: 0.48, green: 0.05, blue: 0.13)
let ashText = Color(red: 0.96, green: 0.89, blue: 0.91)
let ashDim = Color(red: 0.69, green: 0.53, blue: 0.56)
let cryptBg = Color(red: 0.02, green: 0.004, blue: 0.012)

let healthStore = HKHealthStore()

// MARK: - Models

struct DailyStat: Identifiable {
    let id: Date
    let date: Date
    let value: Double
}

struct SleepSegment: Identifiable {
    let id: Date
    let start: Date
    let end: Date
    let stage: String
    let minutes: Double
}

struct WorkoutEntry: Identifiable {
    let id: UUID
    let type: String
    let start: Date
    let minutes: Double
    let calories: Double
    let distanceKm: Double
}

// MARK: - Health engine

@MainActor
final class HealthEngine: ObservableObject {
    @Published var authorized = false
    @Published var loadStatus = "Awaiting the blood rite…"
    @Published var loaded = false

    // Today
    @Published var steps: Double = 0
    @Published var distanceKm: Double = 0
    @Published var activeEnergy: Double = 0
    @Published var exerciseMinutes: Double = 0
    @Published var heartRateLatest: Double = 0
    @Published var heartRateMin: Double = 0
    @Published var heartRateMax: Double = 0
    @Published var restingHR: Double = 0
    @Published var hrv: Double = 0
    @Published var spo2: Double = 0
    @Published var respiratoryRate: Double = 0

    // Trends
    @Published var restingHRTrend: [DailyStat] = []
    @Published var hrvTrend: [DailyStat] = []
    @Published var spo2Trend: [DailyStat] = []
    @Published var stepsTrend: [DailyStat] = []
    @Published var sleepTrend: [DailyStat] = []
    @Published var lastNightSegments: [SleepSegment] = []
    @Published var lastNightTotalMinutes: Double = 0
    @Published var workouts: [WorkoutEntry] = []

    private var types: [HKSampleType] {
        [
            HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned), HKQuantityType(.appleExerciseTime),
            HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.oxygenSaturation),
            HKQuantityType(.respiratoryRate), HKCategoryType(.sleepAnalysis), HKWorkoutType.workoutType()
        ]
    }

    func requestAuth() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            loadStatus = "Health data is not available on this device."
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: Set(types))
            authorized = true
            await loadEverything()
        } catch {
            loadStatus = "Health permission denied: \(error.localizedDescription)"
        }
    }

    func loadEverything() async {
        loadStatus = "Reading the blood records…"
        await loadTodayStatistics()
        await loadLatestVitals()
        await loadTrends()
        await loadSleep()
        await loadWorkouts()
        loaded = true
        loadStatus = ""
    }

    // MARK: helpers

    private func quantityQuery(_ type: HKQuantityType, unit: HKUnit, options: HKStatisticsOptions, start: Date, end: Date) async -> Double {
        await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end), options: options) { _, stat, _ in
                var v = 0.0
                switch options {
                case .cumulativeSum: v = stat?.sumQuantity()?.doubleValue(for: unit) ?? 0
                case .discreteMin: v = stat?.minimumQuantity()?.doubleValue(for: unit) ?? 0
                case .discreteMax: v = stat?.maximumQuantity()?.doubleValue(for: unit) ?? 0
                case .discreteAverage: v = stat?.averageQuantity()?.doubleValue(for: unit) ?? 0
                default: v = stat?.averageQuantity()?.doubleValue(for: unit) ?? 0
                }
                cont.resume(returning: v)
            }
            healthStore.execute(q)
        }
    }

    private func latestSample(_ type: HKSampleType, unit: HKUnit) async -> Double {
        await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(q)
        }
    }

    private func dailyTrend(_ type: HKQuantityType, unit: HKUnit, options: HKStatisticsOptions, days: Int) async -> [DailyStat] {
        await withCheckedContinuation { cont in
            let cal = Calendar.current
            let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -days, to: Date())!)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: options, anchorDate: start, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, stats, _ in
                var out: [DailyStat] = []
                stats?.enumerateStatistics(from: start, to: Date()) { stat, _ in
                    var v = 0.0
                    switch options {
                    case .cumulativeSum: v = stat.sumQuantity()?.doubleValue(for: unit) ?? 0
                    case .discreteAverage: v = stat.averageQuantity()?.doubleValue(for: unit) ?? 0
                    case .discreteMin: v = stat.minimumQuantity()?.doubleValue(for: unit) ?? 0
                    case .discreteMax: v = stat.maximumQuantity()?.doubleValue(for: unit) ?? 0
                    default: v = stat.averageQuantity()?.doubleValue(for: unit) ?? 0
                    }
                    out.append(DailyStat(id: stat.startDate, date: stat.startDate, value: v))
                }
                cont.resume(returning: out)
            }
            healthStore.execute(q)
        }
    }

    // MARK: loaders

    func loadTodayStatistics() async {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        steps = await quantityQuery(HKQuantityType(.stepCount), unit: .count(), options: .cumulativeSum, start: start, end: Date())
        distanceKm = await quantityQuery(HKQuantityType(.distanceWalkingRunning), unit: .meterUnit(with: .kilo), options: .cumulativeSum, start: start, end: Date())
        activeEnergy = await quantityQuery(HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), options: .cumulativeSum, start: start, end: Date())
        exerciseMinutes = await quantityQuery(HKQuantityType(.appleExerciseTime), unit: .minute(), options: .cumulativeSum, start: start, end: Date())
    }

    func loadLatestVitals() async {
        heartRateLatest = await latestSample(HKQuantityType(.heartRate), unit: .count().unitDivided(by: .minute()))
        let cal = Calendar.current
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: Date())!)
        heartRateMin = await quantityQuery(HKQuantityType(.heartRate), unit: .count().unitDivided(by: .minute()), options: .discreteMin, start: start, end: Date())
        heartRateMax = await quantityQuery(HKQuantityType(.heartRate), unit: .count().unitDivided(by: .minute()), options: .discreteMax, start: start, end: Date())
        restingHR = await latestSample(HKQuantityType(.restingHeartRate), unit: .count().unitDivided(by: .minute()))
        hrv = await latestSample(HKQuantityType(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli))
        spo2 = await latestSample(HKQuantityType(.oxygenSaturation), unit: .percent())
        respiratoryRate = await latestSample(HKQuantityType(.respiratoryRate), unit: .count().unitDivided(by: .minute()))
    }

    func loadTrends() async {
        restingHRTrend = await dailyTrend(HKQuantityType(.restingHeartRate), unit: .count().unitDivided(by: .minute()), options: .discreteAverage, days: 30)
        hrvTrend = await dailyTrend(HKQuantityType(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), options: .discreteAverage, days: 30)
        spo2Trend = await dailyTrend(HKQuantityType(.oxygenSaturation), unit: .percent(), options: .discreteMin, days: 30)
        stepsTrend = await dailyTrend(HKQuantityType(.stepCount), unit: .count(), options: .cumulativeSum, days: 14)
        sleepTrend = await dailySleepTrend(days: 14)
    }

    func dailySleepTrend(days: Int) async -> [DailyStat] {
        await withCheckedContinuation { cont in
            let cal = Calendar.current
            let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -days, to: Date())!)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate, limit: 800, sortDescriptors: [sort]) { _, samples, _ in
                var perDay: [Date: Double] = [:]
                for s in (samples as? [HKCategorySample]) ?? [] {
                    let mins = s.endDate.timeIntervalSince(s.startDate) / 60.0
                    if s.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                        s.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                        s.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                        s.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
                        let day = cal.startOfDay(for: s.endDate)
                        perDay[day, default: 0] += mins
                    }
                }
                let out = perDay.sorted { $0.key < $1.key }.map { DailyStat(id: $0.key, date: $0.key, value: $0.value / 60.0) }
                cont.resume(returning: out)
            }
            healthStore.execute(q)
        }
    }

    func loadSleep() async {
        lastNightSegments = await withCheckedContinuation { cont in
            let cal = Calendar.current
            let start = cal.date(byAdding: .hour, value: -20, to: Date())!
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate, limit: 120, sortDescriptors: [sort]) { _, samples, _ in
                var out: [SleepSegment] = []
                let stageNames: [Int: String] = [
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue: "DEEP",
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue: "REM",
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue: "CORE",
                    HKCategoryValueSleepAnalysis.awake.rawValue: "AWAKE",
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: "ASLEEP"
                ]
                for s in (samples as? [HKCategorySample]) ?? [] {
                    let stage = stageNames[s.value] ?? "OTHER"
                    let mins = s.endDate.timeIntervalSince(s.startDate) / 60.0
                    out.append(SleepSegment(id: s.startDate, start: s.startDate, end: s.endDate, stage: stage, minutes: mins))
                }
                cont.resume(returning: out)
            }
            healthStore.execute(q)
        }
        let sleepOnly = lastNightSegments.filter { $0.stage != "AWAKE" }
        lastNightTotalMinutes = sleepOnly.reduce(0) { $0 + $1.minutes }
    }

    func loadWorkouts() async {
        workouts = await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let q = HKSampleQuery(sampleType: HKWorkoutType.workoutType(), predicate: nil, limit: 30, sortDescriptors: [sort]) { _, samples, _ in
                let typeNames: [Int: String] = [1: "Run", 2: "Cycle", 10: "Walk", 52: "Swim", 37: "Strength", 5: "Elliptical", 16: "Rowing", 42: "HIIT", 45: "Other"]
                let out: [WorkoutEntry] = ((samples as? [HKWorkout]) ?? []).map { w in
                    WorkoutEntry(
                        id: w.uuid,
                        type: typeNames[Int(w.workoutActivityType.rawValue)] ?? "Workout",
                        start: w.startDate,
                        minutes: w.duration / 60.0,
                        calories: w.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
                        distanceKm: w.totalDistance?.doubleValue(for: .meterUnit(with: .kilo)) ?? 0
                    )
                }
                cont.resume(returning: out)
            }
            healthStore.execute(q)
        }
    }
}

// MARK: - Root

@main
struct PulselineApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @StateObject private var engine = HealthEngine()

    var body: some View {
        TabView {
            DashboardView(engine: engine)
                .tabItem { Label("TODAY", systemImage: "heart.text.square.fill") }
            HeartView(engine: engine)
                .tabItem { Label("HEART", systemImage: "heart.fill") }
            SleepView(engine: engine)
                .tabItem { Label("SLEEP", systemImage: "moon.stars.fill") }
            ActivityView(engine: engine)
                .tabItem { Label("ACTIVITY", systemImage: "figure.walk") }
            VaultInfoView()
                .tabItem { Label("CRYPT", systemImage: "lock.shield") }
        }
        .accentColor(crimson)
        .onAppear {
            Task { await engine.requestAuth() }
        }
    }
}

// MARK: - Shared

struct PCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
            content()
        }
        .padding(13)
        .background(Color(red: 0.06, green: 0.01, blue: 0.03))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.35), lineWidth: 1))
    }
}

struct PMetric: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 21, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(ashDim)
            }
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(ashDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.35))
        .cornerRadius(8)
    }
}

struct gothicChartStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .chartLegend(.hidden)
            .frame(height: 150)
    }
}

// MARK: - TODAY

struct DashboardView: View {
    @ObservedObject var engine: HealthEngine

    var body: some View {
        NavigationView {
            ZStack {
                cryptBg.ignoresSafeArea()
                if !engine.authorized {
                    VStack(spacing: 12) {
                        Image(systemName: "heart.text.square")
                            .font(.system(size: 38))
                            .foregroundColor(crimson)
                        Text(engine.loadStatus)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(ashDim)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 26)
                        if !engine.loadStatus.contains("not available") {
                            Button {
                                Task { await engine.requestAuth() }
                            } label: {
                                Text("GRANT THE BLOOD RITE")
                                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(crimson)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack(spacing: 8) {
                                PMetric(value: String(Int(engine.steps)), unit: "steps", label: "Steps today")
                                PMetric(value: String(format: "%.1f", engine.distanceKm), unit: "km", label: "Distance")
                            }
                            HStack(spacing: 8) {
                                PMetric(value: String(Int(engine.activeEnergy)), unit: "kcal", label: "Active energy")
                                PMetric(value: String(Int(engine.exerciseMinutes)), unit: "min", label: "Exercise")
                            }
                            PCard(title: "01 // THE PULSE (NOW)") {
                                HStack(spacing: 8) {
                                    PMetric(value: engine.heartRateLatest > 0 ? String(Int(engine.heartRateLatest)) : "—", unit: "bpm", label: "Latest HR")
                                    PMetric(value: engine.heartRateMax > 0 ? String(Int(engine.heartRateMax)) : "—", unit: "bpm max", label: "24h peak")
                                }
                                HStack(spacing: 8) {
                                    PMetric(value: engine.restingHR > 0 ? String(Int(engine.restingHR)) : "—", unit: "bpm", label: "Resting HR")
                                    PMetric(value: engine.hrv > 0 ? String(Int(engine.hrv)) : "—", unit: "ms", label: "HRV")
                                }
                                HStack(spacing: 8) {
                                    PMetric(value: engine.spo2 > 0 ? String(format: "%.1f", engine.spo2 * 100) : "—", unit: "%", label: "SpO2")
                                    PMetric(value: engine.respiratoryRate > 0 ? String(format: "%.1f", engine.respiratoryRate) : "—", unit: "br/min", label: "Respiration")
                                }
                            }
                            PCard(title: "02 // LAST NIGHT") {
                                if engine.lastNightTotalMinutes > 0 {
                                    Text(String(format: "%.1f hours in the crypt", engine.lastNightTotalMinutes / 60.0))
                                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                                        .foregroundColor(.white)
                                    SleepStageBar(segments: engine.lastNightSegments)
                                } else {
                                    Text("No sleep stages recorded yet.")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(ashDim)
                                }
                            }
                            if !engine.loadStatus.isEmpty {
                                Text(engine.loadStatus)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(ashDim)
                            }
                        }
                        .padding(14)
                    }
                }
            }
            .navigationTitle("")
            .overlay(alignment: .top) {
                Text("PULSLINE")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                    .padding(.top, 2)
            }
        }
    }
}

struct SleepStageBar: View {
    let segments: [SleepSegment]

    var body: some View {
        let total = max(1.0, segments.reduce(0) { $0 + $1.minutes })
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments) { s in
                    let w = max(2, geo.size.width * (s.minutes / total))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(stageColor(s.stage))
                        .frame(width: w)
                }
            }
        }
        .frame(height: 26)
    }

    private func stageColor(_ stage: String) -> Color {
        switch stage {
        case "DEEP": return bloodDim
        case "REM": return Color(red: 0.9, green: 0.3, blue: 0.45)
        case "CORE": return Color(red: 0.55, green: 0.12, blue: 0.2)
        case "AWAKE": return Color(white: 0.35)
        default: return Color(red: 0.3, green: 0.08, blue: 0.14)
        }
    }
}

// MARK: - HEART

struct HeartView: View {
    @ObservedObject var engine: HealthEngine

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    PCard(title: "01 // RESTING HEART RATE — 30 NIGHTS") {
                        if engine.restingHRTrend.isEmpty {
                            Text("No resting HR data yet.")
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(ashDim)
                        } else {
                            Chart(engine.restingHRTrend) { s in
                                LineMark(x: .value("Day", s.date), y: .value("BPM", s.value))
                                    .foregroundStyle(crimson)
                                AreaMark(x: .value("Day", s.date), y: .value("BPM", s.value))
                                    .foregroundStyle(crimson.opacity(0.15))
                            }
                            .modifier(gothicChartStyle())
                        }
                    }
                    PCard(title: "02 // HEART RATE VARIABILITY — 30 NIGHTS") {
                        if engine.hrvTrend.isEmpty {
                            Text("No HRV data yet.")
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(ashDim)
                        } else {
                            Chart(engine.hrvTrend) { s in
                                BarMark(x: .value("Day", s.date, unit: .day), y: .value("ms", s.value))
                                    .foregroundStyle(bloodDim)
                            }
                            .modifier(gothicChartStyle())
                        }
                    }
                    PCard(title: "03 // BLOOD OXYGEN — 30 NIGHTS (LOWEST)") {
                        if engine.spo2Trend.isEmpty {
                            Text("No SpO2 data yet.")
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(ashDim)
                        } else {
                            Chart(engine.spo2Trend) { s in
                                LineMark(x: .value("Day", s.date), y: .value("%", s.value * 100))
                                    .foregroundStyle(Color(red: 0.9, green: 0.3, blue: 0.45))
                                AreaMark(x: .value("Day", s.date), y: .value("%", s.value * 100))
                                    .foregroundStyle(Color(red: 0.9, green: 0.3, blue: 0.45).opacity(0.12))
                            }
                            .chartYScale(domain: 80...100)
                            .modifier(gothicChartStyle())
                        }
                    }
                }
                .padding(14)
            }
            .background(cryptBg.ignoresSafeArea())
            .navigationTitle("")
            .overlay(alignment: .top) {
                Text("THE PULSE")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - SLEEP

struct SleepView: View {
    @ObservedObject var engine: HealthEngine

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    PCard(title: "01 // LAST NIGHT — STAGES") {
                        if engine.lastNightSegments.isEmpty {
                            Text("No sleep stages recorded yet.")
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(ashDim)
                        } else {
                            HStack {
                                Text(String(format: "%.1f h total", engine.lastNightTotalMinutes / 60.0))
                                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.white)
                                Spacer()
                                ForEach(["DEEP", "REM", "CORE"], id: \.self) { stage in
                                    let mins = engine.lastNightSegments.filter { $0.stage == stage }.reduce(0.0) { $0 + $1.minutes }
                                    VStack(spacing: 2) {
                                        Text(String(format: "%.0fm", mins))
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                        Text(stage)
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(ashDim)
                                    }
                                }
                            }
                            SleepStageBar(segments: engine.lastNightSegments)
                            let deep = engine.lastNightSegments.filter { $0.stage == "DEEP" }.reduce(0.0) { $0 + $1.minutes }
                            let rem = engine.lastNightSegments.filter { $0.stage == "REM" }.reduce(0.0) { $0 + $1.minutes }
                            Text(String(format: "Deep %.0f min · REM %.0f min — the deeper the crypt, the stronger the blood.", deep, rem))
                                .font(.system(size: 11))
                                .foregroundColor(ashDim)
                        }
                    }
                    PCard(title: "02 // SLEEP DURATION — 14 NIGHTS") {
                        if engine.sleepTrend.isEmpty {
                            Text("No sleep duration data yet.")
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(ashDim)
                        } else {
                            Chart(engine.sleepTrend) { s in
                                BarMark(x: .value("Night", s.date, unit: .day), y: .value("Hours", s.value))
                                    .foregroundStyle(Gradient(colors: [bloodDim, crimson]))
                            }
                            .chartYScale(domain: 0...max(10, (engine.sleepTrend.map { $0.value }.max() ?? 8) + 1))
                            .modifier(gothicChartStyle())
                            let avg = engine.sleepTrend.map { $0.value }.reduce(0, +) / Double(max(1, engine.sleepTrend.count))
                            Text(String(format: "Average: %.1f h per night", avg))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ashDim)
                        }
                    }
                }
                .padding(14)
            }
            .background(cryptBg.ignoresSafeArea())
            .navigationTitle("")
            .overlay(alignment: .top) {
                Text("THE SLEEP")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - ACTIVITY

struct ActivityView: View {
    @ObservedObject var engine: HealthEngine

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    PCard(title: "01 // STEPS — 14 DAYS") {
                        if engine.stepsTrend.isEmpty {
                            Text("No step data yet.")
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(ashDim)
                        } else {
                            Chart(engine.stepsTrend) { s in
                                BarMark(x: .value("Day", s.date, unit: .day), y: .value("Steps", s.value))
                                    .foregroundStyle(Gradient(colors: [crimson, bloodDim]))
                            }
                            .modifier(gothicChartStyle())
                            let total = engine.stepsTrend.map { $0.value }.reduce(0, +)
                            let best = engine.stepsTrend.map { $0.value }.max() ?? 0
                            Text(String(format: "Total %.0f · best day %.0f", total, best))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ashDim)
                        }
                    }
                    PCard(title: "02 // RECENT WORKOUTS") {
                        if engine.workouts.isEmpty {
                            Text("No workouts recorded yet.")
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(ashDim)
                        } else {
                            ForEach(engine.workouts.prefix(10)) { w in
                                HStack {
                                    Text(w.type.uppercased())
                                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                        .foregroundColor(crimson)
                                    Spacer()
                                    Text(w.start, style: .date)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(ashDim)
                                }
                                HStack(spacing: 12) {
                                    Text(String(format: "%.0f min", w.minutes))
                                    if w.distanceKm > 0 { Text(String(format: "%.1f km", w.distanceKm)) }
                                    if w.calories > 0 { Text(String(format: "%.0f kcal", w.calories)) }
                                }
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ashText)
                                Divider().background(Color(white: 0.2))
                            }
                        }
                    }
                }
                .padding(14)
            }
            .background(cryptBg.ignoresSafeArea())
            .navigationTitle("")
            .overlay(alignment: .top) {
                Text("THE HUNT")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - CRYPT (privacy)

struct VaultInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                PCard(title: "01 // WHAT PULSLINE READS") {
                    Text("Steps, distance, energy, exercise, heart rate, resting HR, HRV, SpO2, respiration, sleep stages, workouts — read-only, from Apple Health on this device.")
                        .font(.system(size: 12))
                        .foregroundColor(ashText)
                }
                PCard(title: "02 // WHAT PULSLINE NEVER DOES") {
                    ForEach([
                        "No network access — there is no server, no account, no analytics.",
                        "No writes — your health data cannot be modified by this app.",
                        "No storage — everything is queried live from HealthKit and held in memory only.",
                        "No exports — nothing leaves the device unless you screenshot it yourself."
                    ], id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "xmark.shield")
                                .foregroundColor(crimson)
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundColor(ashText)
                        }
                    }
                }
                PCard(title: "03 // NOTES") {
                    Text("All trends come straight from Apple Health — the same data the Health app shows. If a metric is empty, check the Health app has data for it, and that Pulseline has read permission (Settings → Health → Data Access).")
                        .font(.system(size: 12))
                        .foregroundColor(ashDim)
                }
            }
            .padding(14)
        }
        .background(cryptBg.ignoresSafeArea())
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE CRYPT")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
    }
}
