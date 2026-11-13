import SwiftUI

struct NoteEditorView: View {
    let noteID: UUID

    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case write = "Inscribe"
        case read = "Behold"
        var id: String { rawValue }
    }

    @State private var draft = Note()
    @State private var loaded = false
    @State private var startedBlank = false
    @State private var mode: Mode = .write
    @State private var showDetails = false
    @State private var saveTask: Task<Void, Never>? = nil
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            OrnamentDivider()

            if mode == .write {
                writeView
            } else {
                readView
            }
        }
        .background(GrimoireBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(GrimoireTheme.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    draft.isPinned.toggle()
                } label: {
                    Image(systemName: draft.isPinned ? "pin.fill" : "pin")
                }
                Button {
                    showDetails = true
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                }
                Menu {
                    ShareLink(item: shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        deleteNote()
                    } label: {
                        Label("Delete note", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Button("Heading") { appendLine("# ") }
                Button("List") { appendLine("- ") }
                Button("Task") { appendLine("- [ ] ") }
                Button("Quote") { appendLine("> ") }
                Spacer()
                Button("Done") { editorFocused = false }
            }
        }
        .sheet(isPresented: $showDetails) {
            NoteDetailsSheet(draft: $draft)
                .environmentObject(store)
        }
        .onAppear {
            loadDraft()
        }
        .onDisappear {
            finish()
        }
        .onChange(of: draft) { _, _ in
            scheduleSave()
        }
        .onChange(of: store.notes) { _, _ in
            refreshFromStore()
        }
    }

    // MARK: Subviews

    private var writeView: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Title", text: $draft.title, axis: .vertical)
                .font(GrimoireTheme.title(26))
                .foregroundStyle(GrimoireTheme.bone)
                .lineLimit(1...3)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if !draft.folder.isEmpty || !draft.tags.isEmpty {
                HStack(spacing: 10) {
                    if !draft.folder.isEmpty {
                        Label(draft.folder, systemImage: "folder")
                            .foregroundStyle(GrimoireTheme.muted)
                    }
                    ForEach(draft.tags, id: \.self) { tag in
                        Text("#" + tag)
                            .foregroundStyle(GrimoireTheme.crimsonBright)
                    }
                }
                .font(.system(size: 12, design: .serif))
                .padding(.horizontal, 16)
            }

            TextEditor(text: $draft.body)
                .focused($editorFocused)
                .font(GrimoireTheme.body(17))
                .foregroundStyle(GrimoireTheme.bone)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
        }
    }

    private var readView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(draft.displayTitle)
                    .font(GrimoireTheme.title(30))
                    .foregroundStyle(GrimoireTheme.bone)
                MarkdownPreview(text: draft.body)
            }
            .padding(16)
        }
    }

    private var shareText: String {
        let title = draft.title.trimmed
        if title.isEmpty {
            return draft.body
        }
        return title + "\n\n" + draft.body
    }

    // MARK: Actions

    private func appendLine(_ prefix: String) {
        if draft.body.isEmpty || draft.body.hasSuffix("\n") {
            draft.body += prefix
        } else {
            draft.body += "\n" + prefix
        }
    }

    private func loadDraft() {
        guard !loaded else { return }
        if let existing = store.note(noteID) {
            draft = existing
            startedBlank = existing.isBlank
        }
        loaded = true
    }

    /// Pulls in changes made elsewhere (e.g. a sync) when the user has nothing unsaved.
    private func refreshFromStore() {
        guard loaded, saveTask == nil, let stored = store.note(noteID) else { return }
        if !stored.contentEquals(draft) {
            draft = stored
        }
    }

    private func scheduleSave() {
        guard loaded else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            commit()
            saveTask = nil
        }
    }

    /// Writes the draft to the store only if something actually changed.
    private func commit() {
        guard loaded, draft.id == noteID, let stored = store.note(noteID) else { return }
        if stored.contentEquals(draft) { return }
        store.update(draft)
    }

    private func finish() {
        saveTask?.cancel()
        saveTask = nil
        guard loaded else { return }
        if startedBlank && draft.isBlank {
            store.removeNote(noteID)
        } else {
            commit()
        }
    }

    private func deleteNote() {
        saveTask?.cancel()
        saveTask = nil
        loaded = false
        store.delete(noteID)
        dismiss()
    }
}

struct NoteDetailsSheet: View {
    @Binding var draft: Note
    @EnvironmentObject var store: NoteStore
    @Environment(\.dismiss) private var dismiss

    @State private var tagsText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder", text: $draft.folder)
                        .textInputAutocapitalization(.words)
                    if !store.folders.isEmpty {
                        Menu {
                            ForEach(store.folders, id: \.self) { folder in
                                Button(folder) {
                                    draft.folder = folder
                                }
                            }
                        } label: {
                            Label("Choose existing folder", systemImage: "folder")
                        }
                    }
                } header: {
                    Text("Folder").foregroundStyle(GrimoireTheme.crimsonBright)
                }
                .listRowBackground(GrimoireTheme.panel)

                Section {
                    TextField("Comma separated tags", text: $tagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Tags").foregroundStyle(GrimoireTheme.crimsonBright)
                }
                .listRowBackground(GrimoireTheme.panel)

                Section {
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(draft.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(GrimoireTheme.muted)
                    }
                    HStack {
                        Text("Modified")
                        Spacer()
                        Text(draft.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(GrimoireTheme.muted)
                    }
                }
                .listRowBackground(GrimoireTheme.panel)
            }
            .foregroundStyle(GrimoireTheme.bone)
            .scrollContentBackground(.hidden)
            .background(GrimoireBackground())
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GrimoireTheme.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                tagsText = draft.tags.joined(separator: ", ")
            }
            .onChange(of: tagsText) { _, newValue in
                draft.tags = Note.parseTags(newValue)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }
}
