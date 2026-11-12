import SwiftUI
import UIKit

/// Shared "vampire" design kit: blacks with a red undertone, blood red, pale bone-white text.
/// Copy this one file into any app target.
enum GothicTheme {
    // MARK: Palette
    static let void       = Color(red: 0.020, green: 0.008, blue: 0.012)   // #050203 page background
    static let crypt      = Color(red: 0.071, green: 0.024, blue: 0.035)   // #120609 panels
    static let sepulchre  = Color(red: 0.110, green: 0.039, blue: 0.059)   // #1C0A0F raised panels
    static let tomb       = Color(red: 0.227, green: 0.071, blue: 0.098)   // #3A1219 borders
    static let bloodDeep  = Color(red: 0.361, green: 0.039, blue: 0.094)   // #5C0A18 glows, large fills
    static let blood      = Color(red: 0.620, green: 0.059, blue: 0.157)   // #9E0F28 decoration, borders
    static let bloodHi    = Color(red: 0.831, green: 0.086, blue: 0.227)   // #D4163A bright accent (buttons, highlights)
    static let bone       = Color(red: 0.937, green: 0.894, blue: 0.882)   // #EFE4E1 primary text
    static let ash        = Color(red: 0.612, green: 0.522, blue: 0.537)   // #9C8589 secondary text

    // MARK: Typography
    /// Display face for big titles. Real blackletter (UnifrakturCook) if that font is bundled in the app,
    /// otherwise Didot, which ships with iOS and has the same high-contrast gothic-revival feel.
    static func display(_ size: CGFloat) -> Font {
        if UIFont(name: "UnifrakturCook", size: size) != nil {
            return .custom("UnifrakturCook", size: size)
        }
        return .custom("Didot-Bold", size: size)
    }

    /// Body text: the system serif (New York).
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .serif)
    }
}

/// Pointed (lancet) arch outline, used for windows and frames.
struct GothicArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let spring = rect.minY + rect.height * 0.40
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: spring))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.10))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: spring),
                       control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.10))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

/// A thin blood-red rule with a cross in the middle.
struct OrnamentDivider: View {
    var color: Color = GothicTheme.blood

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, color], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            Text("✠").font(.system(size: 12)).foregroundStyle(color)
            Rectangle()
                .fill(LinearGradient(colors: [color, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
    }
}

extension View {
    /// Near-black page background with a soft blood-red glow from the top.
    func gothicBackground() -> some View {
        self.background(
            ZStack {
                GothicTheme.void
                RadialGradient(colors: [GothicTheme.bloodDeep.opacity(0.55), Color.clear],
                               center: .top, startRadius: 0, endRadius: 420)
            }
            .ignoresSafeArea()
        )
    }

    /// Panel with a thin blood-red border.
    func gothicCard(corner: CGFloat = 6) -> some View {
        self
            .background(GothicTheme.crypt, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(GothicTheme.blood.opacity(0.55), lineWidth: 1)
            )
    }
}
