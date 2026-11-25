import Foundation
import Security

struct BridgeFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Keychain {
    private static let service = "com.ross.forgelink.bridge"
    static func load() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "pairing-token",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "pairing-token"]
        if token.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw BridgeFailure(message: "Could not clear the saved pairing token.") }
            return
        }
        let data = Data(token.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw BridgeFailure(message: "Could not update the pairing token in Keychain.") }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw BridgeFailure(message: "Could not save the pairing token in Keychain.") }
    }
}

final class BridgeClient {
    private let baseURL: URL
    private let token: String
    private let session: URLSession
    init(settings: ConnectionSettings) throws {
        let input = settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: input), let url = components.url,
              let host = components.host, !host.isEmpty,
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw BridgeFailure(message: "Enter a bridge address such as https://forge.your-domain.com (without credentials or query parameters).")
        }
        guard settings.token.count >= 32 else { throw BridgeFailure(message: "Enter the full pairing token from your bridge’s .env file.") }
        baseURL = url
        token = settings.token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }
    func request<T: Decodable>(_ route: String, method: String = "GET", body: RunRequest? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(route))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BridgeFailure(message: "The bridge returned an invalid response.") }
        guard (200..<300).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(APIError.self, from: data)
            throw BridgeFailure(message: failure?.error ?? "Bridge returned HTTP \(response.statusCode). Check the address and reverse proxy.")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw BridgeFailure(message: "Unexpected bridge response. Check that the app and bridge versions match.") }
    }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
