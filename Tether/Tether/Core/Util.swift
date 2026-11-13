import SwiftUI
import UIKit
import MapKit
import CoreLocation

/// A map region that contains all of the coordinates, with some padding.
func regionThatFits(_ coords: [CLLocationCoordinate2D], minSpan: Double = 0.01) -> MKCoordinateRegion {
    guard let first = coords.first else {
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    }
    var minLat = first.latitude
    var maxLat = first.latitude
    var minLon = first.longitude
    var maxLon = first.longitude
    for c in coords {
        minLat = min(minLat, c.latitude)
        maxLat = max(maxLat, c.latitude)
        minLon = min(minLon, c.longitude)
        maxLon = max(maxLon, c.longitude)
    }
    let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    let span = MKCoordinateSpan(
        latitudeDelta: max((maxLat - minLat) * 1.5, minSpan),
        longitudeDelta: max((maxLon - minLon) * 1.5, minSpan)
    )
    return MKCoordinateRegion(center: center, span: span)
}

func regionAround(_ coordinate: CLLocationCoordinate2D, span: Double = 0.01) -> MKCoordinateRegion {
    MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
}

/// Looks up street addresses and remembers them so the map doesn't ask Apple again and again.
@MainActor
final class Geocoder {
    static let shared = Geocoder()

    private var cache: [String: String] = [:]

    func address(lat: Double, lon: Double) async -> String? {
        let key = String(format: "%.4f,%.4f", lat, lon)
        if let hit = cache[key] { return hit }
        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon))
            guard let mark = marks.first else { return nil }
            var parts: [String] = []
            let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
            if !street.isEmpty {
                parts.append(street)
            } else if let name = mark.name {
                parts.append(name)
            }
            if let town = mark.locality { parts.append(town) }
            let text = parts.joined(separator: ", ")
            if text.isEmpty { return nil }
            cache[key] = text
            return text
        } catch {
            return nil
        }
    }
}

/// A street address that fills in once it has been looked up.
struct AddressText: View {
    let lat: Double
    let lon: Double
    var fallback: String = "Locating..."

    @State private var text: String?

    var body: some View {
        Text(text ?? fallback)
            .task(id: "\(lat),\(lon)") {
                text = await Geocoder.shared.address(lat: lat, lon: lon)
            }
    }
}

@MainActor
enum Haptics {
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// A rounded dark text field used on the onboarding and editor screens.
struct TetherField: View {
    let title: String
    @Binding var text: String
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundColor(Theme.muted)
            Group {
                if secure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(capitalization)
                        .autocorrectionDisabled(true)
                }
            }
            .padding(12)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundColor(Theme.bone)
        }
    }
}

/// A row of colour swatches to pick an avatar colour.
struct ColorPicker10: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Theme.palette, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle().stroke(Color.white, lineWidth: selection == hex ? 3 : 0)
                    )
                    .onTapGesture { selection = hex }
            }
        }
    }
}

/// A member's avatar: coloured circle with their initial and a battery ring.
struct MemberAvatar: View {
    let member: Member
    var size: CGFloat = 44

    private func batteryColor(_ level: Double) -> Color {
        if level < 0.15 { return Color.red }
        if level < 0.3 { return Color.orange }
        return Color.green
    }

    var body: some View {
        ZStack {
            Circle().fill(member.paused ? Color.gray.opacity(0.55) : Color(hex: member.color))
            if member.paused {
                Image(systemName: "pause.fill")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text(member.initial)
                    .font(Theme.serif(size * 0.45))
                    .foregroundColor(.white)
            }
            if let level = member.location?.battery, !member.paused {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.03, min(1, level))))
                    .stroke(batteryColor(level), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-5)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
        .shadow(color: Color.black.opacity(0.5), radius: 3)
    }
}
