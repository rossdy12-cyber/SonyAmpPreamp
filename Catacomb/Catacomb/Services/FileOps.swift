import Foundation

/// Every filesystem operation in Catacomb. Anything touching a granted folder
/// goes through `withAccess`, which brackets it with
/// start/stopAccessingSecurityScopedResource on the scoped root.
enum FileOps {

    // MARK: Security scope

    static func withAccess<T>(_ roots: [URL?], _ body: () throws -> T) rethrows -> T {
        var started: [URL] = []
        for candidate in roots {
            if let root = candidate, root.startAccessingSecurityScopedResource() {
                started.append(root)
            }
        }
        defer {
            for root in started {
                root.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }

    // MARK: Listing

    static func list(_ dir: URL, root: URL?) throws -> [FileItem] {
        return try withAccess([root]) { () throws -> [FileItem] in
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
            var result: [FileItem] = []
            for u in urls {
                let values = try? u.resourceValues(forKeys: Set(keys))
                result.append(FileItem(
                    url: u,
                    name: u.lastPathComponent,
                    isDirectory: values?.isDirectory ?? false,
                    size: Int64(values?.fileSize ?? 0),
                    modified: values?.contentModificationDate
                ))
            }
            return result
        }
    }

    // MARK: Create / rename / delete

    static func validate(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." {
            throw CatacombError.message("Enter a valid name.")
        }
        if trimmed.contains("/") || trimmed.contains(":") {
            throw CatacombError.message("Names can't contain \"/\" or \":\".")
        }
        return trimmed
    }

    static func createFolder(named name: String, in dir: URL, root: URL?) throws {
        let clean = try validate(name)
        try withAccess([root]) { () throws -> Void in
            let target = dir.appendingPathComponent(clean, isDirectory: true)
            if FileManager.default.fileExists(atPath: target.path) {
                throw CatacombError.message("\"\(clean)\" already exists.")
            }
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        }
    }

    static func createFile(named name: String, in dir: URL, root: URL?) throws {
        let clean = try validate(name)
        try withAccess([root]) { () throws -> Void in
            let target = dir.appendingPathComponent(clean)
            if FileManager.default.fileExists(atPath: target.path) {
                throw CatacombError.message("\"\(clean)\" already exists.")
            }
            try Data().write(to: target)
        }
    }

    static func rename(_ item: FileItem, to newName: String, root: URL?) throws {
        let clean = try validate(newName)
        if clean == item.name { return }
        try withAccess([root]) { () throws -> Void in
            let target = item.url.deletingLastPathComponent().appendingPathComponent(clean)
            if FileManager.default.fileExists(atPath: target.path) {
                throw CatacombError.message("\"\(clean)\" already exists.")
            }
            try FileManager.default.moveItem(at: item.url, to: target)
        }
    }

    static func delete(_ items: [FileItem], root: URL?) throws {
        try withAccess([root]) { () throws -> Void in
            for item in items {
                try FileManager.default.removeItem(at: item.url)
            }
        }
    }

    // MARK: Move / copy / import

    static func uniqueURL(in dir: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var n = 1
        while true {
            let suffix = n == 1 ? " copy" : " copy \(n)"
            let newName = ext.isEmpty ? base + suffix : base + suffix + "." + ext
            candidate = dir.appendingPathComponent(newName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    static func transfer(_ items: [FileItem], srcRoot: URL?, dest: URL, destRoot: URL?, move: Bool) throws {
        try withAccess([srcRoot, destRoot]) { () throws -> Void in
            let fm = FileManager.default
            let destPath = dest.standardizedFileURL.path
            for item in items {
                let srcPath = item.url.standardizedFileURL.path
                if item.isDirectory && (destPath == srcPath || destPath.hasPrefix(srcPath + "/")) {
                    throw CatacombError.message("Can't put \"\(item.name)\" inside itself.")
                }
                let parentPath = item.url.deletingLastPathComponent().standardizedFileURL.path
                if move && parentPath == destPath { continue }
                let target = uniqueURL(in: dest, name: item.name)
                if move {
                    try fm.moveItem(at: item.url, to: target)
                } else {
                    try fm.copyItem(at: item.url, to: target)
                }
            }
        }
    }

    static func importFiles(_ urls: [URL], into dir: URL, root: URL?) throws -> Int {
        return try withAccess([root]) { () throws -> Int in
            var count = 0
            for u in urls {
                let started = u.startAccessingSecurityScopedResource()
                defer {
                    if started { u.stopAccessingSecurityScopedResource() }
                }
                let target = uniqueURL(in: dir, name: u.lastPathComponent)
                try FileManager.default.copyItem(at: u, to: target)
                count += 1
            }
            return count
        }
    }

    // MARK: Staging (temp copies for Quick Look / share of scoped files)

    static var stagingRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CatacombStage", isDirectory: true)
    }

    static func clearStaging() {
        try? FileManager.default.removeItem(at: stagingRoot)
    }

    /// Returns a URL that stays readable after security scope is released.
    /// Sandbox files (root == nil) are returned as-is.
    static func stage(_ url: URL, root: URL?) throws -> URL {
        if root == nil { return url }
        return try withAccess([root]) { () throws -> URL in
            let dir = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        }
    }

    // MARK: Text editing

    static func readText(_ url: URL, root: URL?) throws -> String {
        return try withAccess([root]) { () throws -> String in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            let size = values?.fileSize ?? 0
            if size > 2_000_000 {
                throw CatacombError.message("This file is too large to edit (over 2 MB).")
            }
            var encoding = String.Encoding.utf8
            return try String(contentsOf: url, usedEncoding: &encoding)
        }
    }

    static func writeText(_ text: String, to url: URL, root: URL?) throws {
        try withAccess([root]) { () throws -> Void in
            let data = Data(text.utf8)
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                try data.write(to: url)
            }
        }
    }

    // MARK: Sizes

    static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        while let next = enumerator.nextObject() as? URL {
            let values = try? next.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
