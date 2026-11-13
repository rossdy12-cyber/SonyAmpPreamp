import SwiftUI
import UniformTypeIdentifiers

struct ActiveSheet: Identifiable {
    enum Kind {
        case preview(URL)
        case edit(FileItem)
        case transfer([FileItem], move: Bool)
        case share([URL])
        case name(NamePrompt)
    }

    let id = UUID()
    let kind: Kind
}

struct FolderView: View {
    let route: FolderRoute

    @EnvironmentObject private var nav: Navigator

    @State private var items: [FileItem] = []
    @State private var query = ""
    @State private var isSelecting = false
    @State private var selection = Set<URL>()
    @State private var activeSheet: ActiveSheet?
    @State private var showImporter = false
    @State private var showDeleteConfirm = false
    @State private var pendingDelete: [FileItem] = []
    @State private var errorMessage: String?
    @State private var loadError: String?

    @AppStorage("catacomb.sortKey") private var sortRaw = SortKey.name.rawValue
    @AppStorage("catacomb.sortAsc") private var ascending = true

    // MARK: Body

    var body: some View {
        ZStack {
            GothicBackground()
            VStack(spacing: 0) {
                breadcrumb
                content
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search this folder")
        .toolbar {
            toolbarContent
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType.item],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { newValue in
                    if !newValue { errorMessage = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            reload()
        }
    }

    // MARK: Sorting / filtering

    private var sortKey: SortKey {
        SortKey(rawValue: sortRaw) ?? .name
    }

    private var displayItems: [FileItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var list = items
        if !trimmed.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        }
        let key = sortKey
        let asc = ascending
        list.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            let result: ComparisonResult
            switch key {
            case .name:
                result = a.name.localizedStandardCompare(b.name)
            case .date:
                let da = a.modified ?? Date.distantPast
                let db = b.modified ?? Date.distantPast
                if da < db {
                    result = .orderedAscending
                } else if da > db {
                    result = .orderedDescending
                } else {
                    result = a.name.localizedStandardCompare(b.name)
                }
            case .size:
                if a.size < b.size {
                    result = .orderedAscending
                } else if a.size > b.size {
                    result = .orderedDescending
                } else {
                    result = a.name.localizedStandardCompare(b.name)
                }
            }
            if result == .orderedSame {
                return false
            }
            return asc ? (result == .orderedAscending) : (result == .orderedDescending)
        }
        return list
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let loadError {
            ContentUnavailableView(
                "Can't open folder",
                systemImage: "exclamationmark.triangle",
                description: Text(loadError)
            )
        } else if items.isEmpty {
            ContentUnavailableView(
                "Empty crypt",
                systemImage: "folder",
                description: Text("Use the menu to add files or create a folder.")
            )
        } else {
            let shown = displayItems
            if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                fileList(shown)
            }
        }
    }

    private func fileList(_ shown: [FileItem]) -> some View {
        List {
            ForEach(shown) { item in
                row(item)
                    .listRowBackground(Theme.panel)
                    .listRowSeparatorTint(Theme.hairline)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            confirmDelete([item])
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            promptRename(item)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(Theme.crimson)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            reload()
        }
    }

    private func row(_ item: FileItem) -> some View {
        let selected = selection.contains(item.url)
        return Button {
            tap(item)
        } label: {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Theme.crimsonBright : Theme.muted)
                }
                Image(systemName: item.symbolName)
                    .font(.title2)
                    .foregroundStyle(item.isDirectory ? Theme.crimsonBright : Theme.bone.opacity(0.8))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.bone)
                        .lineLimit(1)
                    Text(subtitle(for: item))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                if item.isDirectory && !isSelecting {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            contextItems(item)
        }
    }

    @ViewBuilder
    private func contextItems(_ item: FileItem) -> some View {
        if !item.isDirectory {
            Button {
                preview(item)
            } label: {
                Label("Quick Look", systemImage: "eye")
            }
            if item.isTextEditable {
                Button {
                    activeSheet = ActiveSheet(kind: .edit(item))
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
            }
            Button {
                share([item])
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        Button {
            promptRename(item)
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            activeSheet = ActiveSheet(kind: .transfer([item], move: false))
        } label: {
            Label("Copy to…", systemImage: "doc.on.doc")
        }
        Button {
            activeSheet = ActiveSheet(kind: .transfer([item], move: true))
        } label: {
            Label("Move to…", systemImage: "folder")
        }
        Button(role: .destructive) {
            confirmDelete([item])
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func subtitle(for item: FileItem) -> String {
        var parts: [String] = []
        if !item.isDirectory {
            parts.append(FileOps.byteString(item.size))
        }
        if let modified = item.modified {
            parts.append(modified.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Breadcrumb

    private var breadcrumb: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    crumb("Locations", active: false) {
                        nav.path = []
                    }
                    ForEach(Array(nav.path.enumerated()), id: \.offset) { index, entry in
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                        crumb(entry.title, active: index == nav.path.count - 1) {
                            nav.path = Array(nav.path.prefix(index + 1))
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onAppear {
                proxy.scrollTo(nav.path.count - 1, anchor: .trailing)
            }
        }
        .background(Theme.bg1.opacity(0.9))
    }

    private func crumb(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: active ? .bold : .regular, design: .serif))
                .foregroundStyle(active ? Theme.crimsonBright : Theme.bone.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(active ? Theme.crimson.opacity(0.18) : Theme.panel))
        }
        .buttonStyle(.plain)
    }

    // MARK: Toolbar / selection bar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isSelecting {
                Button("All") {
                    selection = Set(displayItems.map { $0.url })
                }
                Button("Done") {
                    endSelecting()
                }
            } else {
                Menu {
                    Button {
                        promptNewFolder()
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    Button {
                        promptNewTextFile()
                    } label: {
                        Label("New Text File", systemImage: "doc.badge.plus")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Files", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        isSelecting = true
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    Divider()
                    Picker("Sort by", selection: $sortRaw) {
                        ForEach(SortKey.allCases) { key in
                            Text(key.label).tag(key.rawValue)
                        }
                    }
                    Toggle("Ascending", isOn: $ascending)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var selectionBar: some View {
        let chosen = items.filter { selection.contains($0.url) }
        return HStack(spacing: 0) {
            barButton("square.and.arrow.up", "Share") {
                share(chosen)
            }
            barButton("doc.on.doc", "Copy") {
                activeSheet = ActiveSheet(kind: .transfer(chosen, move: false))
            }
            barButton("folder", "Move") {
                activeSheet = ActiveSheet(kind: .transfer(chosen, move: true))
            }
            barButton("trash", "Delete") {
                confirmDelete(chosen)
            }
        }
        .padding(.vertical, 8)
        .background(Theme.bg1.ignoresSafeArea(edges: .bottom))
    }

    private func barButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(selection.isEmpty)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet.kind {
        case .preview(let url):
            PreviewSheet(url: url)
        case .edit(let item):
            TextEditorSheet(item: item, root: route.rootURL) {
                reload()
            }
        case .transfer(let list, let move):
            DestinationPicker(items: list, move: move, sourceRoot: route.rootURL) {
                reload()
                endSelecting()
            }
        case .share(let urls):
            ShareSheet(urls: urls)
                .presentationDetents([.medium, .large])
        case .name(let prompt):
            NameSheet(prompt: prompt) { name in
                handleName(prompt, name)
            }
        }
    }

    // MARK: Actions

    private func reload() {
        do {
            items = try FileOps.list(route.url, root: route.rootURL)
            loadError = nil
        } catch {
            items = []
            loadError = error.localizedDescription
        }
        let existing = Set(items.map { $0.url })
        selection = selection.intersection(existing)
    }

    private func tap(_ item: FileItem) {
        if isSelecting {
            if selection.contains(item.url) {
                selection.remove(item.url)
            } else {
                selection.insert(item.url)
            }
            return
        }
        if item.isDirectory {
            nav.path.append(FolderRoute(url: item.url, rootURL: route.rootURL, title: item.name))
        } else if item.isTextEditable {
            activeSheet = ActiveSheet(kind: .edit(item))
        } else {
            preview(item)
        }
    }

    private func endSelecting() {
        isSelecting = false
        selection.removeAll()
    }

    private func preview(_ item: FileItem) {
        do {
            let url = try FileOps.stage(item.url, root: route.rootURL)
            activeSheet = ActiveSheet(kind: .preview(url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func share(_ list: [FileItem]) {
        let files = list.filter { !$0.isDirectory }
        if files.isEmpty {
            errorMessage = "Folders can't be shared. Select files instead."
            return
        }
        do {
            var urls: [URL] = []
            for file in files {
                urls.append(try FileOps.stage(file.url, root: route.rootURL))
            }
            activeSheet = ActiveSheet(kind: .share(urls))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func promptNewFolder() {
        let prompt = NamePrompt(title: "New Folder", confirmLabel: "Create", initial: "", action: .newFolder)
        activeSheet = ActiveSheet(kind: .name(prompt))
    }

    private func promptNewTextFile() {
        let prompt = NamePrompt(title: "New Text File", confirmLabel: "Create", initial: "Untitled.txt", action: .newTextFile)
        activeSheet = ActiveSheet(kind: .name(prompt))
    }

    private func promptRename(_ item: FileItem) {
        let prompt = NamePrompt(title: "Rename", confirmLabel: "Rename", initial: item.name, action: .rename(item))
        activeSheet = ActiveSheet(kind: .name(prompt))
    }

    /// Returns an error message, or nil on success (the sheet then dismisses itself).
    private func handleName(_ prompt: NamePrompt, _ name: String) -> String? {
        do {
            switch prompt.action {
            case .newFolder:
                try FileOps.createFolder(named: name, in: route.url, root: route.rootURL)
            case .newTextFile:
                try FileOps.createFile(named: name, in: route.url, root: route.rootURL)
            case .rename(let item):
                try FileOps.rename(item, to: name, root: route.rootURL)
            }
            reload()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            do {
                _ = try FileOps.importFiles(urls, into: route.url, root: route.rootURL)
                reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private var deleteTitle: String {
        if pendingDelete.count == 1 {
            return "Delete \"\(pendingDelete[0].name)\"?"
        }
        return "Delete \(pendingDelete.count) items?"
    }

    private func confirmDelete(_ list: [FileItem]) {
        if list.isEmpty { return }
        pendingDelete = list
        showDeleteConfirm = true
    }

    private func performDelete() {
        do {
            try FileOps.delete(pendingDelete, root: route.rootURL)
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingDelete = []
        reload()
        endSelecting()
    }
}
