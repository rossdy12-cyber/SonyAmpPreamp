import SwiftUI

struct VaultGalleryView: View {
    @EnvironmentObject var store: StudioStore
    @State private var galleryMode: Int = 0 // 0 = iPhone Vault, 1 = Home PC RTX 2070S Gallery
    @State private var selectedItem: VaultImageItem? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Gallery Source", selection: $galleryMode) {
                    Text("iPhone Vault (\(store.vaultItems.count))").tag(0)
                    Text("Home PC Gallery (\(store.pcGalleryItems.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.top, 8)

                ScrollView {
                    let items = (galleryMode == 0) ? store.vaultItems : store.pcGalleryItems
                    if items.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: galleryMode == 0 ? "photo.stack" : "desktopcomputer.trianglebadge.exclamationmark")
                                .font(.system(size: 42))
                                .foregroundColor(StudioTheme.textSecondary)
                            Text(galleryMode == 0 ? "Your iPhone Vault is Empty" : "No Home PC Gallery Items Loaded")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(StudioTheme.textPrimary)
                            Text(galleryMode == 0 ? "Every image you generate on your iPhone is saved privately here." : "Make sure your Home PC Studio is running and tap Refresh.")
                                .font(.system(size: 12))
                                .foregroundColor(StudioTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                        .padding(.top, 80)
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(items) { item in
                                VaultGridCell(item: item)
                                    .onTapGesture {
                                        selectedItem = item
                                    }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 30)
                    }
                }
            }
            .background(StudioTheme.bgDeep.ignoresSafeArea())
            .navigationTitle("Artwork Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.lockStealthImmediately()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.slash.fill")
                            Text("Hide")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(StudioTheme.cyanGlow)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await store.checkPCConnection()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $selectedItem) { item in
                VaultDetailSheet(item: item)
            }
        }
    }
}

struct VaultGridCell: View {
    let item: VaultImageItem
    @EnvironmentObject var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                StudioTheme.bgElevated
                if let remote = item.remoteURL, let url = URL(string: remote) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Image(systemName: "photo").foregroundColor(StudioTheme.textSecondary)
                        default:
                            ProgressView().tint(StudioTheme.crimson)
                        }
                    }
                } else if let localImg = store.loadImageFromVault(filename: item.filename) {
                    Image(uiImage: localImg)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(item.modelName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(StudioTheme.textPrimary)
                .lineLimit(1)

            Text("\(item.width)×\(item.height) • Seed \(item.seed)")
                .font(.system(size: 10))
                .foregroundColor(StudioTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(StudioTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(StudioTheme.borderSubtle, lineWidth: 1)
        )
    }
}

struct VaultDetailSheet: View {
    let item: VaultImageItem
    @EnvironmentObject var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var loadedImage: UIImage? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let img = loadedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        HStack(spacing: 10) {
                            Button {
                                store.saveImageToPhotos(img)
                            } label: {
                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(StudioTheme.accentGradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            ShareLink(item: Image(uiImage: img), preview: SharePreview("Qwen Studio", image: Image(uiImage: img))) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(StudioTheme.bgElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    } else {
                        ProgressView("Loading Artwork...")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("METADATA & PROMPT")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(StudioTheme.textSecondary)
                        Text("Model: \(item.modelName) • \(item.width)×\(item.height) • Seed: \(item.seed)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(StudioTheme.cyanGlow)
                        Text(item.prompt)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(StudioTheme.textPrimary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(StudioTheme.bgDeep)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        HStack(spacing: 10) {
                            Button {
                                store.prompt = item.prompt
                                if !item.negativePrompt.isEmpty {
                                    store.negativePrompt = item.negativePrompt
                                }
                                store.seedText = "\(item.seed)"
                                store.selectedTab = 0
                                dismiss()
                                store.showToast("Loaded Prompt & Seed into Studio")
                            } label: {
                                Label("Reuse Prompt & Seed", systemImage: "arrow.uturn.backward.square")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(StudioTheme.bgElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            if item.remoteURL == nil {
                                Button(role: .destructive) {
                                    store.deleteVaultItem(item)
                                    dismiss()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(StudioTheme.crimson)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(StudioTheme.bgElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .studioCard()
                }
                .padding(14)
            }
            .background(StudioTheme.bgDeep.ignoresSafeArea())
            .navigationTitle("Artwork Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if let local = store.loadImageFromVault(filename: item.filename) {
                    loadedImage = local
                } else if let remote = item.remoteURL, let url = URL(string: remote),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let img = UIImage(data: data) {
                    loadedImage = img
                }
            }
        }
    }
}
