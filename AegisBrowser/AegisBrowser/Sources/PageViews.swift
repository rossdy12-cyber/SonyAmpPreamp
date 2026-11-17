import SwiftUI

// MARK: - New tab page

struct NewTabPageView: View {
    @ObservedObject var store = DataStore.shared
    @ObservedObject var model = BrowserModel.shared

    private var frequentlyVisited: [HistoryEntry] {
        var seen = Set<String>()
        var out: [HistoryEntry] = []
        for h in store.history where !seen.contains(h.url) {
            if let u = URL(string: h.url), u.host != nil, !h.url.hasPrefix("https://duckduckgo.com") {
                seen.insert(h.url)
                out.append(h)
            }
            if out.count >= 6 { break }
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 26))
                        .foregroundColor(Gothic.crimson)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AEGIS").font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(Gothic.ash)
                        Text(store.blockerEnabled ? "Ad blocker armed · \(store.blockerWhitelist.count) sites exempt" : "Ad blocker disarmed")
                            .font(.system(size: 11)).foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding(.top, 18)

                if !store.favorites.isEmpty {
                    Text("FAVORITES").font(.system(size: 11, weight: .bold)).foregroundColor(Gothic.crimson)
                    let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.favorites) { f in
                            FavoriteCell(entry: f)
                        }
                        Menu {
                            ForEach(store.history.prefix(20)) { h in
                                Button(h.title) {
                                    store.addFavorite(url: h.url, title: h.title)
                                }
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14).fill(Gothic.field())
                                    Image(systemName: "plus").foregroundColor(Gothic.crimson)
                                }
                                .frame(width: 60, height: 60)
                                Text("Add").font(.system(size: 10)).foregroundColor(.gray)
                            }
                        }
                    }
                } else {
                    Text("Tap ⋯ → Add to Favorites to pin sites here.")
                        .font(.system(size: 12)).foregroundColor(.gray)
                }

                if !frequentlyVisited.isEmpty {
                    Text("RECENT HAUNTS").font(.system(size: 11, weight: .bold)).foregroundColor(Gothic.crimson)
                    VStack(spacing: 0) {
                        ForEach(frequentlyVisited) { h in
                            Button {
                                if let u = URL(string: h.url) { model.load(u, in: model.activeTab ?? model.newTab()) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath").foregroundColor(Gothic.crimson.opacity(0.7))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(h.title).foregroundColor(Gothic.ash).lineLimit(1)
                                        Text(OmniboxLogic.prettyURL(URL(string: h.url))).font(.system(size: 10)).foregroundColor(.gray).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 9)
                            }
                            Divider().overlay(Gothic.crimson.opacity(0.25))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }
}

struct FavoriteCell: View {
    let entry: FavoriteEntry
    @ObservedObject var model = BrowserModel.shared

    private var initial: String {
        String(entry.title.prefix(1)).uppercased()
    }

    var body: some View {
        Button {
            if let u = URL(string: entry.url) {
                model.load(u, in: model.activeTab ?? model.newTab())
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Gothic.field())
                    Text(initial)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(Gothic.crimson)
                }
                .frame(width: 60, height: 60)
                Text(entry.title).font(.system(size: 10)).foregroundColor(Gothic.ash).lineLimit(1)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                DataStore.shared.removeFavorite(entry)
            } label: { Label("Remove", systemImage: "trash") }
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @ObservedObject var store = DataStore.shared
    @ObservedObject var model = BrowserModel.shared
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [HistoryEntry] {
        let q = search.lowercased()
        return q.isEmpty ? store.history : store.history.filter { $0.url.lowercased().contains(q) || $0.title.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !filtered.isEmpty {
                    Button(role: .destructive) {
                        store.clearHistory()
                    } label: { Label("Clear All History", systemImage: "trash") }
                }
                ForEach(filtered) { h in
                    Button {
                        if let u = URL(string: h.url) {
                            model.load(u, in: model.activeTab ?? model.newTab())
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.title).lineLimit(1)
                            Text(h.date, style: .date).font(.system(size: 10)).foregroundColor(.gray)
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("History")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .scrollContentBackground(.hidden)
            .gothicChrome()
        }
    }
}

// MARK: - Bookmarks

struct BookmarksView: View {
    @ObservedObject var store = DataStore.shared
    @ObservedObject var model = BrowserModel.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.bookmarks) { b in
                    Button {
                        if let u = URL(string: b.url) {
                            model.load(u, in: model.activeTab ?? model.newTab())
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.title).lineLimit(1)
                            Text(OmniboxLogic.prettyURL(URL(string: b.url))).font(.system(size: 10)).foregroundColor(.gray).lineLimit(1)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.removeBookmark(b)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .scrollContentBackground(.hidden)
            .gothicChrome()
        }
    }
}

// MARK: - Downloads

struct DownloadsView: View {
    @ObservedObject var model = BrowserModel.shared
    @ObservedObject var store = DataStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.downloads) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.filename).lineLimit(1)
                        if d.done {
                            Text("Saved to Files → On My iPhone → Aegis/Downloads")
                                .font(.system(size: 10)).foregroundColor(.gray)
                        } else {
                            ProgressView(value: d.progress)
                                .tint(Gothic.crimson)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            if let entry = store.downloads.first(where: { $0.id == d.id }) { store.removeDownload(entry) }
                            model.downloads.removeAll { $0.id == d.id }
                        } label: { Label("Delete", systemImage: "trash") }
                        if d.done {
                            Button {
                                if let url = d.localURL ?? store.downloadsDir.appendingPathComponent(d.filename) as URL? {
                                    let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                                    model.present(vc, from: nil)
                                }
                            } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            .tint(Gothic.crimson)
                        }
                    }
                }
                ForEach(store.downloads) { e in
                    if !model.downloads.contains(where: { $0.id == e.id }) {
                        HStack {
                            Image(systemName: "arrow.down.circle").foregroundColor(Gothic.crimson)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.filename).lineLimit(1)
                                Text(e.date, style: .date).font(.system(size: 10)).foregroundColor(.gray)
                            }
                            Spacer()
                            Button {
                                let url = store.downloadsDir.appendingPathComponent(e.filename)
                                let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                                model.present(vc, from: nil)
                            } label: { Image(systemName: "square.and.arrow.up") }
                        }
                        .swipeActions {
                            Button(role: .destructive) { store.removeDownload(e) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                if store.downloads.isEmpty && model.downloads.isEmpty {
                    Text("No downloads yet. Files you download appear here and in the Files app.")
                        .font(.system(size: 12)).foregroundColor(.gray)
                }
            }
            .navigationTitle("Downloads")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .scrollContentBackground(.hidden)
            .gothicChrome()
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var store = DataStore.shared
    @ObservedObject var model = BrowserModel.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Search Engine") {
                    Picker("Engine", selection: Binding(get: { store.searchEngine }, set: { e in
                        store.searchEngine = e
                    })) {
                        ForEach(DataStore.SearchEngine.allCases) { e in
                            Text(e.rawValue).tag(e)
                        }
                    }
                }
                Section("Browsing") {
                    Toggle("Ad & Tracker Blocking", isOn: Binding(get: { store.blockerEnabled }, set: { on in
                        store.blockerEnabled = on
                        model.applySettingsToAllTabs()
                    }))
                    Toggle("Force Dark Pages", isOn: Binding(get: { store.forceDark }, set: { on in
                        store.forceDark = on
                        model.applySettingsToAllTabs()
                    }))
                    Stepper(value: Binding(get: { store.textZoom }, set: { z in
                        store.textZoom = z
                        model.applySettingsToAllTabs()
                    }), in: 50...200, step: 10) {
                        Text("Text Zoom: \(store.textZoom)%")
                    }
                }
                Section("Exempt Sites (ads allowed)") {
                    ForEach(Array(store.blockerWhitelist).sorted(), id: \.self) { host in
                        HStack {
                            Image(systemName: "shield.slash").foregroundColor(.gray)
                            Text(host)
                            Spacer()
                            Button("Remove") {
                                store.toggleWhitelist(host: host)
                                model.applySettingsToAllTabs()
                            }
                            .font(.system(size: 12))
                        }
                    }
                    if store.blockerWhitelist.isEmpty {
                        Text("Long-press ⋯ menu on any site to exempt it.").font(.system(size: 11)).foregroundColor(.gray)
                    }
                }
                Section("Danger") {
                    Button(role: .destructive) { store.clearHistory() } label: { Label("Clear History", systemImage: "clock.badge.xmark") }
                    Button(role: .destructive) {
                        model.closeAllTabs()
                    } label: { Label("Close All Tabs", systemImage: "xmark.square") }
                }
                Section("About") {
                    HStack { Text("Aegis Browser"); Spacer(); Text("v2.0.0").foregroundColor(.gray) }
                    Text("Gothic-hardened browser for the Stark fleet. Blocking \(blockerRuleCount) ad/tracker rules.")
                        .font(.system(size: 11)).foregroundColor(.gray)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .gothicChrome()
        }
    }

    private var blockerRuleCount: Int { "11,000+" }
}
