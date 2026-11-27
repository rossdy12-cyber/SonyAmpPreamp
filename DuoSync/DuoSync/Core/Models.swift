import Foundation

// MARK: - Persisted model

struct Machine: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var address: String
    var port: Int
    var lastSeen: Date?
    var hostID: String?

    var baseURL: URL? {
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        guard !host.isEmpty else { return nil }
        var portPart = port
        var hostPart = host
        if let colon = host.lastIndex(of: ":"), let explicit = Int(host[host.index(after: colon)...]) {
            portPart = explicit
            hostPart = String(host[..<colon])
        }
        guard !hostPart.isEmpty else { return nil }
        return URL(string: "http://\(hostPart):\(portPart)")
    }

    var displayAddress: String {
        "\(address):\(port)"
    }
}

enum SyncMode: String, Codable, CaseIterable, Identifiable {
    case twoWay = "two-way"
    case push = "push"
    case pull = "pull"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .twoWay: return "Two-way"
        case .push: return "Send only"
        case .pull: return "Receive only"
        }
    }

    var detail: String {
        switch self {
        case .twoWay: return "Both sides propagate; conflicts keep both copies."
        case .push: return "This iPhone wins. Remote edits are overwritten."
        case .pull: return "The PC wins. Edits made here are overwritten."
        }
    }
}

struct Pair: Codable, Identifiable, Hashable {
    var id: UUID
    var machineId: UUID
    var shareId: String
    var shareName: String
    var folderName: String
    var mode: SyncMode
    var enabled: Bool
    var lastSync: Date?
    var lastSummary: String?
    var lastError: String?
    var remoteReadOnly: Bool

    init(
        id: UUID = UUID(),
        machineId: UUID,
        shareId: String,
        shareName: String,
        folderName: String,
        mode: SyncMode = .twoWay,
        enabled: Bool = true,
        lastSync: Date? = nil,
        lastSummary: String? = nil,
        lastError: String? = nil,
        remoteReadOnly: Bool = false
    ) {
        self.id = id
        self.machineId = machineId
        self.shareId = shareId
        self.shareName = shareName
        self.folderName = folderName
        self.mode = mode
        self.enabled = enabled
        self.lastSync = lastSync
        self.lastSummary = lastSummary
        self.lastError = lastError
        self.remoteReadOnly = remoteReadOnly
    }
}

// MARK: - Sync state

struct CachedHash: Codable {
    var size: Int64
    var mtime: Int64
    var hash: String
}

struct PairState: Codable {
    var base: [String: String] = [:]
    var hashes: [String: CachedHash] = [:]
    var lastSync: Date?
}

struct FileEntry: Hashable, Sendable {
    var hash: String
    var size: Int64
    var mtime: Int64
}

struct SyncSummary: Sendable {
    var pulled = 0
    var pushed = 0
    var deletedLocal = 0
    var deletedRemote = 0
    var conflicts = 0
    var failures: [String] = []
    var warnings: [String] = []
    var ops = 0

    var ok: Bool { failures.isEmpty }

    var sentence: String {
        if !ok { return failures.first ?? "Sync failed" }
        var bits: [String] = []
        if pulled > 0 { bits.append("\(pulled) downloaded") }
        if pushed > 0 { bits.append("\(pushed) uploaded") }
        if deletedLocal > 0 { bits.append("\(deletedLocal) removed") }
        if conflicts > 0 { bits.append("\(conflicts) conflicted") }
        return bits.isEmpty ? "Up to date" : bits.joined(separator: ", ")
    }
}

// MARK: - Protocol wire types

struct HostInfo: Decodable, Sendable {
    struct Details: Decodable, Sendable {
        let id: String
        let name: String
        let port: Int?
    }
    let ok: Bool?
    let host: Details
    let shares: [ShareInfo]?
    let proto: Int?

    enum CodingKeys: String, CodingKey {
        case ok, host, shares
        case proto = "protocol"
    }
}

struct ShareInfo: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let mode: String?

    var isWritable: Bool { (mode ?? "rw") == "rw" }
}

struct RemoteManifest: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let p: String
        let h: String
        let s: Int64
        let m: Int64
    }
    let files: [Entry]
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case notConfigured
    case badAddress
    case unauthorized
    case readOnly
    case missing(String)
    case http(Int, String)
    case transport(String)
    case checksum(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add a machine first."
        case .badAddress: return "The machine address looks wrong."
        case .unauthorized: return "The token was rejected. Copy it again from the PC."
        case .readOnly: return "That folder is shared read-only on the PC."
        case .missing(let path): return "\(path) is no longer on the PC."
        case .http(let code, let message): return message.isEmpty ? "The PC answered HTTP \(code)." : message
        case .transport(let message): return message
        case .checksum(let path): return "\(path) arrived damaged, will retry."
        }
    }
}
