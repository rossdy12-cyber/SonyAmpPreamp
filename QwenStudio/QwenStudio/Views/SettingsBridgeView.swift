import SwiftUI

struct SettingsBridgeView: View {
    @EnvironmentObject var store: StudioStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    stealthConfigCard
                    pcBridgeCard
                    clusterConfigCard
                    aboutCard
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 32)
            }
            .background(StudioTheme.bgDeep.ignoresSafeArea())
            .navigationTitle("GPU Link & Stealth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.lockStealthImmediately()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.slash.fill")
                            Text("Hide")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(StudioTheme.cyanGlow)
                    }
                }
            }
        }
    }

    private var stealthConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("STEALTH CAMOUFLAGE (COREDIAG DECOY)", systemImage: "eye.slash.circle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundColor(StudioTheme.emerald)
                Spacer()
                Button {
                    store.lockStealthImmediately()
                } label: {
                    Text("Lock Now")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(StudioTheme.crimson)
                        .clipShape(Capsule())
                }
            }

            Text("Disguises the app as 'CoreDiag' (System & Network Telemetry). Automatically hides the Studio whenever you swipe up or switch apps. To unlock from CoreDiag: hold 'CoreDiag v2.1 • KERNEL OK' for 1 second (Face ID) or enter your secret PIN in the Port box.")
                .font(.system(size: 11))
                .foregroundColor(StudioTheme.textSecondary)

            Toggle("Auto-Lock to CoreDiag on Launch & App Switch", isOn: $store.requireStealthOnLaunch)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(StudioTheme.textPrimary)
                .tint(StudioTheme.emerald)

            HStack {
                Text("Secret Port PIN:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(StudioTheme.textPrimary)
                TextField("2070", text: $store.stealthPin)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(StudioTheme.cyanGlow)
                    .padding(8)
                    .background(StudioTheme.bgDeep)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .studioCard(borderColor: StudioTheme.emerald.opacity(0.4))
    }

    private var pcBridgeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("HOME PC RTX 2070 SUPER BRIDGE", systemImage: "desktopcomputer")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundColor(StudioTheme.cyanGlow)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.pcOnline ? StudioTheme.emerald : StudioTheme.amber)
                        .frame(width: 8, height: 8)
                    Text(store.pcOnline ? "Connected" : "Standby")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(store.pcOnline ? StudioTheme.emerald : StudioTheme.amber)
                }
            }

            Text("Connect directly to your home desktop Qwen 2.1 Uncensored Studio to render on your local GPU (308-token CLIP + Regional Split-Latent Duo) or browse your PC gallery.")
                .font(.system(size: 12))
                .foregroundColor(StudioTheme.textSecondary)

            TextField("http://100.102.4.54:7865", text: $store.pcBaseURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(StudioTheme.textPrimary)
                .padding(10)
                .background(StudioTheme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                Button {
                    store.pcBaseURL = "http://100.102.4.54:7865"
                    store.saveSettings()
                } label: {
                    Text("Tailscale (100.102.4.54)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(StudioTheme.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    store.pcBaseURL = "http://192.168.1.10:7865"
                    store.saveSettings()
                } label: {
                    Text("Home LAN (192.168.1.10)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(StudioTheme.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Text("Detected Status:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(StudioTheme.textSecondary)
                Spacer()
                Text(store.pcGpuName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(store.pcOnline ? StudioTheme.emerald : StudioTheme.textPrimary)
            }

            Button {
                store.saveSettings()
            } label: {
                Label("Save All Settings & Test Connection", systemImage: "bolt.horizontal.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(StudioTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .studioCard()
    }

    private var clusterConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("STANDALONE AI CLUSTER (WORKS 24/7 ANYWHERE)", systemImage: "sparkles.tv.fill")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(StudioTheme.crimson)

            Text("Generates uncensored SDXL artwork (WAI-NSFW-illustrious-SDXL, Pony Diffusion V6 XL, AlbedoBase XL) directly on your iPhone even when your PC is off. Uses anonymous key 0000000000 by default.")
                .font(.system(size: 12))
                .foregroundColor(StudioTheme.textSecondary)

            HStack {
                Text("AI Horde Key:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(StudioTheme.textPrimary)
                TextField("0000000000", text: $store.hordeApiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(StudioTheme.textPrimary)
                    .padding(8)
                    .background(StudioTheme.bgDeep)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .studioCard()
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COREDIAG // STEALTH STUDIO EDITION v1.1")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(StudioTheme.textSecondary)
            Text("• Disguised on iPhone Home Screen & SideStore as 'CoreDiag'\n• Vault stored in hidden Application Support (invisible in iOS Files app & iCloud Backup)\n• Instant App-Switcher Privacy Curtain + Face ID / PIN 2070 Unlock")
                .font(.system(size: 12))
                .foregroundColor(StudioTheme.textSecondary)
                .lineSpacing(4)
        }
        .studioCard()
    }
}
