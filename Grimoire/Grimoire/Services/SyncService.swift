import Foundation

struct SyncEntry: Codable, Equatable {
    /// Server "last modified" stamp seen at the last sync (nil forces a re-check next time).
    var remoteStamp: Date?
    /// The note's modified date as of the last sync.
    var syncedModified: Date
}

struct SyncSummary {
    var pushed = 0
    var pulled = 0
    var removed = 0
    var failed = 0
    var firstError: String?

    var text: String {
        var s = "\(pushed) sent · \(pulled) received · \(removed) removed"
        if failed > 0 {
            s += " · \(failed) failed"
        }
        return s
    }
}

/// Two-way sync of notes with a WebDAV folder.
///
/// Rules:
/// - Each note is `<uuid>.md` with a front-matter header; newest `modified` date wins.
/// - Deletes are propagated only through tombstones (`_tombstones.json`). A tombstone only deletes a note
///   when it is newer than every known edit of that note; otherwise the note is kept and the tombstone dropped.
/// - A note missing remotely without a tombstone is re-uploaded, and one missing locally without a tombstone
///   is downloaded. Unreadable remote files are skipped, never overwritten.
@MainActor
final class SyncService: ObservableObject {
    enum State: Equatable {
        case idle
        case syncing
        case success(Date)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var summaryText: String = ""
    @Published private(set) var lastSyncDate: Date?

    private var entries: [String: SyncEntry] = [:]
    private let stateURL: URL
    private static let tombstoneName = "_tombstones.json"

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("Grimoire", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.stateURL = root.appendingPathComponent("sync_state.json")
        self.lastSyncDate = UserDefaults.standard.object(forKey: "grimoire.lastSyncDate") as? Date
        if let data = try? Data(contentsOf: stateURL),
           let decoded = try? Coders.decoder.decode([String: SyncEntry].self, from: data) {
            self.entries = decoded
        }
    }

    /// Forgets what was previously synced so the next run re-compares every note.
    func resetState() {
        entries = [:]
        saveEntries()
        summaryText = ""
    }

    func sync(store: NoteStore, settings: SyncSettings) async {
        if state == .syncing { return }
        guard let config = settings.configuration else {
            state = .failed("Set up your NAS connection in Settings first.")
            return
        }

        state = .syncing
        do {
            let summary = try await run(store: store, config: config)
            summaryText = summary.text
            let now = Date()
            lastSyncDate = now
            UserDefaults.standard.set(now, forKey: "grimoire.lastSyncDate")
            if summary.failed > 0 {
                let detail = summary.firstError ?? "unknown error"
                state = .failed("\(summary.failed) note(s) could not sync: \(detail)")
            } else {
                state = .success(now)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
        saveEntries()
    }

    // MARK: Engine

    private func run(store: NoteStore, config: WebDAVConfig) async throws -> SyncSummary {
        let dav = NotesWebDAV(config: config)
        var summary = SyncSummary()

        try await dav.ensureFolder()
        let items = try await dav.list()

        var remote: [UUID: RemoteItem] = [:]
        var hasTombstoneFile = false
        for item in items where !item.isDirectory {
            if item.name == SyncService.tombstoneName {
                hasTombstoneFile = true
                continue
            }
            guard item.name.lowercased().hasSuffix(".md") else { continue }
            let base = String(item.name.dropLast(3))
            if let id = UUID(uuidString: base) {
                remote[id] = item
            }
        }

        // Tombstones from the NAS merged with local ones (latest deletion date wins).
        var remoteTombstones: [UUID: Date] = [:]
        if hasTombstoneFile {
            if let data = try await dav.get(SyncService.tombstoneName),
               let decoded = try? Coders.decoder.decode([Tombstone].self, from: data) {
                for t in decoded {
                    let existing = remoteTombstones[t.id] ?? t.deletedAt
                    remoteTombstones[t.id] = max(existing, t.deletedAt)
                }
            }
        }
        var merged = remoteTombstones
        for t in store.tombstones {
            let existing = merged[t.id] ?? t.deletedAt
            merged[t.id] = max(existing, t.deletedAt)
        }

        var locals: [UUID: Note] = [:]
        for n in store.notes {
            locals[n.id] = n
        }
        var ids = Set(locals.keys)
        for key in remote.keys {
            ids.insert(key)
        }

        for id in ids {
            let key = id.uuidString
            let local = locals[id]
            let remoteItem = remote[id]
            let tomb = merged[id]

            do {
                if let l = local, let r = remoteItem {
                    // Present on both sides.
                    var remoteNote: Note? = nil
                    let remoteModified: Date
                    if let entry = entries[key], let known = entry.remoteStamp, let stamp = r.modified, known == stamp {
                        remoteModified = entry.syncedModified
                    } else {
                        let fetched = try await fetch(dav, r)
                        guard let parsed = fetched else {
                            summary.failed += 1
                            if summary.firstError == nil { summary.firstError = "Could not read \(r.name)" }
                            continue
                        }
                        remoteNote = parsed
                        remoteModified = parsed.modifiedAt
                    }

                    let newest = max(l.modifiedAt, remoteModified)
                    if let t = tomb {
                        if t > newest {
                            try await dav.delete(r.name)
                            store.removeNote(id)
                            entries[key] = nil
                            summary.removed += 1
                            continue
                        } else {
                            merged[id] = nil
                        }
                    }

                    if remoteModified > l.modifiedAt {
                        var incoming = remoteNote
                        if incoming == nil {
                            incoming = try await fetch(dav, r)
                        }
                        guard let rn = incoming else {
                            summary.failed += 1
                            if summary.firstError == nil { summary.firstError = "Could not read \(r.name)" }
                            continue
                        }
                        // Skip if the note was edited while we were talking to the server.
                        if let current = store.note(id), current.modifiedAt == l.modifiedAt {
                            store.applyRemote(rn)
                            entries[key] = SyncEntry(remoteStamp: r.modified, syncedModified: rn.modifiedAt)
                            summary.pulled += 1
                        }
                    } else if l.modifiedAt > remoteModified {
                        try await upload(dav, l)
                        entries[key] = SyncEntry(remoteStamp: nil, syncedModified: l.modifiedAt)
                        summary.pushed += 1
                    } else if let rn = remoteNote {
                        entries[key] = SyncEntry(remoteStamp: r.modified, syncedModified: rn.modifiedAt)
                    }
                } else if let r = remoteItem {
                    // Only on the NAS.
                    let fetched = try await fetch(dav, r)
                    guard let rn = fetched else {
                        summary.failed += 1
                        if summary.firstError == nil { summary.firstError = "Could not read \(r.name)" }
                        continue
                    }
                    if let t = tomb, t >= rn.modifiedAt {
                        try await dav.delete(r.name)
                        entries[key] = nil
                        summary.removed += 1
                    } else {
                        if tomb != nil { merged[id] = nil }
                        store.applyRemote(rn)
                        entries[key] = SyncEntry(remoteStamp: r.modified, syncedModified: rn.modifiedAt)
                        summary.pulled += 1
                    }
                } else if let l = local {
                    // Only on this device.
                    if let t = tomb, t > l.modifiedAt {
                        store.removeNote(id)
                        entries[key] = nil
                        summary.removed += 1
                    } else {
                        if tomb != nil { merged[id] = nil }
                        try await upload(dav, l)
                        entries[key] = SyncEntry(remoteStamp: nil, syncedModified: l.modifiedAt)
                        summary.pushed += 1
                    }
                }
            } catch {
                summary.failed += 1
                if summary.firstError == nil {
                    summary.firstError = error.localizedDescription
                }
            }
        }

        // Drop very old tombstones whose note no longer exists on the NAS.
        let cutoff = Date().addingTimeInterval(-180 * 24 * 3600)
        var stale: [UUID] = []
        for (id, date) in merged where date < cutoff && remote[id] == nil {
            stale.append(id)
        }
        for id in stale {
            merged[id] = nil
        }

        var finalList: [Tombstone] = []
        for (id, date) in merged {
            finalList.append(Tombstone(id: id, deletedAt: date))
        }
        finalList.sort(by: { $0.deletedAt < $1.deletedAt })
        store.setTombstones(finalList)

        if merged != remoteTombstones {
            do {
                let data = try Coders.encoder.encode(finalList)
                try await dav.put(SyncService.tombstoneName, data: data)
            } catch {
                summary.failed += 1
                if summary.firstError == nil {
                    summary.firstError = "Could not save deletions: " + error.localizedDescription
                }
            }
        }

        return summary
    }

    private func fetch(_ dav: NotesWebDAV, _ item: RemoteItem) async throws -> Note? {
        guard let data = try await dav.get(item.name) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let base = String(item.name.dropLast(3))
        guard let id = UUID(uuidString: base) else { return nil }
        return NoteMarkdown.parse(text, id: id, fallbackDate: item.modified)
    }

    private func upload(_ dav: NotesWebDAV, _ note: Note) async throws {
        let data = Data(NoteMarkdown.serialize(note).utf8)
        try await dav.put(note.id.uuidString + ".md", data: data)
    }

    private func saveEntries() {
        guard let data = try? Coders.encoder.encode(entries) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
