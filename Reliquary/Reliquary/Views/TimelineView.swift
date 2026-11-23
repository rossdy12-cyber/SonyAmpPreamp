import SwiftUI

enum PhotoGridLayout {
    static let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
}

@MainActor
final class TimelineStore: ObservableObject {
    @Published private(set) var assets: [ImmichAsset] = []
    @Published private(set) var sections: [MonthSection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var reachedEnd = false
    @Published var errorMessage: String?

    private var nextPage: Int? = 1
    private var knownIDs = Set<String>()

    func reload(client: ImmichClient) async {
        guard !isLoading else { return }
        assets = []
        sections = []
        knownIDs = []
        nextPage = 1
        reachedEnd = false
        errorMessage = nil
        await loadMore(client: client)
    }

    func loadMore(client: ImmichClient) async {
        guard !isLoading, !reachedEnd, let page = nextPage else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await client.searchMetadata(page: page)
            var fresh: [ImmichAsset] = []
            for asset in result.items where !knownIDs.contains(asset.id) {
                knownIDs.insert(asset.id)
                fresh.append(asset)
            }
            assets.append(contentsOf: fresh)
            sections = MonthGrouping.sections(from: assets)
            if let next = result.nextPage {
                nextPage = next
            } else {
                nextPage = nil
                reachedEnd = true
            }
            errorMessage = nil
        } catch {
            if !isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Assets in the exact order shown on screen (newest first).
    var displayOrder: [ImmichAsset] {
        return sections.flatMap { $0.assets }
    }
}

struct TimelineView: View {
    let client: ImmichClient
    @ObservedObject var store: TimelineStore
    @State private var viewer: ViewerContext?

    var body: some View {
        NavigationStack {
            Group {
                if store.sections.isEmpty && store.isLoading {
                    VStack(spacing: 14) {
                        ProgressView().tint(Theme.crimsonBright)
                        Text("Unearthing your archive...")
                            .font(Theme.body(14))
                            .foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.sections.isEmpty, let message = store.errorMessage {
                    ErrorStateView(message: message) {
                        Task { @MainActor in await store.reload(client: client) }
                    }
                } else if store.sections.isEmpty {
                    EmptyStateView(
                        symbol: "moon.stars",
                        title: "Nothing here yet",
                        message: "Upload photos from the Upload tab, or pull down to refresh."
                    )
                } else {
                    content
                }
            }
            .gothicBackground()
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if store.assets.isEmpty && !store.isLoading {
                await store.loadMore(client: client)
            }
        }
        .fullScreenCover(item: $viewer) { context in
            ViewerView(client: client, assets: context.assets, startIndex: context.startIndex)
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(store.sections) { section in
                    Section {
                        LazyVGrid(columns: PhotoGridLayout.columns, spacing: 2) {
                            ForEach(section.assets) { asset in
                                #if os(tvOS)
                                Button {
                                    open(asset)
                                } label: {
                                    AssetCell(client: client, asset: asset)
                                }
                                .buttonStyle(.plain)
                                #else
                                AssetCell(client: client, asset: asset)
                                    .onTapGesture { open(asset) }
                                #endif
                            }
                        }
                    } header: {
                        MonthHeader(title: section.title, count: section.assets.count)
                    }
                }
                footer
            }
        }
        .refreshable {
            // An unstructured Task keeps SwiftUI from cancelling the reload when the list re-renders.
            await Task { @MainActor in
                await store.reload(client: client)
            }.value
        }
    }

    @ViewBuilder
    private var footer: some View {
        if store.isLoading {
            ProgressView()
                .tint(Theme.crimsonBright)
                .frame(maxWidth: .infinity)
                .padding(24)
        } else if let message = store.errorMessage {
            VStack(spacing: 8) {
                Text(message)
                    .font(Theme.body(13))
                    .foregroundColor(Theme.crimsonBright)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { @MainActor in await store.loadMore(client: client) }
                }
                .foregroundColor(Theme.bone)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        } else if !store.reachedEnd {
            Color.clear
                .frame(height: 1)
                .onAppear {
                    Task { @MainActor in await store.loadMore(client: client) }
                }
        } else {
            VStack(spacing: 6) {
                OrnateDivider()
                Text("\(store.assets.count) relics in the archive")
                    .font(Theme.body(12))
                    .foregroundColor(Theme.muted)
            }
            .padding(24)
        }
    }

    private func open(_ asset: ImmichAsset) {
        let ordered = store.displayOrder
        guard let index = ordered.firstIndex(where: { $0.id == asset.id }) else { return }
        viewer = ViewerContext(assets: ordered, startIndex: index)
    }
}

struct MonthHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.title(19))
                .foregroundColor(Theme.bone)
            Spacer()
            Text("\(count)")
                .font(Theme.body(13))
                .foregroundColor(Theme.crimsonBright)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.bg.opacity(0.94))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

struct AssetCell: View {
    let client: ImmichClient
    let asset: ImmichAsset

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RemoteImage(client: client, assetId: asset.id, size: .thumbnail, contentMode: .fill)
            )
            .overlay(alignment: .bottomTrailing) {
                if asset.isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.bone)
                        .padding(5)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
            .overlay(alignment: .topLeading) {
                if asset.isFavorite == true {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.crimsonBright)
                        .padding(5)
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }
}

/// Non-sectioned grid used by albums and search.
struct AssetGridView: View {
    let client: ImmichClient
    let assets: [ImmichAsset]
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: PhotoGridLayout.columns, spacing: 2) {
                ForEach(Array(assets.enumerated()), id: \.element.id) { index, asset in
                    #if os(tvOS)
                    Button {
                        onSelect(index)
                    } label: {
                        AssetCell(client: client, asset: asset)
                    }
                    .buttonStyle(.plain)
                    #else
                    AssetCell(client: client, asset: asset)
                        .onTapGesture { onSelect(index) }
                    #endif
                }
            }
        }
    }
}
