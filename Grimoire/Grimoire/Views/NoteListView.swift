import SwiftUI

struct NoteListView: View {
    @EnvironmentObject var store: NoteStore
    @EnvironmentObject var settings: SyncSettings
    @EnvironmentObject var sync: SyncService

    @Binding var path: [UUID]
    @Binding var showSettings: Bool

    @State private var query = ""
    @State private var folderFilter: String? = nil
    @State private var tagFilter: String? = nil

    private var filtered: [Note] {
        let q = query.trimmed
        let matches = store.notes.filter { (n: Note) -> Bool in
            if let folder = folderFilter, n.folder != folder { return false }
            if let tag = tagFilter, !n.tags.contains(tag) { return false }
            if q.isEmpty { return true }
            if n.title.localizedCaseInsensitiveContains(q) { return true }
            if n.body.localizedCaseInsensitiveContains(q) { return true }
            if n.folder.localizedCaseInsensitiveContains(q) { return true }
            for tag in n.tags where tag.localizedCaseInsensitiveContains(q) { return true }
            return false
        }
        return matches.sorted(by: { $0.modifiedAt > $1.modifiedAt })
    }

    private var pinned: [Note] {
        filtered.filter { $0.isPinned }
    }

    private var others: [Note] {
        filtered.filter { !$0.isPinned }
    }

    private var filterActive: Bool {
        folderFilter != nil || tagFilter != nil
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !pinned.isEmpty {
                Section {
                    ForEach(pinned) { note in
                        row(note)
                    }
                } header: {
                    sectionHeader("Pinned")
                }
            }

            if !others.isEmpty {
                Section {
                    ForEach(others) { note in
                        row(note)
                    }
                } header: {
                    sectionHeader(pinned.isEmpty ? "Tomes" : "Other tomes")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(GrimoireBackground())
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Search the tomes")
        .refreshable {
            if settings.isConfigured {
                await sync.sync(store: store, settings: settings)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                filterMenu
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    if settings.isConfigured {
                        Task { @MainActor in
                            await sync.sync(store: store, settings: settings)
                        }
                    } else {
                        showSettings = true
                    }
                } label: {
                    if sync.state == .syncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                Button {
                    let created = store.createNote(folder: folderFilter ?? "")
                    path.append(created.id)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .toolbarBackground(GrimoireTheme.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if settings.isConfigured {
                SyncStatusStrip()
            }
        }
        .navigationDestination(for: UUID.self) { id in
            NoteEditorView(noteID: id)
        }
    }

    private var titleText: String {
        if let folder = folderFilter { return folder }
        if let tag = tagFilter { return "#" + tag }
        return "Grimoire"
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold, design: .serif))
            .tracking(2)
            .foregroundStyle(GrimoireTheme.crimsonBright)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            OrnamentDivider()
            Text(filterActive || !query.trimmed.isEmpty ? "No tomes match your search." : "The pages are empty.")
                .font(GrimoireTheme.title(20))
                .foregroundStyle(GrimoireTheme.bone)
            if !filterActive && query.trimmed.isEmpty {
                Text("Tap the quill to inscribe your first note.")
                    .font(GrimoireTheme.body(15))
                    .foregroundStyle(GrimoireTheme.muted)
            }
            OrnamentDivider()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var filterMenu: some View {
        Menu {
            Button {
                folderFilter = nil
                tagFilter = nil
            } label: {
                Label("All notes", systemImage: "books.vertical")
            }
            if !store.folders.isEmpty {
                Section("Folders") {
                    ForEach(store.folders, id: \.self) { folder in
                        Button {
                            folderFilter = folder
                            tagFilter = nil
                        } label: {
                            Label(folder, systemImage: "folder")
                        }
                    }
                }
            }
            if !store.allTags.isEmpty {
                Section("Tags") {
                    ForEach(store.allTags, id: \.self) { tag in
                        Button {
                            tagFilter = tag
                            folderFilter = nil
                        } label: {
                            Label(tag, systemImage: "number")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: filterActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    private func row(_ note: Note) -> some View {
        NavigationLink(value: note.id) {
            NoteRow(note: note)
        }
        .listRowBackground(GrimoireTheme.panel.opacity(0.55))
        .listRowSeparatorTint(GrimoireTheme.crimson.opacity(0.35))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.delete(note.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                var changed = note
                changed.isPinned.toggle()
                store.update(changed)
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            .tint(GrimoireTheme.crimson)
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(GrimoireTheme.crimsonBright)
                }
                Text(note.displayTitle)
                    .font(GrimoireTheme.title(18))
                    .foregroundStyle(GrimoireTheme.bone)
                    .lineLimit(1)
            }
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(GrimoireTheme.body(14))
                    .foregroundStyle(GrimoireTheme.muted)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Text(Fmt.relative(note.modifiedAt))
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(GrimoireTheme.muted)
                if !note.folder.isEmpty {
                    Label(note.folder, systemImage: "folder")
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(GrimoireTheme.muted)
                }
                ForEach(note.tags.prefix(3), id: \.self) { tag in
                    Text("#" + tag)
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(GrimoireTheme.crimsonBright)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SyncStatusStrip: View {
    @EnvironmentObject var sync: SyncService

    var body: some View {
        HStack(spacing: 8) {
            switch sync.state {
            case .idle:
                Image(systemName: "icloud")
                    .foregroundStyle(GrimoireTheme.muted)
                Text(idleText)
                    .foregroundStyle(GrimoireTheme.muted)
            case .syncing:
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing with the vault…")
                    .foregroundStyle(GrimoireTheme.muted)
            case .success(let date):
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(GrimoireTheme.crimsonBright)
                Text("Synced " + Fmt.relative(date))
                    .foregroundStyle(GrimoireTheme.muted)
            case .failed(let message):
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(GrimoireTheme.crimsonBright)
                Text(message)
                    .foregroundStyle(GrimoireTheme.crimsonBright)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, design: .serif))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(GrimoireTheme.black.opacity(0.92))
    }

    private var idleText: String {
        if let last = sync.lastSyncDate {
            return "Last synced " + Fmt.relative(last)
        }
        return "Not synced yet"
    }
}
