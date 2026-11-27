import Foundation
import CryptoKit

/// Filename/path filters, kept identical to the Windows app's defaults so both
/// sides agree on which files exist at all.
enum Ignore {
    static let defaults: [String] = [
        "Thumbs.db",
        "desktop.ini",
        ".DS_Store",
        "~$*",
        "*.tmp",
        "*.swp",
        ".duosync.tmp.*"
    ]

    static let partialPrefix = ".duosync.tmp."

    private struct Rule {
        let byPath: Bool
        let regex: NSRegularExpression
    }

    static func matcher(_ patterns: [String]) -> (String, String) -> Bool {
        var rules: [Rule] = []
        for raw in patterns {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let byPath = trimmed.contains("/")
            let body = byPath ? String(trimmed.drop(while: { $0 == "/" })) : trimmed
            guard let regex = try? NSRegularExpression(pattern: "^" + globToRegex(body) + "$", options: [.caseInsensitive]) else {
                continue
            }
            rules.append(Rule(byPath: byPath, regex: regex))
        }
        return { name, rel in
            if name.hasPrefix(partialPrefix) { return true }
            let range = NSRange(location: 0, length: 0)
            for rule in rules {
                let subject = rule.byPath ? rel : name
                let full = NSRange(subject.startIndex..., in: subject)
                if rule.regex.firstMatch(in: subject, options: [], range: full) != nil { return true }
                _ = range
            }
            return false
        }
    }

    static func globToRegex(_ pattern: String) -> String {
        var out = ""
        let chars = Array(pattern)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "*" {
                if index + 1 < chars.count && chars[index + 1] == "*" {
                    out += ".*"
                    index += 1
                } else {
                    out += "[^/]*"
                }
            } else if char == "?" {
                out += "[^/]"
            } else if "\\.+^${}()|[]".contains(char) {
                out += "\\\(char)"
            } else {
                out.append(char)
            }
            index += 1
        }
        return out
    }
}

enum Hasher {
    /// Hash a file, retrying once if it changes while being read.
    static func sha256(of url: URL) throws -> (hash: String, size: Int64, mtime: Int64) {
        let before = try attributes(of: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let after = try attributes(of: url)
        if before.size != after.size || before.mtime != after.mtime {
            throw SyncError.checksum(url.lastPathComponent)
        }
        return (digest, after.size, after.mtime)
    }

    static func attributes(of url: URL) throws -> (size: Int64, mtime: Int64) {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(values.fileSize ?? 0)
        let mtime = Int64((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000)
        return (size, mtime)
    }
}

/// Walks a pair's folder and hashes whatever changed since last time.
struct ScanResult {
    var files: [String: FileEntry] = [:]
    var cache: [String: CachedHash] = [:]
    var problems: [String] = []
}

struct FolderScanner {
    let root: URL
    let isIgnored: (String, String) -> Bool
    let cache: [String: CachedHash]

    func scan() -> ScanResult {
        var result = ScanResult()
        var listing: [(rel: String, url: URL, size: Int64, mtime: Int64)] = []
        walk(directory: root, rel: "", into: &listing, problems: &result.problems)

        for item in listing {
            if let cached = cache[item.rel], cached.size == item.size, cached.mtime == item.mtime {
                result.files[item.rel] = FileEntry(hash: cached.hash, size: item.size, mtime: item.mtime)
                result.cache[item.rel] = cached
                continue
            }
            do {
                let hashed = try Hasher.sha256(of: item.url)
                let entry = FileEntry(hash: hashed.hash, size: hashed.size, mtime: hashed.mtime)
                result.files[item.rel] = entry
                result.cache[item.rel] = CachedHash(size: entry.size, mtime: entry.mtime, hash: entry.hash)
            } catch {
                result.problems.append("\(item.rel): \(error.localizedDescription)")
            }
        }
        return result
    }

    private func walk(
        directory: URL,
        rel: String,
        into listing: inout [(rel: String, url: URL, size: Int64, mtime: Int64)],
        problems: inout [String]
    ) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: []
            )
        } catch {
            problems.append("\(rel.isEmpty ? "." : rel): \(error.localizedDescription)")
            return
        }

        for url in entries {
            let name = url.lastPathComponent
            let childRel = rel.isEmpty ? name : "\(rel)/\(name)"
            if isIgnored(name, childRel) { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }

            if values.isDirectory == true {
                walk(directory: url, rel: childRel, into: &listing, problems: &problems)
            } else if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                let mtime = Int64((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000)
                listing.append((childRel, url, size, mtime))
            }
        }
    }
}

/// Removes directories left empty by deletions, mirroring the Windows behaviour.
enum Pruner {
    @discardableResult
    static func pruneEmptyFolders(in root: URL, isIgnored: (String, String) -> Bool) -> Int {
        var removed = 0
        func visit(_ directory: URL, rel: String) -> Bool {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { return false }

            var hasContent = false
            for url in entries {
                let name = url.lastPathComponent
                let childRel = rel.isEmpty ? name : "\(rel)/\(name)"
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    if isIgnored(name, childRel) {
                        hasContent = true
                        continue
                    }
                    if visit(url, rel: childRel) {
                        removed += 1
                    } else {
                        hasContent = true
                    }
                } else {
                    hasContent = true
                }
            }
            if !hasContent && !rel.isEmpty {
                try? FileManager.default.removeItem(at: directory)
                return true
            }
            return false
        }
        _ = visit(root, rel: "")
        return removed
    }
}
