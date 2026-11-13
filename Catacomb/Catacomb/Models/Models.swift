import Foundation

/// A user-granted external folder, persisted as a security-scoped bookmark.
struct StoredLocation: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var bookmark: Data
}

/// One screen in the navigation stack. `rootURL` is the security-scoped root
/// (nil for the app's own sandbox, which needs no scope).
struct FolderRoute: Hashable {
    let url: URL
    let rootURL: URL?
    let title: String
}

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date?

    var id: URL { url }
    var ext: String { url.pathExtension.lowercased() }
}

extension FileItem {
    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "yml", "yaml", "xml", "csv", "log",
        "swift", "js", "ts", "py", "sh", "html", "css", "ini", "conf", "toml",
        "c", "h", "m", "cpp", "java", "go", "rb", "rs"
    ]

    var isTextEditable: Bool {
        !isDirectory && FileItem.textExtensions.contains(ext)
    }

    var symbolName: String {
        if isDirectory { return "folder.fill" }
        switch ext {
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "txt", "md", "markdown", "rtf", "log":
            return "doc.text"
        case "json", "xml", "yml", "yaml", "plist", "csv", "ini", "conf", "toml":
            return "doc.plaintext"
        case "swift", "js", "ts", "py", "sh", "html", "css", "c", "h", "m", "cpp", "java", "go", "rb", "rs":
            return "chevron.left.forwardslash.chevron.right"
        case "mp3", "m4a", "wav", "aac", "flac", "aiff", "ogg":
            return "waveform"
        case "mp4", "mov", "m4v", "avi", "mkv":
            return "film"
        case "zip", "rar", "7z", "tar", "gz", "tgz":
            return "archivebox"
        default:
            return "doc"
        }
    }
}

enum SortKey: String, CaseIterable, Identifiable {
    case name
    case date
    case size

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Name"
        case .date: return "Date Modified"
        case .size: return "Size"
        }
    }
}

enum CatacombError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
