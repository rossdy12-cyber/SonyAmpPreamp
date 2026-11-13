import SwiftUI

@main
struct GrimoireApp: App {
    @StateObject private var store = NoteStore()
    @StateObject private var settings = SyncSettings()
    @StateObject private var sync = SyncService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        GrimoireTheme.styleNavigationBar()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(sync)
                .preferredColorScheme(.dark)
                .tint(GrimoireTheme.crimsonBright)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && settings.autoSync && settings.isConfigured {
                        Task { @MainActor in
                            await sync.sync(store: store, settings: settings)
                        }
                    }
                }
        }
    }
}
