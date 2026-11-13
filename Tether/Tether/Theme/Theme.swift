import SwiftUI
import UIKit

/// Tether's palette: near-black, crimson accents, bone text.
enum Theme {
    static let bg0 = Color(hex: "0A0A0A")
    static let bg1 = Color(hex: "140808")
    static let panel = Color(hex: "1A0D10")
    static let crimson = Color(hex: "B3001B")
    static let crimsonBright = Color(hex: "DC143C")
    static let bone = Color(hex: "EDE6DA")
    static let muted = Color(hex: "9C8589")
    static let hairline = Color(hex: "B3001B").opacity(0.35)

    /// Colours offered for a member's avatar.
    static let palette: [String] = [
        "DC143C", "E8590C", "F2B01E", "4CAF50", "2EC4B6",
        "3A86FF", "8338EC", "FF5DA2", "A0A0A0", "B08968"
    ]

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

    /// Styles navigation and tab bars (called once at launch).
    @MainActor
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
        let navProxy = UINavigationBar.appearance()
        navProxy.standardAppearance = nav
        navProxy.scrollEdgeAppearance = nav
        navProxy.compactAppearance = nav
        navProxy.tintColor = UIColor(hex: "DC143C")

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(hex: "0A0A0A")
        tab.shadowColor = UIColor(hex: "B3001B").withAlphaComponent(0.5)
        let tabProxy = UITabBar.appearance()
        tabProxy.standardAppearance = tab
        tabProxy.scrollEdgeAppearance = tab
        tabProxy.tintColor = UIColor(hex: "DC143C")
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

/// Near-black gradient behind every screen.
struct TetherBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.bg0, Theme.bg1, Theme.bg0], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Primary crimson button style.
struct CrimsonButtonStyle: ButtonStyle {
    var filled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.serif(16, weight: .semibold))
            .foregroundColor(filled ? Color.white : Theme.crimsonBright)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(filled ? Theme.crimson : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Theme.crimsonBright.opacity(filled ? 0 : 0.8), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Text formatting helpers.
enum Fmt {
    static func relative(_ ts: Double) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: Date(timeIntervalSince1970: ts), relativeTo: Date())
    }

    static func clock(_ ts: Double) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    static func dayTime(_ ts: Double) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    /// Speed in mph, or nil when basically standing still.
    static func speed(_ mps: Double?) -> String? {
        guard let s = mps, s >= 0.8 else { return nil }
        return String(format: "%.0f mph", s * 2.23694)
    }

    static func distance(_ metres: Double) -> String {
        let miles = metres / 1609.344
        if miles >= 0.2 { return String(format: "%.1f mi", miles) }
        return String(format: "%.0f ft", metres * 3.28084)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 1))m"
    }

    static func battery(_ level: Double?) -> String? {
        guard let b = level, b >= 0 else { return nil }
        return "\(Int((b * 100).rounded()))%"
    }

    static func activityLabel(_ a: String?) -> String {
        switch a ?? "" {
        case "walking": return "Walking"
        case "running": return "Running"
        case "cycling": return "Cycling"
        case "driving": return "Driving"
        case "still": return "Still"
        default: return "Unknown"
        }
    }

    static func activityIcon(_ a: String?) -> String {
        switch a ?? "" {
        case "walking": return "figure.walk"
        case "running": return "figure.run"
        case "cycling": return "bicycle"
        case "driving": return "car.fill"
        case "still": return "figure.stand"
        default: return "questionmark.circle"
        }
    }

    static func placeIcon(_ icon: String) -> String {
        switch icon {
        case "home": return "house.fill"
        case "work": return "briefcase.fill"
        case "school": return "graduationcap.fill"
        case "gym": return "dumbbell.fill"
        case "shop": return "bag.fill"
        case "heart": return "heart.fill"
        default: return "mappin"
        }
    }

    static func eventIcon(_ kind: String) -> String {
        switch kind {
        case "arrive": return "arrow.down.right.circle.fill"
        case "leave": return "arrow.up.right.circle.fill"
        case "checkin": return "checkmark.circle.fill"
        case "sos": return "exclamationmark.triangle.fill"
        case "low_battery": return "battery.25"
        case "joined": return "person.badge.plus"
        default: return "bell.fill"
        }
    }

    /// "2026-11-13" for a date, in the phone's time zone.
    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func parseDay(_ text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text)
    }

    static func prettyDay(_ text: String) -> String {
        guard let d = parseDay(text) else { return text }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }
}
