import SwiftUI
import UIKit

enum Theme {
    static let bg0 = Color(hex: "070305")
    static let bg1 = Color(hex: "12060A")
    static let panel = Color(hex: "170A0F")
    static let panelElevated = Color(hex: "210E15")
    static let crimson = Color(hex: "B3001B")
    static let crimsonBright = Color(hex: "E11D48")
    static let bloodGlow = Color(hex: "FF2A54")
    static let amber = Color(hex: "F59E0B")
    static let violet = Color(hex: "A855F7")
    static let cyan = Color(hex: "38BDF8")
    static let emerald = Color(hex: "10B981")
    static let bone = Color(hex: "EFE7DA")
    static let muted = Color(hex: "9E8489")
    static let hairline = Color(hex: "B3001B").opacity(0.38)

    static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .serif)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }

    private static func serifUIFont(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    static func configureAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(hex: "070305")
        nav.shadowColor = UIColor(hex: "B3001B").withAlphaComponent(0.45)
        nav.titleTextAttributes = [
            .foregroundColor: UIColor(hex: "EFE7DA"),
            .font: serifUIFont(18, .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor(hex: "EFE7DA"),
            .font: serifUIFont(32, .bold)
        ]
        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = nav
        proxy.scrollEdgeAppearance = nav
        proxy.compactAppearance = nav
        proxy.tintColor = UIColor(hex: "E11D48")

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(hex: "0B0407")
        tab.shadowColor = UIColor(hex: "B3001B").withAlphaComponent(0.4)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff) / 255.0
        let g = Double((v >> 8) & 0xff) / 255.0
        let b = Double(v & 0xff) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

extension UIColor {
    convenience init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            red: CGFloat((v >> 16) & 0xff) / 255.0,
            green: CGFloat((v >> 8) & 0xff) / 255.0,
            blue: CGFloat(v & 0xff) / 255.0,
            alpha: 1.0
        )
    }
}

struct GothicBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bg0, Theme.bg1, Theme.bg0],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.crimson.opacity(0.16), Color.clear],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

struct GothicCard<Content: View>: View {
    var glowing: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.panelElevated, Theme.panel],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        glowing ? Theme.crimsonBright.opacity(0.85) : Theme.hairline,
                        lineWidth: glowing ? 1.5 : 1.0
                    )
            )
            .shadow(
                color: glowing ? Theme.crimson.opacity(0.35) : Color.black.opacity(0.45),
                radius: glowing ? 12 : 6,
                x: 0,
                y: 4
            )
    }
}
