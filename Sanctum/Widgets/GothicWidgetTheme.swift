import SwiftUI
import UIKit

enum GothicTheme {
    // Authentic Vampire Red & Black Palette
    static let void      = Color(red: 0.020, green: 0.008, blue: 0.012) // #050203 obsidian void
    static let crypt     = Color(red: 0.071, green: 0.024, blue: 0.035) // #120609 dark crypt panel
    static let sepulchre = Color(red: 0.110, green: 0.039, blue: 0.059) // #1C0A0F raised panel
    static let tomb      = Color(red: 0.227, green: 0.071, blue: 0.098) // #3A1219 dark border
    static let bloodDeep = Color(red: 0.361, green: 0.039, blue: 0.094) // #5C0A18 deep blood fill/glow
    static let blood     = Color(red: 0.620, green: 0.059, blue: 0.157) // #9E0F28 blood border & rules
    static let bloodHi   = Color(red: 0.831, green: 0.086, blue: 0.227) // #D4163A bright arterial crimson
    static let scarlet   = Color(red: 0.940, green: 0.180, blue: 0.300) // #F02E4C high-alert crimson
    static let bone      = Color(red: 0.937, green: 0.894, blue: 0.882) // #EFE4E1 pale bone primary text
    static let ash       = Color(red: 0.612, green: 0.522, blue: 0.537) // #9C8589 muted ash secondary text

    static func display(_ size: CGFloat) -> Font {
        if UIFont(name: "Didot-Bold", size: size) != nil {
            return .custom("Didot-Bold", size: size)
        }
        return .system(size: size, weight: .black, design: .serif)
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

struct GothicLancetArch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let spring = rect.minY + rect.height * 0.42
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: spring))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.10)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: spring),
            control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.10)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

struct GothicCathedralBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                GothicTheme.void

                RadialGradient(
                    colors: [GothicTheme.bloodDeep.opacity(0.65), GothicTheme.crypt.opacity(0.4), Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: max(w, h) * 0.85
                )

                // Subtle gothic cathedral lancet arch watermark
                GothicLancetArch()
                    .stroke(GothicTheme.blood.opacity(0.22), lineWidth: 1)
                    .frame(width: w * 0.82, height: h * 0.90)
                    .position(x: w / 2, y: h * 0.56)

                Circle()
                    .stroke(GothicTheme.blood.opacity(0.18), lineWidth: 0.8)
                    .frame(width: min(w, h) * 0.28, height: min(w, h) * 0.28)
                    .position(x: w / 2, y: h * 0.34)

                // Outer blood-red sanctum frame
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [GothicTheme.bloodHi.opacity(0.55), GothicTheme.tomb.opacity(0.35), GothicTheme.blood.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                    .padding(3)
            }
        }
    }
}

struct GothicHeader: View {
    let title: String
    var rightText: String = ""

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text("✠")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(GothicTheme.bloodHi)
                Text(title.uppercased())
                    .font(GothicTheme.serif(9.5, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(GothicTheme.ash)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if !rightText.isEmpty {
                    Text(rightText)
                        .font(GothicTheme.serif(9.5, weight: .semibold))
                        .foregroundStyle(GothicTheme.bone.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [GothicTheme.bloodHi.opacity(0.75), GothicTheme.blood.opacity(0.35), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.8)
        }
    }
}

struct GothicOrnamentRule: View {
    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, GothicTheme.blood.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.8)
            Text("✠")
                .font(.system(size: 8))
                .foregroundStyle(GothicTheme.bloodHi)
            Rectangle()
                .fill(LinearGradient(colors: [GothicTheme.blood.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 0.8)
        }
    }
}

extension View {
    func gothicPanel(active: Bool = false, corner: CGFloat = 7) -> some View {
        self
            .background(
                active
                    ? LinearGradient(colors: [GothicTheme.bloodDeep, GothicTheme.crypt], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [GothicTheme.sepulchre.opacity(0.9), GothicTheme.crypt.opacity(0.95)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: corner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(active ? GothicTheme.bloodHi : GothicTheme.blood.opacity(0.55), lineWidth: active ? 1.2 : 0.8)
            )
    }
}
