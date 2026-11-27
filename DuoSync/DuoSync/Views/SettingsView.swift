import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var sync: SyncManager
    @Environment(\.dismiss) private var dismiss

    @State private var ignoreText = ""
    @State private var editingIgnore = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.machines) { machine in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                StatusDot(state: machine.lastSeen == nil ? .error : .ok)
                                Text(machine.name).font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text("\(store.pairs(for: machine.id).count) folder(s)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Text(machine.displayAddress)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                            Text(machine.lastSeen == nil ? "No answer yet" : "Seen \(relativeTime(machine.lastSeen))")
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }
                        .listRowBackground(Theme.panel)
                        .swipeActions {
                            Button(role: .destructive) {
                                store.removeMachine(machine.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("PCs")
                } footer: {
                    Text("Swipe a PC to remove it and its folders. Files already on this iPhone are kept.")
                }

                Section {
                    Toggle("Sync in the background", isOn: Binding(
                        get: { store.backgroundSync },
                        set: { store.backgroundSync = $0; store.save() }
                    ))
                    .listRowBackground(Theme.panel)
                } header: {
                    Text("Sync")
                } footer: {
                    Text("iOS decides when to grant background time. The app also syncs whenever it opens and while it is on screen.")
                }

                Section {
                    if editingIgnore {
                        TextEditor(text: $ignoreText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 140)
                            .listRowBackground(Theme.panel)
                        HStack {
                            Button("Cancel") {
                                editingIgnore = false
                            }
                            Spacer()
                            Button("Save patterns") {
                                let patterns = ignoreText
                                    .split(separator: "\n")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                                store.ignorePatterns = patterns
                                store.save()
                                editingIgnore = false
                                store.notify("Ignore patterns saved")
                            }
                            .disabled(ignoreText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .listRowBackground(Theme.panel)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(store.ignorePatterns, id: \.self) { pattern in
                                Text(pattern)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .listRowBackground(Theme.panel)
                        Button("Edit patterns") {
                            ignoreText = store.ignorePatterns.joined(separator: "\n")
                            editingIgnore = true
                        }
                        .listRowBackground(Theme.panel)
                    }
                } header: {
                    Text("Ignored files")
                } footer: {
                    Text("Keep these identical to the list in DuoSync on the PC, otherwise the two sides disagree about which files exist.")
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Protocol", value: "1 (TCP over Tailscale)")
                    LabeledContent("Sync folder", value: "Files → DuoSync → Sync")
                    if let url = URL(string: "https://tailscale.com/download/ios") {
                        Link("Get Tailscale", destination: url)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("DuoSync keeps folders in step with your Windows PCs directly over the tailnet. Nothing is uploaded to a third party, and each PC still has to know this iPhone's pairing token — every request is refused without it.")
                }
            }
            .screenBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
