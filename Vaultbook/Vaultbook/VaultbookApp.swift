import SwiftUI
import WebKit

// ============================================================
//  VAULTBOOK — Facebook, restyled in vampire crimson
//  A native sanctuary around Facebook's mobile web. Every page
//  is re-inked the moment it loads: near-black panels, crimson
//  accents, blood-red links. Login lives in the system cookie
//  jar; nothing is proxied and nothing leaves the device.
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

// MARK: - WebPit state

@MainActor
final class WebPit: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var riteOn = true
    @Published var status = "Awakening the tomb…"

    weak var webView: WKWebView?

    static let home = URL(string: "https://www.facebook.com/")!

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func refresh() { webView?.reload() }

    func goHome() {
        webView?.load(URLRequest(url: Self.home))
        status = "Home — the tomb reopens."
    }

    func syncChrome() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
    }

    func setRite(_ on: Bool) {
        riteOn = on
        webView?.evaluateJavaScript(on ? VaultRite.installJS : VaultRite.removeJS, completionHandler: nil)
        status = on ? "The rite is sealed — crimson rules this tomb." : "The rite is lifted — Facebook's own shroud returns."
    }

    func resealIfLifted() {
        if riteOn {
            webView?.evaluateJavaScript(VaultRite.installJS, completionHandler: nil)
        }
    }
}

// MARK: - BloodWebView

struct BloodWebView: UIViewRepresentable {
    @ObservedObject var pit: WebPit

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let ucc = cfg.userContentController
        ucc.addUserScript(WKUserScript(source: VaultRite.installJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.overrideUserInterfaceStyle = .dark
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.02, green: 0.004, blue: 0.012, alpha: 1)
        wv.scrollView.backgroundColor = wv.backgroundColor
        pit.webView = wv
        wv.load(URLRequest(url: WebPit.home))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(pit: pit) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let pit: WebPit

        init(pit: WebPit) { self.pit = pit }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.pit.syncChrome()
                self.pit.resealIfLifted()
                self.pit.status = "Fresh blood — the page has been re-inked in crimson."
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.pit.status = "The veil resisted: \(error.localizedDescription)"
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                self.pit.status = "The veil resisted: \(error.localizedDescription)"
            }
        }
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

    var body: some View {
        VStack(spacing: 0) {
            BloodWebView(pit: pit)
                .frame(maxHeight: .infinity)

            Text(pit.status)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(ashDim)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 18)
                .background(Color(red: 0.06, green: 0.01, blue: 0.03))

            gothicBar
        }
        .background(cryptBg.ignoresSafeArea())
    }

    var gothicBar: some View {
        HStack(spacing: 10) {
            barButton("chevron.left", enabled: pit.canGoBack, action: { pit.goBack() })
            barButton("chevron.right", enabled: pit.canGoForward, action: { pit.goForward() })
            barButton("arrow.clockwise", enabled: true, action: { pit.refresh() })
            barButton("house.fill", enabled: true, action: { pit.goHome() })
            Spacer()
            Button {
                pit.setRite(!pit.riteOn)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: pit.riteOn ? "drop.fill" : "drop")
                        .font(.system(size: 12, weight: .heavy))
                    Text("RITE")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                }
                .foregroundColor(pit.riteOn ? .white : ashDim)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(pit.riteOn ? crimson : Color(red: 0.1, green: 0.015, blue: 0.04))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(red: 0.06, green: 0.01, blue: 0.03))
        .overlay(Rectangle().frame(height: 1).foregroundColor(crimson.opacity(0.4)), alignment: .top)
    }

    func barButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(enabled ? ashText : ashDim.opacity(0.4))
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(Color(red: 0.1, green: 0.015, blue: 0.04))
                .cornerRadius(8)
        }
        .disabled(!enabled)
    }
}
