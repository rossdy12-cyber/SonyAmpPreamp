import Foundation
import LocalAuthentication
import SwiftUI
import UIKit

@MainActor
final class StudioStore: ObservableObject {
    // MARK: - Stealth Decoy & Lock State (Hidden from Lauren)
    @Published var isStealthLocked: Bool = true
    @Published var stealthPin: String = UserDefaults.standard.string(forKey: "qwen_stealth_pin") ?? "2070"
    @Published var requireStealthOnLaunch: Bool = (UserDefaults.standard.object(forKey: "qwen_stealth_enabled") as? Bool) ?? true

    // MARK: - Studio Canvas State
    @Published var selectedTab: Int = 0
    @Published var prompt: String = "masterpiece, best quality, ultra detailed, 1girl, loona (helluva boss), anthropomorphic hellhound wolf girl, white and grey fur, red sclera yellow iris eyes, gothic punk aesthetic, full body, wide shot, head to toe, standing, feet visible, cyberpunk neon bedroom, volumetric neon rim lighting"
    @Published var negativePrompt: String = "lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, username, blurry, deformed, mutated, close-up, portrait, headshot, upper body, cowboy shot"
    @Published var selectedEngine: StudioEngine = .standaloneCluster
    @Published var selectedClusterModel: String = "WAI-NSFW-illustrious-SDXL"
    @Published var selectedStylePreset: String = "qwen_anime"
    @Published var selectedAspect: AspectRatioOption = AspectRatioOption.all[0]
    @Published var steps: Double = 24
    @Published var cfgScale: Double = 7.0
    @Published var seedText: String = "-1"
    @Published var autoEnhance: Bool = false

    // Image-to-Image State
    @Published var initImage: UIImage? = nil
    @Published var denoisingStrength: Double = 0.72

    // Generation Progress State
    @Published var isGenerating: Bool = false
    @Published var statusBanner: String = "Ready"
    @Published var activeImage: UIImage? = nil
    @Published var activeVaultItem: VaultImageItem? = nil
    @Published var errorMessage: String? = nil
    @Published var toastMessage: String? = nil

    // MARK: - Prompt Alchemist State
    @Published var wizIdea: String = ""
    @Published var wizCategoryFilter: String = "All"
    @Published var wizSearchQuery: String = ""
    @Published var wizSubject: String = "loona"
    @Published var wizSubject2: String = "none"
    @Published var wizAnatomy: String = "female"
    @Published var wizAnatomy2: String = "same_as_1"
    @Published var wizOutfit: String = "canonical_outfit"
    @Published var wizOutfit2: String = "same"
    @Published var wizPose: String = ""
    @Published var wizPose2: String = "none"
    @Published var wizSetting: String = ""
    @Published var wizLighting: String = ""
    @Published var generatedVariants: [PromptVariantCard] = []

    // MARK: - Vault & Home PC Bridge State
    @Published var vaultItems: [VaultImageItem] = []
    @Published var pcGalleryItems: [VaultImageItem] = []
    @Published var pcBaseURL: String = UserDefaults.standard.string(forKey: "qwen_pc_url") ?? "http://100.102.4.54:7865"
    @Published var hordeApiKey: String = UserDefaults.standard.string(forKey: "qwen_horde_key") ?? "0000000000"
    @Published var pcOnline: Bool = false
    @Published var pcGpuName: String = "Checking..."
    @Published var pcLocalModels: [String] = []

    // MARK: - Reliquary Private Photos Drive State (TrueNAS IDrive-Sync :8788)
    @Published var reliquaryURL: String = {
        let saved = UserDefaults.standard.string(forKey: "qwen_reliquary_url") ?? ""
        if saved.isEmpty || saved.contains("100.85.127.42") {
            return "http://100.64.0.4:8788"
        }
        return saved
    }()
    @Published var reliquaryToken: String = UserDefaults.standard.string(forKey: "qwen_reliquary_token") ?? (String(data: Data(base64Encoded: "TW90aGVyZmZ1Y2tlcjEhIQ==") ?? Data(), encoding: .utf8) ?? "")
    @Published var reliquaryOnline: Bool = false
    @Published var reliquaryStatus: ReliquaryStatusResponse? = nil
    @Published var reliquaryIsLoading: Bool = false
    @Published var reliquaryTimelineItems: [ReliquaryMediaItem] = []
    @Published var reliquaryTimelineKind: String = "" // "" = All, "image" = Photos, "video" = Videos
    @Published var reliquaryTimelineDone: Bool = false
    @Published var reliquaryCurrentFolder: String = "patreon_incoming/patreon"
    @Published var reliquaryFolders: [ReliquaryFolderEntry] = []
    @Published var reliquaryFolderItems: [ReliquaryMediaItem] = []
    @Published var reliquarySearchQuery: String = ""
    @Published var reliquarySearchResults: [ReliquaryMediaItem] = []
    @Published var reliquaryFavorites: [ReliquaryMediaItem] = []

    private let vaultDir: URL

    init() {
        // Hidden Application Support directory (never visible in iOS Files app or Spotlight)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var hiddenDir = appSupport.appendingPathComponent(".corediag_telemetry", isDirectory: true)
        try? FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        var resValues = URLResourceValues()
        resValues.isExcludedFromBackup = true
        try? hiddenDir.setResourceValues(resValues)
        self.vaultDir = hiddenDir

        // Initialize Prompt Alchemist defaults to match exact option IDs from StudioCatalog.shared
        let cat = StudioCatalog.shared
        if let firstSubj = cat.subjects.first(where: { $0.id == "loona" }) ?? cat.subjects.first(where: { $0.id != "none" }) {
            self.wizSubject = firstSubj.id
        }
        if let firstAnat = cat.anatomies.first {
            self.wizAnatomy = firstAnat.id
        }
        if let firstOutf = cat.outfits.first {
            self.wizOutfit = firstOutf.id
        }
        if let firstPose = cat.poses.first {
            self.wizPose = firstPose.id
        }
        if let firstDuoPose = cat.duo_poses.first {
            self.wizPose2 = firstDuoPose.id
        }
        if let firstSet = cat.settings.first {
            self.wizSetting = firstSet.id
        }
        if let firstLight = cat.lightings.first {
            self.wizLighting = firstLight.id
        }

        self.isStealthLocked = self.requireStealthOnLaunch
        migrateLegacyVaultIfNeeded()
        loadVault()
        if let first = vaultItems.first, let img = loadImageFromVault(filename: first.filename) {
            self.activeImage = img
            self.activeVaultItem = first
        }
        buildPromptsOfflineSync()
        Task {
            await checkPCConnection()
            await refreshReliquaryAll()
        }
    }

    // MARK: - Stealth Unlock & Lock Methods
    func lockStealthImmediately() {
        isStealthLocked = true
    }

    func unlockWithBiometrics(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Verify administrator access to CoreDiag kernel telemetry") { success, _ in
                Task { @MainActor in
                    if success {
                        self.isStealthLocked = false
                    }
                    completion(success)
                }
            }
        } else {
            // Fallback if Face ID / Passcode policy isn't configured
            self.isStealthLocked = false
            completion(true)
        }
    }

    func tryUnlockWithPin(_ candidate: String) -> Bool {
        if candidate.trimmingCharacters(in: .whitespacesAndNewlines) == stealthPin {
            isStealthLocked = false
            return true
        }
        return false
    }

    func saveSettings() {
        let cleaned = pcBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        pcBaseURL = cleaned
        let cleanedRel = reliquaryURL.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        reliquaryURL = cleanedRel
        UserDefaults.standard.set(cleaned, forKey: "qwen_pc_url")
        UserDefaults.standard.set(cleanedRel, forKey: "qwen_reliquary_url")
        UserDefaults.standard.set(reliquaryToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "qwen_reliquary_token")
        UserDefaults.standard.set(hordeApiKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "qwen_horde_key")
        UserDefaults.standard.set(stealthPin.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "qwen_stealth_pin")
        UserDefaults.standard.set(requireStealthOnLaunch, forKey: "qwen_stealth_enabled")
        showToast("Saved settings")
        Task {
            await checkPCConnection()
            await refreshReliquaryAll()
        }
    }

    func showToast(_ msg: String) {
        toastMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if toastMessage == msg {
                toastMessage = nil
            }
        }
    }

    // MARK: - Home PC RTX 2070 Super Connection & Gallery Sync
    func checkPCConnection() async {
        guard let url = URL(string: "\(pcBaseURL)/api/status") else {
            pcOnline = false
            pcGpuName = "Invalid URL"
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4.0
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                pcOnline = false
                pcGpuName = "Offline"
                return
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hw = json["hardware"] as? [String: Any] {
                let gpu = (hw["gpu_name"] as? String) ?? "Home PC GPU"
                let cuda = (hw["cuda_available"] as? Bool) ?? false
                pcOnline = true
                pcGpuName = cuda ? "\(gpu) (CUDA Ready)" : "\(gpu) (Online)"
                if let models = json["installed_local_models"] as? [[String: Any]] {
                    pcLocalModels = models.compactMap { $0["filename"] as? String }
                }
                await fetchPCGallery()
            }
        } catch {
            pcOnline = false
            pcGpuName = "Unreachable (Use AI Cluster or check Tailscale/Wi-Fi)"
        }
    }

    func fetchPCGallery() async {
        guard let url = URL(string: "\(pcBaseURL)/api/gallery") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6.0
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return }
            var parsed: [VaultImageItem] = []
            for item in items.prefix(50) {
                let fname = (item["filename"] as? String) ?? ""
                guard !fname.isEmpty else { continue }
                let relURL = (item["url"] as? String) ?? "/outputs/\(fname)"
                let p = (item["final_prompt"] as? String) ?? (item["raw_prompt"] as? String) ?? ""
                let np = (item["negative_prompt"] as? String) ?? ""
                let model = (item["model"] as? String) ?? "RTX 2070 Super"
                let eng = (item["engine"] as? String) ?? "local_gpu"
                let w = (item["width"] as? Int) ?? 832
                let h = (item["height"] as? Int) ?? 1216
                let seed = (item["seed"] as? Int) ?? -1
                let st = (item["steps"] as? Int) ?? 25
                let cfg = (item["cfg_scale"] as? Double) ?? 7.0
                parsed.append(
                    VaultImageItem(
                        id: "pc_\(fname)",
                        filename: fname,
                        prompt: p,
                        negativePrompt: np,
                        modelName: model,
                        engine: eng,
                        width: w,
                        height: h,
                        seed: seed,
                        steps: st,
                        cfgScale: cfg,
                        createdAt: Date(),
                        remoteURL: "\(pcBaseURL)\(relURL)"
                    )
                )
            }
            self.pcGalleryItems = parsed
        } catch {
            // Ignore gallery sync failure silently
        }
    }

    // MARK: - Prompt Alchemist (Hybrid PC + 100% Standalone On-Device Builder)
    func buildPromptsFromAlchemist() async {
        let s2Clean = (wizSubject2 == "none") ? "" : wizSubject2
        let p2Clean = (wizPose2 == "none") ? "" : wizPose2
        if pcOnline, let url = URL(string: "\(pcBaseURL)/api/generate-prompts") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 5.0
            let body: [String: Any] = [
                "idea": wizIdea,
                "subject": wizSubject == "none" ? "" : wizSubject,
                "subject_2": s2Clean,
                "anatomy": wizAnatomy,
                "anatomy_2": wizAnatomy2,
                "outfit": wizOutfit == "none" ? "" : wizOutfit,
                "outfit_2": wizOutfit2,
                "pose": wizPose == "none" ? "" : wizPose,
                "pose_2": p2Clean,
                "setting": wizSetting == "none" ? "" : wizSetting,
                "lighting": wizLighting == "none" ? "" : wizLighting,
                "rating": "uncensored",
                "style_preset": selectedStylePreset
            ]
            if let httpBody = try? JSONSerialization.data(withJSONObject: body) {
                req.httpBody = httpBody
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let rawVars = json["variants"] as? [[String: Any]] {
                    var cards: [PromptVariantCard] = []
                    for rv in rawVars {
                        cards.append(
                            PromptVariantCard(
                                title: (rv["title"] as? String) ?? "Prompt Variant",
                                recommended_for: (rv["recommended_for"] as? String) ?? "SDXL",
                                prompt: (rv["prompt"] as? String) ?? "",
                                negative: (rv["negative"] as? String) ?? ""
                            )
                        )
                    }
                    if !cards.isEmpty {
                        self.generatedVariants = cards
                        showToast("Built \(cards.count) prompt variants")
                        return
                    }
                }
            }
        }

        buildPromptsOfflineSync()
        showToast("Built 3 prompt variants")
    }

    func buildPromptsOfflineSync() {
        let cat = StudioCatalog.shared
        let char1 = buildSingleCharacterTags(
            subjectKey: wizSubject,
            anatomyKey: wizAnatomy,
            outfitText: wizOutfit,
            poseText: wizPose == "none" ? "" : wizPose,
            catalog: cat
        )

        let s2Clean = (wizSubject2 == "none") ? "" : wizSubject2.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDuo = !s2Clean.isEmpty
        let effAnat2 = (wizAnatomy2 == "same_as_1" || wizAnatomy2.isEmpty) ? wizAnatomy : wizAnatomy2
        let effOutfit2 = (wizOutfit2 == "same") ? wizOutfit : (wizOutfit2 == "default" ? "canonical_outfit" : wizOutfit2)
        let p2Clean = (wizPose2 == "none") ? "" : wizPose2
        let char2 = hasDuo ? buildSingleCharacterTags(
            subjectKey: s2Clean,
            anatomyKey: effAnat2,
            outfitText: effOutfit2,
            poseText: p2Clean,
            catalog: cat
        ) : nil

        let framingTags = "full body, wide shot, head to toe, standing, feet visible"
        let antiCloseupNeg = "close-up, portrait, cropped, headshot, upper body, cowboy shot, out of frame"
        let baseNeg = "lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, worst quality, low quality, jpeg artifacts, signature, watermark, username, blurry, deformed, mutated"

        var extraParts: [String] = [framingTags]
        if !wizIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extraParts.append(wizIdea.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !wizSetting.isEmpty && wizSetting != "none" { extraParts.append(wizSetting) }
        if !wizLighting.isEmpty && wizLighting != "none" { extraParts.append(wizLighting) }
        let sceneSuffix = extraParts.joined(separator: ", ")

        let booruPrompt: String
        let furryPrompt: String
        let photoPrompt: String
        let combinedNeg: String

        if let c2 = char2 {
            let duoHeader = "2 characters, duo, interacting, \(p2Clean.isEmpty ? "standing together" : p2Clean), \(framingTags)"
            if selectedEngine == .homePCRTX {
                booruPrompt = "masterpiece, best quality, ultra detailed, \(duoHeader), \(char1.anime), \(sceneSuffix) ||DUO_SPLIT|| masterpiece, best quality, ultra detailed, \(duoHeader), \(c2.anime), \(sceneSuffix)"
                furryPrompt = "masterpiece, best quality, Kemono FurAffinity high-res, \(duoHeader), \(char1.furry), \(sceneSuffix) ||DUO_SPLIT|| masterpiece, best quality, Kemono FurAffinity high-res, \(duoHeader), \(c2.furry), \(sceneSuffix)"
            } else {
                booruPrompt = "masterpiece, best quality, ultra detailed, \(duoHeader), CHARACTER 1: (\(char1.anime)), CHARACTER 2: (\(c2.anime)), \(sceneSuffix)"
                furryPrompt = "masterpiece, best quality, Kemono FurAffinity high-res, \(duoHeader), CHARACTER 1: (\(char1.furry)), CHARACTER 2: (\(c2.furry)), \(sceneSuffix)"
            }
            photoPrompt = "RAW photo, 8k uhd, dslr, masterpiece, \(duoHeader), \(char1.base), and \(c2.base), \(sceneSuffix)"
            combinedNeg = "\(baseNeg), \(antiCloseupNeg), \(char1.neg), \(c2.neg), solo, 1girl, 1boy, fused bodies, cloned face"
        } else {
            booruPrompt = "masterpiece, best quality, absurdres, \(char1.anime), \(sceneSuffix)"
            furryPrompt = "masterpiece, best quality, absurdres, furry, anthro, Kemono style, \(char1.furry), \(sceneSuffix)"
            photoPrompt = "RAW photo, 8k uhd, dslr, masterpiece, ultra realistic, \(char1.base), \(sceneSuffix)"
            combinedNeg = "\(baseNeg), \(antiCloseupNeg), \(char1.neg)"
        }

        self.generatedVariants = [
            PromptVariantCard(
                title: "1. Illustrious / Pony V6 Booru XL",
                recommended_for: "WAI-NSFW-illustrious-SDXL / Pony V6 XL",
                prompt: booruPrompt,
                negative: combinedNeg
            ),
            PromptVariantCard(
                title: "2. Anthro / Furry / Kemono Masterpiece",
                recommended_for: "WAI-NSFW-illustrious-SDXL / Pony V6 XL",
                prompt: furryPrompt,
                negative: combinedNeg
            ),
            PromptVariantCard(
                title: "3. Cinema 8K / AlbedoBase XL",
                recommended_for: "AlbedoBase XL (SDXL) / Juggernaut XL",
                prompt: photoPrompt,
                negative: combinedNeg
            )
        ]
    }

    private func buildSingleCharacterTags(
        subjectKey: String,
        anatomyKey: String,
        outfitText: String,
        poseText: String,
        catalog: CatalogBundle
    ) -> (base: String, anime: String, furry: String, neg: String) {
        let bank = catalog.character_banks[subjectKey]
        let baseStr = bank?.base ?? subjectKey
        let animeStr = bank?.anime ?? subjectKey
        let furryStr = bank?.furry ?? subjectKey
        let canonOutfit = bank?.canonical_outfit ?? ""

        let anatPos = catalog.anatomy_pos[anatomyKey] ?? ""
        var anatNeg = catalog.anatomy_neg[anatomyKey] ?? ""

        let isDefaultOutfit = (outfitText.isEmpty || outfitText == "canonical_outfit" || outfitText == "none")
        let isExplicitlyBare = outfitText.lowercased().contains("nude") || outfitText.lowercased().contains("no_clothes")

        let resolvedOutfit: String
        if isExplicitlyBare {
            resolvedOutfit = outfitText
            anatNeg += ", clothes, clothing, dressed, underwear, panties, bra, bikini, swimsuit, Lingering clothing, covered, bottomwear, shorts, pants, skirt, dress, censorship, mosaic censoring, bar censor"
        } else if isDefaultOutfit {
            if anatomyKey != "female" {
                // Non-female anatomy defaults to unclothed so clothing doesn't hide anatomy
                resolvedOutfit = "nude, completely_nude, no_clothes, uncensored"
                anatNeg += ", clothes, clothing, dressed, underwear, panties, bra, bikini, swimsuit, bottomwear, shorts, pants, skirt, dress, censorship, mosaic censoring, bar censor"
            } else {
                resolvedOutfit = canonOutfit
            }
        } else {
            resolvedOutfit = outfitText
        }

        let assemble: (String) -> String = { core in
            [anatPos, core, resolvedOutfit, poseText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }

        return (
            base: assemble(baseStr),
            anime: assemble(animeStr),
            furry: assemble(furryStr),
            neg: anatNeg
        )
    }

    func applyVariant(_ card: PromptVariantCard, generateImmediately: Bool = false) {
        self.prompt = card.prompt
        self.negativePrompt = card.negative
        if prompt.contains("||DUO_SPLIT||") {
            if let duoAspect = AspectRatioOption.all.first(where: { $0.id == "1152x768" }) {
                self.selectedAspect = duoAspect
            }
        }
        self.selectedTab = 0
        showToast("Loaded into Studio Canvas")
        if generateImmediately {
            Task {
                await generateImage()
            }
        }
    }

    // MARK: - Main Image Generation Dispatcher
    func generateImage() async {
        guard !isGenerating else { return }
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else {
            errorMessage = "Please enter a prompt or build one in the Alchemist tab."
            return
        }

        isGenerating = true
        errorMessage = nil
        statusBanner = "Initializing \(selectedEngine.shortTitle)..."

        let rawSeed = Int(seedText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        let actualSeed = (rawSeed < 0) ? Int.random(in: 100_000...999_999_999) : rawSeed

        do {
            switch selectedEngine {
            case .homePCRTX:
                try await generateViaHomePC(prompt: cleanPrompt, negative: negativePrompt, seed: actualSeed)
            case .standaloneCluster:
                try await generateViaStandaloneHorde(prompt: cleanPrompt, negative: negativePrompt, seed: actualSeed)
            case .cloudFlux:
                try await generateViaCloudFlux(prompt: cleanPrompt, negative: negativePrompt, seed: actualSeed)
            }
        } catch {
            errorMessage = error.localizedDescription
            statusBanner = "Generation failed"
        }

        isGenerating = false
    }

    // MARK: - 1. Home PC RTX 2070 Super Bridge Engine
    private func generateViaHomePC(prompt: String, negative: String, seed: Int) async throws {
        statusBanner = "Sending to Home PC RTX 2070 Super (\(pcBaseURL))..."
        guard let url = URL(string: "\(pcBaseURL)/api/generate") else {
            throw NSError(domain: "QwenStudio", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Home PC URL. Check the GPU Link tab."])
        }

        var body: [String: Any] = [
            "prompt": prompt,
            "negative_prompt": negative,
            "style_preset": selectedStylePreset,
            "auto_enhance": autoEnhance,
            "engine": "local_gpu",
            "width": selectedAspect.width,
            "height": selectedAspect.height,
            "steps": Int(steps),
            "cfg_scale": cfgScale,
            "seed": seed,
            "batch_size": 1,
            "denoising_strength": denoisingStrength
        ]

        if let initImg = initImage, let jpeg = initImg.jpegData(compressionQuality: 0.9) {
            body["init_image_b64"] = jpeg.base64EncodedString()
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 240.0
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        statusBanner = "Rendering on RTX 2070 Super GPU (308-token SDXL)..."
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "QwenStudio", code: 500, userInfo: [NSLocalizedDescriptionKey: "No response from Home PC."])
        }
        if http.statusCode != 200 {
            let errText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "QwenStudio", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Home PC error: \(errText)"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [[String: Any]],
              let first = images.first,
              let relURL = first["url"] as? String,
              let imgURL = URL(string: "\(pcBaseURL)\(relURL)") else {
            throw NSError(domain: "QwenStudio", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response from Home PC."])
        }

        statusBanner = "Downloading rendered PNG from Home PC..."
        let (imgData, _) = try await URLSession.shared.data(from: imgURL)
        guard let uiImg = UIImage(data: imgData) else {
            throw NSError(domain: "QwenStudio", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not decode image from Home PC."])
        }

        let item = saveToVault(
            image: uiImg,
            prompt: prompt,
            negativePrompt: negative,
            modelName: "RTX 2070S (WAI-Illustrious v14)",
            engine: StudioEngine.homePCRTX.rawValue,
            width: Int(uiImg.size.width),
            height: Int(uiImg.size.height),
            seed: seed
        )
        self.activeImage = uiImg
        self.activeVaultItem = item
        self.statusBanner = "Rendered on Home PC RTX 2070 Super!"
        showToast("Render complete!")
    }

    // MARK: - 2. Standalone AI Horde Cluster Engine
    private func generateViaStandaloneHorde(prompt: String, negative: String, seed: Int) async throws {
        let cleanedPrompt = prompt.replacingOccurrences(of: "||DUO_SPLIT||", with: ", ")
        let hordeCombinedPrompt = "\(cleanedPrompt) ### \(negative)"

        let wReq = max(512, min(1024, (selectedAspect.width / 64) * 64))
        let hReq = max(512, min(1024, (selectedAspect.height / 64) * 64))
        let stepsReq = min(Int(steps), 28)

        let jobId: String
        do {
            jobId = try await submitHordeJob(
                combinedPrompt: hordeCombinedPrompt,
                width: wReq,
                height: hReq,
                steps: stepsReq,
                seed: seed
            )
        } catch {
            statusBanner = "Using cluster-optimized resolution (576×768)..."
            let fallbackW = selectedAspect.width > selectedAspect.height ? 768 : (selectedAspect.width == selectedAspect.height ? 640 : 576)
            let fallbackH = selectedAspect.height > selectedAspect.width ? 768 : 640
            jobId = try await submitHordeJob(
                combinedPrompt: hordeCombinedPrompt,
                width: fallbackW,
                height: fallbackH,
                steps: 22,
                seed: seed
            )
        }

        statusBanner = "Queued on \(selectedClusterModel)..."
        guard let checkURL = URL(string: "https://aihorde.net/api/v2/generate/check/\(jobId)"),
              let statusURL = URL(string: "https://aihorde.net/api/v2/generate/status/\(jobId)") else {
            throw NSError(domain: "QwenStudio", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid cluster status URL."])
        }

        for attempt in 1...80 {
            try await Task.sleep(nanoseconds: 3_000_000_000)
            let (cData, _) = try await URLSession.shared.data(from: checkURL)
            if let cJson = try? JSONSerialization.jsonObject(with: cData) as? [String: Any] {
                let done = (cJson["done"] as? Bool) ?? false
                let faulted = (cJson["faulted"] as? Bool) ?? false
                let waitTime = (cJson["wait_time"] as? Int) ?? 0
                let queuePos = (cJson["queue_position"] as? Int) ?? 0
                let processing = (cJson["processing"] as? Int) ?? 0

                if faulted {
                    throw NSError(domain: "QwenStudio", code: 500, userInfo: [NSLocalizedDescriptionKey: "Cluster worker faulted. Please tap Generate again."])
                }
                if done {
                    break
                }
                if processing > 0 {
                    statusBanner = "Rendering on GPU Worker (\(selectedClusterModel))... ~\(max(2, waitTime))s"
                } else if queuePos > 0 {
                    statusBanner = "Queue #\(queuePos) (\(selectedClusterModel)) • Est. \(waitTime)s"
                } else {
                    statusBanner = "Dispatching to GPU Worker (poll \(attempt))..."
                }
            }
        }

        statusBanner = "Fetching rendered artwork..."
        let (sData, _) = try await URLSession.shared.data(from: statusURL)
        guard let sJson = try JSONSerialization.jsonObject(with: sData) as? [String: Any],
              let gens = sJson["generations"] as? [[String: Any]],
              let firstGen = gens.first,
              let imgField = firstGen["img"] as? String else {
            throw NSError(domain: "QwenStudio", code: 504, userInfo: [NSLocalizedDescriptionKey: "Cluster timed out or returned no image."])
        }

        let rawImageData: Data
        if imgField.hasPrefix("http"), let rURL = URL(string: imgField) {
            let (dlData, _) = try await URLSession.shared.data(from: rURL)
            rawImageData = dlData
        } else if let b64Data = Data(base64Encoded: imgField, options: .ignoreUnknownCharacters) {
            rawImageData = b64Data
        } else {
            throw NSError(domain: "QwenStudio", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not read cluster image payload."])
        }

        guard let decodedImg = UIImage(data: rawImageData) else {
            throw NSError(domain: "QwenStudio", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to decode WebP/PNG image."])
        }

        let item = saveToVault(
            image: decodedImg,
            prompt: prompt,
            negativePrompt: negative,
            modelName: selectedClusterModel,
            engine: StudioEngine.standaloneCluster.rawValue,
            width: Int(decodedImg.size.width),
            height: Int(decodedImg.size.height),
            seed: seed
        )
        self.activeImage = decodedImg
        self.activeVaultItem = item
        self.statusBanner = "Rendered on \(selectedClusterModel)!"
        showToast("Saved to Private Vault!")
    }

    private func submitHordeJob(combinedPrompt: String, width: Int, height: Int, steps: Int, seed: Int) async throws -> String {
        guard let url = URL(string: "https://aihorde.net/api/v2/generate/async") else {
            throw NSError(domain: "QwenStudio", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid cluster endpoint."])
        }
        var params: [String: Any] = [
            "sampler_name": "k_euler_a",
            "cfg_scale": cfgScale,
            "width": width,
            "height": height,
            "steps": steps,
            "karras": true,
            "clip_skip": 2,
            "seed": "\(seed)",
            "n": 1
        ]
        var payload: [String: Any] = [
            "prompt": combinedPrompt,
            "params": params,
            "nsfw": true,
            "censor_nsfw": false,
            "trusted_workers": false,
            "r2": true,
            "models": [selectedClusterModel]
        ]
        if let initImg = initImage, let jpeg = initImg.jpegData(compressionQuality: 0.85) {
            payload["source_image"] = jpeg.base64EncodedString()
            payload["source_processing"] = "img2img"
            params["denoising_strength"] = denoisingStrength
            payload["params"] = params
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = hordeApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0000000000" : hordeApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("QwenStudioiOS:2.1:RossDymond", forHTTPHeaderField: "Client-Agent")
        req.timeoutInterval = 25.0
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "QwenStudio", code: 500, userInfo: [NSLocalizedDescriptionKey: "No response from AI Cluster."])
        }
        guard (200...202).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "QwenStudio", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return id
    }

    // MARK: - 3. Instant Cloud Flux Engine
    private func generateViaCloudFlux(prompt: String, negative: String, seed: Int) async throws {
        statusBanner = "Synthesizing via Cloud Flux..."
        let cleaned = prompt.replacingOccurrences(of: "||DUO_SPLIT||", with: ", ")
        let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "masterpiece"
        let urlStr = "https://image.pollinations.ai/prompt/\(encoded)?width=\(selectedAspect.width)&height=\(selectedAspect.height)&seed=\(seed)&nologo=true&safe=false&model=flux"

        if let url = URL(string: urlStr) {
            var req = URLRequest(url: url)
            req.timeoutInterval = 30.0
            req.setValue("QwenStudioiOS/2.1", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let uiImg = UIImage(data: data) {
                let item = saveToVault(
                    image: uiImg,
                    prompt: prompt,
                    negativePrompt: negative,
                    modelName: "Cloud Flux Uncensored",
                    engine: StudioEngine.cloudFlux.rawValue,
                    width: Int(uiImg.size.width),
                    height: Int(uiImg.size.height),
                    seed: seed
                )
                self.activeImage = uiImg
                self.activeVaultItem = item
                self.statusBanner = "Rendered via Cloud Flux!"
                showToast("Saved to Private Vault!")
                return
            }
        }
        statusBanner = "Cloud Flux busy — routing to Uncensored AI Cluster..."
        try await generateViaStandaloneHorde(prompt: prompt, negative: negative, seed: seed)
    }

    // MARK: - 2x Crisp Super-Resolution Upscaler on Device
    func upscaleActiveImage() {
        guard let src = activeImage else { return }
        statusBanner = "Upscaling 2x on iPhone..."
        let targetSize = CGSize(width: src.size.width * 2, height: src.size.height * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let upscaled = renderer.image { _ in
            src.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        let item = saveToVault(
            image: upscaled,
            prompt: activeVaultItem?.prompt ?? prompt,
            negativePrompt: activeVaultItem?.negativePrompt ?? negativePrompt,
            modelName: "\(activeVaultItem?.modelName ?? "Studio") (2x Upscaled)",
            engine: activeVaultItem?.engine ?? selectedEngine.rawValue,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            seed: activeVaultItem?.seed ?? -1
        )
        self.activeImage = upscaled
        self.activeVaultItem = item
        statusBanner = "Upscaled to \(Int(targetSize.width))×\(Int(targetSize.height))!"
        showToast("2x Upscale saved to Vault!")
    }

    // MARK: - Hidden Private iPhone Vault Persistence
    func saveToVault(
        image: UIImage,
        prompt: String,
        negativePrompt: String,
        modelName: String,
        engine: String,
        width: Int,
        height: Int,
        seed: Int
    ) -> VaultImageItem {
        let id = UUID().uuidString
        let ts = Int(Date().timeIntervalSince1970)
        let filename = "diag_\(ts)_\(seed).dat"
        let fileURL = vaultDir.appendingPathComponent(filename)
        if let png = image.pngData() {
            try? png.write(to: fileURL, options: .atomic)
        }
        let item = VaultImageItem(
            id: id,
            filename: filename,
            prompt: prompt,
            negativePrompt: negativePrompt,
            modelName: modelName,
            engine: engine,
            width: width,
            height: height,
            seed: seed,
            steps: Int(steps),
            cfgScale: cfgScale,
            createdAt: Date(),
            remoteURL: nil
        )
        vaultItems.insert(item, at: 0)
        persistVaultIndex()
        return item
    }

    func loadImageFromVault(filename: String) -> UIImage? {
        let fileURL = vaultDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    func deleteVaultItem(_ item: VaultImageItem) {
        let fileURL = vaultDir.appendingPathComponent(item.filename)
        try? FileManager.default.removeItem(at: fileURL)
        vaultItems.removeAll { $0.id == item.id }
        persistVaultIndex()
        showToast("Deleted from Vault")
    }

    func saveImageToPhotos(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        showToast("Saved to iPhone Photos!")
    }

    private func migrateLegacyVaultIfNeeded() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let oldVault = docs.appendingPathComponent("Vault", isDirectory: true)
        guard FileManager.default.fileExists(atPath: oldVault.path) else { return }
        if let files = try? FileManager.default.contentsOfDirectory(at: oldVault, includingPropertiesForKeys: nil) {
            for f in files {
                let dest = vaultDir.appendingPathComponent(f.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.moveItem(at: f, to: dest)
                }
            }
        }
        try? FileManager.default.removeItem(at: oldVault)
    }

    private func loadVault() {
        let indexURL = vaultDir.appendingPathComponent("vault_index.json")
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([VaultImageItem].self, from: data) else {
            return
        }
        self.vaultItems = decoded.filter {
            FileManager.default.fileExists(atPath: vaultDir.appendingPathComponent($0.filename).path)
        }
    }

    private func persistVaultIndex() {
        let indexURL = vaultDir.appendingPathComponent("vault_index.json")
        if let data = try? JSONEncoder().encode(vaultItems) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Reliquary Private Photos Drive Client (TrueNAS IDrive-Sync :8788)
    private func makeReliquaryRequest(path: String, queryItems: [URLQueryItem] = [], method: String = "GET") -> URLRequest? {
        guard var comps = URLComponents(string: "\(reliquaryURL)\(path)") else { return nil }
        if !queryItems.isEmpty {
            comps.queryItems = queryItems
        }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 12.0
        let tok = reliquaryToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tok.isEmpty {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    func reliquaryThumbURL(path: String, size: String = "s") -> URL? {
        guard var comps = URLComponents(string: "\(reliquaryURL)/thumb") else { return nil }
        var items = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "size", value: size)
        ]
        let tok = reliquaryToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tok.isEmpty {
            items.append(URLQueryItem(name: "token", value: tok))
        }
        comps.queryItems = items
        return comps.url
    }

    func reliquaryFileURL(path: String) -> URL? {
        guard var comps = URLComponents(string: "\(reliquaryURL)/file") else { return nil }
        var items = [URLQueryItem(name: "path", value: path)]
        let tok = reliquaryToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tok.isEmpty {
            items.append(URLQueryItem(name: "token", value: tok))
        }
        comps.queryItems = items
        return comps.url
    }

    func refreshReliquaryAll() async {
        await fetchReliquaryStatus()
        if reliquaryOnline {
            await fetchReliquaryTimeline(reset: true)
            await fetchReliquaryFolder(reliquaryCurrentFolder)
            await fetchReliquaryFavorites()
        }
    }

    func fetchReliquaryStatus() async {
        guard let req = makeReliquaryRequest(path: "/api/status") else {
            reliquaryOnline = false
            return
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                reliquaryOnline = false
                return
            }
            let status = try JSONDecoder().decode(ReliquaryStatusResponse.self, from: data)
            self.reliquaryStatus = status
            self.reliquaryOnline = true
        } catch {
            self.reliquaryOnline = false
        }
    }

    func fetchReliquaryTimeline(reset: Bool = false) async {
        if reset {
            reliquaryTimelineItems = []
            reliquaryTimelineDone = false
        }
        guard !reliquaryTimelineDone && !reliquaryIsLoading else { return }
        reliquaryIsLoading = true
        defer { reliquaryIsLoading = false }

        let offset = reliquaryTimelineItems.count
        var q = [
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "limit", value: "120")
        ]
        if !reliquaryTimelineKind.isEmpty {
            q.append(URLQueryItem(name: "kind", value: reliquaryTimelineKind))
        }
        guard let req = makeReliquaryRequest(path: "/api/timeline", queryItems: q) else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode(ReliquaryTimelineResponse.self, from: data)
            if reset {
                self.reliquaryTimelineItems = decoded.items
            } else {
                let existing = Set(self.reliquaryTimelineItems.map { $0.path })
                let newOnes = decoded.items.filter { !existing.contains($0.path) }
                self.reliquaryTimelineItems.append(contentsOf: newOnes)
            }
            self.reliquaryTimelineDone = decoded.done ?? (decoded.items.count < 120)
            self.reliquaryOnline = true
        } catch {
            // Keep existing items on transient network blip
        }
    }

    func fetchReliquaryFolder(_ folderPath: String) async {
        reliquaryIsLoading = true
        defer { reliquaryIsLoading = false }
        let q = [URLQueryItem(name: "path", value: folderPath)]
        guard let req = makeReliquaryRequest(path: "/api/list", queryItems: q) else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode(ReliquaryListingResponse.self, from: data)
            self.reliquaryCurrentFolder = decoded.path
            self.reliquaryFolders = decoded.folders
            self.reliquaryFolderItems = decoded.items
            self.reliquaryOnline = true
        } catch {
            // Ignore
        }
    }

    func searchReliquary(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            reliquarySearchResults = []
            return
        }
        reliquaryIsLoading = true
        defer { reliquaryIsLoading = false }
        let q = [URLQueryItem(name: "q", value: trimmed)]
        guard let req = makeReliquaryRequest(path: "/api/search", queryItems: q) else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode(ReliquaryTimelineResponse.self, from: data)
            self.reliquarySearchResults = decoded.items
        } catch {
            // Ignore
        }
    }

    func fetchReliquaryFavorites() async {
        guard let req = makeReliquaryRequest(path: "/api/favorites") else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode(ReliquaryTimelineResponse.self, from: data)
            self.reliquaryFavorites = decoded.items
        } catch {
            // Ignore
        }
    }

    func toggleReliquaryFavorite(_ item: ReliquaryMediaItem) async {
        let newFav = !item.favorite
        guard var req = makeReliquaryRequest(path: "/api/favorite", method: "POST") else { return }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["path": item.path, "favorite": newFav]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            if let idx = reliquaryTimelineItems.firstIndex(where: { $0.path == item.path }) {
                reliquaryTimelineItems[idx].favorite = newFav
            }
            if let idx = reliquaryFolderItems.firstIndex(where: { $0.path == item.path }) {
                reliquaryFolderItems[idx].favorite = newFav
            }
            if let idx = reliquarySearchResults.firstIndex(where: { $0.path == item.path }) {
                reliquarySearchResults[idx].favorite = newFav
            }
            await fetchReliquaryFavorites()
            await fetchReliquaryStatus()
            showToast(newFav ? "Added to Reliquary Favorites ♥" : "Removed from Favorites")
        } catch {
            showToast("Failed to update favorite")
        }
    }

    func triggerReliquaryRescan() async {
        guard let req = makeReliquaryRequest(path: "/api/rescan", method: "POST") else { return }
        _ = try? await URLSession.shared.data(for: req)
        showToast("Triggered Reliquary Drive scan")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await fetchReliquaryStatus()
    }

    func downloadReliquaryUIImage(_ item: ReliquaryMediaItem, highRes: Bool = true) async -> UIImage? {
        let targetURL = highRes ? (reliquaryFileURL(path: item.path) ?? reliquaryThumbURL(path: item.path, size: "m")) : reliquaryThumbURL(path: item.path, size: "m")
        guard let url = targetURL else { return nil }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200, let img = UIImage(data: data) {
                return img
            }
        } catch {}
        if let fallbackURL = reliquaryThumbURL(path: item.path, size: "m"),
           let (data, _) = try? await URLSession.shared.data(from: fallbackURL) {
            return UIImage(data: data)
        }
        return nil
    }

    func saveReliquaryItemToLocalVault(_ item: ReliquaryMediaItem) async {
        showToast("Downloading from Reliquary Drive...")
        guard let img = await downloadReliquaryUIImage(item, highRes: true) else {
            showToast("Could not download image")
            return
        }
        _ = saveToVault(
            image: img,
            prompt: "Reliquary Drive: \(item.folder)/\(item.name)",
            negativePrompt: "",
            modelName: "Reliquary Private Drive",
            engine: "reliquary_sync",
            width: Int(img.size.width),
            height: Int(img.size.height),
            seed: -1
        )
        showToast("Saved to Offline Hidden Vault!")
    }

    func saveReliquaryItemToPhotos(_ item: ReliquaryMediaItem) async {
        showToast("Downloading full-res photo...")
        guard let img = await downloadReliquaryUIImage(item, highRes: true) else {
            showToast("Could not download photo")
            return
        }
        saveImageToPhotos(img)
    }

    func useReliquaryItemInStudio(_ item: ReliquaryMediaItem) async {
        showToast("Loading into Studio Img2Img...")
        guard let img = await downloadReliquaryUIImage(item, highRes: false) else {
            showToast("Could not load reference image")
            return
        }
        self.initImage = img
        self.selectedTab = 0
        showToast("Loaded as Studio Reference Image!")
    }
}
