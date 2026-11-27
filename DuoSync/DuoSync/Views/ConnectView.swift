import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var sync: SyncManager
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var port = "5391"
    @State private var token = ""
    @State private var phase: Phase = .idle

    private enum Phase {
        case idle
        case connecting
        case choosing(name: String, hostID: String?, shares: [ShareInfo])
    }

    @State private var error: String?
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                switch phase {
                case .idle, .connecting:
                    connectionForm
                case .choosing(let name, _, let shares):
                    sharePicker(name: name, shares: shares)
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Theme.err)
                    }
                }
            }
            .screenBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("Connect a PC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch phase {
                    case .idle, .connecting:
                        Button("Connect") { connect() }
                            .disabled(!canConnect || isConnecting)
                    case .choosing:
                        Button("Add") { finish() }
                            .disabled(selected.isEmpty)
                    }
                }
            }
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var connectionForm: some View {
        Section {
            TextField("Tailscale address", text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 15, design: .monospaced))
            TextField("Port", text: $port)
                .keyboardType(.numberPad)
        } header: {
            Text("PC address")
        } footer: {
            Text("The name or 100.x address from the Tailscale app, e.g. 100.64.0.8 or aether-pc.")
        }

        Section {
            SecureField("Pairing token", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13, design: .monospaced))
        } header: {
            Text("Token")
        } footer: {
            Text("In DuoSync on the PC, press “Copy token” and paste it here. It is kept in the iOS keychain.")
        }

        if isConnecting {
            Section {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Reaching \(address)…").foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func sharePicker(name: String, shares: [ShareInfo]) -> some View {
        Section {
            ForEach(shares) { share in
                Button {
                    if selected.contains(share.id) {
                        selected.remove(share.id)
                    } else {
                        selected.insert(share.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected.contains(share.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(share.id) ? Theme.accent : Theme.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(share.name)
                                .foregroundStyle(.primary)
                            if !share.isWritable {
                                Text("read-only on the PC")
                                    .font(.caption)
                                    .foregroundStyle(Theme.warn)
                            }
                        }
                        Spacer()
                    }
                }
            }
        } header: {
            Text("Folders on \(name)")
        } footer: {
            Text("Each folder is downloaded into Files → On My iPhone → DuoSync → Sync, and kept in step from there.")
        }
    }

    // MARK: - Actions

    private var isConnecting: Bool {
        if case .connecting = phase { return true }
        return false
    }

    private var canConnect: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty && !token.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func connect() {
        error = nil
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        let portValue = Int(port) ?? 5391
        guard let baseURL = machineURL(trimmed, port: portValue) else {
            error = "That address does not look right."
            return
        }
        let secret = token.trimmingCharacters(in: .whitespaces)

        phase = .connecting
        Task {
            do {
                let info = try await DuoSyncClient(baseURL: baseURL, token: secret).ping()
                let shares = info.shares ?? []
                if shares.isEmpty {
                    phase = .idle
                    error = "That PC has no folders shared yet. Add one in DuoSync on the PC first."
                    return
                }
                selected = Set(shares.map(\.id))
                phase = .choosing(name: info.host.name, hostID: info.host.id, shares: shares)
            } catch {
                phase = .idle
                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func finish() {
        guard case .choosing(let name, let hostID, let shares) = phase else { return }
        let portValue = Int(port) ?? 5391
        let machine = store.upsertMachine(
            name: name,
            address: address.trimmingCharacters(in: .whitespaces),
            port: portValue,
            hostID: hostID,
            token: token.trimmingCharacters(in: .whitespaces)
        )
        for share in shares where selected.contains(share.id) {
            store.addPair(machineID: machine.id, share: share)
        }
        store.appendLog("Connected to \(name) with \(selected.count) folder(s)")
        dismiss()
        Task { await sync.syncAll() }
    }

    private func machineURL(_ address: String, port: Int) -> URL? {
        var host = address
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        var chosenPort = port
        if let colon = host.lastIndex(of: ":"), let explicit = Int(host[host.index(after: colon)...]) {
            chosenPort = explicit
            host = String(host[..<colon])
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !host.isEmpty else { return nil }
        return URL(string: "http://\(host):\(chosenPort)")
    }
}
