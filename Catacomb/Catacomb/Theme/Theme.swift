import SwiftUI
import UIKit

/// Catacomb's palette: near-black, crimson accents, bone text, serif headings.
enum Theme {
    static let bg0 = Color(hex: "0A0A0A")
    static let bg1 = Color(hex: "140808")
    static let panel = Color(hex: "1A0D10")
    static let crimson = Color(hex: "B3001B")
    static let crimsonBright = Color(hex: "DC143C")
    static let bone = Color(hex: "EDE6DA")
    static let muted = Color(hex: "9C8589")
    static let hairline = Color(hex: "B3001B").opacity(0.35)

    static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .serif)
    }

    private static func serifUIFont(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    /// Styles every navigation bar in the app (called once at launch).
    static func configureAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(hex: "0A0A0A")
        nav.shadowColor = UIColor(hex: "B3001B").withAlphaComponent(0.5)
        nav.titleTextAttributes = [
            .foregroundColor: UIColor(hex: "EDE6DA"),
            .font: serifUIFont(17, .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor(hex: "EDE6DA"),
            .font: serifUIFont(34, .bold)
        ]
        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = nav
        proxy.scrollEdgeAppearance = nav
        proxy.compactAppearance = nav
        proxy.tintColor = UIColor(hex: "DC143C")
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >> 8) & 0xff) / 255
        let b = Double(v & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

extension UIColor {
    convenience init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            red: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255,
            alpha: 1
        )
    }
}

/// Deep near-black gradient with a faint crimson vignette.
struct GothicBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bg0, Theme.bg1, Theme.bg0], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.clear, Color.black.opacity(0.5)], center: .center, startRadius: 120, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}
