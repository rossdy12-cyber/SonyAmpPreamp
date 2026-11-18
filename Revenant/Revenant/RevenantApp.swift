import SwiftUI
import AVKit
import UIKit

// ============================================================
//  REVENANT — gothic vertical cinema
//  Sources: the Vault (Jellyfin AI-Shorts library on TrueNAS)
//           + the Archive (public-domain horror/sci-fi on Archive.org)
//  Studio:  import any video URL into the Vault via the NAS receiver
// ============================================================

let JF_BASES = ["http://192.168.0.185:30013", "http://100.85.127.42:30013"]
let JF_KEY = "5e78c9741800422189b6157a480fc075"
let RECEIVER_BASES = ["http://100.85.127.42:18998", "http://192.168.0.185:18998"]
let ARCHIVE_COLLECTIONS: [(id: String, name: String)] = [
    ("SciFi_Horror", "Sci-Fi & Horror"),
    ("feature_films", "Feature Films"),
    ("Film_Noir", "Film Noir"),
    ("classic_cartoons", "Classic Cartoons")
]

let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
let bloodDim = Color(red: 0.48, green: 0.05, blue: 0.13)
let ashText = Color(red: 0.96, green: 0.89, blue: 0.91)
let ashDim = Color(red: 0.69, green: 0.53, blue: 0.56)
let cryptBg = Color(red: 0.02, green: 0.004, blue: 0.012)

// MARK: - Models

struct ArchiveItem: Identifiable, Hashable {
    let id: String
    let title: String
    let collection: String
}

struct VaultItem: Identifiable, Hashable {
    let id: String
    let name: String
    let baseUrl: String
}

struct PlayableItem: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL
    let subtitle: String
}

// MARK: - Sources

final class RevenantSources: ObservableObject {
    @Published var vaultItems: [VaultItem] = []
    @Published var vaultStatus = "The vault is empty… import films in the Studio."
    @Published var feedItems: [PlayableItem] = []
    @Published var feedStatus = "Summoning the reels…"

    // MARK: Vault (Jellyfin)

    func loadVault() async {
        for base in JF_BASES {
            guard let userId = await jellyfinUserId(base) else { continue }
            guard let libId = await jellyfinLibraryId(base, userId) else {
                await MainActor.run { self.vaultStatus = "AI Shorts library missing on Jellyfin." }
                return
            }
            guard let url = URL(string: "\(base)/Users/\(userId)/Items?api_key=\(JF_KEY)&parentId=\(libId)&IncludeItemTypes=Movie&Recursive=true&sortBy=DateCreated&sortOrder=Descending&limit=100") else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let items = (json?["Items"] as? [[String: Any]]) ?? []
                let mapped: [VaultItem] = items.compactMap { dict in
                    guard let id = dict["Id"] as? String, let name = dict["Name"] as? String else { return nil }
                    return VaultItem(id: id, name: name, baseUrl: base)
                }
                await MainActor.run {
                    self.vaultItems = mapped
                    self.vaultStatus = mapped.isEmpty ? "The vault is empty… import films in the Studio." : "\(mapped.count) film(s) resting in the vault."
                }
                if !mapped.isEmpty { return }
            } catch { continue }
        }
        await MainActor.run { if vaultItems.isEmpty { vaultStatus = "The vault is out of reach (offline?)." } }
    }

    private func jellyfinUserId(_ base: String) async -> String? {
        guard let url = URL(string: "\(base)/Users?api_key=\(JF_KEY)") else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let users = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let uid = users.first?["Id"] as? String else { return nil }
        return uid
    }

    private func jellyfinLibraryId(_ base: String, _ userId: String) async -> String? {
        guard let url = URL(string: "\(base)/Users/\(userId)/Views?api_key=\(JF_KEY)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["Items"] as? [[String: Any]] else { return nil }
        for i in items {
            if (i["Name"] as? String) == "AI Shorts", let id = i["Id"] as? String { return id }
        }
        return nil
    }

    func vaultPlayable(_ v: VaultItem) -> URL? {
        URL(string: "\(v.baseUrl)/Videos/\(v.id)/stream.mp4?api_key=\(JF_KEY)&static=true")
    }

    // MARK: Archive (Archive.org)

    func loadFeedPicks() async {
        var picks: [PlayableItem] = []
        for v in vaultItems {
            if let u = vaultPlayable(v) {
                picks.append(PlayableItem(id: "vault_" + v.id, title: v.name, url: u, subtitle: "THE VAULT"))
            }
        }
        let archive = await archiveCollectionPicks("SciFi_Horror", count: 12)
        picks.append(contentsOf: archive)
        await MainActor.run {
            self.feedItems = picks
            self.feedStatus = picks.isEmpty ? "The crypt is silent." : ""
        }
    }

    func archiveCollectionPicks(_ collection: String, count: Int, page: Int = Int.random(in: 1...8)) async -> [PlayableItem] {
        guard let url = URL(string: "https://archive.org/advancedsearch.php?q=collection%3A%22\(collection)%22+AND+mediatype%3Amovies&fl%5B%5D=identifier&fl%5B%5D=title&rows=\(count * 2)&page=\(page)&output=json") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 Revenant", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let respObj = json["response"] as? [String: Any],
              let docs = respObj["docs"] as? [[String: Any]] else { return [] }
        var out: [PlayableItem] = []
        for d in docs.shuffled() {
            guard let id = d["identifier"] as? String else { continue }
            let title = (d["title"] as? String) ?? id
            if let play = await archivePlayable(id, title: title, collection: collection) {
                out.append(play)
                if out.count >= count { break }
            }
        }
        return out
    }

    func archivePlayable(_ identifier: String, title: String, collection: String) async -> PlayableItem? {
        guard let url = URL(string: "https://archive.org/metadata/\(identifier)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 Revenant", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let server = json["server"] as? String,
              let dir = json["dir"] as? String,
              let files = json["files"] as? [[String: Any]] else { return nil }
        let candidates = files
            .filter { ($0["name"] as? String)?.lowercased().hasSuffix(".mp4") == true }
            .compactMap { f -> (String, Int)? in
                guard let n = f["name"] as? String else { return nil }
                let size = Int(f["size"] as? String ?? "0") ?? 0
                return (n, size)
            }
            .sorted { a, b in
                let aPref = a.0.contains("512kb") ? 0 : 1
                let bPref = b.0.contains("512kb") ? 0 : 1
                if aPref != bPref { return aPref < bPref }
                return a.1 < b.1
            }
        guard let pick = candidates.first else { return nil }
        let encoded = pick.0.replacingOccurrences(of: " ", with: "%20")
        guard let playUrl = URL(string: "https://\(server)\(dir)/\(encoded)") else { return nil }
        return PlayableItem(id: identifier + "/" + pick.0, title: title, url: playUrl, subtitle: collection.uppercased())
    }

    // MARK: Studio (import via NAS receiver)

    func importUrl(_ urlString: String) async -> String {
        let clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.lowercased().hasPrefix("http") else { return "That is not a web address, sir." }
        for base in RECEIVER_BASES {
            guard let url = URL(string: "\(base)/sidestore-api/ai-shorts/import") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 900.0
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["url": clean])
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if (json["ok"] as? Bool) == true {
                    let mb = ((json["bytes"] as? Int) ?? 0) / (1024 * 1024)
                    await loadVault()
                    await loadFeedPicks()
                    return "Imported (\(mb) MB) — now resting in the vault."
                } else {
                    let err = (json["error"] as? String) ?? "unknown error"
                    if base == RECEIVER_BASES.last { return "Import failed: \(err)" }
                }
            } catch { continue }
        }
        return "The vault did not answer (offline?)."
    }
}

// MARK: - Root

@main
struct RevenantApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @StateObject private var sources = RevenantSources()

    var body: some View {
        TabView {
            FeedView(sources: sources)
                .tabItem { Label("REELS", systemImage: "play.rectangle.on.rectangle.fill") }
            BrowseView(sources: sources)
                .tabItem { Label("ARCHIVE", systemImage: "film.stack") }
            VaultView(sources: sources)
                .tabItem { Label("VAULT", systemImage: "archivebox.fill") }
            StudioView(sources: sources)
                .tabItem { Label("STUDIO", systemImage: "wand.and.stars") }
        }
        .accentColor(crimson)
        .onAppear {
            Task {
                await sources.loadVault()
                await sources.loadFeedPicks()
            }
        }
    }
}

// MARK: - Shared pieces

struct CryptPlaceholder: View {
    let text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "candleflame")
                .font(.system(size: 34))
                .foregroundColor(crimson)
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(ashDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cryptBg)
    }
}

struct PlayerSheet: View {
    let item: PlayableItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                Text(item.title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(radius: 4)
                Text(item.subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(crimson)
                Spacer()
            }
            .padding(14)
        }
        .onAppear {
            let p = AVPlayer(url: item.url)
            p.play()
            player = p
        }
        .onDisappear { player?.pause() }
    }
}

// MARK: - REELS (vertical pager)

struct FeedView: View {
    @ObservedObject var sources: RevenantSources

    var body: some View {
        Group {
            if sources.feedItems.isEmpty {
                CryptPlaceholder(text: sources.feedStatus)
            } else {
                VerticalPager(items: sources.feedItems)
                    .ignoresSafeArea()
            }
        }
        .background(cryptBg.ignoresSafeArea())
    }
}

struct VerticalPager: UIViewControllerRepresentable {
    let items: [PlayableItem]

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .vertical)
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        if let first = context.coordinator.pageController(at: 0) {
            pvc.setViewControllers([first], direction: .forward, animated: false)
        }
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.refresh(items: items, pvc: pvc)
    }

    func makeCoordinator() -> PagerCoordinator {
        PagerCoordinator(items: items)
    }

    final class PagerCoordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        let items: [PlayableItem]
        private var pageHosts: [Int: PageHostController] = [:]

        init(items: [PlayableItem]) {
            self.items = items
            super.init()
        }

        func refresh(items: [PlayableItem], pvc: UIPageViewController) {
            // items are fixed for the pager's lifetime in v1.0
        }

        func pageController(at index: Int) -> PageHostController? {
            guard index >= 0, index < items.count else { return nil }
            if let existing = pageHosts[index] { return existing }
            let host = PageHostController(item: items[index], index: index)
            pageHosts[index] = host
            return host
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let host = viewController as? PageHostController else { return nil }
            return pageController(at: host.index - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let host = viewController as? PageHostController else { return nil }
            return pageController(at: host.index + 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let visible = pageViewController.viewControllers?.first as? PageHostController else { return }
            for (_, host) in pageHosts where host !== visible {
                host.pause()
            }
            visible.play()
        }

        func presentationCount(for pageViewController: UIPageViewController) -> Int { items.count }
        func presentationIndex(for pageViewController: UIPageViewController) -> Int { 0 }
    }
}

// UIKit page hosting a full-bleed AVPlayer + gothic overlay

final class PageHostController: UIViewController {
    let item: PlayableItem
    let index: Int
    private var playerViewController: AVPlayerViewController?
    private var statusLabel: UILabel?

    init(item: PlayableItem, index: Int) {
        self.item = item
        self.index = index
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.02, green: 0.004, blue: 0.012, alpha: 1)

        let pvc = AVPlayerViewController()
        let player = AVPlayer(url: item.url)
        player.automaticallyWaitsToReduceStalling = true
        pvc.player = player
        pvc.showsPlaybackControls = false
        pvc.videoGravity = .resizeAspect
        addChild(pvc)
        view.addSubview(pvc.view)
        pvc.view.frame = view.bounds
        pvc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pvc.didMove(toParent: self)
        playerViewController = pvc

        // overlay: bottom gradient + titles + tap hint
        let gradient = CAGradientLayer()
        gradient.colors = [UIColor.clear.cgColor, UIColor(red: 0, green: 0, blue: 0, alpha: 0.85).cgColor]
        gradient.frame = CGRect(x: 0, y: view.bounds.height * 0.62, width: view.bounds.width, height: view.bounds.height * 0.38)
        gradient.autoresizingMask = [.flexibleHeight]
        view.layer.addSublayer(gradient)

        let sub = UILabel()
        sub.text = item.subtitle
        sub.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        sub.textColor = UIColor(red: 1.0, green: 0.09, blue: 0.27, alpha: 1)
        let title = UILabel()
        title.text = item.title
        title.font = UIFont.systemFont(ofSize: 17, weight: .heavy)
        title.textColor = .white
        title.numberOfLines = 3
        title.shadowColor = .black
        title.shadowOffset = CGSize(width: 0, height: 2)
        let hint = UILabel()
        hint.text = "tap to pause · swipe up for the next reel"
        hint.font = UIFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        hint.textColor = UIColor(white: 1, alpha: 0.55)

        let overlay = UIStackView(arrangedSubviews: [sub, title, hint])
        overlay.axis = .vertical
        overlay.alignment = .leading
        overlay.spacing = 5
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            overlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(togglePlay))
        view.addGestureRecognizer(tap)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        playerViewController?.view.frame = view.bounds
    }

    @objc private func togglePlay() {
        guard let pvc = playerViewController, let player = pvc.player else { return }
        if player.rate == 0 {
            player.play()
            flash("▶")
        } else {
            player.pause()
            flash("❚❚")
        }
    }

    private func flash(_ symbol: String) {
        let l = UILabel()
        l.text = symbol
        l.font = UIFont.systemFont(ofSize: 44, weight: .heavy)
        l.textColor = .white
        l.alpha = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        UIView.animate(withDuration: 0.5, animations: { l.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.4, animations: { l.alpha = 0 }) { _ in l.removeFromSuperview() }
        }
    }

    func play() {
        playerViewController?.player?.play()
    }

    func pause() {
        playerViewController?.player?.pause()
    }
}

// MARK: - ARCHIVE (browse collections)

struct BrowseView: View {
    @ObservedObject var sources: RevenantSources

    var body: some View {
        NavigationView {
            ZStack {
                cryptBg.ignoresSafeArea()
                List {
                    ForEach(ARCHIVE_COLLECTIONS, id: \.id) { c in
                        NavigationLink {
                            CollectionListView(collection: c)
                        } label: {
                            HStack {
                                Image(systemName: "film")
                                    .foregroundColor(crimson)
                                Text(c.name)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(ashText)
                                Spacer()
                                Text("ARCHIVE.ORG")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(ashDim)
                            }
                            .listRowBackground(Color(red: 0.06, green: 0.01, blue: 0.03))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("THE ARCHIVE")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CollectionListView: View {
    let collection: (id: String, name: String)
    @State private var items: [PlayableItem] = []
    @State private var status = "Digging through the archive…"
    @State private var playing: PlayableItem?

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            if items.isEmpty {
                CryptPlaceholder(text: status)
            } else {
                List(items) { item in
                    Button {
                        playing = item
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(ashText)
                                .lineLimit(2)
                            Text("tap to watch")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(ashDim)
                        }
                        .listRowBackground(Color(red: 0.06, green: 0.01, blue: 0.03))
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let picks = await sources.archiveCollectionPicks(collection.id, count: 30, page: Int.random(in: 1...10))
            items = picks
            status = picks.isEmpty ? "Nothing crawled out of this collection." : ""
        }
        .fullScreenCover(item: $playing) { item in
            PlayerSheet(item: item)
        }
    }
}

// MARK: - VAULT (Jellyfin AI Shorts)

struct VaultView: View {
    @ObservedObject var sources: RevenantSources
    @State private var playing: PlayableItem?

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            if sources.vaultItems.isEmpty {
                CryptPlaceholder(text: sources.vaultStatus)
            } else {
                List(sources.vaultItems) { v in
                    Button {
                        if let u = sources.vaultPlayable(v) {
                            playing = PlayableItem(id: "vault_" + v.id, title: v.name, url: u, subtitle: "THE VAULT")
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(v.name)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(ashText)
                                .lineLimit(2)
                            Text("tap to watch")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(ashDim)
                        }
                        .listRowBackground(Color(red: 0.06, green: 0.01, blue: 0.03))
                    }
                }
                .scrollContentBackground(.hidden)
                .refreshable {
                    await sources.loadVault()
                }
            }
        }
        .navigationTitle("")
        .overlay(alignment: .top) {
            Text("THE VAULT")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
        .fullScreenCover(item: $playing) { item in
            PlayerSheet(item: item)
        }
    }
}

// MARK: - STUDIO (import & generate)

struct StudioView: View {
    @ObservedObject var sources: RevenantSources
    @State private var urlText = ""
    @State private var statusMessage = ""
    @State private var importing = false

    var body: some View {
        ZStack {
            cryptBg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Import card
                    VStack(alignment: .leading, spacing: 9) {
                        Text("01 // IMPORT A FILM INTO THE VAULT")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(crimson)
                        Text("Paste a direct video link (mp4) — from any AI generator, cloud drive or web page. It downloads to TrueNAS and appears in the VAULT + REELS.")
                            .font(.system(size: 12))
                            .foregroundColor(ashDim)
                        TextField("https://…/my-video.mp4", text: $urlText)
                            .font(.system(size: 12, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button {
                            importing = true
                            statusMessage = "Importing… (large films take a few minutes)"
                            Task {
                                let result = await sources.importUrl(urlText)
                                await MainActor.run {
                                    statusMessage = result
                                    importing = false
                                    urlText = ""
                                }
                            }
                        } label: {
                            HStack {
                                if importing { ProgressView().tint(.white) }
                                Text(importing ? "SUMMONING…" : "IMPORT TO THE VAULT")
                            }
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(11)
                            .background(crimson)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(importing || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(13)
                    .background(Color(red: 0.06, green: 0.01, blue: 0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.35), lineWidth: 1))

                    // Generation guidance card
                    VStack(alignment: .leading, spacing: 9) {
                        Text("02 // GENERATE YOUR OWN")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(crimson)
                        Text("Create clips with any generator, then import the result:")
                            .font(.system(size: 12))
                            .foregroundColor(ashDim)
                        ForEach([
                            ("Sora (OpenAI)", "sora.chatgpt.com"),
                            ("Google Veo / Flow", "labs.google/flow"),
                            ("Kling AI", "klingai.com"),
                            ("Runway", "runwayml.com"),
                            ("Luma Dream Machine", "lumalabs.ai")
                        ], id: \.0) { g in
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(crimson)
                                Text(g.0)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(ashText)
                                Spacer()
                                Text(g.1)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(ashDim)
                            }
                        }
                        Text("Download the mp4 from the generator, host or copy its link, paste it above. The vault does the rest.")
                            .font(.system(size: 11))
                            .foregroundColor(ashDim)
                    }
                    .padding(13)
                    .background(Color(red: 0.06, green: 0.01, blue: 0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.25), lineWidth: 1))

                    // Tips
                    VStack(alignment: .leading, spacing: 6) {
                        Text("03 // HOW THE FEED WORKS")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(crimson)
                        Text("REELS mixes the vault (newest first) with freshly-dug classics from the Archive — Nosferatu, Caligari and 29,000 more films of the public domain. Swipe up for the next reel; tap to pause.")
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
            Text("THE STUDIO")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
                .padding(.top, 2)
        }
    }
}
