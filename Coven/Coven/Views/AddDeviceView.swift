import SwiftUI

struct AddDeviceView: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var room = "Sanctum"
    @State private var kind: DeviceKind = .switchDevice
    @State private var host = ""
    @State private var port = "80"
    @State private var onURL = ""
    @State private var offURL = ""
    @State private var toggleURL = ""
    @State private var stateURL = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()
                Form {
                    Section("Identity") {
                        TextField("Device name", text: $name)
                        Picker("Room", selection: $room) {
                            ForEach(store.rooms, id: \.self) { r in
                                Text(r).tag(r)
                            }
                        }
                        TextField("New room name (optional)", text: $room)
                            .textInputAutocapitalization(.words)
                        Picker("Kind", selection: $kind) {
                            ForEach(DeviceKind.allCases) { k in
                                Text(k.rawValue).tag(k)
                            }
                        }
                    }
                    Section("Network") {
                        TextField("Host / IP address", text: $host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)
                    }
                    Section("HTTP Actions") {
                        TextField("On URL or /path", text: $onURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Off URL or /path", text: $offURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Toggle URL or /path", text: $toggleURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("State URL or /path (optional)", text: $stateURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Section("Notes") {
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add to Coven")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedRoom = room.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = SmartDevice(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed Device" : name.trimmingCharacters(in: .whitespacesAndNewlines),
            room: trimmedRoom.isEmpty ? "Sanctum" : trimmedRoom,
            kind: kind,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "80" : port.trimmingCharacters(in: .whitespacesAndNewlines),
            onURL: onURL.trimmingCharacters(in: .whitespacesAndNewlines),
            offURL: offURL.trimmingCharacters(in: .whitespacesAndNewlines),
            toggleURL: toggleURL.trimmingCharacters(in: .whitespacesAndNewlines),
            stateURL: stateURL.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.add(device)
        dismiss()
    }
}