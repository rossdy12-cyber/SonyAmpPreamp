import SwiftUI

struct SettingsView: View {
    let client: ImmichClient
    @EnvironmentObject private var session: Session
    @State private var confirmLogout = false
    @State private var cacheCleared = false

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Server", client.baseURL.absoluteString)
                    row("Signed in as", session.userName ?? "...")
                } header: {
                    sectionTitle("Connection")
                }
                .listRowBackground(Theme.panel)

                Section {
                    Button {
                        ImmichClient.clearCaches()
                        cacheCleared = true
                    } label: {
                        HStack {
                            Text("Clear image cache")
                                .font(Theme.body(16))
                                .foregroundColor(Theme.bone)
                            Spacer()
                            if cacheCleared {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.crimsonBright)
                            }
                        }
                    }
                } header: {
                    sectionTitle("Storage")
                }
                .listRowBackground(Theme.panel)

                Section {
                    Button(role: .destructive) {
                        confirmLogout = true
                    } label: {
                        Text("Disconnect from server")
                            .font(Theme.body(16))
                            .foregroundColor(Theme.crimsonBright)
                    }
                } header: {
                    sectionTitle("Account")
                } footer: {
                    Text("Removes the saved API key from this iPhone. Your photos on the server are untouched.")
                        .font(Theme.body(12))
                        .foregroundColor(Theme.muted)
                }
                .listRowBackground(Theme.panel)

                Section {
                    row("Reliquary", versionText)
                } header: {
                    sectionTitle("About")
                }
                .listRowBackground(Theme.panel)
            }
            .scrollContentBackground(.hidden)
            .gothicBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Disconnect from this Immich server?",
                isPresented: $confirmLogout,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    session.logout()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.body(16))
                .foregroundColor(Theme.bone)
            Spacer()
            Text(value)
                .font(Theme.body(14))
                .foregroundColor(Theme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold, design: .serif))
            .tracking(2)
            .foregroundColor(Theme.crimsonBright)
    }
}
