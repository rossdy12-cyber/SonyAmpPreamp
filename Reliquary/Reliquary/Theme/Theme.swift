import SwiftUI
import UIKit

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

/// Crimson-and-black gothic palette. The app is always dark.
enum Theme {
    static let bg = Color(hex: "0A0A0A")
    static let panel = Color(hex: "140808")
    static let crimson = Color(hex: "B3001B")
    static let crimsonBright = Color(hex: "DC143C")
    static let bone = Color(hex: "E8DFD0")
    static let muted = Color(hex: "8C7F7B")
    static let hairline = Color(hex: "3A0A12")

    static func title(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .bold, design: .serif)
    }

    static func body(_ size: CGFloat = 16) -> Font {
        Font.system(size: size, weight: .regular, design: .serif)
    }

    static func serifUIFont(_ size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    static func applyAppearance() {
        let boneUI = UIColor(hex: "E8DFD0")
        let crimsonUI = UIColor(hex: "DC143C")
        let mutedUI = UIColor(hex: "8C7F7B")
        let bgUI = UIColor(hex: "0A0A0A")
        let lineUI = UIColor(hex: "3A0A12")

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = bgUI
        nav.shadowColor = lineUI
        nav.titleTextAttributes = [.foregroundColor: boneUI, .font: serifUIFont(18)]
        #if !os(tvOS)
        nav.largeTitleTextAttributes = [.foregroundColor: boneUI, .font: serifUIFont(32)]
        #endif
        UINavigationBar.appearance().standardAppearance = nav
        #if !os(tvOS)
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        #endif
        UINavigationBar.appearance().tintColor = crimsonUI

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = bgUI
        tab.shadowColor = lineUI
        let layouts: [UITabBarItemAppearance] = [
            tab.stackedLayoutAppearance,
            tab.inlineLayoutAppearance,
            tab.compactInlineLayoutAppearance
        ]
        for item in layouts {
            item.normal.iconColor = mutedUI
            item.normal.titleTextAttributes = [.foregroundColor: mutedUI]
            item.selected.iconColor = crimsonUI
            item.selected.titleTextAttributes = [.foregroundColor: crimsonUI]
        }
        UITabBar.appearance().standardAppearance = tab
        #if !os(tvOS)
        UITabBar.appearance().scrollEdgeAppearance = tab
        #endif
    }
}

#if os(tvOS)
enum TVNavigationBarTitleDisplayMode {
    case automatic, inline, large
}
extension View {
    func navigationBarTitleDisplayMode(_ mode: TVNavigationBarTitleDisplayMode) -> some View {
        self
    }
}
#endif

extension View {
    /// Solid near-black screen background that also fills the safe areas.
    func gothicBackground() -> some View {
        self.background(Theme.bg.ignoresSafeArea())
    }
}

/// A thin crimson rule with a small cross glyph in the middle.
struct OrnateDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Text("\u{271D}")
                .font(.system(size: 14))
                .foregroundColor(Theme.crimson)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

struct ErrorStateView: View {
    let message: String
    var retryTitle: String = "Try again"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundColor(Theme.crimsonBright)
            Text(message)
                .font(Theme.body(15))
                .foregroundColor(Theme.bone)
                .multilineTextAlignment(.center)
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Text(retryTitle)
                        .font(Theme.title(15))
                        .foregroundColor(Theme.bone)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Theme.crimson)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundColor(Theme.crimson)
            Text(title)
                .font(Theme.title(20))
                .foregroundColor(Theme.bone)
            Text(message)
                .font(Theme.body(14))
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
