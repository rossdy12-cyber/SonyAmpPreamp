import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var ha: HomeAssistantService
    @Binding var haBaseURL: String
    @Binding var haToken: String
    @State private var newRoom = ""
    @State private var testMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()
                Form {
                    Section("Home Assistant Grimoire") {
                        TextField("Base URL (e.g. http://192.168.1.50:8123)", text: $haBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("Long-Lived Access Token", text: $haToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Test & Summon Entities") {
                            testMessage = "Summoning..."
                            ha.fetchStates(baseURL: haBaseURL, token: haToken)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                if let err = ha.lastError {
                                    testMessage = err
                                } else {
                                    testMessage = "Summoned \(ha.entities.count) entities."
                                }
                            }
                        }
                        .foregroundColor(Theme.crimsonBright)
                        if !testMessage.isEmpty {
                            Text(testMessage)
                                .font(.footnote)
                                .foregroundColor(Theme.muted)
                        }
                    }

                    Section("Chambers / Rooms") {
                        ForEach(store.rooms, id: \.self) { room in
                            HStack {
                                Text(room)
                                    .foregroundColor(Theme.bone)
                                Spacer()
                                Text("\(store.devices(in: room).count)")
                                    .foregroundColor(Theme.muted)
                            }
                        }
                        HStack {
                            TextField("New chamber name", text: $newRoom)
                            Button("Add") {
                                let trimmed = newRoom.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                store.ensureRoom(trimmed)
                                newRoom = ""
                            }
                            .foregroundColor(Theme.crimsonBright)
                        }
                    }

                    Section("About Coven") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coven v1.0.0")
                                .font(Theme.serif(18, weight: .semibold))
                                .foregroundColor(Theme.bone)
                            Text("A gothic home automation grimoire. Add devices by IP/HTTP, discover devices on your local network, or bind Home Assistant to command every spirit in your domain.")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.muted)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Rites")
        }
    }
}