import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.dismiss) private var dismiss
    @State var device: SmartDevice
    @State private var statusMessage = ""
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()
                Form {
                    Section("Identity") {
                        TextField("Name", text: $device.name)
                        TextField("Room", text: $device.room)
                        Picker("Kind", selection: $device.kind) {
                            ForEach(DeviceKind.allCases) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                    }
                    Section("Network") {
                        TextField("Host / IP", text: $device.host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Port", text: $device.port)
                            .keyboardType(.numberPad)
                    }
                    Section("HTTP Actions") {
                        TextField("On URL or /path", text: $device.onURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Off URL or /path", text: $device.offURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Toggle URL or /path", text: $device.toggleURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("State URL or /path (optional)", text: $device.stateURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Section("Notes") {
                        TextField("Notes", text: $device.notes, axis: .vertical)
                            .lineLimit(2...4)
                    }
                    Section("Command") {
                        HStack {
                            Button("On") { sendAction(device.onURL) }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.crimson)
                            Button("Off") { sendAction(device.offURL) }
                                .buttonStyle(.bordered)
                            Button("Toggle") { sendAction(device.toggleURL) }
                                .buttonStyle(.bordered)
                        }
                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundColor(Theme.muted)
                        }
                    }
                    Section {
                        Button("Delete Device", role: .destructive) {
                            store.delete(device)
                            dismiss()
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Device Rite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.update(device)
                        dismiss()
                    }
                }
            }
        }
    }

    private func sendAction(_ raw: String) {
        let url = NetworkService.normalizeURL(raw, host: device.host, port: device.port)
        guard !url.isEmpty else {
            statusMessage = "No URL configured."
            return
        }
        isBusy = true
        statusMessage = "Summoning..."
        NetworkService.sendRequest(urlString: url) { result in
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success(let text):
                    statusMessage = text.isEmpty ? "Command accepted." : String(text.prefix(140))
                    device.lastSeen = Date()
                    if raw == device.onURL { device.isOn = true }
                    if raw == device.offURL { device.isOn = false }
                    store.update(device)
                case .failure(let err):
                    statusMessage = err.localizedDescription
                }
            }
        }
    }
}