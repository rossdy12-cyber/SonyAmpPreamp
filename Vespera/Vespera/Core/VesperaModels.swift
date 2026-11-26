import Foundation
import CryptoKit

// MARK: - 8-Channel Procedural Sleep Soundscape Channels

enum SoundChannelID: String, CaseIterable, Identifiable, Codable {
    case rain = "rain"
    case thunder = "thunder"
    case cathedral = "cathedral"
    case hearth = "hearth"
    case ocean = "ocean"
    case brownNoise = "brown"
    case pinkNoise = "pink"
    case binauralDelta = "binaural"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rain: return "Midnight Rain"
        case .thunder: return "Rolling Thunder"
        case .cathedral: return "Cathedral Drone"
        case .hearth: return "Obsidian Hearth"
        case .ocean: return "Abyssal Ocean"
        case .brownNoise: return "Velvet Brown"
        case .pinkNoise: return "Warm Pink"
        case .binauralDelta: return "Delta 2.5Hz Wave"
        }
    }

    var subtitle: String {
        switch self {
        case .rain: return "Stereo rainfall on leaded cathedral glass"
        case .thunder: return "35–90 Hz sub-bass thunder swells for CP-DS10"
        case .cathedral: return "55/110/165 Hz harmonic pipe organ pad"
        case .hearth: return "Warm crackling logs & glowing ember pops"
        case .ocean: return "Slow 0.12 Hz binaural tidal surf roll"
        case .brownNoise: return "Deep 1/f² low-frequency masking blanket"
        case .pinkNoise: return "Balanced octave-band acoustic masking"
        case .binauralDelta: return "110 Hz L / 112.5 Hz R deep-sleep entrainment"
        }
    }

    var icon: String {
        switch self {
        case .rain: return "cloud.rain.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        case .cathedral: return "building.columns.fill"
        case .hearth: return "flame.fill"
        case .ocean: return "water.waves"
        case .brownNoise: return "waveform.path"
        case .pinkNoise: return "waveform"
        case .binauralDelta: return "brain.head.profile"
        }
    }
}

struct SleepRitualPreset: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let levels: [SoundChannelID: Float]
    let recommendedEQ: CPDS10EQPreset

    static let presets: [SleepRitualPreset] = [
        SleepRitualPreset(
            id: "cpds10_slumber",
            name: "CP-DS10 Deep Slumber",
            subtitle: "Midnight Rain + Velvet Brown + Delta 2.5Hz",
            icon: "moon.stars.fill",
            levels: [.rain: 0.62, .brownNoise: 0.45, .binauralDelta: 0.35, .cathedral: 0.25],
            recommendedEQ: .warmBedside
        ),
        SleepRitualPreset(
            id: "gothic_storm",
            name: "Gothic Storm Sanctuary",
            subtitle: "Heavy Rain + 40W Rolling Thunder + Cathedral Organ",
            icon: "cloud.bolt.rain.fill",
            levels: [.rain: 0.78, .thunder: 0.68, .cathedral: 0.42],
            recommendedEQ: .cathedralStereo
        ),
        SleepRitualPreset(
            id: "cathedral_hearth",
            name: "Cathedral Hearth",
            subtitle: "Crackling Obsidian Fireplace + Soft Rain + Warm Drone",
            icon: "flame.fill",
            levels: [.hearth: 0.75, .rain: 0.38, .cathedral: 0.32],
            recommendedEQ: .warmBedside
        ),
        SleepRitualPreset(
            id: "abyssal_tide",
            name: "Abyssal Midnight Tide",
            subtitle: "Slow Stereo Ocean Swell + Warm Pink + Delta Wave",
            icon: "water.waves",
            levels: [.ocean: 0.75, .pinkNoise: 0.28, .binauralDelta: 0.30],
            recommendedEQ: .warmBedside
        ),
        SleepRitualPreset(
            id: "velvet_isolation",
            name: "Partner-Safe Night Mask",
            subtitle: "Sub-Cut Brown & Pink Noise Acoustic Blanket",
            icon: "bed.double.fill",
            levels: [.brownNoise: 0.72, .pinkNoise: 0.40],
            recommendedEQ: .nightSubCut
        )
    ]
}

// MARK: - SHARP CP-DS10 40W Twin-Neodymium 5-Band DSP EQ Presets

enum CPDS10EQPreset: String, CaseIterable, Identifiable, Codable {
    case warmBedside = "warm_bedside"
    case nightSubCut = "night_sub_cut"
    case cathedralStereo = "cathedral_stereo"
    case deepBass = "deep_bass"
    case vocalClarity = "vocal_clarity"
    case custom = "custom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmBedside: return "CP-DS10 Warm Bedside"
        case .nightSubCut: return "Night Sub-Cut (Quiet)"
        case .cathedralStereo: return "40W Cathedral Stereo"
        case .deepBass: return "40W Deep Neodymium Bass"
        case .vocalClarity: return "Vocal & Soundtrack Clarity"
        case .custom: return "Custom 5-Band DSP"
        }
    }

    var description: String {
        switch self {
        case .warmBedside:
            return "Tuned for near-field bedside listening on the SHARP CP-DS10's twin 2\" neodymium drivers (+3.5 dB @ 60Hz, silky rolled-off highs)."
        case .nightSubCut:
            return "Attenuates 60Hz sub-bass (-8 dB) so overnight music & storms won't travel through walls or disturb light sleepers."
        case .cathedralStereo:
            return "Full 40W stereo staging with expanded low-end punch and crystalline 14kHz air."
        case .deepBass:
            return "Maximizes low-end warmth (+7 dB @ 60Hz, +4.5 dB @ 230Hz) from the CP-DS10 acoustic chamber."
        case .vocalClarity:
            return "Lifts 910Hz–3.6kHz vocal and instrumental presence for podcasts, audiobooks, and OSTs."
        case .custom:
            return "User-defined 5-band parametric gain curves."
        }
    }

    /// Gains in dB for [60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz]
    var bands: [Float] {
        switch self {
        case .warmBedside:     return [3.5,  2.5,  0.0, -1.5, -2.5]
        case .nightSubCut:     return [-8.0, -3.5, 0.5,  0.0, -2.0]
        case .cathedralStereo: return [5.0,  2.0,  1.5,  2.5,  4.0]
        case .deepBass:        return [7.0,  4.5,  0.0,  1.0,  1.5]
        case .vocalClarity:    return [-2.0, 0.0,  3.5,  3.0,  1.5]
        case .custom:          return [0.0,  0.0,  0.0,  0.0,  0.0]
        }
    }

    static let frequencies: [Float] = [60, 230, 910, 3600, 14000]
    static let bandLabels: [String] = ["60Hz", "230Hz", "910Hz", "3.6k", "14k"]
}

// MARK: - Navidrome / Subsonic Music Models & Client

struct NavAlbum: Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String
    let coverArt: String?
    let songCount: Int
    let year: Int?
}

struct NavPlaylist: Identifiable, Hashable {
    let id: String
    let name: String
    let songCount: Int
    let duration: Int
}

struct NavSong: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let coverArt: String?
    let duration: Int
}

struct SubsonicClient {
    let baseURL: String
    let username: String
    let password: String

    static let fallbackPublicURL = "https://navidrome.nas-server.co.uk"
    static let defaultVPNURL = "http://100.64.0.4:8997"

    private func authQuery() -> String {
        let salt = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let raw = Data((password + salt).utf8)
        let token = Insecure.MD5.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        let uEnc = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        return "u=\(uEnc)&t=\(token)&s=\(salt)&v=1.16.1&c=VesperaCPDS10&f=json"
    }

    func buildURL(base: String, endpoint: String, extraQuery: String = "") -> URL? {
        var cleanBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleanBase.hasSuffix("/") { cleanBase.removeLast() }
        let q = authQuery() + (extraQuery.isEmpty ? "" : "&" + extraQuery)
        return URL(string: "\(cleanBase)/rest/\(endpoint)?\(q)")
    }

    func fetchJSON(endpoint: String, extraQuery: String = "") async throws -> ( [String: Any], String ) {
        let candidates = [baseURL, Self.defaultVPNURL, Self.fallbackPublicURL]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let uniqueBases = candidates.filter { seen.insert($0).inserted }

        var lastError: Error = URLError(.cannotConnectToHost)
        for candidate in uniqueBases {
            guard let url = buildURL(base: candidate, endpoint: endpoint, extraQuery: extraQuery) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            req.setValue("Vespera/1.0 (SHARP-CP-DS10-Qi2)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let sub = root["subsonic-response"] as? [String: Any],
                   (sub["status"] as? String) == "ok" {
                    return (sub, candidate)
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func fetchAlbums(type: String = "recent", size: Int = 60) async throws -> ([NavAlbum], String) {
        let (sub, activeBase) = try await fetchJSON(endpoint: "getAlbumList2.view", extraQuery: "type=\(type)&size=\(size)")
        let container = sub["albumList2"] as? [String: Any]
        let list = container?["album"] as? [[String: Any]] ?? []
        let albums = list.compactMap { a -> NavAlbum? in
            guard let id = a["id"] as? String, let name = a["name"] as? String else { return nil }
            return NavAlbum(
                id: id,
                name: name,
                artist: (a["artist"] as? String) ?? "Unknown Artist",
                coverArt: a["coverArt"] as? String,
                songCount: (a["songCount"] as? Int) ?? 0,
                year: a["year"] as? Int
            )
        }
        return (albums, activeBase)
    }

    func fetchPlaylists() async throws -> [NavPlaylist] {
        let (sub, _) = try await fetchJSON(endpoint: "getPlaylists.view")
        let container = sub["playlists"] as? [String: Any]
        let list = container?["playlist"] as? [[String: Any]] ?? []
        return list.compactMap { p -> NavPlaylist? in
            guard let id = p["id"] as? String, let name = p["name"] as? String else { return nil }
            return NavPlaylist(
                id: id,
                name: name,
                songCount: (p["songCount"] as? Int) ?? 0,
                duration: (p["duration"] as? Int) ?? 0
            )
        }
    }

    func fetchAlbumSongs(albumID: String) async throws -> [NavSong] {
        let enc = albumID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? albumID
        let (sub, _) = try await fetchJSON(endpoint: "getAlbum.view", extraQuery: "id=\(enc)")
        let alb = sub["album"] as? [String: Any]
        let list = alb?["song"] as? [[String: Any]] ?? []
        return Self.parseSongs(list)
    }

    func fetchPlaylistSongs(playlistID: String) async throws -> [NavSong] {
        let enc = playlistID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? playlistID
        let (sub, _) = try await fetchJSON(endpoint: "getPlaylist.view", extraQuery: "id=\(enc)")
        let pl = sub["playlist"] as? [String: Any]
        let list = pl?["entry"] as? [[String: Any]] ?? []
        return Self.parseSongs(list)
    }

    func searchSongs(query: String) async throws -> [NavSong] {
        let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let (sub, _) = try await fetchJSON(endpoint: "search3.view", extraQuery: "query=\(enc)&songCount=40&albumCount=10")
        let sr = sub["searchResult3"] as? [String: Any]
        let list = sr?["song"] as? [[String: Any]] ?? []
        return Self.parseSongs(list)
    }

    func fetchRandomSleepSongs(size: Int = 30) async throws -> [NavSong] {
        let (sub, _) = try await fetchJSON(endpoint: "getRandomSongs.view", extraQuery: "size=\(size)")
        let container = sub["randomSongs"] as? [String: Any]
        let list = container?["song"] as? [[String: Any]] ?? []
        return Self.parseSongs(list)
    }

    private static func parseSongs(_ list: [[String: Any]]) -> [NavSong] {
        list.compactMap { s -> NavSong? in
            guard let id = s["id"] as? String, let title = s["title"] as? String else { return nil }
            return NavSong(
                id: id,
                title: title,
                artist: (s["artist"] as? String) ?? "Unknown Artist",
                album: (s["album"] as? String) ?? "",
                coverArt: s["coverArt"] as? String,
                duration: (s["duration"] as? Int) ?? 0
            )
        }
    }

    func streamURL(songID: String, activeBase: String? = nil) -> URL? {
        let b = (activeBase?.isEmpty == false) ? activeBase! : baseURL
        let enc = songID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? songID
        return buildURL(base: b, endpoint: "stream.view", extraQuery: "id=\(enc)")
    }

    func coverURL(coverID: String?, activeBase: String? = nil, size: Int = 360) -> URL? {
        guard let coverID, !coverID.isEmpty else { return nil }
        let b = (activeBase?.isEmpty == false) ? activeBase! : baseURL
        let enc = coverID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? coverID
        return buildURL(base: b, endpoint: "getCoverArt.view", extraQuery: "id=\(enc)&size=\(size)")
    }
}
