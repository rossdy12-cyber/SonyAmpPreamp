import SwiftUI
import MapKit
import CoreLocation

private struct PathLine: Identifiable {
    let id: String
    let coords: [CLLocationCoordinate2D]
    let highlighted: Bool
}

private struct StayPin: Identifiable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
}

/// A day's movements for one person: where they stayed and how they travelled between.
struct HistoryView: View {
    @EnvironmentObject var session: Session

    @State private var memberId = ""
    @State private var dates: [String] = []
    @State private var day = ""
    @State private var response: TimelineResponse?
    @State private var message: String?
    @State private var loading = false
    @State private var selectedItem: String?
    @State private var position: MapCameraPosition = .automatic

    private var items: [TimelineItem] { response?.items ?? [] }

    private var lines: [PathLine] {
        var result: [PathLine] = []
        let whole = coordinates(from: response?.points ?? [])
        if whole.count > 1 {
            result.append(PathLine(id: "day", coords: whole, highlighted: false))
        }
        if let chosen = items.first(where: { $0.id == selectedItem }), let pts = chosen.points {
            let coords = coordinates(from: pts)
            if coords.count > 1 {
                result.append(PathLine(id: "chosen", coords: coords, highlighted: true))
            }
        }
        return result
    }

    private var pins: [StayPin] {
        items.compactMap { item in
            guard item.isStay, let lat = item.lat, let lon = item.lon else { return nil }
            return StayPin(
                id: item.id,
                title: item.placeName ?? "Stay",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }
    }

    private var totalDistance: Double {
        items.filter { !$0.isStay }.reduce(0) { $0 + ($1.distance ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TetherBackground()
                VStack(spacing: 0) {
                    pickers
                    timelineMap
                        .frame(height: 250)
                    content
                }
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { adoptSelection() }
        .onChange(of: session.timelineMemberId) { _, _ in adoptSelection() }
        .task(id: memberId) { await loadDates() }
        .task(id: "\(memberId)|\(day)") { await loadTimeline() }
    }

    // MARK: Pieces

    private var pickers: some View {
        HStack(spacing: 12) {
            Picker("Person", selection: $memberId) {
                ForEach(session.members) { member in
                    Text(member.name).tag(member.id)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.crimsonBright)

            Spacer()

            if dates.isEmpty {
                Text(Fmt.prettyDay(day.isEmpty ? Fmt.dayString(Date()) : day))
                    .foregroundColor(Theme.muted)
            } else {
                Picker("Day", selection: $day) {
                    ForEach(dates, id: \.self) { value in
                        Text(Fmt.prettyDay(value)).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.crimsonBright)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var timelineMap: some View {
        Map(position: $position) {
            ForEach(lines) { line in
                MapPolyline(coordinates: line.coords)
                    .stroke(line.highlighted ? Color.white : Theme.crimsonBright.opacity(0.7), lineWidth: line.highlighted ? 5 : 3)
            }
            ForEach(pins) { pin in
                Annotation(pin.title, coordinate: pin.coordinate) {
                    Circle()
                        .fill(Theme.crimson)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    @ViewBuilder
    private var content: some View {
        if loading && response == nil {
            ProgressView()
                .tint(Theme.crimsonBright)
                .padding(.top, 40)
            Spacer()
        } else if let message = message, items.isEmpty {
            Text(message)
                .foregroundColor(Theme.muted)
                .padding(.top, 40)
            Spacer()
        } else if items.isEmpty {
            Text("No movement recorded for this day.")
                .foregroundColor(Theme.muted)
                .padding(.top, 40)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    HStack {
                        Text("\(items.filter { $0.isStay }.count) stops · \(Fmt.distance(totalDistance)) travelled")
                            .font(.footnote)
                            .foregroundColor(Theme.muted)
                        Spacer()
                    }
                    ForEach(items) { item in
                        row(item)
                            .onTapGesture { select(item) }
                    }
                }
                .padding(16)
            }
        }
    }

    private func row(_ item: TimelineItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.isStay ? "mappin.circle.fill" : Fmt.activityIcon(item.mode))
                .font(.system(size: 22))
                .foregroundColor(Theme.crimsonBright)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                if item.isStay {
                    if let name = item.placeName {
                        Text(name)
                            .font(.headline)
                            .foregroundColor(Theme.bone)
                    } else if let lat = item.lat, let lon = item.lon {
                        AddressText(lat: lat, lon: lon, fallback: "Stopped")
                            .font(.headline)
                            .foregroundColor(Theme.bone)
                    } else {
                        Text("Stopped")
                            .font(.headline)
                            .foregroundColor(Theme.bone)
                    }
                    Text("\(Fmt.clock(item.start)) – \(Fmt.clock(item.end)) · \(Fmt.duration(item.end - item.start))")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                } else {
                    Text("\(tripTitle(item)) · \(Fmt.distance(item.distance ?? 0))")
                        .font(.headline)
                        .foregroundColor(Theme.bone)
                    Text(tripDetail(item))
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(selectedItem == item.id ? Theme.crimson.opacity(0.25) : Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func tripTitle(_ item: TimelineItem) -> String {
        guard let mode = item.mode, mode != "unknown" else { return "Trip" }
        return "\(Fmt.activityLabel(mode)) trip"
    }

    private func tripDetail(_ item: TimelineItem) -> String {
        var text = "\(Fmt.clock(item.start)) – \(Fmt.clock(item.end)) · \(Fmt.duration(item.end - item.start))"
        if let top = Fmt.speed(item.maxSpeed) {
            text += " · top \(top)"
        }
        return text
    }

    // MARK: Actions

    private func select(_ item: TimelineItem) {
        selectedItem = item.id
        var coords: [CLLocationCoordinate2D] = []
        if let pts = item.points {
            coords = coordinates(from: pts)
        } else if let lat = item.lat, let lon = item.lon {
            coords = [CLLocationCoordinate2D(latitude: lat, longitude: lon)]
        }
        guard !coords.isEmpty else { return }
        withAnimation {
            position = .region(regionThatFits(coords, minSpan: 0.006))
        }
    }

    private func adoptSelection() {
        if let id = session.timelineMemberId {
            memberId = id
            session.timelineMemberId = nil
        } else if memberId.isEmpty {
            memberId = session.me?.id ?? session.members.first?.id ?? ""
        }
    }

    private func loadDates() async {
        guard !memberId.isEmpty else { return }
        do {
            let result = try await session.request("GET", "/v1/dates", query: [("member", memberId)], as: DatesResponse.self)
            dates = result.dates
            if !dates.contains(day) {
                day = dates.first ?? Fmt.dayString(Date())
            }
        } catch {
            dates = []
            if day.isEmpty { day = Fmt.dayString(Date()) }
            message = error.localizedDescription
        }
    }

    private func loadTimeline() async {
        guard !memberId.isEmpty, !day.isEmpty else { return }
        loading = true
        message = nil
        selectedItem = nil
        do {
            let result = try await session.request(
                "GET", "/v1/timeline",
                query: [("member", memberId), ("date", day), ("tz", TimeZone.current.identifier)],
                as: TimelineResponse.self
            )
            response = result
            let coords = coordinates(from: result.points)
            if !coords.isEmpty {
                withAnimation {
                    position = .region(regionThatFits(coords, minSpan: 0.008))
                }
            }
        } catch {
            response = nil
            message = error.localizedDescription
        }
        loading = false
    }
}
