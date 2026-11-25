import Foundation
import AVFoundation

enum PresetDeviceProfile: String, Codable, CaseIterable, Identifiable {
    case sonyAmp = "sony_amp"
    case airPodsPro2 = "airpods_pro_2"
    case custom = "custom"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .sonyAmp: return "Sony ES Line-Driver"
        case .airPodsPro2: return "AirPods Pro 2 H2 DSP"
        case .custom: return "Custom User Profiles"
        }
    }
}

enum SpatialRoomStyle: String, Codable, CaseIterable, Identifiable {
    case studioBooth = "studio_booth"
    case jazzClub = "jazz_club"
    case concertHall = "concert_hall"
    case cathedral = "cathedral"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studioBooth: return "Studio Booth"
        case .jazzClub: return "Intimate Club"
        case .concertHall: return "Concert Hall"
        case .cathedral: return "Cathedral"
        }
    }

    var avPreset: AVAudioUnitReverbPreset {
        switch self {
        case .studioBooth: return .smallRoom
        case .jazzClub: return .mediumChamber
        case .concertHall: return .largeHall2
        case .cathedral: return .cathedral
        }
    }
}

struct EQPreset: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    var targetProfile: PresetDeviceProfile = .sonyAmp
    let preampGainDB: Float
    let megaBassDB: Float
    let brillianceDB: Float
    /// 10-band ISO center frequencies: 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz
    let bands: [Float]

    // AirPods Pro 2 H2 Acoustic & Spatial Sounding Controls
    var airPodsSubBassDB: Float = 0.0        // 45 Hz H2 driver sub-bass extension (0...+8 dB)
    var airPodsVocalPresenceDB: Float = 0.0  // 3.2 kHz ear-canal pinna contour (-4...+6 dB)
    var airPodsSilkAirDB: Float = 0.0        // 14 kHz DSEE AAC harmonic air restore (0...+6 dB)
    var stereoWidthPercent: Float = 100.0    // 50% (Crossfeed) ... 100% (Natural) ... 150% (Wide Stage)
    var spatialReverbMix: Float = 0.0        // 0...45% wet spatial room mix
    var spatialRoomStyle: SpatialRoomStyle = .studioBooth

    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let frequencyLabels: [String] = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    static let sonyPresets: [EQPreset] = [
        EQPreset(
            id: "sony_line_driver",
            name: "Sony ES Line-Driver",
            subtitle: "Restores full 1.2V–2.0V AUX line level + warm low-end",
            icon: "hifispeaker.2.fill",
            targetProfile: .sonyAmp,
            preampGainDB: 7.5,
            megaBassDB: 3.5,
            brillianceDB: 2.0,
            bands: [3.0, 4.0, 2.5, 0.5, 0.0, 0.5, 1.5, 2.0, 2.5, 2.0],
            airPodsSubBassDB: 2.0,
            airPodsVocalPresenceDB: 1.0,
            airPodsSilkAirDB: 1.5,
            stereoWidthPercent: 105.0,
            spatialReverbMix: 0.0,
            spatialRoomStyle: .studioBooth
        ),
        EQPreset(
            id: "sony_megabass",
            name: "Sony MegaBass+",
            subtitle: "Deep 31–62Hz sub-harmonic slam + crisp highs",
            icon: "speaker.wave.3.fill",
            targetProfile: .sonyAmp,
            preampGainDB: 8.5,
            megaBassDB: 6.5,
            brillianceDB: 3.0,
            bands: [6.0, 7.0, 4.5, 1.0, -0.5, 0.0, 1.5, 2.5, 3.5, 3.0],
            airPodsSubBassDB: 5.0,
            airPodsVocalPresenceDB: 1.0,
            airPodsSilkAirDB: 2.5,
            stereoWidthPercent: 110.0,
            spatialReverbMix: 0.0,
            spatialRoomStyle: .studioBooth
        ),
        EQPreset(
            id: "metal_rock_punch",
            name: "Heavy Guitar & Kick",
            subtitle: "Tight double-kick punch, scooped mud, forward guitars",
            icon: "guitars.fill",
            targetProfile: .sonyAmp,
            preampGainDB: 8.0,
            megaBassDB: 4.5,
            brillianceDB: 3.5,
            bands: [4.5, 5.5, 3.0, -1.5, -1.0, 1.5, 3.0, 3.5, 3.0, 2.5],
            airPodsSubBassDB: 4.0,
            airPodsVocalPresenceDB: 2.0,
            airPodsSilkAirDB: 3.0,
            stereoWidthPercent: 115.0,
            spatialReverbMix: 4.0,
            spatialRoomStyle: .studioBooth
        ),
        EQPreset(
            id: "reference_2v_flat",
            name: "Pure 2V Reference",
            subtitle: "Clean +9.5dB voltage boost with flat studio response",
            icon: "waveform.path.ecg",
            targetProfile: .sonyAmp,
            preampGainDB: 9.5,
            megaBassDB: 0.0,
            brillianceDB: 0.0,
            bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            airPodsSubBassDB: 0.0,
            airPodsVocalPresenceDB: 0.0,
            airPodsSilkAirDB: 0.0,
            stereoWidthPercent: 100.0,
            spatialReverbMix: 0.0,
            spatialRoomStyle: .studioBooth
        ),
        EQPreset(
            id: "loudness_contour",
            name: "Late-Night Loudness",
            subtitle: "Fletcher-Munson bass & treble contour for rich fullness",
            icon: "moon.stars.fill",
            targetProfile: .sonyAmp,
            preampGainDB: 6.5,
            megaBassDB: 5.0,
            brillianceDB: 4.0,
            bands: [5.5, 4.5, 2.0, 0.0, -1.0, -0.5, 1.0, 2.5, 4.0, 4.5],
            airPodsSubBassDB: 4.0,
            airPodsVocalPresenceDB: 0.5,
            airPodsSilkAirDB: 3.5,
            stereoWidthPercent: 105.0,
            spatialReverbMix: 6.0,
            spatialRoomStyle: .jazzClub
        ),
        EQPreset(
            id: "vocal_acoustic",
            name: "Hi-Res Vocal & Stage",
            subtitle: "Warm midrange presence & airy soundstage",
            icon: "music.mic",
            targetProfile: .sonyAmp,
            preampGainDB: 7.0,
            megaBassDB: 2.0,
            brillianceDB: 2.5,
            bands: [1.5, 2.0, 1.5, 1.0, 2.0, 3.0, 3.0, 2.0, 2.5, 3.0],
            airPodsSubBassDB: 1.5,
            airPodsVocalPresenceDB: 3.0,
            airPodsSilkAirDB: 2.5,
            stereoWidthPercent: 120.0,
            spatialReverbMix: 10.0,
            spatialRoomStyle: .jazzClub
        )
    ]

    static let airPodsPro2Presets: [EQPreset] = [
        EQPreset(
            id: "airpods_pro2_harman",
            name: "AirPods Pro 2 Harman Ref",
            subtitle: "H2 45Hz sub-shelf, de-mudded 250Hz, 3.2kHz pinna & 14kHz DSEE air",
            icon: "airpodspro",
            targetProfile: .airPodsPro2,
            preampGainDB: 1.5,
            megaBassDB: 2.5,
            brillianceDB: 1.5,
            bands: [4.0, 3.5, 1.5, -1.5, -0.5, 0.5, 2.0, 2.0, 1.5, 2.0],
            airPodsSubBassDB: 4.0,
            airPodsVocalPresenceDB: 2.0,
            airPodsSilkAirDB: 2.0,
            stereoWidthPercent: 118.0,
            spatialReverbMix: 0.0,
            spatialRoomStyle: .studioBooth
        ),
        EQPreset(
            id: "airpods_pro2_bass_slam",
            name: "AirPods Pro 2 Sub-Slam",
            subtitle: "Maximum H2 low-distortion 45Hz sub-bass authority & clean vocals",
            icon: "waveform.circle.fill",
            targetProfile: .airPodsPro2,
            preampGainDB: 2.0,
            megaBassDB: 5.5,
            brillianceDB: 2.5,
            bands: [6.5, 6.0, 3.5, -1.0, -0.5, 0.5, 1.5, 2.0, 2.5, 3.0],
            airPodsSubBassDB: 6.5,
            airPodsVocalPresenceDB: 1.5,
            airPodsSilkAirDB: 3.0,
            stereoWidthPercent: 115.0,
            spatialReverbMix: 5.0,
            spatialRoomStyle: .studioBooth
        ),
        EQPreset(
            id: "airpods_pro2_spatial_stage",
            name: "AirPods Pro 2 3D Concert",
            subtitle: "140% out-of-head holographic stage + Concert Hall spatial acoustics",
            icon: "dot.radiowaves.left.and.right",
            targetProfile: .airPodsPro2,
            preampGainDB: 1.5,
            megaBassDB: 3.0,
            brillianceDB: 2.0,
            bands: [3.5, 3.0, 1.5, -0.5, 0.0, 1.0, 2.5, 2.5, 2.0, 2.5],
            airPodsSubBassDB: 3.5,
            airPodsVocalPresenceDB: 2.5,
            airPodsSilkAirDB: 3.0,
            stereoWidthPercent: 140.0,
            spatialReverbMix: 18.0,
            spatialRoomStyle: .concertHall
        ),
        EQPreset(
            id: "airpods_pro2_vocal_hd",
            name: "AirPods Pro 2 Vocal Studio",
            subtitle: "Forward intimate vocals, sibilance control & studio booth imaging",
            icon: "person.wave.2.fill",
            targetProfile: .airPodsPro2,
            preampGainDB: 1.5,
            megaBassDB: 1.5,
            brillianceDB: 2.0,
            bands: [1.5, 2.0, 1.0, -1.0, 1.5, 3.0, 3.5, 2.5, 1.5, 2.5],
            airPodsSubBassDB: 2.0,
            airPodsVocalPresenceDB: 4.0,
            airPodsSilkAirDB: 2.5,
            stereoWidthPercent: 112.0,
            spatialReverbMix: 8.0,
            spatialRoomStyle: .studioBooth
        ),
        EQPreset(
            id: "airpods_pro2_metal_rock",
            name: "AirPods Pro 2 Rock & Metal",
            subtitle: "Fast double-kick attack, biting guitars & zero 6kHz ear fatigue",
            icon: "guitars.fill",
            targetProfile: .airPodsPro2,
            preampGainDB: 2.0,
            megaBassDB: 4.0,
            brillianceDB: 2.5,
            bands: [4.5, 5.0, 2.5, -2.0, -1.0, 2.0, 3.5, 2.5, 1.5, 3.0],
            airPodsSubBassDB: 4.5,
            airPodsVocalPresenceDB: 2.5,
            airPodsSilkAirDB: 3.5,
            stereoWidthPercent: 122.0,
            spatialReverbMix: 5.0,
            spatialRoomStyle: .jazzClub
        ),
        EQPreset(
            id: "airpods_pro2_late_night",
            name: "AirPods Pro 2 Velvet Night",
            subtitle: "Warm sub-pillow, relaxed upper-mids & crossfeed for zero fatigue",
            icon: "moon.zzz.fill",
            targetProfile: .airPodsPro2,
            preampGainDB: 0.5,
            megaBassDB: 3.5,
            brillianceDB: 1.5,
            bands: [4.5, 4.0, 2.5, 0.5, 0.0, -1.0, -1.5, -0.5, 1.5, 2.5],
            airPodsSubBassDB: 4.5,
            airPodsVocalPresenceDB: -1.5,
            airPodsSilkAirDB: 2.0,
            stereoWidthPercent: 85.0,
            spatialReverbMix: 12.0,
            spatialRoomStyle: .jazzClub
        )
    ]

    static var builtInPresets: [EQPreset] {
        sonyPresets + airPodsPro2Presets
    }
}
