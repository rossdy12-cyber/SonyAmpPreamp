import Foundation

struct WebDAVConfig {
    var baseURL: String
    var username: String
    var password: String
    var folder: String
}

enum WebDAVError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server URL or folder name is not valid."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .http(let code):
            switch code {
            case 401:
                return "Login failed (401). Check the username and password."
            case 403:
                return "Access denied (403). The account may not be allowed to write to this folder."
            case 404:
                return "Not found (404). Check the server URL."
            case 405:
                return "The server refused the request (405). Is WebDAV enabled at this URL?"
            case 507:
                return "The NAS is out of space (507)."
            default:
                return "The server returned HTTP status \(code)."
            }
        }
    }
}

struct RemoteItem {
    var name: String
    var modified: Date?
    var isDirectory: Bool
}

/// Minimal WebDAV client scoped to one remote folder of flat files.
struct NotesWebDAV {
    let config: WebDAVConfig

    private var folderComponents: [String] {
        var parts: [String] = []
        for piece in config.folder.split(separator: "/") {
            let part = String(piece).trimmed
            if !part.isEmpty {
                parts.append(part)
            }
        }
        return parts
    }

    private var rootString: String {
        var s = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") {
            s.removeLast()
        }
        return s
    }

    private func encode(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    private func makeURL(_ components: [String], trailingSlash: Bool) -> URL? {
        var s = rootString
        for component in components {
            s += "/" + encode(component)
        }
        if trailingSlash {
            s += "/"
        }
        return URL(string: s)
    }

    private func makeRequest(_ url: URL, method: String, timeout: TimeInterval = 30) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        let credentials = Data("\(config.username):\(config.password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        return (data, http)
    }

    /// Creates the remote folder (and any parents). Existing folders are fine.
    func ensureFolder() async throws {
        var parts: [String] = []
        for component in folderComponents {
            parts.append(component)
            guard let url = makeURL(parts, trailingSlash: true) else {
                throw WebDAVError.invalidURL
            }
            let (_, http) = try await send(makeRequest(url, method: "MKCOL"))
            if http.statusCode == 401 {
                throw WebDAVError.http(401)
            }
        }
    }

    func list() async throws -> [RemoteItem] {
        guard let url = makeURL(folderComponents, trailingSlash: true) else {
            throw WebDAVError.invalidURL
        }
        var request = makeRequest(url, method: "PROPFIND")
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = "<?xml version=\"1.0\" encoding=\"utf-8\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:getlastmodified/><d:resourcetype/></d:prop></d:propfind>"
        request.httpBody = Data(body.utf8)

        let (data, http) = try await send(request)
        guard http.statusCode == 207 || (200..<300).contains(http.statusCode) else {
            throw WebDAVError.http(http.statusCode)
        }
        return PropfindParser.parse(data)
    }

    /// Returns nil when the file does not exist.
    func get(_ name: String) async throws -> Data? {
        guard let url = makeURL(folderComponents + [name], trailingSlash: false) else {
            throw WebDAVError.invalidURL
        }
        let (data, http) = try await send(makeRequest(url, method: "GET", timeout: 60))
        if http.statusCode == 404 {
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WebDAVError.http(http.statusCode)
        }
        return data
    }

    func put(_ name: String, data: Data) async throws {
        guard let url = makeURL(folderComponents + [name], trailingSlash: false) else {
            throw WebDAVError.invalidURL
        }
        var request = makeRequest(url, method: "PUT", timeout: 60)
        request.setValue("text/markdown; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, http) = try await send(request)
        guard (200..<300).contains(http.statusCode) else {
            throw WebDAVError.http(http.statusCode)
        }
    }

    /// A missing file counts as already deleted.
    func delete(_ name: String) async throws {
        guard let url = makeURL(folderComponents + [name], trailingSlash: false) else {
            throw WebDAVError.invalidURL
        }
        let (_, http) = try await send(makeRequest(url, method: "DELETE"))
        if http.statusCode == 404 {
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WebDAVError.http(http.statusCode)
        }
    }
}

private final class PropfindParser: NSObject, XMLParserDelegate {
    private var items: [RemoteItem] = []
    private var text = ""
    private var href: String?
    private var modified: Date?
    private var isDirectory = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    static func parse(_ data: Data) -> [RemoteItem] {
        let delegate = PropfindParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    private static func localName(_ name: String) -> String {
        let last = name.components(separatedBy: ":").last ?? name
        return last.lowercased()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        text = ""
        let local = PropfindParser.localName(elementName)
        if local == "response" {
            href = nil
            modified = nil
            isDirectory = false
        } else if local == "collection" {
            isDirectory = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let local = PropfindParser.localName(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if local == "href" {
            href = value
        } else if local == "getlastmodified" {
            if let date = PropfindParser.dateFormatter.date(from: value) {
                modified = date
            }
        } else if local == "response" {
            finishItem()
        }
    }

    private func finishItem() {
        guard let rawHref = href else { return }
        let decoded = rawHref.removingPercentEncoding ?? rawHref
        let directory = isDirectory || decoded.hasSuffix("/")
        var trimmed = decoded
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        let name = (trimmed as NSString).lastPathComponent
        if name.isEmpty { return }
        items.append(RemoteItem(name: name, modified: modified, isDirectory: directory))
    }
}
