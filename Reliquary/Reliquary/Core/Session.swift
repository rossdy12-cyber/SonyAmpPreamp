import Foundation
import SwiftUI

@MainActor
final class Session: ObservableObject {
    private enum Keys {
        static let server = "reliquary.server.url"
        static let apiKey = "reliquary.apikey"
        static let user = "reliquary.user"
    }

    @Published private(set) var client: ImmichClient? = nil
    @Published var serverText: String
    @Published var userName: String?
    @Published var notice: String?

    init() {
        let saved = UserDefaults.standard.string(forKey: Keys.server) ?? ""
        serverText = saved
        userName = UserDefaults.standard.string(forKey: Keys.user)
        notice = nil
        if let url = ImmichClient.normalize(saved),
           let key = KeychainStore.load(account: Keys.apiKey),
           !key.isEmpty {
            client = ImmichClient(baseURL: url, apiKey: key)
        }
    }

    /// Validates the credentials against GET /api/users/me and, if they work, stores them.
    func connect(urlString: String, apiKey: String) async throws {
        guard let url = ImmichClient.normalize(urlString) else { throw ImmichError.invalidURL }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ImmichError.missingKey }

        let candidate = ImmichClient(baseURL: url, apiKey: key)
        let user = try await candidate.validate()

        UserDefaults.standard.set(url.absoluteString, forKey: Keys.server)
        UserDefaults.standard.set(user.displayName, forKey: Keys.user)
        KeychainStore.save(key, account: Keys.apiKey)

        serverText = url.absoluteString
        userName = user.displayName
        notice = nil
        client = candidate
    }

    /// Re-checks the stored key at launch. Only a definite 401 signs the user out.
    func refreshUser() async {
        guard let current = client else { return }
        do {
            let user = try await current.validate()
            userName = user.displayName
            UserDefaults.standard.set(user.displayName, forKey: Keys.user)
        } catch ImmichError.unauthorized {
            notice = "Your API key was rejected. Please connect again."
            logout()
        } catch {
            // Offline or server down: keep the session.
        }
    }

    func logout() {
        KeychainStore.delete(account: Keys.apiKey)
        UserDefaults.standard.removeObject(forKey: Keys.user)
        userName = nil
        client = nil
        ImageStore.shared.removeAll()
    }
}
