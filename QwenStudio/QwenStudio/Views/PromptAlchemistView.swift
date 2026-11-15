import SwiftUI

struct PromptAlchemistView: View {
    @EnvironmentObject var store: StudioStore
    @State private var showDuoSection: Bool = false

    private var catalog: CatalogBundle { StudioCatalog.shared }

    private var validSubjects: [SelectOption] {
        catalog.subjects.filter { $0.id != "none" && !$0.id.isEmpty }
    }

    private var subjectGroups: [String] {
        var seen = Set<String>()
        var result: [String] = ["All"]
        for s in validSubjects {
            if !seen.contains(s.group) {
                seen.insert(s.group)
                result.append(s.group)
            }
        }
        return result
    }

    private var filteredSubjects: [SelectOption] {
        validSubjects.filter { opt in
            let matchesGroup = (store.wizCategoryFilter == "All" || opt.group == store.wizCategoryFilter)
            let q = store.wizSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = q.isEmpty || opt.label.lowercased().contains(q) || opt.id.lowercased().contains(q) || opt.group.lowercased().contains(q)
            return matchesGroup && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    character1Card
                    anatomyAndOutfitCard
                    duoCharacterCard
                    sceneAndLightingCard
                    buildActionCard
                    variantsListSection
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 40)
            }
            .background(StudioTheme.bgDeep.ignoresSafeArea())
            .navigationTitle("Prompt Alchemist")
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
                            await store.buildPromptsFromAlchemist()
                            if let first = store.generatedVariants.first {
                                store.applyVariant(first, generateImmediately: true)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                            Text("Render")
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
        }
    }

    private var character1Card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("CHARACTER 1 PRESET (\(validSubjects.count) CHARACTERS)", systemImage: "person.fill.viewfinder")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundColor(StudioTheme.crimson)
                Spacer()
            }

            // Currently Selected Character Banner
            if let selectedObj = catalog.subjects.first(where: { $0.id == store.wizSubject }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected Character:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(StudioTheme.textSecondary)
                        Text(selectedObj.label)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(StudioTheme.cyanGlow)
                    }
                    Spacer()
                    Menu {
                        ForEach(validSubjects) { s in
                            Button(s.label) {
                                store.wizSubject = s.id
                                store.buildPromptsOfflineSync()
                            }
                        }
                    } label: {
                        Label("List", systemImage: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(StudioTheme.bgElevated)
                            .clipShape(Capsule())
                    }
                }
                .padding(10)
                .background(StudioTheme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(StudioTheme.textSecondary)
                TextField("Search Loona, Renamon, Gardevoir, Rouge, Ranni...", text: $store.wizSearchQuery)
                    .font(.system(size: 13))
                    .foregroundColor(StudioTheme.textPrimary)
                if !store.wizSearchQuery.isEmpty {
                    Button {
                        store.wizSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(StudioTheme.textSecondary)
                    }
                }
            }
            .padding(9)
            .background(StudioTheme.bgDeep)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Category Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(subjectGroups, id: \.self) { grp in
                        let sel = (store.wizCategoryFilter == grp)
                        Button {
                            store.wizCategoryFilter = grp
                        } label: {
                            Text(grp)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(sel ? .white : StudioTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(sel ? AnyShapeStyle(StudioTheme.accentGradient) : AnyShapeStyle(StudioTheme.bgElevated))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Scrollable Character Grid
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(44)), GridItem(.fixed(44)), GridItem(.fixed(44))], spacing: 8) {
                    ForEach(filteredSubjects) { subj in
                        let isSelected = (store.wizSubject == subj.id)
                        Button {
                            store.wizSubject = subj.id
                            store.buildPromptsOfflineSync()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(subj.label)
                                    .font(.system(size: 12, weight: .bold))
                                    .lineLimit(1)
                                Text(subj.group)
                                    .font(.system(size: 9, weight: .medium))
                                    .opacity(0.75)
                                    .lineLimit(1)
                            }
                            .foregroundColor(isSelected ? .white : StudioTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(isSelected ? AnyShapeStyle(StudioTheme.accentGradient) : AnyShapeStyle(StudioTheme.bgElevated))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 152)
        }
        .studioCard()
    }

    private var anatomyAndOutfitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHARACTER 1 ANATOMY, SHAPE & OUTFIT")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(StudioTheme.textSecondary)

            selectorRow(
                title: "Anatomy & Shape",
                currentLabel: catalog.anatomies.first(where: { $0.id == store.wizAnatomy })?.label ?? store.wizAnatomy,
                accent: StudioTheme.crimson,
                options: catalog.anatomies
            ) { chosen in
                store.wizAnatomy = chosen.id
                store.buildPromptsOfflineSync()
            }

            Divider().background(StudioTheme.borderSubtle)

            selectorRow(
                title: "Outfit / Attire",
                currentLabel: catalog.outfits.first(where: { $0.id == store.wizOutfit })?.label ?? "Character Default",
                accent: StudioTheme.cyanGlow,
                options: catalog.outfits
            ) { chosen in
                store.wizOutfit = chosen.id
                store.buildPromptsOfflineSync()
            }

            Divider().background(StudioTheme.borderSubtle)

            selectorRow(
                title: "Pose & Framing",
                currentLabel: catalog.poses.first(where: { $0.id == store.wizPose })?.label ?? "Standing Full-Body",
                accent: StudioTheme.neonViolet,
                options: catalog.poses
            ) { chosen in
                store.wizPose = chosen.id
                store.buildPromptsOfflineSync()
            }
        }
        .studioCard()
    }

    private var duoCharacterCard: some View {
        let hasDuo = (store.wizSubject2 != "none" && !store.wizSubject2.isEmpty)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showDuoSection.toggle()
                }
            } label: {
                HStack {
                    Label("2ND CHARACTER (DUO SCENE & POSE)", systemImage: "person.2.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.8)
                        .foregroundColor(StudioTheme.neonViolet)
                    Spacer()
                    Text(hasDuo ? "Duo Active" : "Solo (Tap to Add 2nd)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(hasDuo ? StudioTheme.emerald : StudioTheme.textSecondary)
                    Image(systemName: (showDuoSection || hasDuo) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(StudioTheme.textSecondary)
                }
            }

            if showDuoSection || hasDuo {
                Divider().background(StudioTheme.borderSubtle)

                selectorRow(
                    title: "2nd Character",
                    currentLabel: catalog.subjects.first(where: { $0.id == store.wizSubject2 })?.label ?? "None (Solo — 1 Character)",
                    accent: StudioTheme.crimson,
                    options: catalog.subjects
                ) { chosen in
                    store.wizSubject2 = chosen.id
                    store.buildPromptsOfflineSync()
                }

                if hasDuo {
                    let char2AnatOptions = [SelectOption(id: "same_as_1", label: "Same Anatomy as Character 1", group: "Standard")] + catalog.anatomies
                    selectorRow(
                        title: "Char 2 Anatomy",
                        currentLabel: char2AnatOptions.first(where: { $0.id == store.wizAnatomy2 })?.label ?? "Same as Character 1",
                        accent: StudioTheme.crimson,
                        options: char2AnatOptions
                    ) { chosen in
                        store.wizAnatomy2 = chosen.id
                        store.buildPromptsOfflineSync()
                    }

                    let char2OutfitOptions = [
                        SelectOption(id: "same", label: "Same Outfit as Character 1", group: "Standard"),
                        SelectOption(id: "default", label: "Character 2's Canonical Outfit", group: "Standard")
                    ] + catalog.outfits
                    selectorRow(
                        title: "Char 2 Outfit",
                        currentLabel: char2OutfitOptions.first(where: { $0.id == store.wizOutfit2 })?.label ?? "Same as Character 1",
                        accent: StudioTheme.cyanGlow,
                        options: char2OutfitOptions
                    ) { chosen in
                        store.wizOutfit2 = chosen.id
                        store.buildPromptsOfflineSync()
                    }

                    selectorRow(
                        title: "Duo Pose / Interaction",
                        currentLabel: catalog.duo_poses.first(where: { $0.id == store.wizPose2 })?.label ?? "Side-by-Side",
                        accent: StudioTheme.neonViolet,
                        options: catalog.duo_poses
                    ) { chosen in
                        store.wizPose2 = chosen.id
                        store.buildPromptsOfflineSync()
                    }
                }
            }
        }
        .studioCard(borderColor: hasDuo ? StudioTheme.neonViolet.opacity(0.6) : StudioTheme.borderSubtle)
    }

    private var sceneAndLightingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SETTING, LIGHTING & EXTRA DETAILS")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(StudioTheme.textSecondary)

            selectorRow(
                title: "Setting / Background",
                currentLabel: catalog.settings.first(where: { $0.id == store.wizSetting })?.label ?? "Default Setting",
                accent: StudioTheme.cyanGlow,
                options: catalog.settings
            ) { chosen in
                store.wizSetting = chosen.id
                store.buildPromptsOfflineSync()
            }

            Divider().background(StudioTheme.borderSubtle)

            selectorRow(
                title: "Lighting & Atmosphere",
                currentLabel: catalog.lightings.first(where: { $0.id == store.wizLighting })?.label ?? "Default Lighting",
                accent: StudioTheme.amber,
                options: catalog.lightings
            ) { chosen in
                store.wizLighting = chosen.id
                store.buildPromptsOfflineSync()
            }

            Divider().background(StudioTheme.borderSubtle)

            TextField("Optional custom action / scene idea...", text: $store.wizIdea)
                .font(.system(size: 13))
                .foregroundColor(StudioTheme.textPrimary)
                .padding(9)
                .background(StudioTheme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: store.wizIdea) { _ in
                    store.buildPromptsOfflineSync()
                }
        }
        .studioCard()
    }

    private func selectorRow(
        title: String,
        currentLabel: String,
        accent: Color,
        options: [SelectOption],
        onSelect: @escaping (SelectOption) -> Void
    ) -> some View {
        Menu {
            ForEach(options) { opt in
                Button(opt.label) {
                    onSelect(opt)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(StudioTheme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(accent)
                }
                Text(currentLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accent)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(StudioTheme.bgDeep)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var buildActionCard: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await store.buildPromptsFromAlchemist()
                }
            } label: {
                Label("Refresh 3 Variants", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(StudioTheme.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(StudioTheme.crimson, lineWidth: 1.5)
                    )
            }

            Button {
                Task {
                    await store.buildPromptsFromAlchemist()
                    if let first = store.generatedVariants.first {
                        store.applyVariant(first, generateImmediately: true)
                    }
                }
            } label: {
                Label("Build & Render Now", systemImage: "bolt.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(StudioTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var variantsListSection: some View {
        VStack(spacing: 12) {
            ForEach(store.generatedVariants) { card in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(card.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(StudioTheme.textPrimary)
                        Spacer()
                        Text(card.recommended_for)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(StudioTheme.cyanGlow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(StudioTheme.cyanGlow.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    Text(card.prompt)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(StudioTheme.textSecondary)
                        .lineLimit(4)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StudioTheme.bgDeep)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 10) {
                        Button {
                            store.applyVariant(card, generateImmediately: false)
                        } label: {
                            Label("Send to Studio", systemImage: "arrow.up.right.square")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(StudioTheme.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            store.applyVariant(card, generateImmediately: true)
                        } label: {
                            Label("Generate Image", systemImage: "wand.and.stars")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(StudioTheme.accentGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .studioCard(borderColor: StudioTheme.neonViolet.opacity(0.4))
            }
        }
    }
}
