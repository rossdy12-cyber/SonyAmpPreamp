import SwiftUI

enum Gothic {
    static let crimson = Color(red: 0.86, green: 0.08, blue: 0.24)
    static let bloodDark = Color(red: 0.18, green: 0.02, blue: 0.05)
    static let ash = Color(red: 0.93, green: 0.90, blue: 0.87)
    static let coal = Color(red: 0.03, green: 0.01, blue: 0.02)
    static let ember = Color(red: 0.45, green: 0.03, blue: 0.10)

    static let bg = LinearGradient(
        colors: [Color(red: 0.05, green: 0.015, blue: 0.025), Color(red: 0.01, green: 0.004, blue: 0.008)],
        startPoint: .top, endPoint: .bottom)

    static func field(_ dark: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(dark ? Color(red: 0.10, green: 0.03, blue: 0.05) : Color(red: 0.14, green: 0.04, blue: 0.07))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(crimson.opacity(0.45), lineWidth: 1))
    }
}

extension View {
    func gothicChrome() -> some View {
        background(Gothic.bg.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}
