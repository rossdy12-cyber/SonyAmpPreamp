import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers
import UIKit

// ============================================================
//  KNELL — gothic ringtone forge
//  Procedurally composes tones, renders true .m4r AAC files,
//  exports via the share sheet. Nothing leaves the device.
// ============================================================

let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
let bloodDim = Color(red: 0.48, green: 0.05, blue: 0.13)
let ashText = Color(red: 0.96, green: 0.89, blue: 0.91)
let ashDim = Color(red: 0.69, green: 0.53, blue: 0.56)
let cryptBg = Color(red: 0.02, green: 0.004, blue: 0.012)

struct KnellTone: Identifiable {
    let id: UUID
    let name: String
    let fileURL: URL
    let seconds: Double
    let created: Date
}

// MARK: - Synthesis engine

enum KnellForge {

    static let sampleRate: Double = 44100

    // D minor pentatonic + gothic intervals
    static let dMinorPentatonic: [Double] = [146.83, 174.61, 196.00, 220.00, 261.63, 293.66, 349.23, 392.00, 440.00]

    struct Params {
        var baseFreq: Double = 220.0        // A3
        var tempoBPM: Double = 96
        var duration: Double = 30.0         // seconds (ringtone max 40)
        var waveMix: Double = 0.0           // 0 = pure bell-ish sine, 1 = harsh saw
        var darkness: Double = 0.5          // minor spacing / detune
        var seed: UInt64 = 7
    }

    static func presetParams(_ preset: Int) -> Params {
        switch preset {
        case 0: return Params(baseFreq: 220, tempoBPM: 96, duration: 30, waveMix: 0.05, darkness: 0.5, seed: 11)   // Gothic Bell
        case 1: return Params(baseFreq: 110, tempoBPM: 72, duration: 30, waveMix: 0.55, darkness: 0.8, seed: 23)   // Deep Crypt Pulse
        case 2: return Params(baseFreq: 293.66, tempoBPM: 60, duration: 30, waveMix: 0.02, darkness: 0.3, seed: 41) // Requiem Air
        case 3: return Params(baseFreq: 880, tempoBPM: 140, duration: 8, waveMix: 0.15, darkness: 0.6, seed: 5)    // Duke Click
        case 4: return Params(baseFreq: 164.81, tempoBPM: 88, duration: 30, waveMix: 0.3, darkness: 0.65, seed: 77) // Bells of the Dead
        default: return Params()
        }
    }

    // mulberry32 PRNG
    static func rng(_ seed: UInt64) -> () -> Double {
        var state = seed &* 2654435761 &+ 1
        return {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) & 0xFFFFFFFF) / Double(0xFFFFFFFF)
        }
    }

    /// Gothic melodic motifs as semitone offsets from the base note.
    /// A memorable phrase beats a random walk — the ear hooks onto repetition.
    static let motifs: [[Double]] = [
        // Dies Irae — the gothic phrase of phrases
        [0, 2, 3, 0, 2, -1, 0],
        // Toccata-style: chromatic descent with octave stabs
        [0, -1, -2, 0, 7, -1, -2, -4],
        // Lament bass, slow descending thirds
        [0, -3, -5, -7, -5, -3],
        // Triadic summons (minor arpeggio up + fall)
        [0, 3, 7, 12, 7, 3, 0, -5],
        // Tolling: sparse fifths and octaves
        [0, 7, 0, 12, 0]
    ]

    /// Procedurally composes a note sequence from a gothic motif: repeated
    /// phrase, octave lifts on repeats, accents on phrase heads, breath rests.
    static func composeSequence(_ p: Params) -> [(freq: Double, start: Double, dur: Double, gain: Double)] {
        let random = rng(p.seed)
        var notes: [(Double, Double, Double, Double)] = []
        let beat = 60.0 / p.tempoBPM
        let motif = motifs[presetIndexFor(p) % motifs.count]
        var t = 0.0
        var phraseRound = 0
        while t < p.duration - beat * 0.5 {
            // breath between phrase rounds (varies: 1-2 beats)
            if phraseRound > 0 {
                t += beat * (random() < 0.5 ? 1 : 2)
            }
            let octaveLift = phraseRound % 2 == 1 ? 12.0 : 0.0   // eerie second-round lift
            var intra = 0.0
            let roundStart = t
            for (i, semi) in motif.enumerated() {
                let f = p.baseFreq * pow(2.0, (semi + octaveLift) / 12.0)
                // rhythm: mostly eighth-notes, some dotted or held
                var dur = beat * 0.75
                let r = random()
                if r < 0.18 { dur = beat * 1.4 }          // held, ominous
                else if r < 0.35 { intra += beat * 0.25 } // rest, syncopation
                // velocity: phrase-head accent, cadence swell, human variation
                var gain = 0.85
                if i == 0 { gain = 1.0 }
                else if i == motif.count - 1 { gain = 0.95 }
                else { gain = 0.62 + random() * 0.2 }
                let start = t + intra
                if start < p.duration - 0.05 {
                    notes.append((f, start, min(dur * 2.2, p.duration - start), gain))
                }
                intra += dur
            }
            t = roundStart + intra
            phraseRound += 1
            if t > p.duration - beat * 1.5 { break }
        }
        // final toll: two low bells to land the ring
        let tail = min(1.8, p.duration * 0.25)
        if p.duration > 6 {
            notes.append((p.baseFreq * 0.5, max(0, p.duration - tail), tail, 1.0))
            notes.append((p.baseFreq * 0.75, max(0, p.duration - tail * 0.55), tail * 0.55, 0.8))
        }
        return notes
    }

    private static func presetIndexFor(_ p: Params) -> Int {
        Int(p.seed % 5)
    }

    /// Renders the composition into a mono PCM buffer with ADSR envelopes + overtone shimmer.
    static func renderBuffer(_ p: Params) -> [Float] {
        let totalSamples = Int(p.duration * sampleRate)
        var buffer = [Float](repeating: 0, count: totalSamples)
        let notes = composeSequence(p)
        let random = rng(p.seed &+ 999)

        // --- struck-bell partial model: each partial has its own decay rate ---
        // Real bell partial ratios (inharmonic, like a church bell)
        let partials: [(ratio: Double, amp: Double, tau: Double)] = [
            (1.0,   1.00, 1.00),   // fundamental hum, rings longest
            (2.0,   0.55, 0.55),   // prime
            (2.756, 0.42, 0.40),   // tierce (minor third — the gothic soul of the bell)
            (5.404, 0.22, 0.22),   // quint / nominal, decays fast
            (0.56,  0.35, 0.80),   // sub-hum, deep dark body
            (1.19,  0.30, 0.45)    // sombre
        ]

        // --- doom chord stab at t=0: minor triad, instantly recognizable ---
        let chordDur = min(0.55, p.duration * 0.2)
        for ratio in [1.0, 1.19, 1.5] {
            let cf = p.baseFreq * ratio
            let idx0 = 0
            let n = Int(chordDur * sampleRate)
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let env = exp(-t / 0.28) * min(1.0, t / 0.003)
                let s = sin(2.0 * .pi * cf * t) * 0.5 + sin(2.0 * .pi * cf * 2.756 * t) * 0.15
                buffer[idx0 + i] += Float(s * env * 0.35)
            }
        }

        for (freq, start, dur, gain) in notes {
            let startIdx = Int(start * sampleRate)
            let noteSamples = Int(dur * sampleRate)
            guard startIdx < totalSamples else { continue }
            // detuned dual oscillator for gothic width
            let detune = 1.0 + (random() - 0.5) * 0.01 * p.darkness
            // strike transient: filtered noise burst at note attack
            let strikeSamples = min(160, noteSamples)
            var strikeSeed = UInt64(truncatingIfNeeded: freq.bitPattern) &+ p.seed
            for i in 0..<strikeSamples {
                strikeSeed = strikeSeed &* 6364136223846793005 &+ 1442695040888963407
                let noise = Double((strikeSeed >> 33) & 0xFFFFFFFF) / Double(0xFFFFFFFF) * 2.0 - 1.0
                let env = exp(-Double(i) / sampleRate / 0.004)
                buffer[startIdx + i] += Float(noise * env * 0.30 * gain)
            }

            let tremPhase = 2.0 * .pi * 5.5 * start   // phase-locked tremolo per note
            for i in 0..<noteSamples where startIdx + i < totalSamples {
                let t = Double(i) / sampleRate
                var sample = 0.0
                // struck-bell partial stack: exponential decay per partial,
                // higher partials die faster (that "real bell" shimmer)
                for pt in partials {
                    let pf = freq * pt.ratio * detune
                    if pf > sampleRate / 2 { continue }
                    let tau = max(0.08, dur * pt.tau)
                    let env = exp(-t / tau) * min(1.0, t / 0.002)
                    sample += sin(2.0 * .pi * pf * t) * pt.amp * env
                }
                // waveform blend: add darkened saw body on harsher presets
                if p.waveMix > 0.05 {
                    let sawRaw = 2.0 * (freq * t - floor(freq * t + 0.5))
                    let body = exp(-t / max(0.1, dur * 0.35))
                    sample += sawRaw * p.waveMix * 0.35 * body
                    sample += sin(2.0 * .pi * freq * detune * t) * p.waveMix * 0.25 * body
                }
                // vibrato/tremolo shimmer for drama
                let trem = 1.0 + 0.10 * sin(tremPhase + 2.0 * .pi * 5.5 * t)
                sample *= trem

                buffer[startIdx + i] += Float(sample * gain * 0.55)
            }
        }

        // --- sub-bass crypt pulse every 2 beats (weight + urgency) ---
        let pulsePeriod = 60.0 / p.tempoBPM * 2
        var pt0 = 0.0
        while pt0 < p.duration - 0.2 {
            let idx0 = Int(pt0 * sampleRate)
            let n = min(Int(0.45 * sampleRate), totalSamples - idx0)
            for i in 0..<max(0, n) {
                let t = Double(i) / sampleRate
                let env = exp(-t / 0.12) * min(1.0, t / 0.004)
                buffer[idx0 + i] += Float(sin(2.0 * .pi * (p.baseFreq / 2) * t) * env * 0.5)
            }
            pt0 += pulsePeriod
        }

        // --- cathedral space: dual feedback delay (dotted-eighth + half-note) ---
        let beatSamples = Int(sampleRate * 60.0 / p.tempoBPM)
        let d1 = max(1, Int(Double(beatSamples) * 0.75))   // dotted eighth
        let d2 = max(1, beatSamples * 2)                    // half note
        var line1 = [Float](repeating: 0, count: d1)
        var line2 = [Float](repeating: 0, count: min(d2, totalSamples))
        var i1 = 0, i2 = 0
        for i in 0..<totalSamples {
            let e1 = line1[i1] * 0.42
            let e2 = line2[i2] * 0.30
            let wet = buffer[i] + e1 + e2
            line1[i1] = wet * 0.38
            line2[i2] = wet * 0.30
            buffer[i] = wet
            i1 = (i1 + 1) % d1
            i2 = (i2 + 1) % line2.count
        }

        // --- normalize to loud, ringtone-punchy level, then soft-knee limit ---
        var peak: Float = 0.0001
        for v in buffer { peak = max(peak, abs(v)) }
        let norm = 0.92 / peak
        let fadeSamples = Int(min(1.0, p.duration) * sampleRate)
        for i in 0..<totalSamples {
            var v = buffer[i] * norm
            // soft knee limiter: keeps punch, kills digital clipping
            if abs(v) > 0.75 { v = v > 0 ? 0.75 + (abs(v) - 0.75) * 0.2 : -(0.75 + (abs(v) - 0.75) * 0.2) }
            if i > totalSamples - fadeSamples {
                v *= Float(totalSamples - i) / Float(fadeSamples)
            }
            buffer[i] = v
        }
        return buffer
    }

    /// Writes PCM to a temporary WAV, then transcodes to true .m4r AAC via AVAssetExportSession.
    static func renderToM4R(name: String, params: Params, toDirectory: URL) async throws -> URL {
        let samples = renderBuffer(params)
        try FileManager.default.createDirectory(at: toDirectory, withIntermediateDirectories: true)
        let m4rURL = toDirectory.appendingPathComponent(name.replacingOccurrences(of: " ", with: "_") + ".m4a")
        try? FileManager.default.removeItem(at: m4rURL)

        // Write directly to AAC using AVAudioFile - no WAV intermediate, no export session
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        var settings = format.settings
        settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
        settings[AVSampleRateKey] = sampleRate
        settings[AVNumberOfChannelsKey] = 1
        settings[AVEncoderBitRateKey] = 128000

        let audioFile = try AVAudioFile(
            forWriting: m4rURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        // Write in chunks (AVAudioFile can handle large buffers but chunking is safer)
        let chunkSize = 44100 * 5  // 5 seconds
        var offset = 0
        while offset < samples.count {
            let count = min(chunkSize, samples.count - offset)
            var chunk = [Float](repeating: 0, count: count)
            for i in 0..<count {
                chunk[i] = samples[offset + i]
            }
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) {
                buffer.frameLength = AVAudioFrameCount(count)
                if let channelData = buffer.floatChannelData {
                    let channel = channelData.pointee
                    for i in 0..<count {
                        channel[i] = chunk[i]
                    }
                }
                try audioFile.write(from: buffer)
            }
            offset += count
        }

        guard FileManager.default.fileExists(atPath: m4rURL.path) else {
            throw NSError(domain: "Knell", code: 3, userInfo: [NSLocalizedDescriptionKey: "AAC write completed but file missing"])
        }
        return m4rURL
    }

    /// Converts any audio or video file into a trimmed ringtone-ready .m4a.
    /// Primary path: AVAssetExportSession (Apple M4A preset) with a timeRange.
    /// Fallback path: AVAssetReader PCM extraction + direct AVAudioFile AAC write.
    static func convertToM4A(source: URL, start: Double, length: Double, name: String, toDirectory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: toDirectory, withIntermediateDirectories: true)
        let out = toDirectory.appendingPathComponent(name.replacingOccurrences(of: " ", with: "_") + ".m4a")
        try? FileManager.default.removeItem(at: out)

        let asset = AVURLAsset(url: source)
        let assetDuration = try await asset.load(.duration).seconds
        guard assetDuration.isFinite, assetDuration > 0 else {
            throw NSError(domain: "Knell", code: 10, userInfo: [NSLocalizedDescriptionKey: "No readable audio in that file"])
        }
        let trimStart = max(0, min(start, max(0, assetDuration - 1)))
        let trimLen = max(1, min(length, 40, assetDuration - trimStart))

        // --- primary: export session ---
        if let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
            session.outputURL = out
            session.outputFileType = .m4a
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: trimStart, preferredTimescale: 600),
                duration: CMTime(seconds: trimLen, preferredTimescale: 600))
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { cont.resume() }
            }
            if session.status == .completed && FileManager.default.fileExists(atPath: out.path) {
                return out
            }
        }

        // --- fallback: PCM read + AAC write (handles exotic codecs/multichannel) ---
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "Knell", code: 11, userInfo: [NSLocalizedDescriptionKey: "That file has no audio track"])
        }
        let readSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: readSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            duration: CMTime(seconds: trimLen, preferredTimescale: 600))
        reader.startReading()

        var pcm: [Float] = []
        while let sb = output.copyNextSampleBuffer() {
            guard let dataBuffer = CMSampleBufferGetDataBuffer(sb) else { continue }
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>? = nil
            CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
            guard let p = dataPointer, totalLength > 0 else { continue }
            let floatCount = totalLength / MemoryLayout<Float>.size
            p.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
                for f in 0..<floatCount { pcm.append(floats[f]) }
            }
        }
        reader.cancelReading()
        guard !pcm.isEmpty else {
            throw NSError(domain: "Knell", code: 13, userInfo: [NSLocalizedDescriptionKey: "Audio extraction came back empty"])
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000
        ]
        let audioFile = try AVAudioFile(forWriting: out, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk = 44100 * 5
        var offset = 0
        while offset < pcm.count {
            let count = min(chunk, pcm.count - offset)
            if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) {
                buf.frameLength = AVAudioFrameCount(count)
                if let ch = buf.floatChannelData {
                    for i in 0..<count { ch.pointee[i] = pcm[offset + i] }
                }
                try audioFile.write(from: buf)
            }
            offset += count
        }
        guard FileManager.default.fileExists(atPath: out.path) else {
            throw NSError(domain: "Knell", code: 14, userInfo: [NSLocalizedDescriptionKey: "Conversion wrote no file"])
        }
        return out
    }
}

struct PButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(enabled ? bloodDim : Color(red: 0.2, green: 0.03, blue: 0.07))
                .foregroundColor(enabled ? .white : ashDim)
                .cornerRadius(7)
        }
        .disabled(!enabled)
    }
}

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

// MARK: - Root

@main
struct KnellApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Forge state

@MainActor
final class ForgeState: ObservableObject {
    @Published var preset: Int = 0
    @Published var baseFreq: Double = 220
    @Published var tempo: Double = 96
    @Published var duration: Double = 30
    @Published var waveMix: Double = 0.05
    @Published var darkness: Double = 0.5
    @Published var seed: UInt64 = 11

    @Published var tones: [KnellTone] = []
    @Published var statusMessage = ""
    @Published var rendering = false
    @Published var sharingURL: URL? = nil

    private var player: AVAudioPlayer?
    private var docsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    init() {
        loadTones()
    }

    var params: KnellForge.Params {
        var p = KnellForge.Params()
        p.baseFreq = baseFreq
        p.tempoBPM = tempo
        p.duration = duration
        p.waveMix = waveMix
        p.darkness = darkness
        p.seed = seed
        return p
    }

    func conjure() {
        seed = UInt64.random(in: 1...UInt64.max)
        baseFreq = [110, 146.83, 164.81, 220, 293.66, 440].randomElement()!
        tempo = Double(Int.random(in: 60...150))
        waveMix = Double.random(in: 0.0...0.7)
        darkness = Double.random(in: 0.2...0.9)
    }

    func loadTones() {
        let files = (try? FileManager.default.contentsOfDirectory(at: docsDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let urls = files.filter { $0.pathExtension == "m4r" || $0.pathExtension == "m4a" }
        let list: [KnellTone] = urls.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard let attrs = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]) else { return nil }
            let seconds = Double(attrs.fileSize ?? 0) / (128 * 1024 / 8.0) // ~128kbps estimate
            return KnellTone(id: UUID(), name: name, fileURL: url, seconds: min(40, max(1, seconds)), created: attrs.creationDate ?? Date())
        }
        tones = list.sorted { $0.created > $1.created }
    }

    func playPreview() {
        let p = params
        Task.detached(priority: .userInitiated) {
            let samples = KnellForge.renderBuffer(p)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("knell_preview.wav")
            ForgeState.writeWavFile(samples, to: tmp)
            await MainActor.run {
                self.player = try? AVAudioPlayer(contentsOf: tmp)
                self.player?.play()
            }
        }
    }

    private nonisolated static func writeWavFile(_ samples: [Float], to url: URL) {
        var wav = Data()
        let dataBytes = samples.withUnsafeBytes { Data($0) }
        let byteRate = Int(KnellForge.sampleRate) * 2
        func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append("RIFF".data(using: .ascii)!); append32(UInt32(36 + dataBytes.count))
        wav.append("WAVE".data(using: .ascii)!); wav.append("fmt ".data(using: .ascii)!)
        append16(16); append16(1); append16(1)
        append32(UInt32(Int(KnellForge.sampleRate))); append32(UInt32(byteRate)); append16(2); append16(16)
        wav.append("data".data(using: .ascii)!); append32(UInt32(dataBytes.count)); wav.append(dataBytes)
        try? wav.write(to: url)
    }

    private func writeWav(_ samples: [Float], to url: URL) {
        var wav = Data()
        let dataBytes = samples.withUnsafeBytes { Data($0) }
        let byteRate = Int(KnellForge.sampleRate) * 2
        func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append("RIFF".data(using: .ascii)!); append32(UInt32(36 + dataBytes.count))
        wav.append("WAVE".data(using: .ascii)!); wav.append("fmt ".data(using: .ascii)!)
        append16(16); append16(1); append16(1)
        append32(UInt32(Int(KnellForge.sampleRate))); append32(UInt32(byteRate)); append16(2); append16(16)
        wav.append("data".data(using: .ascii)!); append32(UInt32(dataBytes.count)); wav.append(dataBytes)
        try? wav.write(to: url)
    }

    func forgeAndShare() async {
        rendering = true
        statusMessage = "Forging the tone…"
        do {
            let stamp = Int(Date().timeIntervalSince1970) % 100000
            let p = params
            let docs = docsDir
            print("[Knell] docs dir: \(docs.path)")
            print("[Knell] docs exists: \(FileManager.default.fileExists(atPath: docs.path))")
            // heavy synthesis must NOT run on the main thread
            let url = try await Task.detached(priority: .userInitiated) {
                let u = try await KnellForge.renderToM4R(name: "Knell_\(stamp)", params: p, toDirectory: docs)
                print("[Knell] rendered to: \(u.path)")
                print("[Knell] file exists: \(FileManager.default.fileExists(atPath: u.path))")
                let size = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size]) ?? "unknown"
                print("[Knell] file size: \(size)")
                return u
            }.value
            loadTones()
            let exists = FileManager.default.fileExists(atPath: url.path)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int ?? 0
            statusMessage = "Rendered: \(url.lastPathComponent) | exists: \(exists) | size: \(size)B | archive: \(tones.count) tones"
            rendering = false
            if exists {
                let stamp2 = "\(url.lastPathComponent)"
                DocumentExportHost.shared.present(url: url) { outcome in
                    DispatchQueue.main.async {
                        self.loadTones()
                        self.statusMessage = outcome + " — rename .m4a to .m4r in Files to set as ringtone."
                        self.rendering = false
                    }
                }
                _ = stamp2
            } else {
                self.rendering = false
            }
        } catch {
            statusMessage = "Forge failed: \(error.localizedDescription)"
            rendering = false
        }
    }

    
    func importFromUrl(_ urlString: String) async {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
            importStatus = "That is not a valid URL."
            return
        }
        importing = true
        importStatus = "Downloading from the web…"
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 300
            req.setValue("Mozilla/5.0 Knell", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                throw NSError(domain: "Knell", code: 1, userInfo: [NSLocalizedDescriptionKey: "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"])
            }
            guard data.count > 10000 else {
                throw NSError(domain: "Knell", code: 2, userInfo: [NSLocalizedDescriptionKey: "File too small to be audio"])
            }
            let stamp = Int(Date().timeIntervalSince1970) % 100000
            var ext = url.pathExtension.lowercased()
            if ext.isEmpty || !["mp3", "m4a", "m4r", "wav", "aac", "m4b", "ogg", "flac"].contains(ext) {
                ext = "mp3"
            }
            let tmp = docsDir.appendingPathComponent("Imported_\(stamp).\(ext)")
            try data.write(to: tmp)
            if ext == "m4a" || ext == "m4r" {
                let final = docsDir.appendingPathComponent("Knell_\(stamp).m4a")
                try FileManager.default.moveItem(at: tmp, to: final)
            } else {
                let asset = AVURLAsset(url: tmp, options: nil)
                let m4aOut = docsDir.appendingPathComponent("Knell_\(stamp).m4a")
                guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                    throw NSError(domain: "Knell", code: 3)
                }
                export.outputURL = m4aOut
                export.outputFileType = .m4a
                try? FileManager.default.removeItem(at: m4aOut)
                await export.export()
                guard export.status == .completed else {
                    throw NSError(domain: "Knell", code: 4, userInfo: [NSLocalizedDescriptionKey: "Transcode failed: \(export.error?.localizedDescription ?? "?")"])
                }
                try? FileManager.default.removeItem(at: tmp)
            }
            loadTones()
            importStatus = "Imported to ARCHIVE."
            importing = false
        } catch {
            importStatus = "Import failed: \(error.localizedDescription)"
            importing = false
        }
    }

    func deleteTone(_ tone: KnellTone) {
        try? FileManager.default.removeItem(at: tone.fileURL)
        loadTones()
    }

    // MARK: Import / conversion state
    @Published var importSource: URL? = nil
    @Published var importDuration: Double = 30
    @Published var importStart: Double = 0
    @Published var importing = false
    @Published var importStatus: String = ""
    @Published var importUrlText: String = ""
    @Published var showPhotoPicker = false

    func beginImportFromFiles() {
        FileImportHost.shared.present { [weak self] url in
            DispatchQueue.main.async {
                guard let self = self, let u = url else { return }
                self.importSource = u
                self.importStart = 0
                Task {
                    let asset = AVURLAsset(url: u)
                    let d = (try? await asset.load(.duration).seconds) ?? 30
                    await MainActor.run {
                        self.importDuration = min(d, 40)
                        self.statusMessage = "Loaded \(u.lastPathComponent) — \(String(format: "%.1f", d))s available. Set the START and LENGTH, then CONVERT."
                    }
                }
            }
        }
    }

    func convertImport() async {
        guard let src = importSource else { return }
        importing = true
        statusMessage = "Converting…"
        do {
            var scopeOK = src.startAccessingSecurityScopedResource()
            let stamp = Int(Date().timeIntervalSince1970) % 100000
            let out = try await KnellForge.convertToM4A(
                source: src, start: importStart, length: importDuration,
                name: "Knell_Import_\(stamp)", toDirectory: docsDir)
            if scopeOK { src.stopAccessingSecurityScopedResource(); scopeOK = false }
            loadTones()
            importing = false
            DocumentExportHost.shared.present(url: out) { outcome in
                DispatchQueue.main.async {
                    self.loadTones()
                    self.statusMessage = outcome + " — rename .m4a to .m4r in Files to set as ringtone."
                }
            }
        } catch {
            if src.startAccessingSecurityScopedResource() { src.stopAccessingSecurityScopedResource() }
            importing = false
            statusMessage = "Conversion failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Root view

struct ContentView: View {
    @StateObject private var forge = ForgeState()

    var body: some View {
        TabView {
            ForgeView(forge: forge)
                .tabItem { Label("FORGE", systemImage: "hammer.fill") }
            ImportView(forge: forge)
                .tabItem { Label("IMPORT", systemImage: "arrow.down.doc.fill") }
            ArchiveView(forge: forge)
                .tabItem { Label("ARCHIVE", systemImage: "music-note.list") }
            CryptView()
                .tabItem { Label("CRYPT", systemImage: "lock.shield") }
        }
        .accentColor(crimson)
    }
}

// MARK: - IMPORT tab (convert audio/video into a ringtone)

final class FileImportHost: NSObject, UIDocumentPickerDelegate {
    static var shared = FileImportHost()
    private var onFinish: ((URL?) -> Void)?
    private var overlayWindow: UIWindow?

    func present(completion: @escaping (URL?) -> Void) {
        onFinish = completion
        DispatchQueue.main.async {
            var types: [UTType] = [.audio, .movie, .video, .mpeg4Audio, .mp3, .wav, .aiff]
            if let m4r = UTType("com.apple.ringtone") { types.append(m4r) }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            picker.delegate = self
            let w = UIWindow(windowScene: UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }!)
            w.windowLevel = .alert + 1
            w.rootViewController = picker
            w.makeKeyAndVisible()
            self.overlayWindow = w
        }
    }

    private func dismissOverlay() {
        DispatchQueue.main.async {
            if let w = self.overlayWindow {
                w.isHidden = true
                w.rootViewController = nil
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                for scene in scenes {
                    if let main = scene.windows.first(where: { $0 !== w && $0.canBecomeKey && !$0.isHidden }) {
                        main.makeKey()
                    }
                }
            }
            self.overlayWindow = nil
        }
    }

    private func finish(_ url: URL?) {
        dismissOverlay()
        onFinish?(url)
        onFinish = nil
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }
}

struct ImportView: View {
    @ObservedObject var forge: ForgeState

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PCard(title: "00 // IMPORT FROM URL") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Paste a direct audio link (mp3, m4a, wav) from any generator or cloud share.")
                                .font(.system(size: 12))
                                .foregroundColor(ashDim)
                            TextField("https://…/audio.mp3", text: $forge.importUrlText)
                                .font(.system(size: 12, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Button {
                                Task { await forge.importFromUrl(forge.importUrlText) }
                            } label: {
                                HStack {
                                    if forge.importing { ProgressView().tint(.white) }
                                    Text(forge.importing ? "DOWNLOADING…" : "DOWNLOAD & CONVERT")
                                }
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(11)
                                .background(crimson)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .disabled(forge.importing || forge.importUrlText.trimmingCharacters(in: .whitespaces).isEmpty)
                            if !forge.importStatus.isEmpty {
                                Text(forge.importStatus)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    PCard(title: "00 // IMPORT FROM URL") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Paste a direct audio link (mp3, m4a, wav) from any generator or cloud share.")
                                .font(.system(size: 12))
                                .foregroundColor(ashDim)
                            TextField("https://…/audio.mp3", text: $forge.importUrlText)
                                .font(.system(size: 12, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Button {
                                Task { await forge.importFromUrl(forge.importUrlText) }
                            } label: {
                                HStack {
                                    if forge.importing { ProgressView().tint(.white) }
                                    Text(forge.importing ? "DOWNLOADING…" : "DOWNLOAD & CONVERT")
                                }
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(11)
                                .background(crimson)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .disabled(forge.importing || forge.importUrlText.trimmingCharacters(in: .whitespaces).isEmpty)
                            if !forge.importStatus.isEmpty {
                                Text(forge.importStatus)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    PCard(title: "00 // IMPORT FROM URL") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Paste a direct audio link (mp3, m4a, wav) from any generator or cloud share.")
                                .font(.system(size: 12))
                                .foregroundColor(ashDim)
                            TextField("https://…/audio.mp3", text: $forge.importUrlText)
                                .font(.system(size: 12, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Button {
                                Task { await forge.importFromUrl(forge.importUrlText) }
                            } label: {
                                HStack {
                                    if forge.importing { ProgressView().tint(.white) }
                                    Text(forge.importing ? "DOWNLOADING…" : "DOWNLOAD & CONVERT")
                                }
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(11)
                                .background(crimson)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .disabled(forge.importing)
                            if !forge.importStatus.isEmpty {
                                Text(forge.importStatus)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    PCard(title: "01 // RAISE THE SOUND") {
                        VStack(spacing: 10) {
                            PButton(title: "PICK AUDIO / VIDEO FROM FILES", enabled: !forge.importing) {
                                forge.beginImportFromFiles()
                            }
                            PButton(title: "PICK VIDEO FROM PHOTOS", enabled: !forge.importing) {
                                forge.showPhotoPicker = true
                            }
                        }
                    }

                    if forge.importSource != nil {
                        PCard(title: "02 // CARVE THE SEGMENT") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("START")
                                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                        .foregroundColor(crimson)
                                    Spacer()
                                    Text(String(format: "%.1fs", forge.importStart))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(ashText)
                                }
                                Slider(value: $forge.importStart, in: 0...max(1, forge.importDuration * 3), step: 0.5)
                                    .tint(crimson)
                                HStack {
                                    Text("LENGTH")
                                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                        .foregroundColor(crimson)
                                    Spacer()
                                    Text(String(format: "%.1fs (max 40)", forge.importDuration))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(ashText)
                                }
                                Slider(value: $forge.importDuration, in: 1...40, step: 0.5)
                                    .tint(crimson)
                            }
                        }
                        PCard(title: "03 // CONVERT TO RINGTONE") {
                            VStack(spacing: 10) {
                                PButton(title: forge.importing ? "CONVERTING…" : "CONVERT TO .M4A", enabled: !forge.importing) {
                                    Task { await forge.convertImport() }
                                }
                                Text("The converted file opens the Files browser — save it, rename .m4a → .m4r, tap to set as your ringtone.")
                                    .font(.system(size: 11))
                                    .foregroundColor(ashDim)
                            }
                        }
                    }

                    PCard(title: "STATUS") {
                        Text(forge.statusMessage.isEmpty ? "Choose a sound — any song, video voiceover or recording becomes a ringtone." : forge.statusMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(forge.statusMessage.contains("failed") ? crimson : ashText)
                    }
                }
                .padding(14)
            }
            .sheet(isPresented: $forge.showPhotoPicker) {
                PhotoVideoPicker { url in
                    DispatchQueue.main.async {
                        if let u = url {
                            forge.importSource = u
                            forge.importStart = 0
                            Task {
                                let asset = AVURLAsset(url: u)
                                let d = (try? await asset.load(.duration).seconds) ?? 30
                                await MainActor.run {
                                    forge.importDuration = min(d, 40)
                                    forge.statusMessage = "Loaded \(u.lastPathComponent) — \(String(format: "%.1f", d))s available. Set START and LENGTH, then CONVERT."
                                }
                            }
                        }
                        forge.showPhotoPicker = false
                    }
                }
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE RELIQUARY")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
    }
}

struct PhotoVideoPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                onPick(nil)
                return
            }
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let u = url else { self.onPick(nil); return }
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("knell_import_\(UUID().uuidString).mov")
                try? FileManager.default.copyItem(at: u, to: tmp)
                self.onPick(tmp)
            }
        }
    }
}

// MARK: - FORGE tab

struct ForgeView: View {
    @ObservedObject var forge: ForgeState

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PCard(title: "01 // CHOOSE YOUR TOLL") {
                        Picker("Preset", selection: $forge.preset) {
                            Text("Gothic Bell").tag(0)
                            Text("Deep Crypt Pulse").tag(1)
                            Text("Requiem Air").tag(2)
                            Text("Duke Click").tag(3)
                            Text("Bells of the Dead").tag(4)
                            Text("Custom").tag(5)
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: forge.preset) { nv in
                            if nv != 5 {
                                let p = KnellForge.presetParams(nv)
                                forge.baseFreq = p.baseFreq
                                forge.tempo = p.tempoBPM
                                forge.duration = p.duration
                                forge.waveMix = p.waveMix
                                forge.darkness = p.darkness
                                forge.seed = p.seed
                            }
                        }

                        Button {
                            forge.conjure()
                            forge.preset = 5
                        } label: {
                            Label("CONJURE NEW", systemImage: "dice.fill")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(bloodDim)
                                .foregroundColor(.white)
                                .cornerRadius(7)
                        }
                    }

                    PCard(title: "02 // SHAPE THE SOUND") {
                        KnellSlider(label: "KEY", value: $forge.baseFreq, range: 80...900, format: "%.0f Hz")
                        KnellSlider(label: "TEMPO", value: $forge.tempo, range: 50...160, format: "%.0f BPM")
                        KnellSlider(label: "LENGTH", value: $forge.duration, range: 5...40, format: "%.0f s")
                        KnellSlider(label: "DARKNESS", value: $forge.darkness, range: 0...1, format: "%.0f%%")
                        KnellSlider(label: "RAZOR", value: $forge.waveMix, range: 0...1, format: "%.0f%%")
                    }

                    HStack(spacing: 10) {
                        Button {
                            forge.playPreview()
                        } label: {
                            Label("PREVIEW", systemImage: "play.fill")
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(bloodDim)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        Button {
                            Task { await forge.forgeAndShare() }
                        } label: {
                            HStack {
                                if forge.rendering { ProgressView().tint(.white) }
                                Text(forge.rendering ? "FORGING…" : "FORGE .M4R")
                            }
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(crimson)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(forge.rendering)
                    }

                    if !forge.statusMessage.isEmpty {
                        Text(forge.statusMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }
                .padding(14)
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE FORGE")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
    }
}

struct KnellSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(ashDim)
                .frame(width: 70, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(crimson)
            Text(String(format: format, value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(ashText)
                .frame(width: 62, alignment: .trailing)
        }
    }
}

// MARK: - ARCHIVE tab

struct ToneRowView: View {
    let tone: KnellTone
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(tone.name)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(ashText)
                Text(String(format: "~%.0fs · %@", tone.seconds, tone.created.formatted(date: .abbreviated, time: .shortened)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(ashDim)
            }
            Spacer()
            Button {
                if let player = try? AVAudioPlayer(contentsOf: tone.fileURL) {
                    objc_setAssociatedObject(self, "player", player, .OBJC_ASSOCIATION_RETAIN)
                    player.play()
                }
            } label: {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(crimson)
            }
            Button {
                onExport()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(crimson)
            }
            .accessibilityLabel("Export to Files")
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(ashDim)
            }
        }
    }
}

struct ArchiveView: View {
    @ObservedObject var forge: ForgeState
    @State private var sharingURL: URL?

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            if forge.tones.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 36))
                        .foregroundColor(bloodDim)
                    Text("No tones forged yet.\nVisit the FORGE.")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(ashDim)
                        .multilineTextAlignment(.center)
                }
            } else {
                List {
                    ForEach(forge.tones) { tone in
                        ToneRowView(tone: tone) {
                            sharingURL = tone.fileURL
                        } onDelete: {
                            forge.deleteTone(tone)
                        }
                        .listRowBackground(Color(red: 0.06, green: 0.01, blue: 0.03))
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE ARCHIVE")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
        .onChange(of: sharingURL) { url in
            if let u = url {
                DocumentExportHost.shared.present(url: u) { outcome in
                    DispatchQueue.main.async {
                        forge.statusMessage = outcome
                    }
                }
                sharingURL = nil
            }
        }
    }
}

final class DocumentExportHost: NSObject, UIDocumentPickerDelegate {
    static var shared = DocumentExportHost()
    private var picker: UIDocumentPickerViewController?
    private var onFinish: ((String) -> Void)?
    private var overlayWindow: UIWindow?

    func present(url: URL, completion: @escaping (String) -> Void) {
        onFinish = completion
        DispatchQueue.main.async {
            Self.presentOnMain(url: url, host: self)
        }
    }

    private static var window: UIWindow?

    private static func presentOnMain(url: URL, host: DocumentExportHost) {
        // UIKit hard-asserts in initForExportingURLs if the file is missing
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[Knell] export picker aborted: file missing at " + url.path)
            host.finish("Export skipped — file missing")
            return
        }

        // Present via a dedicated UIWindow overlay — completely bypasses the
        // SwiftUI presentation stack and its sheet/representable conflicts.
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = host
        host.picker = picker

        let w = UIWindow(windowScene: UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }!)
        w.windowLevel = .alert + 1
        w.rootViewController = picker
        w.makeKeyAndVisible()
        window = w
        host.overlayWindow = w
        print("[Knell] document picker presented via window overlay")
    }

    private func dismissOverlay() {
        DispatchQueue.main.async {
            if let w = self.overlayWindow ?? Self.window {
                w.isHidden = true
                w.rootViewController = nil
                // restore the app's main window as key
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                for scene in scenes {
                    if let main = scene.windows.first(where: { $0 !== w && $0.canBecomeKey && !$0.isHidden }) {
                        main.makeKey()
                    }
                }
            }
            Self.window = nil
            self.overlayWindow = nil
        }
    }

    private func finish(_ message: String) {
        dismissOverlay()
        onFinish?(message)
        onFinish = nil
    }

    // UIDocumentPickerDelegate
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        print("[Knell] saved to: \(urls.first?.path ?? "?")")
        finish("Saved to Files ✓")
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("[Knell] export picker cancelled")
        finish("Export cancelled — tone kept in the ARCHIVE")
    }

    private static func keyTopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let root = scenes.first?.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController, !(presented is UIDocumentPickerViewController) {
            top = presented
        }
        return top
    }
}

struct DocumentExportView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - CRYPT tab

struct CryptView: View {
    private func installSteps() -> [String] {
        [
            "Forge your tone and tap FORGE .M4A — the Files browser appears.",
            "Save the .m4a file to On My iPhone or iCloud Drive.",
            "Open the Files app, find the .m4a file, and rename it: change the extension to .m4r.",
            "Tap the renamed .m4r file — iOS offers to set it as your ringtone.",
            "Settings → Sounds & Haptics → Ringtone → pick your tone."
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                PCard(title: "01 // HOW TO INSTALL A RINGTONE") {
                    let steps = installSteps()
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { pair in
                            Text("\(pair.offset + 1). \(pair.element)")
                                .font(.system(size: 12))
                                .foregroundColor(ashText)
                        }
                    }
                }
                PCard(title: "02 // HOW THE FORGE WORKS") {
                    Text("Every tone is composed live on this device: D-minor scale walks, bell overtones, ADSR envelopes and detuned dual oscillators — then rendered offline to a true 44.1kHz AAC .m4r. Apple caps ringtones at 40 seconds; the forge defaults to 30.")
                        .font(.system(size: 12))
                        .foregroundColor(ashDim)
                }
                PCard(title: "03 // WHAT KNELL NEVER DOES") {
                    Text("No network. No account. No tracking. The tones are yours alone — generated, stored and shared entirely on this device.")
                        .font(.system(size: 12))
                        .foregroundColor(ashText)
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
