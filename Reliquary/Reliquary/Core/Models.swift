import Foundation

// MARK: - Helpers

func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
}

enum DateParsing {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ text: String?) -> Date? {
        guard let text = text else { return nil }
        if let d = DateParsing.withFraction.date(from: text) { return d }
        return DateParsing.plain.date(from: text)
    }

    static func iso(_ date: Date) -> String {
        DateParsing.withFraction.string(from: date)
    }
}

// MARK: - Immich models (tolerant: every field except ids is optional)

struct ImmichUser: Decodable {
    let id: String
    let email: String?
    let name: String?

    private enum CodingKeys: String, CodingKey { case id, email, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        email = try? c.decode(String.self, forKey: .email)
        name = try? c.decode(String.self, forKey: .name)
    }

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        if let e = email, !e.isEmpty { return e }
        return "Immich user"
    }
}

struct ImmichAsset: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let originalFileName: String?
    let fileCreatedAt: String?
    let localDateTime: String?
    let isFavorite: Bool?
    let sortDate: Date?

    private enum CodingKeys: String, CodingKey {
        case id, type, originalFileName, fileCreatedAt, localDateTime, isFavorite
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try? c.decode(String.self, forKey: .type)
        originalFileName = try? c.decode(String.self, forKey: .originalFileName)
        let created = try? c.decode(String.self, forKey: .fileCreatedAt)
        let local = try? c.decode(String.self, forKey: .localDateTime)
        fileCreatedAt = created
        localDateTime = local
        isFavorite = try? c.decode(Bool.self, forKey: .isFavorite)
        sortDate = DateParsing.parse(local) ?? DateParsing.parse(created)
    }

    var isVideo: Bool { (type ?? "").uppercased() == "VIDEO" }
    var displayName: String { originalFileName ?? id }
}

struct ImmichAlbum: Decodable, Identifiable, Hashable {
    let id: String
    let albumName: String
    let assetCount: Int?
    let albumThumbnailAssetId: String?

    private enum CodingKeys: String, CodingKey {
        case id, albumName, assetCount, albumThumbnailAssetId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        albumName = (try? c.decode(String.self, forKey: .albumName)) ?? "Untitled"
        assetCount = try? c.decode(Int.self, forKey: .assetCount)
        albumThumbnailAssetId = try? c.decode(String.self, forKey: .albumThumbnailAssetId)
    }
}

struct ImmichAlbumDetail: Decodable {
    let assets: [ImmichAsset]
    let assetCount: Int?

    private enum CodingKeys: String, CodingKey { case assets, assetCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assets = (try? c.decode([ImmichAsset].self, forKey: .assets)) ?? []
        assetCount = try? c.decode(Int.self, forKey: .assetCount)
    }
}

/// Response shape of POST /search/metadata and POST /search/smart:
/// `{ "assets": { "items": [...], "nextPage": "2" | 2 | null } }`
struct AssetsPage: Decodable {
    let items: [ImmichAsset]
    let nextPage: Int?

    private enum Outer: String, CodingKey { case assets }
    private enum Inner: String, CodingKey { case items, nextPage }

    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: Outer.self)
        let inner = try outer.nestedContainer(keyedBy: Inner.self, forKey: .assets)
        items = try inner.decode([ImmichAsset].self, forKey: .items)
        if let s = try? inner.decode(String.self, forKey: .nextPage) {
            nextPage = Int(s)
        } else if let i = try? inner.decode(Int.self, forKey: .nextPage) {
            nextPage = i
        } else {
            nextPage = nil
        }
    }
}

struct UploadResponse: Decodable {
    let id: String?
    let status: String?

    private enum CodingKeys: String, CodingKey { case id, status }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decode(String.self, forKey: .id)
        status = try? c.decode(String.self, forKey: .status)
    }
}

// MARK: - Timeline grouping

struct MonthSection: Identifiable {
    let id: String
    let title: String
    var assets: [ImmichAsset]
}

enum MonthGrouping {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return c
    }()

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = MonthGrouping.calendar
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    static func sections(from assets: [ImmichAsset]) -> [MonthSection] {
        let sorted = assets.sorted {
            ($0.sortDate ?? Date.distantPast) > ($1.sortDate ?? Date.distantPast)
        }
        var result: [MonthSection] = []
        for asset in sorted {
            var key = "undated"
            if let d = asset.sortDate {
                let parts = MonthGrouping.calendar.dateComponents([.year, .month], from: d)
                key = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
            }
            if let last = result.last, last.id == key {
                result[result.count - 1].assets.append(asset)
            } else {
                var title = "Undated"
                if let d = asset.sortDate {
                    title = MonthGrouping.titleFormatter.string(from: d)
                }
                result.append(MonthSection(id: key, title: title, assets: [asset]))
            }
        }
        return result
    }
}
