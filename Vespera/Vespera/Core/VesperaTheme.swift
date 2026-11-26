import SwiftUI
import AVKit
import UIKit

enum VesperaTheme {
    // True OLED #000000 for zero night-vision glare on the SHARP CP-DS10 Qi2 dock
    static let oledBlack = Color.black
    static let abyss = Color(red: 0.03, green: 0.015, blue: 0.02)
    static let surface = Color(red: 0.075, green: 0.035, blue: 0.045)
    static let raised = Color(red: 0.12, green: 0.05, blue: 0.068)
    static let crimson = Color(red: 0.545, green: 0.0, blue: 0.0)
    static let blood = Color(red: 0.863, green: 0.078, blue: 0.235)
    static let ember = Color(red: 1.0, green: 0.16, blue: 0.26)
    static let gold = Color(red: 0.83, green: 0.686, blue: 0.216)
    static let bone = Color(red: 0.94, green: 0.90, blue: 0.86)
    static let ash = Color(red: 0.62, green: 0.55, blue: 0.52)
    static let line = Color(red: 0.28, green: 0.07, blue: 0.11)

    static func gothic(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func engraved(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

struct CathedralBackground: View {
    var pureOLED: Bool = false

    var body: some View {
        ZStack {
            if pureOLED {
                Color.black.ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        Color.black,
                        VesperaTheme.abyss,
                        Color(red: 0.09, green: 0.01, blue: 0.025),
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [VesperaTheme.crimson.opacity(0.22), .clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()
            }
        }
    }
}

struct GothicCardModifier: ViewModifier {
    var highlighted: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(VesperaTheme.surface.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                highlighted ? VesperaTheme.ember : VesperaTheme.blood.opacity(0.65),
                                VesperaTheme.line.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: highlighted ? 1.5 : 1.0
                    )
            )
            .shadow(color: (highlighted ? VesperaTheme.blood : VesperaTheme.crimson).opacity(0.25), radius: 10, y: 4)
    }
}

extension View {
    func gothicCard(highlighted: Bool = false) -> some View {
        modifier(GothicCardModifier(highlighted: highlighted))
    }
}

/// Native iOS Bluetooth / AirPlay route picker button for one-tap switching to SHARP CP-DS10
struct BluetoothRoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor(red: 0.863, green: 0.078, blue: 0.235, alpha: 1.0)
        picker.activeTintColor = UIColor(red: 1.0, green: 0.16, blue: 0.26, alpha: 1.0)
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
