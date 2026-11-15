import Foundation
import SwiftUI
import UIKit

@MainActor
final class StudioStore: ObservableObject {
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
    @Published var wizSubject2: String = ""
    @Published var wizAnatomy: String = "female"
    @Published var wizAnatomy2: String = "same_as_1"
    @Published var wizOutfit: String = ""
    @Published var wizOutfit2: String = "same"
    @Published var wizPose: String = "full body standing confidently, head to toe visible"
    @Published var wizPose2: String = ""
    @Published var wizSetting: String = "luxury penthouse bedroom at night, neon city skyline through floor-to-ceiling glass"
    @Published var wizLighting: String = "cinematic rim lighting, volumetric neon glow, soft shadows"
    @Published var generatedVariants: [PromptVariantCard] = []

    // MARK: - Vault & Home PC Bridge State
    @Published var vaultItems: [VaultImageItem] = []
    @Published var pcGalleryItems: [VaultImageItem] = []
    @Published var pcBaseURL: String = UserDefaults.standard.string(forKey: "qwen_pc_url") ?? "http://100.102.4.54:7865"
    @Published var hordeApiKey: String = UserDefaults.standard.string(forKey: "qwen_horde_key") ?? "0000000000"
    @Published var pcOnline: Bool = false
    @Published var pcGpuName: String = "Checking..."
    @Published var pcLocalModels: [String] = []

    private let vaultDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.vaultDir = docs.appendingPathComponent("Vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: vaultDir, withIntermediateDirectories: true)
        loadVault()
        if let first = vaultItems.first, let img = loadImageFromVault(filename: first.filename) {
            self.activeImage = img
            self.activeVaultItem = first
        }
        Task {
            await checkPCConnection()
        }
    }

    func saveSettings() {
        let cleaned = pcBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        pcBaseURL = cleaned
        UserDefaults.standard.set(cleaned, forKey: "qwen_pc_url")
        UserDefaults.standard.set(hordeApiKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "qwen_horde_key")
        showToast("Saved bridge settings")
        Task {
            await checkPCConnection()
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
        // If Home PC is reachable, try the PC's /api/generate-prompts endpoint first for 100% parity
        if pcOnline, let url = URL(string: "\(pcBaseURL)/api/generate-prompts") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 5.0
            let body: [String: Any] = [
                "idea": wizIdea,
                "subject": wizSubject,
                "subject_2": wizSubject2,
                "anatomy": wizAnatomy,
                "anatomy_2": wizAnatomy2,
                "outfit": wizOutfit,
                "outfit_2": wizOutfit2,
                "pose": wizPose,
                "pose_2": wizPose2,
                "setting": wizSetting,
                "lighting": wizLighting,
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

        // Standalone On-Device Prompt Builder (works 100% offline / anywhere)
        let cat = StudioCatalog.shared
        let char1 = buildSingleCharacterTags(
            subjectKey: wizSubject,
            anatomyKey: wizAnatomy,
            outfitText: wizOutfit,
            poseText: wizPose,
            catalog: cat
        )

        let hasDuo = !wizSubject2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let effAnat2 = (wizAnatomy2 == "same_as_1" || wizAnatomy2.isEmpty) ? wizAnatomy : wizAnatomy2
        let effOutfit2 = (wizOutfit2 == "same") ? wizOutfit : (wizOutfit2 == "default" ? "" : wizOutfit2)
        let char2 = hasDuo ? buildSingleCharacterTags(
            subjectKey: wizSubject2,
            anatomyKey: effAnat2,
            outfitText: effOutfit2,
            poseText: wizPose2,
            catalog: cat
        ) : nil

        let framingTags = "full body, wide shot, head to toe, standing, feet visible"
        let antiCloseupNeg = "close-up, portrait, cropped, headshot, upper body, cowboy shot, out of frame"
        let baseNeg = "lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, worst quality, low quality, jpeg artifacts, signature, watermark, username, blurry, deformed, mutated"

        var extraParts: [String] = [framingTags]
        if !wizIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extraParts.append(wizIdea.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !wizSetting.isEmpty { extraParts.append(wizSetting) }
        if !wizLighting.isEmpty { extraParts.append(wizLighting) }
        let sceneSuffix = extraParts.joined(separator: ", ")

        let booruPrompt: String
        let furryPrompt: String
        let photoPrompt: String
        let combinedNeg: String

        if let c2 = char2 {
            let duoHeader = "2 characters, duo, interacting, \(wizPose2.isEmpty ? "standing together" : wizPose2), \(framingTags)"
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
        showToast("Built 3 prompt variants")
    }

    private func buildSingleCharacterTags(
        subjectKey: String,
        anatomyKey: String,
        outfitText: String,
        poseText: String,
        catalog: CatalogBundle
    ) -> (base: String, anime: String, furry: String, neg: String) {
        let bank = catalog.character_banks[subjectKey]
        var baseStr = bank?.base ?? subjectKey
        var animeStr = bank?.anime ?? subjectKey
        var furryStr = bank?.furry ?? subjectKey

        let customOutfitSelected = !outfitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if customOutfitSelected {
            // Strip default clothing phrases from character preset when user explicitly selects an outfit/bare state
            let clothWords = ["crop top", "shorts", "stockings", "dress", "uniform", "armor", "jacket", "shirt", "skirt", "pants", "boots", "gloves", "choker", "collar", "bikini", "suit", "robe", "cloak", "hoodie", "jeans", "leotard", "bodysuit", "tunic", "vest"]
            for w in clothWords {
                baseStr = baseStr.replacingOccurrences(of: w, with: "", options: .caseInsensitive)
                animeStr = animeStr.replacingOccurrences(of: w, with: "", options: .caseInsensitive)
                furryStr = furryStr.replacingOccurrences(of: w, with: "", options: .caseInsensitive)
            }
        }

        let anatPos = catalog.anatomy_pos[anatomyKey] ?? ""
        var anatNeg = catalog.anatomy_neg[anatomyKey] ?? ""

        // If non-clothed anatomy or bare outfit is chosen, block unwanted clothing in negative prompt
        let isBare = outfitText.lowercased().contains("nude") || outfitText.lowercased().contains("unclothed") || (anatomyKey != "female" && !customOutfitSelected)
        if isBare {
            anatNeg += ", clothes, clothing, dressed, underwear, panties, bra, bikini, swimsuit, Lingering clothing, covered, bottomwear, shorts, pants, skirt, dress, censorship, mosaic censoring, bar censor"
        }

        let outfitPart = customOutfitSelected ? outfitText : (anatomyKey != "female" ? "completely unclothed, bare body" : "")
        let posePart = poseText

        let assemble: (String) -> String = { core in
            [anatPos, core, outfitPart, posePart]
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
            throw NSError(domain: "QwenStudio", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Home PC URL. Check the Link tab."])
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

    // MARK: - 2. Standalone AI Horde Cluster Engine (Works 24/7 Anywhere Without PC)
    private func generateViaStandaloneHorde(prompt: String, negative: String, seed: Int) async throws {
        // Strip ||DUO_SPLIT|| marker if user generated a Duo prompt on Cluster
        let cleanedPrompt = prompt.replacingOccurrences(of: "||DUO_SPLIT||", with: ", ")
        let hordeCombinedPrompt = "\(cleanedPrompt) ### \(negative)"

        // First try requested resolution (rounded to multiple of 64); if anonymous key hits kudos limit, auto-adjust to 576x832 / 768x768
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
            // Automatic fallback to zero-kudos anonymous-safe SDXL dimensions so free key never fails
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
        showToast("Saved to iPhone Vault!")
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

    // MARK: - 3. Instant Cloud Flux Engine (with Automatic Cluster Fallback)
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
                showToast("Saved to iPhone Vault!")
                return
            }
        }
        // Fallback seamlessly to Standalone AI Cluster
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

    // MARK: - Local iPhone Vault Persistence
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
        let filename = "qwen_\(ts)_\(seed).png"
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
}
