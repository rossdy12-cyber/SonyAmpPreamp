import SwiftUI
import UIKit

/// Crimson's palette: deep black with blood-crimson accents.
enum Crimson {
    static let bg = Color(hex: "050203")
    static let bg2 = Color(hex: "0C0406")
    static let panel = Color(hex: "120609")
    static let field = Color(hex: "1C0A0F")
    static let accent = Color(hex: "D4163A")
    static let accent2 = Color(hex: "FF6B81")
    static let text = Color(hex: "EFE4E1")
    static let muted = Color(hex: "9C8589")
    static let hairline = Color.white.opacity(0.08)
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255,
                  opacity: 1)
    }
}
