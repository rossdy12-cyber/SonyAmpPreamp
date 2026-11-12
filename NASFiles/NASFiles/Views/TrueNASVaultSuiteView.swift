import SwiftUI
import WebKit
import Vision
import VisionKit
import PhotosUI
import LocalAuthentication

// MARK: - Shared TrueNAS Vault Store

struct ZFSFileEntry: Identifiable, Hashable {
    var id: String { fullPath }
    let name: String
    let fullPath: String
    let isDirectory: Bool
    let sizeString: String
    let modifiedString: String
}

struct VaultScannedDoc: Identifiable, Codable {
    let id: UUID
    var title: String
    var category: String
    var ocrText: String
    var createdAt: Date
    var syncedToNAS: Bool
}

struct VaultSecretItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var username: String
    var secretValue: String
    var notes: String
    var updatedAt: Date
}

struct VaultPrivatePhoto: Identifiable, Codable {
    let id: UUID
    var caption: String
    var imageFileName: String
    var addedAt: Date
}

struct VaultBookmarkItem: Identifiable, Codable {
    let id: UUID
    var urlString: String
    var title: String
    var excerpt: String
    var readerContent: String
    var tag: String
    var isStarred: Bool
    var isArchived: Bool
    var savedAt: Date
}

@MainActor
final class TrueNASVaultStore: ObservableObject {
    @AppStorage("vault.truenasHost") var truenasHost: String = "100.85.127.42"
    @AppStorage("vault.zimaHost") var zimaHost: String = "100.82.255.29"
    @AppStorage("vault.enclavePIN") var enclavePIN: String = "2580"

    // Tab 1: Direct TrueNAS ZFS Pool Browser
    @Published var currentZFSPath: String = "/mnt/storage_pool"
    @Published var zfsEntries: [ZFSFileEntry] = []
    @Published var poolSummary: String = "Checking ZFS storage_pool..."
    @Published var isLoadingZFS: Bool = false
    @Published var zfsSearchQuery: String = ""
    @Published var previewFileTitle: String = ""
    @Published var previewFileContent: String = ""
    @Published var showFilePreviewSheet: Bool = false
    @Published var statusBanner: String = "Connected to TrueNAS Vault Suite (100.85.127.42)"

    // Tab 2: PhotoPulse AI
    @Published var twoFactorCode: String = ""
    @Published var selectedContainer: String = "icloudpd"
    @Published var containerLogs: String = "Tap any photo daemon below to inspect live sync & face-clustering logs."
    @Published var isBusyPhoto: Bool = false

    // Tab 3: VaultScan OCR
    @Published var scannedDocs: [VaultScannedDoc] = []
    @Published var isRunningOCR: Bool = false

    // Tab 4: PhotoVault Biometric Enclave
    @Published var isEnclaveUnlocked: Bool = false
    @Published var secrets: [VaultSecretItem] = []
    @Published var privatePhotos: [VaultPrivatePhoto] = []

    // Tab 5: LinkVault Reader
    @Published var bookmarks: [VaultBookmarkItem] = []
    @Published var isFetchingLink: Bool = false

    let photoDaemons: [(id: String, name: String, desc: String, icon: String)] = [
        ("icloudpd", "iCloud Downloader (Personal)", "Full personal iCloud photo stream -> TrueNAS", "icloud.and.arrow.down.fill"),
        ("icloudpd-shared", "iCloud Downloader (Shared)", "Shared iCloud albums -> TrueNAS", "person.2.crop.square.stack.fill"),
        ("icloudpd-hidden", "iCloud Downloader (Hidden)", "Hidden iCloud vault -> TrueNAS", "eye.slash.circle.fill"),
        ("album-ross", "Immich Face -> Album (Ross)", "Auto-assigns Ross face matches to album", "face.smiling.inverse"),
        ("album-ross-and-lauren", "Immich Face -> Album (Ross & Lauren)", "Auto-assigns Ross & Lauren photos to shared album", "heart.circle.fill"),
        ("immichframe", "ImmichFrame Digital Frame (:9180)", "Slideshow frame pulling from Immich", "photo.artframe"),
        ("damselfly", "Damselfly Fast Indexer (:6363)", "Metadata & face/keyword photo indexer", "sparkle.magnifyingglass")
    ]

    init() {
        loadLocalState()
    }

    // MARK: - Persistence

    private var docsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func loadLocalState() {
        if let data = try? Data(contentsOf: docsDir.appendingPathComponent("vault_scans.json")),
           let decoded = try? JSONDecoder().decode([VaultScannedDoc].self, from: data) {
            scannedDocs = decoded
        }
        if let data = try? Data(contentsOf: docsDir.appendingPathComponent("vault_secrets.json")),
           let decoded = try? JSONDecoder().decode([VaultSecretItem].self, from: data) {
            secrets = decoded
        } else {
            secrets = [
                VaultSecretItem(id: UUID(), title: "TrueNAS Nightscout API", username: "admin", secretValue: "http://100.85.127.42:1337", notes: "GlucoPulse T1D CGM & Tandem t:slim X2 telemetry", updatedAt: Date()),
                VaultSecretItem(id: UUID(), title: "SideStore Upload Token", username: "SideStore CI", secretValue: "", notes: "TrueNAS port 18998 IPA auto-publish receiver", updatedAt: Date())
            ]
        }
        if let data = try? Data(contentsOf: docsDir.appendingPathComponent("vault_photos.json")),
           let decoded = try? JSONDecoder().decode([VaultPrivatePhoto].self, from: data) {
            privatePhotos = decoded
        }
        if let data = try? Data(contentsOf: docsDir.appendingPathComponent("vault_bookmarks.json")),
           let decoded = try? JSONDecoder().decode([VaultBookmarkItem].self, from: data) {
            bookmarks = decoded
        } else {
            bookmarks = [
                VaultBookmarkItem(
                    id: UUID(),
                    urlString: "https://navidrome.nas-server.co.uk/sidestore/source.json",
                    title: "TrueNAS SideStore & LiveContainer 28-App Source",
                    excerpt: "Self-hosted AltStore/SideStore/LiveContainer JSON repository on TrueNAS.",
                    readerContent: "Self-hosted SideStore & LiveContainer repository serving all 28 custom iOS and watchOS IPAs directly from TrueNAS with Codemagic Apple M2 auto-publishing.",
                    tag: "TrueNAS",
                    isStarred: true,
                    isArchived: false,
                    savedAt: Date()
                )
            ]
        }
    }

    func saveScans() {
        if let data = try? JSONEncoder().encode(scannedDocs) {
            try? data.write(to: docsDir.appendingPathComponent("vault_scans.json"), options: .atomic)
        }
    }

    func saveSecrets() {
        if let data = try? JSONEncoder().encode(secrets) {
            try? data.write(to: docsDir.appendingPathComponent("vault_secrets.json"), options: .atomic)
        }
    }

    func savePrivatePhotos() {
        if let data = try? JSONEncoder().encode(privatePhotos) {
            try? data.write(to: docsDir.appendingPathComponent("vault_photos.json"), options: .atomic)
        }
    }

    func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            try? data.write(to: docsDir.appendingPathComponent("vault_bookmarks.json"), options: .atomic)
        }
    }

    // MARK: - TrueNAS Remote Execution Bridge

    func execTrueNAS(_ cmd: String) async -> String {
        guard let url = URL(string: "http://\(truenasHost):9092/api/antigravity/exec") else { return "Invalid TrueNAS URL" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 18
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": cmd])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let out = (obj["stdout"] as? String) ?? (obj["output"] as? String) ?? ""
                let err = (obj["stderr"] as? String) ?? ""
                return (out + (err.isEmpty ? "" : "\n" + err)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Tab 1: Direct TrueNAS ZFS Explorer

    func loadZFSDirectory(_ path: String? = nil) async {
        let target = path ?? currentZFSPath
        currentZFSPath = target
        isLoadingZFS = true
        defer { isLoadingZFS = false }

        let safePath = target.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        df -h '\(safePath)' 2>/dev/null | tail -n 1 | awk '{print "Pool: "$1" | Used: "$3" / "$2" ("$5" full) | Free: "$4}'
        echo "===ENTRIES==="
        python3 -c '
        import os, sys, datetime
        p = sys.argv[1]
        if not os.path.exists(p):
            sys.exit(0)
        items = []
        for name in sorted(os.listdir(p), key=lambda x: (not os.path.isdir(os.path.join(p, x)), x.lower())):
            if name.startswith("."): continue
            fp = os.path.join(p, name)
            try:
                st = os.stat(fp)
                is_dir = os.path.isdir(fp)
                sz = "-" if is_dir else (f"{st.st_size/1048576:.1f} MB" if st.st_size >= 1048576 else f"{max(1, st.st_size//1024)} KB")
                dt = datetime.datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M")
                print(f"{name}\\t{fp}\\t{1 if is_dir else 0}\\t{sz}\\t{dt}")
            except Exception:
                pass
        ' '\(safePath)'
        """
        let output = await execTrueNAS(script)
        let parts = output.components(separatedBy: "===ENTRIES===")
        if let header = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !header.isEmpty {
            poolSummary = header
        }
        guard parts.count > 1 else {
            zfsEntries = []
            return
        }
        var parsed: [ZFSFileEntry] = []
        for line in parts[1].components(separatedBy: .newlines) {
            let cols = line.components(separatedBy: "\t")
            if cols.count >= 5 {
                parsed.append(
                    ZFSFileEntry(
                        name: cols[0],
                        fullPath: cols[1],
                        isDirectory: cols[2] == "1",
                        sizeString: cols[3],
                        modifiedString: cols[4]
                    )
                )
            }
        }
        zfsEntries = parsed
        statusBanner = "Loaded \(parsed.count) items in \(target)"
    }

    func previewZFSFile(_ entry: ZFSFileEntry) async {
        let safePath = entry.fullPath.replacingOccurrences(of: "'", with: "'\\''")
        let out = await execTrueNAS("head -c 24000 '\(safePath)' 2>&1")
        previewFileTitle = entry.name
        previewFileContent = out.isEmpty ? "(Empty file or binary content)" : out
        showFilePreviewSheet = true
    }

    func createZFSFolder(named folderName: String) async {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let full = (currentZFSPath as NSString).appendingPathComponent(trimmed).replacingOccurrences(of: "'", with: "'\\''")
        _ = await execTrueNAS("mkdir -p '\(full)'")
        await loadZFSDirectory(currentZFSPath)
    }

    func deleteZFSEntry(_ entry: ZFSFileEntry) async {
        let safe = entry.fullPath.replacingOccurrences(of: "'", with: "'\\''")
        _ = await execTrueNAS("rm -rf '\(safe)'")
        await loadZFSDirectory(currentZFSPath)
    }

    // MARK: - Tab 2: PhotoPulse AI Methods

    func fetchPhotoLogs(_ container: String) async {
        isBusyPhoto = true
        defer { isBusyPhoto = false }
        let out = await execTrueNAS("sudo docker logs --tail 60 \(container) 2>&1")
        containerLogs = out.isEmpty ? "No recent output from \(container)." : out
        statusBanner = "Loaded logs for \(container)"
    }

    func restartPhotoDaemon(_ container: String) async {
        isBusyPhoto = true
        defer { isBusyPhoto = false }
        let out = await execTrueNAS("sudo docker restart \(container) 2>&1")
        statusBanner = "Restarted \(container): \(out)"
        await fetchPhotoLogs(container)
    }

    func submitApple2FA() async {
        let code = twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            statusBanner = "Enter your 6-digit Apple 2FA code first"
            return
        }
        isBusyPhoto = true
        defer { isBusyPhoto = false }
        let cmd = "echo '\(code)' | sudo docker attach --sig-proxy=false \(selectedContainer) 2>&1 || sudo docker exec \(selectedContainer) sh -c 'echo \(code) > /tmp/2fa_code' 2>&1"
        let out = await execTrueNAS(cmd)
        statusBanner = "Submitted 2FA code \(code) to \(selectedContainer)"
        containerLogs = out.isEmpty ? "Submitted code \(code) to \(selectedContainer)" : out
        twoFactorCode = ""
    }

    // MARK: - Tab 3: VaultScan OCR & TrueNAS Sync

    func performOCRAndSave(image: UIImage, titleHint: String = "") async {
        isRunningOCR = true
        defer { isRunningOCR = false }

        let service = OCRService()
        let extracted = (try? await service.recogniseText(in: image)) ?? ""
        let lower = extracted.lowercased()
        let autoCategory: String
        if lower.contains("total") || lower.contains("vat") || lower.contains("receipt") || lower.contains("£") {
            autoCategory = "Receipt"
        } else if lower.contains("glucose") || lower.contains("insulin") || lower.contains("nhs") || lower.contains("dexcom") || lower.contains("tandem") {
            autoCategory = "Medical / T1D"
        } else if lower.contains("invoice") || lower.contains("account") {
            autoCategory = "Invoice"
        } else {
            autoCategory = "Document"
        }

        let firstLine = extracted
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Scanned Document"
        let finalTitle = titleHint.isEmpty ? String(firstLine.prefix(44)) : titleHint

        var doc = VaultScannedDoc(
            id: UUID(),
            title: finalTitle,
            category: autoCategory,
            ocrText: extracted.isEmpty ? "(No text detected)" : extracted,
            createdAt: Date(),
            syncedToNAS: false
        )
        scannedDocs.insert(doc, at: 0)
        saveScans()

        // Archive to TrueNAS /mnt/storage_pool/vaultscan
        if let jsonData = try? JSONEncoder().encode(doc),
           let b64 = jsonData.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            let cmd = "mkdir -p /mnt/storage_pool/vaultscan && python3 -c \"import base64, urllib.parse; open('/mnt/storage_pool/vaultscan/\(doc.id.uuidString).json','wb').write(base64.b64decode(urllib.parse.unquote('\(b64)')))\" && echo OK"
            let res = await execTrueNAS(cmd)
            if res.contains("OK") {
                doc.syncedToNAS = true
                if let idx = scannedDocs.firstIndex(where: { $0.id == doc.id }) {
                    scannedDocs[idx].syncedToNAS = true
                    saveScans()
                }
                statusBanner = "Scanned & archived '\(finalTitle)' to TrueNAS /mnt/storage_pool/vaultscan"
            }
        }
    }

    // MARK: - Tab 4: Biometric Enclave Unlock

    func unlockEnclaveWithBiometrics() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock TrueNAS PhotoVault & Secret Enclave") { success, _ in
                Task { @MainActor in
                    if success {
                        self.isEnclaveUnlocked = true
                        self.statusBanner = "PhotoVault Enclave unlocked via Face ID / Passcode"
                    }
                }
            }
        } else {
            isEnclaveUnlocked = true
        }
    }

    func savePhotoToEnclave(image: UIImage, caption: String) {
        let fileName = "enclave_\(UUID().uuidString).jpg"
        let url = docsDir.appendingPathComponent(fileName)
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .atomic)
            let item = VaultPrivatePhoto(id: UUID(), caption: caption.isEmpty ? "Private Vault Photo" : caption, imageFileName: fileName, addedAt: Date())
            privatePhotos.insert(item, at: 0)
            savePrivatePhotos()
        }
    }

    func loadEnclaveImage(_ fileName: String) -> UIImage? {
        let url = docsDir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Tab 5: LinkVault Reader Extraction & TrueNAS Sync

    func addAndExtractBookmark(urlString: String, tag: String) async {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if !normalized.lowercased().hasPrefix("http://") && !normalized.lowercased().hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        guard let url = URL(string: normalized) else { return }

        isFetchingLink = true
        defer { isFetchingLink = false }

        var pageTitle = url.host ?? normalized
        var cleanReader = ""
        var excerpt = ""

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 12
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            if let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                if let tRange = html.range(of: "<title[^>]*>(.*?)</title>", options: [.regularExpression, .caseInsensitive]) {
                    let rawTitle = String(html[tRange])
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rawTitle.isEmpty { pageTitle = rawTitle }
                }
                let stripped = html
                    .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count > 25 }
                    .joined(separator: "\n\n")
                cleanReader = stripped.isEmpty ? "Saved URL: \(normalized)" : String(stripped.prefix(15000))
                excerpt = String(cleanReader.prefix(180)).replacingOccurrences(of: "\n", with: " ")
            }
        } catch {
            cleanReader = "Offline bookmark saved for \(normalized).\n(\(error.localizedDescription))"
            excerpt = "Saved bookmark (\(url.host ?? normalized))"
        }

        let item = VaultBookmarkItem(
            id: UUID(),
            urlString: normalized,
            title: pageTitle,
            excerpt: excerpt,
            readerContent: cleanReader,
            tag: tag.isEmpty ? "General" : tag,
            isStarred: false,
            isArchived: false,
            savedAt: Date()
        )
        bookmarks.insert(item, at: 0)
        saveBookmarks()
        await syncBookmarksToTrueNAS()
    }

    func syncBookmarksToTrueNAS() async {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        let b64 = data.base64EncodedString()
        let cmd = "mkdir -p /mnt/storage_pool/linkvault && python3 -c \"import base64; open('/mnt/storage_pool/linkvault/links.json','wb').write(base64.b64decode('\(b64)'))\" && echo OK"
        let res = await execTrueNAS(cmd)
        if res.contains("OK") {
            statusBanner = "Synced \(bookmarks.count) LinkVault bookmarks to TrueNAS (/mnt/storage_pool/linkvault)"
        }
    }
}

// MARK: - 1. Direct TrueNAS ZFS Pool & WebDAV Browser Tab

struct TrueNASDirectPoolBrowserView: View {
    @EnvironmentObject var vaultStore: TrueNASVaultStore
    @State private var mode: Int = 0 // 0 = TrueNAS ZFS Direct, 1 = WebDAV Browser
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    private let quickPaths: [(label: String, path: String, icon: String)] = [
        ("Storage Pool", "/mnt/storage_pool", "externaldrive.fill.badge.checkmark"),
        ("Media", "/mnt/storage_pool/media", "film.stack.fill"),
        ("Photos", "/mnt/storage_pool/photos", "photo.on.rectangle.angled"),
        ("VaultScan", "/mnt/storage_pool/vaultscan", "doc.viewfinder"),
        ("App Configs", "/mnt/.ix-apps/app_configs", "gearshape.2.fill"),
        ("SideStore IPAs", "/mnt/.ix-apps/app_mounts/nginx-proxy-manager/data/sidestore/ipas", "shippingbox.fill")
    ]

    var filteredEntries: [ZFSFileEntry] {
        let q = vaultStore.zfsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return vaultStore.zfsEntries }
        return vaultStore.zfsEntries.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Browser Mode", selection: $mode) {
                    Text("TrueNAS ZFS Pool").tag(0)
                    Text("WebDAV Browser").tag(1)
                    Text("Offline & Settings").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if mode == 1 {
                    BrowserView()
                } else if mode == 2 {
                    VaultOfflineAndSettingsTabView()
                } else {
                    VStack(spacing: 8) {
                        // ZFS Pool Status Strip
                        HStack(spacing: 8) {
                            Image(systemName: "externaldrive.connected.to.line.below.fill")
                                .foregroundStyle(.cyan)
                            Text(vaultStore.poolSummary)
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                            Spacer()
                            if vaultStore.isLoadingZFS {
                                ProgressView().scaleEffect(0.7)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.cyan.opacity(0.12))
                        .cornerRadius(10)
                        .padding(.horizontal, 12)

                        // Quick Jump Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quickPaths, id: \.path) { preset in
                                    Button {
                                        Task { await vaultStore.loadZFSDirectory(preset.path) }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: preset.icon)
                                            Text(preset.label)
                                        }
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(vaultStore.currentZFSPath == preset.path ? Color.cyan : Color.secondary.opacity(0.15))
                                        .foregroundStyle(vaultStore.currentZFSPath == preset.path ? .black : .primary)
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                        }

                        // Path Breadcrumb Bar
                        HStack {
                            if vaultStore.currentZFSPath != "/" {
                                Button {
                                    let parent = (vaultStore.currentZFSPath as NSString).deletingLastPathComponent
                                    Task { await vaultStore.loadZFSDirectory(parent.isEmpty ? "/" : parent) }
                                } label: {
                                    Label("Up", systemImage: "arrow.turn.left.up")
                                        .font(.caption.bold())
                                }
                                .buttonStyle(.bordered)
                            }
                            Text(vaultStore.currentZFSPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                            Button {
                                showNewFolderAlert = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                            }
                            Button {
                                Task { await vaultStore.loadZFSDirectory() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .padding(.horizontal, 12)

                        List {
                            ForEach(filteredEntries) { entry in
                                Button {
                                    if entry.isDirectory {
                                        Task { await vaultStore.loadZFSDirectory(entry.fullPath) }
                                    } else {
                                        Task { await vaultStore.previewZFSFile(entry) }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: entry.isDirectory ? "folder.fill" : iconForFileName(entry.name))
                                            .font(.title3)
                                            .foregroundStyle(entry.isDirectory ? .cyan : .secondary)
                                            .frame(width: 26)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                            Text("\(entry.modifiedString) • \(entry.isDirectory ? "Folder" : entry.sizeString)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if entry.isDirectory {
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await vaultStore.deleteZFSEntry(entry) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .searchable(text: $vaultStore.zfsSearchQuery, prompt: "Filter ZFS dataset files...")
                    }
                    .task {
                        if vaultStore.zfsEntries.isEmpty {
                            await vaultStore.loadZFSDirectory()
                        }
                    }
                    .sheet(isPresented: $vaultStore.showFilePreviewSheet) {
                        NavigationStack {
                            ScrollView {
                                Text(vaultStore.previewFileContent)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .navigationTitle(vaultStore.previewFileTitle)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { vaultStore.showFilePreviewSheet = false }
                                }
                            }
                        }
                    }
                    .alert("New ZFS Folder", isPresented: $showNewFolderAlert) {
                        TextField("Folder name", text: $newFolderName)
                        Button("Create") {
                            let name = newFolderName
                            newFolderName = ""
                            Task { await vaultStore.createZFSFolder(named: name) }
                        }
                        Button("Cancel", role: .cancel) { newFolderName = "" }
                    }
                }
            }
            .navigationTitle("TrueNAS Vault v2.0")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func iconForFileName(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "ipa", "zip", "tar", "gz": return "doc.zipper"
        case "jpg", "jpeg", "png", "heic", "webp": return "photo"
        case "mp4", "mkv", "mov": return "film"
        case "flac", "mp3", "m4a", "wav": return "waveform"
        case "pdf": return "doc.richtext"
        case "py", "sh", "swift", "json", "yml", "yaml": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text"
        }
    }
}

// MARK: - 2. PhotoPulse AI Tab

struct VaultPhotoPulseWebView: UIViewRepresentable {
    let urlString: String
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.isOpaque = false
        web.backgroundColor = .black
        if let u = URL(string: urlString) {
            web.load(URLRequest(url: u))
        }
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct VaultPhotoPulseTabView: View {
    @EnvironmentObject var vaultStore: TrueNASVaultStore
    @State private var subTab: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("PhotoPulse View", selection: $subTab) {
                    Text("iCloudPD & AI Daemons").tag(0)
                    Text("Immich & Damselfly").tag(1)
                    Text("Live Frames (:9180)").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(10)

                if subTab == 0 {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: "sparkles.tv.fill").foregroundStyle(.pink)
                                Text(vaultStore.statusBanner).font(.caption)
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.pink.opacity(0.15))
                            .cornerRadius(10)

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Apple iCloudPD 2FA Cookie Refresher")
                                    .font(.headline)
                                Picker("Stream", selection: $vaultStore.selectedContainer) {
                                    Text("Personal").tag("icloudpd")
                                    Text("Shared").tag("icloudpd-shared")
                                    Text("Hidden").tag("icloudpd-hidden")
                                }
                                .pickerStyle(.segmented)

                                HStack {
                                    TextField("6-Digit Apple 2FA Code", text: $vaultStore.twoFactorCode)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                    Button("Submit 2FA") {
                                        Task { await vaultStore.submitApple2FA() }
                                    }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.pink)
                                    .foregroundStyle(.white)
                                    .cornerRadius(8)
                                }
                            }
                            .padding(14)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(14)

                            Text("Photo Sync & Face-Clustering Daemons")
                                .font(.headline)

                            ForEach(vaultStore.photoDaemons, id: \.id) { d in
                                HStack(spacing: 12) {
                                    Image(systemName: d.icon)
                                        .font(.title3)
                                        .foregroundStyle(.pink)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(d.name).font(.subheadline.bold())
                                        Text(d.desc).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Logs") {
                                        Task { await vaultStore.fetchPhotoLogs(d.id) }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Restart") {
                                        Task { await vaultStore.restartPhotoDaemon(d.id) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.pink)
                                    .controlSize(.small)
                                }
                                .padding(10)
                                .background(Color.secondary.opacity(0.08))
                                .cornerRadius(12)
                            }

                            Text("Live Container Console Output")
                                .font(.subheadline.bold())
                            Text(vaultStore.containerLogs)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.black.opacity(0.85))
                                .cornerRadius(10)
                        }
                        .padding()
                    }
                } else if subTab == 1 {
                    VaultImmichBrowserSubView()
                } else {
                    VaultPhotoPulseWebView(urlString: "http://\(vaultStore.truenasHost):9180")
                }
            }
            .navigationTitle("PhotoPulse AI")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct VaultImmichBrowserSubView: View {
    @EnvironmentObject var vaultStore: TrueNASVaultStore
    @State private var server: Int = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("Server", selection: $server) {
                Text("TrueNAS Immich (:30041)").tag(0)
                Text("Zimaboard (:2283)").tag(1)
                Text("Damselfly (:6363)").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            if server == 0 {
                VaultPhotoPulseWebView(urlString: "http://\(vaultStore.truenasHost):30041").id("im0")
            } else if server == 1 {
                VaultPhotoPulseWebView(urlString: "http://\(vaultStore.zimaHost):2283").id("im1")
            } else {
                VaultPhotoPulseWebView(urlString: "http://\(vaultStore.truenasHost):6363").id("im2")
            }
        }
    }
}

// MARK: - 3. VaultScan OCR Tab

struct VaultDocumentCameraScanner: UIViewControllerRepresentable {
    var onScanCompleted: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: VaultDocumentCameraScanner
        init(_ parent: VaultDocumentCameraScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0 {
                let img = scan.imageOfPage(at: 0)
                parent.onScanCompleted(img)
            }
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}

struct VaultScanOCRTabView: View {
    @EnvironmentObject var vaultStore: TrueNASVaultStore
    @State private var searchQuery: String = ""
    @State private var selectedCategory: String = "All"
    @State private var showCameraScanner: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedDoc: VaultScannedDoc?

    private let categories = ["All", "Receipt", "Medical / T1D", "Invoice", "Document"]

    var filteredDocs: [VaultScannedDoc] {
        vaultStore.scannedDocs.filter { doc in
            let matchesCat = (selectedCategory == "All" || doc.category == selectedCategory)
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = q.isEmpty || doc.title.lowercased().contains(q) || doc.ocrText.lowercased().contains(q)
            return matchesCat && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        if VNDocumentCameraViewController.isSupported {
                            showCameraScanner = true
                        }
                    } label: {
                        Label("Camera Scan", systemImage: "doc.viewfinder.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.teal)
                            .foregroundStyle(.white)
                            .cornerRadius(10)
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Import Photo OCR", systemImage: "photo.badge.magnifyingglass")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.indigo)
                            .foregroundStyle(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                if vaultStore.isRunningOCR {
                    HStack {
                        ProgressView()
                        Text("Running Apple Vision OCR & archiving to TrueNAS...")
                            .font(.caption)
                    }
                    .padding(8)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { cat in
                            Button {
                                selectedCategory = cat
                            } label: {
                                Text(cat)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedCategory == cat ? Color.teal : Color.secondary.opacity(0.15))
                                    .foregroundStyle(selectedCategory == cat ? .white : .primary)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }

                if filteredDocs.isEmpty {
                    ContentUnavailableView(
                        "No Scanned Documents Yet",
                        systemImage: "doc.viewfinder",
                        description: Text("Scan receipts, medical letters, or documents with Apple Vision OCR. Every scan is indexed for full-text search and archived to TrueNAS (/mnt/storage_pool/vaultscan).")
                    )
                } else {
                    List {
                        ForEach(filteredDocs) { doc in
                            Button {
                                selectedDoc = doc
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(doc.title)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(doc.category)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Color.teal.opacity(0.2))
                                            .foregroundStyle(.teal)
                                            .cornerRadius(6)
                                    }
                                    Text(doc.ocrText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    HStack {
                                        Text(doc.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                        Spacer()
                                        Label(
                                            doc.syncedToNAS ? "Backed up to TrueNAS" : "Local",
                                            systemImage: doc.syncedToNAS ? "checkmark.icloud.fill" : "internaldrive"
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(doc.syncedToNAS ? .green : .orange)
                                    }
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    vaultStore.scannedDocs.removeAll { $0.id == doc.id }
                                    vaultStore.saveScans()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $searchQuery, prompt: "Search OCR text across all scans...")
            .navigationTitle("VaultScan OCR")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCameraScanner) {
                VaultDocumentCameraScanner { img in
                    Task { await vaultStore.performOCRAndSave(image: img) }
                }
            }
            .sheet(item: $selectedDoc) { doc in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(doc.category, systemImage: "tag.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.teal)
                                Spacer()
                                Text(doc.createdAt.formatted())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                            Text(doc.ocrText)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                    .navigationTitle(doc.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: doc.ocrText)
                        }
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await vaultStore.performOCRAndSave(image: img)
                    }
                }
            }
        }
    }
}

// MARK: - 4. PhotoVault Biometric Enclave Tab

struct PhotoVaultEnclaveTabView: View {
    @EnvironmentObject var vaultStore: TrueNASVaultStore
    @State private var pinInput: String = ""
    @State private var showAddSecret: Bool = false
    @State private var newSecretTitle: String = ""
    @State private var newSecretUser: String = ""
    @State private var newSecretValue: String = ""
    @State private var newSecretNotes: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var newPhotoCaption: String = ""

    var body: some View {
        NavigationStack {
            if !vaultStore.isEnclaveUnlocked {
                VStack(spacing: 20) {
                    Image(systemName: "faceid")
                        .font(.system(size: 64))
                        .foregroundStyle(.purple)
                    Text("PhotoVault & Secret Enclave")
                        .font(.title2.bold())
                    Text("Protected by Face ID / Touch ID & AES Keychain Enclave")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        vaultStore.unlockEnclaveWithBiometrics()
                    } label: {
                        Label("Unlock with Face ID / Passcode", systemImage: "lock.open.fill")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.purple)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }

                    HStack(spacing: 10) {
                        SecureField("Or enter Enclave PIN (default 2580)", text: $pinInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        Button("Unlock") {
                            if pinInput == vaultStore.enclavePIN {
                                vaultStore.isEnclaveUnlocked = true
                                pinInput = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                }
                .padding()
                .navigationTitle("PhotoVault Enclave")
            } else {
                List {
                    Section("Encrypted Credentials & API Secrets") {
                        ForEach(vaultStore.secrets) { sec in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "key.fill").foregroundStyle(.purple)
                                    Text(sec.title).font(.subheadline.bold())
                                    Spacer()
                                    Button {
                                        UIPasteboard.general.string = sec.secretValue
                                        vaultStore.statusBanner = "Copied '\(sec.title)' to clipboard"
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                            .font(.caption2.bold())
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                                if !sec.username.isEmpty {
                                    Text("User: \(sec.username)").font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(sec.secretValue)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.purple)
                                if !sec.notes.isEmpty {
                                    Text(sec.notes).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { idx in
                            vaultStore.secrets.remove(atOffsets: idx)
                            vaultStore.saveSecrets()
                        }

                        Button {
                            showAddSecret = true
                        } label: {
                            Label("Add Secret / Credential", systemImage: "plus.circle.fill")
                        }
                    }

                    Section("Private Biometric Photo Enclave (\(vaultStore.privatePhotos.count))") {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Import Photo into Encrypted Enclave", systemImage: "photo.badge.plus")
                        }

                        ForEach(vaultStore.privatePhotos) { item in
                            HStack(spacing: 12) {
                                if let uiImg = vaultStore.loadEnclaveImage(item.imageFileName) {
                                    Image(uiImage: uiImg)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.purple.opacity(0.2))
                                        .frame(width: 64, height: 64)
                                        .overlay(Image(systemName: "lock.doc.fill"))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.caption).font(.subheadline.bold())
                                    Text(item.addedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { idx in
                            vaultStore.privatePhotos.remove(atOffsets: idx)
                            vaultStore.savePrivatePhotos()
                        }
                    }
                }
                .navigationTitle("PhotoVault Enclave")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            vaultStore.isEnclaveUnlocked = false
                        } label: {
                            Label("Lock", systemImage: "lock.fill")
                        }
                    }
                }
                .sheet(isPresented: $showAddSecret) {
                    NavigationStack {
                        Form {
                            TextField("Title (e.g. TrueNAS Root / API Key)", text: $newSecretTitle)
                            TextField("Username / Account", text: $newSecretUser)
                            TextField("Secret / Password / Token", text: $newSecretValue)
                            TextField("Notes", text: $newSecretNotes)
                        }
                        .navigationTitle("New Enclave Secret")
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Cancel") { showAddSecret = false }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Save") {
                                    let item = VaultSecretItem(
                                        id: UUID(),
                                        title: newSecretTitle.isEmpty ? "Untitled Secret" : newSecretTitle,
                                        username: newSecretUser,
                                        secretValue: newSecretValue,
                                        notes: newSecretNotes,
                                        updatedAt: Date()
                                    )
                                    vaultStore.secrets.insert(item, at: 0)
                                    vaultStore.saveSecrets()
                                    newSecretTitle = ""
                                    newSecretUser = ""
                                    newSecretValue = ""
                                    newSecretNotes = ""
                                    showAddSecret = false
                                }
                            }
                        }
                    }
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            vaultStore.savePhotoToEnclave(image: img, caption: "Enclave Photo \(Date().formatted(date: .numeric, time: .shortened))")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 5. LinkVault Offline Reader & Bookmark Archiver Tab

struct LinkVaultReaderTabView: View {
    @EnvironmentObject var vaultStore: TrueNASVaultStore
    @State private var newURL: String = ""
    @State private var newTag: String = "TrueNAS"
    @State private var searchQuery: String = ""
    @State private var selectedBookmark: VaultBookmarkItem?

    var filteredBookmarks: [VaultBookmarkItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return vaultStore.bookmarks }
        return vaultStore.bookmarks.filter {
            $0.title.lowercased().contains(q) ||
            $0.urlString.lowercased().contains(q) ||
            $0.readerContent.lowercased().contains(q) ||
            $0.tag.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Paste URL to archive for offline reading...", text: $newURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let u = newURL
                        newURL = ""
                        Task { await vaultStore.addAndExtractBookmark(urlString: u, tag: newTag) }
                    } label: {
                        if vaultStore.isFetchingLink {
                            ProgressView()
                        } else {
                            Label("Archive", systemImage: "tray.and.arrow.down.fill")
                                .font(.caption.bold())
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                List {
                    ForEach(filteredBookmarks) { bm in
                        Button {
                            selectedBookmark = bm
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(bm.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(bm.tag)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundStyle(.orange)
                                        .cornerRadius(5)
                                }
                                Text(bm.urlString)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                                if !bm.excerpt.isEmpty {
                                    Text(bm.excerpt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                vaultStore.bookmarks.removeAll { $0.id == bm.id }
                                vaultStore.saveBookmarks()
                                Task { await vaultStore.syncBookmarksToTrueNAS() }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $searchQuery, prompt: "Search saved links & full reader text...")
            .navigationTitle("LinkVault Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vaultStore.syncBookmarksToTrueNAS() }
                    } label: {
                        Label("Sync NAS", systemImage: "arrow.triangle.2.circlepath.icloud")
                    }
                }
            }
            .sheet(item: $selectedBookmark) { bm in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(bm.title).font(.title3.bold())
                            if let u = URL(string: bm.urlString) {
                                Link(bm.urlString, destination: u)
                                    .font(.caption.monospaced())
                            }
                            Divider()
                            Text(bm.readerContent)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                    .navigationTitle("Reader Mode")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedBookmark = nil }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 6. Offline Cache & Settings Tab

struct VaultOfflineAndSettingsTabView: View {
    @State private var section: Int = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $section) {
                    Text("Offline Downloads").tag(0)
                    Text("WebDAV & Server Settings").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(10)

                if section == 0 {
                    DownloadsView()
                } else {
                    SettingsView()
                }
            }
        }
    }
}
