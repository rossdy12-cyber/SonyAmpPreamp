import Foundation
import SwiftUI

/// Runs the merge for one pair. Deliberately not main-actor isolated: hashing and
/// transfers happen off the main thread.
struct SyncRunner {
    let machine: Machine
    let token: String
    let pair: Pair
    let root: URL
    let isIgnored: (String, String) -> Bool
    let state: PairState
    let pruneEmptyFolders: Bool

    func run() async throws -> (summary: SyncSummary, state: PairState) {
        guard let baseURL = machine.baseURL else { throw SyncError.badAddress }
        let client = DuoSyncClient(baseURL: baseURL, token: token)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var summary = SyncSummary()

        // 1. What is on this phone.
        let scan = FolderScanner(root: root, isIgnored: isIgnored, cache: state.hashes).scan()
        summary.warnings = scan.problems

        // 2. What the PC reports.
        let remote = try await client.manifest(shareId: pair.shareId)

        // 3. Refuse to mirror an empty folder over a populated one.
        if remote.isEmpty && !scan.files.isEmpty && !state.base.isEmpty {
            throw SyncError.http(409, "The PC reported an empty folder — skipping deletions this round.")
        }
        if pair.mode == .push && pair.remoteReadOnly {
            throw SyncError.readOnly
        }

        // 4. Plan the merge.
        let planned = Engine.plan(local: scan.files, remote: remote, base: state.base, mode: pair.mode)
        summary.ops = planned.ops.reduce(into: 0) { total, op in
            if case .rebase = op { return }
            total += 1
        }

        // 5. Execute in order. Only steps that actually happened move the baseline,
        //    so a failure is retried next round instead of being assumed done.
        var localFiles = scan.files
        var cache = scan.cache
        var applied: [SyncOp] = []
        for op in planned.ops {
            do {
                try await apply(op, client: client, localFiles: &localFiles, cache: &cache, summary: &summary)
                applied.append(op)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                summary.failures.append("\(op.path): \(message)")
            }
        }

        // 6. Remove folders the deletions left empty.
        if pruneEmptyFolders && (summary.deletedLocal > 0 || summary.deletedRemote > 0) {
            Pruner.pruneEmptyFolders(in: root, isIgnored: isIgnored)
        }

        // 7. Persist only what is still on disk.
        let liveKeys = Set(localFiles.keys)
        let trimmedCache = cache.filter { liveKeys.contains($0.key) }

        var next = PairState()
        next.base = Engine.committed(base: state.base, ops: applied)
        next.hashes = trimmedCache
        next.lastSync = Date()
        return (summary, next)
    }

    private func apply(
        _ op: SyncOp,
        client: DuoSyncClient,
        localFiles: inout [String: FileEntry],
        cache: inout [String: CachedHash],
        summary: inout SyncSummary
    ) async throws {
        switch op {
        case .rebase:
            return

        case .recycle(let path, let to):
            let source = localURL(path)
            let destination = localURL(to)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: source, to: destination)
            if let entry = localFiles.removeValue(forKey: path), cache[path] != nil {
                localFiles[to] = entry
                cache[to] = cache.removeValue(forKey: path)
            }
            summary.conflicts += 1

        case .saveFromRemote(let path, let to, _):
            let destination = localURL(to)
            try await client.download(
                shareId: pair.shareId,
                path: path,
                to: destination,
                expectedHash: nil,
                mtimeMs: 0
            )
            localFiles.removeValue(forKey: to)
            cache.removeValue(forKey: to)
            summary.conflicts += 1

        case .pull(let path, let remote):
            let destination = localURL(path)
            if let planned = localFiles[path] {
                // A file saved while the sync runs is retried next round rather
                // than silently overwritten.
                if let current = try? Hasher.sha256(of: destination).hash, current != planned.hash {
                    throw SyncError.http(409, "changed while syncing, will retry")
                }
            }
            try await client.download(
                shareId: pair.shareId,
                path: path,
                to: destination,
                expectedHash: remote.hash,
                mtimeMs: remote.mtime
            )
            localFiles[path] = remote
            cache[path] = CachedHash(size: remote.size, mtime: remote.mtime, hash: remote.hash)
            summary.pulled += 1

        case .push(let path, _), .pushConflict(let path, _):
            let source = localURL(path)
            let hashed = try Hasher.sha256(of: source)
            try await client.upload(
                shareId: pair.shareId,
                path: path,
                from: source,
                hash: hashed.hash,
                mtimeMs: hashed.mtime
            )
            if case .pushConflict = op { summary.conflicts += 1 } else { summary.pushed += 1 }

        case .deleteRemote(let path):
            try await client.delete(shareId: pair.shareId, path: path)
            summary.deletedRemote += 1

        case .deleteLocal(let path):
            let target = localURL(path)
            if let planned = localFiles[path],
               let current = try? Hasher.sha256(of: target).hash,
               current != planned.hash {
                throw SyncError.http(409, "changed while syncing, will retry")
            }
            try? FileManager.default.removeItem(at: target)
            localFiles.removeValue(forKey: path)
            cache.removeValue(forKey: path)
            summary.deletedLocal += 1
        }
    }

    private func localURL(_ relativePath: String) -> URL {
        var url = root
        for component in relativePath.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        return url
    }
}

@MainActor
final class SyncManager: ObservableObject {
    @Published private(set) var runningPairs: Set<UUID> = []
    @Published private(set) var isSyncingAll = false

    private let store: Store
    private var lastAutomaticRun = Date.distantPast

    init(store: Store) {
        self.store = store
    }

    var isBusy: Bool { !runningPairs.isEmpty || isSyncingAll }

    func isRunning(_ pairID: UUID) -> Bool { runningPairs.contains(pairID) }

    func syncAll(silent: Bool = false) async {
        guard !isSyncingAll else { return }
        isSyncingAll = true
        defer { isSyncingAll = false }
        for pair in store.pairs where pair.enabled {
            await sync(pairID: pair.id, silent: true)
        }
        if !silent { store.notify("Checked every folder") }
    }

    /// Keeps the phone in step while the app is open, without hammering the PC.
    func syncIfStale() async {
        guard Date().timeIntervalSince(lastAutomaticRun) > 12 else { return }
        lastAutomaticRun = Date()
        await syncAll(silent: true)
    }

    @discardableResult
    func sync(pairID: UUID, silent: Bool = false) async -> SyncSummary? {
        guard !runningPairs.contains(pairID) else { return nil }
        guard let pair = store.pair(id: pairID),
              let machine = store.machine(id: pair.machineId) else { return nil }

        runningPairs.insert(pairID)
        defer { runningPairs.remove(pairID) }

        let folder = store.folderURL(for: pair)
        store.createFolderIfNeeded(pair)
        let runner = SyncRunner(
            machine: machine,
            token: store.token(for: machine.id),
            pair: pair,
            root: folder,
            isIgnored: Ignore.matcher(store.ignorePatterns),
            state: store.loadState(for: pair),
            pruneEmptyFolders: true
        )

        do {
            let result = try await runner.run()
            store.saveState(result.state, for: pair)
            store.markSeen(machine.id)
            let summary = result.summary
            store.mutatePair(id: pair.id) { stored in
                stored.lastSync = Date()
                stored.lastSummary = summary.sentence
                stored.lastError = summary.ok ? nil : summary.failures.first
            }
            store.appendLog("\(machine.name) · \(pair.shareName): \(summary.sentence)")
            if !summary.ok, let first = summary.failures.first {
                store.appendLog("  ! \(first)")
            }
            return summary
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            store.mutatePair(id: pair.id) { stored in
                stored.lastError = message
                stored.lastSync = Date()
            }
            store.appendLog("\(machine.name) · \(pair.shareName): failed — \(message)")
            if !silent { store.notify(message) }
            return nil
        }
    }
}
