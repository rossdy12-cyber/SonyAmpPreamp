import SwiftUI
import CoreLocation

/// The circle's recent events: arrivals, departures, check-ins, SOS and low batteries.
struct ActivityView: View {
    @EnvironmentObject var session: Session

    var body: some View {
        NavigationStack {
            ZStack {
                TetherBackground()
                if session.events.isEmpty {
                    ScrollView {
                        VStack(spacing: 10) {
                            Image(systemName: "bell.slash")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.crimsonBright)
                            Text("Nothing yet")
                                .font(Theme.serif(22))
                                .foregroundColor(Theme.bone)
                            Text("Arrivals, departures, check-ins and SOS alerts show up here.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(Theme.muted)
                        }
                        .padding(.top, 120)
                        .padding(.horizontal, 32)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(session.events.reversed()) { event in
                                row(event)
                                    .onTapGesture { open(event) }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .refreshable {
                await session.refreshEvents(notify: false)
            }
            .navigationTitle("Activity")
        }
    }

    private func row(_ event: TetherEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: Fmt.eventIcon(event.kind))
                .font(.system(size: 22))
                .foregroundColor(event.kind == "sos" ? Color.red : Theme.crimsonBright)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.headline)
                    .font(.headline)
                    .foregroundColor(Theme.bone)
                if !event.text.isEmpty && event.text != event.headline {
                    Text(event.text)
                        .font(.subheadline)
                        .foregroundColor(Theme.muted)
                }
                Text(Fmt.relative(event.ts))
                    .font(.caption)
                    .foregroundColor(Theme.muted)
            }
            Spacer()
        }
        .padding(12)
        .background(event.kind == "sos" ? Theme.crimson.opacity(0.3) : Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func open(_ event: TetherEvent) {
        if let lat = event.lat, let lon = event.lon {
            session.focus(on: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        } else if !event.memberId.isEmpty {
            session.focus(onMember: event.memberId)
        }
    }
}
