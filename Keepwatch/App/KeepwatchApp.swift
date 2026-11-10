import SwiftUI

@main
struct KeepwatchApp: App {
    @StateObject private var store = KeepwatchStore()

    var body: some Scene {
        WindowGroup {
            KeepwatchRootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
