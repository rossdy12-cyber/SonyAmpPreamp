import Foundation
import UIKit
import Combine

struct JarvisNotificationItem: Identifiable, Codable {
    var id: String
    var app: String
    var title: String
    var body: String
    var category: String
    var timestamp: String
    var priority: String?
}

@MainActor
final class JarvisSyncManager: ObservableObject {
    static let shared = JarvisSyncManager()

    @Published var serverHost: String {
        didSet { UserDefaults.standard.set(serverHost, forKey: "jarvis_server_host") }
    }
    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Standby — Ready to link with J.A.R.V.I.S. PC"
    @Published var recentNotifications: [JarvisNotificationItem] = []
    @Published var pcClipboardText: String = ""
    @Published var batteryPercent: Int = 100
    @Published var batteryState: String = "Full"

    // DeepAI Code bridge (MK-VII tab 09 agent on the PC)
    @Published var deepAiMessages: [DeepAiMessage] = []
    @Published var deepAiWorking: Bool = false
    @Published var deepAiStatus: String = "READY"
    @Published var deepAiModel: String = ""

    private var heartbeatTimer: Timer?

    private init() {
        self.serverHost = UserDefaults.standard.string(forKey: "jarvis_server_host") ?? "http://192.168.0.185:7777"
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryTelemetry()
        startHeartbeat()
    }

    func updateBatteryTelemetry() {
        let lvl = UIDevice.current.batteryLevel
        if lvl >= 0 {
            batteryPercent = Int(round(lvl * 100))
        }
        switch UIDevice.current.batteryState {
        case .charging: batteryState = "Charging"
        case .full: batteryState = "Full"
        case .unplugged: batteryState = "Unplugged"
        default: batteryState = "Active"
        }
    }

    func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.sendHeartbeatAndFetchFeed()
            }
        }
        Task {
            await sendHeartbeatAndFetchFeed()
        }
    }

    func sendHeartbeatAndFetchFeed() async {
        updateBatteryTelemetry()
        let base = serverHost.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/api/iphone/heartbeat") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "deviceName": UIDevice.current.name,
            "systemVersion": UIDevice.current.systemVersion,
            "batteryPercent": batteryPercent,
            "batteryState": batteryState,
            "mode": "NativeSwiftUI"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                isConnected = true
                statusMessage = "LINKED // \(base)"
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["notifications"] as? [[String: Any]] {
                    let mapped: [JarvisNotificationItem] = items.prefix(30).compactMap { dict in
                        guard let title = dict["title"] as? String else { return nil }
                        return JarvisNotificationItem(
                            id: (dict["id"] as? String) ?? UUID().uuidString,
                            app: (dict["app"] as? String) ?? "iPhone",
                            title: title,
                            body: (dict["body"] as? String) ?? "",
                            category: (dict["category"] as? String) ?? "alert",
                            timestamp: (dict["timestamp"] as? String) ?? "",
                            priority: dict["priority"] as? String
                        )
                    }
                    self.recentNotifications = mapped
                }
            } else {
                isConnected = false
                statusMessage = "HTTP Error from J.A.R.V.I.S."
            }
        } catch {
            // Automatic fallback to Tailscale IP if LAN IP is unreachable (e.g. on 5G/LTE away from home)
            if serverHost.contains("192.168.0.185") {
                serverHost = "http://100.76.215.23:7777"
            }
            isConnected = false
            statusMessage = "Searching for J.A.R.V.I.S. (\(error.localizedDescription))"
        }
    }

    func pushNotificationToJarvis(app: String, title: String, body: String, category: String = "message", speakOnPc: Bool = true) async -> Bool {
        let base = serverHost.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/api/iphone/notify") else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 6.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "app": app,
            "title": title,
            "body": body,
            "category": category,
            "speak": speakOnPc,
            "deviceName": UIDevice.current.name,
            "batteryPercent": batteryPercent
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                await sendHeartbeatAndFetchFeed()
                return true
            }
        } catch {}
        return false
    }

    func pushClipboardToPc() async {
        guard let str = UIPasteboard.general.string, !str.isEmpty else { return }
        _ = await pushNotificationToJarvis(
            app: "iOS Clipboard",
            title: "Clipboard Beamed from iPhone",
            body: str,
            category: "clipboard",
            speakOnPc: false
        )
    }

    func sendPcCommand(_ action: String) async {
        let base = serverHost.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/api/iphone/command") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": action])
        _ = try? await URLSession.shared.data(for: req)
    }

    // ------------------------------------------------------------------ DeepAI Code chat bridge

    func sendDeepAi(_ text: String) async {
        let base = serverHost.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/api/deepai/send") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 8.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["message": text])
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                deepAiWorking = true
                deepAiStatus = "WORKING"
                await pollDeepAiState()
            }
        } catch {
            deepAiStatus = "SEND FAILED"
        }
    }

    func pollDeepAiState() async {
        let base = serverHost.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/api/deepai/state") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 6.0
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            deepAiWorking = (json["isWorking"] as? Bool) ?? false
            deepAiStatus = (json["statusText"] as? String) ?? ""
            deepAiModel = (json["activeModel"] as? String) ?? ""
            if let items = json["messages"] as? [[String: Any]] {
                let mapped: [DeepAiMessage] = items.suffix(20).compactMap { dict in
                    guard let text = dict["text"] as? String else { return nil }
                    return DeepAiMessage(
                        id: ((dict["time"] as? String) ?? "") + "|\(text.prefix(24))",
                        role: (dict["role"] as? String) ?? "DEEPAI",
                        model: (dict["model"] as? String) ?? "",
                        text: text,
                        time: (dict["time"] as? String) ?? ""
                    )
                }
                deepAiMessages = mapped
            }
        } catch {}
    }
}

struct DeepAiMessage: Identifiable {
    let id: String
    let role: String
    let model: String
    let text: String
    let time: String
}
