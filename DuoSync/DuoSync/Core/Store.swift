import Foundation
import SwiftUI

/// Everything the app remembers: which PCs and folders are paired, the baseline
/// for each pair, the ignore list and the activity log.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var machines: [Machine] = []
    @Published private(set) var pairs: [Pair] = []
    @Published var ignorePatterns: [String] = Ignore.defaults
    @Published var backgroundSync: Bool = true
    @Published private(set) var logLines: [String] = []
    @Published var lastMessage: String?

    private let fileManager = FileManager.default
    private let settingsFile: URL
    private let stateDirectory: URL
    private let logFile: URL

    static let documents: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    static let syncRoot: URL = documents.appendingPathComponent("Sync", isDirectory: true)

    init() {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? Store.documents
        let base = support.appendingPathComponent("DuoSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        settingsFile = base.appendingPathComponent("settings.json")
        stateDirectory = base.appendingPathComponent("state", isDirectory: true)
        logFile = base.appendingPathComponent("activity.log")
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Store.syncRoot, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = Store.syncRoot
        try? mutableRoot.setResourceValues(values)
        load()
    }

    // MARK: - Persisted settings

    private struct SettingsFile: Codable {
        var machines: [Machine]
        var pairs: [Pair]
        var ignorePatterns: [String]
        var backgroundSync: Bool
    }

    private func load() {
        guard let data = try? Data(contentsOf: settingsFile),
              let decoded = try? JSONDecoder().decode(SettingsFile.self, from: data) else {
            appendLog("DuoSync started")
            return
        }
        machines = decoded.machines
        pairs = decoded.pairs
        ignorePatterns = decoded.ignorePatterns
        backgroundSync = decoded.backgroundSync
        appendLog("DuoSync started")
    }

    func save() {
        let payload = SettingsFile(
            machines: machines,
            pairs: pairs,
            ignorePatterns: ignorePatterns,
            backgroundSync: backgroundSync
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let temp = settingsFile.appendingPathExtension("tmp")
        try? data.write(to: temp, options: .atomic)
        try? fileManager.removeItem(at: settingsFile)
        try? fileManager.moveItem(at: temp, to: settingsFile)
    }

    // MARK: - Machines

    func token(for machineID: UUID) -> String {
        Keychain.read(account: "machine.\(machineID.uuidString)") ?? ""
    }

    func setToken(_ token: String, for machineID: UUID) {
        Keychain.save(token, account: "machine.\(machineID.uuidString)")
    }

    func machine(id: UUID) -> Machine? {
        machines.first { $0.id == id }
    }

    @discardableResult
    func upsertMachine(name: String, address: String, port: Int, hostID: String?, token: String) -> Machine {
        if let index = machines.firstIndex(where: { $0.hostID == hostID && hostID != nil }) {
            machines[index].name = name
            machines[index].address = address
            machines[index].port = port
            machines[index].lastSeen = Date()
            setToken(token, for: machines[index].id)
            save()
            return machines[index]
        }
        let machine = Machine(
            id: UUID(),
            name: name,
            address: address,
            port: port,
            lastSeen: Date(),
            hostID: hostID
        )
        machines.append(machine)
        setToken(token, for: machine.id)
        save()
        return machine
    }

    func markSeen(_ machineID: UUID) {
        guard let index = machines.firstIndex(where: { $0.id == machineID }) else { return }
        machines[index].lastSeen = Date()
    }

    func removeMachine(_ machineID: UUID) {
        for pair in pairs where pair.machineId == machineID {
            try? fileManager.removeItem(at: stateFile(for: pair))
        }
        pairs.removeAll { $0.machineId == machineID }
        Keychain.delete(account: "machine.\(machineID.uuidString)")
        machines.removeAll { $0.id == machineID }
        save()
    }

    // MARK: - Pairs

    func pairs(for machineID: UUID) -> [Pair] {
        pairs.filter { $0.machineId == machineID }
    }

    func pair(id: UUID) -> Pair? {
        pairs.first { $0.id == id }
    }

    @discardableResult
    func addPair(machineID: UUID, share: ShareInfo, mode: SyncMode = .twoWay) -> Pair {
        if let existing = pairs.first(where: { $0.machineId == machineID && $0.shareId == share.id }) {
            return existing
        }
        let pair = Pair(
            machineId: machineID,
            shareId: share.id,
            shareName: share.name,
            folderName: uniqueFolderName(share.name),
            mode: mode,
            remoteReadOnly: !share.isWritable
        )
        pairs.append(pair)
        createFolderIfNeeded(pair)
        save()
        return pair
    }

    func updatePair(_ pair: Pair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index] = pair
        save()
    }

    func mutatePair(id: UUID, _ mutate: (inout Pair) -> Void) {
        guard let index = pairs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&pairs[index])
        save()
    }

    func removePair(_ pairID: UUID) {
        guard let pair = pairs.first(where: { $0.id == pairID }) else { return }
        try? fileManager.removeItem(at: stateFile(for: pair))
        pairs.removeAll { $0.id == pairID }
        save()
    }

    /// Forget the merge baseline, so the next run re-baselines instead of
    /// propagating deletions.
    func resetBaseline(for pair: Pair) {
        try? fileManager.removeItem(at: stateFile(for: pair))
    }

    // MARK: - Pair state

    func stateFile(for pair: Pair) -> URL {
        stateDirectory.appendingPathComponent("\(pair.id.uuidString).json")
    }

    func loadState(for pair: Pair) -> PairState {
        guard let data = try? Data(contentsOf: stateFile(for: pair)),
              let state = try? JSONDecoder().decode(PairState.self, from: data) else {
            return PairState()
        }
        return state
    }

    func saveState(_ state: PairState, for pair: Pair) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateFile(for: pair), options: .atomic)
    }

    // MARK: - Folders

    func folderURL(for pair: Pair) -> URL {
        Self.syncRoot.appendingPathComponent(pair.folderName, isDirectory: true)
    }

    func createFolderIfNeeded(_ pair: Pair) {
        try? fileManager.createDirectory(at: folderURL(for: pair), withIntermediateDirectories: true)
    }

    private func uniqueFolderName(_ wanted: String) -> String {
        let base = Store.sanitise(wanted)
        var candidate = base
        var counter = 2
        let taken = Set(pairs.map(\.folderName))
        while taken.contains(candidate) {
            candidate = "\(base) (\(counter))"
            counter += 1
        }
        return candidate
    }

    static func sanitise(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Folder" : String(cleaned.prefix(64))
    }

    /// Short message for the toast overlay.
    func notify(_ message: String) {
        lastMessage = message
    }

    // MARK: - Log

    func appendLog(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(stamp)] \(line)"
        logLines.append(entry)
        if logLines.count > 400 { logLines.removeFirst(logLines.count - 400) }
        if let data = (entry + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    func clearLog() {
        logLines.removeAll()
        try? fileManager.removeItem(at: logFile)
    }
}
