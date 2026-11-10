import Foundation
import SwiftUI

struct SlskdSearchFile: Identifiable, Hashable {
    var id: String { "\(username)|\(filename)" }
    let username: String
    let filename: String
    let size: Int64
    let bitRate: Int?
    let sampleRate: Int?
    let bitDepth: Int?
    let lengthSeconds: Int?
    let hasFreeUploadSlot: Bool
    let uploadSpeed: Int

    var shortName: String {
        filename.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? filename
    }

    var folderName: String {
        let parts = filename.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/")
        guard parts.count >= 2 else { return "" }
        return parts[parts.count - 2]
    }

    var isLossless: Bool {
        let lower = filename.lowercased()
        return lower.hasSuffix(".flac") || lower.hasSuffix(".wav") || lower.hasSuffix(".alac")
    }

    var qualityBadge: String {
        let ext = (filename.components(separatedBy: ".").last ?? "AUDIO").uppercased()
        if let bd = bitDepth, let sr = sampleRate, bd > 0, sr > 0 {
            return "\(ext) \(bd)-bit/\(sr / 1000)kHz"
        }
        if let br = bitRate, br > 0 {
            return "\(ext) \(br)kbps"
        }
        return ext
    }

    var sizeMB: String {
        String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0))
    }
}

struct SlskdTransferItem: Identifiable, Hashable {
    let id: String
    let username: String
    let filename: String
    let state: String
    let percentComplete: Double
    let size: Int64

    var shortName: String {
        filename.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? filename
    }
}

struct LidarrArtistItem: Identifiable, Hashable {
    let id: Int
    let artistName: String
    let foreignArtistId: String
    let overview: String
    let monitored: Bool
    let albumCount: Int
    let trackCount: Int
    let sizeOnDisk: Int64
}

struct LidarrQueueItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let artistName: String
    let status: String
    let protocolName: String
    let sizeleft: Double
    let size: Double

    var progressPercent: Int {
        guard size > 0 else { return 0 }
        return max(0, min(100, Int(((size - sizeleft) / size) * 100.0)))
    }
}

@MainActor
final class AcquisitionClient: ObservableObject {
    // SoulSeekr (slskd) Config & State
    @Published var slskdURL: String {
        didSet { UserDefaults.standard.set(slskdURL, forKey: "acq.slskd.url") }
    }
    @Published var slskdApiKey: String {
        didSet { UserDefaults.standard.set(slskdApiKey, forKey: "acq.slskd.key") }
    }
    @Published var slskdSearchText: String = ""
    @Published var slskdOnlyFLAC: Bool = false
    @Published var slskdIsSearching: Bool = false
    @Published var slskdStatus: String = "Ready — Connected to TrueNAS slskd (:5030)"
    @Published var slskdResults: [SlskdSearchFile] = []
    @Published var slskdTransfers: [SlskdTransferItem] = []

    // Encore (Lidarr) Config & State
    @Published var lidarrURL: String {
        didSet { UserDefaults.standard.set(lidarrURL, forKey: "acq.lidarr.url") }
    }
    @Published var lidarrApiKey: String {
        didSet { UserDefaults.standard.set(lidarrApiKey, forKey: "acq.lidarr.key") }
    }
    @Published var lidarrArtists: [LidarrArtistItem] = []
    @Published var lidarrLookupResults: [LidarrArtistItem] = []
    @Published var lidarrQueue: [LidarrQueueItem] = []
    @Published var lidarrSearchTerm: String = ""
    @Published var lidarrStatus: String = "Ready — Connected to TrueNAS Lidarr (:30071)"
    @Published var lidarrIsLoading: Bool = false

    init() {
        let d = UserDefaults.standard
        let savedSlskdURL = d.string(forKey: "acq.slskd.url") ?? ""
        self.slskdURL = savedSlskdURL.isEmpty ? "http://100.85.127.42:5030" : savedSlskdURL
        let savedSlskdKey = d.string(forKey: "acq.slskd.key") ?? ""
        self.slskdApiKey = savedSlskdKey.isEmpty ? "slskd-key-6b97c2e2c9a607103baad6c9" : savedSlskdKey

        let savedLidarrURL = d.string(forKey: "acq.lidarr.url") ?? ""
        self.lidarrURL = savedLidarrURL.isEmpty ? "http://100.85.127.42:30071" : savedLidarrURL
        let savedLidarrKey = d.string(forKey: "acq.lidarr.key") ?? ""
        self.lidarrApiKey = savedLidarrKey.isEmpty ? "5473b4c450dbda981e6068821b7a084c" : savedLidarrKey
    }

    // MARK: - 1. SoulSeekr (slskd) Search & Download Engine

    private func cleanBase(_ raw: String) -> String {
        var b = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }

    func searchSoulseek() async {
        let q = slskdSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        slskdIsSearching = true
        slskdResults = []
        slskdStatus = "Searching Soulseek P2P network for '\(q)'..."
        defer { slskdIsSearching = false }

        let base = cleanBase(slskdURL)
        guard let startURL = URL(string: "\(base)/api/v0/searches") else {
            slskdStatus = "Invalid slskd URL"
            return
        }

        let searchId = UUID().uuidString
        do {
            var req = URLRequest(url: startURL, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(slskdApiKey, forHTTPHeaderField: "X-API-Key")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "id": searchId,
                "searchText": q
            ])

            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                slskdStatus = "slskd rejected search (HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0))"
                return
            }

            // Poll for P2P responses over 4.5 seconds
            for poll in 1...3 {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                await fetchSlskdSearchResults(searchId: searchId, pollStep: poll)
            }
        } catch {
            slskdStatus = "slskd unreachable (\(error.localizedDescription)). Ensure Tailscale is connected."
        }
    }

    private func fetchSlskdSearchResults(searchId: String, pollStep: Int) async {
        let base = cleanBase(slskdURL)
        guard let resURL = URL(string: "\(base)/api/v0/searches/\(searchId)?includeResponses=true") else { return }
        do {
            var req = URLRequest(url: resURL, timeoutInterval: 12)
            req.setValue(slskdApiKey, forHTTPHeaderField: "X-API-Key")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responses = root["responses"] as? [[String: Any]] else { return }

            var parsed: [SlskdSearchFile] = []
            for r in responses {
                let user = r["username"] as? String ?? "peer"
                let freeSlot = (r["freeUploadSlots"] as? Int ?? 0) > 0
                let speed = r["uploadSpeed"] as? Int ?? 0
                guard let files = r["files"] as? [[String: Any]] else { continue }
                for f in files {
                    guard let fname = f["filename"] as? String else { continue }
                    let lower = fname.lowercased()
                    guard lower.hasSuffix(".flac") || lower.hasSuffix(".mp3") || lower.hasSuffix(".wav") || lower.hasSuffix(".m4a") else { continue }
                    let sz = (f["size"] as? NSNumber)?.int64Value ?? 0
                    parsed.append(SlskdSearchFile(
                        username: user,
                        filename: fname,
                        size: sz,
                        bitRate: f["bitRate"] as? Int,
                        sampleRate: f["sampleRate"] as? Int,
                        bitDepth: f["bitDepth"] as? Int,
                        lengthSeconds: f["length"] as? Int,
                        hasFreeUploadSlot: freeSlot,
                        uploadSpeed: speed
                    ))
                }
            }

            parsed.sort { a, b in
                if a.isLossless != b.isLossless { return a.isLossless }
                if a.hasFreeUploadSlot != b.hasFreeUploadSlot { return a.hasFreeUploadSlot }
                return a.uploadSpeed > b.uploadSpeed
            }
            slskdResults = Array(parsed.prefix(80))
            slskdStatus = "Found \(parsed.count) audio files on Soulseek P2P (\(parsed.filter { $0.isLossless }.count) Lossless FLAC)"
        } catch {}
    }

    func enqueueSlskdDownload(file: SlskdSearchFile) async {
        let base = cleanBase(slskdURL)
        let encodedUser = file.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.username
        guard let url = URL(string: "\(base)/api/v0/transfers/downloads/\(encodedUser)") else { return }
        do {
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(slskdApiKey, forHTTPHeaderField: "X-API-Key")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                ["filename": file.filename, "size": file.size]
            ])
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                slskdStatus = "Queued download on TrueNAS: \(file.shortName)"
                await refreshSlskdTransfers()
            } else {
                slskdStatus = "Peer busy or transfer queued (HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0))"
            }
        } catch {
            slskdStatus = "Download request failed: \(error.localizedDescription)"
        }
    }

    func refreshSlskdTransfers() async {
        let base = cleanBase(slskdURL)
        guard let url = URL(string: "\(base)/api/v0/transfers/downloads") else { return }
        do {
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue(slskdApiKey, forHTTPHeaderField: "X-API-Key")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let users = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            var list: [SlskdTransferItem] = []
            for u in users {
                let uname = u["username"] as? String ?? "peer"
                guard let dirs = u["directories"] as? [[String: Any]] else { continue }
                for d in dirs {
                    guard let files = d["files"] as? [[String: Any]] else { continue }
                    for f in files {
                        let id = f["id"] as? String ?? UUID().uuidString
                        let fname = f["filename"] as? String ?? ""
                        let state = f["state"] as? String ?? "Queued"
                        let pct = f["percentComplete"] as? Double ?? 0.0
                        let sz = (f["size"] as? NSNumber)?.int64Value ?? 0
                        list.append(SlskdTransferItem(id: id, username: uname, filename: fname, state: state, percentComplete: pct, size: sz))
                    }
                }
            }
            slskdTransfers = list
        } catch {}
    }

    // MARK: - 2. Encore (Lidarr) Artist Discovery, Library & Queue Engine

    func loadLidarrLibraryAndQueue() async {
        lidarrIsLoading = true
        defer { lidarrIsLoading = false }
        let base = cleanBase(lidarrURL)

        if let artistURL = URL(string: "\(base)/api/v1/artist") {
            do {
                var req = URLRequest(url: artistURL, timeoutInterval: 12)
                req.setValue(lidarrApiKey, forHTTPHeaderField: "X-Api-Key")
                let (data, _) = try await URLSession.shared.data(for: req)
                if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var parsed: [LidarrArtistItem] = []
                    for item in arr {
                        let id = item["id"] as? Int ?? 0
                        let name = item["artistName"] as? String ?? "Unknown"
                        let mbid = item["foreignArtistId"] as? String ?? ""
                        let overview = item["overview"] as? String ?? ""
                        let monitored = item["monitored"] as? Bool ?? true
                        let stats = item["statistics"] as? [String: Any]
                        let albums = stats?["albumCount"] as? Int ?? 0
                        let tracks = stats?["trackCount"] as? Int ?? 0
                        let size = (stats?["sizeOnDisk"] as? NSNumber)?.int64Value ?? 0
                        parsed.append(LidarrArtistItem(id: id, artistName: name, foreignArtistId: mbid, overview: overview, monitored: monitored, albumCount: albums, trackCount: tracks, sizeOnDisk: size))
                    }
                    lidarrArtists = parsed.sorted { $0.artistName.localizedCaseInsensitiveCompare($1.artistName) == .orderedAscending }
                    lidarrStatus = "Lidarr Connected • \(lidarrArtists.count) Monitored Artists"
                }
            } catch {
                lidarrStatus = "Lidarr unreachable (\(error.localizedDescription)). Ensure Tailscale is active."
            }
        }

        if let qURL = URL(string: "\(base)/api/v1/queue") {
            do {
                var req = URLRequest(url: qURL, timeoutInterval: 10)
                req.setValue(lidarrApiKey, forHTTPHeaderField: "X-Api-Key")
                let (data, _) = try await URLSession.shared.data(for: req)
                if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let records = root["records"] as? [[String: Any]] {
                    lidarrQueue = records.map { r in
                        LidarrQueueItem(
                            id: r["id"] as? Int ?? Int.random(in: 1...99999),
                            title: r["title"] as? String ?? "Album Download",
                            artistName: (r["artist"] as? [String: Any])?["artistName"] as? String ?? "",
                            status: r["status"] as? String ?? "downloading",
                            protocolName: r["protocol"] as? String ?? "usenet/torrent",
                            sizeleft: r["sizeleft"] as? Double ?? 0,
                            size: r["size"] as? Double ?? 100
                        )
                    }
                }
            } catch {}
        }
    }

    func lookupLidarrArtists() async {
        let q = lidarrSearchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        lidarrIsLoading = true
        defer { lidarrIsLoading = false }

        let base = cleanBase(lidarrURL)
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        guard let url = URL(string: "\(base)/api/v1/artist/lookup?term=\(encoded)") else { return }
        do {
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue(lidarrApiKey, forHTTPHeaderField: "X-Api-Key")
            let (data, _) = try await URLSession.shared.data(for: req)
            if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                lidarrLookupResults = arr.prefix(25).enumerated().map { idx, item in
                    LidarrArtistItem(
                        id: item["id"] as? Int ?? (100000 + idx),
                        artistName: item["artistName"] as? String ?? "Artist",
                        foreignArtistId: item["foreignArtistId"] as? String ?? "",
                        overview: item["overview"] as? String ?? "",
                        monitored: true,
                        albumCount: 0,
                        trackCount: 0,
                        sizeOnDisk: 0
                    )
                }
                lidarrStatus = "Found \(lidarrLookupResults.count) artists on MusicBrainz / Lidarr"
            }
        } catch {
            lidarrStatus = "Lookup failed: \(error.localizedDescription)"
        }
    }

    func triggerLidarrArtistSearch(artistId: Int, artistName: String) async {
        let base = cleanBase(lidarrURL)
        guard let url = URL(string: "\(base)/api/v1/command") else { return }
        do {
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(lidarrApiKey, forHTTPHeaderField: "X-Api-Key")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "name": "ArtistSearch",
                "artistId": artistId
            ])
            _ = try await URLSession.shared.data(for: req)
            lidarrStatus = "Triggered Lidarr Indexer Search for \(artistName)"
            await loadLidarrLibraryAndQueue()
        } catch {}
    }

    func addArtistToLidarr(_ artist: LidarrArtistItem) async {
        let base = cleanBase(lidarrURL)
        guard let url = URL(string: "\(base)/api/v1/artist") else { return }
        do {
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(lidarrApiKey, forHTTPHeaderField: "X-Api-Key")
            let body: [String: Any] = [
                "artistName": artist.artistName,
                "foreignArtistId": artist.foreignArtistId,
                "qualityProfileId": 1,
                "metadataProfileId": 1,
                "rootFolderPath": "/music",
                "monitored": true,
                "addOptions": [
                    "monitor": "all",
                    "searchForMissingAlbums": true
                ]
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                lidarrStatus = "Added \(artist.artistName) to Lidarr & started album search!"
                lidarrLookupResults = []
                lidarrSearchTerm = ""
                await loadLidarrLibraryAndQueue()
            } else {
                lidarrStatus = "Artist may already be in Lidarr (HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0))"
            }
        } catch {
            lidarrStatus = "Error adding artist: \(error.localizedDescription)"
        }
    }
}
