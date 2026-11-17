import SwiftUI
import UserNotifications

@main
struct JarvisCompanionApp: App {
    @StateObject private var syncManager = JarvisSyncManager.shared

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(syncManager)
                .preferredColorScheme(.dark)
        }
    }
}
