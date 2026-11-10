import SwiftUI
import WatchKit
import UIKit
import AVFoundation
import HealthKit
import Foundation

@main
struct OmniWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WristOSRootView()
        }
    }
}

struct WatchCameraEvent: Identifiable {
    let id: String
    let camera: String
    let label: String
    let score: Int
}

@MainActor
final class WristOSStore: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
    @Published var truenasHost: String = "100.85.127.42"
    @Published var workPCHost: String = "100.102.4.54"
    @Published var bazziteHost: String = "100.79.246.119"
    @Published var laurenHost: String = "100.116.230.25"

    // Tab & Watch Face selector (0..4)
    @Published var selectedTab: Int = 0
    @Published var selectedFaceIndex: Double = 0.0
    @Published var statusLine: String = "SYSTEMS ONLINE"
    @Published var jarvisReply: String = "All TrueNAS, SentryCam, Work PC, and Bazzite systems standing by, sir."
    @Published var voiceInputText: String = ""
    @Published var isBusy: Bool = false

    // Telemetry & Biometrics
    @Published var heartRateBPM: Int = 72
    @Published var stepCount: Int = 4280
    @Published var batteryPercent: Int = 88
    @Published var serverLoadPercent: Int = 24
    @Published var activeContainers: Int = 26
    @Published var nextPaydayDays: Int = 11
    @Published var workPCOnline: Bool = true
    @Published var bazziteOnline: Bool = false
    @Published var ghostModeActive: Bool = false

    // Live T1D GlucoPulse & Tandem t:slim X2 Telemetry
    @Published var bgMmol: String = "--"
    @Published var bgMgdL: Int = 0
    @Published var bgTrendArrow: String = "→"
    @Published var bgForecast30m: String = "--"
    @Published var pumpIOB: Double = 0.0
    @Published var pumpBasal: Double = 0.0
    @Published var pumpBattery: Int = 0
    @Published var pumpReservoir: Int = 0

    // SentryCam Live & PTZ
    @Published var selectedCamera: String = "tapo_c200"
    @Published var cameraFrames: [String: UIImage] = [:]
    @Published var recentEvents: [WatchCameraEvent] = []
    @Published var crownPanValue: Double = 0.15
    @Published var crownVolumeValue: Double = 50.0
    @Published var lastCrownVolStep: Int = 50
    @Published var windowsPin: String = UserDefaults.standard.string(forKey: "watch_win_pin") ?? ""

    private var audioPlayer: AVAudioPlayer?
    private var audioRecorder: AVAudioRecorder?
    private var recordStopTask: Task<Void, Never>?
    private let healthStore = HKHealthStore()
    private var extendedSession: WKExtendedRuntimeSession?
    @Published var isRecordingVoice: Bool = false
    @Published var lastSpokenTranscript: String = ""
    @Published var weatherSummary: String = "14°C CLEAR"
    @Published var stayAwakePinned: Bool = true
    @Published var sessionRunning: Bool = false

    let faceNames = [
        "STARK",
        "007 Q",
        "PIP-BOY",
        "CCTV",
        "LCARS"
    ]

    override init() {
        super.init()
        updateBattery()
        requestHealthKit()
        startAlwaysOnWatchFaceSession()
        Task {
            await fetchFreeWeather()
            await fetchNightscoutT1D()
        }
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchNightscoutT1D()
                self?.ensureAlwaysOnWatchFaceSession()
            }
        }
    }

    func fetchNightscoutT1D() async {
        if let u = URL(string: "http://\(truenasHost):1337/api/v1/entries/sgv.json?count=4"),
           let (data, _) = try? await URLSession.shared.data(from: u),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = arr.first,
           let sgv = first["sgv"] as? Int, sgv > 0 {
            let oldMgdL = bgMgdL
            bgMgdL = sgv
            bgMmol = String(format: "%.1f", Double(sgv) / 18.0182)
            let dir = (first["direction"] as? String ?? "Flat").lowercased()
            switch dir {
            case "doubleup": bgTrendArrow = "↑↑"
            case "singleup": bgTrendArrow = "↑"
            case "fortyfiveup": bgTrendArrow = "↗"
            case "fortyfivedown": bgTrendArrow = "↘"
            case "singledown": bgTrendArrow = "↓"
            case "doubledown": bgTrendArrow = "↓↓"
            default: bgTrendArrow = "→"
            }
            if arr.count >= 3, let oldestSgv = arr.last?["sgv"] as? Int {
                let slopePer15m = Double(sgv - oldestSgv)
                let pred = min(400, max(40, Int((Double(sgv) + slopePer15m * 2.0).rounded())))
                bgForecast30m = String(format: "%.1f", Double(pred) / 18.0182)
            } else {
                bgForecast30m = bgMmol
            }
            if sgv <= 70 && oldMgdL > 70 {
                playHaptic(.failure)
            } else if sgv >= 198 && oldMgdL < 198 {
                playHaptic(.notification)
            }
        }

        if let u2 = URL(string: "http://\(truenasHost):1337/api/v1/devicestatus.json?count=1"),
           let (d2, _) = try? await URLSession.shared.data(from: u2),
           let arr2 = try? JSONSerialization.jsonObject(with: d2) as? [[String: Any]],
           let dev = arr2.first,
           let pump = dev["pump"] as? [String: Any] {
            if let iobDict = pump["iob"] as? [String: Any], let iobVal = iobDict["bolusiob"] as? Double ?? iobDict["iob"] as? Double {
                pumpIOB = iobVal
            }
            if let ext = pump["extended"] as? [String: Any], let basal = ext["TempBasalAbsoluteRate"] as? Double {
                pumpBasal = basal
            }
            if let res = pump["reservoir"] as? Double {
                pumpReservoir = Int(res)
            }
            if let bat = pump["battery"] as? [String: Any], let pct = bat["percent"] as? Int {
                pumpBattery = pct
            }
        }
    }

    func logHypoCarbs15g() async {
        playHaptic(.success)
        statusLine = "Logged +15g Hypo Carbs"
        guard let url = URL(string: "http://\(truenasHost):1337/api/v1/treatments.json") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "eventType": "Carb Correction",
            "carbs": 15,
            "enteredBy": "J.A.R.V.I.S. Watch OS",
            "notes": "+15g Hypo Rescue from Apple Watch"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    func startAlwaysOnWatchFaceSession() {
        stayAwakePinned = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.ensureAlwaysOnWatchFaceSession()
        }
    }

    func ensureAlwaysOnWatchFaceSession() {
        guard stayAwakePinned else {
            extendedSession?.invalidate()
            extendedSession = nil
            sessionRunning = false
            return
        }
        if let s = extendedSession {
            if s.state == .running {
                sessionRunning = true
                return
            }
            if s.state == .scheduled || s.state == .notStarted {
                return
            }
            extendedSession = nil
        }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        extendedSession = s
    }

    func toggleStayAwakePinned() {
        stayAwakePinned.toggle()
        playHaptic(stayAwakePinned ? .success : .directionDown)
        statusLine = stayAwakePinned ? "WATCH FACE LOCK ON" : "WATCH FACE LOCK OFF"
        ensureAlwaysOnWatchFaceSession()
    }

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.sessionRunning = true
            self.statusLine = "📌 WATCH FACE LOCKED"
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.sessionRunning = false
            if self.stayAwakePinned {
                self.extendedSession = nil
                self.ensureAlwaysOnWatchFaceSession()
            }
        }
    }

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        Task { @MainActor in
            self.sessionRunning = false
            self.extendedSession = nil
            if self.stayAwakePinned {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.ensureAlwaysOnWatchFaceSession()
            }
        }
    }

    func fetchFreeWeather() async {
        guard let u = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=51.5074&longitude=-0.1278&current_weather=true") else { return }
        if let (data, _) = try? await URLSession.shared.data(from: u),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cw = obj["current_weather"] as? [String: Any],
           let temp = cw["temperature"] as? Double {
            let code = (cw["weathercode"] as? Int) ?? 0
            let cond = code == 0 ? "CLEAR" : (code <= 3 ? "CLOUDY" : "RAIN")
            weatherSummary = "\(Int(temp.rounded()))°C \(cond)"
        }
    }

    func playHaptic(_ type: WKHapticType = .click) {
        WKInterfaceDevice.current().play(type)
    }

    func updateBattery() {
        let dev = WKInterfaceDevice.current()
        dev.isBatteryMonitoringEnabled = true
        let lvl = dev.batteryLevel
        if lvl >= 0 {
            batteryPercent = Int(lvl * 100)
        }
    }

    func requestHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }
        healthStore.requestAuthorization(toShare: [], read: [hrType, stepType]) { [weak self] ok, _ in
            if ok {
                Task { @MainActor in
                    self?.fetchLatestHeartRate()
                }
            }
        }
    }

    func fetchLatestHeartRate() {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let q = HKSampleQuery(sampleType: hrType, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            if let s = samples?.first as? HKQuantitySample {
                let bpm = Int(s.quantity.doubleValue(for: HKUnit(from: "count/min")))
                Task { @MainActor in
                    self?.heartRateBPM = bpm
                }
            }
        }
        healthStore.execute(q)
    }

    // MARK: - Work PC & Bazzite Unlockers
    func unlockWorkPC() async {
        playHaptic(.notification)
        statusLine = "Unlocking Work PC..."
        let pinParam = windowsPin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let u1 = URL(string: "http://\(workPCHost):9090/u")
        let u2 = URL(string: "http://\(workPCHost):9095/wake")

        var ok = false
        if let u1 = u1 {
            var req = URLRequest(url: u1)
            req.timeoutInterval = 5
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                ok = true
            }
        }
        if let u2 = u2 {
            var req = URLRequest(url: u2)
            req.timeoutInterval = 3
            _ = try? await URLSession.shared.data(for: req)
        }
        playHaptic(ok ? .success : .retry)
        statusLine = ok ? "🔓 Work PC Unlocked!" : "🔓 Wake+Unlock Sent to Work PC"
    }

    func lockWorkPC(blankOnly: Bool = false) async {
        playHaptic(.directionDown)
        let mode = blankOnly ? "blank" : "winlock"
        guard let u = URL(string: "http://\(workPCHost):9090/api/power/lock?mode=\(mode)") else { return }
        var req = URLRequest(url: u)
        req.timeoutInterval = 4
        _ = try? await URLSession.shared.data(for: req)
        statusLine = blankOnly ? "Monitors Blanked" : "🔒 Work PC Locked"
    }

    func unlockBazzitePC() async {
        playHaptic(.notification)
        statusLine = "Waking & Unlocking Bazzite..."
        let unlockCmd = "loginctl unlock-sessions; for s in $(loginctl list-sessions --no-legend | awk '{print $1}'); do loginctl unlock-session $s; done; DISPLAY=:0 xset dpms force on 2>/dev/null; qdbus org.freedesktop.ScreenSaver /ScreenSaver SetActive false 2>/dev/null; dbus-send --session --dest=org.freedesktop.ScreenSaver --type=method_call /ScreenSaver org.freedesktop.ScreenSaver.SetActive boolean:false 2>/dev/null; kscreen-doctor --dpms on 2>/dev/null; echo 'Unlocked'"

        var directOK = false
        if let bzURL = URL(string: "http://\(bazziteHost):9091/api/antigravity/exec") {
            var req = URLRequest(url: bzURL)
            req.httpMethod = "POST"
            req.timeoutInterval = 4
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": unlockCmd, "timeout": 6])
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                directOK = true
            }
        }

        // Also trigger WOL + Unlock relay via Work PC Bridge & TrueNAS
        if let wURL = URL(string: "http://\(workPCHost):9090/b") {
            var req = URLRequest(url: wURL)
            req.timeoutInterval = 4
            _ = try? await URLSession.shared.data(for: req)
        }
        if let tnURL = URL(string: "http://\(truenasHost):9092/api/antigravity/exec") {
            var req = URLRequest(url: tnURL)
            req.httpMethod = "POST"
            req.timeoutInterval = 4
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let relayCmd = "curl -s -m 3 -X POST http://\(bazziteHost):9091/api/antigravity/exec -H 'Content-Type: application/json' -d '{\"command\":\"loginctl unlock-sessions; DISPLAY=:0 xset dpms force on 2>/dev/null\"}' >/dev/null 2>&1 &"
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": relayCmd])
            _ = try? await URLSession.shared.data(for: req)
        }

        playHaptic(.success)
        statusLine = directOK ? "🔓 Bazzite Unlocked!" : "⚡ Bazzite WOL + Unlock Sent!"
    }

    func lockBazzitePC() async {
        playHaptic(.directionDown)
        if let wURL = URL(string: "http://\(workPCHost):9090/api/power/bazzite/lock") {
            _ = try? await URLSession.shared.data(from: wURL)
        }
        statusLine = "🔒 Bazzite Locked"
    }

    func unlockLaurenPC() async {
        playHaptic(.success)
        if let u = URL(string: "http://\(workPCHost):9090/api/power/lauren/unlock") {
            _ = try? await URLSession.shared.data(from: u)
        }
        statusLine = "🔓 Lauren PC Unlocked"
    }

    func toggleAniimoGhost() async {
        playHaptic(.click)
        guard let u = URL(string: "http://\(workPCHost):9095/ghost/toggle") else { return }
        if let (data, _) = try? await URLSession.shared.data(from: u),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let g = json["ghost"] as? Bool {
            ghostModeActive = g
            statusLine = g ? "👻 Aniimo Ghost ON" : "🎮 Aniimo Foreground"
        } else {
            statusLine = "Ghost toggle sent"
        }
    }

    func adjustPCVolume(newVal: Double) async {
        let cur = Int(newVal)
        let diff = cur - lastCrownVolStep
        guard abs(diff) >= 2 else { return }
        lastCrownVolStep = cur
        playHaptic(.click)
        let delta = diff > 0 ? 2 : -2
        guard let u = URL(string: "http://\(workPCHost):9090/api/volume?delta=\(delta)") else { return }
        _ = try? await URLSession.shared.data(from: u)
        statusLine = "PC Volume \(delta > 0 ? "▲" : "▼") (\(cur)%)"
    }

    // MARK: - J.A.R.V.I.S. Direct Wrist Microphone (AVAudioRecorder) & Voice Dictation
    func toggleVoiceRecording() {
        if isRecordingVoice {
            Task { await stopAndSendVoiceRecording() }
        } else {
            startVoiceRecording()
        }
    }

    func startVoiceRecording() {
        playHaptic(.start)
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self = self else { return }
                guard granted else {
                    self.statusLine = "Mic Permission Needed"
                    self.startSystemDictation()
                    return
                }
                do {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers])
                    try session.setActive(true)
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis_wrist_cmd.wav")
                    try? FileManager.default.removeItem(at: url)
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatLinearPCM),
                        AVSampleRateKey: 16000.0,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsFloatKey: false
                    ]
                    let rec = try AVAudioRecorder(url: url, settings: settings)
                    rec.prepareToRecord()
                    rec.record()
                    self.audioRecorder = rec
                    self.isRecordingVoice = true
                    self.statusLine = "🎙️ LISTENING... TAP TO SEND"
                    self.recordStopTask?.cancel()
                    self.recordStopTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 6_500_000_000)
                        if !Task.isCancelled && self.isRecordingVoice {
                            await self.stopAndSendVoiceRecording()
                        }
                    }
                } catch {
                    self.isRecordingVoice = false
                    self.startSystemDictation()
                }
            }
        }
    }

    func stopAndSendVoiceRecording() async {
        recordStopTask?.cancel()
        recordStopTask = nil
        guard let rec = audioRecorder else {
            isRecordingVoice = false
            return
        }
        let url = rec.url
        rec.stop()
        audioRecorder = nil
        isRecordingVoice = false
        playHaptic(.stop)

        guard let wavData = try? Data(contentsOf: url), wavData.count > 1000 else {
            statusLine = "Audio too short"
            return
        }

        isBusy = true
        statusLine = "Transcribing voice..."
        defer { isBusy = false }

        let telemetry = "[Watch Telemetry: Glucose \(bgMmol) mmol/L (\(bgTrendArrow), 30m Forecast \(bgForecast30m) mmol/L), Tandem IOB \(String(format: "%.2f", pumpIOB)) U, HR \(heartRateBPM) BPM, Battery \(batteryPercent)%]"
        guard let endpoint = URL(string: "http://\(truenasHost):8998/api/voice/audio") else { return }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "audio_base64": wavData.base64EncodedString(),
            "telemetry": telemetry,
            "session_id": "watch-voice"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let tr = json["transcript"] as? String, !tr.isEmpty {
                lastSpokenTranscript = tr
            }
            let reply = (json["reply"] as? String) ?? "Command executed, sir."
            jarvisReply = reply
            statusLine = "J.A.R.V.I.S. Spoke"
            playHaptic(.success)
            if let b64 = json["audio_base64"] as? String,
               let outWav = Data(base64Encoded: b64) {
                playWatchAudio(outWav)
            }
        } else {
            statusLine = "Voice Hub Timeout"
            playHaptic(.failure)
        }
    }

    func startSystemDictation() {
        playHaptic(.click)
        guard let ctrl = WKExtension.shared().visibleInterfaceController else { return }
        ctrl.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { [weak self] results in
            if let text = results?.first as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { @MainActor in
                    self?.lastSpokenTranscript = text
                    await self?.askJarvis(text)
                }
            }
        }
    }
    func askJarvis(_ prompt: String) async {
        let q = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        playHaptic(.start)
        isBusy = true
        statusLine = "Consulting J.A.R.V.I.S..."
        defer { isBusy = false }

        let enriched = "\(q) [Watch Telemetry: Glucose \(bgMmol) mmol/L (\(bgTrendArrow), 30m Forecast \(bgForecast30m) mmol/L), Tandem IOB \(String(format: "%.2f", pumpIOB)) U, HR \(heartRateBPM) BPM, Battery \(batteryPercent)%]"
        guard let u = URL(string: "http://\(truenasHost):8998/api/voice/ask") else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 18
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": enriched])

        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let reply = (json["reply"] as? String) ?? "Command executed, sir."
            jarvisReply = reply
            statusLine = "J.A.R.V.I.S. Responded"
            playHaptic(.success)
            if let b64 = json["audio_base64"] as? String,
               let wavData = Data(base64Encoded: b64) {
                playWatchAudio(wavData)
            }
            return
        }

        // Fallback to Work PC Bridge
        if let u2 = URL(string: "http://\(workPCHost):9090/api/chat") {
            var req2 = URLRequest(url: u2)
            req2.httpMethod = "POST"
            req2.timeoutInterval = 10
            req2.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req2.httpBody = try? JSONSerialization.data(withJSONObject: ["message": q])
            if let (d2, _) = try? await URLSession.shared.data(for: req2),
               let j2 = try? JSONSerialization.jsonObject(with: d2) as? [String: Any],
               let r2 = j2["reply"] as? String {
                jarvisReply = r2
                statusLine = "J.A.R.V.I.S. Bridge Reply"
                playHaptic(.success)
                return
            }
        }
        statusLine = "Command Dispatched"
    }

    private func playWatchAudio(_ data: Data) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            // Audio fallback silent
        }
    }

    // MARK: - SentryCam Live Snapshot & Crown PTZ
    func refreshCameraSnapshot(_ cam: String? = nil) async {
        let targetCam = cam ?? selectedCamera
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = URL(string: "http://\(truenasHost):5000/api/\(targetCam)/latest.jpg?h=360&t=\(ts)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, http.statusCode == 200,
           let img = UIImage(data: data) {
            cameraFrames[targetCam] = img
        }
    }

    func loadRecentEvents() async {
        guard let url = URL(string: "http://\(truenasHost):5000/api/events?limit=8") else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var out: [WatchCameraEvent] = []
            for item in arr {
                if let id = item["id"] as? String {
                    let c = (item["camera"] as? String) ?? "cam"
                    let l = (item["label"] as? String) ?? "motion"
                    let sc = Int(((item["top_score"] as? Double) ?? 0.85) * 100)
                    out.append(WatchCameraEvent(id: id, camera: c, label: l, score: sc))
                }
            }
            recentEvents = out
        }
    }

    func toggleTapoPatrol(start: Bool) async {
        playHaptic(.click)
        let cmd = start ? "docker start tapo-patrol" : "docker stop tapo-patrol"
        guard let u = URL(string: "http://\(truenasHost):9092/api/antigravity/exec") else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": cmd])
        _ = try? await URLSession.shared.data(for: req)
        statusLine = start ? "Tapo Patrol Active" : "Tapo Patrol Paused"
    }
}

struct WristOSRootView: View {
    @StateObject private var store = WristOSStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TabView(selection: $store.selectedTab) {
            WatchFacesGalleryView(store: store)
                .ignoresSafeArea(.all)
                .tag(0)
            WatchGlucoPulseView(store: store)
                .tag(1)
            WatchUnlockDeckView(store: store)
                .tag(2)
            WatchJarvisVoiceView(store: store)
                .tag(3)
            WatchSentryCamView(store: store)
                .tag(4)
            WatchOpsTelemetryView(store: store)
                .tag(5)
        }
        .ignoresSafeArea(store.selectedTab == 0 ? .all : [])
        .background(Color.black.ignoresSafeArea(.all))
        .toolbar(store.selectedTab == 0 ? .hidden : .automatic, for: .navigationBar)
        .onAppear {
            store.startAlwaysOnWatchFaceSession()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.startAlwaysOnWatchFaceSession()
            }
        }
        .onChange(of: isLuminanceReduced) { _, reduced in
            if reduced && store.stayAwakePinned && store.selectedTab != 0 {
                store.selectedTab = 0
            }
        }
    }
}

// MARK: - 1. 5 Full-Screen Edge-to-Edge Interactive Watch Faces (Series 10 Full Bezel Layout)
struct WatchFacesGalleryView: View {
    @ObservedObject var store: WristOSStore
    @Environment(\.isLuminanceReduced) var isLuminanceReduced

    var activeIndex: Int {
        min(max(Int(store.selectedFaceIndex.rounded()), 0), store.faceNames.count - 1)
    }

    var bgBadgeColor: Color {
        if store.bgMgdL > 0 && store.bgMgdL <= 70 { return .red }
        if store.bgMgdL >= 198 { return .orange }
        return .green
    }

    var body: some View {
        let screen = WKInterfaceDevice.current().screenBounds
        let fullW = screen.width
        let fullH = screen.height
        let dialSize = min(fullW * 0.72, fullH - 86.0)

        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 15.0 : 1.0)) { context in
            VStack(spacing: 0) {
                // Top Edge Bezel Telemetry Bar (Positioned x=12..146pt so watchOS top-right clock at x=153..192pt never overlaps)
                HStack(spacing: 4) {
                    HStack(spacing: 2.5) {
                        Image(systemName: store.stayAwakePinned ? "lock.fill" : "lock.open")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(store.sessionRunning ? .green : (store.stayAwakePinned ? .cyan : .gray))
                        Text(store.faceNames[activeIndex])
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(.cyan)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.cyan.opacity(0.16))
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.4), lineWidth: 0.8))
                    .clipShape(Capsule())
                    .onTapGesture {
                        store.playHaptic(.click)
                        store.selectedFaceIndex = Double((activeIndex + 1) % store.faceNames.count)
                    }
                    .onLongPressGesture {
                        store.toggleStayAwakePinned()
                    }

                    HStack(spacing: 4) {
                        Text("🩸\(store.bgMmol)\(store.bgTrendArrow)")
                            .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                            .foregroundColor(bgBadgeColor)
                            .lineLimit(1)
                        Text("♥\(store.heartRateBPM)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.09))
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.6))
                    .clipShape(Capsule())

                    Spacer(minLength: 58)
                }
                .padding(.leading, 12)
                .padding(.top, 17)

                Spacer(minLength: 2)

                // Full-Width Center Watch Face Area
                Group {
                    switch activeIndex {
                    case 0:
                        StarkArcWatchFace(date: context.date, store: store, dim: isLuminanceReduced, dialSize: dialSize)
                    case 1:
                        GoldenEyeWatchFace(date: context.date, store: store, dim: isLuminanceReduced, dialSize: dialSize)
                    case 2:
                        PipBoyWatchFace(date: context.date, store: store, dim: isLuminanceReduced)
                    case 3:
                        NightOpsCCTVWatchFace(date: context.date, store: store, dim: isLuminanceReduced, dialSize: dialSize)
                    default:
                        LCARSChronoWatchFace(date: context.date, store: store, dim: isLuminanceReduced)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: dialSize + 8)

                Spacer(minLength: 2)

                // Bottom Edge Quick-Unlock & Voice Mic Dock
                if !isLuminanceReduced {
                    HStack(spacing: 5) {
                        Button {
                            Task { await store.unlockWorkPC() }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.open.desktopcomputer")
                                    .font(.system(size: 9.5, weight: .bold))
                                Text("Work PC")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.22))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.cyan.opacity(0.5), lineWidth: 0.8))
                            .foregroundColor(.cyan)
                            .cornerRadius(9)
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.toggleVoiceRecording()
                        } label: {
                            Image(systemName: store.isRecordingVoice ? "stop.circle.fill" : "mic.fill")
                                .font(.system(size: 12, weight: .heavy))
                                .frame(width: 30, height: 26)
                                .background(store.isRecordingVoice ? Color.red : Color.cyan.opacity(0.3))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(store.isRecordingVoice ? Color.red : Color.cyan, lineWidth: 1))
                                .foregroundColor(.white)
                                .cornerRadius(9)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await store.unlockBazzitePC() }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 9.5, weight: .bold))
                                Text("Bazzite")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.28))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.purple.opacity(0.55), lineWidth: 0.8))
                            .foregroundColor(Color(red: 0.85, green: 0.65, blue: 1.0))
                            .cornerRadius(9)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                } else {
                    Text("ALWAYS-ON STARK HUD • IOB \(String(format: "%.1fU", store.pumpIOB))")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.5))
                        .padding(.bottom, 16)
                }
            }
            .frame(width: fullW, height: fullH)
            .background(Color.black)
        }
        .ignoresSafeArea(.all)
        .toolbar(.hidden, for: .navigationBar)
        .focusable(true)
        .digitalCrownRotation(
            $store.selectedFaceIndex,
            from: 0.0,
            through: Double(store.faceNames.count - 1),
            by: 1.0,
            sensitivity: .low,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
    }
}

struct StarkArcWatchFace: View {
    let date: Date
    @ObservedObject var store: WristOSStore
    let dim: Bool
    let dialSize: CGFloat

    var secAngle: Double {
        Double(Calendar.current.component(.second, from: date)) * 6.0
    }

    var timeFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    var body: some View {
        let outerD = dialSize
        let midD = dialSize * 0.83
        let coreD = dialSize * 0.69

        ZStack {
            Circle()
                .stroke(
                    store.isRecordingVoice ? Color.red.opacity(0.85) : Color.cyan.opacity(dim ? 0.25 : 0.5),
                    style: StrokeStyle(lineWidth: 4.5, dash: [9, 6])
                )
                .frame(width: outerD, height: outerD)
                .rotationEffect(.degrees(secAngle))

            Circle()
                .stroke(
                    store.isRecordingVoice ? Color.orange.opacity(0.75) : Color.blue.opacity(dim ? 0.25 : 0.6),
                    style: StrokeStyle(lineWidth: 2.5, dash: [5, 7])
                )
                .frame(width: midD, height: midD)
                .rotationEffect(.degrees(-secAngle * 1.5))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [(store.isRecordingVoice ? Color.red : Color.cyan).opacity(dim ? 0.16 : 0.42), .clear],
                        center: .center,
                        startRadius: 3,
                        endRadius: coreD * 0.55
                    )
                )
                .frame(width: coreD, height: coreD)

            VStack(spacing: 1) {
                Text(timeFormatted)
                    .font(.system(size: dialSize * 0.24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .lineLimit(1)

                Text(store.isRecordingVoice ? "🎙️ SPEAK NOW..." : "IOB \(String(format: "%.1fU", store.pumpIOB)) • ⚡\(store.batteryPercent)%")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(store.isRecordingVoice ? .red : .white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: midD - 12)
            .onTapGesture {
                store.toggleVoiceRecording()
            }
        }
        .frame(width: outerD, height: outerD)
    }
}

struct GoldenEyeWatchFace: View {
    let date: Date
    @ObservedObject var store: WristOSStore
    let dim: Bool
    let dialSize: CGFloat

    var body: some View {
        HStack {
            VStack(spacing: 2.5) {
                ForEach(0..<8, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill((8 - i) * 12 <= store.batteryPercent ? Color.orange : Color.white.opacity(0.1))
                        .frame(width: 9, height: max(8, (dialSize - 24) / 8))
                }
            }
            Spacer()
            VStack(spacing: 3) {
                Text("007 // Q-BRANCH")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                Text(date, style: .time)
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text("BAT \(store.batteryPercent)% • IOB \(String(format: "%.1fU", store.pumpIOB))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .lineLimit(1)
                Text(store.statusLine)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer()
            VStack(spacing: 2.5) {
                ForEach(0..<8, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i > 0 ? Color.cyan : Color.white.opacity(0.1))
                        .frame(width: 9, height: max(8, (dialSize - 24) / 8))
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

struct PipBoyWatchFace: View {
    let date: Date
    @ObservedObject var store: WristOSStore
    let dim: Bool
    let pipGreen = Color(red: 0.1, green: 1.0, blue: 0.45)

    var body: some View {
        VStack(spacing: 3) {
            Text("PIP-BOY 3000 MK IV")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(pipGreen)
            Divider().background(pipGreen)
            Text(date, style: .time)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundColor(pipGreen)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text("HP \(store.batteryPercent)/100")
                Text("IOB \(String(format: "%.1fU", store.pumpIOB))")
            }
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundColor(pipGreen)
            Text(store.statusLine)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(pipGreen.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(pipGreen.opacity(0.6), lineWidth: 1.5))
        .padding(.horizontal, 10)
    }
}

struct NightOpsCCTVWatchFace: View {
    let date: Date
    @ObservedObject var store: WristOSStore
    let dim: Bool
    let dialSize: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Text(date, style: .time)
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundColor(.red)
            if let img = store.cameraFrames["tapo_c200"] {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(height: max(68, dialSize - 28))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.6), lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.12))
                    .frame(height: max(68, dialSize - 28))
                    .overlay(Text("TAPO C200 LIVE").font(.system(size: 9.5, weight: .bold, design: .monospaced)).foregroundColor(.red))
            }
        }
        .padding(.horizontal, 10)
        .task {
            while !Task.isCancelled {
                await store.refreshCameraSnapshot("tapo_c200")
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }
}

struct LCARSChronoWatchFace: View {
    let date: Date
    @ObservedObject var store: WristOSStore
    let dim: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.orange)
                    .frame(width: 28, height: 13)
                Text("LCARS // STARDATE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(.orange)
            }
            Text(date, style: .time)
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundColor(.yellow)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text("DOCKER: \(store.activeContainers)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                Text("PAYDAY: \(store.nextPaydayDays)D")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.purple)
            }
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - 2. Wrist PC Unlock & DeskSwitch Deck
struct WatchUnlockDeckView: View {
    @ObservedObject var store: WristOSStore

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("WRIST PC UNLOCKER")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(.cyan)

                Text(store.statusLine)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .lineLimit(1)

                // Work PC Unlock & Lock
                VStack(spacing: 5) {
                    Text("Work PC (ROSS-DYMOND-PC)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        Button {
                            Task { await store.unlockWorkPC() }
                        } label: {
                            Label("Unlock", systemImage: "lock.open.fill")
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.cyan)

                        Button {
                            Task { await store.lockWorkPC(blankOnly: false) }
                        } label: {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .tint(.red)
                    }
                }
                .padding(6)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)

                // Bazzite Linux PC Unlock & Lock
                VStack(spacing: 5) {
                    Text("Bazzite Gaming PC")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        Button {
                            Task { await store.unlockBazzitePC() }
                        } label: {
                            Label("Unlock + WOL", systemImage: "lock.open.fill")
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.purple)

                        Button {
                            Task { await store.lockBazzitePC() }
                        } label: {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .tint(.orange)
                    }
                }
                .padding(6)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)

                // Aniimo Ghost Mode & Lauren PC
                HStack(spacing: 6) {
                    Button {
                        Task { await store.toggleAniimoGhost() }
                    } label: {
                        Label("Ghost", systemImage: "eye.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .tint(.green)

                    Button {
                        Task { await store.unlockLaurenPC() }
                    } label: {
                        Label("Lauren", systemImage: "tv.fill")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .tint(.pink)
                }

                // Optional Windows PIN input for hard lock screen
                TextField("Work PC PIN (Optional)", text: $store.windowsPin)
                    .font(.system(size: 10))
                    .onChange(of: store.windowsPin) { _, newVal in
                        UserDefaults.standard.set(newVal, forKey: "watch_win_pin")
                    }

                Text("Crown: Work PC Volume (\(Int(store.crownVolumeValue))%)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 4)
        }
        .focusable(true)
        .digitalCrownRotation(
            $store.crownVolumeValue,
            from: 0.0,
            through: 100.0,
            by: 2.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: store.crownVolumeValue) { _, newVal in
            Task { await store.adjustPCVolume(newVal: newVal) }
        }
    }
}

// MARK: - 3. J.A.R.V.I.S. Wrist Voice & AI (Direct Wrist Mic + Watch Dictation + Spoken Replies)
struct WatchJarvisVoiceView: View {
    @ObservedObject var store: WristOSStore

    let presets = [
        ("Status Report", "Status report please Jarvis"),
        ("Check Glucose", "How is my blood sugar and insulin on board looking?"),
        ("Check Cameras", "Check the security cameras"),
        ("Unlock Work PC", "Unlock my work PC")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                HStack {
                    Circle()
                        .fill(store.isRecordingVoice ? Color.red : (store.isBusy ? Color.orange : Color.cyan))
                        .frame(width: 8, height: 8)
                    Text(store.isRecordingVoice ? "LISTENING ON MIC..." : (store.isBusy ? "PROCESSING..." : "J.A.R.V.I.S. VOICE CORE"))
                        .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(store.isRecordingVoice ? .red : .cyan)
                }

                // Primary Push-to-Talk Wrist Microphone + Watch Dictation Buttons
                HStack(spacing: 6) {
                    Button {
                        store.toggleVoiceRecording()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: store.isRecordingVoice ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text(store.isRecordingVoice ? "TAP TO SEND" : "TAP TO SPEAK")
                                .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(store.isRecordingVoice ? Color.red.opacity(0.85) : Color.cyan.opacity(0.28))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(store.isRecordingVoice ? Color.red : Color.cyan, lineWidth: 1.2))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.startSystemDictation()
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: "waveform.badge.mic")
                                .font(.system(size: 13, weight: .bold))
                            Text("Dictate")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .frame(width: 46)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.28))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.6), lineWidth: 1))
                        .foregroundColor(.cyan)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }

                if !store.lastSpokenTranscript.isEmpty {
                    Text("🗣️ \"\(store.lastSpokenTranscript)\"")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.cyan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                Text(store.jarvisReply)
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cyan.opacity(0.14))
                    .cornerRadius(8)

                ForEach(presets, id: \.0) { p in
                    Button {
                        Task { await store.askJarvis(p.1) }
                    } label: {
                        Text(p.0)
                            .font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.blue)
                }

                TextField("Or type/scribble...", text: $store.voiceInputText)
                    .font(.system(size: 10))
                    .submitLabel(.send)
                    .onSubmit {
                        let q = store.voiceInputText
                        store.voiceInputText = ""
                        Task { await store.askJarvis(q) }
                    }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - 4. SentryCam Wrist CCTV + Digital Crown PTZ
struct WatchSentryCamView: View {
    @ObservedObject var store: WristOSStore

    let cams = [
        ("tapo_c200", "Tapo C200"),
        ("bike_camera", "Bike Cam"),
        ("doorbell", "Doorbell")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(cams, id: \.0) { c in
                        Button {
                            store.selectedCamera = c.0
                            Task { await store.refreshCameraSnapshot(c.0) }
                        } label: {
                            Text(c.1)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity)
                                .background(store.selectedCamera == c.0 ? Color.red : Color.white.opacity(0.12))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let img = store.cameraFrames[store.selectedCamera] {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 96)
                        .overlay(ProgressView().tint(.red))
                }

                HStack(spacing: 6) {
                    Button("Patrol ON") {
                        Task { await store.toggleTapoPatrol(start: true) }
                    }
                    .font(.system(size: 9, weight: .bold))
                    .tint(.green)

                    Button("Pause") {
                        Task { await store.toggleTapoPatrol(start: false) }
                    }
                    .font(.system(size: 9, weight: .bold))
                    .tint(.orange)
                }

                if !store.recentEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("RECENT AI DETECTIONS")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                        ForEach(store.recentEvents.prefix(4)) { ev in
                            Text("• \(ev.label.capitalized) (\(ev.camera)) \(ev.score)%")
                                .font(.system(size: 9))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .task(id: store.selectedCamera) {
            await store.loadRecentEvents()
            while !Task.isCancelled {
                await store.refreshCameraSnapshot()
                try? await Task.sleep(nanoseconds: 1_800_000_000)
            }
        }
    }
}

// MARK: - 5. TrueNAS, Docker & Biometrics Telemetry
struct WatchOpsTelemetryView: View {
    @ObservedObject var store: WristOSStore

    let containers = ["frigate", "tapo-patrol", "icloudpd", "ix-jellyfin-jellyfin-1"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("OPS & BIOMETRICS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.green)

                Button {
                    store.toggleStayAwakePinned()
                } label: {
                    HStack {
                        Image(systemName: store.stayAwakePinned ? "pin.fill" : "pin.slash")
                        Text(store.stayAwakePinned ? "Default Watch Screen: ON" : "Default Watch Screen: OFF")
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .tint(store.stayAwakePinned ? .cyan : .gray)

                HStack {
                    Text("♥ \(store.heartRateBPM) BPM")
                        .foregroundColor(.red)
                    Spacer()
                    Text("⚡ \(store.batteryPercent)%")
                        .foregroundColor(.green)
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))

                Text("DOCKER QUICK RESTART")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)

                ForEach(containers, id: \.self) { c in
                    Button {
                        store.playHaptic(.click)
                        Task {
                            guard let u = URL(string: "http://\(store.truenasHost):9092/api/antigravity/exec") else { return }
                            var req = URLRequest(url: u)
                            req.httpMethod = "POST"
                            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                            req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": "docker restart \(c)"])
                            _ = try? await URLSession.shared.data(for: req)
                            store.statusLine = "Restarted \(c)"
                        }
                    } label: {
                        HStack {
                            Text(c)
                                .font(.system(size: 10, weight: .semibold))
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                        }
                    }
                    .tint(.teal)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - 6. Live T1D GlucoPulse & Tandem Wrist HUD
struct WatchGlucoPulseView: View {
    @ObservedObject var store: WristOSStore

    var bgColor: Color {
        if store.bgMgdL > 0 && store.bgMgdL <= 70 { return .red }
        if store.bgMgdL >= 198 { return .orange }
        return .green
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(bgColor)
                    Text("GLUCOPULSE T1D")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(bgColor)
                    Spacer()
                    Button {
                        Task { await store.fetchNightscoutT1D() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 2) {
                    Text("\(store.bgMmol) \(store.bgTrendArrow)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(bgColor)
                    Text("mmol/L • 30m: \(store.bgForecast30m) mmol/L")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)

                HStack(spacing: 6) {
                    VStack(spacing: 1) {
                        Text("IOB")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                        Text(String(format: "%.2f U", store.pumpIOB))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(5)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)

                    VStack(spacing: 1) {
                        Text("BASAL")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                        Text(String(format: "%.2f U/h", store.pumpBasal))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(5)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                }

                Button {
                    Task { await store.logHypoCarbs15g() }
                } label: {
                    Label("+15g Hypo Carbs", systemImage: "bolt.heart.fill")
                        .font(.system(size: 10, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .tint(.orange)

                Button {
                    Task { await store.askJarvis("Give me a quick clinical check on my current blood glucose and active insulin on board.") }
                } label: {
                    Label("Ask J.A.R.V.I.S. T1D", systemImage: "waveform.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .tint(.cyan)
            }
            .padding(.horizontal, 4)
        }
    }
}
