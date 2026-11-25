import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var status: BridgeStatus?
    @Published var runs: [Run] = []
    @Published var detail: Run?
    @Published var selectedProject = ""
    @Published var selectedAgent = ""
    @Published var error: String?
    @Published var isConnecting = false
    @Published var isSubmitting = false
    @Published var connected = false
    @Published var showSettings = false
    @Published var endpoint: String
    private(set) var token: String
    private var client: BridgeClient?
    private var refreshing = false
    private var generation = 0

    init() {
        endpoint = UserDefaults.standard.string(forKey: "bridgeEndpoint") ?? ""
        token = Keychain.load()
        if endpoint.isEmpty || token.isEmpty { showSettings = true }
    }
    var project: Project? { status?.projects.first { $0.id == selectedProject } }
    var activeCount: Int { runs.filter(\.isActive).count }
    var projectBusy: Bool { runs.contains { $0.projectId == selectedProject && $0.isActive } }
    var settings: ConnectionSettings { ConnectionSettings(endpoint: endpoint, token: token) }

    func connect(_ settings: ConnectionSettings? = nil) async {
        guard !isConnecting else { return }
        let candidate = settings ?? self.settings
        isConnecting = true
        error = nil
        defer { isConnecting = false }
        do {
            let newClient = try BridgeClient(settings: candidate)
            let info: BridgeStatus = try await newClient.request("v1/status")
            try Keychain.save(candidate.token)
            generation += 1
            client = newClient
            endpoint = candidate.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            token = candidate.token
            UserDefaults.standard.set(endpoint, forKey: "bridgeEndpoint")
            status = info
            runs = []
            detail = nil
            if !info.projects.contains(where: { $0.id == selectedProject }) { selectedProject = info.projects.first?.id ?? "" }
            if !info.agents.contains(where: { $0.id == selectedAgent }) { selectedAgent = info.agents.first?.id ?? "" }
            connected = true
            showSettings = false
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
    func refresh() async {
        guard let client, !refreshing else { return }
        let current = generation
        refreshing = true
        defer { refreshing = false }
        do {
            let latest: [Run] = try await client.request("v1/runs")
            guard current == generation else { return }
            runs = latest
            connected = true
        } catch {
            guard current == generation else { return }
            connected = false
            self.error = "Connection lost. Runs continue on the host. \(error.localizedDescription)"
        }
    }
    func submit(prompt: String? = nil, action: SavedAction? = nil) async -> Run? {
        guard let client, !isSubmitting, !selectedProject.isEmpty else { return nil }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        do {
            let request = RunRequest(projectId: selectedProject, agentId: action == nil ? selectedAgent : nil, actionId: action?.id, prompt: prompt)
            let run: Run = try await client.request("v1/runs", method: "POST", body: request)
            runs.insert(run, at: 0)
            detail = run
            return run
        } catch {
            self.error = "Could not confirm submission. Refresh history before retrying, to avoid duplicate work. \(error.localizedDescription)"
            return nil
        }
    }
    func loadDetail(_ id: String) async {
        guard let client else { return }
        let current = generation
        do {
            let result: Run = try await client.request("v1/runs/\(id)")
            guard current == generation else { return }
            detail = result
            if let index = runs.firstIndex(where: { $0.id == id }) { runs[index] = result }
            connected = true
        } catch { self.error = error.localizedDescription }
    }
    func cancel(_ id: String) async {
        guard let client else { return }
        do {
            let result: Run = try await client.request("v1/runs/\(id)", method: "DELETE")
            detail = result
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func forget() {
        do { try Keychain.save("") }
        catch { self.error = error.localizedDescription; return }
        generation += 1
        client = nil
        token = ""
        endpoint = ""
        status = nil
        runs = []
        detail = nil
        connected = false
        UserDefaults.standard.removeObject(forKey: "bridgeEndpoint")
        showSettings = true
    }
}
