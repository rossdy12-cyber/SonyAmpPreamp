import SwiftUI
import MapKit
import CoreLocation

private struct LocatedMember: Identifiable {
    let member: Member
    let coordinate: CLLocationCoordinate2D
    var id: String { member.id }
}

struct MapTab: View {
    @EnvironmentObject var session: Session

    @State private var position: MapCameraPosition = .automatic
    @State private var selected: Member?
    @State private var didFit = false

    private var located: [LocatedMember] {
        session.members.compactMap { member in
            guard let loc = member.location, !member.paused else { return nil }
            return LocatedMember(member: member, coordinate: loc.coordinate)
        }
    }

    var body: some View {
        ZStack {
            Map(position: $position) {
                ForEach(session.places) { place in
                    MapCircle(center: place.coordinate, radius: place.radius)
                        .foregroundStyle(Theme.crimson.opacity(0.18))
                        .stroke(Theme.crimsonBright.opacity(0.8), lineWidth: 1)
                    Annotation(place.name, coordinate: place.coordinate) {
                        Image(systemName: Fmt.placeIcon(place.icon))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(7)
                            .background(Theme.crimson)
                            .clipShape(Circle())
                    }
                }
                ForEach(located) { item in
                    Annotation(item.member.name, coordinate: item.coordinate) {
                        MemberAvatar(member: item.member)
                            .onTapGesture { selected = item.member }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .ignoresSafeArea(edges: .top)

            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        roundButton("scope") { fitAll() }
                        roundButton("arrow.clockwise") {
                            Task { await session.refreshAll() }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 60)

                Spacer()

                SafetyBar()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .sheet(item: $selected) { member in
            MemberSheet(memberId: member.id)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.bg0)
        }
        .onAppear {
            if !located.isEmpty && !didFit {
                fitAll()
                didFit = true
            }
        }
        .onChange(of: located.count) { _, count in
            if count > 0 && !didFit {
                fitAll()
                didFit = true
            }
        }
        .onChange(of: session.focusTick) { _, _ in
            applyFocus()
        }
    }

    private func roundButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.bone)
                .frame(width: 42, height: 42)
                .background(Theme.panel.opacity(0.92))
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                .clipShape(Circle())
        }
    }

    private func fitAll() {
        var coords = located.map { $0.coordinate }
        if coords.isEmpty {
            coords = session.places.map { $0.coordinate }
        }
        guard !coords.isEmpty else { return }
        withAnimation {
            position = .region(regionThatFits(coords))
        }
    }

    private func applyFocus() {
        if let id = session.focusMemberId,
           let member = session.member(withId: id),
           let loc = member.location {
            withAnimation {
                position = .region(regionAround(loc.coordinate))
            }
            selected = member
        } else if let coordinate = session.focusCoordinate {
            withAnimation {
                position = .region(regionAround(coordinate))
            }
        }
    }
}

// MARK: - Member sheet

struct MemberSheet: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss

    let memberId: String

    private var member: Member? { session.member(withId: memberId) }

    var body: some View {
        ZStack {
            TetherBackground()
            if let member = member {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(member)
                        details(member)
                        actions(member)
                    }
                    .padding(20)
                }
            } else {
                Text("This person is no longer in the circle.")
                    .foregroundColor(Theme.muted)
            }
        }
    }

    private func header(_ member: Member) -> some View {
        HStack(spacing: 14) {
            MemberAvatar(member: member, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                    .font(Theme.serif(24))
                    .foregroundColor(Theme.bone)
                if member.paused {
                    Text("Sharing paused")
                        .foregroundColor(Theme.muted)
                } else if let loc = member.location {
                    Text(loc.placeName.map { "At \($0)" } ?? "Updated \(Fmt.relative(loc.ts))")
                        .foregroundColor(Theme.muted)
                } else {
                    Text("No location yet")
                        .foregroundColor(Theme.muted)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func details(_ member: Member) -> some View {
        if member.paused {
            Text("\(member.name) has paused location sharing\(member.pausedSince.map { " since " + Fmt.dayTime($0) } ?? "").")
                .foregroundColor(Theme.muted)
        } else if let loc = member.location {
            VStack(alignment: .leading, spacing: 12) {
                infoRow("mappin.circle.fill", "Where") {
                    if let name = loc.placeName {
                        Text(name)
                    } else {
                        AddressText(lat: loc.lat, lon: loc.lon)
                    }
                }
                infoRow(Fmt.activityIcon(loc.activity), "Doing") {
                    Text(Fmt.speed(loc.speed).map { "\(Fmt.activityLabel(loc.activity)) · \($0)" } ?? Fmt.activityLabel(loc.activity))
                }
                infoRow(loc.charging == true ? "battery.100.bolt" : "battery.50", "Battery") {
                    Text((Fmt.battery(loc.battery) ?? "Unknown") + (loc.charging == true ? " · charging" : ""))
                }
                infoRow("clock.fill", "Updated") {
                    Text(Fmt.relative(loc.ts))
                }
            }
            .padding(14)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func infoRow<Content: View>(_ icon: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Theme.crimsonBright)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(Theme.muted)
                content()
                    .foregroundColor(Theme.bone)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func actions(_ member: Member) -> some View {
        VStack(spacing: 10) {
            if !member.paused, let loc = member.location {
                Button {
                    openDirections(to: loc.coordinate, name: member.name)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(CrimsonButtonStyle())
            }
            Button {
                session.timelineMemberId = member.id
                session.selectedTab = 2
                dismiss()
            } label: {
                Label("Timeline", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(CrimsonButtonStyle(filled: false))
        }
    }

    private func openDirections(to coordinate: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
