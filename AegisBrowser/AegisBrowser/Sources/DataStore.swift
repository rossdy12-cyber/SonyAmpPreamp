import Foundation
import Combine

// MARK: - Persistence models

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: String { url }
    var url: String
    var title: String
    var date: Date
}

struct FavoriteEntry: Codable, Identifiable, Equatable {
    var id: String { url }
    var title: String
    var url: String
}

struct BookmarkFolder: Codable, Identifiable, Equatable {
    var id: String { title }
    var title: String
    var entries: [HistoryEntry]
}

struct DownloadEntry: Codable, Identifiable {
    var id: UUID
    var filename: String
    var url: String
    var date: Date
    var completed: Bool
}

// MARK: - Store

final class DataStore: ObservableObject {
    static let shared = DataStore()
    private let dir: URL
    private let queue = DispatchQueue(label: "aegis.datastore")

    @Published var history: [HistoryEntry] = []
    @Published var favorites: [FavoriteEntry] = []
    @Published var bookmarks: [HistoryEntry] = []
    @Published var downloads: [DownloadEntry] = []
    @Published var blockerWhitelist: Set<String> = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = support.appendingPathComponent("AegisData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    private func fileURL(_ name: String) -> URL { dir.appendingPathComponent(name) }

    private func load() {
        history = read("history.json")
        favorites = read("favorites.json")
        bookmarks = read("bookmarks.json")
        downloads = read("downloads.json")
        let wl: [String] = read("blocker_whitelist.json")
        blockerWhitelist = Set(wl)
    }

    private func read<T: Decodable>(_ name: String) -> T {
        if let data = try? Data(contentsOf: fileURL(name)),
           let v = try? JSONDecoder().decode(T.self, from: data) {
            return v
        }
        switch name {
        case "blocker_whitelist.json": return [] as! T
        default: return [] as! T
        }
    }

    private func persist<T: Encodable>(_ value: T, _ name: String) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? data.write(to: self.fileURL(name), options: .atomic)
        }
    }

    // History
    func recordVisit(url: String, title: String) {
        guard !url.hasPrefix("about:") else { return }
        history.removeAll { $0.url == url }
        history.insert(HistoryEntry(url: url, title: title.isEmpty ? url : title, date: Date()), at: 0)
        if history.count > 2000 { history.removeLast(history.count - 2000) }
        persist(history, "history.json")
    }

    func clearHistory() {
        history.removeAll()
        persist(history, "history.json")
    }

    // Bookmarks / Favorites
    func addBookmark(url: String, title: String) {
        guard !bookmarks.contains(where: { $0.url == url }) else { return }
        bookmarks.insert(HistoryEntry(url: url, title: title.isEmpty ? url : title, date: Date()), at: 0)
        persist(bookmarks, "bookmarks.json")
    }

    func removeBookmark(_ entry: HistoryEntry) {
        bookmarks.removeAll { $0.url == entry.url }
        persist(bookmarks, "bookmarks.json")
    }

    func isBookmarked(_ url: String) -> Bool {
        bookmarks.contains { $0.url == url }
    }

    func addFavorite(url: String, title: String) {
        guard !favorites.contains(where: { $0.url == url }) else { return }
        favorites.append(FavoriteEntry(title: title.isEmpty ? url : title, url: url))
        persist(favorites, "favorites.json")
    }

    func removeFavorite(_ f: FavoriteEntry) {
        favorites.removeAll { $0.url == f.url }
        persist(favorites, "favorites.json")
    }

    // Downloads
    func upsertDownload(_ d: DownloadEntry) {
        if let idx = downloads.firstIndex(where: { $0.id == d.id }) {
            downloads[idx] = d
        } else {
            downloads.insert(d, at: 0)
        }
        persist(downloads, "downloads.json")
    }

    func removeDownload(_ d: DownloadEntry) {
        downloads.removeAll { $0.id == d.id }
        persist(downloads, "downloads.json")
        try? FileManager.default.removeItem(at: downloadsDir.appendingPathComponent(d.filename))
    }

    var downloadsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // Blocker whitelist
    func toggleWhitelist(host: String) {
        if blockerWhitelist.contains(host) {
            blockerWhitelist.remove(host)
        } else {
            blockerWhitelist.insert(host)
        }
        persist(Array(blockerWhitelist), "blocker_whitelist.json")
    }

    // Settings
    enum SearchEngine: String, CaseIterable, Identifiable {
        case duckduckgo = "DuckDuckGo", google = "Google", bing = "Bing", startpage = "Startpage"
        var id: String { rawValue }
        var template: String {
            switch self {
            case .duckduckgo: return "https://duckduckgo.com/?q=%@"
            case .google: return "https://www.google.com/search?q=%@"
            case .bing: return "https://www.bing.com/search?q=%@"
            case .startpage: return "https://www.startpage.com/sp/search?query=%@"
            }
        }
    }

    var searchEngine: SearchEngine {
        get { SearchEngine(rawValue: UserDefaults.standard.string(forKey: "aegis.engine") ?? "") ?? .duckduckgo }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "aegis.engine") }
    }

    var blockerEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "aegis.blocker") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "aegis.blocker") }
    }

    var forceDark: Bool {
        get { UserDefaults.standard.bool(forKey: "aegis.dark") }
        set { UserDefaults.standard.set(newValue, forKey: "aegis.dark") }
    }

    var textZoom: Int {
        get { UserDefaults.standard.object(forKey: "aegis.zoom") as? Int ?? 100 }
        set { UserDefaults.standard.set(newValue, forKey: "aegis.zoom") }
    }
}
