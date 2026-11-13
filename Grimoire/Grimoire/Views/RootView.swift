import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var settings: SyncSettings
    @EnvironmentObject var sync: SyncService

    @State private var path: [UUID] = []
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            NoteListView(path: $path, showSettings: $showSettings)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(sync)
        }
        .task {
            if settings.autoSync && settings.isConfigured {
                await sync.sync(store: store, settings: settings)
            }
        }
    }
}
