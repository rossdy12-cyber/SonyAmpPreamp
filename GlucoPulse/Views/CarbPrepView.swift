import SwiftUI
import UIKit
import AVFoundation

struct CarbPrepView: View {
    @EnvironmentObject private var store: GlucoStore
    @EnvironmentObject private var carbStore: CarbPrepStore

    @State private var activeSection: Int = 0 // 0 = UK Food & Plate, 1 = Batch Meal Prep, 2 = Add Custom
    @State private var showScannerSheet: Bool = false
    @State private var manualBarcodeText: String = ""

    // Custom Food Form
    @State private var customName: String = ""
    @State private var customBrand: String = "Homemade / UK"
    @State private var customCarbs100: String = ""
    @State private var customFibre100: String = "0"
    @State private var customProtein100: String = "0"
    @State private var customFat100: String = "0"
    @State private var customKcal100: String = "0"
    @State private var customPortionGrams: String = "100"

    var body: some View {
        NavigationStack {
            ZStack {
                GlucoTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Mode", selection: $activeSection) {
                        Text("UK Food & Plate").tag(0)
                        Text("Batch Meal Prep").tag(1)
                        Text("Custom Food").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    ScrollView {
                        VStack(spacing: 16) {
                            if activeSection == 0 {
                                plateSummaryCard
                                searchAndBarcodeCard
                                foodResultsList
                            } else if activeSection == 1 {
                                batchPrepBuilderCard
                                savedBatchesCard
                            } else {
                                customFoodCreatorCard
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 28)
                    }
                }
            }
            .navigationTitle("UK Carbs & Meal Prep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScannerSheet = true
                    } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                            .foregroundStyle(GlucoTheme.inRangeGreen)
                    }
                }
            }
            .sheet(isPresented: $showScannerSheet) {
                BarcodeScannerSheet { code in
                    showScannerSheet = false
                    Task {
                        if let item = await carbStore.lookupBarcode(code) {
                            carbStore.addToPlate(item)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 1. Current Meal Plate Card

    private var plateSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "fork.knife.circle.fill")
                        .foregroundStyle(GlucoTheme.inRangeGreen)
                    Text("CURRENT MEAL PLATE (\(carbStore.plateItems.count) ITEMS)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(GlucoTheme.textSecondary)
                }
                Spacer()
                if !carbStore.plateItems.isEmpty {
                    Button("Clear") {
                        carbStore.plateItems.removeAll()
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GlucoTheme.lowRed)
                }
            }

            HStack(spacing: 10) {
                macroPill(label: "Total Carbs", value: "\(carbStore.plateTotalCarbs)g", color: GlucoTheme.inRangeGreen)
                macroPill(label: "Net Carbs", value: "\(carbStore.plateTotalNetCarbs)g", color: GlucoTheme.tandemCyan)
                macroPill(label: "Protein", value: "\(carbStore.plateTotalProtein)g", color: GlucoTheme.textPrimary)
                macroPill(label: "Fat", value: "\(carbStore.plateTotalFat)g", color: GlucoTheme.highAmber)
                macroPill(label: "Energy", value: "\(carbStore.plateTotalKcal)", color: GlucoTheme.controlIQPurple)
            }

            ForEach(carbStore.plateItems) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.food.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(GlucoTheme.textPrimary)
                            Text("\(Int(entry.weightGrams))g · \(String(format: "%.1fg", entry.carbsGrams)) carbs · \(String(format: "%.1fg", entry.fatGrams)) fat · \(String(format: "%.1fg", entry.proteinGrams)) prot")
                                .font(.system(size: 11))
                                .foregroundStyle(GlucoTheme.textSecondary)
                        }
                        Spacer()
                        Text("\(Int(entry.carbsGrams.rounded()))g")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(GlucoTheme.inRangeGreen)
                    }

                    HStack(spacing: 6) {
                        ForEach([-50.0, -10.0, 10.0, 50.0], id: \.self) { delta in
                            Button(delta > 0 ? "+\(Int(delta))g" : "\(Int(delta))g") {
                                carbStore.adjustPlateWeight(id: entry.id, delta: delta)
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(GlucoTheme.background, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(delta > 0 ? GlucoTheme.inRangeGreen : GlucoTheme.highAmber)
                        }
                        Spacer()
                        Button {
                            carbStore.plateItems.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(GlucoTheme.lowRed)
                        }
                    }
                }
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
            }

            if carbStore.plateTotalCarbs > 0 {
                Button {
                    let summary = carbStore.plateItems.map { "\($0.food.name) (\(Int($0.weightGrams))g)" }.joined(separator: " + ")
                    store.sendMealToBolusCalculator(
                        carbsGrams: carbStore.plateTotalCarbs,
                        fatGrams: carbStore.plateTotalFat,
                        proteinGrams: carbStore.plateTotalProtein,
                        note: summary
                    )
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Send \(carbStore.plateTotalCarbs)g Carbs (+ FPU) to Smart Bolus Calculator")
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(GlucoTheme.inRangeGreen, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
                }
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private func macroPill(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(GlucoTheme.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 2. Search & Barcode Lookup Card

    private var searchAndBarcodeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GlucoTheme.textSecondary)
                TextField("Search UK foods (Greggs, Tesco, Basmati, Heinz...)", text: $carbStore.searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(GlucoTheme.textPrimary)
                    .onSubmit {
                        Task { await carbStore.searchOpenFoodFactsUK() }
                    }
                if !carbStore.searchQuery.isEmpty {
                    Button {
                        carbStore.searchQuery = ""
                        carbStore.remoteResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(GlucoTheme.textSecondary)
                    }
                }
            }
            .padding(11)
            .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                Button {
                    Task { await carbStore.searchOpenFoodFactsUK() }
                } label: {
                    HStack(spacing: 6) {
                        if carbStore.isSearchingOnline {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "globe.europe.africa.fill")
                        }
                        Text("Search OpenFoodFacts UK")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(GlucoTheme.tandemCyan, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.black)
                }

                Button {
                    showScannerSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.viewfinder")
                        Text("Scan Barcode")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(GlucoTheme.inRangeGreen)
                }
            }

            if !carbStore.barcodeStatusMessage.isEmpty {
                Text(carbStore.barcodeStatusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GlucoTheme.tandemCyan)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(carbStore.categories, id: \.self) { cat in
                        Button(cat) {
                            carbStore.selectedCategory = cat
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(carbStore.selectedCategory == cat ? GlucoTheme.inRangeGreen : GlucoTheme.cardElevated, in: Capsule())
                        .foregroundStyle(carbStore.selectedCategory == cat ? .black : GlucoTheme.textSecondary)
                    }
                }
            }
        }
        .padding(14)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private var foodResultsList: some View {
        VStack(spacing: 10) {
            ForEach(carbStore.filteredFoods) { item in
                let defaultCarbs = (item.carbsPer100g * item.defaultPortionGrams) / 100.0
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(GlucoTheme.textPrimary)
                        Text("\(item.brand) · \(String(format: "%.1fg", item.carbsPer100g)) carbs/100g · \(item.portionLabel)")
                            .font(.system(size: 11))
                            .foregroundStyle(GlucoTheme.textSecondary)
                    }
                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text("\(Int(defaultCarbs.rounded()))g")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(GlucoTheme.inRangeGreen)

                        HStack(spacing: 6) {
                            Button("+Plate") {
                                carbStore.addToPlate(item)
                            }
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(GlucoTheme.inRangeGreen.opacity(0.22), in: Capsule())
                            .foregroundStyle(GlucoTheme.inRangeGreen)

                            Button("+Batch") {
                                carbStore.addToBatch(item)
                                activeSection = 1
                            }
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(GlucoTheme.controlIQPurple.opacity(0.22), in: Capsule())
                            .foregroundStyle(GlucoTheme.controlIQPurple)
                        }
                    }
                }
                .padding(13)
                .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(GlucoTheme.border, lineWidth: 1))
            }
        }
    }

    // MARK: - 3. Batch Meal Prep Tub Divider

    private var batchPrepBuilderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                    .foregroundStyle(GlucoTheme.controlIQPurple)
                Text("BATCH MEAL-PREP TUB CALCULATOR")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(GlucoTheme.controlIQPurple)
                Spacer()
                if !carbStore.batchIngredients.isEmpty {
                    Button("Clear Pot") {
                        carbStore.batchIngredients.removeAll()
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GlucoTheme.lowRed)
                }
            }

            TextField("Recipe Name (e.g. Chilli Con Carne 4 Tubs)", text: $carbStore.batchTitle)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(GlucoTheme.textPrimary)
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Number of Tubs / Portions")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    Stepper(value: $carbStore.batchPortionCount, in: 1...20) {
                        Text("\(carbStore.batchPortionCount) tubs")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(GlucoTheme.tandemCyan)
                    }
                }
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Cooked Weight (g)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    TextField("1400", value: $carbStore.batchCookedWeightGrams, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(GlucoTheme.inRangeGreen)
                }
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 10) {
                macroPill(label: "Per Tub Carbs", value: String(format: "%.1fg", carbStore.batchCarbsPerTub), color: GlucoTheme.inRangeGreen)
                macroPill(label: "Per 100g Cooked", value: String(format: "%.1fg", carbStore.batchCarbsPer100gCooked), color: GlucoTheme.tandemCyan)
                macroPill(label: "Total Pot Carbs", value: "\(Int(carbStore.batchTotalCarbs.rounded()))g", color: GlucoTheme.controlIQPurple)
            }

            ForEach(carbStore.batchIngredients) { ing in
                HStack {
                    Text("\(ing.food.name) (\(Int(ing.weightGrams))g)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                    Spacer()
                    Text("\(String(format: "%.1fg", ing.carbsGrams)) carbs")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(GlucoTheme.inRangeGreen)
                    Button {
                        carbStore.batchIngredients.removeAll { $0.id == ing.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(GlucoTheme.lowRed)
                    }
                }
                .padding(9)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 10) {
                Button {
                    carbStore.saveCurrentBatchRecipe()
                } label: {
                    Label("Save Batch Recipe", systemImage: "bookmark.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(GlucoTheme.controlIQPurple, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }

                Button {
                    let portions = Double(max(1, carbStore.batchPortionCount))
                    store.sendMealToBolusCalculator(
                        carbsGrams: Int(carbStore.batchCarbsPerTub.rounded()),
                        fatGrams: Int((carbStore.batchTotalFat / portions).rounded()),
                        proteinGrams: Int((carbStore.batchTotalProtein / portions).rounded()),
                        note: "\(carbStore.batchTitle) (1/\(carbStore.batchPortionCount) tub)"
                    )
                } label: {
                    Label("Bolus 1 Tub (\(Int(carbStore.batchCarbsPerTub.rounded()))g)", systemImage: "bolt.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(GlucoTheme.inRangeGreen, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private var savedBatchesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved Meal-Prep Batches")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(GlucoTheme.textPrimary)

            if carbStore.savedBatches.isEmpty {
                Text("No saved batch recipes yet — add raw ingredients from the UK Food tab (+Batch) and tap Save Batch Recipe.")
                    .font(.system(size: 12))
                    .foregroundStyle(GlucoTheme.textSecondary)
            } else {
                ForEach(carbStore.savedBatches) { b in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(b.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(GlucoTheme.textPrimary)
                            Text("\(b.portionCount) tubs · \(String(format: "%.1fg", b.carbsPerPortion)) carbs/tub · \(String(format: "%.1fg", b.carbsPer100gCooked))/100g cooked")
                                .font(.system(size: 11))
                                .foregroundStyle(GlucoTheme.textSecondary)
                        }
                        Spacer()
                        Button("Bolus 1 Tub") {
                            store.sendMealToBolusCalculator(
                                carbsGrams: Int(b.carbsPerPortion.rounded()),
                                fatGrams: Int((b.totalFatGrams / Double(max(1, b.portionCount))).rounded()),
                                proteinGrams: Int((b.totalProteinGrams / Double(max(1, b.portionCount))).rounded()),
                                note: "\(b.title) (1 tub)"
                            )
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(GlucoTheme.tandemCyan, in: Capsule())
                        .foregroundStyle(.black)
                    }
                    .padding(12)
                    .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    // MARK: - 4. Custom Food Creator Card

    private var customFoodCreatorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Custom UK Food / Packaging Label")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GlucoTheme.textPrimary)

            TextField("Food Name (e.g. M&S Count On Us Lasagne)", text: $customName)
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(GlucoTheme.textPrimary)

            HStack(spacing: 10) {
                TextField("Carbs per 100g", text: $customCarbs100)
                    .keyboardType(.decimalPad)
                    .padding(10)
                    .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(GlucoTheme.inRangeGreen)

                TextField("Default Portion (g)", text: $customPortionGrams)
                    .keyboardType(.decimalPad)
                    .padding(10)
                    .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(GlucoTheme.textPrimary)
            }

            HStack(spacing: 10) {
                TextField("Fat / 100g", text: $customFat100)
                    .keyboardType(.decimalPad)
                    .padding(10)
                    .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(GlucoTheme.textPrimary)

                TextField("Protein / 100g", text: $customProtein100)
                    .keyboardType(.decimalPad)
                    .padding(10)
                    .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(GlucoTheme.textPrimary)
            }

            Button {
                let c = Double(customCarbs100) ?? 0
                let p = Double(customPortionGrams) ?? 100
                guard !customName.isEmpty, c >= 0 else { return }
                let item = UKFoodItem(
                    name: customName,
                    brand: customBrand,
                    category: "Custom",
                    carbsPer100g: c,
                    fibrePer100g: Double(customFibre100) ?? 0,
                    proteinPer100g: Double(customProtein100) ?? 0,
                    fatPer100g: Double(customFat100) ?? 0,
                    kcalPer100g: Double(customKcal100) ?? (c * 4.0),
                    defaultPortionGrams: p,
                    portionLabel: "\(Int(p))g portion"
                )
                carbStore.customFoods.insert(item, at: 0)
                carbStore.addToPlate(item)
                customName = ""
                customCarbs100 = ""
                activeSection = 0
            } label: {
                Text("Save Custom Food & Add to Plate")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(GlucoTheme.inRangeGreen, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }
}

// MARK: - Live AVFoundation Camera Barcode Scanner Sheet

struct BarcodeScannerSheet: View {
    var onFound: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manualCode: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                GlucoTheme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    BarcodeScannerRepresentable(onCodeFound: onFound)
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(GlucoTheme.inRangeGreen, lineWidth: 2)
                        )
                        .padding(.horizontal, 16)

                    Text("Align UK supermarket EAN-13 / EAN-8 barcode inside frame")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(GlucoTheme.textSecondary)

                    HStack(spacing: 10) {
                        TextField("Or type barcode digits manually...", text: $manualCode)
                            .keyboardType(.numberPad)
                            .padding(11)
                            .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(GlucoTheme.textPrimary)

                        Button("Lookup") {
                            if !manualCode.isEmpty {
                                onFound(manualCode)
                            }
                        }
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(GlucoTheme.inRangeGreen, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 16)

                    Spacer()
                }
                .padding(.top, 12)
            }
            .navigationTitle("Scan UK Food Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    var onCodeFound: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCodeFound = onCodeFound
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}

    final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCodeFound: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var didEmit = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.ean13, .ean8, .upce, .code128]
            }

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.layer.bounds
            view.layer.addSublayer(preview)
            self.previewLayer = preview

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning {
                session.stopRunning()
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !didEmit,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let str = obj.stringValue else { return }
            didEmit = true
            session.stopRunning()
            onCodeFound?(str)
        }
    }
}
