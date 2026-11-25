import Foundation
import Combine

final class HomeAssistantService: ObservableObject {
    @Published var entities: [HAEntity] = []
    @Published var isLoading = false
    @Published var lastError: String? = nil

    func fetchStates(baseURL: String, token: String) {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty, !token.isEmpty, let url = URL(string: "\(base)/api/states") else {
            DispatchQueue.main.async { self.lastError = "Set Home Assistant URL and token in Settings." }
            return
        }
        DispatchQueue.main.async {
            self.isLoading = true
            self.lastError = nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async { self.isLoading = false }
            if let error = error {
                DispatchQueue.main.async { self.lastError = error.localizedDescription }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status), let data = data else {
                DispatchQueue.main.async { self.lastError = "HTTP \(status) from Home Assistant" }
                return
            }
            do {
                if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    let mapped: [HAEntity] = arr.compactMap { dict in
                        guard let entityId = dict["entity_id"] as? String else { return nil }
                        let state = dict["state"] as? String ?? "unknown"
                        let attrs = dict["attributes"] as? [String: Any]
                        let friendly = attrs?["friendly_name"] as? String ?? entityId
                        let domain = entityId.split(separator: ".").first.map(String.init) ?? "unknown"
                        return HAEntity(entityId: entityId, state: state, friendlyName: friendly, domain: domain)
                    }
                    let allowed: Set<String> = ["light", "switch", "fan", "climate", "cover", "lock", "camera", "sensor", "binary_sensor", "media_player", "scene", "script", "automation"]
                    let filtered = mapped.filter { allowed.contains($0.domain) }
                        .sorted { $0.friendlyName.localizedCaseInsensitiveCompare($1.friendlyName) == .orderedAscending }
                    DispatchQueue.main.async { self.entities = filtered }
                }
            } catch {
                DispatchQueue.main.async { self.lastError = "Failed to parse Home Assistant response." }
            }
        }.resume()
    }

    func callService(baseURL: String, token: String, domain: String, service: String, entityId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/services/\(domain)/\(service)") else {
            completion(.failure(NSError(domain: "Coven", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid Home Assistant URL"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["entity_id": entityId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(status) {
                completion(.success(()))
            } else {
                completion(.failure(NSError(domain: "Coven", code: status, userInfo: [NSLocalizedDescriptionKey: "Home Assistant HTTP \(status)"])))
            }
        }.resume()
    }
}