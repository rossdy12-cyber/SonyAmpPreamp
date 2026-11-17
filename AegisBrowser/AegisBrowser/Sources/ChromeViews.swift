import SwiftUI
import WebKit

struct BrowserScreen: View {
    @ObservedObject var model = BrowserModel.shared
    @ObservedObject var store = DataStore.shared

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Gothic.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    AddressBar()
                    ProgressBar()
                    ZStack {
                        WebContainer(model: model)
                        if model.activeTab?.currentURL == nil && !model.omniboxFocused {
                            NewTabPageView()
                        }
                        if let err = model.pageError {
                            ErrorCard(message: err.message)
                        }
                    }
                    BottomToolbar()
                }
                if model.omniboxFocused { OmniboxOverlay() }
                if model.showTabSwitcher { TabSwitcher() }
                if model.showFind { FindInPageBar() }
                if let toast = model.toast { ToastView(msg: toast) }
            }
            .onTapGesture { }
        }
        .onAppear {
            if let t = model.activeTab {
                t.webView?.evaluateJavaScript("window.__aegisSetDark && __aegisSetDark(\(store.forceDark)); window.__aegisSetZoom && __aegisSetZoom(\(store.textZoom));", completionHandler: nil)
            }
        }
        .sheet(item: sheetBinding) { which in
            switch which {
            case "downloads": DownloadsView()
            case "history": HistoryView()
            case "bookmarks": BookmarksView()
            case "settings": SettingsView()
            default: EmptyView()
            }
        }
        .confirmationDialog(item: $model.pendingLinkMenu) { info in
            LinkMenu(info: info)
        }
    }

    private var sheetBinding: Binding<String?> {
        Binding(get: { activeSheet }, set: { activeSheet = $0 })
    }
    @State private var activeSheet: String? = nil
}

// MARK: - Address bar

struct AddressBar: View {
    @ObservedObject var model = BrowserModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if model.activeTab?.isPrivate == true {
                Image(systemName: "theatermasks.fill")
                    .foregroundColor(Gothic.crimson)
            }
            HStack(spacing: 6) {
                Image(systemName: model.activeTab?.isPrivate == true ? "eye.slash" : "lock.shield")
                    .font(.system(size: 12))
                    .foregroundColor(Gothic.crimson.opacity(0.8))
                TextField("Search or enter address", text: $model.omniboxText)
                    .focused($focused)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .font(.system(size: 14, design: .rounded))
                    .onSubmit { model.navigate(model.omniboxText) }
                    .onTapGesture {
                        model.omniboxFocused = true
                        focused = true
                    }
                if !model.omniboxText.isEmpty {
                    Button { model.omniboxText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Gothic.field())
            .onChange(of: focused) { f in
                if !f { model.omniboxFocused = false; model.syncOmniboxText() }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Gothic.coal)
        .onChange(of: model.activeTabID) { _ in model.syncOmniboxText() }
        .onReceive(model.$omniboxFocused) { f in
            focused = f
        }
    }
}

struct ProgressBar: View {
    @ObservedObject var model = BrowserModel.shared
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.clear)
                Rectangle()
                    .fill(Gothic.crimson)
                    .frame(width: geo.size.width * CGFloat(model.activeTab?.progress ?? 0))
                    .animation(.linear(duration: 0.2), value: model.activeTab?.progress)
            }
        }
        .frame(height: 2)
    }
}

// MARK: - Bottom toolbar

struct BottomToolbar: View {
    @ObservedObject var model = BrowserModel.shared
    @State private var sheet: String? = nil
    @State private var showMenu = false

    var body: some View {
        HStack {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(model.activeTab?.canGoBack != true)
                .opacity(model.activeTab?.canGoBack == true ? 1 : 0.35)
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(model.activeTab?.canGoForward != true)
                .opacity(model.activeTab?.canGoForward == true ? 1 : 0.35)
            Button { sharePage() } label: { Image(systemName: "square.and.arrow.up") }
            Button { model.showTabSwitcher = true } label: {
                Text("\(model.tabs.count)").font(.system(size: 13, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Capsule().fill(Gothic.crimson.opacity(model.activeTab?.isPrivate == true ? 0.9 : 0.55)))
                    .foregroundColor(.white)
            }
            Menu {
                Button { model.newTab(activate: true) } label: { Label("New Tab", systemImage: "plus") }
                Button { model.setPrivateMode(!model.currentPrivateMode); model.newTab(activate: true) } label: {
                    Label(model.currentPrivateMode ? "New Normal Tab" : "New Private Tab", systemImage: "theatermasks")
                }
                Divider()
                Button { addFavorite() } label: { Label("Add to Favorites", systemImage: "star") }
                Button { addBookmark() } label: { Label("Add Bookmark", systemImage: "book") }
                Divider()
                Toggle(isOn: Binding(get: { model.activeTab?.desktopUA ?? false }, set: { _ in model.toggleDesktop() })) {
                    Label("Desktop Site", systemImage: "desktopcomputer")
                }
                Toggle(isOn: Binding(get: { store.forceDark }, set: { on in
                    store.forceDark = on; model.applySettingsToAllTabs()
                })) { Label("Force Dark", systemImage: "moon.fill") }
                Toggle(isOn: Binding(get: { store.blockerEnabled }, set: { on in
                    store.blockerEnabled = on; model.applySettingsToAllTabs()
                })) { Label("Ad Blocking", systemImage: "shield.lefthalf.filled") }
                if let host = model.activeTab?.host {
                    Button {
                        store.toggleWhitelist(host: host)
                        model.applySettingsToAllTabs()
                        model.reload()
                    } label: {
                        Label(store.blockerWhitelist.contains(host) ? "Enable Ads on \(host)" : "Disable Ads on \(host)", systemImage: "shield.slash")
                    }
                }
                Divider()
                Button { model.showFind = true } label: { Label("Find in Page", systemImage: "magnifyingglass") }
                Button { sheet = "downloads" } label: { Label("Downloads", systemImage: "arrow.down.circle") }
                Button { sheet = "bookmarks" } label: { Label("Bookmarks", systemImage: "book") }
                Button { sheet = "history" } label: { Label("History", systemImage: "clock") }
                Button { sheet = "settings" } label: { Label("Settings", systemImage: "gearshape") }
                Divider()
                Button { openInSafari() } label: { Label("Open in Safari", systemImage: "arrow.up.forward.app") }
                Button(role: .destructive) { clearPrivate() } label: { Label("Erase Cookies & Data", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .font(.system(size: 18))
        .foregroundColor(model.activeTab?.isPrivate == true ? Gothic.crimson : Gothic.ash)
        .padding(.horizontal, 26)
        .padding(.vertical, 9)
        .background(Gothic.coal)
        .sheet(item: Binding(get: { sheet.map { SheetID(id: $0) } }, set: { sheet = $0?.id })) { s in
            Group {
                switch s.id {
                case "downloads": DownloadsView()
                case "history": HistoryView()
                case "bookmarks": BookmarksView()
                case "settings": SettingsView()
                default: EmptyView()
                }
            }
        }
    }

    private func sharePage() {
        guard let url = model.activeTab?.currentURL else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        model.present(vc, from: nil)
    }

    private func openInSafari() {
        guard let url = model.activeTab?.currentURL else { return }
        UIApplication.shared.open(url)
    }

    private func addFavorite() {
        guard let url = model.activeTab?.currentURL else { return }
        store.addFavorite(url: url.absoluteString, title: model.activeTab?.title ?? "")
        model.showToast("Added to favorites")
    }

    private func addBookmark() {
        guard let url = model.activeTab?.currentURL else { return }
        store.addBookmark(url: url.absoluteString, title: model.activeTab?.title ?? "")
        model.showToast("Bookmarked")
    }

    private func clearPrivate() {
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeCookies, WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage],
                                                 modifiedSince: .distantPast) {
            model.showToast("Cookies & data erased")
        }
    }
}

struct SheetID: Identifiable { let id: String }

// MARK: - Omnibox suggestions overlay

struct OmniboxOverlay: View {
    @ObservedObject var model = BrowserModel.shared
    @ObservedObject var store = DataStore.shared

    private var suggestions: [(kind: String, title: String, sub: String, url: URL)] {
        let q = model.omniboxText.trimmingCharacters(in: .whitespaces)
        var out: [(String, String, String, URL)] = []
        if !q.isEmpty {
            let (resolved, isSearch) = OmniboxLogic.resolve(q, engine: store.searchEngine)
            if !isSearch {
                out.append(("Go", q, resolved.host ?? "", resolved))
            } else {
                out.append(("Search", q, store.searchEngine.rawValue, resolved))
            }
            let ql = q.lowercased()
            for h in store.history where h.url.lowercased().contains(ql) || h.title.lowercased().contains(ql) {
                if let u = URL(string: h.url) { out.append(("History", h.title, OmniboxLogic.prettyURL(u), u)) }
                if out.count > 8 { break }
            }
            for b in store.bookmarks where b.url.lowercased().contains(ql) || b.title.lowercased().contains(ql) {
                if let u = URL(string: b.url) { out.append(("Bookmark", b.title, OmniboxLogic.prettyURL(u), u)) }
                if out.count > 10 { break }
            }
        } else {
            for f in store.favorites.prefix(6) {
                if let u = URL(string: f.url) { out.append(("Favorite", f.title, OmniboxLogic.prettyURL(u), u)) }
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 56)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                        Button {
                            model.omniboxFocused = false
                            model.navigate(s.3.absoluteString)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: iconName(s.0))
                                    .foregroundColor(Gothic.crimson)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.1).foregroundColor(Gothic.ash).lineLimit(1)
                                    Text(s.2).font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
                                }
                                Spacer()
                                Text(s.0).font(.system(size: 10)).foregroundColor(.gray)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        Divider().overlay(Gothic.crimson.opacity(0.25))
                    }
                }
                .background(Gothic.bloodDark)
            }
            .frame(maxHeight: 320)
            .background(Gothic.bloodDark)
            .cornerRadius(0)
            Spacer(minLength: 0)
        }
        .background(Color.black.opacity(0.55).ignoresSafeArea().onTapGesture {
            model.omniboxFocused = false
        })
    }

    private func iconName(_ kind: String) -> String {
        switch kind {
        case "Go": return "globe"
        case "Search": return "magnifyingglass"
        case "History": return "clock.arrow.circlepath"
        case "Bookmark": return "book.fill"
        default: return "star.fill"
        }
    }
}

// MARK: - Tab switcher

struct TabSwitcher: View {
    @ObservedObject var model = BrowserModel.shared

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Toggle(isOn: Binding(get: { model.currentPrivateMode }, set: { on in
                    model.setPrivateMode(on)
                })) {
                    Label("Private", systemImage: "theatermasks.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .toggleStyle(.button)
                .tint(Gothic.crimson)
                Spacer()
                Button { model.closeAllTabs() } label: { Image(systemName: "xmark.circle") }
                Button { model.newTab(activate: true) } label: { Image(systemName: "plus.circle.fill") }
                    .font(.system(size: 22))
            }
            .padding(.horizontal, 14)
            .font(.system(size: 18))
            .foregroundColor(Gothic.ash)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.tabs) { tab in
                        TabCard(tab: tab)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 10)
        .background(Gothic.bg.ignoresSafeArea())
        .gesture(DragGesture().onEnded { g in
            if g.translation.height > 100 { model.showTabSwitcher = false }
        })
    }
}

struct TabCard: View {
    @ObservedObject var tab: Tab
    @ObservedObject var model = BrowserModel.shared

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: tab.isPrivate ? "theatermasks.fill" : "globe")
                    .font(.system(size: 10)).foregroundColor(Gothic.crimson)
                Text(tab.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    .foregroundColor(Gothic.ash)
                Spacer(minLength: 2)
                Button { model.closeTab(tab) } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                    .foregroundColor(.gray)
            }
            Button { model.activate(tab) } label: {
                TabSnapshotView(tab: tab)
                    .frame(width: 150, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(tab.id == model.activeTabID ? Gothic.crimson : Gothic.crimson.opacity(0.25), lineWidth: tab.id == model.activeTabID ? 2 : 1))
            }
            .onAppear { refreshSnapshot() }
        }
        .onAppear {
            Task { await refreshSnapshot() }
        }
    }

    private func refreshSnapshot() {
        guard tab.webView != nil else { return }
        model.snapshot(tab) { img in
            if let img { tab.snapshot = img }
        }
    }
}

// MARK: - Find in page

struct FindInPageBar: View {
    @ObservedObject var model = BrowserModel.shared
    @State private var query = ""
    @State private var count = 0

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(Gothic.crimson)
                TextField("Find in page", text: $query)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .onSubmit { run(0) }
                Text("\(count > 0 ? "" : "0")\(count) hits")
                    .font(.system(size: 11)).foregroundColor(.gray)
                Button { run(1) } label: { Image(systemName: "arrow.down") }
                Button { run(-1) } label: { Image(systemName: "arrow.up") }
                Button { model.showFind = false; clear() } label: { Image(systemName: "xmark") }
            }
            .padding(12)
            .background(Gothic.field())
            .padding(10)
        }
    }

    private func js() -> String {
        "window.__aegisFind.count(\(String(query.jsonEscaped)));"
    }

    private func run(_ dir: Int) {
        guard let wv = model.activeTab?.webView else { return }
        wv.evaluateJavaScript(js()) { res, _ in
            count = (res as? Int) ?? 0
        }
        if dir != 0 {
            wv.evaluateJavaScript("window.__aegisFind.step(\(dir)); 0", completionHandler: nil)
        }
    }

    private func clear() {
        model.activeTab?.webView?.evaluateJavaScript("window.__aegisFind.count(''); 0", completionHandler: nil)
    }
}

extension String {
    var jsonEscaped: String {
        let data = try? JSONEncoder().encode(self)
        return String(data: data ?? Data(), encoding: .utf8) ?? "''"
    }
}

// MARK: - Misc chrome

struct LinkMenu: View {
    let info: BrowserModel.LinkMenuInfo
    @ObservedObject var model = BrowserModel.shared

    var body: some View {
        Group {
            Button { openInNewTab(privateMode: false) } label: { Label("Open in New Tab", systemImage: "plus.square.on.square") }
            Button { openInNewTab(privateMode: true) } label: { Label("Open in Private Tab", systemImage: "theatermasks") }
            Button { copy() } label: { Label("Copy Link", systemImage: "doc.on.doc") }
            Button { model.startDownload(from: URL(string: info.href) ?? URL(fileURLWithPath: "/")) } label: { Label("Download", systemImage: "arrow.down.circle") }
            Button { share() } label: { Label("Share…", systemImage: "square.and.arrow.up") }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func openInNewTab(privateMode: Bool) {
        guard let url = URL(string: info.href) else { return }
        _ = model.newTab(url: url, activate: true, privateMode: privateMode)
    }

    private func copy() {
        UIPasteboard.general.string = info.href
        model.showToast("Link copied")
    }

    private func share() {
        guard let url = URL(string: info.href) else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        model.present(vc, from: nil)
    }
}

struct ErrorCard: View {
    let message: String
    @ObservedObject var model = BrowserModel.shared
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40)).foregroundColor(Gothic.crimson)
            Text("The crypt is unreachable")
                .font(.system(size: 17, weight: .bold)).foregroundColor(Gothic.ash)
            Text(message).font(.system(size: 12)).foregroundColor(.gray).multilineTextAlignment(.center)
            Button { model.reload() } label: { Text("Try Again").padding(.horizontal, 18).padding(.vertical, 8) }
                .background(Gothic.field())
                .foregroundColor(Gothic.crimson)
        }
        .padding(24)
        .background(Gothic.bloodDark)
        .cornerRadius(14)
        .padding(30)
    }
}

struct ToastView: View {
    let msg: String
    var body: some View {
        VStack {
            Spacer()
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Gothic.ash)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Gothic.field())
                .cornerRadius(20)
                .padding(.bottom, 70)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}
