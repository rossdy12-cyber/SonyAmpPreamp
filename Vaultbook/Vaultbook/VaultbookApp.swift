import SwiftUI
import WebKit
import LocalAuthentication
import SafariServices

// ============================================================
//  VAULTBOOK v2 — Facebook as a native-feeling sanctum.
//  No browser chrome: Facebook's own mobile UI is the app.
//  Pull-to-refresh, edge-swipe back, autoplay video, external
//  links escape to Safari, long-press link menus, Face ID seal.
//  Login persists in the system cookie jar. Nothing is proxied.
// ============================================================

let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
let bloodDim = Color(red: 0.48, green: 0.05, blue: 0.13)
let ashText = Color(red: 0.96, green: 0.89, blue: 0.91)
let ashDim = Color(red: 0.69, green: 0.53, blue: 0.56)
let cryptBg = Color(red: 0.02, green: 0.004, blue: 0.012)

// MARK: - The Vampire Rite (injected stylesheet)

enum VaultRite {
    static let styleID = "vaultbook-rite"

    static let css = """
    :root { color-scheme: dark !important; }
    html, body { background-color:#0b0207 !important; color:#f0dee4 !important; }
    #header, #MComposer, #MBackActionBar, #MNewStoriesNavBar,
    div[role="banner"], div[role="navigation"], div[role="complementary"],
    div[role="contentinfo"] { background-color:#150309 !important; }
    article, div[role="article"], div[data-ft], .story_body_container {
      background-color:#1a0511 !important;
    }
    div[style*="background-color: rgb(255, 255, 255)"],
    div[style*="background-color: #fff"],
    div[style*="background-color:#fff"],
    div[style*="background-color: rgb(244, 244, 244)"] { background-color:#150309 !important; }
    h1, h2, h3, h4, h5, span, p, div, td, th, label, li {
      color:#f0dee4 !important;
    }
    div[data-sigil*="timestamp"], div.timestamp, abbr { color:#b78d97 !important; }
    a, [role="link"], [role="link"] * {
      color:#ff5f7e !important; text-decoration-color:#ff5f7e !important;
    }
    button, input[type="submit"], [role="button"] {
      background-color:#3a0812 !important; color:#ffdbe3 !important;
      border-color:#5a0c1e !important;
    }
    button *, [role="button"] * { color:#ffdbe3 !important; }
    button svg, div[role="button"] svg, [role="img"] svg { fill:#ff5f7e !important; }
    input, textarea, select {
      background-color:#1c0512 !important; color:#f5e6ea !important;
      border-color:#5a0c1e !important; caret-color:#ff1750 !important;
    }
    input::placeholder, textarea::placeholder { color:#8d6270 !important; }
    ::selection { background-color:#8a0e28 !important; }
    table { background-color:transparent !important; }
    hr { border-color:#4a0a1e !important; }
    """

    static var installJS: String {
        let data = try! JSONSerialization.data(withJSONObject: [css], options: [])
        let literal = String(data: data, encoding: .utf8)!
        return "var s=document.createElement('style');s.id='\(styleID)';s.textContent=\(literal)[0];(document.head||document.documentElement).appendChild(s);"
    }

    static var removeJS: String {
        "var s=document.getElementById('\(styleID)');if(s)s.remove();"
    }
}

// MARK: - Domain allowlist (main-frame stays in-app only for Facebook)

enum VaultGates {
    static func isSanctuary(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if host.isEmpty { return true }
        for d in ["facebook.com", "fbcdn.net", "fb.watch", "facebook.net",
                  "fbsbx.com", "messenger.com", "instagram.com", "threads.net"] {
            if host == d || host.hasSuffix("." + d) { return true }
        }
        return false
    }
}

// MARK: - State

@MainActor
final class WebPit: ObservableObject {
    @Published var riteOn = true
    @Published var loading = true
    @Published var firstLoaded = false
    @Published var showTools = false
    @Published var sealed = true
    @Published var toast = ""

    weak var webView: WKWebView?

    static let home = URL(string: "https://www.facebook.com/")!

    func sealDefaults() {
        let d = UserDefaults.standard
        if d.object(forKey: "vb_rite") == nil { d.set(true, forKey: "vb_rite") }
        if d.object(forKey: "vb_lock") == nil { d.set(true, forKey: "vb_lock") }
        riteOn = d.bool(forKey: "vb_rite")
        sealed = d.bool(forKey: "vb_lock")
    }

    func setRite(_ on: Bool) {
        riteOn = on
        UserDefaults.standard.set(on, forKey: "vb_rite")
        webView?.evaluateJavaScript(on ? VaultRite.installJS : VaultRite.removeJS, completionHandler: nil)
        toast = on ? "The rite is sealed." : "The rite is lifted."
    }

    func resealIfLifted() {
        if riteOn {
            webView?.evaluateJavaScript(VaultRite.installJS, completionHandler: nil)
        }
    }

    func goHome() {
        webView?.load(URLRequest(url: Self.home))
    }

    func openInSafari() {
        guard let u = webView?.url else { return }
        UIApplication.shared.open(u)
    }

    func forgetLogin() {
        let store = WKWebsiteDataStore.default()
        let types: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases
        ]
        store.removeData(ofTypes: types, modifiedSince: Date.distantPast) {
            Task { @MainActor in
                self.webView?.load(URLRequest(url: Self.home))
                self.toast = "The old pact is burned. Sign in anew."
            }
        }
    }
}

// MARK: - The Web View

struct BloodWebView: UIViewRepresentable {
    @ObservedObject var pit: WebPit

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let ucc = cfg.userContentController
        if pit.riteOn {
            ucc.addUserScript(WKUserScript(source: VaultRite.installJS,
                                           injectionTime: .atDocumentEnd,
                                           forMainFrameOnly: true))
        }
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsLinkPreview = true
        wv.overrideUserInterfaceStyle = .dark
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.02, green: 0.004, blue: 0.012, alpha: 1)
        wv.scrollView.backgroundColor = wv.backgroundColor
        wv.scrollView.decelerationRate = .normal

        let rc = UIRefreshControl()
        rc.tintColor = UIColor(red: 1.0, green: 0.09, blue: 0.27, alpha: 1)
        rc.addTarget(context.coordinator, action: #selector(Coordinator.pulled), for: .valueChanged)
        wv.scrollView.refreshControl = rc

        pit.webView = wv
        wv.load(URLRequest(url: WebPit.home))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(pit: pit) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let pit: WebPit

        init(pit: WebPit) { self.pit = pit }

        @objc func pulled() {
            pit.webView?.reload()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                self.pit.loading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.pit.loading = false
                self.pit.firstLoaded = true
                self.pit.resealIfLifted()
                webView.scrollView.refreshControl?.endRefreshing()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.pit.loading = false
                webView.scrollView.refreshControl?.endRefreshing()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.pit.loading = false
                webView.scrollView.refreshControl?.endRefreshing()
            }
        }

        // External main-frame links escape to Safari; Facebook stays inside.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme == "about" || scheme == "blob" || scheme == "data" {
                decisionHandler(.allow)
                return
            }
            let isMain = navigationAction.targetFrame?.isMainFrame ?? true
            if isMain && !VaultGates.isSanctuary(url) {
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
                return
            }
            decisionHandler(.allow)
        }

        // Long-press menus on links: copy / Safari.
        func webView(_ webView: WKWebView,
                     contextMenuConfigurationFor elementInfo: WKContextMenuElementInfo,
                     completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
            guard let url = elementInfo.linkURL else {
                completionHandler(nil)
                return
            }
            let config = UIContextMenuConfiguration(actionProvider: { _ in
                UIMenu(children: [
                    UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
                        UIPasteboard.general.string = url.absoluteString
                    },
                    UIAction(title: "Open in Safari", image: UIImage(systemName: "safari")) { _ in
                        UIApplication.shared.open(url)
                    }
                ])
            })
            completionHandler(config)
        }

        // New-window requests (target=_blank): open inside the same view.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}

// MARK: - Face ID seal

func unsealCrypt() async -> Bool {
    let ctx = LAContext()
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
        return true
    }
    do {
        return try await ctx.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unseal the vault")
    } catch {
        return false
    }
}

// MARK: - Root

@main
struct VaultbookApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @StateObject private var pit = WebPit()
    @State private var unsealed = false

    var body: some View {
        ZStack {
            BloodWebView(pit: pit)
                .ignoresSafeArea(edges: .bottom)

            if !pit.firstLoaded {
                splashOverlay
            }

            if pit.loading && pit.firstLoaded {
                VStack {
                    ProgressView()
                        .tint(crimson)
                        .padding(8)
                        .background(cryptBg.opacity(0.85))
                        .cornerRadius(10)
                    Spacer()
                }
                .padding(.top, 4)
            }

            toolsButton

            if !pit.toast.isEmpty {
                VStack {
                    Spacer()
                    Text(pit.toast)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ashText)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(bloodDim)
                        .cornerRadius(8)
                        .padding(.bottom, 96)
                }
                .transition(.opacity)
            }

            if pit.sealed && !unsealed {
                lockOverlay
            }
        }
        .background(cryptBg.ignoresSafeArea())
        .sheet(isPresented: $pit.showTools) {
            ToolsSheet(pit: pit)
        }
        .onAppear {
            pit.sealDefaults()
            if pit.sealed {
                Task {
                    unsealed = await unsealCrypt()
                }
            }
        }
        .onChange(of: pit.toast) { t in
            guard !t.isEmpty else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if pit.toast == t { pit.toast = "" }
            }
        }
    }

    var splashOverlay: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 42))
                    .foregroundColor(crimson)
                Text("VAULTBOOK")
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundColor(ashText)
                    .kerning(6)
                Text("opening the tomb…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ashDim)
                ProgressView()
                    .tint(crimson)
            }
        }
    }

    var lockOverlay: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundColor(crimson)
                Text("THE VAULT IS SEALED")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(ashText)
                Button {
                    Task {
                        unsealed = await unsealCrypt()
                    }
                } label: {
                    Text("UNSEAL")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 24)
                        .background(crimson)
                        .cornerRadius(9)
                }
            }
        }
    }

    var toolsButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    pit.showTools = true
                } label: {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(crimson.opacity(0.92))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                }
                .opacity(pit.firstLoaded ? 0.85 : 0)
                .padding(.trailing, 12)
                .padding(.bottom, 68)
            }
        }
    }
}

// MARK: - Tools sheet

struct ToolsSheet: View {
    @ObservedObject var pit: WebPit
    @Environment(\.presentationMode) var present

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("VAULTBOOK")
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundColor(crimson)
                        .frame(maxWidth: .infinity)

                    Toggle(isOn: Binding(
                        get: { pit.riteOn },
                        set: { pit.setRite($0) })) {
                        Text("VAMPIRE RITE")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(ashText)
                    }
                    .tint(crimson)

                    Toggle(isOn: Binding(
                        get: { pit.sealed },
                        set: { on in
                            pit.sealed = on
                            UserDefaults.standard.set(on, forKey: "vb_lock")
                        })) {
                        Text("FACE ID SEAL")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(ashText)
                    }
                    .tint(crimson)

                    sheetButton("HOME", icon: "house.fill") {
                        pit.goHome()
                        present.wrappedValue.dismiss()
                    }
                    sheetButton("OPEN PAGE IN SAFARI", icon: "safari") {
                        pit.openInSafari()
                        present.wrappedValue.dismiss()
                    }
                    sheetButton("FORGET LOGIN (LOG OUT)", icon: "person.badge.minus") {
                        pit.forgetLogin()
                        present.wrappedValue.dismiss()
                    }

                    Text("Facebook's own web app is the engine — the rite re-inks every page in crimson, external links escape to Safari, and your login lives in the system cookie jar.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(ashDim)
                }
                .padding(18)
            }
        }
    }

    func sheetButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(crimson)
                Text(title)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(ashText)
                Spacer()
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(Color(red: 0.1, green: 0.015, blue: 0.04))
            .cornerRadius(9)
        }
    }
}
