import Foundation
import AVFoundation

enum SynthesizedAudioGenerator {
    static var clipsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Clips", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var soundsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Sounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func clipURL(for fileName: String) -> URL {
        clipsDirectory.appendingPathComponent(fileName)
    }

    /// Generates a playable 16-bit PCM WAV file for a disturbance clip if it doesn't already exist.
    @discardableResult
    static func ensureDisturbanceClipWAV(
        fileName: String,
        category: DisturbanceCategory,
        durationSeconds: Double = 4.0
    ) -> URL {
        let url = clipURL(for: fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let sampleRate = 22050
        let totalSamples = max(2205, Int(Double(sampleRate) * min(12.0, max(2.0, durationSeconds))))
        var samples = [Int16](repeating: 0, count: totalSamples)

        var rngState: UInt64 = UInt64(abs(fileName.hashValue)) | 1
        func nextRand() -> Double {
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            let val = Double((rngState >> 33) & 0x7FFFFFFF) / Double(0x7FFFFFFF)
            return val * 2.0 - 1.0
        }

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            var sig = nextRand() * 0.015 // subtle room floor

            switch category {
            case .cough:
                // Two sharp percussive expulsive cough bursts at t=0.45s and t=1.25s
                for burstStart in [0.45, 1.25, 2.35] where burstStart < durationSeconds - 0.3 {
                    let dt = t - burstStart
                    if dt >= 0 && dt < 0.32 {
                        let env = exp(-dt * 14.0) * sin(min(1.0, dt * 60.0) * .pi * 0.5)
                        let resonant = sin(2.0 * .pi * 420.0 * t) * 0.45
                            + sin(2.0 * .pi * 780.0 * t) * 0.30
                            + nextRand() * 0.65
                        sig += env * resonant * 0.85
                    }
                }
            case .snore:
                // Rhythmic palatal vibration bursts every ~1.8s
                let cycle = fmod(t, 1.85)
                if cycle > 0.25 && cycle < 1.25 {
                    let phase = (cycle - 0.25) / 1.0
                    let env = sin(phase * .pi)
                    let f0 = 115.0 + 18.0 * sin(2.0 * .pi * 3.0 * t)
                    let rattle = sin(2.0 * .pi * f0 * t) * 0.50
                        + sin(2.0 * .pi * (f0 * 2.0) * t) * 0.28
                        + sin(2.0 * .pi * (f0 * 3.0) * t) * 0.15
                        + nextRand() * 0.22
                    sig += env * rattle * 0.72
                }
            case .talk:
                // Syllabic formant-like murmur envelope
                let syll = max(0.0, sin(2.0 * .pi * 2.6 * t) * 0.7 + 0.2)
                let f1 = 165.0 + 25.0 * sin(2.0 * .pi * 0.9 * t)
                let f2 = 620.0 + 90.0 * cos(2.0 * .pi * 1.7 * t)
                let voice = (sin(2.0 * .pi * f1 * t) * 0.55 + sin(2.0 * .pi * f2 * t) * 0.30 + nextRand() * 0.08)
                let window = (t > 0.3 && t < durationSeconds - 0.3) ? 1.0 : 0.0
                sig += window * syll * voice * 0.58
            case .gasp:
                // Silence then sudden sharp inspiratory gasp at 45% of clip
                let trigger = durationSeconds * 0.45
                let dt = t - trigger
                if dt >= 0 && dt < 0.75 {
                    let env = sin((dt / 0.75) * .pi)
                    let hiss = nextRand() * 0.55 + sin(2.0 * .pi * 540.0 * t) * 0.35
                    sig += env * hiss * 0.80
                }
            case .movement, .ambient:
                let env = sin(min(1.0, t / max(1.0, durationSeconds)) * .pi)
                sig += env * nextRand() * 0.32
            }

            let clamped = max(-0.98, min(0.98, sig))
            samples[i] = Int16(clamped * 32767.0)
        }

        writeWAV(samples: samples, sampleRate: sampleRate, to: url)
        return url
    }

    /// Generates a loopable ambient wind-down soundscape WAV file.
    static func ensureWindDownWAV(for sound: WindDownSound) -> URL? {
        guard sound != .off else { return nil }
        let safeName = sound.rawValue.replacingOccurrences(of: " ", with: "_").lowercased()
        let url = soundsDirectory.appendingPathComponent("winddown_\(safeName).wav")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let sampleRate = 22050
        let duration = 8.0
        let totalSamples = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: totalSamples)
        var brown: Double = 0.0
        var rng: UInt64 = 0xC0FFEE1234567890

        func nextWhite() -> Double {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return (Double((rng >> 33) & 0x7FFFFFFF) / Double(0x7FFFFFFF)) * 2.0 - 1.0
        }

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            // Seamless loop crossfade envelope near edges
            let edgeFade: Double
            if t < 0.25 {
                edgeFade = t / 0.25
            } else if t > duration - 0.25 {
                edgeFade = (duration - t) / 0.25
            } else {
                edgeFade = 1.0
            }

            let white = nextWhite()
            brown = (brown + 0.025 * white) / 1.025
            var sig: Double = 0.0

            switch sound {
            case .off:
                sig = 0.0
            case .cryptRain:
                let dropMod = 0.65 + 0.25 * sin(2.0 * .pi * 0.25 * t)
                sig = (brown * 1.8 + white * 0.14) * dropMod * 0.45
            case .velvetBrown:
                sig = brown * 2.6 * 0.45
            case .cathedralDrone:
                let d1 = sin(2.0 * .pi * 64.0 * t) * 0.38
                let d2 = sin(2.0 * .pi * 96.0 * t) * 0.26
                let d3 = sin(2.0 * .pi * 128.0 * t + sin(2.0 * .pi * 0.125 * t)) * 0.18
                sig = (d1 + d2 + d3 + brown * 0.35) * 0.48
            case .midnightWind:
                let sweep = 0.55 + 0.45 * sin(2.0 * .pi * 0.125 * t)
                sig = (brown * 2.2 + sin(2.0 * .pi * 110.0 * t) * 0.08) * sweep * 0.46
            case .deltaPulse:
                let c1 = sin(2.0 * .pi * 216.0 * t) * 0.32
                let c2 = sin(2.0 * .pi * 218.5 * t) * 0.32
                sig = (c1 + c2 + brown * 0.25) * 0.42
            }

            let clamped = max(-0.95, min(0.95, sig * edgeFade))
            samples[i] = Int16(clamped * 32767.0)
        }

        writeWAV(samples: samples, sampleRate: sampleRate, to: url)
        return url
    }

    /// Generates a harmonic gothic chime WAV for the Smart Phase Alarm.
    static func ensureSmartAlarmChimeWAV() -> URL {
        let url = soundsDirectory.appendingPathComponent("torpor_smart_alarm_chime.wav")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let sampleRate = 22050
        let duration = 4.0
        let totalSamples = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: totalSamples)

        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let env1 = exp(-t * 1.15)
            let t2 = max(0.0, t - 1.8)
            let env2 = t >= 1.8 ? exp(-t2 * 1.25) : 0.0

            let chime1 = (sin(2.0 * .pi * 432.0 * t) * 0.45 + sin(2.0 * .pi * 648.0 * t) * 0.28 + sin(2.0 * .pi * 864.0 * t) * 0.14) * env1
            let chime2 = (sin(2.0 * .pi * 512.0 * t2) * 0.45 + sin(2.0 * .pi * 768.0 * t2) * 0.28) * env2
            let sig = max(-0.95, min(0.95, (chime1 + chime2) * 0.65))
            samples[i] = Int16(sig * 32767.0)
        }

        writeWAV(samples: samples, sampleRate: sampleRate, to: url)
        return url
    }

    private static func writeWAV(samples: [Int16], sampleRate: Int, to url: URL) {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = UInt16(numChannels * (bitsPerSample / 8))
        let dataSize = UInt32(samples.count * 2)
        let chunkSize = 36 + dataSize

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        var cs = chunkSize.littleEndian
        data.append(Data(bytes: &cs, count: 4))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        var subchunk1Size: UInt32 = UInt32(16).littleEndian
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = UInt16(1).littleEndian
        data.append(Data(bytes: &audioFormat, count: 2))
        var nc = numChannels.littleEndian
        data.append(Data(bytes: &nc, count: 2))
        var sr = UInt32(sampleRate).littleEndian
        data.append(Data(bytes: &sr, count: 4))
        var br = byteRate.littleEndian
        data.append(Data(bytes: &br, count: 4))
        var ba = blockAlign.littleEndian
        data.append(Data(bytes: &ba, count: 2))
        var bps = bitsPerSample.littleEndian
        data.append(Data(bytes: &bps, count: 2))
        data.append("data".data(using: .ascii)!)
        var ds = dataSize.littleEndian
        data.append(Data(bytes: &ds, count: 4))

        samples.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                data.append(UnsafeBufferPointer(start: base, count: samples.count))
            }
        }

        try? data.write(to: url, options: .atomic)
    }
}
