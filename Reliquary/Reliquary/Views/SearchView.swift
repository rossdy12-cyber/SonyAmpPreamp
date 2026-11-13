import SwiftUI

struct SearchView: View {
    let client: ImmichClient

    @State private var query = ""
    @State private var results: [ImmichAsset] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @State private var viewer: ViewerContext?

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    VStack(spacing: 14) {
                        ProgressView().tint(Theme.crimsonBright)
                        Text("Searching the archive...")
                            .font(Theme.body(14))
                            .foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = errorMessage {
                    ErrorStateView(message: message) {
                        Task { @MainActor in await runSearch() }
                    }
                } else if !hasSearched {
                    EmptyStateView(
                        symbol: "sparkle.magnifyingglass",
                        title: "Seek a memory",
                        message: "Describe what you're looking for, like \"candlelit church\" or \"dog on a beach\"."
                    )
                } else if results.isEmpty {
                    EmptyStateView(
                        symbol: "moon.zzz",
                        title: "Nothing found",
                        message: "No relics matched that search."
                    )
                } else {
                    AssetGridView(client: client, assets: results) { index in
                        viewer = ViewerContext(assets: results, startIndex: index)
                    }
                }
            }
            .gothicBackground()
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Describe what you seek")
            .onSubmit(of: .search) {
                Task { @MainActor in await runSearch() }
            }
        }
        .fullScreenCover(item: $viewer) { context in
            ViewerView(client: client, assets: context.assets, startIndex: context.startIndex)
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        hasSearched = true
        do {
            results = try await client.smartSearch(query: trimmed)
        } catch {
            if !isCancellation(error) {
                results = []
                errorMessage = error.localizedDescription
            }
        }
        isSearching = false
    }
}
