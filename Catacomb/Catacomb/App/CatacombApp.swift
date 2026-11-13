import SwiftUI

@main
struct CatacombApp: App {
    @StateObject private var store = LocationStore()
    @StateObject private var nav = Navigator()

    init() {
        Theme.configureAppearance()
        FileOps.clearStaging()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(nav)
                .tint(Theme.crimsonBright)
                .preferredColorScheme(.dark)
        }
    }
}
