import Foundation
import SwiftUI

@MainActor
final class SleepStore: ObservableObject {
    static let shared = SleepStore()

    @Published var sessions: [SleepSession] = []
    @Published var selectedFactors: Set<PreSleepFactor> = [.coldRoom]
    @Published var sessionNotesDraft: String = ""

    // Smart Alarm & Acoustic Settings
    @Published var smartAlarmEnabled: Bool = true { didSet { saveSettings() } }
    @Published var alarmHour: Int = 7 { didSet { saveSettings() } }
    @Published var alarmMinute: Int = 15 { didSet { saveSettings() } }
    @Published var wakeWindowMinutes: Int = 20 { didSet { saveSettings() } }
    @Published var sensitivityPreset: SensitivityPreset = .balanced { didSet { saveSettings() } }
    @Published var clipDurationSeconds: Int = 8 { didSet { saveSettings() } }
    @Published var windDownSound: WindDownSound = .cryptRain { didSet { saveSettings() } }
    @Published var windDownMinutes: Int = 20 { didSet { saveSettings() } }

    private let sessionsFileURL: URL
    private let settingsKey = "torpor_settings_v1"

    private struct PersistedSettings: Codable {
        var smartAlarmEnabled: Bool
        var alarmHour: Int
        var alarmMinute: Int
        var wakeWindowMinutes: Int
        var sensitivityPreset: SensitivityPreset
        var clipDurationSeconds: Int
        var windDownSound: WindDownSound
        var windDownMinutes: Int
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        sessionsFileURL = docs.appendingPathComponent("torpor_sessions.json")
        loadSettings()
        loadSessions()
        if sessions.isEmpty {
            seedSampleSessions()
        }
    }

    var alarmTimeFormatted: String {
        String(format: "%02d:%02d", alarmHour, alarmMinute)
    }

    var wakeWindowFormatted: String {
        let total = alarmHour * 60 + alarmMinute - wakeWindowMinutes
        let wrapped = (total + 1440) % 1440
        let h = wrapped / 60
        let m = wrapped % 60
        return "\(String(format: "%02d:%02d", h, m)) – \(alarmTimeFormatted)"
    }

    func toggleFactor(_ factor: PreSleepFactor) {
        if selectedFactors.contains(factor) {
            selectedFactors.remove(factor)
        } else {
            selectedFactors.insert(factor)
        }
    }

    func addSession(_ session: SleepSession) {
        sessions.insert(session, at: 0)
        saveSessions()
    }

    func deleteSession(_ session: SleepSession) {
        sessions.removeAll { $0.id == session.id }
        saveSessions()
    }

    func toggleBookmark(sessionID: UUID, eventID: UUID) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionID }),
              let eIdx = sessions[sIdx].events.firstIndex(where: { $0.id == eventID }) else { return }
        sessions[sIdx].events[eIdx].isBookmarked.toggle()
        saveSessions()
    }

    func reclassifyEvent(sessionID: UUID, eventID: UUID, newCategory: DisturbanceCategory) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionID }),
              let eIdx = sessions[sIdx].events.firstIndex(where: { $0.id == eventID }) else { return }
        sessions[sIdx].events[eIdx].category = newCategory
        recomputeCounts(forSessionAt: sIdx)
        saveSessions()
    }

    func updateEventNote(sessionID: UUID, eventID: UUID, note: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionID }),
              let eIdx = sessions[sIdx].events.firstIndex(where: { $0.id == eventID }) else { return }
        sessions[sIdx].events[eIdx].userNote = note
        saveSessions()
    }

    private func recomputeCounts(forSessionAt sIdx: Int) {
        let evs = sessions[sIdx].events
        sessions[sIdx].coughCount = evs.filter { $0.category == .cough }.count
        sessions[sIdx].snoreCount = evs.filter { $0.category == .snore }.count
        sessions[sIdx].talkCount = evs.filter { $0.category == .talk }.count
        sessions[sIdx].gaspCount = evs.filter { $0.category == .gasp }.count
    }

    // MARK: - Analytics & Factor Correlations

    var averageQualityScore: Int {
        guard !sessions.isEmpty else { return 0 }
        let sum = sessions.reduce(0) { $0 + $1.sleepQualityScore }
        return Int(round(Double(sum) / Double(sessions.count)))
    }

    var averageSnoreScore: Int {
        guard !sessions.isEmpty else { return 0 }
        let sum = sessions.reduce(0) { $0 + $1.snoreScore }
        return Int(round(Double(sum) / Double(sessions.count)))
    }

    var averageSleepHours: Double {
        guard !sessions.isEmpty else { return 0.0 }
        let sum = sessions.reduce(0.0) { $0 + $1.durationHours }
        return (sum / Double(sessions.count) * 10).rounded() / 10.0
    }

    var totalRecordedClipsCount: Int {
        sessions.reduce(0) { $0 + $1.events.count }
    }

    struct FactorImpact: Identifiable {
        var id: String { factor.rawValue }
        let factor: PreSleepFactor
        let nightsCount: Int
        let avgCoughs: Double
        let avgSnores: Double
        let avgQuality: Int
        let deltaDisturbancesPercent: Int
    }

    var factorImpacts: [FactorImpact] {
        guard !sessions.isEmpty else { return [] }
        let baselineDist = Double(sessions.reduce(0) { $0 + $1.coughCount + $1.snoreCount }) / Double(sessions.count)

        var results: [FactorImpact] = []
        for f in PreSleepFactor.allCases {
            let matching = sessions.filter { $0.factors.contains(f) }
            guard !matching.isEmpty else { continue }
            let cAvg = Double(matching.reduce(0) { $0 + $1.coughCount }) / Double(matching.count)
            let sAvg = Double(matching.reduce(0) { $0 + $1.snoreCount }) / Double(matching.count)
            let qAvg = matching.reduce(0) { $0 + $1.sleepQualityScore } / matching.count
            let combined = cAvg + sAvg
            let pct = baselineDist > 0.1 ? Int(round(((combined - baselineDist) / baselineDist) * 100.0)) : 0
            results.append(
                FactorImpact(
                    factor: f,
                    nightsCount: matching.count,
                    avgCoughs: (cAvg * 10).rounded() / 10.0,
                    avgSnores: (sAvg * 10).rounded() / 10.0,
                    avgQuality: qAvg,
                    deltaDisturbancesPercent: pct
                )
            )
        }
        return results.sorted { abs($0.deltaDisturbancesPercent) > abs($1.deltaDisturbancesPercent) }
    }

    func exportCSVReport() -> URL {
        var csv = "Date,Start,End,DurationHours,SleepQuality,SnoreScore,Coughs,Snores,Talks,Gasps,SnoreMins,PeakdB,Factors\n"
        let df = ISO8601DateFormatter()
        for s in sessions {
            let fStr = s.factors.map(\.rawValue).joined(separator: "|")
            csv += "\(df.string(from: s.startDate)),\(df.string(from: s.startDate)),\(df.string(from: s.endDate)),\(String(format: "%.2f", s.durationHours)),\(s.sleepQualityScore),\(s.snoreScore),\(s.coughCount),\(s.snoreCount),\(s.talkCount),\(s.gaspCount),\(s.snoreDurationMinutes),\(s.peakDecibels),\"\(fStr)\"\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Torpor_Sleep_Report.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Persistence & Demo Night Generator

    func saveSessions() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(sessions) {
            try? data.write(to: sessionsFileURL, options: .atomic)
        }
    }

    private func loadSessions() {
        guard let data = try? Data(contentsOf: sessionsFileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let decoded = try? dec.decode([SleepSession].self, from: data) {
            sessions = decoded
        }
    }

    private func saveSettings() {
        let s = PersistedSettings(
            smartAlarmEnabled: smartAlarmEnabled,
            alarmHour: alarmHour,
            alarmMinute: alarmMinute,
            wakeWindowMinutes: wakeWindowMinutes,
            sensitivityPreset: sensitivityPreset,
            clipDurationSeconds: clipDurationSeconds,
            windDownSound: windDownSound,
            windDownMinutes: windDownMinutes
        )
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let s = try? JSONDecoder().decode(PersistedSettings.self, from: data) else { return }
        smartAlarmEnabled = s.smartAlarmEnabled
        alarmHour = s.alarmHour
        alarmMinute = s.alarmMinute
        wakeWindowMinutes = s.wakeWindowMinutes
        sensitivityPreset = s.sensitivityPreset
        clipDurationSeconds = s.clipDurationSeconds
        windDownSound = s.windDownSound
        windDownMinutes = s.windDownMinutes
    }

    func generateAdditionalDemoNight() {
        let night = Self.buildRealisticSession(
            daysAgo: 0,
            bedHour: 23,
            bedMin: 20,
            durationHours: 7.6,
            factors: [.coldRoom, .nasalStrip],
            coughCount: Int.random(in: 2...5),
            snoreCount: Int.random(in: 3...7),
            talkCount: Int.random(in: 1...2),
            gaspCount: Int.random(in: 0...1),
            quality: Int.random(in: 81...92),
            snoreScore: Int.random(in: 18...34),
            note: "Simulated overnight acoustic & actigraphy capture."
        )
        addSession(night)
    }

    private func seedSampleSessions() {
        let presets: [(Int, Int, Int, Double, [PreSleepFactor], Int, Int, Int, Int, Int, Int, String)] = [
            (1, 23, 35, 7.6, [.coldRoom, .nasalStrip], 2, 4, 1, 0, 88, 19, "Restful chamber sleep; two brief dry coughs around 03:15 AM."),
            (2, 0, 15, 6.8, [.alcohol, .backSleeping, .lateScreen], 6, 11, 2, 1, 66, 54, "Heavy snoring cluster during back-sleeping phase between 02:00–04:10 AM."),
            (3, 23, 10, 8.1, [.coldRoom, .mouthTape, .humidifier], 1, 2, 0, 0, 94, 11, "Deepest torpor cycle of the week; humidifier reduced throat irritation."),
            (4, 23, 50, 7.1, [.caffeine, .allergies], 7, 5, 1, 1, 72, 38, "Congestion triggered coughing spikes at 01:40 AM and 04:55 AM."),
            (5, 22, 55, 7.8, [.workout, .coldRoom, .nasalStrip], 2, 3, 1, 0, 90, 16, "Strong Deep Torpor recovery after evening training.")
        ]

        var built: [SleepSession] = []
        for p in presets {
            built.append(
                Self.buildRealisticSession(
                    daysAgo: p.0,
                    bedHour: p.1,
                    bedMin: p.2,
                    durationHours: p.3,
                    factors: p.4,
                    coughCount: p.5,
                    snoreCount: p.6,
                    talkCount: p.7,
                    gaspCount: p.8,
                    quality: p.9,
                    snoreScore: p.10,
                    note: p.11
                )
            )
        }
        sessions = built
        saveSessions()
    }

    private static func buildRealisticSession(
        daysAgo: Int,
        bedHour: Int,
        bedMin: Int,
        durationHours: Double,
        factors: [PreSleepFactor],
        coughCount: Int,
        snoreCount: Int,
        talkCount: Int,
        gaspCount: Int,
        quality: Int,
        snoreScore: Int,
        note: String
    ) -> SleepSession {
        let cal = Calendar.current
        let now = Date()
        let baseDay = cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        var comps = cal.dateComponents([.year, .month, .day], from: baseDay)
        comps.hour = bedHour
        comps.minute = bedMin
        var start = cal.date(from: comps) ?? baseDay
        if bedHour >= 20 {
            start = cal.date(byAdding: .day, value: -1, to: start) ?? start
        }
        let end = start.addingTimeInterval(durationHours * 3600.0)

        // Build 60 hypnogram points across the night
        var timeline: [HypnogramPoint] = []
        let steps = 60
        for i in 0..<steps {
            let frac = Double(i) / Double(steps - 1)
            let ptDate = start.addingTimeInterval(frac * durationHours * 3600.0)
            let cycle = sin(frac * .pi * 4.2)
            let stage: SleepStage
            if i < 3 || i == steps - 1 {
                stage = .awake
            } else if cycle < -0.35 && frac < 0.65 {
                stage = .deepTorpor
            } else if cycle > 0.45 && frac > 0.22 {
                stage = .rem
            } else {
                stage = .light
            }
            let db = 34.0 + (stage == .deepTorpor ? 2.5 : (stage == .rem ? 5.5 : 4.0)) + Double((i * 7) % 5)
            timeline.append(
                HypnogramPoint(
                    timestamp: ptDate,
                    stage: stage,
                    decibels: db,
                    motionEnergy: stage == .awake ? 0.09 : 0.015
                )
            )
        }

        // Build disturbance events and write real playable WAV clips
        var events: [DisturbanceEvent] = []
        func appendEvents(count: Int, cat: DisturbanceCategory, baseDb: Double, dur: Double) {
            guard count > 0 else { return }
            for idx in 0..<count {
                let offsetFrac = Double(idx + 1) / Double(count + 1)
                let jitter = Double(((idx + 3) * 17) % 19) * 60.0
                let evDate = start.addingTimeInterval(offsetFrac * durationHours * 3600.0 + jitter)
                let fileName = "seed_d\(daysAgo)_\(cat.shortLabel.lowercased())_\(idx).wav"
                SynthesizedAudioGenerator.ensureDisturbanceClipWAV(
                    fileName: fileName,
                    category: cat,
                    durationSeconds: dur
                )
                let peak = baseDb + Double((idx * 5) % 9)
                let wf: [Float] = (0..<36).map { bar in
                    let p = Double(bar) / 35.0
                    let env = Float(sin(p * .pi))
                    let mod = Float(0.55 + 0.45 * sin(Double(bar * (idx + 2)) * 0.7))
                    return max(0.12, min(0.96, env * mod))
                }
                events.append(
                    DisturbanceEvent(
                        timestamp: evDate,
                        durationSeconds: dur,
                        peakDecibels: peak,
                        avgDecibels: peak - 7.5,
                        category: cat,
                        confidence: 0.92,
                        audioFileName: fileName,
                        waveformSamples: wf,
                        isBookmarked: idx == 0 && (cat == .cough || cat == .snore),
                        userNote: "",
                        frequencyCentroidHz: cat == .cough ? 680.0 : (cat == .snore ? 142.0 : 410.0)
                    )
                )
            }
        }

        appendEvents(count: coughCount, cat: .cough, baseDb: 65.0, dur: 3.5)
        appendEvents(count: snoreCount, cat: .snore, baseDb: 56.0, dur: 5.2)
        appendEvents(count: talkCount, cat: .talk, baseDb: 52.0, dur: 4.4)
        appendEvents(count: gaspCount, cat: .gasp, baseDb: 63.0, dur: 3.8)
        events.sort { $0.timestamp < $1.timestamp }

        let peakDb = events.map(\.peakDecibels).max() ?? 48.0
        let snoreMins = Double(snoreCount) * 3.4

        return SleepSession(
            startDate: start,
            endDate: end,
            factors: factors,
            events: events,
            timeline: timeline,
            sleepQualityScore: quality,
            snoreScore: snoreScore,
            coughCount: coughCount,
            snoreCount: snoreCount,
            talkCount: talkCount,
            gaspCount: gaspCount,
            snoreDurationMinutes: (snoreMins * 10).rounded() / 10.0,
            peakDecibels: peakDb,
            avgDecibels: 38.5,
            notes: note,
            wokeBySmartAlarm: true
        )
    }
}
