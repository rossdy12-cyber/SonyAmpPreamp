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

enum GrimoireTheme {
    static let black = Color(hex: "0A0A0A")
    static let oxblood = Color(hex: "140808")
    static let panel = Color(hex: "1A0C0E")
    static let panelRaised = Color(hex: "241012")
    static let crimson = Color(hex: "B3001B")
    static let crimsonBright = Color(hex: "DC143C")
    static let bone = Color(hex: "EADFCB")
    static let muted = Color(hex: "9A8678")

    static func title(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .semibold, design: .serif)
    }

    static func body(_ size: CGFloat = 17) -> Font {
        Font.system(size: size, weight: .regular, design: .serif)
    }

    static func serifUIFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    static func styleNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)
        appearance.shadowColor = UIColor(red: 0.70, green: 0.0, blue: 0.106, alpha: 0.6)
        let boneUI = UIColor(red: 0.918, green: 0.875, blue: 0.796, alpha: 1)
        appearance.titleTextAttributes = [
            .foregroundColor: boneUI,
            .font: serifUIFont(size: 18, weight: .semibold)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: boneUI,
            .font: serifUIFont(size: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

enum Fmt {
    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Deep near-black gradient with a faint crimson vignette.
struct GrimoireBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [GrimoireTheme.black, GrimoireTheme.oxblood, GrimoireTheme.black],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.55)],
                center: .center,
                startRadius: 120,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

/// Thin crimson rule with a small cross in the middle.
struct OrnamentDivider: View {
    private var rule: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.clear, GrimoireTheme.crimson.opacity(0.85), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            rule
            Text("✠")
                .font(.system(size: 12))
                .foregroundStyle(GrimoireTheme.crimsonBright)
            rule
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
