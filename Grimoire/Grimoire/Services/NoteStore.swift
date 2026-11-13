import Foundation

/// Local persistence: one JSON file per note in Documents/Grimoire/Notes plus a tombstone list.
/// Deliberately not main-actor isolated; it is only ever called from the main thread.
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var tombstones: [Tombstone] = []

    private let notesDir: URL
    private let tombstoneURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("Grimoire", isDirectory: true)
        let dir = root.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.notesDir = dir
        self.tombstoneURL = root.appendingPathComponent("tombstones.json")
        load()
    }

    // MARK: Queries

    func note(_ id: UUID) -> Note? {
        notes.first(where: { $0.id == id })
    }

    var folders: [String] {
        var set = Set<String>()
        for n in notes where !n.folder.isEmpty {
            set.insert(n.folder)
        }
        return set.sorted()
    }

    var allTags: [String] {
        var set = Set<String>()
        for n in notes {
            for t in n.tags {
                set.insert(t)
            }
        }
        return set.sorted()
    }

    // MARK: Mutations

    @discardableResult
    func createNote(folder: String = "") -> Note {
        let n = Note(folder: folder)
        notes.append(n)
        persist(n)
        return n
    }

    /// Saves edits to an existing note. Unknown ids are ignored so a deleted note is never resurrected.
    func update(_ note: Note, touch: Bool = true) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = note
        if touch {
            updated.modifiedAt = Date().wholeSeconds
        }
        notes[index] = updated
        persist(updated)
    }

    /// User-initiated delete: removes the note and records a tombstone so sync can propagate it.
    func delete(_ id: UUID) {
        removeNote(id)
        tombstones.removeAll(where: { $0.id == id })
        tombstones.append(Tombstone(id: id, deletedAt: Date().wholeSeconds))
        saveTombstones()
    }

    /// Removes a note without recording a tombstone (discarding blanks, or applying a remote delete).
    func removeNote(_ id: UUID) {
        notes.removeAll(where: { $0.id == id })
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    /// Inserts or replaces a note received from the NAS, keeping its modified date untouched.
    func applyRemote(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.append(note)
        }
        persist(note)
        if tombstones.contains(where: { $0.id == note.id }) {
            tombstones.removeAll(where: { $0.id == note.id })
            saveTombstones()
        }
    }

    func setTombstones(_ list: [Tombstone]) {
        tombstones = list
        saveTombstones()
    }

    // MARK: Disk

    private func fileURL(_ id: UUID) -> URL {
        notesDir.appendingPathComponent(id.uuidString + ".json")
    }

    private func persist(_ note: Note) {
        guard let data = try? Coders.encoder.encode(note) else { return }
        try? data.write(to: fileURL(note.id), options: .atomic)
    }

    private func saveTombstones() {
        guard let data = try? Coders.encoder.encode(tombstones) else { return }
        try? data.write(to: tombstoneURL, options: .atomic)
    }

    private func load() {
        var loaded: [Note] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let note = try? Coders.decoder.decode(Note.self, from: data) {
                loaded.append(note)
            }
        }
        notes = loaded

        if let data = try? Data(contentsOf: tombstoneURL),
           let list = try? Coders.decoder.decode([Tombstone].self, from: data) {
            tombstones = list
        }
    }
}
