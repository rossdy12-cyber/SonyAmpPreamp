import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var session: Session

    @State private var server: String = Credentials.serverURL.isEmpty
        ? "https://navidrome.nas-server.co.uk/tether"
        : Credentials.serverURL
    @State private var code = ""
    @State private var name = ""
    @State private var color = Theme.palette[0]
    @State private var busy = false
    @State private var errorText: String?

    private var canJoin: Bool {
        !busy
            && !server.trimmingCharacters(in: .whitespaces).isEmpty
            && !code.trimmingCharacters(in: .whitespaces).isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 54))
                        .foregroundColor(Theme.crimsonBright)
                    Text("Tether")
                        .font(Theme.serif(40))
                        .foregroundColor(Theme.bone)
                    Text("Private location sharing for the people you trust. Your locations stay on your own server.")
                        .foregroundColor(Theme.muted)
                }
                .padding(.top, 40)

                TetherField(title: "Server address", text: $server, keyboard: .URL)
                TetherField(title: "Invite code", text: $code, capitalization: .characters)
                TetherField(title: "Your name", text: $name, capitalization: .words)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your colour")
                        .font(.footnote)
                        .foregroundColor(Theme.muted)
                    ColorPicker10(selection: $color)
                }

                if let errorText = errorText {
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundColor(Color.red)
                }

                Button {
                    join()
                } label: {
                    if busy {
                        ProgressView().tint(Color.white)
                    } else {
                        Text("Join the circle")
                    }
                }
                .buttonStyle(CrimsonButtonStyle())
                .disabled(!canJoin)
                .opacity(canJoin ? 1 : 0.5)

                Text("Ask whoever runs the server for an invite code. Tether will then ask for location access: choose \"Always\" so your circle can see you when the app is closed.")
                    .font(.footnote)
                    .foregroundColor(Theme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func join() {
        errorText = nil
        busy = true
        let serverText = server
        let codeText = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameText = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let colorText = color
        Task {
            do {
                try await session.join(server: serverText, code: codeText, name: nameText, color: colorText)
            } catch {
                errorText = error.localizedDescription
            }
            busy = false
        }
    }
}
