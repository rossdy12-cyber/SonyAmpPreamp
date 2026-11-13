import SwiftUI

struct AlbumsView: View {
    let client: ImmichClient

    @State private var albums: [ImmichAlbum] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && albums.isEmpty {
                    ProgressView()
                        .tint(Theme.crimsonBright)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if albums.isEmpty, let message = errorMessage {
                    ErrorStateView(message: message) {
                        Task { @MainActor in await load() }
                    }
                } else if albums.isEmpty {
                    EmptyStateView(
                        symbol: "rectangle.stack",
                        title: "No albums",
                        message: "Albums you create in Immich will appear here."
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(albums) { album in
                                NavigationLink(value: album) {
                                    AlbumCard(client: client, album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                    }
                    .refreshable {
                        await Task { @MainActor in await load() }.value
                    }
                }
            }
            .gothicBackground()
            .navigationTitle("Albums")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ImmichAlbum.self) { album in
                AlbumDetailView(client: client, album: album)
            }
        }
        .task {
            if !didLoad {
                didLoad = true
                await load()
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            albums = try await client.albums()
        } catch {
            if !isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}

struct AlbumCard: View {
    let client: ImmichClient
    let album: ImmichAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(cover)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.hairline, lineWidth: 1)
                )

            Text(album.albumName)
                .font(Theme.title(15))
                .foregroundColor(Theme.bone)
                .lineLimit(1)

            if let count = album.assetCount {
                Text(count == 1 ? "1 relic" : "\(count) relics")
                    .font(Theme.body(12))
                    .foregroundColor(Theme.muted)
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let thumbId = album.albumThumbnailAssetId {
            RemoteImage(client: client, assetId: thumbId, size: .thumbnail, contentMode: .fill)
        } else {
            ZStack {
                Theme.panel
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 30))
                    .foregroundColor(Theme.crimson)
            }
        }
    }
}

struct AlbumDetailView: View {
    let client: ImmichClient
    let album: ImmichAlbum

    @State private var assets: [ImmichAsset] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didLoad = false
    @State private var viewer: ViewerContext?

    var body: some View {
        Group {
            if isLoading && assets.isEmpty {
                ProgressView()
                    .tint(Theme.crimsonBright)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if assets.isEmpty, let message = errorMessage {
                ErrorStateView(message: message) {
                    Task { @MainActor in await load() }
                }
            } else if assets.isEmpty {
                EmptyStateView(
                    symbol: "photo.on.rectangle",
                    title: "Empty crypt",
                    message: "This album has no photos or videos yet."
                )
            } else {
                AssetGridView(client: client, assets: assets) { index in
                    viewer = ViewerContext(assets: assets, startIndex: index)
                }
            }
        }
        .gothicBackground()
        .navigationTitle(album.albumName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !didLoad {
                didLoad = true
                await load()
            }
        }
        .fullScreenCover(item: $viewer) { context in
            ViewerView(client: client, assets: context.assets, startIndex: context.startIndex)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await client.albumAssets(id: album.id)
            assets = fetched.sorted {
                ($0.sortDate ?? Date.distantPast) > ($1.sortDate ?? Date.distantPast)
            }
        } catch {
            if !isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}
