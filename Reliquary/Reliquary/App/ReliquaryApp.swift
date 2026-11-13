import SwiftUI

@main
struct ReliquaryApp: App {
    @StateObject private var session = Session()

    init() {
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .tint(Theme.crimsonBright)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        Group {
            if let client = session.client {
                MainTabsView(client: client)
                    .id(ObjectIdentifier(client))
            } else {
                LoginView()
            }
        }
        .gothicBackground()
        .task {
            await session.refreshUser()
        }
    }
}

struct MainTabsView: View {
    let client: ImmichClient
    @StateObject private var timeline = TimelineStore()
    @StateObject private var uploads = UploadManager()

    var body: some View {
        TabView {
            TimelineView(client: client, store: timeline)
                .tabItem { Label("Timeline", systemImage: "photo.stack") }
            AlbumsView(client: client)
                .tabItem { Label("Albums", systemImage: "rectangle.stack") }
            SearchView(client: client)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            UploadView(client: client, uploads: uploads, timeline: timeline)
                .tabItem { Label("Upload", systemImage: "arrow.up.circle") }
            SettingsView(client: client)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
