import Foundation

extension Date {
    /// Drops fractional seconds so values survive JSON / front-matter round trips unchanged.
    var wholeSeconds: Date {
        Date(timeIntervalSince1970: floor(timeIntervalSince1970))
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Coders {
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

enum Iso {
    static func string(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func date(_ text: String?) -> Date? {
        guard let text = text else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}

struct Tombstone: Codable, Equatable {
    var id: UUID
    var deletedAt: Date
}

struct Note: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var folder: String
    var tags: [String]
    var isPinned: Bool
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        folder: String = "",
        tags: [String] = [],
        isPinned: Bool = false,
        createdAt: Date = Date().wholeSeconds,
        modifiedAt: Date = Date().wholeSeconds
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.folder = folder
        self.tags = tags
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    var displayTitle: String {
        let t = title.trimmed
        if !t.isEmpty { return t }
        let junk = CharacterSet(charactersIn: "#>*-+ ").union(.whitespaces)
        for line in body.split(separator: "\n", omittingEmptySubsequences: true) {
            let cleaned = String(line).trimmingCharacters(in: junk)
            if !cleaned.isEmpty { return cleaned }
        }
        return "Untitled Tome"
    }

    var preview: String {
        let flat = body.replacingOccurrences(of: "\n", with: " ").trimmed
        if flat.count > 140 {
            return String(flat.prefix(140)) + "…"
        }
        return flat
    }

    var isBlank: Bool {
        title.trimmed.isEmpty && body.trimmed.isEmpty && tags.isEmpty
    }

    /// True when the user-visible content matches (ignores timestamps).
    func contentEquals(_ other: Note) -> Bool {
        return title == other.title
            && body == other.body
            && folder == other.folder
            && tags == other.tags
            && isPinned == other.isPinned
    }

    static func parseTags(_ text: String) -> [String] {
        var result: [String] = []
        for part in text.split(separator: ",") {
            let tag = String(part).replacingOccurrences(of: "#", with: "").trimmed
            if !tag.isEmpty && !result.contains(tag) {
                result.append(tag)
            }
        }
        return result
    }
}

/// Markdown file format used for NAS sync: a small front-matter header followed by the body.
enum NoteMarkdown {
    private static func oneLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func serialize(_ note: Note) -> String {
        var lines: [String] = []
        lines.append("---")
        lines.append("id: " + note.id.uuidString)
        lines.append("title: " + oneLine(note.title))
        lines.append("folder: " + oneLine(note.folder))
        var tagParts: [String] = []
        for tag in note.tags {
            tagParts.append(oneLine(tag).replacingOccurrences(of: ",", with: " "))
        }
        lines.append("tags: " + tagParts.joined(separator: ", "))
        lines.append("pinned: " + (note.isPinned ? "true" : "false"))
        lines.append("created: " + Iso.string(note.createdAt))
        lines.append("modified: " + Iso.string(note.modifiedAt))
        lines.append("---")
        return lines.joined(separator: "\n") + "\n" + note.body
    }

    /// The note id always comes from the file name; the header value is informational only.
    static func parse(_ rawText: String, id: UUID, fallbackDate: Date?) -> Note {
        let text = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        var meta: [String: String] = [:]
        var bodyText = text

        if text.hasPrefix("---\n") {
            let rest = String(text.dropFirst(4))
            var header: String? = nil
            if let range = rest.range(of: "\n---\n") {
                header = String(rest[rest.startIndex..<range.lowerBound])
                bodyText = String(rest[range.upperBound...])
            } else if rest.hasSuffix("\n---") {
                header = String(rest.dropLast(4))
                bodyText = ""
            }
            if let header = header {
                for line in header.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    meta[key] = value
                }
            }
        }

        let fallback = (fallbackDate ?? Date()).wholeSeconds
        let modified = Iso.date(meta["modified"]) ?? fallback
        let created = Iso.date(meta["created"]) ?? modified

        return Note(
            id: id,
            title: meta["title"] ?? "",
            body: bodyText,
            folder: meta["folder"] ?? "",
            tags: Note.parseTags(meta["tags"] ?? ""),
            isPinned: (meta["pinned"] ?? "false").lowercased() == "true",
            createdAt: created,
            modifiedAt: modified
        )
    }
}
