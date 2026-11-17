import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sync: JarvisSyncManager
    @State private var quickApp: String = "WhatsApp"
    @State private var quickSender: String = ""
    @State private var quickBody: String = ""
    @State private var speakOnPc: Bool = true

    private let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
    private let bgDark = Color(red: 0.04, green: 0.01, blue: 0.02)

    var body: some View {
        TabView {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    // Connection & Telemetry Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(sync.isConnected ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)
                            Text("J.A.R.V.I.S. // iOS NEURAL UPLINK")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundColor(crimson)
                            Spacer()
                            Text("BAT: \(sync.batteryPercent)% (\(sync.batteryState))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.white)
                        }

                        Text(sync.statusMessage)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)

                        HStack(spacing: 8) {
                            TextField("http://192.168.0.185:7777", text: $sync.serverHost)
                                .font(.system(.caption, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                            Button("SYNC") {
                                Task { await sync.sendHeartbeatAndFetchFeed() }
                            }
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(crimson)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }

                        HStack(spacing: 8) {
                            Button("LAN (192.168.0.185)") {
                                sync.serverHost = "http://192.168.0.185:7777"
                                Task { await sync.sendHeartbeatAndFetchFeed() }
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .buttonStyle(.bordered)
                            .tint(crimson)

                            Button("TAILSCALE (100.76.215.23)") {
                                sync.serverHost = "http://100.76.215.23:7777"
                                Task { await sync.sendHeartbeatAndFetchFeed() }
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .buttonStyle(.bordered)
                            .tint(.cyan)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.75))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.5), lineWidth: 1))

                    // Quick Actions & Remote PC Controls
                    VStack(alignment: .leading, spacing: 10) {
                        Text("01 // BEAM TO PC & REMOTE COMMANDS")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(crimson)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            Button {
                                Task { await sync.pushClipboardToPc() }
                            } label: {
                                Label("BEAM CLIPBOARD", systemImage: "doc.on.clipboard")
                                    .font(.system(size: 11, design: .monospaced).weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .background(crimson.opacity(0.22))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }

                            Button {
                                Task {
                                    _ = await sync.pushNotificationToJarvis(
                                        app: "iPhone Ping",
                                        title: "Find My PC / Alert",
                                        body: "Ross pinged J.A.R.V.I.S. from iPhone.",
                                        category: "alert",
                                        speakOnPc: true
                                    )
                                }
                            } label: {
                                Label("PING J.A.R.V.I.S.", systemImage: "wave.3.right")
                                    .font(.system(size: 11, design: .monospaced).weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .background(crimson.opacity(0.22))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }

                            Button {
                                Task { await sync.sendPcCommand("lock") }
                            } label: {
                                Label("LOCK PC SCREEN", systemImage: "lock.shield")
                                    .font(.system(size: 11, design: .monospaced).weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .background(Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }

                            Button {
                                Task { await sync.sendPcCommand("unlock") }
                            } label: {
                                Label("UNLOCK PC", systemImage: "lock.open")
                                    .font(.system(size: 11, design: .monospaced).weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.75))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.4), lineWidth: 1))

                    // Manual / Test Notification Dispatcher
                    VStack(alignment: .leading, spacing: 8) {
                        Text("02 // SEND ALERT OR MESSAGE TO J.A.R.V.I.S. HUD")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(crimson)

                        Picker("App", selection: $quickApp) {
                            Text("WhatsApp").tag("WhatsApp")
                            Text("iMessage").tag("iMessage")
                            Text("Phone Call").tag("Phone Call")
                            Text("Instagram").tag("Instagram")
                            Text("iPhone Note").tag("iPhone Note")
                        }
                        .pickerStyle(.segmented)

                        TextField("Sender / Title (e.g. Lauren)", text: $quickSender)
                            .font(.system(.caption, design: .monospaced))
                            .textFieldStyle(.roundedBorder)

                        TextField("Notification or Message text...", text: $quickBody)
                            .font(.system(.caption, design: .monospaced))
                            .textFieldStyle(.roundedBorder)

                        Toggle("Announce aloud on J.A.R.V.I.S. speakers", isOn: $speakOnPc)
                            .font(.system(.caption2, design: .monospaced))
                            .tint(crimson)

                        Button {
                            guard !quickTitleOrDefault.isEmpty else { return }
                            Task {
                                _ = await sync.pushNotificationToJarvis(
                                    app: quickApp,
                                    title: quickTitleOrDefault,
                                    body: quickBody,
                                    category: "message",
                                    speakOnPc: speakOnPc
                                )
                                quickBody = ""
                            }
                        } label: {
                            Text("⚡ BEAM TO J.A.R.V.I.S. 3-MONITOR HUD")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(crimson)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.75))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.4), lineWidth: 1))

                    // Live Synced Notifications Feed
                    VStack(alignment: .leading, spacing: 8) {
                        Text("03 // RECENT SYNCED iPHONE NOTIFICATIONS (\(sync.recentNotifications.count))")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(crimson)

                        if sync.recentNotifications.isEmpty {
                            Text("No notifications synced yet.")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.gray)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(sync.recentNotifications) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("[\(item.app.uppercased())]")
                                            .font(.system(size: 10, design: .monospaced).weight(.bold))
                                            .foregroundColor(crimson)
                                        Text(item.title)
                                            .font(.system(size: 12, design: .monospaced).weight(.bold))
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text(item.timestamp)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.gray)
                                    }
                                    if !item.body.isEmpty {
                                        Text(item.body)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.85))
                                    }
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.75))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.4), lineWidth: 1))
                }
                .padding()
            }
            .background(bgDark.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .tabItem {
            Label("SYNC", systemImage: "iphone.radiowaves.left.and.right")
        }

        DeepAiChatView()
            .tabItem {
                Label("DEEPAI", systemImage: "bubble.left.and.text.bubble.right")
            }
        }
        .accentColor(crimson)
    }

    private var quickTitleOrDefault: String {
        quickSender.trimmingCharacters(in: .whitespaces).isEmpty ? quickApp : quickSender
    }
}

// MARK: - DeepAI Code chat (talk to the PC agent from the phone)

struct DeepAiChatView: View {
    @EnvironmentObject var sync: JarvisSyncManager
    @State private var input: String = ""
    @State private var pollTimer: Timer? = nil

    private let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
    private let bgDark = Color(red: 0.04, green: 0.01, blue: 0.02)

    private func bubble(_ m: DeepAiMessage) -> some View {
        let isUser = m.role == "USER"
        let labelColor: Color = isUser ? Color(red: 1.0, green: 0.7, blue: 0.75) : crimson
        let bubbleBg: Color = isUser ? Color(red: 0.35, green: 0.05, blue: 0.11) : Color.white.opacity(0.06)
        let borderOpacity: Double = isUser ? 0.5 : 0.25
        let stamp = m.time.count >= 5 ? String(m.time.suffix(8).prefix(5)) : ""
        return VStack(alignment: .leading, spacing: 3) {
            Text(isUser ? "YOU" : "DEEPAI")
                .font(.system(size: 9, design: .monospaced).weight(.bold))
                .foregroundColor(labelColor)
            Text(m.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .textSelection(.enabled)
            if !stamp.isEmpty {
                Text(stamp)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(9)
        .background(bubbleBg)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(crimson.opacity(borderOpacity), lineWidth: 1))
        .cornerRadius(9)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status bar
                HStack {
                    Circle()
                        .fill(sync.deepAiWorking ? Color.orange : Color.green)
                        .frame(width: 9, height: 9)
                    Text(sync.deepAiWorking ? "WORKING" : (sync.deepAiStatus.isEmpty ? "READY" : sync.deepAiStatus))
                        .font(.system(size: 10, design: .monospaced).weight(.bold))
                        .foregroundColor(sync.deepAiWorking ? .orange : .cyan)
                    Spacer()
                    if !sync.deepAiModel.isEmpty {
                        Text(sync.deepAiModel.uppercased())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.7))

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if sync.deepAiMessages.isEmpty {
                                Text("DeepAI Code agent on your PC. Send coding or system instructions — replies stream back here.\n\nModel selection lives in MK-VII tab 09 on the PC.")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .padding(.top, 30)
                            }
                            ForEach(sync.deepAiMessages) { m in
                                bubble(m)
                                    .id(m.id)
                            }
                            if sync.deepAiWorking {
                                HStack(spacing: 6) {
                                    ProgressView().tint(crimson)
                                    Text("agent working…")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                                .padding(9)
                            }
                        }
                        .padding(10)
                    }
                    .onChange(of: sync.deepAiMessages) { _ in
                        if let last = sync.deepAiMessages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }

                // Composer
                HStack(spacing: 8) {
                    TextField("Message DeepAI Code…", text: $input, axis: .vertical)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        input = ""
                        Task { await sync.sendDeepAi(text) }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .padding(10)
                            .background(crimson)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(sync.deepAiWorking)
                    .opacity(sync.deepAiWorking ? 0.5 : 1.0)
                }
                .padding(10)
                .background(Color.black.opacity(0.8))
            }
            .background(bgDark.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .onAppear {
            Task { await sync.pollDeepAiState() }
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task { @MainActor in await sync.pollDeepAiState() }
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}
