import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var settings: SyncSettings
    @EnvironmentObject var sync: SyncService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $settings.serverURL, prompt: Text("https://nas.example.com/dav"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $settings.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $settings.password)
                    TextField("Remote folder", text: $settings.remoteFolder, prompt: Text("Grimoire"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("NAS WebDAV").foregroundStyle(GrimoireTheme.crimsonBright)
                } footer: {
                    Text("Notes are stored on your NAS as Markdown files, one per note, inside the remote folder. The password is kept in the iOS Keychain.")
                        .foregroundStyle(GrimoireTheme.muted)
                }
                .listRowBackground(GrimoireTheme.panel)

                Section {
                    Toggle("Sync automatically", isOn: $settings.autoSync)
                        .tint(GrimoireTheme.crimson)
                    Button {
                        Task { @MainActor in
                            await sync.sync(store: store, settings: settings)
                        }
                    } label: {
                        HStack {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if sync.state == .syncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(sync.state == .syncing || !settings.isConfigured)
                } header: {
                    Text("Sync").foregroundStyle(GrimoireTheme.crimsonBright)
                } footer: {
                    Text("Syncs when the app opens and when you pull down on the list. The newest edit of a note wins; notes are only deleted on the NAS when you delete them here.")
                        .foregroundStyle(GrimoireTheme.muted)
                }
                .listRowBackground(GrimoireTheme.panel)

                Section {
                    statusRow
                    if !sync.summaryText.isEmpty {
                        Text(sync.summaryText)
                            .foregroundStyle(GrimoireTheme.muted)
                    }
                    if let last = sync.lastSyncDate {
                        HStack {
                            Text("Last sync")
                            Spacer()
                            Text(last.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(GrimoireTheme.muted)
                        }
                    }
                    Button("Reset sync memory") {
                        sync.resetState()
                    }
                    .foregroundStyle(GrimoireTheme.crimsonBright)
                } header: {
                    Text("Status").foregroundStyle(GrimoireTheme.crimsonBright)
                }
                .listRowBackground(GrimoireTheme.panel)

                Section {
                    HStack {
                        Text("Notes")
                        Spacer()
                        Text("\(store.notes.count)")
                            .foregroundStyle(GrimoireTheme.muted)
                    }
                    HStack {
                        Text("Folders")
                        Spacer()
                        Text("\(store.folders.count)")
                            .foregroundStyle(GrimoireTheme.muted)
                    }
                } header: {
                    Text("Library").foregroundStyle(GrimoireTheme.crimsonBright)
                }
                .listRowBackground(GrimoireTheme.panel)
            }
            .foregroundStyle(GrimoireTheme.bone)
            .scrollContentBackground(.hidden)
            .background(GrimoireBackground())
            .navigationTitle("Altar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GrimoireTheme.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch sync.state {
        case .idle:
            Text(settings.isConfigured ? "Ready to sync." : "Enter the server URL and username to enable sync.")
                .foregroundStyle(GrimoireTheme.muted)
        case .syncing:
            Text("Syncing…")
                .foregroundStyle(GrimoireTheme.muted)
        case .success(let date):
            Label("Synced " + Fmt.relative(date), systemImage: "checkmark.circle")
                .foregroundStyle(GrimoireTheme.bone)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(GrimoireTheme.crimsonBright)
        }
    }
}
