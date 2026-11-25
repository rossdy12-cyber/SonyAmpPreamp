import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmForget = false
    var body: some View {
        NavigationStack {
            List {
                Section("Bridge") {
                    LabeledContent("Status", value: model.connected ? "Connected" : "Offline")
                    if let status = model.status {
                        LabeledContent("Host", value: status.name)
                        LabeledContent("Bridge version", value: status.version)
                    }
                    if !model.endpoint.isEmpty { Text(model.endpoint).font(.caption.monospaced()).textSelection(.enabled) }
                    Button("Edit connection") { model.showSettings = true }
                    Button(model.isConnecting ? "Connecting…" : "Reconnect") { Task { await model.connect() } }
                        .disabled(model.isConnecting || model.endpoint.isEmpty)
                }
                Section("Execution") {
                    Label("Your phone is a remote control. Code executes on the bridge host, not iOS.", systemImage: "server.rack")
                    Label("Tasks keep running if you switch apps or lose signal. Reconnect to read saved logs.", systemImage: "arrow.triangle.2.circlepath")
                    Label("Agents use their existing host logins and configured tool permissions. Permission bypass is not enabled by ForgeLink.", systemImage: "checkmark.shield")
                }.font(.subheadline)
                Section("Your IPA pipeline") {
                    Text("TrueNAS → GitHub macOS build → TrueNAS signing → Stark Store")
                        .font(.subheadline.monospaced())
                    Text("ForgeLink ships with an unsigned IPA build workflow. Signing certificates and upload tokens stay in your existing server and CI secret storage.")
                        .font(.caption).foregroundStyle(Forge.secondary)
                }
                Section("Security") {
                    Text("Use HTTPS for internet access. HTTP is only appropriate inside a trusted private VPN. Never port-forward the bridge’s HTTP port directly to the internet.")
                    Text("The pairing token is saved in this iPhone’s Keychain. Run logs and task prompts are stored on the host. Anyone with the pairing token can submit tasks to configured projects.")
                    Button("Forget bridge", role: .destructive) { confirmForget = true }
                }.font(.subheadline)
            }
            .scrollContentBackground(.hidden).background(Forge.background)
            .navigationTitle("Connection")
            .confirmationDialog("Forget this bridge?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget pairing", role: .destructive) { model.forget() }
            } message: { Text("Removes the saved pairing token from this phone. Running tasks on the bridge are not stopped.") }
        }
    }
}

struct PairingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var token = ""
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 36)).foregroundStyle(Forge.mint)
                        Text("Bring your workspace\nwith you.").font(.title.bold())
                        Text("Connect to ForgeLink Bridge on TrueNAS or your development computer.").font(.subheadline).foregroundStyle(Forge.secondary)
                    }.padding(.vertical, 10)
                }.listRowBackground(Color.clear)
                Section("Bridge address") {
                    TextField("https://forge.your-domain.com", text: $endpoint)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .textContentType(.URL)
                    Text("Use your HTTPS reverse proxy or private VPN address. Include any reverse-proxy path prefix.")
                        .font(.caption).foregroundStyle(Forge.secondary)
                }
                Section("Pairing token") {
                    SecureField("Token from bridge .env", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("This is a separate bridge token—not your Apple, Claude, Google or DeepAI password. It is stored in Keychain.")
                        .font(.caption).foregroundStyle(Forge.secondary)
                }
                if endpoint.lowercased().hasPrefix("http://") {
                    Section {
                        Label("HTTP does not encrypt the token or code. Only use it within a trusted private VPN. Prefer HTTPS.", systemImage: "exclamationmark.shield")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                if let failure { Section { Text(failure).font(.caption).foregroundStyle(.orange) } }
                Section {
                    Button {
                        Task {
                            await model.connect(ConnectionSettings(endpoint: endpoint, token: token.trimmingCharacters(in: .whitespacesAndNewlines)))
                            if model.showSettings { failure = model.error; model.error = nil }
                        }
                    } label: {
                        HStack { Spacer(); if model.isConnecting { ProgressView() }; Text(model.isConnecting ? "Connecting…" : "Connect securely").bold(); Spacer() }
                    }.disabled(model.isConnecting || endpoint.isEmpty || token.isEmpty)
                }
                Section("First time?") {
                    Text("On your host, open the bridge folder, run npm run init, configure project paths and agent commands, then npm start. See README.md for the TrueNAS and DeepAI webhook setup.")
                        .font(.caption).foregroundStyle(Forge.secondary)
                }
            }.scrollContentBackground(.hidden).background(Forge.background)
                .navigationTitle("Pair a bridge").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Later") { dismiss() }.disabled(model.isConnecting) } }
                .interactiveDismissDisabled(model.isConnecting)
                .onAppear { endpoint = model.endpoint; token = model.token }
        }
    }
}
