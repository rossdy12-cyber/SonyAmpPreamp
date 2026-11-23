import SwiftUI
import UIKit

// ============================================================
//  WRAITH — the tailnet's ghostly overseer
//  Gothic command deck for the Headscale control server:
//  every node, online state, IPs and expirations at a glance.
// ============================================================

let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
let bloodDim = Color(red: 0.48, green: 0.05, blue: 0.13)
let ashText = Color(red: 0.96, green: 0.89, blue: 0.91)
let ashDim = Color(red: 0.69, green: 0.53, blue: 0.56)
let cryptBg = Color(red: 0.02, green: 0.004, blue: 0.012)

struct HsNode: Identifiable, Codable {
    let id: String
    let name: String
    let user: HsUser?
    let ipAddresses: [String]?
    let online: Bool?
    let expiry: String?
    let lastSeen: String?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, user, online, expiry, tags
        case ipAddresses = "ipAddresses"
        case lastSeen = "lastSeen"
    }

    var displayIP: String { ipAddresses?.first ?? "—" }
    var userLabel: String { user?.displayName ?? user?.name ?? "—" }

    var expiryDate: Date? {
        guard let e = expiry, e != "0001-01-01T00:00:00Z", e != "N/A" else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: e) ?? ISO8601DateFormatter().date(from: e)
    }

    var expiryDays: Int? {
        guard let d = expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: d).day
    }
}

struct HsUser: Codable {
    let id: String
    let name: String?
    let displayName: String?
    var display: String { displayName ?? name ?? "—" }
}

struct HsUserFull: Identifiable, Codable {
    let id: String
    let name: String?
    let displayName: String?
    let createdAt: String?
    var display: String { displayName ?? name ?? "—" }
}

final class WraithState: ObservableObject {
    @Published var serverURL: String
    @Published var apiKey: String
    @Published var nodes: [HsNode] = []
    @Published var users: [HsUserFull] = []
    @Published var statusMessage = ""
    @Published var loading = false
    @Published var linked = false

    private static let defaultsKey = "wraith.settings.v1"

    init() {
        let saved = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        serverURL = saved["url"] ?? "http://100.85.127.42:8086"
        apiKey = saved["key"] ?? ""
        if !apiKey.isEmpty { refresh() }
    }

    func save() {
        UserDefaults.standard.set(["url": serverURL, "key": apiKey], forKey: Self.defaultsKey)
        refresh()
    }

    private var base: String {
        serverURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    func refresh() {
        guard !base.isEmpty, !trimmedKey.isEmpty else { linked = false; return }
        loading = true
        let g = DispatchGroup()
        var gotNodes: [HsNode]?
        var gotUsers: [HsUserFull]?
        var anyError: String?

        let fetch = { (path: String, done: @escaping (Data?) -> Void) in
            guard let url = URL(string: "\(self.base)\(path)") else { done(nil); return }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(self.trimmedKey)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 20
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                if let http = resp as? HTTPURLResponse, http.statusCode == 401 { anyError = "Rejected: wrong API key (401)" }
                done(data)
            }.resume()
        }

        g.enter()
        fetch("/api/v1/node") { data in
            struct Resp: Codable { let nodes: [HsNode]? }
            gotNodes = (try? JSONDecoder().decode(Resp.self, from: data ?? Data()))?.nodes
            g.leave()
        }
        g.enter()
        fetch("/api/v1/user") { data in
            struct Resp: Codable { let users: [HsUserFull]? }
            gotUsers = (try? JSONDecoder().decode(Resp.self, from: data ?? Data()))?.users
            g.leave()
        }
        g.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.loading = false
            if let n = gotNodes { self.nodes = n; self.linked = true }
            if let u = gotUsers { self.users = u }
            if let e = anyError { self.statusMessage = e }
            else if gotNodes == nil { self.statusMessage = "Could not reach the Headscale realm. Check the KEYS tab." }
            else { self.statusMessage = "" }
        }
    }

    func expireNode(_ node: HsNode) {
        guard let url = URL(string: "\(base)/api/v1/node/\(node.id)/expire") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                self?.statusMessage = code == 200 ? "\(node.name) has been severed (expired) — it must re-authenticate to return." : "Severing failed (HTTP \(code))."
                self?.refresh()
            }
        }.resume()
    }
}

// MARK: - Root

@main
struct WraithApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @StateObject private var wraith = WraithState()

    var body: some View {
        TabView {
            NetworkView(wraith: wraith)
                .tabItem { Label("NETWORK", systemImage: "dot.viewfinder") }
            RealmView(wraith: wraith)
                .tabItem { Label("REALM", systemImage: "person.3.fill") }
            KeysView(wraith: wraith)
                .tabItem { Label("KEYS", systemImage: "key.fill") }
        }
        .accentColor(crimson)
    }
}

// MARK: - Shared bits

struct WCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color(red: 0.08, green: 0.012, blue: 0.035))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.38), lineWidth: 1))
        .cornerRadius(10)
    }
}

struct WButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(enabled ? bloodDim : Color(red: 0.2, green: 0.03, blue: 0.07))
                .foregroundColor(enabled ? .white : ashDim)
                .cornerRadius(7)
        }
        .disabled(!enabled)
    }
}

func expiryColor(_ node: HsNode) -> Color {
    guard let days = node.expiryDays else { return .green.opacity(0.8) }
    if days < 0 { return .red }
    if days < 7 { return .orange }
    return .green.opacity(0.8)
}

// MARK: - NETWORK tab

struct NetworkView: View {
    @ObservedObject var wraith: WraithState

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    WCard(title: "01 // THE WALKING NETWORK") {
                        if wraith.nodes.isEmpty {
                            Text(wraith.loading ? "Summoning the network…" : "No nodes visible — seal the KEYS first.")
                                .font(.system(size: 12)).foregroundColor(ashDim)
                        } else {
                            ForEach(wraith.nodes) { node in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Circle()
                                            .fill((node.online ?? false) ? Color(red: 0, green: 0.9, blue: 0.45) : Color(red: 0.45, green: 0.3, blue: 0.35))
                                            .frame(width: 9, height: 9)
                                            .shadow(color: (node.online ?? false) ? Color(red: 0, green: 0.9, blue: 0.45) : .clear, radius: 4)
                                        Text(node.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(ashText)
                                        Spacer()
                                        Text((node.online ?? false) ? "ONLINE" : "asleep")
                                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                            .foregroundColor((node.online ?? false) ? Color(red: 0, green: 0.9, blue: 0.45) : ashDim)
                                    }
                                    Text("\(node.displayIP) · \(node.userLabel)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(ashDim)
                                    if let days = node.expiryDays {
                                        Text(days < 0 ? "EXPIRED — must re-authenticate" : "expires in \(days) day\(days == 1 ? "" : "s")")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(expiryColor(node))
                                    } else {
                                        Text("no expiry — eternal")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(ashDim.opacity(0.7))
                                    }
                                    HStack {
                                        Spacer()
                                        Button {
                                            wraith.statusMessage = "Hold CONFIRM to sever \(node.name) — it must re-authenticate to return."
                                        } label: {
                                            Image(systemName: "scissors")
                                                .foregroundColor(crimson.opacity(0.8))
                                                .font(.system(size: 12))
                                        }
                                        .simultaneousGesture(LongPressGesture().onEnded { _ in
                                            wraith.expireNode(node)
                                        })
                                        Text("hold to sever").font(.system(size: 9, design: .monospaced)).foregroundColor(ashDim.opacity(0.6))
                                    }
                                }
                                .padding(10)
                                .background(Color(red: 0.12, green: 0.02, blue: 0.05))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.3), lineWidth: 1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    WCard(title: "02 // OVERSEER WHISPERS") {
                        Text(wraith.statusMessage.isEmpty ? "The wraith watches \(wraith.nodes.filter { $0.online ?? false }.count) of \(wraith.nodes.count) nodes." : wraith.statusMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(wraith.statusMessage.contains("Rejected") || wraith.statusMessage.contains("Could not") ? crimson : ashText)
                    }
                }
                .padding(14)
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            HStack {
                Text("THE WRAITH")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                Spacer()
                Button { wraith.refresh() } label: {
                    Image(systemName: wraith.loading ? "hourglass" : "arrow.clockwise")
                        .foregroundColor(crimson)
                }
                .disabled(wraith.loading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
    }
}

// MARK: - REALM tab (users)

struct RealmView: View {
    @ObservedObject var wraith: WraithState

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    WCard(title: "01 // SOULS OF THE REALM") {
                        if wraith.users.isEmpty {
                            Text("No souls visible.")
                                .font(.system(size: 12)).foregroundColor(ashDim)
                        } else {
                            ForEach(wraith.users) { u in
                                HStack {
                                    Image(systemName: "person.fill")
                                        .foregroundColor(crimson)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(u.display)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(ashText)
                                        if let c = u.createdAt {
                                            Text("joined \(String(c.prefix(10)))")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(ashDim)
                                        }
                                    }
                                    Spacer()
                                    Text("\(wraith.nodes.filter { $0.user?.name == u.name || $0.user?.displayName == u.displayName }.count) nodes")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(ashDim)
                                }
                                .padding(9)
                                .background(Color(red: 0.12, green: 0.02, blue: 0.05))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.3), lineWidth: 1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    WCard(title: "02 // HOW THE REALM WORKS") {
                        Text("Every device joins through your Headscale on TrueNAS — the control server of your own tailnet, no outside cloud. The WireGuard tunnel itself runs in the official Tailscale app; Wraith is its eternal watcher.")
                            .font(.system(size: 12)).foregroundColor(ashText)
                    }
                }
                .padding(14)
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE REALM")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
    }
}

// MARK: - KEYS tab

struct KeysView: View {
    @ObservedObject var wraith: WraithState
    @State private var draftURL = ""
    @State private var draftKey = ""

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    WCard(title: "01 // SEAL THE OVERSEER") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Headscale URL")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ashDim)
                            TextField("http://100.85.127.42:8086", text: $draftURL)
                                .textFieldStyle(.plain)
                                .foregroundColor(ashText)
                                .font(.system(size: 12, design: .monospaced))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(9)
                                .background(Color(red: 0.1, green: 0.02, blue: 0.05))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.4), lineWidth: 1))
                            Text("Headscale API key (365-day)")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ashDim)
                            SecureField("paste hskey-api-…", text: $draftKey)
                                .textFieldStyle(.plain)
                                .foregroundColor(ashText)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(9)
                                .background(Color(red: 0.1, green: 0.02, blue: 0.05))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.4), lineWidth: 1))
                            WButton(title: "SEAL THE PACT") {
                                wraith.serverURL = draftURL.isEmpty ? wraith.serverURL : draftURL
                                wraith.apiKey = draftKey.isEmpty ? wraith.apiKey : draftKey
                                wraith.save()
                            }
                            HStack(spacing: 6) {
                                Circle().fill(wraith.linked ? Color(red: 0, green: 0.9, blue: 0.45) : Color(red: 1, green: 0.67, blue: 0))
                                    .frame(width: 9, height: 9)
                                Text(wraith.linked ? "LINKED — the realm answers" : "Not linked")
                                    .font(.system(size: 11, design: .monospaced)).foregroundColor(ashDim)
                            }
                        }
                    }
                    WCard(title: "02 // STATUS") {
                        Text(wraith.statusMessage.isEmpty ? (wraith.linked ? "Watching." : "Paste the URL and API key, then seal the pact.") : wraith.statusMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(wraith.statusMessage.contains("Rejected") || wraith.statusMessage.contains("Could not") ? crimson : ashText)
                    }
                }
                .padding(14)
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE KEYS")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
        .onAppear {
            draftURL = wraith.serverURL
            draftKey = wraith.apiKey
        }
    }
}
