import SwiftUI

enum StudioTheme {
    static let bgDeep = Color(red: 0.031, green: 0.027, blue: 0.047)
    static let bgCard = Color(red: 0.075, green: 0.063, blue: 0.114)
    static let bgElevated = Color(red: 0.118, green: 0.098, blue: 0.176)
    static let borderSubtle = Color.white.opacity(0.10)
    static let crimson = Color(red: 0.882, green: 0.114, blue: 0.282)
    static let neonViolet = Color(red: 0.545, green: 0.361, blue: 0.965)
    static let cyanGlow = Color(red: 0.220, green: 0.741, blue: 0.973)
    static let emerald = Color(red: 0.063, green: 0.725, blue: 0.506)
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)
    static let textPrimary = Color(red: 0.965, green: 0.957, blue: 0.988)
    static let textSecondary = Color(red: 0.678, green: 0.647, blue: 0.765)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [crimson, neonViolet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var cardGradient: LinearGradient {
        LinearGradient(
            colors: [bgCard, Color(red: 0.055, green: 0.047, blue: 0.088)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct StudioCardModifier: ViewModifier {
    var borderColor: Color = StudioTheme.borderSubtle
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(StudioTheme.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

extension View {
    func studioCard(borderColor: Color = StudioTheme.borderSubtle) -> some View {
        modifier(StudioCardModifier(borderColor: borderColor))
    }
}
