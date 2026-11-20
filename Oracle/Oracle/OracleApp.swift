import SwiftUI
import UIKit

// ============================================================
//  ORACLE — speak with DeepAI Code from anywhere
//  Chats with the headless agent running on the TrueNAS.
//  Nothing runs on this device but the crypt-glass UI.
// ============================================================

let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
let bloodDim = Color(red: 0.48, green: 0.05, blue: 0.13)
let ashText = Color(red: 0.96, green: 0.89, blue: 0.91)
let ashDim = Color(red: 0.69, green: 0.53, blue: 0.56)
let cryptBg = Color(red: 0.02, green: 0.004, blue: 0.012)

struct OracleMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: String   // "user" | "assistant"
    let text: String
    let ts: Double
}

final class OracleState: ObservableObject {
    @Published var serverURL: String
    @Published var secret: String
    @Published var signedIn = false
    @Published var messages: [OracleMessage] = []
    @Published var sessionId: String = ""
    @Published var working = false
    @Published var statusMessage = ""
    @Published var sessions: [SessionRow] = []
    @Published var signInURL: String = ""
    @Published var showSignInPaste = false

    struct SessionRow: Identifiable, Codable {
        let id: String
        let title: String
        let last: Double
    }

    private static let defaultsKey = "oracle.settings.v1"

    init() {
        let saved = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        serverURL = saved["url"] ?? "http://100.85.127.42:9395"
        secret = saved["secret"] ?? ""
        checkHealth()
    }

    func save() {
        UserDefaults.standard.set(["url": serverURL, "secret": secret], forKey: Self.defaultsKey)
        checkHealth()
    }

    private var base: String { serverURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    func checkHealth() {
        guard !base.isEmpty, !secret.isEmpty else { signedIn = false; return }
        guard let url = URL(string: "\(base)/v1/health") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let ready = (try? JSONDecoder().decode([String: Bool].self, from: data ?? Data()))?["ready"] ?? false
            DispatchQueue.main.async { self?.signedIn = ready }
        }.resume()
    }

    func startSignIn() {
        guard let url = URL(string: "\(base)/v1/signin/start") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(secret, forHTTPHeaderField: "X-Oracle-Secret")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            struct StartResp: Codable { let ok: Bool; let url: String?; let instructions: String? }
            let resp = try? JSONDecoder().decode(StartResp.self, from: data ?? Data())
            DispatchQueue.main.async {
                if let u = resp?.url {
                    self?.signInURL = u
                    self?.statusMessage = resp?.instructions ?? ""
                    self?.showSignInPaste = true
                } else {
                    self?.statusMessage = "Could not start sign-in — check the KEYS settings."
                }
            }
        }.resume()
    }

    func finishSignIn(paste: String) {
        guard let url = URL(string: "\(base)/v1/signin/finish") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(secret, forHTTPHeaderField: "X-Oracle-Secret")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["paste": paste])
        req.timeoutInterval = 30
        working = true
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            struct FinishResp: Codable { let ok: Bool; let error: String?; let username: String? }
            let resp = try? JSONDecoder().decode(FinishResp.self, from: data ?? Data())
            DispatchQueue.main.async {
                self?.working = false
                if resp?.ok == true {
                    self?.showSignInPaste = false
                    self?.statusMessage = "Sealed. The oracle is awake\(resp?.username.map({ " — \($0)" }) ?? "")."
                    self?.signedIn = true
                } else {
                    self?.statusMessage = resp?.error ?? "Sign-in failed."
                }
            }
        }.resume()
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !working else { return }
        let user = OracleMessage(id: UUID(), role: "user", text: trimmed, ts: Date().timeIntervalSince1970)
        messages.append(user)
        working = true
        statusMessage = ""
        guard let url = URL(string: "\(base)/v1/chat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(secret, forHTTPHeaderField: "X-Oracle-Secret")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 420
        struct ChatBody: Codable { let message: String; let session_id: String? }
        req.httpBody = try? JSONEncoder().encode(ChatBody(message: trimmed, session_id: sessionId.isEmpty ? nil : sessionId))
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            struct ChatResp: Codable { let ok: Bool; let session_id: String?; let reply: String?; let error: String? }
            let resp = try? JSONDecoder().decode(ChatResp.self, from: data ?? Data())
            DispatchQueue.main.async {
                guard let self else { return }
                self.working = false
                if let r = resp?.reply {
                    self.sessionId = resp?.session_id ?? self.sessionId
                    self.messages.append(OracleMessage(id: UUID(), role: "assistant", text: r, ts: Date().timeIntervalSince1970))
                } else {
                    self.statusMessage = resp?.error ?? "The oracle went silent — check the KEYS tab."
                }
            }
        }.resume()
    }

    func newSession() {
        sessionId = ""
        messages = []
        statusMessage = "Fresh page. The oracle awaits your question."
    }

    func loadSessions() {
        guard let url = URL(string: "\(base)/v1/sessions") else { return }
        var req = URLRequest(url: url)
        req.setValue(secret, forHTTPHeaderField: "X-Oracle-Secret")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            struct Resp: Codable { let ok: Bool; let sessions: [SessionRow]? }
            let resp = try? JSONDecoder().decode(Resp.self, from: data ?? Data())
            DispatchQueue.main.async { self?.sessions = resp?.sessions ?? [] }
        }.resume()
    }

    func loadHistory(_ sid: String) {
        guard let url = URL(string: "\(base)/v1/history/\(sid)") else { return }
        var req = URLRequest(url: url)
        req.setValue(secret, forHTTPHeaderField: "X-Oracle-Secret")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            struct Resp: Codable { let ok: Bool; let messages: [OracleMessage]? }
            let resp = try? JSONDecoder().decode(Resp.self, from: data ?? Data())
            DispatchQueue.main.async {
                if let m = resp?.messages, resp?.ok == true {
                    self?.sessionId = sid
                    self?.messages = m
                } else {
                    self?.statusMessage = "That session is unreadable."
                }
            }
        }.resume()
    }
}

// MARK: - Root

@main
struct OracleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var oracle = OracleState()

    var body: some View {
        TabView {
            ChatView(oracle: oracle)
                .tabItem { Label("CHAT", systemImage: "bubble.left.and.bubble.right.fill") }
            SessionsView(oracle: oracle)
                .tabItem { Label("PAGES", systemImage: "book.closed.fill") }
            KeysView(oracle: oracle)
                .tabItem { Label("KEYS", systemImage: "key.fill") }
        }
        .accentColor(crimson)
    }
}

// MARK: - Shared bits

struct OCard<Content: View>: View {
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
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 1, green: 0.09, blue: 0.27).opacity(0.38), lineWidth: 1))
        .cornerRadius(10)
    }
}

struct OButton: View {
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

// MARK: - CHAT tab

struct ChatView: View {
    @ObservedObject var oracle: OracleState
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if oracle.messages.isEmpty {
                                VStack(spacing: 8) {
                                    Text("THE ORACLE SLEEPS UNTIL QUESTIONED")
                                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                        .foregroundColor(ashDim)
                                    Text("Ask anything — it runs on your NAS, day or night, with or without a computer in sight.")
                                        .font(.system(size: 12))
                                        .foregroundColor(ashDim.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            }
                            ForEach(oracle.messages) { m in
                                HStack {
                                    if m.role == "user" { Spacer(minLength: 44) }
                                    Text(m.text)
                                        .font(.system(size: 13))
                                        .foregroundColor(m.role == "user" ? .white : ashText)
                                        .padding(11)
                                        .background(m.role == "user" ? bloodDim : Color(red: 0.09, green: 0.02, blue: 0.05))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(crimson.opacity(m.role == "user" ? 0.5 : 0.35), lineWidth: 1))
                                        .cornerRadius(12)
                                    if m.role != "user" { Spacer(minLength: 44) }
                                }
                                .id(m.id)
                            }
                            if oracle.working {
                                HStack {
                                    Text("The oracle is conjuring…")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(ashDim)
                                    Spacer()
                                }.padding(.horizontal, 6)
                            }
                            if !oracle.statusMessage.isEmpty {
                                Text(oracle.statusMessage)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(crimson)
                                    .padding(.horizontal, 6)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: oracle.messages.count) { _ in
                        if let last = oracle.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                Divider().overlay(crimson.opacity(0.4))
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Question the oracle…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .lineLimit(1...4)
                        .padding(10)
                        .background(Color(red: 0.1, green: 0.02, blue: 0.05))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.4), lineWidth: 1))
                        .cornerRadius(10)
                        .focused($focused)
                    Button {
                        oracle.send(draft)
                        draft = ""
                    } label: {
                        Image(systemName: oracle.working ? "hourglass" : "paperplane.fill")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(11)
                            .background(oracle.working ? Color(red: 0.25, green: 0.05, blue: 0.1) : bloodDim)
                            .cornerRadius(10)
                    }
                    .disabled(oracle.working || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(10)
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            HStack {
                Text("THE ORACLE")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                Spacer()
                Button { oracle.newSession() } label: {
                    Image(systemName: "plus.circle")
                        .foregroundColor(crimson)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack { Spacer()
                    Button("Done") { focused = false }.foregroundColor(crimson)
                }
            }
        }
    }
}

// MARK: - PAGES tab (session history)

struct SessionsView: View {
    @ObservedObject var oracle: OracleState

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    OCard(title: "01 // PAST CONSULTATIONS") {
                        if oracle.sessions.isEmpty {
                            Text("No pages yet. Every conversation is kept in the vault on your NAS.")
                                .font(.system(size: 12)).foregroundColor(ashDim)
                        } else {
                            ForEach(oracle.sessions) { s in
                                Button { oracle.loadHistory(s.id) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(ashText)
                                            .lineLimit(1)
                                        Text(Date(timeIntervalSince1970: s.last), style: .relative)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(ashDim)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color(red: 0.12, green: 0.02, blue: 0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.3), lineWidth: 1))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    OButton(title: "REFRESH THE VAULT") { oracle.loadSessions() }
                }
                .padding(14)
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE PAGES")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
        .onAppear { oracle.loadSessions() }
    }
}

// MARK: - KEYS tab (settings + sign-in)

struct KeysView: View {
    @ObservedObject var oracle: OracleState
    @State private var paste = ""
    @State private var draftURL = ""
    @State private var draftSecret = ""

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    OCard(title: "01 // LINK TO THE CRYPT") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Server URL")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ashDim)
                            TextField("http://100.85.127.42:9395", text: $draftURL)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(9)
                                .background(Color(red: 0.1, green: 0.02, blue: 0.05))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.4), lineWidth: 1))
                            Text("Shared secret (from the bridge log)")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ashDim)
                            SecureField("paste secret", text: $draftSecret)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(9)
                                .background(Color(red: 0.1, green: 0.02, blue: 0.05))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.4), lineWidth: 1))
                            OButton(title: "SEAL THE LINK") {
                                oracle.serverURL = draftURL.isEmpty ? oracle.serverURL : draftURL
                                oracle.secret = draftSecret.isEmpty ? oracle.secret : draftSecret
                                oracle.save()
                            }
                            HStack(spacing: 6) {
                                Circle().fill(oracle.signedIn ? Color(red: 0, green: 0.9, blue: 0.45) : Color(red: 1, green: 0.67, blue: 0))
                                    .frame(width: 9, height: 9)
                                Text(oracle.signedIn ? "LINKED — the oracle is awake" : "Not linked / not signed in")
                                    .font(.system(size: 11, design: .monospaced)).foregroundColor(ashDim)
                            }
                        }
                    }

                    OCard(title: "02 // WAKE THE ORACLE (DEEPAI SIGN-IN)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("One-time: sign in to DeepAI to grant the NAS agent its voice.")
                                .font(.system(size: 12)).foregroundColor(ashText)
                            OButton(title: "BEGIN SIGN-IN", enabled: !oracle.working) {
                                oracle.startSignIn()
                            }
                            if oracle.showSignInPaste {
                                Text(oracle.statusMessage)
                                    .font(.system(size: 11)).foregroundColor(ashDim)
                                TextField("paste the failed localhost URL (contains ?code=…)", text: $paste)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(9)
                                    .background(Color(red: 0.1, green: 0.02, blue: 0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(crimson.opacity(0.4), lineWidth: 1))
                                OButton(title: oracle.working ? "EXCHANGING…" : "COMPLETE SIGN-IN", enabled: !paste.isEmpty && !oracle.working) {
                                    oracle.finishSignIn(paste: paste)
                                    paste = ""
                                }
                            }
                        }
                    }

                    OCard(title: "STATUS") {
                        Text(oracle.statusMessage.isEmpty ? (oracle.signedIn ? "Ready." : "Configure the link above, then wake the oracle.") : oracle.statusMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(oracle.statusMessage.contains("failed") || oracle.statusMessage.contains("error") ? crimson : ashText)
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
            draftURL = oracle.serverURL
            draftSecret = oracle.secret
        }
    }
}
