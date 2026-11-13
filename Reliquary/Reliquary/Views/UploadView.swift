import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

struct PickedFile {
    let url: URL
    let name: String
    let assetIdentifier: String?
}

/// Thread-safe collector for files copied on the item provider's background queue.
final class PickedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [PickedFile] = []

    func add(_ file: PickedFile) {
        lock.lock()
        files.append(file)
        lock.unlock()
    }

    var all: [PickedFile] {
        lock.lock()
        let copy = files
        lock.unlock()
        return copy
    }
}

// MARK: - Picker

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPicked: ([PickedFile]) -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
        config.selectionLimit = 0
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            guard !results.isEmpty else { return }

            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("reliquary-upload-" + UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            let group = DispatchGroup()
            let box = PickedBox()

            for result in results {
                let provider = result.itemProvider
                var typeIdentifier: String?
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    typeIdentifier = UTType.movie.identifier
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    typeIdentifier = UTType.image.identifier
                }
                guard let identifier = typeIdentifier else { continue }
                let assetIdentifier = result.assetIdentifier

                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                    defer { group.leave() }
                    guard let url = url else { return }
                    // The provided file is deleted when this callback returns, so copy it now.
                    let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    let destination = folder.appendingPathComponent(url.lastPathComponent)
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: url, to: destination)
                    } catch {
                        return
                    }
                    box.add(PickedFile(url: destination, name: url.lastPathComponent, assetIdentifier: assetIdentifier))
                }
            }

            let callback = parent.onPicked
            group.notify(queue: .main) {
                callback(box.all)
            }
        }
    }
}

// MARK: - Upload queue

struct UploadItem: Identifiable {
    enum State {
        case waiting
        case uploading
        case created
        case duplicate
        case failed(String)
    }

    let id = UUID()
    let name: String
    var state: State
}

@MainActor
final class UploadManager: ObservableObject {
    @Published var items: [UploadItem] = []
    @Published var isRunning = false

    var finishedCount: Int {
        return items.filter { item in
            switch item.state {
            case .created, .duplicate, .failed: return true
            default: return false
            }
        }.count
    }

    var uploadedCount: Int {
        return items.filter { item in
            if case .created = item.state { return true }
            return false
        }.count
    }

    func clearFinished() {
        guard !isRunning else { return }
        items = []
    }

    /// Uploads files one at a time. Returns after the whole batch is processed.
    func upload(files: [PickedFile], client: ImmichClient) async {
        guard !files.isEmpty else { return }
        isRunning = true
        let firstNewIndex = items.count
        items.append(contentsOf: files.map { UploadItem(name: $0.name, state: .waiting) })

        for (offset, file) in files.enumerated() {
            let position = firstNewIndex + offset
            items[position].state = .uploading

            let dates = UploadManager.dates(for: file.assetIdentifier)
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.url.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            let deviceAssetId = file.assetIdentifier ?? "\(file.name)-\(size)"

            do {
                let status = try await client.uploadAsset(
                    fileURL: file.url,
                    filename: file.name,
                    deviceAssetId: deviceAssetId,
                    created: dates.created,
                    modified: dates.modified
                )
                items[position].state = (status == "duplicate") ? .duplicate : .created
            } catch {
                items[position].state = .failed(error.localizedDescription)
            }
            try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
        }
        isRunning = false
    }

    private static func dates(for identifier: String?) -> (created: Date, modified: Date) {
        let now = Date()
        guard let identifier = identifier else { return (now, now) }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        if let asset = fetched.firstObject {
            return (asset.creationDate ?? now, asset.modificationDate ?? now)
        }
        return (now, now)
    }
}

// MARK: - View

struct UploadView: View {
    let client: ImmichClient
    @ObservedObject var uploads: UploadManager
    let timeline: TimelineStore

    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 44))
                        .foregroundColor(Theme.crimsonBright)
                    Text("Offer to the archive")
                        .font(Theme.title(20))
                        .foregroundColor(Theme.bone)
                    Text("Pick photos and videos from this iPhone to send to your Immich server.")
                        .font(Theme.body(14))
                        .foregroundColor(Theme.muted)
                        .multilineTextAlignment(.center)

                    Button(action: choose) {
                        Text(uploads.isRunning ? "Uploading..." : "Choose photos & videos")
                            .font(Theme.title(16))
                            .foregroundColor(Theme.bone)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.crimson)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(uploads.isRunning)
                    .opacity(uploads.isRunning ? 0.5 : 1)
                }
                .padding(24)

                if uploads.items.isEmpty {
                    Spacer()
                } else {
                    OrnateDivider().padding(.horizontal, 24)
                    List {
                        ForEach(uploads.items) { item in
                            HStack(spacing: 12) {
                                statusIcon(for: item.state)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(Theme.body(14))
                                        .foregroundColor(Theme.bone)
                                        .lineLimit(1)
                                    Text(statusText(for: item.state))
                                        .font(Theme.body(12))
                                        .foregroundColor(statusColor(for: item.state))
                                        .lineLimit(2)
                                }
                            }
                            .listRowBackground(Theme.panel)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .gothicBackground()
            .navigationTitle("Upload")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !uploads.items.isEmpty && !uploads.isRunning {
                        Button("Clear") { uploads.clearFinished() }
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            PhotoPicker(isPresented: $showPicker) { files in
                startUpload(files)
            }
            .ignoresSafeArea()
        }
    }

    private func choose() {
        Task { @MainActor in
            // Authorization is only needed to read original capture dates; the picker works without it.
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            showPicker = true
        }
    }

    private func startUpload(_ files: [PickedFile]) {
        let manager = uploads
        let timelineStore = timeline
        let current = client
        Task { @MainActor in
            await manager.upload(files: files, client: current)
            if manager.uploadedCount > 0 {
                await timelineStore.reload(client: current)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for state: UploadItem.State) -> some View {
        switch state {
        case .waiting:
            Image(systemName: "clock").foregroundColor(Theme.muted)
        case .uploading:
            ProgressView().tint(Theme.crimsonBright)
        case .created:
            Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.crimsonBright)
        case .duplicate:
            Image(systemName: "equal.circle").foregroundColor(Theme.muted)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundColor(Theme.crimsonBright)
        }
    }

    private func statusText(for state: UploadItem.State) -> String {
        switch state {
        case .waiting: return "Waiting"
        case .uploading: return "Uploading..."
        case .created: return "Uploaded"
        case .duplicate: return "Already in your archive"
        case .failed(let message): return message
        }
    }

    private func statusColor(for state: UploadItem.State) -> Color {
        switch state {
        case .failed: return Theme.crimsonBright
        case .created: return Theme.bone
        default: return Theme.muted
        }
    }
}
