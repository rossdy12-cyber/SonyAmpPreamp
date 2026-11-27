import Foundation

/// Talks to the DuoSync server running on a Windows PC, over the tailnet.
struct DuoSyncClient {
    let baseURL: URL
    let token: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["x-duosync-protocol": "1"]
        return URLSession(configuration: config)
    }()

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    // MARK: - Endpoints

    func ping(timeout: TimeInterval = 10) async throws -> HostInfo {
        var request = try makeRequest(path: "/api/v1/ping", query: [:], method: "GET")
        request.timeoutInterval = timeout
        let (data, _) = try await send(request)
        guard let info = try? JSONDecoder().decode(HostInfo.self, from: data) else {
            throw SyncError.http(200, "The PC answered with something unexpected. Is DuoSync up to date?")
        }
        guard info.ok == true else { throw SyncError.http(200, "The PC is not ready.") }
        if let proto = info.proto, proto != 1 {
            throw SyncError.http(200, "The PC runs a different protocol version.")
        }
        return info
    }

    func manifest(shareId: String) async throws -> [String: FileEntry] {
        let request = try makeRequest(path: "/api/v1/shares/\(encode(shareId))/manifest", query: [:], method: "GET")
        let (data, _) = try await send(request)
        let manifest = try JSONDecoder().decode(RemoteManifest.self, from: data)
        var files: [String: FileEntry] = [:]
        for entry in manifest.files where !entry.p.isEmpty {
            guard Self.isSafeRelativePath(entry.p) else { continue }
            files[entry.p] = FileEntry(hash: entry.h, size: entry.s, mtime: entry.m)
        }
        return files
    }

    func download(
        shareId: String,
        path: String,
        to destination: URL,
        expectedHash: String?,
        mtimeMs: Int64
    ) async throws {
        let request = try makeRequest(
            path: "/api/v1/shares/\(encode(shareId))/file",
            query: ["p": path],
            method: "GET"
        )
        let (tempURL, response) = try await Self.session.download(for: request)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let http = response as? HTTPURLResponse else { throw SyncError.transport("Bad response") }
        guard http.statusCode == 200 else { throw try error(for: http, body: nil) }

        if let expectedHash {
            let hashed = try Hasher.sha256(of: tempURL)
            guard hashed.hash == expectedHash else { throw SyncError.checksum(path) }
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        if mtimeMs > 0 {
            let date = Date(timeIntervalSince1970: Double(mtimeMs) / 1000)
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: destination.path)
        }
    }

    func upload(shareId: String, path: String, from fileURL: URL, hash: String, mtimeMs: Int64) async throws {
        let request = try makeRequest(
            path: "/api/v1/shares/\(encode(shareId))/file",
            query: ["p": path, "h": hash, "m": String(mtimeMs)],
            method: "PUT",
            contentType: "application/octet-stream"
        )
        let (data, response) = try await Self.session.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else { throw SyncError.transport("Bad response") }
        guard (200..<300).contains(http.statusCode) else {
            throw try error(for: http, body: data)
        }
    }

    func delete(shareId: String, path: String) async throws {
        let request = try makeRequest(
            path: "/api/v1/shares/\(encode(shareId))/file",
            query: ["p": path],
            method: "DELETE"
        )
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.transport("Bad response") }
        guard (200..<300).contains(http.statusCode) else { throw try error(for: http, body: data) }
    }

    // MARK: - Plumbing

    private func makeRequest(
        path: String,
        query: [String: String],
        method: String,
        contentType: String? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SyncError.badAddress
        }
        components.path = path
        if !query.isEmpty {
            components.percentEncodedQuery = query
                .map { "\(encode($0.key))=\(encode($0.value))" }
                .joined(separator: "&")
        }
        guard let url = components.url else { throw SyncError.badAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "x-duosync-token")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SyncError.transport("Bad response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw try error(for: http, body: data)
            }
            return (data, response)
        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.transport(Self.describe(error))
        }
    }

    private func error(for response: HTTPURLResponse, body: Data?) throws -> SyncError {
        let message = body
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }?["error"]
            ?? ""
        switch response.statusCode {
        case 401: return .unauthorized
        case 403: return .readOnly
        case 404: return message.isEmpty ? .missing("that file") : .http(404, message)
        default:
            if message.isEmpty { return .transport(Self.describeStatus(response.statusCode)) }
            return .http(response.statusCode, message)
        }
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            return "Cannot reach the PC. Is it on, with Tailscale connected?"
        case NSURLErrorTimedOut:
            return "The PC took too long to answer."
        case NSURLErrorNetworkConnectionLost:
            return "The connection dropped."
        case NSURLErrorNotConnectedToInternet:
            return "This iPhone is offline."
        default:
            return ns.localizedDescription
        }
    }

    private static func describeStatus(_ code: Int) -> String {
        switch code {
        case 502, 503, 504: return "The PC is not accepting requests right now (HTTP \(code))."
        default: return "The PC answered HTTP \(code)."
        }
    }

    /// Escape everything that is not unreserved, so `+`, spaces and `#` in file
    /// names survive the round trip.
    private func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        if path.contains("\\") { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
}
