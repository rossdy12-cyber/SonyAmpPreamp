import Foundation
import SwiftUI
import WebKit
import Combine

// MARK: - Tab

final class Tab: Identifiable, Equatable, ObservableObject {
    let id = UUID()
    let isPrivate: Bool
    let restoreURL: URL?
    var webView: WKWebView?
    var blocking = true
    var desktopUA = false
    var snapshot: UIImage?

    @Published var title: String = "New Tab"
    @Published var urlString: String = ""
    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false

    static func == (lhs: Tab, rhs: Tab) -> Bool { lhs.id == rhs.id }

    init(url: URL? = nil, isPrivate: Bool = false) {
        self.restoreURL = url
        self.isPrivate = isPrivate
    }

    var currentURL: URL? { webView?.url ?? restoreURL }
    var isActive: Bool { !urlString.isEmpty }

    var host: String? { currentURL?.host }
}

// MARK: - Download tracking

final class DownloadTask: ObservableObject, Identifiable {
    let id = UUID()
    var filename: String
    let url: URL
    @Published var progress: Double = 0
    @Published var done = false
    var localURL: URL?
    var resumeData: Data?

    init(url: URL) {
        self.url = url
        var name = url.lastPathComponent
        if name.isEmpty || name.contains("?") { name = "download-\(Int(Date().timeIntervalSince1970))" }
        self.filename = name
    }
}

// MARK: - Browser model

final class BrowserModel: NSObject, ObservableObject {
    static let shared = BrowserModel()
    let store = DataStore.shared

    @Published var tabs: [Tab] = []
    @Published var activeTabID: UUID?
    @Published var showTabSwitcher = false
    @Published var omniboxFocused = false
    @Published var omniboxText = ""
    @Published var downloads: [DownloadTask] = []
    @Published var pendingLinkMenu: LinkMenuInfo?
    @Published var pageError: PageErrorInfo?
    @Published var showFind = false
    @Published var toast: String?

    struct LinkMenuInfo: Identifiable {
        let id = UUID()
        let href: String
        let isImage: Bool
    }

    struct PageErrorInfo: Identifiable {
        let id = UUID()
        let message: String
    }

    var ruleList: WKContentRuleList?
    let persistentPool = WKProcessPool()
    let privatePool = WKProcessPool()

    override init() {
        super.init()
        Blocker.loadRuleList { [weak self] list in
            DispatchQueue.main.async {
                self?.ruleList = list
                for t in self?.tabs ?? [] { self?.applyBlocking(t) }
            }
        }
        restoreTabs()
        if tabs.isEmpty {
            let t = Tab()
            tabs = [t]
            activeTabID = t.id
        }
    }

    // MARK: Tabs

    var activeTab: Tab? { tabs.first { $0.id == activeTabID } }

    @discardableResult
    func newTab(url: URL? = nil, activate: Bool = true, privateMode: Bool? = nil) -> Tab {
        let isPrivate = privateMode ?? currentPrivateMode
        let t = Tab(url: url, isPrivate: isPrivate)
        tabs.append(t)
        if activate { activeTabID = t.id }
        persistTabs()
        return t
    }

    var currentPrivateMode = false

    func setPrivateMode(_ on: Bool) {
        currentPrivateMode = on
        objectWillChange.send()
    }

    func closeTab(_ t: Tab) {
        t.webView?.stopLoading()
        t.webView?.removeFromSuperview()
        t.webView = nil
        tabs.removeAll { $0.id == t.id }
        if activeTabID == t.id {
            activeTabID = tabs.last?.id
            if tabs.isEmpty { let n = newTab(activate: true); _ = n }
        }
        persistTabs()
    }

    func closeAllTabs() {
        for t in tabs { t.webView?.removeFromSuperview(); t.webView = nil }
        tabs.removeAll()
        let n = newTab(activate: true)
        _ = n
    }

    func activate(_ t: Tab) {
        activeTabID = t.id
        showTabSwitcher = false
        syncOmniboxText(t)
        persistTabs()
    }

    func syncOmniboxText(_ t: Tab? = nil) {
        omniboxText = OmniboxLogic.prettyURL((t ?? activeTab)?.currentURL)
    }

    // MARK: Navigation

    func navigate(_ raw: String, in t: Tab? = nil) {
        guard let tab = t ?? activeTab else { return }
        let (url, _) = OmniboxLogic.resolve(raw, engine: store.searchEngine)
        load(url, in: tab)
    }

    func load(_ url: URL, in t: Tab) {
        ensureWebView(t)
        let req = URLRequest(url: url)
        t.webView?.load(req)
        omniboxFocused = false
        pageError = nil
    }

    func reload(_ t: Tab? = nil) { (t ?? activeTab)?.webView?.reload() }
    func goBack(_ t: Tab? = nil) { (t ?? activeTab)?.webView?.goBack() }
    func goForward(_ t: Tab? = nil) { (t ?? activeTab)?.webView?.goForward() }
    func stop(_ t: Tab? = nil) { (t ?? activeTab)?.webView?.stopLoading() }

    func toggleDesktop(_ t: Tab? = nil) {
        guard let tab = t ?? activeTab, let wv = tab.webView else { return }
        tab.desktopUA.toggle()
        wv.customUserAgent = tab.desktopUA ? BrowserModel.desktopUA : nil
        wv.reload()
    }

    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"

    // MARK: WebView management

    func ensureWebView(_ t: Tab) -> WKWebView {
        if let w = t.webView { return w }
        let cfg = WKWebViewConfiguration()
        cfg.processPool = t.isPrivate ? privatePool : persistentPool
        cfg.websiteDataStore = t.isPrivate ? .nonPersistent() : .default()
        cfg.allowsInlineMediaPlayback = true
        cfg.preferences.isElementFullscreenEnabled = true
        cfg.userContentController.add(ConfigCoordinator(), name: "aegisMenu")
        if let rl = ruleList, t.blocking, store.blockerEnabled {
            cfg.userContentController.add(rl)
        }
        let scripts: [(String, WKUserScriptInjectionTime)] = [
            (Blocker.bootstrapJS, .atDocumentEnd),
            (Blocker.contextMenuJS, .atDocumentEnd),
            (Blocker.findJS, .atDocumentEnd)
        ]
        for (js, time) in scripts {
            cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: time, forMainFrameOnly: false))
        }
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.allowsBackForwardNavigationGestures = true
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.03, green: 0.01, blue: 0.02, alpha: 1)
        wv.scrollView.backgroundColor = .clear
        wv.navigationDelegate = self
        wv.uiDelegate = self
        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor(red: 0.86, green: 0.08, blue: 0.24, alpha: 1)
        refresh.addTarget(self, action: #selector(refreshPulled(_:)), for: .valueChanged)
        wv.scrollView.addSubview(refresh)
        t.webView = wv
        if let restore = t.restoreURL {
            wv.load(URLRequest(url: restore))
        }
        return wv
    }

    @objc private func refreshPulled(_ sender: UIRefreshControl) {
        guard let sv = sender.superview as? UIScrollView, let wv = sv.delegate as? WKWebView else { return }
        wv.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { sender.endRefreshing() }
    }

    func applyBlocking(_ t: Tab, host: String? = nil) {
        guard let wv = t.webView, let rl = ruleList else { return }
        let cc = wv.configuration.userContentController
        let targetHost = host ?? t.host
        let shouldBlock = store.blockerEnabled && !(targetHost.map { store.blockerWhitelist.contains($0) } ?? false)
        if shouldBlock != t.blocking {
            t.blocking = shouldBlock
            if shouldBlock { cc.add(rl) }
            else { cc.removeAllContentRuleLists() }
        }
    }

    func applySettingsToAllTabs() {
        let dark = store.forceDark
        let zoom = store.textZoom
        for t in tabs {
            guard let wv = t.webView else { continue }
            let js = "window.__aegisSetDark && __aegisSetDark(\(dark)); window.__aegisSetZoom && __aegisSetZoom(\(zoom));"
            wv.evaluateJavaScript(js, completionHandler: nil)
            applyBlocking(t)
        }
    }

    func snapshot(_ t: Tab, completion: @escaping (UIImage?) -> Void) {
        guard let wv = t.webView else { completion(nil); return }
        wv.takeSnapshot(with: nil) { img, _ in completion(img) }
    }

    // MARK: Persistence

    private func persistTabs() {
        let urls = tabs.filter { !$0.isPrivate }.compactMap { $0.webView?.url?.absoluteString ?? $0.restoreURL?.absoluteString }
        UserDefaults.standard.set(urls, forKey: "aegis.tabs")
    }

    private func restoreTabs() {
        guard let urls = UserDefaults.standard.stringArray(forKey: "aegis.tabs"), !urls.isEmpty else { return }
        for u in urls.prefix(10).compactMap(URL.init(string:)) {
            _ = newTab(url: u, activate: false)
        }
        activeTabID = tabs.first?.id
    }

    // MARK: Downloads

    func startDownload(from url: URL) {
        let task = DownloadTask(url: url)
        downloads.append(task)
        // carry webview cookies for authenticated downloads
        if let wv = activeTab?.webView {
            wv.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                for c in cookies { HTTPCookieStorage.shared.setCookie(c) }
            }
        }
        let req = URLRequest(url: url)
        let dTask = dlSession.downloadTask(with: req)
        taskToDownload[dTask] = task
        dTask.resume()
    }

    var taskToDownload: [URLSessionTask: DownloadTask] = [:]

    lazy var dlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        return URLSession(configuration: cfg, delegate: DLDelegate(model: self), delegateQueue: nil)
    }()

    func share(url: URL, from view: UIView?) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(vc, from: view)
    }

    func present(_ vc: UIViewController, from view: UIView?) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        if let view { vc.popoverPresentationController?.sourceView = view }
        top.present(vc, animated: true)
    }

    func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            if self?.toast == msg { self?.toast = nil }
        }
    }
}

// MARK: - Script message coordinator

final class ConfigCoordinator: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "aegisMenu", let body = message.body as? [String: Any],
              let href = body["href"] as? String else { return }
        let isImage = body["isImage"] as? Bool ?? false
        DispatchQueue.main.async {
            BrowserModel.shared.pendingLinkMenu = .init(href: href, isImage: isImage)
        }
    }
}

// MARK: - WKNavigationDelegate / UIDelegate

extension BrowserModel: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let tab = tabFor(webView), let host = navigationAction.request.url?.host {
            if navigationAction.navigationType == .linkActivated, navigationAction.targetFrame?.isMainFrame == true {
                applyBlocking(tab, host: host)
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let http = navigationResponse.response as? HTTPURLResponse else { decisionHandler(.allow); return }
        let mime = (http.mimeType ?? "").lowercased()
        let displayable = mime.contains("text/html") || mime.contains("xhtml") || mime.contains("image/") ||
            mime.contains("application/pdf") || mime.contains("text/plain") || mime.contains("video/") ||
            mime.contains("audio/") || mime.contains("javascript") || mime.contains("json") || mime.contains("xml")
        if !displayable, let url = navigationResponse.response.url {
            decisionHandler(.cancel)
            startDownload(from: url)
            showToast("Downloading…")
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let tab = tabFor(webView) else { return }
        tab.progress = 0.1
        if let u = webView.url {
            tab.urlString = u.absoluteString
        }
        applyBlocking(tab, host: webView.url?.host)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab = tabFor(webView) else { return }
        tab.progress = 1
        tab.title = webView.title?.isEmpty == false ? webView.title! : (webView.url?.host ?? "New Tab")
        tab.urlString = webView.url?.absoluteString ?? ""
        tab.canGoBack = webView.canGoBack
        tab.canGoForward = webView.canGoForward
        if !tab.isPrivate, let u = webView.url, u.scheme?.hasPrefix("http") == true {
            store.recordVisit(url: u.absoluteString, title: tab.title)
        }
        let js = "window.__aegisSetDark && __aegisSetDark(\(store.forceDark)); window.__aegisSetZoom && __aegisSetZoom(\(store.textZoom));"
        webView.evaluateJavaScript(js, completionHandler: nil)
        persistTabsPublic()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let tab = tabFor(webView) else { return }
        tab.progress = 0
        handleFail(error)
    }

    private func handleFail(_ error: Error) {
        let ns = error as NSError
        guard ns.code != NSURLErrorCancelled, ns.code != 102 else { return }
        pageError = .init(message: ns.localizedDescription)
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    // target=_blank -> new tab
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            let t = newTab(url: url, activate: true)
            _ = ensureWebView(t)
            if let idx = tabs.firstIndex(where: { $0.id == t.id }) {
                // container view will pick it up on activeTab change
                _ = idx
            }
        }
        return nil
    }

    // JS alert/confirm/prompt
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        alertJS(message: message, withOK: { completionHandler() })
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        alertJS(message: message, withOK: { completionHandler(true) }, withCancel: { completionHandler(false) })
    }

    private func alertJS(message: String, withOK: @escaping () -> Void, withCancel: (() -> Void)? = nil) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else { withOK(); return }
        var top = root
        while let p = top.presentedViewController { top = p }
        let alert = UIAlertController(title: "Aegis", message: message, preferredStyle: .alert)
        if let cancel = withCancel {
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in cancel() }))
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in withOK() }))
        top.present(alert, animated: true)
    }

    func tabFor(_ webView: WKWebView) -> Tab? {
        tabs.first { $0.webView == webView }
    }

    func persistTabsPublic() { persistTabs() }
}
