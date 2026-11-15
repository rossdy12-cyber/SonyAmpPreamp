import SwiftUI

struct PromptAlchemistView: View {
    @EnvironmentObject var store: StudioStore
    @State private var showDuoSection: Bool = false

    private var catalog: CatalogBundle { StudioCatalog.shared }

    private var subjectGroups: [String] {
        var seen = Set<String>()
        var result: [String] = ["All"]
        for s in catalog.subjects where !s.id.isEmpty {
            if !seen.contains(s.group) {
                seen.insert(s.group)
                result.append(s.group)
            }
        }
        return result
    }

    private var filteredSubjects: [SelectOption] {
        catalog.subjects.filter { opt in
            guard !opt.id.isEmpty else { return false }
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
                .padding(.bottom, 32)
            }
            .background(StudioTheme.bgDeep.ignoresSafeArea())
            .navigationTitle("Prompt Alchemist")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var character1Card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("CHARACTER 1 PRESET (\(catalog.subjects.count - 1) CHARACTERS)", systemImage: "person.fill.viewfinder")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundColor(StudioTheme.crimson)
                Spacer()
                if let selectedObj = catalog.subjects.first(where: { $0.id == store.wizSubject }) {
                    Text(selectedObj.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(StudioTheme.cyanGlow)
                        .lineLimit(1)
                }
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
                LazyHGrid(rows: [GridItem(.fixed(42)), GridItem(.fixed(42)), GridItem(.fixed(42))], spacing: 8) {
                    ForEach(filteredSubjects) { subj in
                        let isSelected = (store.wizSubject == subj.id)
                        Button {
                            store.wizSubject = subj.id
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
                            .frame(height: 40)
                            .background(isSelected ? AnyShapeStyle(StudioTheme.accentGradient) : AnyShapeStyle(StudioTheme.bgElevated))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 146)
        }
        .studioCard()
    }

    private var anatomyAndOutfitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHARACTER 1 ANATOMY, SHAPE & OUTFIT")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(StudioTheme.textSecondary)

            HStack {
                Text("Anatomy & Shape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(StudioTheme.textPrimary)
                Spacer()
                Picker("Anatomy", selection: $store.wizAnatomy) {
                    ForEach(catalog.anatomies) { anat in
                        Text(anat.label).tag(anat.id)
                    }
                }
                .tint(StudioTheme.crimson)
            }

            Divider().background(StudioTheme.borderSubtle)

            HStack {
                Text("Outfit / Attire")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(StudioTheme.textPrimary)
                Spacer()
                Picker("Outfit", selection: $store.wizOutfit) {
                    ForEach(catalog.outfits) { outf in
                        Text(outf.label).tag(outf.id)
                    }
                }
                .tint(StudioTheme.cyanGlow)
            }

            Divider().background(StudioTheme.borderSubtle)

            HStack {
                Text("Pose & Framing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(StudioTheme.textPrimary)
                Spacer()
                Picker("Pose", selection: $store.wizPose) {
                    ForEach(catalog.poses) { p in
                        Text(p.label).tag(p.id)
                    }
                }
                .tint(StudioTheme.neonViolet)
            }
        }
        .studioCard()
    }

    private var duoCharacterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    Text(store.wizSubject2.isEmpty ? "Solo (Tap to Add 2nd)" : "Duo Active")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(store.wizSubject2.isEmpty ? StudioTheme.textSecondary : StudioTheme.emerald)
                    Image(systemName: showDuoSection ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(StudioTheme.textSecondary)
                }
            }

            if showDuoSection || !store.wizSubject2.isEmpty {
                Divider().background(StudioTheme.borderSubtle)

                HStack {
                    Text("2nd Character")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(StudioTheme.textPrimary)
                    Spacer()
                    Picker("2nd Character", selection: $store.wizSubject2) {
                        Text("None (Solo 1 Character)").tag("")
                        ForEach(catalog.subjects.filter { !$0.id.isEmpty }) { s in
                            Text(s.label).tag(s.id)
                        }
                    }
                    .tint(StudioTheme.crimson)
                }

                if !store.wizSubject2.isEmpty {
                    HStack {
                        Text("Char 2 Anatomy")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(StudioTheme.textPrimary)
                        Spacer()
                        Picker("Char 2 Anatomy", selection: $store.wizAnatomy2) {
                            Text("Same as Character 1").tag("same_as_1")
                            ForEach(catalog.anatomies) { anat in
                                Text(anat.label).tag(anat.id)
                            }
                        }
                        .tint(StudioTheme.crimson)
                    }

                    HStack {
                        Text("Char 2 Outfit")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(StudioTheme.textPrimary)
                        Spacer()
                        Picker("Char 2 Outfit", selection: $store.wizOutfit2) {
                            Text("Same as Character 1").tag("same")
                            Text("Character 2 Default").tag("default")
                            ForEach(catalog.outfits.filter { !$0.id.isEmpty }) { outf in
                                Text(outf.label).tag(outf.id)
                            }
                        }
                        .tint(StudioTheme.cyanGlow)
                    }

                    HStack {
                        Text("Duo Pose / Action")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(StudioTheme.textPrimary)
                        Spacer()
                        Picker("Duo Pose", selection: $store.wizPose2) {
                            ForEach(catalog.duo_poses) { dp in
                                Text(dp.label).tag(dp.id)
                            }
                        }
                        .tint(StudioTheme.neonViolet)
                    }
                }
            }
        }
        .studioCard(borderColor: store.wizSubject2.isEmpty ? StudioTheme.borderSubtle : StudioTheme.neonViolet.opacity(0.6))
    }

    private var sceneAndLightingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SETTING, LIGHTING & EXTRA DETAILS")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .foregroundColor(StudioTheme.textSecondary)

            HStack {
                Text("Setting")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(StudioTheme.textPrimary)
                Spacer()
                Picker("Setting", selection: $store.wizSetting) {
                    ForEach(catalog.settings) { st in
                        Text(st.label).tag(st.id)
                    }
                }
                .tint(StudioTheme.cyanGlow)
            }

            Divider().background(StudioTheme.borderSubtle)

            HStack {
                Text("Lighting")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(StudioTheme.textPrimary)
                Spacer()
                Picker("Lighting", selection: $store.wizLighting) {
                    ForEach(catalog.lightings) { lt in
                        Text(lt.label).tag(lt.id)
                    }
                }
                .tint(StudioTheme.amber)
            }

            Divider().background(StudioTheme.borderSubtle)

            TextField("Optional custom action / scene idea...", text: $store.wizIdea)
                .font(.system(size: 13))
                .foregroundColor(StudioTheme.textPrimary)
                .padding(9)
                .background(StudioTheme.bgDeep)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .studioCard()
    }

    private var buildActionCard: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await store.buildPromptsFromAlchemist()
                }
            } label: {
                Label("Build 3 Prompt Variants", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
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
                    .font(.system(size: 14, weight: .heavy))
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
