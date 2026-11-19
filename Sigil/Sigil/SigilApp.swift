import SwiftUI
import CryptoKit
import LocalAuthentication
import AVFoundation
import AudioToolbox
import UIKit
import UserNotifications

// ============================================================
//  SIGIL — gothic authenticator (Duo-Mobile style, our crypt)
//  TOTP accounts via QR (otpauth://) or manual entry.
//  Secrets live in the Keychain, sealed behind Face ID optionally.
// ============================================================

let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
let bloodDim = Color(red: 0.48, green: 0.05, blue: 0.13)
let ashText = Color(red: 0.96, green: 0.89, blue: 0.91)
let ashDim = Color(red: 0.69, green: 0.53, blue: 0.56)
let cryptBg = Color(red: 0.02, green: 0.004, blue: 0.012)

// MARK: - Models

struct SigilAccount: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var issuer: String
    var account: String
    var secretBase32: String
    var digits: Int = 6
    var period: Int = 30
    var algorithm: String = "SHA1"

    var label: String { issuer.isEmpty ? account : issuer }
}

// MARK: - TOTP engine (RFC 6238)

enum TotpEngine {
    static func normalizeBase32(_ s: String) -> Data {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var bits = 0
        var value = 0
        var out: [UInt8] = []
        for ch in s.uppercased().replacingOccurrences(of: " ", with: "") {
            if ch == "=" { break }
            guard let idx = alphabet.firstIndex(of: ch) else { continue }
            value = (value << 5) | idx
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return Data(out)
    }

    static func generate(secretBase32: String, digits: Int, period: Int, algorithm: String, at date: Date = Date()) -> (code: String, remaining: Int) {
        let secret = normalizeBase32(secretBase32)
        guard !secret.isEmpty else { return ("——", period) }
        let counter = UInt64(max(0, date.timeIntervalSince1970 / Double(period)))
        var bigEndianCounter = counter.bigEndian
        let counterData = withUnsafeBytes(of: &bigEndianCounter) { Data($0) }

        let hash: Data
        switch algorithm.uppercased() {
        case "SHA256":
            hash = Data(HMAC<SHA256>.authenticationCode(for: counterData, using: SymmetricKey(data: secret)))
        case "SHA512":
            hash = Data(HMAC<SHA512>.authenticationCode(for: counterData, using: SymmetricKey(data: secret)))
        default:
            hash = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: SymmetricKey(data: secret)))
        }

        guard hash.count > 19 else { return ("——", period) }
        let offset = Int(hash[hash.count - 1] & 0x0F)
        let part = (UInt32(hash[offset]) << 24)
            | (UInt32(hash[offset + 1]) << 16)
            | (UInt32(hash[offset + 2]) << 8)
            | UInt32(hash[offset + 3])
        let modulus = UInt32(pow(10.0, Double(digits)))
        var code = String((part & 0x7FFFFFFF) % modulus)
        while code.count < digits { code = "0" + code }

        let remaining = period - Int(date.timeIntervalSince1970.truncatingRemainder(dividingBy: Double(period)))
        return (code, max(0, remaining))
    }

    static func grouped(_ code: String) -> String {
        guard code.count > 4 else { return code }
        let mid = code.index(code.startIndex, offsetBy: code.count / 2)
        return String(code[..<mid]) + " " + String(code[mid...])
    }

    static func parseOtpauthUri(_ uri: String) -> SigilAccount? {
        guard uri.lowercased().hasPrefix("otpauth://") else { return nil }
        guard let match = uri.range(of: "otpauth://totp/") else { return nil }
        let rest = String(uri[match.upperBound...])
        let parts = rest.components(separatedBy: "?")
        let labelPart = parts.first ?? ""
        let query = parts.count > 1 ? parts[1] : ""
        var issuer = "", account = labelPart
        if labelPart.contains(":") {
            let bits = labelPart.components(separatedBy: ":")
            issuer = bits.first?.removingPercentEncoding ?? ""
            account = bits.dropFirst().joined(separator: ":").removingPercentEncoding ?? labelPart
        } else {
            account = labelPart.removingPercentEncoding ?? labelPart
        }
        var secret = "", digits = 6, period = 30, algorithm = "SHA1"
        for pair in query.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            guard kv.count == 2 else { continue }
            let key = kv[0].lowercased()
            let val = kv[1].removingPercentEncoding ?? kv[1]
            switch key {
            case "secret": secret = val
            case "issuer": issuer = val
            case "digits": digits = Int(val) ?? 6
            case "period": period = Int(val) ?? 30
            case "algorithm": algorithm = val.uppercased()
            default: break
            }
        }
        guard !secret.isEmpty else { return nil }
        return SigilAccount(issuer: issuer, account: account, secretBase32: secret, digits: digits, period: period, algorithm: algorithm)
    }
}

// MARK: - Keychain vault (sealed)

enum CryptVault {
    static let service = "com.ross.sigil.crypt"

    static func save(_ accounts: [SigilAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "accounts"
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load() -> [SigilAccount] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "accounts",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let accounts = try? JSONDecoder().decode([SigilAccount].self, from: data) else { return [] }
        return accounts
    }
}

// MARK: - Root

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var shared: AppDelegate?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppDelegate.shared = self
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "SIGIL_APPROVAL", actions: [
                UNNotificationAction(identifier: "SIGIL_APPROVE", title: "✓ APPROVE", options: [.foreground]),
                UNNotificationAction(identifier: "SIGIL_DENY", title: "✕ DENY", options: [.destructive])
            ], intentIdentifiers: [])
        ])
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            await SigilEngine.shared.registerPush(token: hex)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        SigilEngine.shared.pushStatus = "Push registration failed: \(error.localizedDescription)"
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let requestId = userInfo["requestId"] as? String else { return }
        if response.actionIdentifier == "SIGIL_APPROVE" {
            if SigilEngine.shared.biometricApproveEnabled {
                SigilEngine.shared.awaitingApprovalRequestId = requestId
            } else {
                await SigilEngine.shared.respond(requestId: requestId, approve: true)
            }
        } else if response.actionIdentifier == "SIGIL_DENY" {
            await SigilEngine.shared.respond(requestId: requestId, approve: false)
        } else {
            await SigilEngine.shared.loadPending()
        }
    }
}

@main
struct SigilApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @StateObject private var engine = SigilEngine.shared
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            CodesView(engine: engine)
                .tabItem { Label("SIGILS", systemImage: "key.horizontal.fill") }
            SealsView(engine: engine)
                .tabItem { Label("SEALS", systemImage: "checkmark.shield.fill") }
            SettingsView(engine: engine)
                .tabItem { Label("CRYPT", systemImage: "lock.shield") }
        }
        .accentColor(crimson)
        .onChange(of: engine.awaitingApprovalRequestId) { rid in
            if rid != nil { tab = 1 }
        }
    }
}

// MARK: - Engine

@MainActor
final class SigilEngine: ObservableObject {
    static let shared = SigilEngine()

    @Published var accounts: [SigilAccount] = []
    @Published var now = Date()
    @Published var unlocked = false
    @Published var cryptLockEnabled: Bool {
        didSet { UserDefaults.standard.set(cryptLockEnabled, forKey: "sigil.cryptLock") }
    }
    @Published var pushStatus = "Not registered"
    @Published var pendingRequests: [SigilApproval] = []
    @Published var biometricApproveEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricApproveEnabled, forKey: "sigil.biometricApprove") }
    }
    @Published var awaitingApprovalRequestId: String? = nil

    let receiverBases = ["http://100.85.127.42:18998", "https://navidrome.nas-server.co.uk"]

    private var timer: Timer?

    init() {
        cryptLockEnabled = UserDefaults.standard.bool(forKey: "sigil.cryptLock")
        biometricApproveEnabled = UserDefaults.standard.bool(forKey: "sigil.biometricApprove")
        accounts = CryptVault.load()
        unlocked = !cryptLockEnabled
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        if cryptLockEnabled {
            Task { await authenticate() }
        }
    }

    func authenticate() async {
        let ctx = LAContext()
        var error: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            do {
                let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unseal your sigils")
                if ok { unlocked = true }
            } catch {
                unlocked = false
            }
        } else if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            do {
                let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unseal your sigils")
                if ok { unlocked = true }
            } catch {
                unlocked = false
            }
        } else {
            unlocked = true // no biometrics enrolled - don't lock the user out
        }
    }

    func add(_ account: SigilAccount) {
        accounts.append(account)
        CryptVault.save(accounts)
    }

    func delete(_ account: SigilAccount) {
        accounts.removeAll { $0.id == account.id }
        CryptVault.save(accounts)
    }

    func code(for account: SigilAccount) -> (code: String, remaining: Int) {
        TotpEngine.generate(secretBase32: account.secretBase32, digits: account.digits, period: account.period, algorithm: account.algorithm, at: now)
    }

    func exportJson() -> String {
        let uris = accounts.map { a -> String in
            "otpauth://totp/\(a.issuer):\(a.account)?secret=\(a.secretBase32)&issuer=\(a.issuer)&digits=\(a.digits)&period=\(a.period)&algorithm=\(a.algorithm)"
        }
        return uris.joined(separator: "\n")
    }

    func importJson(_ text: String) -> Int {
        var added = 0
        for line in text.components(separatedBy: .newlines) {
            if let account = TotpEngine.parseOtpauthUri(line.trimmingCharacters(in: .whitespaces)) {
                add(account)
                added += 1
            }
        }
        return added
    }

    // ---- login approval bridge ----

    func registerPush(token: String) async {
        for base in receiverBases {
            guard let url = URL(string: "\(base)/sidestore-api/sigil/register") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 10
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (json["ok"] as? Bool) == true {
                    pushStatus = "Sealed to the crypt (\((json["deviceCount"] as? Int) ?? 1) device(s))"
                    return
                }
            } catch { continue }
        }
        pushStatus = "Push registration failed — approval pushes won't arrive"
    }

    func authenticateApproval() async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        let reason = "Approve the login request"
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            do { return try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) }
            catch { return false }
        }
        do { return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) }
        catch { return false }
    }

    func respond(requestId: String, approve: Bool) async {
        for base in receiverBases {
            guard let url = URL(string: "\(base)/sidestore-api/sigil/respond") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 10
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": requestId, "approve": approve])
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (json["ok"] as? Bool) == true {
                    await loadPending()
                    return
                }
            } catch { continue }
        }
    }

    func loadPending() async {
        for base in receiverBases {
            guard let url = URL(string: "\(base)/sidestore-api/sigil/pending") else { continue }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (json["ok"] as? Bool) == true {
                    let items = (json["pending"] as? [[String: Any]]) ?? []
                    let mapped: [SigilApproval] = items.compactMap { dict in
                        guard let id = dict["id"] as? String else { return nil }
                        return SigilApproval(
                            id: id,
                            service: (dict["service"] as? String) ?? "Unknown",
                            detail: (dict["detail"] as? String) ?? "",
                            ts: (dict["ts"] as? Double) ?? 0
                        )
                    }
                    await MainActor.run { pendingRequests = mapped }
                    return
                }
            } catch { continue }
        }
    }
}

struct SigilApproval: Identifiable, Equatable {
    let id: String
    let service: String
    let detail: String
    let ts: Double
}

// MARK: - SEALS tab (login approvals)

struct SealsView: View {
    @ObservedObject var engine: SigilEngine
    @State private var pollTimer: Timer?
    @State private var sealStatus = ""

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PUSH STATUS")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(ashDim)
                        Text(engine.pushStatus)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(engine.pushStatus.contains("Sealed") ? .green : .orange)
                    }
                    .padding(13)
                    .background(Color(red: 0.06, green: 0.01, blue: 0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.3), lineWidth: 1))

                    if engine.pendingRequests.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 34))
                                .foregroundColor(bloodDim)
                            Text("No logins awaiting your seal.")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(ashDim)
                            Text("When any of your services asks for approval, it appears here — and as a notification with APPROVE / DENY buttons.")
                                .font(.system(size: 11))
                                .foregroundColor(ashDim.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        ForEach(engine.pendingRequests) { req in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(req.service.uppercased())
                                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                    .foregroundColor(crimson)
                                if !req.detail.isEmpty {
                                    Text(req.detail)
                                        .font(.system(size: 12))
                                        .foregroundColor(ashText)
                                }
                                Text("asked \(Date(timeIntervalSince1970: req.ts), style: .relative) ago")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(ashDim)
                                if !sealStatus.isEmpty {
                                    Text(sealStatus)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                                HStack(spacing: 10) {
                                    Button {
                                        Task {
                                            if engine.biometricApproveEnabled {
                                                let ok = await engine.authenticateApproval()
                                                guard ok else {
                                                    sealStatus = "Face ID failed — approval NOT sent."
                                                    return
                                                }
                                                sealStatus = ""
                                            }
                                            await engine.respond(requestId: req.id, approve: true)
                                        }
                                    } label: {
                                        Text(engine.biometricApproveEnabled ? "✓ APPROVE (FACE ID)" : "✓ APPROVE")
                                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                            .frame(maxWidth: .infinity)
                                            .padding(10)
                                            .background(Color.green.opacity(0.85))
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                    }
                                    Button {
                                        Task { await engine.respond(requestId: req.id, approve: false) }
                                    } label: {
                                        Text("✕ DENY")
                                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                            .frame(maxWidth: .infinity)
                                            .padding(10)
                                            .background(crimson)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(13)
                            .background(Color(red: 0.06, green: 0.01, blue: 0.03))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.4), lineWidth: 1))
                        }
                    }
                }
                .padding(14)
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("SEALS")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
        .onAppear {
            Task { await engine.loadPending() }
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
                Task { @MainActor in await engine.loadPending() }
            }
        }
        .onChange(of: engine.awaitingApprovalRequestId) { rid in
            guard let rid = rid else { return }
            Task {
                let ok = await engine.authenticateApproval()
                if ok {
                    await engine.respond(requestId: rid, approve: true)
                } else {
                    sealStatus = "Face ID failed — the request is still waiting below."
                }
                engine.awaitingApprovalRequestId = nil
                await engine.loadPending()
            }
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}

// MARK: - CODES tab

struct CodesView: View {
    @ObservedObject var engine: SigilEngine
    @State private var addSheet = false
    @State private var copiedId: UUID?

    var body: some View {
        NavigationView {
            ZStack {
                cryptBg.ignoresSafeArea()
                if !engine.unlocked {
                    sealedGate
                } else if engine.accounts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "key.horizontal")
                            .font(.system(size: 36))
                            .foregroundColor(crimson)
                        Text("No sigils bound yet.")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(ashDim)
                        Button {
                            addSheet = true
                        } label: {
                            Text("BIND YOUR FIRST SIGIL")
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(crimson)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(engine.accounts) { account in
                                SigilCard(engine: engine, account: account, copied: copiedId == account.id) {
                                    let code = engine.code(for: account).code
                                    UIPasteboard.general.string = code
                                    copiedId = account.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        if copiedId == account.id { copiedId = nil }
                                    }
                                }
                            }
                        }
                        .padding(14)
                    }
                }
            }
            .navigationTitle("")
            .overlay(alignment: .top) {
                Text("SIGILS")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                    .padding(.top, 2)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if engine.unlocked {
                        Button {
                            addSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundColor(crimson)
                        }
                    }
                }
            }
            .sheet(isPresented: $addSheet) {
                AddAccountView(engine: engine)
            }
        }
    }

    private var sealedGate: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundColor(crimson)
            Text("The crypt is sealed.")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(ashText)
            Button {
                Task { await engine.authenticate() }
            } label: {
                Text("UNSEAL")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(crimson)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
    }
}

struct SigilCard: View {
    @ObservedObject var engine: SigilEngine
    let account: SigilAccount
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        let (code, remaining) = engine.code(for: account)
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / CGFloat(account.period))
                    .stroke(remaining <= 5 ? Color.orange : crimson, lineWidth: 4)
                    .rotationEffect(.degrees(-90))
                Text("\(remaining)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(account.label.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                Text(account.account)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ashDim)
                Text(TotpEngine.grouped(code))
                    .font(.system(size: 26, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(spacing: 8) {
                Button(action: onCopy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(copied ? .green : crimson)
                }
                Menu {
                    Button(role: .destructive) {
                        engine.delete(account)
                    } label: {
                        Label("Break this sigil", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(ashDim)
                }
            }
        }
        .padding(13)
        .background(Color(red: 0.06, green: 0.01, blue: 0.03))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - ADD (QR scan or manual)

struct AddAccountView: View {
    @ObservedObject var engine: SigilEngine
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var manualUri = ""
    @State private var issuer = ""
    @State private var account = ""
    @State private var secret = ""
    @State private var manualError = ""

    var body: some View {
        NavigationView {
            ZStack {
                cryptBg.ignoresSafeArea()
                VStack(spacing: 14) {
                    Picker("Method", selection: $mode) {
                        Text("SCAN QR").tag(0)
                        Text("PASTE LINK").tag(1)
                        Text("MANUAL").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 14)

                    if mode == 0 {
                        QRScannerView { uri in
                            if let account = TotpEngine.parseOtpauthUri(uri) {
                                engine.add(account)
                                dismiss()
                            }
                        }
                        .frame(maxHeight: 420)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(crimson.opacity(0.4), lineWidth: 1))
                        Text("Point the lens at the service's QR code.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ashDim)
                    } else if mode == 1 {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Paste an otpauth:// link (from any authenticator export):")
                                .font(.system(size: 12))
                                .foregroundColor(ashDim)
                            TextEditor(text: $manualUri)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 120)
                                .background(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.3)))
                            Button {
                                if let account = TotpEngine.parseOtpauthUri(manualUri.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                    engine.add(account)
                                    dismiss()
                                } else {
                                    manualError = "That link could not be parsed."
                                }
                            } label: {
                                Text("BIND SIGIL")
                                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding(11)
                                    .background(crimson)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            if !manualError.isEmpty {
                                Text(manualError)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(14)
                    } else {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Enter the details from the service (secret is usually shown as base32):")
                                .font(.system(size: 12))
                                .foregroundColor(ashDim)
                            TextField("Issuer (e.g. GitHub)", text: $issuer)
                                .font(.system(size: 12, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                            TextField("Account (e.g. you@mail.com)", text: $account)
                                .font(.system(size: 12, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                            TextField("Secret (base32)", text: $secret)
                                .font(.system(size: 12, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                            Button {
                                guard !secret.trimmingCharacters(in: .whitespaces).isEmpty else {
                                    manualError = "The secret cannot be empty."
                                    return
                                }
                                engine.add(SigilAccount(
                                    issuer: issuer,
                                    account: account.isEmpty ? issuer : account,
                                    secretBase32: secret.trimmingCharacters(in: .whitespaces)
                                ))
                                dismiss()
                            } label: {
                                Text("BIND SIGIL")
                                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding(11)
                                    .background(crimson)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            if !manualError.isEmpty {
                                Text(manualError)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(14)
                    }
                    Spacer()
                }
            }
            .navigationTitle("")
            .overlay(alignment: .top) {
                Text("BIND A SIGIL")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                    .padding(.top, 2)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - QR scanner

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        ScannerController(onScan: onScan)
    }

    func updateUIViewController(_ vc: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onScan: (String) -> Void
    private var session = AVCaptureSession()
    private var fired = false

    init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showNoCamera()
            return
        }
        session.beginConfiguration()
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    private func showNoCamera() {
        let l = UILabel()
        l.text = "Camera unavailable.\nAdd accounts via PASTE LINK or MANUAL instead."
        l.numberOfLines = 0
        l.textAlignment = .center
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !fired else { return }
        for obj in metadataObjects {
            if let qr = obj as? AVMetadataMachineReadableCodeObject, qr.type == .qr, let value = qr.stringValue {
                fired = true
                DispatchQueue.main.async {
                    AudioServicesPlaySystemSound(1057)
                    self.onScan(value)
                }
                return
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }
}

// MARK: - CRYPT tab (settings)

struct SettingsView: View {
    @ObservedObject var engine: SigilEngine
    @State private var importText = ""
    @State private var importStatus = ""

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("01 // CRYPT LOCK")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(crimson)
                        Toggle("Seal behind Face ID / passcode", isOn: $engine.cryptLockEnabled)
                            .font(.system(size: 12, design: .monospaced))
                            .tint(crimson)
                        Toggle("Require Face ID to approve logins", isOn: $engine.biometricApproveEnabled)
                            .font(.system(size: 12, design: .monospaced))
                            .tint(crimson)
                        Text("When sealed, the sigils require your biometrics each time the app opens. With Face ID approval on, every APPROVE tap asks for your face first.")
                            .font(.system(size: 11))
                            .foregroundColor(ashDim)
                    }
                    .padding(13)
                    .background(Color(red: 0.06, green: 0.01, blue: 0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.35), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 9) {
                        Text("02 // EXPORT THE CRYPT")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(crimson)
                        Text("Copy all sigils as otpauth:// links — importable by any authenticator (or Sigil on your other phone).")
                            .font(.system(size: 12))
                            .foregroundColor(ashDim)
                        Button {
                            UIPasteboard.general.string = engine.exportJson()
                        } label: {
                            Text("COPY ALL SIGILS TO CLIPBOARD")
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(11)
                                .background(crimson)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    .padding(13)
                    .background(Color(red: 0.06, green: 0.01, blue: 0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.35), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 9) {
                        Text("03 // RESTORE FROM LINKS")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(crimson)
                        TextEditor(text: $importText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 100)
                            .background(Color.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.3)))
                        Button {
                            let n = engine.importJson(importText)
                            importStatus = n > 0 ? "Bound \(n) sigil(s)." : "No otpauth:// links found in that text."
                            importText = ""
                        } label: {
                            Text("RESTORE")
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(11)
                                .background(bloodDim)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        if !importStatus.isEmpty {
                            Text(importStatus)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(13)
                    .background(Color(red: 0.06, green: 0.01, blue: 0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.25), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("04 // HONEST NOTES")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(crimson)
                        Text("Sigil generates standard TOTP codes — the same system every authenticator uses. Duo's PUSH APPROVALS run through Duo's own cloud and cannot be reproduced against their service; Sigil covers the TOTP side fully.")
                            .font(.system(size: 12))
                            .foregroundColor(ashDim)
                        Text("Secrets are sealed in the iOS Keychain, device-only — they never leave this phone except through your own export.")
                            .font(.system(size: 12))
                            .foregroundColor(ashDim)
                    }
                    .padding(13)
                    .background(Color(red: 0.06, green: 0.01, blue: 0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.25), lineWidth: 1))
                }
                .padding(14)
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE CRYPT")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
    }
}
