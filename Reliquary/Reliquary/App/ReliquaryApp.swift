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
    #if !os(tvOS)
    @StateObject private var uploads = UploadManager()
    #endif

    var body: some View {
        TabView {
            TimelineView(client: client, store: timeline)
                .tabItem { Label("Timeline", systemImage: "photo.stack") }
            AlbumsView(client: client)
                .tabItem { Label("Albums", systemImage: "rectangle.stack") }
            #if os(tvOS)
            SlideshowAmbientView(client: client, store: timeline)
                .tabItem { Label("4K Slideshow", systemImage: "sparkles.tv") }
            #endif
            SearchView(client: client)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            #if !os(tvOS)
            UploadView(client: client, uploads: uploads, timeline: timeline)
                .tabItem { Label("Upload", systemImage: "arrow.up.circle") }
            #endif
            SettingsView(client: client)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#if os(tvOS)
struct SlideshowAmbientView: View {
    let client: ImmichClient
    @ObservedObject var store: TimelineStore
    @State private var currentIndex: Int = 0
    @State private var currentImage: UIImage?
    @State private var zoomToggle: Bool = false

    private var photoAssets: [ImmichAsset] {
        store.assets.filter { !$0.isVideo }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.ignoresSafeArea()
            if let img = currentImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(zoomToggle ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 8.0), value: zoomToggle)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    ProgressView().tint(Theme.crimsonBright)
                    Text("Preparing 4K Ambient Memories Frame...")
                        .font(Theme.title(22))
                        .foregroundColor(Theme.bone)
                }
            }

            if !photoAssets.isEmpty, photoAssets.indices.contains(currentIndex) {
                let asset = photoAssets[currentIndex]
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asset.displayName)
                            .font(Theme.title(20))
                            .foregroundColor(Theme.bone)
                        Text("RELIQUARY 4K AMBIENT FRAME • \(currentIndex + 1) / \(photoAssets.count)")
                            .font(Theme.body(14))
                            .foregroundColor(Theme.crimsonBright)
                    }
                    Spacer()
                    Button("Next Relic") {
                        advance()
                    }
                }
                .padding(32)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
            }
        }
        .task {
            if store.assets.isEmpty {
                await store.loadMore(client: client)
            }
            await loadSlide()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { break }
                advance()
            }
        }
    }

    private func advance() {
        let list = photoAssets
        guard !list.isEmpty else { return }
        currentIndex = (currentIndex + 1) % list.count
        Task { await loadSlide() }
    }

    private func loadSlide() async {
        let list = photoAssets
        guard list.indices.contains(currentIndex) else { return }
        let asset = list[currentIndex]
        if let data = try? await client.imageData(assetId: asset.id, size: .preview),
           let decoded = UIImage(data: data) {
            withAnimation(.easeInOut(duration: 1.0)) {
                currentImage = decoded
                zoomToggle.toggle()
            }
        }
    }
}
#endif
