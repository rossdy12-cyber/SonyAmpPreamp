import Foundation

/// Persists user-granted folders as security-scoped bookmarks.
final class LocationStore: ObservableObject {
    @Published private(set) var locations: [StoredLocation] = []

    private let defaultsKey = "catacomb.locations.v1"

    init() {
        load()
    }

    static var sandboxURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var sandboxRoute: FolderRoute {
        FolderRoute(url: LocationStore.sandboxURL, rootURL: nil, title: "Catacomb")
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([StoredLocation].self, from: data) else {
            return
        }
        locations = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(locations) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    // MARK: Granting access

    /// `url` comes straight from the folder picker and is security scoped.
    func add(folder url: URL) throws {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }
        let wantedPath = url.standardizedFileURL.path
        for existing in locations {
            if let resolved = resolveQuietly(existing), resolved.standardizedFileURL.path == wantedPath {
                return
            }
        }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        locations.append(StoredLocation(id: UUID(), name: url.lastPathComponent, bookmark: data))
        save()
    }

    func remove(at offsets: IndexSet) {
        locations.remove(atOffsets: offsets)
        save()
    }

    // MARK: Resolving

    private func resolveQuietly(_ location: StoredLocation) -> URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: location.bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    /// Resolves a bookmark and refreshes it if iOS marked it stale.
    /// Call from user actions, not from a view body (it may publish changes).
    func route(for location: StoredLocation) -> FolderRoute? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: location.bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        if stale {
            refresh(location, url: url)
        }
        return FolderRoute(url: url, rootURL: url, title: location.name)
    }

    private func refresh(_ location: StoredLocation, url: URL) {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
              let index = locations.firstIndex(where: { $0.id == location.id }) else {
            return
        }
        locations[index].bookmark = data
        save()
    }
}

/// Holds the navigation path so breadcrumbs can pop to any depth.
final class Navigator: ObservableObject {
    @Published var path: [FolderRoute] = []
}
