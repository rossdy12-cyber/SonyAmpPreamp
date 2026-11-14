import Foundation
import SwiftUI

enum DisturbanceCategory: String, Codable, CaseIterable, Identifiable {
    case cough = "Coughing"
    case snore = "Snoring"
    case talk = "Sleep Talk"
    case gasp = "Gasping / Apnea"
    case movement = "Movement"
    case ambient = "Room Noise"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .cough: return "Cough"
        case .snore: return "Snore"
        case .talk: return "Talk"
        case .gasp: return "Gasp"
        case .movement: return "Shift"
        case .ambient: return "Noise"
        }
    }

    var icon: String {
        switch self {
        case .cough: return "lungs.fill"
        case .snore: return "waveform.path.ecg"
        case .talk: return "bubble.left.and.waveform.fill"
        case .gasp: return "wind"
        case .movement: return "bed.double.fill"
        case .ambient: return "speaker.wave.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .cough: return Theme.bloodGlow
        case .snore: return Theme.amber
        case .talk: return Theme.violet
        case .gasp: return Color(hex: "FB7185")
        case .movement: return Theme.cyan
        case .ambient: return Theme.muted
        }
    }

    var acousticSignature: String {
        switch self {
        case .cough:
            return "Sharp percussive transient burst (350–1,400 Hz, high crest factor)"
        case .snore:
            return "Rhythmic low-frequency palatal vibration (80–320 Hz harmonic train)"
        case .talk:
            return "Mid-band vocal formant modulation (250–2,200 Hz syllabic envelope)"
        case .gasp:
            return "Silent respiratory pause followed by high-velocity inspiratory gasp"
        case .movement:
            return "Broadband rustling / linen friction & accelerometer shift"
        case .ambient:
            return "External environmental transient outside vocal/respiratory band"
        }
    }
}

enum SleepStage: String, Codable, CaseIterable, Identifiable {
    case awake = "Awake"
    case rem = "REM Dream"
    case light = "Light Slumber"
    case deepTorpor = "Deep Torpor"

    var id: String { rawValue }

    /// Numeric depth for hypnogram plotting (3 = top/Awake, 0 = bottom/Deep Torpor)
    var chartLevel: Double {
        switch self {
        case .awake: return 3.0
        case .rem: return 2.0
        case .light: return 1.0
        case .deepTorpor: return 0.0
        }
    }

    var color: Color {
        switch self {
        case .awake: return Theme.bloodGlow
        case .rem: return Theme.violet
        case .light: return Theme.crimsonBright
        case .deepTorpor: return Color(hex: "7F1D1D")
        }
    }
}

enum PreSleepFactor: String, Codable, CaseIterable, Identifiable {
    case caffeine = "Late Caffeine"
    case alcohol = "Crimson Wine"
    case heavyMeal = "Heavy Feast"
    case lateScreen = "Late Screen"
    case workout = "Training"
    case stress = "High Stress"
    case nasalStrip = "Nasal Strip"
    case mouthTape = "Mouth Tape"
    case coldRoom = "Cold Crypt"
    case backSleeping = "Back Sleep"
    case allergies = "Congestion"
    case humidifier = "Humidifier"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .caffeine: return "cup.and.saucer.fill"
        case .alcohol: return "wineglass.fill"
        case .heavyMeal: return "fork.knife"
        case .lateScreen: return "iphone.radiowaves.left.and.right"
        case .workout: return "figure.run"
        case .stress: return "bolt.heart.fill"
        case .nasalStrip: return "bandage.fill"
        case .mouthTape: return "mouth.fill"
        case .coldRoom: return "snowflake"
        case .backSleeping: return "figure.walk.arrival"
        case .allergies: return "allergens"
        case .humidifier: return "humidity.fill"
        }
    }

    var isRemedy: Bool {
        switch self {
        case .nasalStrip, .mouthTape, .coldRoom, .humidifier:
            return true
        default:
            return false
        }
    }
}

enum WindDownSound: String, Codable, CaseIterable, Identifiable {
    case off = "Silence"
    case cryptRain = "Crypt Rain"
    case velvetBrown = "Velvet Brown Noise"
    case cathedralDrone = "Cathedral Drone"
    case midnightWind = "Midnight Wind"
    case deltaPulse = "432Hz Delta Pulse"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .off: return "speaker.slash.fill"
        case .cryptRain: return "cloud.heavyrain.fill"
        case .velvetBrown: return "waveform"
        case .cathedralDrone: return "bell.and.waves.left.and.right.fill"
        case .midnightWind: return "wind"
        case .deltaPulse: return "moon.stars.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .off: return "No sleep aid soundscape"
        case .cryptRain: return "Deep stone resonance & steady nocturnal rainfall"
        case .velvetBrown: return "Low-pass filtered warm acoustic masking"
        case .cathedralDrone: return "Sub-harmonic 64 Hz + 96 Hz dark ambient chord"
        case .midnightWind: return "Slowly sweeping gothic cavern airflow"
        case .deltaPulse: return "432 Hz carrier with 2.5 Hz delta binaural beat"
        }
    }
}

enum SensitivityPreset: String, Codable, CaseIterable, Identifiable {
    case low = "Low (+14 dB)"
    case balanced = "Balanced (+9 dB)"
    case high = "High (+6 dB)"
    case vampiric = "Vampiric (+3.5 dB)"

    var id: String { rawValue }

    var thresholdDeltaDb: Double {
        switch self {
        case .low: return 14.0
        case .balanced: return 9.0
        case .high: return 6.0
        case .vampiric: return 3.5
        }
    }

    var description: String {
        switch self {
        case .low: return "Captures only loud coughs & heavy snoring"
        case .balanced: return "Ideal for nightly coughing, snoring & sleep talk"
        case .high: return "Captures light snores, murmurs & subtle gasps"
        case .vampiric: return "Ultra-sensitive hair-trigger acoustic capture"
        }
    }
}

struct DisturbanceEvent: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date
    var durationSeconds: Double
    var peakDecibels: Double
    var avgDecibels: Double
    var category: DisturbanceCategory
    var confidence: Double
    var audioFileName: String?
    var waveformSamples: [Float]
    var isBookmarked: Bool = false
    var userNote: String = ""
    var frequencyCentroidHz: Double = 240.0
}

struct HypnogramPoint: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestamp: Date
    var stage: SleepStage
    var decibels: Double
    var motionEnergy: Double
}

struct SleepSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var startDate: Date
    var endDate: Date
    var factors: [PreSleepFactor]
    var events: [DisturbanceEvent]
    var timeline: [HypnogramPoint]
    var sleepQualityScore: Int
    var snoreScore: Int
    var coughCount: Int
    var snoreCount: Int
    var talkCount: Int
    var gaspCount: Int
    var snoreDurationMinutes: Double
    var peakDecibels: Double
    var avgDecibels: Double
    var notes: String = ""
    var wokeBySmartAlarm: Bool = false

    var durationHours: Double {
        max(0.1, endDate.timeIntervalSince(startDate) / 3600.0)
    }

    var durationFormatted: String {
        let totalMinutes = Int(max(1, endDate.timeIntervalSince(startDate) / 60.0))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return "\(h)h \(String(format: "%02dm", m))"
    }

    var disturbancesPerHour: Double {
        Double(events.count) / durationHours
    }

    func minutes(in stage: SleepStage) -> Int {
        guard timeline.count > 1 else { return 0 }
        let totalMins = endDate.timeIntervalSince(startDate) / 60.0
        let matches = timeline.filter { $0.stage == stage }.count
        return Int(round((Double(matches) / Double(timeline.count)) * totalMins))
    }

    func percentage(in stage: SleepStage) -> Int {
        guard !timeline.isEmpty else { return 0 }
        let matches = timeline.filter { $0.stage == stage }.count
        return Int(round((Double(matches) / Double(timeline.count)) * 100.0))
    }
}
