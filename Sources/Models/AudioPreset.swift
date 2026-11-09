import Foundation

struct EQPreset: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var subtitle: String
    var icon: String
    /// Pre-amp digital line-driver boost in dB (-6.0 to +12.0 dB)
    var preampGainDB: Float
    /// Dedicated Sub-Bass / MegaBass harmonic shelf boost in dB (0.0 to +8.0 dB)
    var megaBassDB: Float
    /// High-frequency air / brilliance exciter in dB (0.0 to +6.0 dB)
    var brillianceDB: Float
    /// Enables Apple CoreAudio PeakLimiter to prevent 0 dBFS digital clipping
    var softLimiterEnabled: Bool
    /// 10-band ISO frequencies: 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz (-12 to +12 dB)
    var bands: [Float]

    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let frequencyLabels: [String] = ["31", "62", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

    static let builtInPresets: [EQPreset] = [
        EQPreset(
            id: "sony_line_driver",
            name: "Sony ES Line-Driver",
            subtitle: "Auto USB-C 0.5V → 1.4Vrms Boost + Warm Hi-Fi Curve",
            icon: "cable.connector.horizontal",
            preampGainDB: 7.5,
            megaBassDB: 2.5,
            brillianceDB: 1.5,
            softLimiterEnabled: true,
            bands: [3.5, 3.0, 1.5, 0.5, 0.0, 0.0, 0.5, 1.0, 1.5, 2.0]
        ),
        EQPreset(
            id: "sony_megabass",
            name: "Sony MegaBass EX",
            subtitle: "Deep Sub-Bass Slam & Crisp Highs for Stereo Amps",
            icon: "speaker.wave.3.fill",
            preampGainDB: 8.0,
            megaBassDB: 5.0,
            brillianceDB: 2.5,
            softLimiterEnabled: true,
            bands: [6.0, 7.0, 4.0, 0.5, -1.0, 0.0, 1.5, 2.5, 3.5, 4.0]
        ),
        EQPreset(
            id: "metal_rock_punch",
            name: "Metal & Rock Punch",
            subtitle: "Tight Double-Kick, Mid Clarity & +8.5 dB Line Drive",
            icon: "guitars.fill",
            preampGainDB: 8.5,
            megaBassDB: 3.5,
            brillianceDB: 2.0,
            softLimiterEnabled: true,
            bands: [4.5, 5.5, 2.5, -1.5, -1.0, 1.0, 3.0, 4.0, 3.5, 2.5]
        ),
        EQPreset(
            id: "reference_2v_flat",
            name: "Pure 2V Reference Flat",
            subtitle: "Uncolored +9.5 dB Pre-Amp Voltage Boost (0 dB EQ)",
            icon: "waveform.path.ecg",
            preampGainDB: 9.5,
            megaBassDB: 0.0,
            brillianceDB: 0.0,
            softLimiterEnabled: true,
            bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        ),
        EQPreset(
            id: "loudness_contour",
            name: "Fletcher-Munson Loudness",
            subtitle: "Full-Bodied Bass & Treble at Low Amp Volumes",
            icon: "dial.high.fill",
            preampGainDB: 6.5,
            megaBassDB: 4.0,
            brillianceDB: 3.0,
            softLimiterEnabled: true,
            bands: [5.5, 4.5, 2.0, 0.0, -1.5, -1.0, 0.5, 2.0, 4.0, 5.0]
        ),
        EQPreset(
            id: "vocal_acoustic",
            name: "Vocal & Acoustic Stage",
            subtitle: "Warm Tube-Style Midrange Presence & Air",
            icon: "music.mic",
            preampGainDB: 6.5,
            megaBassDB: 1.5,
            brillianceDB: 2.5,
            softLimiterEnabled: true,
            bands: [2.0, 2.5, 1.0, 1.5, 2.5, 3.0, 2.5, 1.5, 2.5, 3.5]
        )
    ]
}
