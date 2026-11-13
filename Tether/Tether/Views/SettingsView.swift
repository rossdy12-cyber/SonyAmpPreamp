import SwiftUI
import UIKit
import CoreLocation
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var engine: LocationEngine
    @EnvironmentObject var notifier: Notifier

    @State private var name = ""
    @State private var color = Theme.palette[0]
    @State private var localAlerts = Credentials.localAlerts
    @State private var pending = 0
    @State private var confirmLeave = false
    @State private var savingProfile = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TetherBackground()
                List {
                    profileSection
                    sharingSection
                    permissionSection
                    notificationSection
                    serverSection
                    aboutSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Leave the circle?",
                isPresented: $confirmLeave,
                titleVisibility: .visible
            ) {
                Button("Leave and delete my history", role: .destructive) {
                    Task { await session.leaveCircle() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your location history is deleted from the server and you will need a new invite code to rejoin.")
            }
        }
        .task {
            if let me = session.me {
                name = me.name
                color = me.color
            }
            pending = await UploadQueue.shared.pendingCount
            notifier.refreshStatus()
        }
        .onChange(of: session.me?.id) { _, _ in
            if let me = session.me {
                name = me.name
                color = me.color
            }
        }
    }

    // MARK: Sections

    private var profileSection: some View {
        Section("You") {
            HStack {
                if let me = session.me {
                    MemberAvatar(member: me, size: 40)
                }
                TextField("Your name", text: $name)
                    .textInputAutocapitalization(.words)
                    .foregroundColor(Theme.bone)
            }
            .listRowBackground(Theme.panel)

            ColorPicker10(selection: $color)
                .padding(.vertical, 4)
                .listRowBackground(Theme.panel)

            Button {
                Task {
                    savingProfile = true
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = await session.updateProfile(name: trimmed.isEmpty ? nil : trimmed, color: color)
                    savingProfile = false
                }
            } label: {
                Text(savingProfile ? "Saving..." : "Save name and colour")
                    .foregroundColor(Theme.crimsonBright)
            }
            .disabled(savingProfile)
            .listRowBackground(Theme.panel)
        }
    }

    private var sharingSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { session.paused },
                set: { value in
                    session.paused = value
                    Task { await session.setPaused(value) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pause sharing")
                        .foregroundColor(Theme.bone)
                    Text("Your circle sees \"paused\" and nothing is recorded.")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }
            }
            .tint(Theme.crimson)
            .listRowBackground(Theme.panel)

            Picker("Sharing mode", selection: $engine.mode) {
                ForEach(SharingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Theme.panel)

            Text(engine.mode.detail)
                .font(.caption)
                .foregroundColor(Theme.muted)
                .listRowBackground(Theme.panel)

            if pending > 0 {
                Text("\(pending) location\(pending == 1 ? "" : "s") waiting to upload")
                    .font(.caption)
                    .foregroundColor(Theme.muted)
                    .listRowBackground(Theme.panel)
            }
        } header: {
            Text("Sharing")
        }
    }

    private var permissionSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: engine.hasAlways ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(engine.hasAlways ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(permissionTitle)
                        .foregroundColor(Theme.bone)
                    Text(permissionDetail)
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }
            }
            .listRowBackground(Theme.panel)

            if !engine.hasAlways {
                Button {
                    if engine.authStatus == .notDetermined || engine.authStatus == .authorizedWhenInUse {
                        engine.requestAlways()
                    } else {
                        openSettings()
                    }
                } label: {
                    Text(engine.authStatus == .notDetermined || engine.authStatus == .authorizedWhenInUse
                         ? "Allow location access"
                         : "Open iOS Settings")
                        .foregroundColor(Theme.crimsonBright)
                }
                .listRowBackground(Theme.panel)

                if engine.authStatus == .authorizedWhenInUse {
                    Button {
                        openSettings()
                    } label: {
                        Text("Open iOS Settings to choose Always")
                            .foregroundColor(Theme.crimsonBright)
                    }
                    .listRowBackground(Theme.panel)
                }
            }
        } header: {
            Text("Location access")
        } footer: {
            Text("Choose Location > Always, with Precise Location on, so Tether keeps sharing when the app is closed.")
        }
    }

    private var permissionTitle: String {
        switch engine.authStatus {
        case .authorizedAlways: return "Always: sharing works in the background"
        case .authorizedWhenInUse: return "Only while you use the app"
        case .denied: return "Location is turned off"
        case .restricted: return "Location is restricted on this phone"
        default: return "Location access not chosen yet"
        }
    }

    private var permissionDetail: String {
        switch engine.authStatus {
        case .authorizedAlways: return "Your circle sees you even when Tether is closed."
        case .authorizedWhenInUse: return "Your circle only sees you while Tether is open. Change this to Always."
        case .denied: return "Turn it on in iOS Settings so you can be shared."
        case .restricted: return "A restriction on this phone blocks location."
        default: return "Tether needs it to share where you are."
        }
    }

    private var notificationSection: some View {
        Section {
            HStack {
                Text("Notifications")
                    .foregroundColor(Theme.bone)
                Spacer()
                Text(notificationStatusText)
                    .foregroundColor(Theme.muted)
            }
            .listRowBackground(Theme.panel)

            if notifier.status == .notDetermined {
                Button {
                    notifier.requestAuthorization()
                } label: {
                    Text("Turn on notifications")
                        .foregroundColor(Theme.crimsonBright)
                }
                .listRowBackground(Theme.panel)
            } else if notifier.status == .denied {
                Button {
                    openSettings()
                } label: {
                    Text("Open iOS Settings")
                        .foregroundColor(Theme.crimsonBright)
                }
                .listRowBackground(Theme.panel)
            }

            Toggle(isOn: $localAlerts) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local alerts")
                        .foregroundColor(Theme.bone)
                    Text("Alerts when Tether wakes in the background. Turn off once push notifications work, to avoid doubles.")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }
            }
            .tint(Theme.crimson)
            .onChange(of: localAlerts) { _, value in
                Credentials.localAlerts = value
            }
            .listRowBackground(Theme.panel)
        } header: {
            Text("Notifications")
        } footer: {
            Text("Instant alerts when the app is closed need the server's push relay and a build signed with your paid developer profile.")
        }
    }

    private var notificationStatusText: String {
        switch notifier.status {
        case .authorized: return "On"
        case .provisional: return "Quiet"
        case .denied: return "Off"
        case .ephemeral: return "Temporary"
        default: return "Not asked"
        }
    }

    private var serverSection: some View {
        Section("Server") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Address")
                    .font(.caption)
                    .foregroundColor(Theme.muted)
                Text(Credentials.serverURL)
                    .foregroundColor(Theme.bone)
                    .textSelection(.enabled)
            }
            .listRowBackground(Theme.panel)

            Button {
                Task { await checkConnection() }
            } label: {
                Text("Check connection")
                    .foregroundColor(Theme.crimsonBright)
            }
            .listRowBackground(Theme.panel)

            Button(role: .destructive) {
                confirmLeave = true
            } label: {
                Text("Leave the circle")
            }
            .listRowBackground(Theme.panel)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                    .foregroundColor(Theme.bone)
                Spacer()
                Text(version)
                    .foregroundColor(Theme.muted)
            }
            .listRowBackground(Theme.panel)
        }
    }

    // MARK: Actions

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func checkConnection() async {
        guard let base = APIClient.normalize(Credentials.serverURL) else {
            session.showMessage("The server address isn't valid.")
            return
        }
        do {
            _ = try await APIClient(base: base, token: nil).raw("GET", "/health", timeout: 10)
            session.showMessage("Connected to the server.")
        } catch {
            session.show(error)
        }
    }
}
