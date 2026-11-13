import SwiftUI
import UniformTypeIdentifiers

struct LocationRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.crimsonBright)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.serif(17, weight: .semibold))
                    .foregroundStyle(Theme.bone)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
        }
        .contentShape(Rectangle())
    }
}

struct RootView: View {
    @EnvironmentObject private var store: LocationStore
    @EnvironmentObject private var nav: Navigator

    @State private var showFolderPicker = false
    @State private var errorMessage: String?
    @State private var sandboxSize: Int64 = 0
    @State private var freeBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0

    var body: some View {
        NavigationStack(path: $nav.path) {
            ZStack {
                GothicBackground()
                List {
                    Section {
                        storageCard
                            .listRowBackground(Theme.panel)
                    }

                    Section {
                        Button {
                            nav.path.append(store.sandboxRoute)
                        } label: {
                            LocationRow(
                                icon: "iphone",
                                title: "Catacomb",
                                subtitle: "Files stored in this app (also in the Files app)"
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.panel)
                    } header: {
                        sectionHeader("On this iPhone")
                    }

                    Section {
                        ForEach(store.locations) { location in
                            Button {
                                open(location)
                            } label: {
                                LocationRow(
                                    icon: "externaldrive.fill",
                                    title: location.name,
                                    subtitle: "Granted folder"
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.panel)
                        }
                        .onDelete { offsets in
                            store.remove(at: offsets)
                        }

                        Button {
                            showFolderPicker = true
                        } label: {
                            Label("Add Folder…", systemImage: "plus.circle.fill")
                                .font(Theme.serif(16, weight: .semibold))
                                .foregroundStyle(Theme.crimsonBright)
                        }
                        .listRowBackground(Theme.panel)
                    } header: {
                        sectionHeader("Granted folders")
                    } footer: {
                        Text("Pick any folder from Files (iCloud Drive, On My iPhone, other apps). Swipe a folder to remove access.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Catacomb")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: FolderRoute.self) { route in
                FolderView(route: route)
            }
            .task {
                await refreshStorage()
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [UTType.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try store.add(folder: url)
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
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

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.serif(13, weight: .semibold))
            .foregroundStyle(Theme.muted)
    }

    private func open(_ location: StoredLocation) {
        if let route = store.route(for: location) {
            nav.path.append(route)
        } else {
            errorMessage = "\"\(location.name)\" is no longer available. Remove it and add the folder again."
        }
    }

    // MARK: Storage summary

    private var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        let used = Double(totalBytes - freeBytes) / Double(totalBytes)
        return min(max(used, 0), 1)
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storage")
                .font(Theme.serif(17, weight: .semibold))
                .foregroundStyle(Theme.bone)
            ProgressView(value: usedFraction)
                .tint(Theme.crimsonBright)
            Text("Catacomb holds \(FileOps.byteString(sandboxSize)). \(FileOps.byteString(freeBytes)) free of \(FileOps.byteString(totalBytes)) on this iPhone.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
    }

    private func refreshStorage() async {
        let docs = LocationStore.sandboxURL
        let size = await Task.detached(priority: .utility) { () -> Int64 in
            return FileOps.directorySize(docs)
        }.value
        sandboxSize = size

        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        )
        freeBytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
        totalBytes = Int64(values?.volumeTotalCapacity ?? 0)
    }
}
