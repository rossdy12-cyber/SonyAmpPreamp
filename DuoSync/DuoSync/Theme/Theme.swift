import SwiftUI

enum Theme {
    static let accent = Color(red: 0.30, green: 0.55, blue: 1.0)
    static let background = Color(red: 0.078, green: 0.086, blue: 0.102)
    static let panel = Color(red: 0.106, green: 0.118, blue: 0.141)
    static let panelRaised = Color(red: 0.129, green: 0.145, blue: 0.173)
    static let line = Color.white.opacity(0.09)
    static let muted = Color(white: 0.62)
    static let ok = Color(red: 0.21, green: 0.75, blue: 0.50)
    static let warn = Color(red: 0.88, green: 0.66, blue: 0.23)
    static let err = Color(red: 0.90, green: 0.41, blue: 0.37)
}

struct StatusDot: View {
    enum State { case ok, idle, busy, error }

    let state: State

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.28), lineWidth: 4)
                    .scaleEffect(state == .busy ? 1.7 : 1.0)
                    .opacity(state == .busy ? 1 : 0)
            )
            .animation(state == .busy ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: state)
    }

    private var color: Color {
        switch state {
        case .ok: return Theme.ok
        case .idle: return Theme.muted
        case .busy: return Theme.accent
        case .error: return Theme.err
        }
    }
}

struct Pill: View {
    let text: String
    var tint: Color = Theme.muted

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 0.5))
            .foregroundStyle(tint)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }

    func screenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}

/// Relative time, in the shorthand people expect from a sync app.
func relativeTime(_ date: Date?) -> String {
    guard let date else { return "never" }
    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 10 { return "just now" }
    if seconds < 60 { return "\(seconds)s ago" }
    if seconds < 3600 { return "\(seconds / 60)m ago" }
    if seconds < 86_400 { return "\(seconds / 3600)h ago" }
    return "\(seconds / 86_400)d ago"
}

func fileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    return formatter.string(fromByteCount: max(bytes, 0))
}
