import SwiftUI

struct PairFilesView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var sync: SyncManager
    @Environment(\.dismiss) private var dismiss

    let pairID: UUID

    @State private var items: [Item] = []
    @State private var showingModePicker = false
    @State private var confirmUnpair = false

    private var pair: Pair? { store.pair(id: pairID) }

    struct Item: Identifiable, Hashable {
        let url: URL
        let isDirectory: Bool
        let size: Int64
        let modified: Date?

        var id: String { url.path }
        var name: String { url.lastPathComponent }
    }

    var body: some View {
        List {
            if let pair {
                Section {
                    HStack(spacing: 10) {
                        StatusDot(state: sync.isRunning(pair.id) ? .busy : (pair.lastError == nil ? .ok : .error))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pair.lastSync == nil ? "Not synced yet" : pair.lastSummary ?? "Up to date")
                                .font(.subheadline.weight(.medium))
                            Text("\(relativeTime(pair.lastSync)) · \(pair.mode.label)")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button {
                            Task { await sync.sync(pairID: pair.id) }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderless)
                        .disabled(sync.isRunning(pair.id))
                    }
                    .listRowBackground(Theme.panel)
                    if let error = pair.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.err)
                            .listRowBackground(Theme.panel)
                    }
                }

                if items.isEmpty {
                    Section {
                        Text("This folder is empty.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .listRowBackground(Theme.panel)
                    }
                } else {
                    Section {
                        ForEach(items) { item in
                            if item.isDirectory {
                                NavigationLink {
                                    PairFilesView(pairID: pairID, subpath: joined(subpath, item.name))
                                        .environmentObject(store)
                                        .environmentObject(sync)
                                } label: {
                                    row(item)
                                }
                                .listRowBackground(Theme.panel)
                            } else {
                                Button {
                                    previewing = item
                                } label: {
                                    row(item)
                                }
                                .listRowBackground(Theme.panel)
                            }
                        }
                    } header: {
                        Text(subpath.isEmpty ? "Files" : subpath)
                    }
                }
            }
        }
        .screenBackground()
        .listStyle(.insetGrouped)
        .navigationTitle(pair?.shareName ?? "Folder")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await sync.sync(pairID: pairID)
            reload()
        }
        .onAppear(perform: reload)
        .onChange(of: sync.isBusy) { _, busy in
            if !busy { reload() }
        }
        .sheet(item: $previewing) { item in
            FilePreview(item: item)
        }
        .confirmationDialog("Sync mode", isPresented: $showingModePicker) {
            ForEach(SyncMode.allCases) { mode in
                Button(mode.label) {
                    store.mutatePair(id: pairID) { $0.mode = mode }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Unpair this folder?", isPresented: $confirmUnpair) {
            Button("Unpair", role: .destructive) {
                store.removePair(pairID)
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await sync.sync(pairID: pairID) }
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        showingModePicker = true
                    } label: {
                        Label("Sync mode: \(pair?.mode.label ?? "")", systemImage: "slider.horizontal.3")
                    }
                    if let pair {
                        ShareLink(item: store.folderURL(for: pair)) {
                            Label("Open in Files", systemImage: "folder")
                        }
                    }
                    Button {
                        if let pair {
                            store.resetBaseline(for: pair)
                            store.mutatePair(id: pairID) { stored in
                                stored.lastSync = nil
                                stored.lastSummary = "Baseline cleared"
                                stored.lastError = nil
                            }
                            store.notify("Baseline cleared — next sync re-baselines")
                        }
                    } label: {
                        Label("Forget sync history", systemImage: "clock.arrow.circlepath")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmUnpair = true
                    } label: {
                        Label("Unpair", systemImage: "link.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    @State private var subpath: String = ""
    @State private var previewing: Item?

    init(pairID: UUID, subpath: String = "") {
        self.pairID = pairID
        _subpath = State(initialValue: subpath)
    }

    private func joined(_ base: String, _ name: String) -> String {
        base.isEmpty ? name : "\(base)/\(name)"
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.isDirectory ? "folder.fill" : icon(for: item.name))
                .foregroundStyle(item.isDirectory ? Theme.accent : Theme.muted)
                .font(.system(size: 15))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Text(item.isDirectory ? "Folder" : "\(fileSize(item.size)) · \(relativeTime(item.modified))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
    }

    private func icon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo"
        case "pdf": return "doc.richtext"
        case "md", "txt", "rtf": return "doc.text"
        case "mp3", "m4a", "wav", "flac": return "waveform"
        case "mov", "mp4", "m4v": return "film"
        case "zip": return "archivebox"
        case "swift", "js", "py", "json", "yml", "yaml", "html", "css": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    private func reload() {
        guard let pair else { return }
        var url = store.folderURL(for: pair)
        for component in subpath.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            items = []
            return
        }
        items = entries.compactMap { entry in
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else {
                return nil
            }
            return Item(
                url: entry,
                isDirectory: values.isDirectory ?? false,
                size: Int64(values.fileSize ?? 0),
                modified: values.contentModificationDate
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

// MARK: - Preview

struct FilePreview: View {
    @Environment(\.dismiss) private var dismiss

    let item: PairFilesView.Item

    @State private var text: String?
    @State private var image: UIImage?
    @State private var note: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if let text {
                        Text(text)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "doc")
                                .font(.system(size: 34))
                                .foregroundStyle(Theme.muted)
                            Text(note ?? "No inline preview for this file type.")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: item.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .task { load() }
        }
    }

    private func load() {
        let ext = (item.name as NSString).pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) {
            image = UIImage(contentsOfFile: item.url.path)
            if image == nil { note = "Could not decode this image." }
            return
        }
        let textExtensions = ["txt", "md", "json", "yml", "yaml", "swift", "js", "ts", "py", "html", "css", "csv", "log", "sh", "xml", "plist", "ini", "conf"]
        guard textExtensions.contains(ext) || ext.isEmpty else { return }
        guard item.size < 2_000_000 else {
            note = "Too large to preview (\(fileSize(item.size)))."
            return
        }
        if let contents = try? String(contentsOf: item.url, encoding: .utf8) {
            text = contents
        } else {
            note = "Not readable as text."
        }
    }
}
