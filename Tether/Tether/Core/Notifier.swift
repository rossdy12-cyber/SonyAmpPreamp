import Foundation
import UIKit
import UserNotifications

/// Local alerts, the notification permission, and the APNs registration.
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    @Published var status: UNAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
    }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let value = settings.authorizationStatus
            Task { @MainActor in
                Notifier.shared.status = value
            }
        }
    }

    /// Asks for permission to show alerts, then registers for push.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                Notifier.shared.refreshStatus()
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    /// Re-registers for push when permission was already given (the token can change).
    func registerForPushIfAllowed() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            Task { @MainActor in
                Notifier.shared.status = settings.authorizationStatus
                if allowed {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    /// Shows a local notification for an event.
    func notify(_ event: TetherEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.headline
        content.body = event.text
        content.sound = UNNotificationSound.default
        content.userInfo = ["kind": event.kind, "event": event.id]
        if event.kind == "sos" {
            content.interruptionLevel = .timeSensitive
        }
        let request = UNNotificationRequest(identifier: "tether-event-\(event.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let kind = response.notification.request.content.userInfo["kind"] as? String
        Task { @MainActor in
            Session.shared.selectedTab = (kind == "sos") ? 0 : 3
        }
        completionHandler()
    }
}
