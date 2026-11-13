import SwiftUI
import MapKit
import CoreLocation

struct PlacesView: View {
    @EnvironmentObject var session: Session

    @State private var editing: Place?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            ZStack {
                TetherBackground()
                if session.places.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 44))
                            .foregroundColor(Theme.crimsonBright)
                        Text("No places yet")
                            .font(Theme.serif(22))
                            .foregroundColor(Theme.bone)
                        Text("Add Home, Work or School and Tether will tell your circle when someone arrives or leaves.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(Theme.muted)
                            .padding(.horizontal, 32)
                        Button("Add a place") { adding = true }
                            .buttonStyle(CrimsonButtonStyle())
                            .padding(.horizontal, 60)
                            .padding(.top, 6)
                    }
                } else {
                    List {
                        ForEach(session.places) { place in
                            Button {
                                editing = place
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: Fmt.placeIcon(place.icon))
                                        .foregroundColor(.white)
                                        .frame(width: 38, height: 38)
                                        .background(Theme.crimson)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(place.name)
                                            .font(.headline)
                                            .foregroundColor(Theme.bone)
                                        Text("Radius \(Int(place.radius)) m")
                                            .font(.caption)
                                            .foregroundColor(Theme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(Theme.muted)
                                }
                            }
                            .listRowBackground(Theme.panel)
                        }
                        .onDelete { offsets in
                            let doomed = offsets.map { session.places[$0] }
                            Task {
                                for place in doomed {
                                    await session.deletePlace(place)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Places")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        adding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $adding) {
                PlaceEditor(place: nil)
            }
            .sheet(item: $editing) { place in
                PlaceEditor(place: place)
            }
        }
    }
}

private struct EditorPin: Identifiable {
    let coordinate: CLLocationCoordinate2D
    var id: String { "pin" }
}

struct PlaceEditor: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var engine: LocationEngine
    @Environment(\.dismiss) private var dismiss

    let place: Place?

    @State private var name: String
    @State private var icon: String
    @State private var radius: Double
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition = .automatic
    @State private var saving = false

    init(place: Place?) {
        self.place = place
        _name = State(initialValue: place?.name ?? "")
        _icon = State(initialValue: place?.icon ?? "pin")
        _radius = State(initialValue: place?.radius ?? 150)
        _coordinate = State(initialValue: place?.coordinate)
    }

    private var pins: [EditorPin] {
        if let coordinate = coordinate {
            return [EditorPin(coordinate: coordinate)]
        }
        return []
    }

    private var canSave: Bool {
        !saving && !name.trimmingCharacters(in: .whitespaces).isEmpty && coordinate != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TetherBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        TetherField(title: "Name", text: $name, capitalization: .words)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Icon")
                                .font(.footnote)
                                .foregroundColor(Theme.muted)
                            HStack(spacing: 10) {
                                ForEach(Place.icons, id: \.self) { option in
                                    Image(systemName: Fmt.placeIcon(option))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)
                                        .background(icon == option ? Theme.crimson : Theme.panel)
                                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                                        .clipShape(Circle())
                                        .onTapGesture { icon = option }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Radius: \(Int(radius)) m")
                                .font(.footnote)
                                .foregroundColor(Theme.muted)
                            Slider(value: $radius, in: 50...2000, step: 10)
                                .tint(Theme.crimsonBright)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location")
                                .font(.footnote)
                                .foregroundColor(Theme.muted)
                            MapReader { proxy in
                                Map(position: $position) {
                                    ForEach(pins) { pin in
                                        MapCircle(center: pin.coordinate, radius: radius)
                                            .foregroundStyle(Theme.crimson.opacity(0.2))
                                            .stroke(Theme.crimsonBright, lineWidth: 1)
                                        Marker(name.isEmpty ? "Place" : name, systemImage: Fmt.placeIcon(icon), coordinate: pin.coordinate)
                                            .tint(Theme.crimsonBright)
                                    }
                                }
                                .mapStyle(.standard(elevation: .flat))
                                .onTapGesture { point in
                                    if let tapped = proxy.convert(point, from: .local) {
                                        coordinate = tapped
                                    }
                                }
                            }
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))

                            Text("Tap the map to place it, or use where you are now.")
                                .font(.caption)
                                .foregroundColor(Theme.muted)

                            Button {
                                useCurrentLocation()
                            } label: {
                                Label("Use my current location", systemImage: "location.fill")
                            }
                            .buttonStyle(CrimsonButtonStyle(filled: false))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(place == nil ? "New place" : "Edit place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let coordinate = coordinate {
                    position = .region(regionAround(coordinate, span: 0.012))
                } else if let here = engine.lastLocation {
                    position = .region(regionAround(here.coordinate, span: 0.012))
                }
            }
        }
        .presentationBackground(Theme.bg0)
    }

    private func useCurrentLocation() {
        guard let here = engine.lastLocation else {
            session.showMessage("No location fix yet. Check that location is allowed.")
            return
        }
        coordinate = here.coordinate
        position = .region(regionAround(here.coordinate, span: 0.012))
    }

    private func save() {
        guard let coordinate = coordinate else { return }
        saving = true
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let editId = place?.id
        let chosenIcon = icon
        let chosenRadius = radius
        Task {
            let ok = await session.savePlace(id: editId, name: trimmed, coordinate: coordinate, radius: chosenRadius, icon: chosenIcon)
            saving = false
            if ok { dismiss() }
        }
    }
}
