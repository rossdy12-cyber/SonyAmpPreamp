import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: Session
    @State private var server = ""
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(
                colors: [Color(hex: "2A060C"), Theme.bg],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 40)

                    Image(systemName: "eye.fill")
                        .font(.system(size: 64))
                        .foregroundColor(Theme.crimsonBright)
                        .shadow(color: Theme.crimson, radius: 18)

                    Text("RELIQUARY")
                        .font(Theme.title(34))
                        .tracking(7)
                        .foregroundColor(Theme.bone)

                    Text("Your Immich archive, kept in shadow")
                        .font(Theme.body(14))
                        .italic()
                        .foregroundColor(Theme.muted)

                    OrnateDivider().padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        label("Server address")
                        TextField("https://immich.example.com", text: $server)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .modifier(FieldStyle())

                        label("API key").padding(.top, 8)
                        SecureField("Paste your API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .modifier(FieldStyle())

                        Text("Create a key in Immich under Account Settings > API Keys, with all permissions enabled.")
                            .font(Theme.body(12))
                            .foregroundColor(Theme.muted)
                            .padding(.top, 4)
                    }

                    if let notice = session.notice {
                        Text(notice)
                            .font(Theme.body(13))
                            .foregroundColor(Theme.bone)
                            .multilineTextAlignment(.center)
                    }

                    if let errorText = errorText {
                        Text(errorText)
                            .font(Theme.body(13))
                            .foregroundColor(Theme.crimsonBright)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: connect) {
                        HStack {
                            if isConnecting {
                                ProgressView().tint(Theme.bone)
                            }
                            Text(isConnecting ? "Opening the vault..." : "Enter the Reliquary")
                                .font(Theme.title(17))
                        }
                        .foregroundColor(Theme.bone)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.crimson)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isConnecting || server.isEmpty || apiKey.isEmpty)
                    .opacity((server.isEmpty || apiKey.isEmpty) ? 0.5 : 1)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 26)
            }
        }
        .onAppear {
            if server.isEmpty { server = session.serverText }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .serif))
            .tracking(2)
            .foregroundColor(Theme.crimsonBright)
    }

    private func connect() {
        errorText = nil
        isConnecting = true
        let urlText = server
        let keyText = apiKey
        Task { @MainActor in
            do {
                try await session.connect(urlString: urlText, apiKey: keyText)
            } catch {
                errorText = error.localizedDescription
            }
            isConnecting = false
        }
    }
}

private struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.body(16))
            .foregroundColor(Theme.bone)
            .padding(12)
            .background(Theme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
