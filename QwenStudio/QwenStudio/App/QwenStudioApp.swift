import SwiftUI

@main
struct QwenStudioApp: App {
    @StateObject private var store = StudioStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
