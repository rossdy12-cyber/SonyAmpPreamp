import SwiftUI

struct KeepwatchRootView: View {
    @EnvironmentObject private var store: KeepwatchStore
    @State private var selectedTab: Int = 0

    private let cyanAccent = Color(red: 0.22, green: 0.78, blue: 0.98)

    var body: some View {
        TabView(selection: $selectedTab) {
            TrueNASInfrastructureView()
                .tabItem {
                    Label("TrueNAS & Docker", systemImage: "server.rack")
                }
                .tag(0)

            NetRadarMatrixView()
                .tabItem {
                    Label("NetRadar", systemImage: "dot.radiowaves.left.and.right")
                }
                .tag(1)

            SideStoreAndCIView()
                .tabItem {
                    Label("SideStore & CI", systemImage: "shippingbox.and.arrow.backward.fill")
                }
                .tag(2)

            AntigravityOpsView()
                .tabItem {
                    Label("Antigravity Ops", systemImage: "cpu.fill")
                }
                .tag(3)
        }
        .tint(cyanAccent)
    }
}

enum KWTheme {
    static let bg = Color(red: 0.04, green: 0.06, blue: 0.10)
    static let card = Color(red: 0.09, green: 0.12, blue: 0.18)
    static let cardElevated = Color(red: 0.12, green: 0.16, blue: 0.24)
    static let cyan = Color(red: 0.22, green: 0.78, blue: 0.98)
    static let green = Color(red: 0.18, green: 0.86, blue: 0.50)
    static let amber = Color(red: 0.98, green: 0.70, blue: 0.18)
    static let red = Color(red: 0.96, green: 0.32, blue: 0.36)
    static let purple = Color(red: 0.68, green: 0.52, blue: 0.98)
}

// MARK: - TAB 1: TRUENAS INFRASTRUCTURE, ZFS & DOCKER CONTROL
struct TrueNASInfrastructureView: View {
    @EnvironmentObject private var store: KeepwatchStore
    @State private var containerSearch: String = ""

    private var filteredContainers: [DockerContainerItem] {
        let q = containerSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return store.containers }
        return store.containers.filter { $0.name.lowercased().contains(q) || $0.image.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KWTheme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if !store.lastActionBanner.isEmpty {
                            actionBanner
                        }
                        systemVitalsCard
                        zfsStoragePoolCard
                        systemdDaemonsCard
                        dockerContainersCard
                    }
                    .padding(16)
                }
                .refreshable {
                    await store.refreshAll()
                }
            }
            .navigationTitle("Keepwatch Ops v2.0")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        if store.isLoading {
                            ProgressView().tint(KWTheme.cyan)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(KWTheme.cyan)
                        }
                    }
                }
            }
        }
    }

    private var actionBanner: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(KWTheme.green)
            Text(store.lastActionBanner)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                store.lastActionBanner = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.gray)
            }
        }
        .padding(12)
        .background(KWTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private var systemVitalsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(KWTheme.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.hostname)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Uptime: \(store.uptime) • Updated \(store.timestamp)")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
                Spacer()
                Text("ONLINE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(KWTheme.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(KWTheme.green)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                vitalTile(label: "CPU Load Avg", value: store.loadAvg.components(separatedBy: " ").first ?? store.loadAvg, sub: store.loadAvg, color: KWTheme.cyan)
                vitalTile(label: "Memory Used", value: "\(store.memPercent)%", sub: String(format: "%.1f / %.1f GB", store.memUsedGB, store.memTotalGB), color: store.memPercent > 92 ? KWTheme.amber : KWTheme.green)
                vitalTile(label: "CPU Thermal", value: "\(store.cpuTempC)°C", sub: "Core Package", color: store.cpuTempC > 75 ? KWTheme.red : KWTheme.green)
            }
        }
        .padding(16)
        .background(KWTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func vitalTile(label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(sub)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.gray)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(KWTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private var zfsStoragePoolCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("ZFS STORAGE_POOL HEALTH", systemImage: "internaldrive.fill")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(KWTheme.purple)
                Spacer()
                Text("\(store.poolUsedGB) GB used / \(store.poolFreeGB) GB free (\(store.poolPercent)%)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            ProgressView(value: Double(store.poolPercent), total: 100.0)
                .tint(KWTheme.purple)
        }
        .padding(16)
        .background(KWTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var systemdDaemonsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRUENAS SYSTEMD & SIDESTORE DAEMONS")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(KWTheme.cyan)

            ForEach(store.services) { svc in
                let isActive = (svc.status == "active")
                HStack {
                    Circle()
                        .fill(isActive ? KWTheme.green : KWTheme.red)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(svc.label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(svc.name) • \(svc.status.uppercased())")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.gray)
                    }
                    Spacer()
                    if svc.name == "sidestore-tun.service" || svc.name == "tailscaled.service" {
                        Button("Restart") {
                            Task { await store.performOpsAction(action: "restart_service", target: svc.name) }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(KWTheme.cyan.opacity(0.2), in: Capsule())
                        .foregroundStyle(KWTheme.cyan)
                    }
                }
                .padding(10)
                .background(KWTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(KWTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var dockerContainersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RUNNING DOCKER CONTAINERS (\(store.containers.count))")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(KWTheme.green)
                Spacer()
            }

            TextField("Filter containers (slskd, navidrome, lidarr, nightscout)...", text: $containerSearch)
                .textInputAutocapitalization(.never)
                .font(.system(size: 12))
                .padding(9)
                .background(KWTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)

            ForEach(filteredContainers) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(c.status) • \(c.image)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Restart") {
                        Task { await store.performOpsAction(action: "restart_container", target: c.name) }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(KWTheme.amber.opacity(0.2), in: Capsule())
                    .foregroundStyle(KWTheme.amber)
                }
                .padding(10)
                .background(KWTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(KWTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - TAB 2: NETRADAR (TAILSCALE & SERVICE LATENCY MATRIX)
struct NetRadarMatrixView: View {
    @EnvironmentObject private var store: KeepwatchStore

    var body: some View {
        NavigationStack {
            ZStack {
                KWTheme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("TAILSCALE & LAN LATENCY RADAR")
                                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(KWTheme.cyan)
                                Text("Tests live HTTP & Tailscale tunnel latency from your iPhone")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.gray)
                            }
                            Spacer()
                            Button {
                                Task { await store.runNetRadarSweep() }
                            } label: {
                                Label("Ping All", systemImage: "bolt.horizontal.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(KWTheme.cyan, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                        }
                        .padding(16)
                        .background(KWTheme.card, in: RoundedRectangle(cornerRadius: 18))

                        ForEach(store.radarNodes) { node in
                            HStack {
                                Circle()
                                    .fill(node.isOnline ? KWTheme.green : KWTheme.red)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(node.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text("\(node.category) • \(node.urlString)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.gray)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(node.statusText)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(node.isOnline ? KWTheme.green : KWTheme.amber)
                            }
                            .padding(14)
                            .background(KWTheme.card, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("NetRadar Mesh Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task { await store.runNetRadarSweep() }
            }
        }
    }
}

// MARK: - TAB 3: SIDESTORE & LIVECONTAINER REPO + CODEMAGIC CI CONTROLLER
struct SideStoreAndCIView: View {
    @EnvironmentObject private var store: KeepwatchStore
    @State private var showBuildLogSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                KWTheme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        codemagicCIControllerCard
                        repoAppsCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("SideStore & M2 CI")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showBuildLogSheet) {
                NavigationStack {
                    ScrollView {
                        Text(store.buildLogTail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(KWTheme.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .background(Color.black)
                    .navigationTitle("Codemagic M2 Build Log")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showBuildLogSheet = false }
                        }
                    }
                }
            }
        }
    }

    private var codemagicCIControllerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hammer.circle.fill")
                    .foregroundStyle(KWTheme.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CODEMAGIC APPLE M2 BUILD PIPELINE")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(KWTheme.purple)
                    Text("TrueNAS Smart Git HTTP → Codemagic M2 → Auto-Publish IPA")
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    Task { await store.performOpsAction(action: "trigger_codemagic") }
                } label: {
                    Label("Trigger M2 Build", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(KWTheme.purple, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }

                Button {
                    showBuildLogSheet = true
                } label: {
                    Label("View Build Log", systemImage: "terminal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(KWTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(KWTheme.cyan)
                }
            }

            if !store.lastActionBanner.isEmpty {
                Text(store.lastActionBanner)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(KWTheme.green)
            }
        }
        .padding(16)
        .background(KWTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var repoAppsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PUBLISHED SIDESTORE / LIVECONTAINER APPS (\(store.repoApps.count))")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundStyle(KWTheme.cyan)
                Spacer()
                if let url = URL(string: "livecontainer://source?url=https://navidrome.nas-server.co.uk/sidestore/source.json") {
                    Link("Add to LiveContainer", destination: url)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(KWTheme.green)
                }
            }

            ForEach(store.repoApps) { app in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(app.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                            Text("v\(app.version)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(KWTheme.cyan.opacity(0.2), in: Capsule())
                                .foregroundStyle(KWTheme.cyan)
                        }
                        Text(app.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                        Text("\(app.bundleIdentifier) • \(app.sizeBytes / 1024) KB")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.gray.opacity(0.8))
                    }
                    Spacer()
                    if let dl = URL(string: app.downloadURL) {
                        Link(destination: dl) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(KWTheme.green)
                        }
                    }
                }
                .padding(12)
                .background(KWTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(KWTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - TAB 4: ANTIGRAVITY OPS & SIDESTORE / TAILSCALE REFERENCE
struct AntigravityOpsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                KWTheme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        opsCard(
                            title: "SideStore 0.7.0 Tailscale Direct Mode (No LocalDevVPN App Needed)",
                            icon: "network.badge.shield.half.filled",
                            color: KWTheme.green,
                            items: [
                                "TrueNAS Service: sidestore-tun.service (Post-Init Script ID 6: /mnt/storage_pool/scripts/start-sidestore-tun.sh)",
                                "Reflects 10.7.0.1 and 10.7.1.1 over tailscale0 so iPhone usbmuxd refreshes over Tailscale.",
                                "In SideStore → Settings → Connection Configuration: set Use Local VPN = OFF and Remote Endpoint Device IP = 10.7.0.1."
                            ]
                        )

                        opsCard(
                            title: "Self-Hosted Git + Codemagic M2 CI Pipeline",
                            icon: "arrow.triangle.branch",
                            color: KWTheme.purple,
                            items: [
                                "Git Smart HTTP Repo: https://navidrome.nas-server.co.uk/sidestore/SonyAmpPreamp.git",
                                "Auto-Upload Endpoint: https://navidrome.nas-server.co.uk/sidestore-upload",
                                "SideStore & LiveContainer Source JSON: https://navidrome.nas-server.co.uk/sidestore/source.json"
                            ]
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Antigravity & Edge Notes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func opsCard(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            ForEach(items, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(color).frame(width: 6, height: 6).padding(.top, 6)
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(16)
        .background(KWTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}
