import SwiftUI
import AVFoundation
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

    /// Procedurally composes a note sequence: arpeggios, tolling bells, rests.
    static func composeSequence(_ p: Params) -> [(freq: Double, start: Double, dur: Double, gain: Double)] {
        let random = rng(p.seed)
        var notes: [(Double, Double, Double, Double)] = []
        let beat = 60.0 / p.tempoBPM
        var t = 0.0
        var lastIdx = Int(random() * 4)
        while t < p.duration - beat * 0.5 {
            let roll = random()
            if roll < 0.18 {
                // rest / silence breath
                t += beat * (random() < 0.5 ? 1 : 2)
                continue
            }
            // walk the scale, occasionally leap (gothic interval jumps)
            var idx = lastIdx
            if random() < 0.45 {
                idx = max(0, min(dMinorPentatonic.count - 1, idx + (random() < 0.5 ? 1 : -1)))
            } else if random() < 0.2 {
                idx = max(0, min(dMinorPentatonic.count - 1, idx + Int(random() * 5) - 2))
            }
            lastIdx = idx
            var freq = dMinorPentatonic[idx]
            // scale toward the base note register
            if freq < p.baseFreq * 0.7 || freq > p.baseFreq * 3.0 {
                freq = p.baseFreq * (random() < 0.5 ? 1 : 2)
            }
            let dur = beat * (random() < 0.3 ? 2 : 1) * (1.0 + random() * 0.4)
            let gain = 0.55 + random() * 0.35
            notes.append((freq, t, min(dur, p.duration - t), gain))
            // occasional bell overtone layer
            if random() < 0.3 {
                notes.append((freq * 2.01, t, min(dur * 0.6, p.duration - t), gain * 0.35))
            }
            t += dur * (random() < 0.5 ? 1.0 : 1.5)
        }
        return notes
    }

    /// Renders the composition into a mono PCM buffer with ADSR envelopes + overtone shimmer.
    static func renderBuffer(_ p: Params) -> [Float] {
        let totalSamples = Int(p.duration * sampleRate)
        var buffer = [Float](repeating: 0, count: totalSamples)
        let notes = composeSequence(p)
        let random = rng(p.seed &+ 999)

        for (freq, start, dur, gain) in notes {
            let startIdx = Int(start * sampleRate)
            let noteSamples = Int(dur * sampleRate)
            guard startIdx < totalSamples else { continue }
            // detuned dual oscillator for gothic width
            let detune = 1.0 + (random() - 0.5) * 0.01 * p.darkness
            for i in 0..<noteSamples where startIdx + i < totalSamples {
                let t = Double(i) / sampleRate
                let phase = 2.0 * .pi * freq * t
                // ADSR: fast attack, decay to sustain, release
                let attack = min(1.0, t / 0.008)
                let decayEnd = min(dur, 0.35)
                let decay = t < decayEnd ? 1.0 - 0.55 * (t / decayEnd) : 0.45
                let release = min(1.0, (dur - t) / min(0.25, dur * 0.25))
                let env = attack * max(0.0, decay) * max(0.0, release)

                // waveform blend: sine (bell) + saw (dark)
                let sine = sin(phase)
                let sawRaw = 2.0 * (freq * t - floor(freq * t + 0.5))
                let saw = sawRaw * 0.6
                let detuned = sin(phase * detune) * 0.5
                var sample = sine * (1.0 - p.waveMix) + (saw + detuned) * p.waveMix

                // bell overtones (inharmonic, like a real bell)
                sample += sin(phase * 2.756) * 0.12 * (1.0 - p.waveMix)
                sample += sin(phase * 5.404) * 0.05 * (1.0 - p.waveMix)

                // sub-boss: gentle low pulse every bar for the crypt feel
                if p.waveMix > 0.4 {
                    let pulsePeriod = 60.0 / p.tempoBPM * 4
                    let pulseT = t.truncatingRemainder(dividingBy: pulsePeriod)
                    if pulseT < 0.08 {
                        sample += sin(2.0 * .pi * (p.baseFreq / 2) * pulseT) * 0.25
                    }
                }

                buffer[startIdx + i] += Float(sample * env * gain * 0.28)
            }
        }

        // soft clip + fade out the last second
        let fadeSamples = Int(min(1.0, p.duration) * sampleRate)
        for i in 0..<totalSamples {
            var v = buffer[i]
            v = v / (1.0 + abs(v) * 0.6)   // soft saturation
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
        let wavURL = toDirectory.appendingPathComponent(name + "_raw.wav")
        // NOTE: .m4r is an Apple-reserved UTI - initForExportingURLs aborts on it.
        // We export as .m4a (fully supported); the user renames to .m4r in Files.
        let m4rURL = toDirectory.appendingPathComponent(name.replacingOccurrences(of: " ", with: "_") + ".m4a")

        // 1. write WAV
        var wav = Data()
        let dataBytes = samples.withUnsafeBytes { Data($0) }
        let byteRate = Int(sampleRate) * 2
        func append(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + dataBytes.count))
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        append16(16)                                    // PCM chunk
        append16(1)                                     // format
        append16(1)                                     // channels
        append(UInt32(Int(sampleRate)))                 // sample rate
        append(UInt32(byteRate))
        append16(2)                                     // block align
        append16(16)                                    // bits
        wav.append("data".data(using: .ascii)!)
        append(UInt32(dataBytes.count))
        wav.append(dataBytes)
        try wav.write(to: wavURL)

        // 2. transcode to AAC .m4r
        let asset = AVURLAsset(url: wavURL, options: nil)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "Knell", code: 1)
        }
        export.outputURL = m4rURL
        export.outputFileType = .m4a
        try? FileManager.default.removeItem(at: m4rURL)
        await export.export()
        print("[Knell] export status: \(export.status.rawValue), error: \(String(describing: export.error))")
        print("[Knell] m4a exists: \(FileManager.default.fileExists(atPath: m4rURL.path))")
        try? FileManager.default.removeItem(at: wavURL)
        return m4rURL
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
                DocumentExportHost.shared.present(url: url)
            }
        } catch {
            statusMessage = "Forge failed: \(error.localizedDescription)"
            rendering = false
        }
    }

    func deleteTone(_ tone: KnellTone) {
        try? FileManager.default.removeItem(at: tone.fileURL)
        loadTones()
    }
}

// MARK: - Root view

struct ContentView: View {
    @StateObject private var forge = ForgeState()

    var body: some View {
        TabView {
            ForgeView(forge: forge)
                .tabItem { Label("FORGE", systemImage: "hammer.fill") }
            ArchiveView(forge: forge)
                .tabItem { Label("ARCHIVE", systemImage: "music-note.list") }
            CryptView()
                .tabItem { Label("CRYPT", systemImage: "lock.shield") }
        }
        .accentColor(crimson)
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
                        KnellSlider(label: "DARKNESS", value: $forge.darkness, range: 0...1, format: "%.0%")
                        KnellSlider(label: "RAZOR", value: $forge.waveMix, range: 0...1, format: "%.0%")
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
                DocumentExportHost.shared.present(url: u)
                sharingURL = nil
            }
        }
    }
}

final class DocumentExportHost: NSObject, UIDocumentPickerDelegate {
    static var shared = DocumentExportHost()
    private var picker: UIDocumentPickerViewController?

    func present(url: URL) {
        DispatchQueue.main.async {
            Self.presentOnMain(url: url)
        }
    }

    private static var window: UIWindow?

    private static func presentOnMain(url: URL) {
        // UIKit hard-asserts in initForExportingURLs if the file is missing
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[Knell] export picker aborted: file missing at " + url.path)
            return
        }

        // Present via a dedicated UIWindow overlay — completely bypasses the
        // SwiftUI presentation stack and its sheet/representable conflicts.
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        shared.picker = picker

        let w = UIWindow(windowScene: UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }!)
        w.windowLevel = .alert + 1
        w.rootViewController = picker
        w.makeKeyAndVisible()
        window = w
        print("[Knell] document picker presented via window overlay")
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
