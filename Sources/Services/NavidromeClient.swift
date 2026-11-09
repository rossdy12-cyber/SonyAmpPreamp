import Foundation
import CryptoKit

struct SubsonicArtist: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let albumCount: Int?
}

struct SubsonicAlbum: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let year: Int?
}

struct SubsonicTrack: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let album: String?
    let artist: String?
    let track: Int?
    let duration: Int?
    let bitRate: Int?
    let suffix: String?
    let contentType: String?
    let size: Int64?
    let coverArt: String?

    var formattedDuration: String {
        guard let d = duration else { return "--:--" }
        return String(format: "%d:%02d", d / 60, d % 60)
    }

    var qualityBadge: String {
        let ext = (suffix ?? "AUDIO").uppercased()
        if let br = bitRate, br > 0 {
            return "\(ext) • \(br) kbps"
        }
        return ext
    }
}

@MainActor
final class NavidromeClient: ObservableObject {
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "nd_server_url") }
    }
    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "nd_username") }
    }
    @Published var password: String {
        didSet { UserDefaults.standard.set(password, forKey: "nd_password") }
    }

    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var artists: [SubsonicArtist] = []
    @Published var recentAlbums: [SubsonicAlbum] = []
    @Published var searchTracks: [SubsonicTrack] = []

    init() {
        let savedURL = UserDefaults.standard.string(forKey: "nd_server_url") ?? ""
        if savedURL.isEmpty || savedURL == "http://100.85.127.42:30043" {
            self.serverURL = "https://navidrome.nas-server.co.uk"
        } else {
            self.serverURL = savedURL
        }
        self.username = UserDefaults.standard.string(forKey: "nd_username") ?? "NISES"
        self.password = UserDefaults.standard.string(forKey: "nd_password") ?? ""
    }

    private func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func buildURL(endpoint: String, queryItems: [URLQueryItem] = []) -> URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard var components = URLComponents(string: "\(trimmed)/rest/\(endpoint)") else { return nil }

        let salt = String(Int.random(in: 100000...999999))
        let token = md5Hex(password + salt)

        var items: [URLQueryItem] = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "SonyAmpDSP"),
            URLQueryItem(name: "f", value: "json")
        ]
        items.append(contentsOf: queryItems)
        components.queryItems = items
        return components.url
    }

    func coverArtURL(id: String?, size: Int = 300) -> URL? {
        guard let id = id, !id.isEmpty else { return nil }
        return buildURL(endpoint: "getCoverArt.view", queryItems: [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "size", value: String(size))
        ])
    }

    func pingAndLoadLibrary() async {
        if password.isEmpty && !serverURL.contains("nas-server.co.uk") {
            errorMessage = "Enter your Navidrome password for \(username), or switch URL to https://navidrome.nas-server.co.uk"
            isConnected = false
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guard let artistsURL = buildURL(endpoint: "getArtists.view"),
                  let albumsURL = buildURL(endpoint: "getAlbumList2.view", queryItems: [
                      URLQueryItem(name: "type", value: "frequent"),
                      URLQueryItem(name: "size", value: "30")
                  ]) else {
                throw URLError(.badURL)
            }

            async let artistsData = URLSession.shared.data(from: artistsURL)
            async let albumsData = URLSession.shared.data(from: albumsURL)

            let (aBytes, _) = try await artistsData
            let (alBytes, _) = try await albumsData

            if let json = try JSONSerialization.jsonObject(with: aBytes) as? [String: Any],
               let resp = json["subsonic-response"] as? [String: Any] {
                if let status = resp["status"] as? String, status == "failed",
                   let err = resp["error"] as? [String: Any],
                   let msg = err["message"] as? String {
                    self.errorMessage = "Navidrome: \(msg)"
                    self.isConnected = false
                    return
                }
                if let artistsRoot = resp["artists"] as? [String: Any],
                   let indices = artistsRoot["index"] as? [[String: Any]] {
                    var parsed: [SubsonicArtist] = []
                    for idx in indices {
                        if let list = idx["artist"] as? [[String: Any]] {
                            for item in list {
                                if let id = item["id"] as? String,
                                   let name = item["name"] as? String {
                                    let count = item["albumCount"] as? Int
                                    parsed.append(SubsonicArtist(id: id, name: name, albumCount: count))
                                }
                            }
                        }
                    }
                    self.artists = parsed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    self.isConnected = true
                }
            }

            if let json = try JSONSerialization.jsonObject(with: alBytes) as? [String: Any],
               let resp = json["subsonic-response"] as? [String: Any],
               let albumList = resp["albumList2"] as? [String: Any],
               let albumsArr = albumList["album"] as? [[String: Any]] {
                self.recentAlbums = albumsArr.compactMap { Self.parseAlbum($0) }
            }
        } catch {
            self.errorMessage = "Connection failed (\(error.localizedDescription)). Ensure Tailscale is active or you are on LAN."
            self.isConnected = false
        }
    }

    func fetchArtistAlbums(artistId: String) async -> [SubsonicAlbum] {
        guard let url = buildURL(endpoint: "getArtist.view", queryItems: [
            URLQueryItem(name: "id", value: artistId)
        ]) else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let resp = json["subsonic-response"] as? [String: Any],
               let artist = resp["artist"] as? [String: Any],
               let albums = artist["album"] as? [[String: Any]] {
                return albums.compactMap { Self.parseAlbum($0) }
            }
        } catch {}
        return []
    }

    func fetchAlbumTracks(albumId: String) async -> [SubsonicTrack] {
        guard let url = buildURL(endpoint: "getAlbum.view", queryItems: [
            URLQueryItem(name: "id", value: albumId)
        ]) else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let resp = json["subsonic-response"] as? [String: Any],
               let album = resp["album"] as? [String: Any],
               let songs = album["song"] as? [[String: Any]] {
                return songs.compactMap { Self.parseTrack($0) }
            }
        } catch {}
        return []
    }

    func search(query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchTracks = []
            return
        }
        guard let url = buildURL(endpoint: "search3.view", queryItems: [
            URLQueryItem(name: "query", value: q),
            URLQueryItem(name: "songCount", value: "40")
        ]) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let resp = json["subsonic-response"] as? [String: Any],
               let res = resp["searchResult3"] as? [String: Any],
               let songs = res["song"] as? [[String: Any]] {
                self.searchTracks = songs.compactMap { Self.parseTrack($0) }
            }
        } catch {}
    }

    /// Downloads raw bit-perfect FLAC/audio file to local cache so AVAudioEngine can process 32-bit float DSP
    func downloadTrackForDSP(track: SubsonicTrack) async throws -> URL {
        let ext = (track.suffix ?? "flac").lowercased()
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("NavidromeCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let localURL = cacheDir.appendingPathComponent("\(track.id).\(ext)")
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        guard let streamURL = buildURL(endpoint: "stream.view", queryItems: [
            URLQueryItem(name: "id", value: track.id),
            URLQueryItem(name: "raw", value: "true")
        ]) else {
            throw URLError(.badURL)
        }

        let (tempURL, _) = try await URLSession.shared.download(from: streamURL)
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        return localURL
    }

    private static func parseAlbum(_ dict: [String: Any]) -> SubsonicAlbum? {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String ?? dict["title"] as? String else { return nil }
        return SubsonicAlbum(
            id: id,
            name: name,
            artist: dict["artist"] as? String,
            artistId: dict["artistId"] as? String,
            coverArt: dict["coverArt"] as? String,
            songCount: dict["songCount"] as? Int,
            duration: dict["duration"] as? Int,
            year: dict["year"] as? Int
        )
    }

    private static func parseTrack(_ dict: [String: Any]) -> SubsonicTrack? {
        guard let id = dict["id"] as? String,
              let title = dict["title"] as? String else { return nil }
        return SubsonicTrack(
            id: id,
            title: title,
            album: dict["album"] as? String,
            artist: dict["artist"] as? String,
            track: dict["track"] as? Int,
            duration: dict["duration"] as? Int,
            bitRate: dict["bitRate"] as? Int,
            suffix: dict["suffix"] as? String,
            contentType: dict["contentType"] as? String,
            size: (dict["size"] as? NSNumber)?.int64Value,
            coverArt: dict["coverArt"] as? String
        )
    }
}
