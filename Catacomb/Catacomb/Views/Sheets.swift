import SwiftUI
import QuickLook
import UIKit

// MARK: - Quick Look / Share bridges

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as NSURL
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct PreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuickLookView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - Name prompt (new folder / new file / rename)

struct NamePrompt {
    enum Action {
        case newFolder
        case newTextFile
        case rename(FileItem)
    }

    let title: String
    let confirmLabel: String
    let initial: String
    let action: Action
}

struct NameSheet: View {
    let prompt: NamePrompt
    /// Returns an error message, or nil when the action succeeded.
    let onSubmit: (String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorText: String?
    @FocusState private var focused: Bool

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .foregroundStyle(Theme.bone)
                        .onSubmit {
                            submit()
                        }
                        .listRowBackground(Theme.panel)
                } footer: {
                    if let errorText {
                        Text(errorText)
                            .foregroundStyle(Theme.crimsonBright)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg0.ignoresSafeArea())
            .navigationTitle(prompt.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(prompt.confirmLabel) {
                        submit()
                    }
                    .disabled(!canSubmit)
                }
            }
            .onAppear {
                name = prompt.initial
                focused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        guard canSubmit else { return }
        if let message = onSubmit(name) {
            errorText = message
        } else {
            dismiss()
        }
    }
}

// MARK: - Text / Markdown / JSON editor

struct TextEditorSheet: View {
    let item: FileItem
    let root: URL?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var original = ""
    @State private var loaded = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var showDiscard = false
    @State private var showMarkdownPreview = false

    private var dirty: Bool {
        loaded && text != original
    }

    private var isMarkdown: Bool {
        item.ext == "md" || item.ext == "markdown"
    }

    private var isJSON: Bool {
        item.ext == "json"
    }

    private var renderedMarkdown: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return attributed
        }
        return AttributedString(text)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg0.ignoresSafeArea()
                if let loadError, !loaded {
                    ContentUnavailableView(
                        "Can't open file",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if showMarkdownPreview {
                    ScrollView {
                        Text(renderedMarkdown)
                            .foregroundStyle(Theme.bone)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Theme.bone)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        if dirty {
                            showDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isMarkdown {
                        Button {
                            showMarkdownPreview.toggle()
                        } label: {
                            Image(systemName: showMarkdownPreview ? "pencil" : "eye")
                        }
                    }
                    if isJSON {
                        Button("Format") {
                            formatJSON()
                        }
                    }
                    Button("Save") {
                        save()
                    }
                    .disabled(!dirty)
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { newValue in
                        if !newValue { saveError = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .onAppear {
                load()
            }
        }
        .interactiveDismissDisabled(dirty)
    }

    private func load() {
        guard !loaded else { return }
        do {
            let content = try FileOps.readText(item.url, root: root)
            text = content
            original = content
            loaded = true
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        do {
            try FileOps.writeText(text, to: item.url, root: root)
            original = text
            onSaved()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func formatJSON() {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard JSONSerialization.isValidJSONObject(object) else {
                saveError = "Only JSON objects and arrays can be formatted."
                return
            }
            let out = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            if let formatted = String(data: out, encoding: .utf8) {
                text = formatted
            }
        } catch {
            saveError = "Invalid JSON: \(error.localizedDescription)"
        }
    }
}

// MARK: - Move / copy destination picker

struct DestinationPicker: View {
    let items: [FileItem]
    let move: Bool
    let sourceRoot: URL?
    let onDone: () -> Void

    @EnvironmentObject private var store: LocationStore
    @Environment(\.dismiss) private var dismiss

    @State private var stack: [FolderRoute] = []
    @State private var folders: [FileItem] = []
    @State private var loadError: String?
    @State private var errorMessage: String?

    private var current: FolderRoute? {
        stack.last
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()
                List {
                    if let current {
                        if let loadError {
                            Text(loadError)
                                .foregroundStyle(Theme.muted)
                                .listRowBackground(Theme.panel)
                        } else if folders.isEmpty {
                            Text("No subfolders here.")
                                .foregroundStyle(Theme.muted)
                                .listRowBackground(Theme.panel)
                        }
                        ForEach(folders) { folder in
                            Button {
                                stack.append(FolderRoute(url: folder.url, rootURL: current.rootURL, title: folder.name))
                                loadFolders()
                            } label: {
                                LocationRow(icon: "folder.fill", title: folder.name, subtitle: "Folder")
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.panel)
                        }
                    } else {
                        Button {
                            stack = [store.sandboxRoute]
                            loadFolders()
                        } label: {
                            LocationRow(icon: "iphone", title: "Catacomb", subtitle: "Files stored in this app")
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.panel)

                        ForEach(store.locations) { location in
                            Button {
                                if let route = store.route(for: location) {
                                    stack = [route]
                                    loadFolders()
                                } else {
                                    errorMessage = "\"\(location.name)\" is no longer available."
                                }
                            } label: {
                                LocationRow(icon: "externaldrive.fill", title: location.name, subtitle: "Granted folder")
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.panel)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(current?.title ?? (move ? "Move to…" : "Copy to…"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if current != nil {
                        Button("Up") {
                            stack.removeLast()
                            loadFolders()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let current {
                    Button {
                        perform(into: current)
                    } label: {
                        Text(move ? "Move here" : "Copy here")
                            .font(Theme.serif(17, weight: .semibold))
                            .foregroundStyle(Theme.bone)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.crimson)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.bg1.ignoresSafeArea(edges: .bottom))
                }
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
        }
    }

    private func loadFolders() {
        guard let current else {
            folders = []
            loadError = nil
            return
        }
        do {
            let all = try FileOps.list(current.url, root: current.rootURL)
            var result: [FileItem] = []
            for entry in all where entry.isDirectory {
                if !items.contains(where: { $0.url == entry.url }) {
                    result.append(entry)
                }
            }
            result.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            folders = result
            loadError = nil
        } catch {
            folders = []
            loadError = error.localizedDescription
        }
    }

    private func perform(into destination: FolderRoute) {
        do {
            try FileOps.transfer(
                items,
                srcRoot: sourceRoot,
                dest: destination.url,
                destRoot: destination.rootURL,
                move: move
            )
            onDone()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
