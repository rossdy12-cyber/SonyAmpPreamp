import Foundation

/// WebDAV connection settings. The password lives in the Keychain; everything else in UserDefaults.
final class SyncSettings: ObservableObject {
    private static let passwordAccount = "webdav-password"

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "grimoire.serverURL") }
    }
    @Published var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "grimoire.username") }
    }
    @Published var remoteFolder: String {
        didSet { UserDefaults.standard.set(remoteFolder, forKey: "grimoire.remoteFolder") }
    }
    @Published var autoSync: Bool {
        didSet { UserDefaults.standard.set(autoSync, forKey: "grimoire.autoSync") }
    }
    @Published var password: String {
        didSet {
            if password.isEmpty {
                KeychainStore.delete(account: SyncSettings.passwordAccount)
            } else {
                KeychainStore.save(password, account: SyncSettings.passwordAccount)
            }
        }
    }

    init() {
        let defaults = UserDefaults.standard
        self.serverURL = defaults.string(forKey: "grimoire.serverURL") ?? ""
        self.username = defaults.string(forKey: "grimoire.username") ?? ""
        self.remoteFolder = defaults.string(forKey: "grimoire.remoteFolder") ?? "Grimoire"
        self.autoSync = defaults.object(forKey: "grimoire.autoSync") as? Bool ?? true
        self.password = KeychainStore.load(account: SyncSettings.passwordAccount) ?? ""
    }

    var configuration: WebDAVConfig? {
        let url = serverURL.trimmed
        guard !url.isEmpty, URL(string: url) != nil else { return nil }
        guard !username.trimmed.isEmpty else { return nil }
        return WebDAVConfig(
            baseURL: url,
            username: username.trimmed,
            password: password,
            folder: remoteFolder.trimmed.isEmpty ? "Grimoire" : remoteFolder
        )
    }

    var isConfigured: Bool {
        configuration != nil
    }
}
