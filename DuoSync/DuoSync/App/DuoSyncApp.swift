import SwiftUI

@main
@MainActor
struct DuoSyncApp: App {
    @StateObject private var store: Store
    @StateObject private var sync: SyncManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = Store()
        let manager = SyncManager(store: store)
        _store = StateObject(wrappedValue: store)
        _sync = StateObject(wrappedValue: manager)
        BackgroundSync.register(manager)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(sync)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        Task { await sync.syncIfStale() }
                    case .background:
                        BackgroundSync.schedule()
                    default:
                        break
                    }
                }
        }
    }
}
