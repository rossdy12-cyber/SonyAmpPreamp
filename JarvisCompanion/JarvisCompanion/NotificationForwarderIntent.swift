import AppIntents
import Foundation

/// Exposes a native iOS Shortcuts & Automations block ("Forward Notification to J.A.R.V.I.S.")
/// so any iOS Automation (Incoming Message, WhatsApp, Email, Focus Change, CarPlay, Battery)
/// immediately forwards the notification payload to J.A.R.V.I.S. over Wi-Fi or Tailscale.
@available(iOS 16.0, *)
struct ForwardNotificationToJarvisIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Notification to J.A.R.V.I.S."
    static var description = IntentDescription("Forwards an iPhone notification, message, or alert directly to your J.A.R.V.I.S. Gaming OS HUD.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "App Name (e.g. Messages, WhatsApp, Mail)", default: "Messages")
    var appName: String

    @Parameter(title: "Sender or Notification Title")
    var senderTitle: String

    @Parameter(title: "Message Body / Notification Content")
    var messageBody: String

    @Parameter(title: "Announce via J.A.R.V.I.S. Voice on PC", default: true)
    var speakAloud: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await JarvisSyncManager.shared.pushNotificationToJarvis(
            app: appName,
            title: senderTitle,
            body: messageBody,
            category: "message",
            speakOnPc: speakAloud
        )
        if ok {
            return .result(dialog: "Synced notification from \(senderTitle) to J.A.R.V.I.S.")
        } else {
            return .result(dialog: "Could not reach J.A.R.V.I.S. server.")
        }
    }
}

@available(iOS 16.0, *)
struct JarvisShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ForwardNotificationToJarvisIntent(),
            phrases: [
                "Send notification to \(.applicationName)",
                "Forward message to \(.applicationName)"
            ],
            shortTitle: "Sync to J.A.R.V.I.S.",
            systemImageName: "bolt.horizontal.circle.fill"
        )
    }
}
