import SwiftUI
import PhotosUI

struct StudioCanvasView: View {
    @EnvironmentObject var store: StudioStore
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showFullScreenImage: Bool = false
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerBanner
                    artworkPreviewCard
                    generateActionCard
                    engineSelectorCard
                    promptEditorCard
                    aspectAndParamsCard
                    img2imgCard
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 32)
            }
            .background(StudioTheme.bgDeep.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(StudioTheme.accentGradient)
                        Text("QWEN 2.1 STUDIO")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundColor(StudioTheme.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPromptFocused = false
                        store.selectedTab = 1
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Alchemist")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(StudioTheme.accentGradient)
                        .clipShape(Capsule())
                    }
                }
            }
            .sheet(isPresented: $showFullScreenImage) {
                if let img = store.activeImage {
                    FullScreenImageSheet(image: img, item: store.activeVaultItem)
                }
            }
        }
    }

    private var headerBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(store.pcOnline ? StudioTheme.emerald : StudioTheme.cyanGlow)
                .frame(width: 8, height: 8)
            Text(store.pcOnline ? "PC RTX 2070S Online + Standalone Cluster Ready" : "Standalone Uncensored Cluster Ready (24/7 Anywhere)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(StudioTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            Text(store.selectedEngine.shortTitle)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(StudioTheme.crimson)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(StudioTheme.crimson.opacity(0.16))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(StudioTheme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var artworkPreviewCard: some View {
        VStack(spacing: 12) {
            if let img = store.activeImage {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .onTapGesture {
                            showFullScreenImage = true
                        }

                    HStack(spacing: 8) {
                        Button {
                            store.saveImageToPhotos(img)
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }

                        Button {
                            store.upscaleActiveImage()
                        } label: {
                            Label("2x HD", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }

                        ShareLink(item: Image(uiImage: img), preview: SharePreview("Qwen Studio Artwork", image: Image(uiImage: img))) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                    .foregroundColor(.white)
                    .padding(10)
                }

                if let meta = store.activeVaultItem {
                    HStack {
                        Text("\(meta.width)×\(meta.height) • \(meta.modelName)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(StudioTheme.textSecondary)
                        Spacer()
                        Text("Seed: \(meta.seed)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(StudioTheme.cyanGlow)
                            .onTapGesture {
                                store.seedText = "\(meta.seed)"
                                store.showToast("Locked Seed \(meta.seed)")
                            }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(StudioTheme.accentGradient)
                    Text("Ready to Render Uncensored AI Artwork")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(StudioTheme.textPrimary)
                    Text("Use the Alchemist tab to pick from 119 characters, Duo poses & anatomy shapes, or type any prompt below and tap Generate.")
                        .font(.system(size: 12))
                        .foregroundColor(StudioTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
            }
        }
        .studioCard(borderColor: store.isGenerating ? StudioTheme.crimson : StudioTheme.borderSubtle)
    }

    private var generateActionCard: some View {
        VStack(spacing: 10) {
            Button {
                isPromptFocused = false
                Task {
                    await store.generateImage()
                }
            } label: {
                HStack(spacing: 10) {
                    if store.isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars.inverse")
                            .font(.system(size: 18, weight: .bold))
                    }
                    Text(store.isGenerating ? store.statusBanner : "GENERATE UNCENSORED IMAGE")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    store.isGenerating
                        ? LinearGradient(colors: [StudioTheme.neonViolet, StudioTheme.crimson], startPoint: .leading, endPoint: .trailing)
                        : StudioTheme.accentGradient
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: StudioTheme.crimson.opacity(0.45), radius: 12, y: 4)
            }
            .disabled(store.isGenerating)

            if let err = store.errorMessage {
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(StudioTheme.amber)
                    .multilineTextAlignment(.center)
            } else {
                Text(store.statusBanner)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(StudioTheme.textSecondary)
            }
        }
    }

    private var engineSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GENERATION ENGINE")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1)
                .foregroundColor(StudioTheme.textSecondary)

            HStack(spacing: 8) {
                ForEach(StudioEngine.allCases) { eng in
                    let isSelected = (store.selectedEngine == eng)
                    Button {
                        store.selectedEngine = eng
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: eng.icon)
                                .font(.system(size: 16, weight: .bold))
                            Text(eng.shortTitle)
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundColor(isSelected ? .white : StudioTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? AnyShapeStyle(StudioTheme.accentGradient) : AnyShapeStyle(StudioTheme.bgElevated))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            Text(store.selectedEngine.subtitle)
                .font(.system(size: 11))
                .foregroundColor(StudioTheme.textSecondary)

            if store.selectedEngine == .standaloneCluster {
                HStack {
                    Text("Cluster SDXL Model")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(StudioTheme.textPrimary)
                    Spacer()
                    Picker("Model", selection: $store.selectedClusterModel) {
                        ForEach(StudioCatalog.clusterModels, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .tint(StudioTheme.crimson)
                }
                .padding(.top, 4)
            }
        }
        .studioCard()
    }

    private var promptEditorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("POSITIVE PROMPT")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1)
                    .foregroundColor(StudioTheme.textSecondary)
                Spacer()
                Button {
                    store.selectedTab = 1
                } label: {
                    Label("119 Character Builder", systemImage: "person.2.crop.square.stack.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(StudioTheme.cyanGlow)
                }
            }

            TextEditor(text: $store.prompt)
                .focused($isPromptFocused)
                .font(.system(size: 13))
                .foregroundColor(StudioTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96, maxHeight: 150)
                .padding(8)
                .background(StudioTheme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(StudioTheme.borderSubtle, lineWidth: 1)
                )

            HStack {
                Text("NEGATIVE PROMPT")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1)
                    .foregroundColor(StudioTheme.textSecondary)
                Spacer()
                Button("Clear Prompt") {
                    store.prompt = ""
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(StudioTheme.crimson)
            }

            TextEditor(text: $store.negativePrompt)
                .focused($isPromptFocused)
                .font(.system(size: 12))
                .foregroundColor(StudioTheme.textSecondary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 54, maxHeight: 90)
                .padding(8)
                .background(StudioTheme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(StudioTheme.borderSubtle, lineWidth: 1)
                )
        }
        .studioCard()
    }

    private var aspectAndParamsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RESOLUTION & SAMPLING")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1)
                .foregroundColor(StudioTheme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AspectRatioOption.all) { opt in
                        let sel = (store.selectedAspect.id == opt.id)
                        Button {
                            store.selectedAspect = opt
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.label)
                                    .font(.system(size: 12, weight: .bold))
                                Text(opt.subtitle)
                                    .font(.system(size: 10))
                                    .opacity(0.85)
                            }
                            .foregroundColor(sel ? .white : StudioTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(sel ? AnyShapeStyle(StudioTheme.accentGradient) : AnyShapeStyle(StudioTheme.bgElevated))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }

            HStack {
                Text("Steps: \(Int(store.steps))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(StudioTheme.textPrimary)
                    .frame(width: 90, alignment: .leading)
                Slider(value: $store.steps, in: 15...40, step: 1)
                    .tint(StudioTheme.crimson)
            }

            HStack {
                Text("CFG: \(String(format: "%.1f", store.cfgScale))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(StudioTheme.textPrimary)
                    .frame(width: 90, alignment: .leading)
                Slider(value: $store.cfgScale, in: 4.0...12.0, step: 0.5)
                    .tint(StudioTheme.neonViolet)
            }

            HStack(spacing: 10) {
                Text("Seed:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(StudioTheme.textPrimary)
                TextField("-1 (Random)", text: $store.seedText)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(7)
                    .background(StudioTheme.bgDeep)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("Random (-1)") {
                    store.seedText = "-1"
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(StudioTheme.cyanGlow)
            }
        }
        .studioCard()
    }

    private var img2imgCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("IMAGE-TO-IMAGE REFERENCE (OPTIONAL)")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1)
                    .foregroundColor(StudioTheme.textSecondary)
                Spacer()
                if store.initImage != nil {
                    Button("Remove") {
                        store.initImage = nil
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(StudioTheme.crimson)
                }
            }

            HStack(spacing: 12) {
                if let ref = store.initImage {
                    Image(uiImage: ref)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(store.initImage == nil ? "Pick Reference Photo from iPhone" : "Change Reference Photo", systemImage: "photo.badge.plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(StudioTheme.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .onChange(of: selectedPhotoItem) { newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let uiImg = UIImage(data: data) {
                            store.initImage = uiImg
                        }
                    }
                }
            }

            if store.initImage != nil {
                HStack {
                    Text("Denoise: \(String(format: "%.2f", store.denoisingStrength))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(StudioTheme.textPrimary)
                    Slider(value: $store.denoisingStrength, in: 0.25...0.95, step: 0.05)
                        .tint(StudioTheme.crimson)
                }
            }
        }
        .studioCard()
    }
}

struct FullScreenImageSheet: View {
    let image: UIImage
    let item: VaultImageItem?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: StudioStore
    @State private var scale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { val in scale = max(1.0, min(val, 4.0)) }
                            .onEnded { _ in withAnimation(.spring()) { scale = 1.0 } }
                    )
            }
            .navigationTitle(item?.modelName ?? "Artwork Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.saveImageToPhotos(image)
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
    }
}
