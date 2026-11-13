import Foundation
import UniformTypeIdentifiers

enum ImageSize: String {
    case thumbnail
    case preview
}

enum ImmichError: LocalizedError {
    case invalidURL
    case missingKey
    case unauthorized
    case server(Int, String?)
    case badResponse
    case decoding(String)
    case network(String)
    case upload(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That server address doesn't look right. Try something like https://immich.example.com"
        case .missingKey:
            return "Enter your Immich API key."
        case .unauthorized:
            return "The server rejected the API key. Create a new key in Immich under Account Settings > API Keys."
        case .server(let status, let message):
            if let message = message, !message.isEmpty {
                return "Server error \(status): \(message)"
            }
            return "Server error \(status)."
        case .badResponse:
            return "The server sent a response Reliquary couldn't understand. Is this really an Immich server?"
        case .decoding(let detail):
            return "Couldn't read the server's reply (\(detail)). The Immich version may differ from what Reliquary expects."
        case .network(let detail):
            return "Couldn't reach the server: \(detail)"
        case .upload(let detail):
            return "Upload failed: \(detail)"
        }
    }
}

final class ImmichClient {
    let baseURL: URL
    let apiKey: String
    private let session: URLSession

    static let sharedCache = URLCache(
        memoryCapacity: 64 * 1024 * 1024,
        diskCapacity: 1024 * 1024 * 1024,
        directory: nil
    )

    init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.urlCache = ImmichClient.sharedCache
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 45
        config.httpMaximumConnectionsPerHost = 8
        self.session = URLSession(configuration: config)
    }

    // MARK: URL handling

    /// Accepts "host", "host:2283", "https://host/", "https://host/api" and returns the bare base URL.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            s = "https://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        if s.lowercased().hasSuffix("/api") {
            s = String(s.dropLast(4))
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    private func apiURL(_ path: String) throws -> URL {
        guard let url = URL(string: baseURL.absoluteString + "/api" + path) else {
            throw ImmichError.invalidURL
        }
        return url
    }

    private func makeRequest(
        _ path: String,
        method: String = "GET",
        jsonBody: [String: Any]? = nil,
        forImage: Bool = false
    ) throws -> URLRequest {
        var request = URLRequest(url: try apiURL(path))
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(forImage ? "*/*" : "application/json", forHTTPHeaderField: "Accept")
        if let body = jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if forImage {
            request.cachePolicy = .returnCacheDataElseLoad
        }
        return request
    }

    // MARK: Transport

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            try check(response, data: data)
            return data
        } catch let error as URLError {
            if error.code == .cancelled { throw error }
            throw ImmichError.network(error.localizedDescription)
        }
    }

    private func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ImmichError.badResponse }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw ImmichError.unauthorized
        default:
            throw ImmichError.server(http.statusCode, serverMessage(from: data))
        }
    }

    private func serverMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let message = object["message"] as? String { return message }
        if let list = object["message"] as? [String] { return list.joined(separator: ", ") }
        return nil
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ImmichError.decoding(String(describing: type))
        }
    }

    // MARK: Account

    func validate() async throws -> ImmichUser {
        let data = try await send(try makeRequest("/users/me"))
        return try decode(ImmichUser.self, from: data)
    }

    // MARK: Timeline and search

    /// Timeline source. Uses POST /search/metadata with pagination, which exists across many Immich versions.
    func searchMetadata(page: Int, size: Int = 200, albumId: String? = nil) async throws -> AssetsPage {
        var body: [String: Any] = ["page": page, "size": size]
        if let albumId = albumId { body["albumIds"] = [albumId] }
        var ordered = body
        ordered["order"] = "desc"
        do {
            let data = try await send(try makeRequest("/search/metadata", method: "POST", jsonBody: ordered))
            return try decode(AssetsPage.self, from: data)
        } catch let error as ImmichError {
            // Some versions reject the "order" field; retry without it.
            if case .server(let status, _) = error, status == 400 {
                let data = try await send(try makeRequest("/search/metadata", method: "POST", jsonBody: body))
                return try decode(AssetsPage.self, from: data)
            }
            throw error
        }
    }

    func smartSearch(query: String) async throws -> [ImmichAsset] {
        let body: [String: Any] = ["query": query, "page": 1, "size": 200]
        let data = try await send(try makeRequest("/search/smart", method: "POST", jsonBody: body))
        return try decode(AssetsPage.self, from: data).items
    }

    // MARK: Albums

    func albums() async throws -> [ImmichAlbum] {
        let ownedData = try await send(try makeRequest("/albums"))
        var result = try decode([ImmichAlbum].self, from: ownedData)
        if let sharedData = try? await send(try makeRequest("/albums?shared=true")),
           let shared = try? decode([ImmichAlbum].self, from: sharedData) {
            let known = Set(result.map { $0.id })
            result.append(contentsOf: shared.filter { !known.contains($0.id) })
        }
        return result
    }

    func albumAssets(id: String) async throws -> [ImmichAsset] {
        let data = try await send(try makeRequest("/albums/\(id)"))
        let detail = try decode(ImmichAlbumDetail.self, from: data)
        if !detail.assets.isEmpty || (detail.assetCount ?? 0) == 0 {
            return detail.assets
        }
        // Newer servers may omit the asset list from the album endpoint; page through search instead.
        var collected: [ImmichAsset] = []
        var page = 1
        var guardCount = 0
        while guardCount < 100 {
            let result = try await searchMetadata(page: page, size: 200, albumId: id)
            collected.append(contentsOf: result.items)
            guardCount += 1
            if let next = result.nextPage { page = next } else { break }
        }
        return collected
    }

    // MARK: Media

    func imageData(assetId: String, size: ImageSize) async throws -> Data {
        do {
            let path = "/assets/\(assetId)/thumbnail?size=\(size.rawValue)"
            return try await send(try makeRequest(path, forImage: true))
        } catch let error as ImmichError {
            if case .server(let status, _) = error, status == 404 {
                let format = size == .preview ? "JPEG" : "WEBP"
                let legacy = "/asset/thumbnail/\(assetId)?format=\(format)"
                return try await send(try makeRequest(legacy, forImage: true))
            }
            throw error
        }
    }

    func videoPlaybackURL(assetId: String) -> URL? {
        return try? apiURL("/assets/\(assetId)/video/playback")
    }

    static func clearCaches() {
        ImmichClient.sharedCache.removeAllCachedResponses()
        ImageStore.shared.removeAll()
    }

    // MARK: Upload

    /// Streams a multipart body to a temp file and uploads it, so large videos don't sit in memory.
    func uploadAsset(
        fileURL: URL,
        filename: String,
        deviceAssetId: String,
        created: Date,
        modified: Date
    ) async throws -> String {
        let boundary = "ReliquaryBoundary-" + UUID().uuidString
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reliquary-body-" + UUID().uuidString + ".multipart")
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
            throw ImmichError.upload("couldn't create a temporary file")
        }

        do {
            let out = try FileHandle(forWritingTo: bodyURL)
            let fields: [(String, String)] = [
                ("deviceAssetId", deviceAssetId),
                ("deviceId", "reliquary-ios"),
                ("fileCreatedAt", DateParsing.iso(created)),
                ("fileModifiedAt", DateParsing.iso(modified)),
                ("isFavorite", "false")
            ]
            for (name, value) in fields {
                let part = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
                try out.write(contentsOf: Data(part.utf8))
            }

            let safeName = filename.replacingOccurrences(of: "\"", with: "_")
            let mime = ImmichClient.mimeType(for: fileURL)
            let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"assetData\"; filename=\"\(safeName)\"\r\nContent-Type: \(mime)\r\n\r\n"
            try out.write(contentsOf: Data(header.utf8))

            let input = try FileHandle(forReadingFrom: fileURL)
            while true {
                guard let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty else { break }
                try out.write(contentsOf: chunk)
            }
            try input.close()

            try out.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try out.close()
        } catch {
            throw ImmichError.upload(error.localizedDescription)
        }

        var request = try makeRequest("/assets", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        do {
            let (data, response) = try await session.upload(for: request, fromFile: bodyURL)
            try check(response, data: data)
            let parsed = try? JSONDecoder().decode(UploadResponse.self, from: data)
            return parsed?.status ?? "created"
        } catch let error as URLError {
            if error.code == .cancelled { throw error }
            throw ImmichError.network(error.localizedDescription)
        }
    }

    private static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
