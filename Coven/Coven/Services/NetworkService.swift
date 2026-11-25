import Foundation

enum NetworkService {
    static func sendRequest(urlString: String, method: String = "GET", body: String? = nil, headers: [String: String] = [:], completion: @escaping (Result<String, Error>) -> Void) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "Coven", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 8
        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        if let body = body, !body.isEmpty {
            req.httpBody = body.data(using: .utf8)
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if (200...299).contains(status) {
                completion(.success(text))
            } else {
                let msg = text.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(text.prefix(200))"
                completion(.failure(NSError(domain: "Coven", code: status, userInfo: [NSLocalizedDescriptionKey: msg])))
            }
        }.resume()
    }

    static func normalizeURL(_ raw: String, host: String, port: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        if t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://") {
            return t
        }
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: String
        if p.isEmpty || p == "80" {
            base = "http://\(h)"
        } else {
            base = "http://\(h):\(p)"
        }
        if t.hasPrefix("/") {
            return base + t
        }
        return base + "/" + t
    }
}