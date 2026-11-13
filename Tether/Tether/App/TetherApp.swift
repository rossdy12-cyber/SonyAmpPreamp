import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = Notifier.shared
        BackgroundSync.register()
        Theme.configureAppearance()
        Notifier.shared.refreshStatus()
        // A relaunch caused by a location or region event needs the engine running again.
        LocationEngine.shared.start()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Credentials.apnsToken = hex
        Task {
            await Session.shared.registerDevice()
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Happens on builds without the push entitlement; Tether still works by polling.
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            await Session.shared.backgroundSync()
            completionHandler(.newData)
        }
    }
}

@main
struct TetherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = Session.shared
    @StateObject private var engine = LocationEngine.shared
    @StateObject private var notifier = Notifier.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(engine)
                .environmentObject(notifier)
                .preferredColorScheme(.dark)
        }
    }
}
