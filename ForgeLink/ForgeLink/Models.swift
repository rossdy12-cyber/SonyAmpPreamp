import Foundation

struct BridgeStatus: Decodable {
    let name: String
    let version: String
    let agents: [Agent]
    let projects: [Project]
}
struct Agent: Decodable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let resumable: Bool?
    var canResume: Bool { resumable ?? false }
    var symbol: String {
        switch id {
        case "claude": return "sparkles"
        case "antigravity": return "globe.americas.fill"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }
}
struct Project: Decodable, Identifiable {
    let id: String
    let name: String
    let instructions: String?
    let actions: [SavedAction]
}
struct SavedAction: Decodable, Identifiable {
    let id: String
    let name: String
}
struct ConversationMessage: Decodable, Identifiable {
    let id: String
    let projectId: String
    let projectName: String
    let parentRunId: String?
    let agentId: String
    let title: String
    let prompt: String
    let status: String
    let startedAt: String
    let endedAt: String?
    let exitCode: Int?
    let output: String
    let responseLost: Bool
    let canContinue: Bool
    let revision: Int
    let conversationId: String
}
struct Run: Decodable, Identifiable {
    let id: String
    let projectId: String
    let projectName: String
    let agentId: String
    let title: String
    let prompt: String
    let status: String
    let startedAt: String
    let endedAt: String?
    let exitCode: Int?
    let output: String?
    let responseLost: Bool?
    let canContinue: Bool?
    let parentRunId: String?
    let conversationId: String?
    let revision: Int
    let truncated: Bool
    var isActive: Bool { status == "running" }
    var statusLabel: String {
        if status == "dispatched" { return "Sent to DeepAI" }
        return status.capitalized
    }
    var agentName: String {
        switch agentId {
        case "claude": return "Claude"
        case "antigravity": return "Antigravity"
        case "deepai": return "DeepAI Code"
        default: return "Saved command"
        }
    }
    var dateLabel: String {
        guard let date = ISO8601DateFormatter.fractional.date(from: startedAt) else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
struct RunRequest: Encodable {
    let projectId: String
    let agentId: String?
    let actionId: String?
    let prompt: String?
    let parentRunId: String?
}
struct APIError: Decodable { let error: String }
struct ConnectionSettings {
    var endpoint: String
    var token: String
}
