import AVKit
import SwiftUI

enum ReliquaryTabMode: String, CaseIterable, Identifiable {
    case folders = "Creators"
    case timeline = "Timeline"
    case search = "Search"
    case favorites = "Favorites ♥"

    var id: String { rawValue }
}

struct ReliquaryDriveView: View {
    @EnvironmentObject var store: StudioStore
    @State private var mode: ReliquaryTabMode = .folders
    @State private var selectedItem: ReliquaryMediaItem? = nil
    @State private var activePlaylist: [ReliquaryMediaItem] = []

    private let mediaColumns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    private let folderColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                statusHeaderBar
                modePickerBar

                Group {
                    switch mode {
                    case .folders:
                        foldersBrowserContent
                    case .timeline:
                        timelineBrowserContent
                    case .search:
                        searchBrowserContent
                    case .favorites:
                        favoritesBrowserContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(StudioTheme.bgDeep.ignoresSafeArea())
            .navigationTitle("Reliquary Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.lockStealthImmediately()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.slash.fill")
                            Text("Hide")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(StudioTheme.cyanGlow)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { await store.refreshReliquaryAll() }
                        } label: {
                            Label("Refresh Reliquary Drive", systemImage: "arrow.clockwise")
                        }
                        Button {
                            Task { await store.triggerReliquaryRescan() }
                        } label: {
                            Label("Rescan TrueNAS IDrive-Sync", systemImage: "externaldrive.badge.timemachine")
                        }
                        Divider()
                        Button {
                            mode = .folders
                            Task { await store.fetchReliquaryFolder("patreon_incoming/patreon") }
                        } label: {
                            Label("Jump to Creator Folders", systemImage: "folder.fill.badge.person.crop")
                        }
                        Button {
                            mode = .folders
                            Task { await store.fetchReliquaryFolder("") }
                        } label: {
                            Label("Jump to Drive Root (/)", systemImage: "externaldrive.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(StudioTheme.textPrimary)
                    }
                }
            }
            .sheet(item: $selectedItem) { item in
                ReliquaryFullViewerSheet(
                    initialItem: item,
                    playlist: activePlaylist.isEmpty ? [item] : activePlaylist
                )
                .environmentObject(store)
            }
            .task {
                if store.reliquaryStatus == nil {
                    await store.refreshReliquaryAll()
                }
            }
        }
    }

    // MARK: - Top Status Header Bar
    private var statusHeaderBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.reliquaryOnline ? StudioTheme.emerald : StudioTheme.amber)
                .frame(width: 8, height: 8)

            if let st = store.reliquaryStatus, store.reliquaryOnline {
                Text("IDrive-Sync • \(st.images.formatted()) Photos • \(st.videos.formatted()) Videos")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(StudioTheme.textPrimary)
                    .lineLimit(1)
            } else {
                Text("Reliquary Drive (100.85.127.42:8788) • Connecting...")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(StudioTheme.amber)
                    .lineLimit(1)
            }

            Spacer()

            if store.reliquaryIsLoading {
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(StudioTheme.crimson)
            } else {
                Button {
                    Task { await store.refreshReliquaryAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(StudioTheme.cyanGlow)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(StudioTheme.bgCard)
    }

    // MARK: - Mode Picker
    private var modePickerBar: some View {
        Picker("Mode", selection: $mode) {
            ForEach(ReliquaryTabMode.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
    }

    // MARK: - 1. Creator Folders Browser
    private var foldersBrowserContent: some View {
        VStack(spacing: 8) {
            folderBreadcrumbBar

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !store.reliquaryFolders.isEmpty {
                        Text("FOLDERS (\(store.reliquaryFolders.count))")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.8)
                            .foregroundColor(StudioTheme.cyanGlow)
                            .padding(.horizontal, 12)

                        LazyVGrid(columns: folderColumns, spacing: 10) {
                            ForEach(store.reliquaryFolders) { folder in
                                Button {
                                    Task {
                                        await store.fetchReliquaryFolder(folder.path)
                                    }
                                } label: {
                                    ReliquaryFolderCard(folder: folder)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }

                    if !store.reliquaryFolderItems.isEmpty {
                        Text("MEDIA IN FOLDER (\(store.reliquaryFolderItems.count))")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.8)
                            .foregroundColor(StudioTheme.crimson)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)

                        mediaGrid(items: store.reliquaryFolderItems, paginateTimeline: false)
                    }

                    if store.reliquaryFolders.isEmpty && store.reliquaryFolderItems.isEmpty && !store.reliquaryIsLoading {
                        emptyStateView(
                            icon: "folder.badge.questionmark",
                            title: "Folder Empty or Unreachable",
                            subtitle: "Make sure Tailscale is connected on your iPhone (100.85.127.42:8788), or tap Creators Root above."
                        )
                    }
                }
                .padding(.vertical, 8)
            }
            .refreshable {
                await store.fetchReliquaryFolder(store.reliquaryCurrentFolder)
            }
        }
    }

    private var folderBreadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    Task { await store.fetchReliquaryFolder("__patreon_live__") }
                } label: {
                    Label("Paid Patrons (Live)", systemImage: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(store.reliquaryCurrentFolder.hasPrefix("__patreon_live__") ? .white : StudioTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(store.reliquaryCurrentFolder.hasPrefix("__patreon_live__") ? StudioTheme.crimson : StudioTheme.bgElevated)
                        )
                }

                Button {
                    Task { await store.fetchReliquaryFolder("patreon_incoming/patreon") }
                } label: {
                    Label("Creators", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(store.reliquaryCurrentFolder == "patreon_incoming/patreon" ? .white : StudioTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(store.reliquaryCurrentFolder == "patreon_incoming/patreon" ? StudioTheme.crimson : StudioTheme.bgElevated)
                        )
                }

                Button {
                    Task { await store.fetchReliquaryFolder("") }
                } label: {
                    Label("Root /", systemImage: "externaldrive.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(store.reliquaryCurrentFolder.isEmpty ? .white : StudioTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(store.reliquaryCurrentFolder.isEmpty ? StudioTheme.crimson : StudioTheme.bgElevated)
                        )
                }

                if !store.reliquaryCurrentFolder.isEmpty {
                    Button {
                        let parts = store.reliquaryCurrentFolder.split(separator: "/").dropLast()
                        let parent = parts.joined(separator: "/")
                        Task { await store.fetchReliquaryFolder(parent) }
                    } label: {
                        Label("Up", systemImage: "arrow.turn.left.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(StudioTheme.cyanGlow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(StudioTheme.bgElevated))
                    }

                    Text(store.reliquaryCurrentFolder)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(StudioTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    // MARK: - 2. Timeline Browser
    private var timelineBrowserContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                timelineFilterPill(label: "All Media", kind: "")
                timelineFilterPill(label: "Photos Only", kind: "image")
                timelineFilterPill(label: "Videos Only", kind: "video")
                Spacer()
            }
            .padding(.horizontal, 14)

            ScrollView {
                if store.reliquaryTimelineItems.isEmpty && !store.reliquaryIsLoading {
                    emptyStateView(
                        icon: "photo.on.rectangle.angled",
                        title: "No Timeline Items Loaded",
                        subtitle: "Tap Refresh or check that your iPhone is connected to Tailscale."
                    )
                } else {
                    mediaGrid(items: store.reliquaryTimelineItems, paginateTimeline: true)
                }
            }
            .refreshable {
                await store.fetchReliquaryTimeline(reset: true)
            }
        }
    }

    private func timelineFilterPill(label: String, kind: String) -> some View {
        let active = store.reliquaryTimelineKind == kind
        return Button {
            store.reliquaryTimelineKind = kind
            Task {
                await store.fetchReliquaryTimeline(reset: true)
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(active ? .white : StudioTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(active ? StudioTheme.crimson : StudioTheme.bgElevated)
                )
        }
    }

    // MARK: - 3. Search Browser
    private var searchBrowserContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(StudioTheme.textSecondary)
                TextField("Search creator, folder, or filename...", text: $store.reliquarySearchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13))
                    .foregroundColor(StudioTheme.textPrimary)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await store.searchReliquary(store.reliquarySearchQuery) }
                    }
                if !store.reliquarySearchQuery.isEmpty {
                    Button {
                        store.reliquarySearchQuery = ""
                        store.reliquarySearchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(StudioTheme.textSecondary)
                    }
                }
                Button {
                    Task { await store.searchReliquary(store.reliquarySearchQuery) }
                } label: {
                    Text("Find")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(StudioTheme.crimson)
                        .clipShape(Capsule())
                }
            }
            .padding(10)
            .background(StudioTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 14)

            ScrollView {
                if store.reliquarySearchResults.isEmpty {
                    emptyStateView(
                        icon: "magnifyingglass.circle",
                        title: "Search 266,690 Private Files",
                        subtitle: "Enter a creator name (e.g. Alana Fox, Coug, Dark Artifacts, Seductive Thicc) or filename above."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FOUND \(store.reliquarySearchResults.count) MATCHES")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(StudioTheme.cyanGlow)
                            .padding(.horizontal, 14)
                        mediaGrid(items: store.reliquarySearchResults, paginateTimeline: false)
                    }
                }
            }
        }
    }

    // MARK: - 4. Favorites Browser
    private var favoritesBrowserContent: some View {
        ScrollView {
            if store.reliquaryFavorites.isEmpty {
                emptyStateView(
                    icon: "heart.slash",
                    title: "No Favorites Yet",
                    subtitle: "Tap the ♥ button on any photo or video in Reliquary Drive to pin it here."
                )
            } else {
                mediaGrid(items: store.reliquaryFavorites, paginateTimeline: false)
            }
        }
        .refreshable {
            await store.fetchReliquaryFavorites()
        }
        .task {
            await store.fetchReliquaryFavorites()
        }
    }

    // MARK: - Shared 3-Column Media Grid
    private func mediaGrid(items: [ReliquaryMediaItem], paginateTimeline: Bool) -> some View {
        LazyVGrid(columns: mediaColumns, spacing: 6) {
            ForEach(items) { item in
                Button {
                    activePlaylist = items
                    selectedItem = item
                } label: {
                    ReliquaryMediaThumbCell(item: item)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if paginateTimeline, item.id == items.last?.id {
                        Task {
                            await store.fetchReliquaryTimeline(reset: false)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 24)
    }

    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(StudioTheme.textSecondary.opacity(0.6))
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(StudioTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(StudioTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Folder Card with Cover Thumbnail
struct ReliquaryFolderCard: View {
    @EnvironmentObject var store: StudioStore
    let folder: ReliquaryFolderEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let cover = folder.cover, let url = store.reliquaryThumbURL(path: cover, size: "s") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Rectangle()
                            .fill(StudioTheme.bgElevated)
                            .overlay(
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(StudioTheme.crimson.opacity(0.6))
                            )
                    }
                }
                .frame(height: 125)
                .clipped()
            } else {
                Rectangle()
                    .fill(StudioTheme.bgElevated)
                    .frame(height: 125)
                    .overlay(
                        Image(systemName: "folder.fill")
                            .font(.system(size: 28))
                            .foregroundColor(StudioTheme.crimson.opacity(0.6))
                    )
            }

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(folder.count.formatted()) items")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(StudioTheme.cyanGlow)
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(StudioTheme.borderSubtle, lineWidth: 1)
        )
    }
}

// MARK: - Media Grid Thumbnail Cell
struct ReliquaryMediaThumbCell: View {
    @EnvironmentObject var store: StudioStore
    let item: ReliquaryMediaItem

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let url = store.reliquaryThumbURL(path: item.path, size: "s") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Rectangle()
                            .fill(StudioTheme.bgElevated)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(StudioTheme.textSecondary)
                            )
                    }
                }
                .frame(height: 135)
                .clipped()
            } else {
                Rectangle()
                    .fill(StudioTheme.bgElevated)
                    .frame(height: 135)
            }

            HStack(spacing: 4) {
                if item.favorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(StudioTheme.crimson)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                }
                if item.isVideo {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("VID")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(StudioTheme.crimson.opacity(0.9)))
                }
            }
            .padding(5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Full-Screen Swipeable Media & Video Viewer Sheet
struct ReliquaryFullViewerSheet: View {
    @EnvironmentObject var store: StudioStore
    @Environment(\.dismiss) private var dismiss

    let initialItem: ReliquaryMediaItem
    let playlist: [ReliquaryMediaItem]

    @State private var currentPath: String = ""

    private var currentItem: ReliquaryMediaItem {
        playlist.first(where: { $0.path == currentPath }) ?? initialItem
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $currentPath) {
                    ForEach(playlist) { media in
                        ReliquarySingleMediaPage(item: media)
                            .tag(media.path)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(currentItem.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text(currentItem.folder)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(StudioTheme.cyanGlow)
                        .lineLimit(1)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActionControls
            }
            .onAppear {
                if currentPath.isEmpty {
                    currentPath = initialItem.path
                }
            }
        }
    }

    private var bottomActionControls: some View {
        HStack(spacing: 10) {
            Button {
                Task { await store.toggleReliquaryFavorite(currentItem) }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: currentItem.favorite ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(currentItem.favorite ? StudioTheme.crimson : .white)
                    Text("Favorite")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(StudioTheme.bgElevated.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if !currentItem.isVideo {
                Button {
                    Task { await store.saveReliquaryItemToLocalVault(currentItem) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "lock.doc.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(StudioTheme.emerald)
                        Text("To Vault")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(StudioTheme.bgElevated.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    Task { await store.saveReliquaryItemToPhotos(currentItem) }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(StudioTheme.cyanGlow)
                        Text("Save Photo")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(StudioTheme.bgElevated.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    Task {
                        await store.useReliquaryItemInStudio(currentItem)
                        dismiss()
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text("AI Studio")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(StudioTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.85))
    }
}

struct ReliquarySingleMediaPage: View {
    @EnvironmentObject var store: StudioStore
    let item: ReliquaryMediaItem
    @State private var zoomScale: CGFloat = 1.0
    @State private var player: AVPlayer? = nil

    var body: some View {
        ZStack {
            if item.isVideo {
                if let player = player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .horizontal)
                } else {
                    ProgressView("Loading video stream...")
                        .foregroundColor(.white)
                }
            } else {
                if let url = store.reliquaryThumbURL(path: item.path, size: "m") {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(zoomScale)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { val in
                                            zoomScale = max(1.0, min(val, 4.0))
                                        }
                                        .onEnded { _ in
                                            if zoomScale < 1.1 {
                                                withAnimation(.spring()) { zoomScale = 1.0 }
                                            }
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation(.spring()) {
                                        zoomScale = (zoomScale > 1.1) ? 1.0 : 2.5
                                    }
                                }
                        case .failure:
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(StudioTheme.amber)
                                Text("Could not load preview")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        default:
                            ProgressView()
                                .tint(StudioTheme.crimson)
                        }
                    }
                }
            }
        }
        .onAppear {
            if item.isVideo, player == nil, let streamURL = store.reliquaryFileURL(path: item.path) {
                let av = AVPlayer(url: streamURL)
                self.player = av
                av.play()
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}
