import Foundation

/// One step of a merge plan. The Windows app plans with the same rules and the
/// same ordering, so both sides converge on an identical file set.
enum SyncOp: Sendable {
    case rebase(path: String, hash: String)
    case recycle(path: String, to: String)
    case saveFromRemote(path: String, to: String, loserHash: String)
    case pull(path: String, remote: FileEntry)
    case push(path: String, hash: String)
    case pushConflict(path: String, hash: String)
    case deleteRemote(path: String)
    case deleteLocal(path: String)

    var rank: Int {
        switch self {
        case .rebase: return 5
        case .recycle: return 10
        case .saveFromRemote: return 20
        case .pull: return 30
        case .push: return 40
        case .pushConflict: return 41
        case .deleteRemote: return 50
        case .deleteLocal: return 60
        }
    }

    var path: String {
        switch self {
        case .rebase(let path, _): return path
        case .recycle(let path, _): return path
        case .saveFromRemote(let path, _, _): return path
        case .pull(let path, _): return path
        case .push(let path, _): return path
        case .pushConflict(let path, _): return path
        case .deleteRemote(let path): return path
        case .deleteLocal(let path): return path
        }
    }

    /// How this step moves the agreed baseline. `nil` hash means "no longer there".
    var baseUpdates: [(path: String, hash: String?)] {
        switch self {
        case .rebase(let path, let hash):
            return [(path, hash)]
        case .recycle:
            return []
        case .saveFromRemote(_, let to, let loserHash):
            return [(to, loserHash)]
        case .pull(let path, let remote):
            return [(path, remote.hash)]
        case .push(let path, let hash), .pushConflict(let path, let hash):
            return [(path, hash)]
        case .deleteRemote(let path), .deleteLocal(let path):
            return [(path, nil)]
        }
    }
}

enum Engine {
    /// Plan one pair.
    /// - base: path -> hash both sides had agreed on at the end of the last sync.
    static func plan(
        local: [String: FileEntry],
        remote: [String: FileEntry],
        base: [String: String],
        mode: SyncMode
    ) -> (ops: [SyncOp], base: [String: String]) {
        switch mode {
        case .push: return planOneWay(local: local, remote: remote, base: base, localIsSource: true)
        case .pull: return planOneWay(local: local, remote: remote, base: base, localIsSource: false)
        case .twoWay: return planTwoWay(local: local, remote: remote, base: base)
        }
    }

    static func committed(base: [String: String], ops: [SyncOp]) -> [String: String] {
        var next = base
        for op in ops {
            for update in op.baseUpdates {
                if let hash = update.hash {
                    next[update.path] = hash
                } else {
                    next.removeValue(forKey: update.path)
                }
            }
        }
        return next
    }

    private static func ordered(_ ops: [SyncOp]) -> [SyncOp] {
        ops.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.path < rhs.path
        }
    }

    private static func planTwoWay(
        local: [String: FileEntry],
        remote: [String: FileEntry],
        base: [String: String]
    ) -> (ops: [SyncOp], base: [String: String]) {
        var ops: [SyncOp] = []
        let paths = Set(local.keys).union(remote.keys).union(base.keys).sorted()

        for path in paths {
            let localEntry = local[path]
            let remoteEntry = remote[path]
            let localHash = localEntry?.hash
            let remoteHash = remoteEntry?.hash
            let baseHash = base[path]

            // Already identical. Record the agreement so a stale baseline cannot
            // make the next run look like a change on both sides.
            if localHash == remoteHash {
                if let localHash, baseHash != localHash {
                    ops.append(.rebase(path: path, hash: localHash))
                }
                continue
            }

            let localChanged = localHash != baseHash
            let remoteChanged = remoteHash != baseHash

            if !localChanged && remoteChanged {
                if let remoteEntry {
                    ops.append(.pull(path: path, remote: remoteEntry))
                } else {
                    ops.append(.deleteLocal(path: path))
                }
                continue
            }

            if localChanged && !remoteChanged {
                if let localHash {
                    ops.append(.push(path: path, hash: localHash))
                } else {
                    ops.append(.deleteRemote(path: path))
                }
                continue
            }

            // Both sides moved away from the baseline, and they disagree.
            if localHash == nil, let remoteEntry {
                // Deleted here, edited there: an edit beats a deletion.
                ops.append(.pull(path: path, remote: remoteEntry))
                continue
            }
            if remoteHash == nil, let localEntry {
                ops.append(.push(path: path, hash: localEntry.hash))
                continue
            }

            guard let localHash, let remoteHash, let remoteEntry else { continue }

            // True conflict: the higher hash keeps the real name, the loser is
            // stashed beside it under a name both sides compute identically.
            let localWins = localHash > remoteHash
            let winner = localWins ? localHash : remoteHash
            let loser = localWins ? remoteHash : localHash
            let conflict = conflictName(path, hash: loser)

            if localWins {
                ops.append(.saveFromRemote(path: path, to: conflict, loserHash: loser))
                ops.append(.push(path: path, hash: winner))
            } else {
                ops.append(.recycle(path: path, to: conflict))
                ops.append(.pull(path: path, remote: remoteEntry))
                ops.append(.pushConflict(path: conflict, hash: loser))
            }
        }

        let sorted = ordered(ops)
        return (sorted, committed(base: base, ops: sorted))
    }

    private static func planOneWay(
        local: [String: FileEntry],
        remote: [String: FileEntry],
        base: [String: String],
        localIsSource: Bool
    ) -> (ops: [SyncOp], base: [String: String]) {
        var ops: [SyncOp] = []
        let paths = Set(local.keys).union(remote.keys).union(base.keys).sorted()

        for path in paths {
            let localHash = local[path]?.hash
            let remoteHash = remote[path]?.hash
            let baseHash = base[path]

            if localHash == remoteHash {
                if let localHash, baseHash != localHash {
                    ops.append(.rebase(path: path, hash: localHash))
                }
                continue
            }

            if localIsSource {
                if localHash == baseHash { continue }
                if let localHash {
                    ops.append(.push(path: path, hash: localHash))
                } else {
                    ops.append(.deleteRemote(path: path))
                }
            } else {
                if remoteHash == baseHash { continue }
                if let remoteEntry = remote[path] {
                    ops.append(.pull(path: path, remote: remoteEntry))
                } else {
                    ops.append(.deleteLocal(path: path))
                }
            }
        }

        let sorted = ordered(ops)
        return (sorted, committed(base: base, ops: sorted))
    }

    /// `a/b/name.ext` -> `a/b/name (conflict 1a2b3c4d).ext`
    static func conflictName(_ path: String, hash: String) -> String {
        let ns = path as NSString
        let dir = ns.deletingLastPathComponent
        let base = ns.lastPathComponent as NSString
        let ext = base.pathExtension
        let stem = base.deletingPathExtension
        let short = String(hash.prefix(8))
        let name = ext.isEmpty ? "\(stem) (conflict \(short))" : "\(stem) (conflict \(short)).\(ext)"
        return (dir.isEmpty || dir == ".") ? name : "\(dir)/\(name)"
    }
}
