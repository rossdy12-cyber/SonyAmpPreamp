import SwiftUI

@main
struct TorporApp: App {
    @StateObject private var store = SleepStore.shared
    @StateObject private var engine = SleepAudioEngine()

    init() {
        Theme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}
