import Foundation

extension Notification.Name {
    /// Posted (from any thread) when the server says our token is no longer valid.
    static let tetherUnauthorized = Notification.Name("tetherUnauthorized")
}

// MARK: - Credentials

/// Where the server address and token live. Safe to read from any thread (background wake-ups use it).
enum Credentials {
    private static let defaults = UserDefaults.standard

    static let defaultServer = "https://navidrome.nas-server.co.uk/tether"

    /// A reinstall wipes UserDefaults but keeps the Keychain, so the address is kept in both. If the
    /// address is missing but a token is still saved, fall back to the standard address so the app
    /// does not end up signed in with nowhere to connect.
    static var serverURL: String {
        get {
            if let saved = defaults.string(forKey: "tether.server"), !saved.isEmpty { return saved }
            if let saved = KeychainStore.load(account: "server"), !saved.isEmpty { return saved }
            return token != nil ? defaultServer : ""
        }
        set {
            defaults.set(newValue, forKey: "tether.server")
            KeychainStore.save(newValue, account: "server")
        }
    }

    static var token: String? {
        get { KeychainStore.load(account: "token") }
        set {
            if let value = newValue {
                KeychainStore.save(value, account: "token")
            } else {
                KeychainStore.delete(account: "token")
            }
        }
    }

    /// True while the user has paused sharing.
    static var paused: Bool {
        get { defaults.bool(forKey: "tether.paused") }
        set { defaults.set(newValue, forKey: "tether.paused") }
    }

    /// The hex APNs device token, if iOS has given us one.
    static var apnsToken: String? {
        get { defaults.string(forKey: "tether.apns") }
        set { defaults.set(newValue, forKey: "tether.apns") }
    }

    /// Show local alerts for new events while the app wakes in the background.
    static var localAlerts: Bool {
        get { defaults.object(forKey: "tether.localAlerts") == nil ? true : defaults.bool(forKey: "tether.localAlerts") }
        set { defaults.set(newValue, forKey: "tether.localAlerts") }
    }

    static var api: APIClient? {
        guard let token = token, let base = APIClient.normalize(serverURL) else { return nil }
        return APIClient(base: base, token: token)
    }
}

// MARK: - Errors

enum APIError: Error, LocalizedError {
    case badURL
    case unauthorized
    case server(status: Int, code: String, message: String)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "That server address doesn't look right."
        case .unauthorized:
            return "You've been signed out. Join the circle again."
        case .server(_, _, let message):
            return message
        case .network(let text):
            return "Can't reach the server (\(text))."
        case .decoding:
            return "The server sent something Tether couldn't read."
        }
    }
}

// MARK: - Client

struct APIClient {
    let base: URL
    let token: String?

    init(base: URL, token: String?) {
        self.base = base
        self.token = token
    }

    /// Accepts "host", "host/tether", "https://host/tether/" and so on.
    static func normalize(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        if !value.contains("://") { value = "https://" + value }
        while value.hasSuffix("/") { value.removeLast() }
        guard let url = URL(string: value), url.host != nil else { return nil }
        return url
    }

    /// Encodes a plain dictionary as a JSON body.
    static func json(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [])
    }

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    func call<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [(String, String)] = [],
        json: Data? = nil,
        as type: T.Type,
        timeout: TimeInterval = 20
    ) async throws -> T {
        let data = try await raw(method, path, query: query, json: json, timeout: timeout)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    func raw(
        _ method: String,
        _ path: String,
        query: [(String, String)] = [],
        json: Data? = nil,
        timeout: TimeInterval = 20
    ) async throws -> Data {
        guard var comps = URLComponents(string: base.absoluteString + path) else { throw APIError.badURL }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = comps.url else { throw APIError.badURL }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json = json {
            request.httpBody = json
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        guard let http = result.1 as? HTTPURLResponse else {
            throw APIError.network("no response")
        }
        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        if http.statusCode >= 400 {
            var code = "error"
            var message = "The server returned an error (\(http.statusCode))."
            if let object = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any] {
                if let c = object["error"] as? String { code = c }
                if let m = object["message"] as? String { message = m }
            }
            if http.statusCode == 429 && message.hasPrefix("The server returned") {
                message = "Too many attempts. Wait a bit and try again."
            }
            throw APIError.server(status: http.statusCode, code: code, message: message)
        }
        return result.0
    }
}
