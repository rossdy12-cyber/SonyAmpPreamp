import SwiftUI
import UIKit

// MARK: - Gothic Vampire TV Theme

enum STVGothicTheme {
    static let void      = Color(red: 0.020, green: 0.008, blue: 0.012) // #050203
    static let crypt     = Color(red: 0.071, green: 0.024, blue: 0.035) // #120609
    static let sepulchre = Color(red: 0.118, green: 0.039, blue: 0.059) // #1E0A0F
    static let tomb      = Color(red: 0.235, green: 0.071, blue: 0.098) // #3C1219
    static let bloodDeep = Color(red: 0.361, green: 0.039, blue: 0.094) // #5C0A18
    static let blood     = Color(red: 0.620, green: 0.059, blue: 0.157) // #9E0F28
    static let bloodHi   = Color(red: 0.831, green: 0.086, blue: 0.227) // #D4163A
    static let bone      = Color(red: 0.937, green: 0.894, blue: 0.882) // #EFE4E1
    static let ash       = Color(red: 0.620, green: 0.525, blue: 0.541) // #9E868A

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .serif)
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

struct STVLancetArch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let spring = rect.minY + rect.height * 0.44
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: spring))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.10)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: spring),
            control: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.10)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

struct STVCathedralBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                STVGothicTheme.void

                RadialGradient(
                    colors: [STVGothicTheme.bloodDeep.opacity(0.58), STVGothicTheme.crypt.opacity(0.36), .clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: max(w, h) * 0.78
                )

                STVLancetArch()
                    .stroke(STVGothicTheme.blood.opacity(0.18), lineWidth: 2)
                    .frame(width: w * 0.68, height: h * 0.88)
                    .position(x: w / 2, y: h * 0.55)

                Circle()
                    .stroke(STVGothicTheme.blood.opacity(0.14), lineWidth: 1.5)
                    .frame(width: min(w, h) * 0.34, height: min(w, h) * 0.34)
                    .position(x: w / 2, y: h * 0.36)
            }
        }
    }
}

struct STVFocusButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    var active: Bool = false
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isFocused
                            ? LinearGradient(colors: [STVGothicTheme.bloodDeep, STVGothicTheme.sepulchre], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : (active
                                ? LinearGradient(colors: [STVGothicTheme.bloodDeep.opacity(0.78), STVGothicTheme.crypt], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [STVGothicTheme.sepulchre.opacity(0.88), STVGothicTheme.crypt.opacity(0.94)], startPoint: .top, endPoint: .bottom))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? STVGothicTheme.bloodHi : (active ? STVGothicTheme.blood : STVGothicTheme.tomb),
                        lineWidth: isFocused ? 3.5 : (active ? 2.0 : 1.2)
                    )
            )
            .shadow(color: isFocused ? STVGothicTheme.bloodHi.opacity(0.65) : .clear, radius: isFocused ? 22 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.03 : 1.0))
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

// MARK: - Models

struct StarkStoreAppItem: Codable, Identifiable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    let developerName: String?
    let subtitle: String?
    let localizedDescription: String?
    let iconURL: String?
    let version: String?
    let versionDate: String?
    let downloadURL: String?
    let size: Int?

    var isTVApp: Bool {
        let b = bundleIdentifier.lowercased()
        let n = name.lowercased()
        let s = (subtitle ?? "").lowercased()
        return b.hasSuffix(".tv") || n.contains(" tv") || s.contains("tvos") || s.contains("apple tv")
    }

    var formattedSize: String {
        guard let sz = size, sz > 0 else { return "tvOS / iOS" }
        let mb = Double(sz) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", mb)
    }
}

struct StarkSourceManifest: Codable {
    let name: String?
    let apps: [StarkStoreAppItem]?
}

struct PairedAppleTVDevice: Codable, Identifiable {
    var id: String { udid }
    let udid: String
    let name: String
    let ip: String
    let model: String
    let paired: Bool
}

struct AppleTVEngineStatus: Codable {
    let ok: Bool
    let engine_running: Bool?
    let cert_subject: String?
    let cert_expires: String?
    let devices: [PairedAppleTVDevice]?
    let message: String?
    let error: String?
}

// MARK: - ViewModel

@MainActor
final class StarkStoreTVViewModel: ObservableObject {
    @Published var selectedTab: String = "tvos" // "tvos", "all", "pair"
    @Published var apps: [StarkStoreAppItem] = []
    @Published var pairedDevices: [PairedAppleTVDevice] = []
    @Published var certSubject: String = "Apple Development: Ross Dymond (G42YL9QS8W)"
    @Published var certExpires: String = "365-Day Active"
    @Published var isLoading: Bool = false
    @Published var installingBundleId: String?
    @Published var statusBanner: String?
    @Published var isErrorBanner: Bool = false

    // Pairing Inputs
    @Published var pairIPInput: String = "192.168.0.62"
    @Published var pairPINInput: String = ""
    @Published var pairNameInput: String = "Ross Apple TV 4K"

    private let sourceURLs = [
        "https://navidrome.nas-server.co.uk/sidestore/source.json",
        "http://100.64.0.4:18998/source.json",
        "http://100.85.127.42:18998/source.json"
    ]

    private let atvAPIBases = [
        "https://hs.nas-server.co.uk/appletv-api",
        "http://100.64.0.4:18998/sidestore-api/appletv",
        "http://100.85.127.42:18998/sidestore-api/appletv"
    ]

    var displayedApps: [StarkStoreAppItem] {
        if selectedTab == "tvos" {
            let tvOnly = apps.filter { $0.isTVApp }
            return tvOnly.isEmpty ? apps : tvOnly
        }
        return apps
    }

    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Load apps from source.json
        for sURL in sourceURLs {
            guard let url = URL(string: sURL) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let manifest = try? JSONDecoder().decode(StarkSourceManifest.self, from: data),
               let list = manifest.apps, !list.isEmpty {
                self.apps = list
                break
            }
        }

        // 2. Load paired Apple TV devices from TrueNAS Wireless Installer Engine
        for base in atvAPIBases {
            guard let url = URL(string: "\(base)?action=status") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let st = try? JSONDecoder().decode(AppleTVEngineStatus.self, from: data),
               st.ok {
                if let devs = st.devices { self.pairedDevices = devs }
                if let cs = st.cert_subject { self.certSubject = cs }
                if let ce = st.cert_expires { self.certExpires = ce }
                break
            }
        }
    }

    func installOnAppleTV(app: StarkStoreAppItem) async {
        installingBundleId = app.bundleIdentifier
        statusBanner = "✠ Signing & Wirelessly Installing \(app.name) (v\(app.version ?? "1.0.0")) onto Apple TV..."
        isErrorBanner = false
        defer { installingBundleId = nil }

        let targetUDID = pairedDevices.first?.udid ?? ""
        let payload: [String: Any] = [
            "action": "install",
            "bundleId": app.bundleIdentifier,
            "udid": targetUDID,
            "ip": pairIPInput
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        for base in atvAPIBases {
            guard let url = URL(string: base) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 90
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData

            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let st = try JSONDecoder().decode(AppleTVEngineStatus.self, from: data)
                if st.ok {
                    statusBanner = st.message ?? "✠ \(app.name) installed onto your Apple TV Home Screen!"
                    isErrorBanner = false
                } else {
                    statusBanner = st.error ?? "Wireless install failed — ensure Apple TV is paired in the PAIR APPLE TV tab."
                    isErrorBanner = true
                }
                return
            } catch {
                continue
            }
        }
        statusBanner = "Could not reach TrueNAS Wireless Apple TV Installer Engine."
        isErrorBanner = true
    }

    func pairAppleTV() async {
        let ip = pairIPInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = pairPINInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty, !pin.isEmpty else {
            statusBanner = "Enter your Apple TV's LAN IP and the 6-digit PIN from Settings → Remotes and Devices → Remote App and Devices."
            isErrorBanner = true
            return
        }

        isLoading = true
        statusBanner = "✠ Pairing TrueNAS Wireless Installer Engine with Apple TV at \(ip) (PIN: \(pin))..."
        isErrorBanner = false
        defer { isLoading = false }

        let payload: [String: Any] = [
            "action": "pair",
            "ip": ip,
            "pin": pin,
            "name": pairNameInput
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        for base in atvAPIBases {
            guard let url = URL(string: base) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 25
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData

            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let st = try JSONDecoder().decode(AppleTVEngineStatus.self, from: data)
                if st.ok {
                    if let devs = st.devices { self.pairedDevices = devs }
                    statusBanner = st.message ?? "✠ Apple TV at \(ip) paired permanently with TrueNAS!"
                    isErrorBanner = false
                    pairPINInput = ""
                } else {
                    statusBanner = st.error ?? "Pairing failed — check that Remote App and Devices is open on the Apple TV."
                    isErrorBanner = true
                }
                return
            } catch {
                continue
            }
        }
        statusBanner = "Could not reach TrueNAS Wireless Pairing Engine."
        isErrorBanner = true
    }
}

// MARK: - Main View

struct StarkStoreTVRootView: View {
    @StateObject private var vm = StarkStoreTVViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 36),
        GridItem(.flexible(), spacing: 36),
        GridItem(.flexible(), spacing: 36)
    ]

    var body: some View {
        ZStack {
            STVCathedralBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                headerBar
                tabRibbon

                if let banner = vm.statusBanner {
                    HStack(spacing: 14) {
                        if vm.installingBundleId != nil || vm.isLoading {
                            ProgressView()
                                .tint(STVGothicTheme.bloodHi)
                        } else {
                            Text("✠")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(STVGothicTheme.bloodHi)
                        }
                        Text(banner)
                            .font(STVGothicTheme.serif(20, weight: .semibold))
                            .foregroundStyle(STVGothicTheme.bone)
                        Spacer()
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(vm.isErrorBanner ? STVGothicTheme.tomb : STVGothicTheme.bloodDeep.opacity(0.88))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(STVGothicTheme.bloodHi, lineWidth: 1.6)
                    )
                    .padding(.horizontal, 48)
                }

                if vm.selectedTab == "pair" {
                    pairingView
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 36) {
                            ForEach(vm.displayedApps) { app in
                                appCard(app)
                            }
                        }
                        .padding(.horizontal, 48)
                        .padding(.vertical, 18)
                    }
                }
            }
            .padding(.top, 28)
        }
        .task {
            await vm.refreshAll()
        }
    }

    private var headerBar: some View {
        HStack {
            HStack(spacing: 14) {
                Text("✠")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(STVGothicTheme.bloodHi)
                Text("STARK STORE TV")
                    .font(STVGothicTheme.display(38))
                    .tracking(2.5)
                    .foregroundStyle(STVGothicTheme.bone)
                Text("365-DAY SIGNED · WIRELESS APPLE TV INSTALLER")
                    .font(STVGothicTheme.serif(15, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(STVGothicTheme.bloodHi)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(STVGothicTheme.bloodDeep.opacity(0.75))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(STVGothicTheme.bloodHi, lineWidth: 1.2)
                    )
            }

            Spacer()

            Button {
                Task { await vm.refreshAll() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("SYNC CRYPT")
                }
                .font(STVGothicTheme.serif(17, weight: .bold))
                .foregroundStyle(STVGothicTheme.bone)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(STVFocusButtonStyle(active: false, cornerRadius: 10))
        }
        .padding(.horizontal, 48)
    }

    private var tabRibbon: some View {
        HStack(spacing: 18) {
            tabPill(id: "tvos", icon: "appletv.fill", title: "TVOS SANCTUM (\(vm.apps.filter { $0.isTVApp }.count))")
            tabPill(id: "all", icon: "square.grid.3x3.fill", title: "ALL STARK APPS (\(vm.apps.count))")
            tabPill(id: "pair", icon: "antenna.radiowaves.left.and.right", title: "PAIR APPLE TV (\(vm.pairedDevices.count) PAIRED)")
            Spacer()
            Text(vm.certSubject)
                .font(STVGothicTheme.serif(15, weight: .semibold))
                .foregroundStyle(STVGothicTheme.ash)
        }
        .padding(.horizontal, 48)
    }

    private func tabPill(id: String, icon: String, title: String) -> some View {
        let active = vm.selectedTab == id
        return Button {
            vm.selectedTab = id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(active ? STVGothicTheme.bloodHi : STVGothicTheme.ash)
                Text(title)
                    .font(STVGothicTheme.serif(18, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(active ? STVGothicTheme.bone : STVGothicTheme.ash)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
        }
        .buttonStyle(STVFocusButtonStyle(active: active, cornerRadius: 12))
    }

    private func appCard(_ app: StarkStoreAppItem) -> some View {
        let isInstalling = vm.installingBundleId == app.bundleIdentifier
        return Button {
            Task { await vm.installOnAppleTV(app: app) }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    AsyncImage(url: URL(string: app.iconURL ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            ZStack {
                                STVGothicTheme.bloodDeep
                                Text("✠")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundStyle(STVGothicTheme.bone)
                            }
                        }
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(STVGothicTheme.bloodHi, lineWidth: 1.5)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(app.name)
                                .font(STVGothicTheme.serif(23, weight: .bold))
                                .foregroundStyle(STVGothicTheme.bone)
                                .lineLimit(1)
                            if app.isTVApp {
                                Text("tvOS")
                                    .font(.system(size: 13, weight: .black, design: .monospaced))
                                    .foregroundStyle(STVGothicTheme.bone)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(STVGothicTheme.bloodHi)
                                    )
                            }
                        }
                        Text("v\(app.version ?? "1.0.0") · \(app.formattedSize)")
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(STVGothicTheme.bloodHi)
                        Text(app.bundleIdentifier)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(STVGothicTheme.ash)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                Text(app.localizedDescription ?? app.subtitle ?? "Signed & hosted on TrueNAS Stark Store.")
                    .font(STVGothicTheme.serif(16))
                    .foregroundStyle(STVGothicTheme.ash)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(height: 68, alignment: .topLeading)

                HStack {
                    Spacer()
                    if isInstalling {
                        ProgressView()
                            .tint(STVGothicTheme.bloodHi)
                        Text("INSTALLING OVER LAN...")
                            .font(STVGothicTheme.serif(16, weight: .bold))
                            .foregroundStyle(STVGothicTheme.bone)
                    } else {
                        Text("✠ INSTALL / UPDATE ON APPLE TV ✠")
                            .font(STVGothicTheme.serif(16, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(STVGothicTheme.bone)
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(STVGothicTheme.bloodDeep.opacity(0.85))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(STVGothicTheme.bloodHi, lineWidth: 1.2)
                )
            }
            .padding(20)
        }
        .buttonStyle(STVFocusButtonStyle(active: app.isTVApp, cornerRadius: 18))
    }

    private var pairingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("✠ WIRELESS APPLE TV PAIRING SANCTUM (TRUE-NAS <-> APPLE TV)")
                    .font(STVGothicTheme.display(26))
                    .foregroundStyle(STVGothicTheme.bone)

                Text("1. Open Settings → Remotes and Devices → Remote App and Devices on this Apple TV.\n2. Enter your Apple TV's LAN IP (e.g. 192.168.0.62 or 192.168.0.200) and the 6-digit PIN displayed on screen.\n3. Once paired, clicking 'INSTALL / UPDATE ON APPLE TV' on any app pushes the 365-day signed IPA straight to this Apple TV over your network.")
                    .font(STVGothicTheme.serif(18))
                    .foregroundStyle(STVGothicTheme.ash)

                HStack(spacing: 18) {
                    TextField("Apple TV IP (e.g. 192.168.0.62)", text: $vm.pairIPInput)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                    TextField("6-Digit PIN", text: $vm.pairPINInput)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))

                    Button {
                        Task { await vm.pairAppleTV() }
                    } label: {
                        Text("✠ CONSECRATE PAIRING ✠")
                            .font(STVGothicTheme.serif(20, weight: .bold))
                            .foregroundStyle(STVGothicTheme.bone)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(STVFocusButtonStyle(active: true, cornerRadius: 12))
                }

                if !vm.pairedDevices.isEmpty {
                    Text("PAIRED APPLE TV DEVICES")
                        .font(STVGothicTheme.serif(18, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(STVGothicTheme.bloodHi)
                        .padding(.top, 10)

                    ForEach(vm.pairedDevices) { dev in
                        HStack {
                            Image(systemName: "appletv.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(STVGothicTheme.bloodHi)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dev.name)
                                    .font(STVGothicTheme.serif(21, weight: .bold))
                                    .foregroundStyle(STVGothicTheme.bone)
                                Text("UDID: \(dev.udid) · IP: \(dev.ip) · \(dev.model)")
                                    .font(.system(size: 16, design: .monospaced))
                                    .foregroundStyle(STVGothicTheme.ash)
                            }
                            Spacer()
                            Text(dev.paired ? "PAIRED ✠" : "UNPAIRED")
                                .font(STVGothicTheme.serif(17, weight: .bold))
                                .foregroundStyle(STVGothicTheme.bloodHi)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(STVGothicTheme.crypt)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(STVGothicTheme.blood, lineWidth: 1.5)
                        )
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 16)
        }
    }
}

@main
struct StarkStoreTVApp: App {
    var body: some Scene {
        WindowGroup {
            StarkStoreTVRootView()
        }
    }
}
