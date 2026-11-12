import Foundation
import SwiftUI

struct UKFoodItem: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var brand: String
    var category: String
    var carbsPer100g: Double
    var fibrePer100g: Double
    var proteinPer100g: Double
    var fatPer100g: Double
    var kcalPer100g: Double
    var defaultPortionGrams: Double
    var portionLabel: String
    var barcode: String?

    var netCarbsPer100g: Double {
        max(0, carbsPer100g - fibrePer100g)
    }
}

struct MealPlateEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var food: UKFoodItem
    var weightGrams: Double

    var carbsGrams: Double { (food.carbsPer100g * weightGrams) / 100.0 }
    var netCarbsGrams: Double { (food.netCarbsPer100g * weightGrams) / 100.0 }
    var fibreGrams: Double { (food.fibrePer100g * weightGrams) / 100.0 }
    var proteinGrams: Double { (food.proteinPer100g * weightGrams) / 100.0 }
    var fatGrams: Double { (food.fatPer100g * weightGrams) / 100.0 }
    var kcal: Double { (food.kcalPer100g * weightGrams) / 100.0 }
}

struct SavedBatchRecipe: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date
    var totalCookedWeightGrams: Double
    var portionCount: Int
    var totalCarbsGrams: Double
    var totalProteinGrams: Double
    var totalFatGrams: Double
    var totalKcal: Double

    var carbsPerPortion: Double {
        totalCarbsGrams / Double(max(1, portionCount))
    }

    var carbsPer100gCooked: Double {
        guard totalCookedWeightGrams > 0 else { return 0 }
        return (totalCarbsGrams / totalCookedWeightGrams) * 100.0
    }
}

@MainActor
final class CarbPrepStore: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var selectedCategory: String = "All"
    @Published var remoteResults: [UKFoodItem] = []
    @Published var isSearchingOnline: Bool = false
    @Published var barcodeStatusMessage: String = ""

    // Current Meal Plate
    @Published var plateItems: [MealPlateEntry] = [] {
        didSet { saveCodable(plateItems, key: "carbprep.plate") }
    }

    // Batch Meal Prep Builder
    @Published var batchTitle: String = "Chilli Con Carne Meal Prep"
    @Published var batchIngredients: [MealPlateEntry] = [] {
        didSet { saveCodable(batchIngredients, key: "carbprep.batchIngredients") }
    }
    @Published var batchCookedWeightGrams: Double = 1400 {
        didSet { UserDefaults.standard.set(batchCookedWeightGrams, forKey: "carbprep.batchCookedWt") }
    }
    @Published var batchPortionCount: Int = 4 {
        didSet { UserDefaults.standard.set(batchPortionCount, forKey: "carbprep.batchPortions") }
    }
    @Published var savedBatches: [SavedBatchRecipe] = [] {
        didSet { saveCodable(savedBatches, key: "carbprep.savedBatches") }
    }

    @Published var customFoods: [UKFoodItem] = [] {
        didSet { saveCodable(customFoods, key: "carbprep.customFoods") }
    }

    let categories = ["All", "UK Staples", "Supermarket", "UK Takeaway", "Hypo Rescue", "Custom"]

    init() {
        let d = UserDefaults.standard
        if let pData = d.data(forKey: "carbprep.plate"),
           let p = try? JSONDecoder().decode([MealPlateEntry].self, from: pData) {
            self.plateItems = p
        }
        if let bData = d.data(forKey: "carbprep.batchIngredients"),
           let b = try? JSONDecoder().decode([MealPlateEntry].self, from: bData) {
            self.batchIngredients = b
        }
        let cw = d.double(forKey: "carbprep.batchCookedWt")
        if cw > 0 { self.batchCookedWeightGrams = cw }
        let pc = d.integer(forKey: "carbprep.batchPortions")
        if pc > 0 { self.batchPortionCount = pc }

        if let sData = d.data(forKey: "carbprep.savedBatches"),
           let s = try? JSONDecoder().decode([SavedBatchRecipe].self, from: sData) {
            self.savedBatches = s
        }
        if let cData = d.data(forKey: "carbprep.customFoods"),
           let c = try? JSONDecoder().decode([UKFoodItem].self, from: cData) {
            self.customFoods = c
        }
    }

    private func saveCodable<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Plate & Batch Totals

    var plateTotalCarbs: Int { Int(plateItems.reduce(0.0) { $0 + $1.carbsGrams }.rounded()) }
    var plateTotalNetCarbs: Int { Int(plateItems.reduce(0.0) { $0 + $1.netCarbsGrams }.rounded()) }
    var plateTotalProtein: Int { Int(plateItems.reduce(0.0) { $0 + $1.proteinGrams }.rounded()) }
    var plateTotalFat: Int { Int(plateItems.reduce(0.0) { $0 + $1.fatGrams }.rounded()) }
    var plateTotalKcal: Int { Int(plateItems.reduce(0.0) { $0 + $1.kcal }.rounded()) }

    var batchTotalCarbs: Double { batchIngredients.reduce(0.0) { $0 + $1.carbsGrams } }
    var batchTotalProtein: Double { batchIngredients.reduce(0.0) { $0 + $1.proteinGrams } }
    var batchTotalFat: Double { batchIngredients.reduce(0.0) { $0 + $1.fatGrams } }
    var batchTotalKcal: Double { batchIngredients.reduce(0.0) { $0 + $1.kcal } }

    var batchCarbsPerTub: Double {
        batchTotalCarbs / Double(max(1, batchPortionCount))
    }

    var batchCarbsPer100gCooked: Double {
        guard batchCookedWeightGrams > 0 else { return 0 }
        return (batchTotalCarbs / batchCookedWeightGrams) * 100.0
    }

    func addToPlate(_ food: UKFoodItem, grams: Double? = nil) {
        let w = grams ?? food.defaultPortionGrams
        if let idx = plateItems.firstIndex(where: { $0.food.id == food.id }) {
            plateItems[idx].weightGrams += w
        } else {
            plateItems.append(MealPlateEntry(food: food, weightGrams: w))
        }
    }

    func adjustPlateWeight(id: UUID, delta: Double) {
        guard let idx = plateItems.firstIndex(where: { $0.id == id }) else { return }
        let updated = plateItems[idx].weightGrams + delta
        if updated <= 0 {
            plateItems.remove(at: idx)
        } else {
            plateItems[idx].weightGrams = updated
        }
    }

    func addToBatch(_ food: UKFoodItem, grams: Double? = nil) {
        let w = grams ?? food.defaultPortionGrams
        batchIngredients.append(MealPlateEntry(food: food, weightGrams: w))
    }

    func saveCurrentBatchRecipe() {
        guard !batchIngredients.isEmpty else { return }
        let saved = SavedBatchRecipe(
            title: batchTitle.isEmpty ? "Meal Prep Batch" : batchTitle,
            createdAt: Date(),
            totalCookedWeightGrams: batchCookedWeightGrams,
            portionCount: max(1, batchPortionCount),
            totalCarbsGrams: batchTotalCarbs,
            totalProteinGrams: batchTotalProtein,
            totalFatGrams: batchTotalFat,
            totalKcal: batchTotalKcal
        )
        savedBatches.insert(saved, at: 0)
    }

    // MARK: - Filtered Offline + Online Food List

    var allOfflineFoods: [UKFoodItem] {
        customFoods + Self.ukBuiltInFoods
    }

    var filteredFoods: [UKFoodItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = allOfflineFoods.filter { item in
            if selectedCategory != "All" && item.category != selectedCategory {
                return false
            }
            if q.isEmpty { return true }
            return item.name.lowercased().contains(q)
                || item.brand.lowercased().contains(q)
                || (item.barcode?.contains(q) ?? false)
        }
        return base + remoteResults
    }

    // MARK: - OpenFoodFacts UK Live Search & Barcode Scanner Lookup

    func searchOpenFoodFactsUK() async {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        isSearchingOnline = true
        defer { isSearchingOnline = false }

        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let urlStr = "https://uk.openfoodfacts.org/cgi/search.pl?search_terms=\(encoded)&search_simple=1&action=process&json=1&page_size=20"
        guard let url = URL(string: urlStr) else { return }

        do {
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue("GlucoPulseT1D/2.0 (iOS; UK)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let products = root["products"] as? [[String: Any]] else { return }

            var results: [UKFoodItem] = []
            for p in products {
                guard let name = (p["product_name_en"] as? String) ?? (p["product_name"] as? String),
                      !name.trimmingCharacters(in: .whitespaces).isEmpty,
                      let nutriments = p["nutriments"] as? [String: Any] else { continue }

                let carbs = Self.num(nutriments["carbohydrates_100g"])
                let fibre = Self.num(nutriments["fiber_100g"])
                let protein = Self.num(nutriments["proteins_100g"])
                let fat = Self.num(nutriments["fat_100g"])
                let kcal = Self.num(nutriments["energy-kcal_100g"])
                let brand = (p["brands"] as? String) ?? "OpenFoodFacts UK"
                let code = p["code"] as? String

                if carbs > 0 || protein > 0 || fat > 0 {
                    results.append(UKFoodItem(
                        id: code ?? UUID().uuidString,
                        name: name,
                        brand: brand,
                        category: "Supermarket",
                        carbsPer100g: carbs,
                        fibrePer100g: fibre,
                        proteinPer100g: protein,
                        fatPer100g: fat,
                        kcalPer100g: kcal,
                        defaultPortionGrams: 100,
                        portionLabel: "100g",
                        barcode: code
                    ))
                }
            }
            remoteResults = results
        } catch {}
    }

    func lookupBarcode(_ rawCode: String) async -> UKFoodItem? {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }

        // Check offline UK database first
        if let local = allOfflineFoods.first(where: { $0.barcode == code }) {
            barcodeStatusMessage = "Found in UK database: \(local.name) (\(String(format: "%.1f", local.carbsPer100g))g carbs/100g)"
            return local
        }

        barcodeStatusMessage = "Looking up barcode \(code) on OpenFoodFacts UK..."
        guard let url = URL(string: "https://uk.openfoodfacts.org/api/v2/product/\(code).json") else {
            barcodeStatusMessage = "Invalid barcode URL."
            return nil
        }

        do {
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue("GlucoPulseT1D/2.0 (iOS; UK)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let product = root["product"] as? [String: Any] else {
                barcodeStatusMessage = "Barcode \(code) not found in OpenFoodFacts."
                return nil
            }

            let name = (product["product_name_en"] as? String)
                ?? (product["product_name"] as? String)
                ?? "Scanned Product (\(code))"
            let brand = (product["brands"] as? String) ?? "UK Barcode"
            let nutriments = (product["nutriments"] as? [String: Any]) ?? [:]
            let carbs = Self.num(nutriments["carbohydrates_100g"])
            let fibre = Self.num(nutriments["fiber_100g"])
            let protein = Self.num(nutriments["proteins_100g"])
            let fat = Self.num(nutriments["fat_100g"])
            let kcal = Self.num(nutriments["energy-kcal_100g"])
            let servingGrams = Self.num(product["serving_quantity"]) > 0 ? Self.num(product["serving_quantity"]) : 100.0

            let item = UKFoodItem(
                id: code,
                name: name,
                brand: brand,
                category: "Supermarket",
                carbsPer100g: carbs,
                fibrePer100g: fibre,
                proteinPer100g: protein,
                fatPer100g: fat,
                kcalPer100g: kcal,
                defaultPortionGrams: servingGrams,
                portionLabel: "\(Int(servingGrams))g serving",
                barcode: code
            )
            customFoods.insert(item, at: 0)
            barcodeStatusMessage = "Scanned: \(item.name) — \(String(format: "%.1f", item.carbsPer100g))g carbs/100g"
            return item
        } catch {
            barcodeStatusMessage = "Barcode lookup error: \(error.localizedDescription)"
            return nil
        }
    }

    private static func num(_ any: Any?) -> Double {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String, let d = Double(s) { return d }
        return 0.0
    }

    // MARK: - Built-in UK Carbs & Cals / Supermarket / Restaurant / Hypo Rescue Database

    static let ukBuiltInFoods: [UKFoodItem] = [
        // Hypo Rescue Treatments
        UKFoodItem(id: "uk-lift-shot", name: "Lift Fast-Acting Glucose Shot (60ml)", brand: "Lift GlucoJuice", category: "Hypo Rescue", carbsPer100g: 25.0, fibrePer100g: 0, proteinPer100g: 0, fatPer100g: 0, kcalPer100g: 100, defaultPortionGrams: 60, portionLabel: "1 bottle (15g carbs)", barcode: "5060130090016"),
        UKFoodItem(id: "uk-dextro-tabs", name: "Dextro Energy Glucose Tablets", brand: "Dextro Energy", category: "Hypo Rescue", carbsPer100g: 89.0, fibrePer100g: 0, proteinPer100g: 0, fatPer100g: 0, kcalPer100g: 365, defaultPortionGrams: 17, portionLabel: "5 tablets (~15g carbs)", barcode: "4000540000105"),
        UKFoodItem(id: "uk-jelly-babies", name: "Bassetts Jelly Babies", brand: "Maynards Bassetts", category: "Hypo Rescue", carbsPer100g: 78.0, fibrePer100g: 0, proteinPer100g: 4.1, fatPer100g: 0.1, kcalPer100g: 330, defaultPortionGrams: 20, portionLabel: "4 sweets (~15.5g carbs)", barcode: "5010038252101"),
        UKFoodItem(id: "uk-lucozade", name: "Lucozade Energy Original", brand: "Lucozade UK", category: "Hypo Rescue", carbsPer100g: 8.9, fibrePer100g: 0, proteinPer100g: 0, fatPer100g: 0, kcalPer100g: 37, defaultPortionGrams: 170, portionLabel: "170ml (~15g carbs)", barcode: "5010157061509"),

        // UK Staples (Rice, Pasta, Potatoes, Bread, Oats)
        UKFoodItem(id: "uk-basmati-cooked", name: "White Basmati Rice (Cooked)", brand: "UK Staple", category: "UK Staples", carbsPer100g: 30.8, fibrePer100g: 0.8, proteinPer100g: 3.1, fatPer100g: 0.5, kcalPer100g: 141, defaultPortionGrams: 180, portionLabel: "180g cooked portion"),
        UKFoodItem(id: "uk-basmati-dry", name: "White Basmati Rice (Dry Uncooked)", brand: "UK Staple", category: "UK Staples", carbsPer100g: 77.5, fibrePer100g: 1.4, proteinPer100g: 8.5, fatPer100g: 1.1, kcalPer100g: 354, defaultPortionGrams: 75, portionLabel: "75g dry"),
        UKFoodItem(id: "uk-pasta-cooked", name: "White Pasta / Penne (Cooked)", brand: "UK Staple", category: "UK Staples", carbsPer100g: 30.9, fibrePer100g: 1.8, proteinPer100g: 5.5, fatPer100g: 0.9, kcalPer100g: 158, defaultPortionGrams: 200, portionLabel: "200g cooked"),
        UKFoodItem(id: "uk-pasta-dry", name: "White Pasta / Penne (Dry Uncooked)", brand: "UK Staple", category: "UK Staples", carbsPer100g: 72.0, fibrePer100g: 3.0, proteinPer100g: 12.5, fatPer100g: 1.5, kcalPer100g: 354, defaultPortionGrams: 85, portionLabel: "85g dry"),
        UKFoodItem(id: "uk-jacket-potato", name: "Baked Jacket Potato (with skin)", brand: "UK Staple", category: "UK Staples", carbsPer100g: 21.5, fibrePer100g: 2.6, proteinPer100g: 2.5, fatPer100g: 0.2, kcalPer100g: 97, defaultPortionGrams: 250, portionLabel: "1 medium potato (250g)"),
        UKFoodItem(id: "uk-mash-potato", name: "Mashed Potato (with butter & milk)", brand: "UK Staple", category: "UK Staples", carbsPer100g: 15.5, fibrePer100g: 1.4, proteinPer100g: 2.0, fatPer100g: 4.2, kcalPer100g: 108, defaultPortionGrams: 200, portionLabel: "200g serving"),
        UKFoodItem(id: "uk-oven-chips", name: "McCain Home Chips (Oven Cooked)", brand: "McCain UK", category: "UK Staples", carbsPer100g: 27.0, fibrePer100g: 2.7, proteinPer100g: 3.0, fatPer100g: 5.2, kcalPer100g: 169, defaultPortionGrams: 165, portionLabel: "165g portion", barcode: "5010228000018"),
        UKFoodItem(id: "uk-warburtons-toastie", name: "Warburtons Toastie Thick White Bread", brand: "Warburtons", category: "Supermarket", carbsPer100g: 45.7, fibrePer100g: 2.4, proteinPer100g: 9.2, fatPer100g: 2.1, kcalPer100g: 239, defaultPortionGrams: 94, portionLabel: "2 thick slices (94g)", barcode: "5010044000017"),
        UKFoodItem(id: "uk-hovis-wholemeal", name: "Hovis Thick Wholemeal Bread", brand: "Hovis", category: "Supermarket", carbsPer100g: 37.8, fibrePer100g: 6.5, proteinPer100g: 10.4, fatPer100g: 2.2, kcalPer100g: 222, defaultPortionGrams: 88, portionLabel: "2 slices (88g)", barcode: "5010003000119"),
        UKFoodItem(id: "uk-heinz-beans", name: "Heinz Baked Beans in Tomato Sauce", brand: "Heinz UK", category: "Supermarket", carbsPer100g: 12.5, fibrePer100g: 3.7, proteinPer100g: 4.7, fatPer100g: 0.2, kcalPer100g: 78, defaultPortionGrams: 207, portionLabel: "Half tin (207g)", barcode: "5000157024671"),
        UKFoodItem(id: "uk-quaker-oats", name: "Quaker Rolled Porridge Oats (Dry)", brand: "Quaker UK", category: "Supermarket", carbsPer100g: 60.0, fibrePer100g: 9.0, proteinPer100g: 11.0, fatPer100g: 8.0, kcalPer100g: 374, defaultPortionGrams: 40, portionLabel: "40g bowl", barcode: "5000108018315"),
        UKFoodItem(id: "uk-weetabix", name: "Weetabix Original Biscuits", brand: "Weetabix", category: "Supermarket", carbsPer100g: 69.0, fibrePer100g: 10.0, proteinPer100g: 12.0, fatPer100g: 2.0, kcalPer100g: 362, defaultPortionGrams: 37.5, portionLabel: "2 biscuits (37.5g)", barcode: "5010029000016"),
        UKFoodItem(id: "uk-banana", name: "Banana (Peeled Weight)", brand: "Fresh Fruit", category: "UK Staples", carbsPer100g: 20.3, fibrePer100g: 1.4, proteinPer100g: 1.2, fatPer100g: 0.1, kcalPer100g: 89, defaultPortionGrams: 100, portionLabel: "1 medium peeled (100g)"),
        UKFoodItem(id: "uk-apple", name: "Apple (Royal Gala / Braeburn)", brand: "Fresh Fruit", category: "UK Staples", carbsPer100g: 11.8, fibrePer100g: 1.8, proteinPer100g: 0.4, fatPer100g: 0.1, kcalPer100g: 51, defaultPortionGrams: 135, portionLabel: "1 medium apple (135g)"),
        UKFoodItem(id: "uk-kidney-beans", name: "Red Kidney Beans in Water (Drained)", brand: "Tesco / Sainsbury's", category: "Supermarket", carbsPer100g: 16.5, fibrePer100g: 6.7, proteinPer100g: 7.5, fatPer100g: 0.6, kcalPer100g: 115, defaultPortionGrams: 240, portionLabel: "1 drained tin (240g)"),
        UKFoodItem(id: "uk-chopped-tomatoes", name: "Tin of Chopped Tomatoes", brand: "Napolina / Tesco", category: "Supermarket", carbsPer100g: 3.9, fibrePer100g: 1.0, proteinPer100g: 1.1, fatPer100g: 0.2, kcalPer100g: 23, defaultPortionGrams: 400, portionLabel: "1 full tin (400g)"),

        // UK High Street, Greggs, McDonald's, Nando's, Domino's (Great for FPU + Bolus!)
        UKFoodItem(id: "uk-greggs-sausage-roll", name: "Greggs Sausage Roll", brand: "Greggs UK", category: "UK Takeaway", carbsPer100g: 24.0, fibrePer100g: 1.8, proteinPer100g: 9.4, fatPer100g: 22.0, kcalPer100g: 327, defaultPortionGrams: 103, portionLabel: "1 roll (25g carbs)"),
        UKFoodItem(id: "uk-greggs-steak-bake", name: "Greggs Steak Bake", brand: "Greggs UK", category: "UK Takeaway", carbsPer100g: 22.8, fibrePer100g: 1.5, proteinPer100g: 11.2, fatPer100g: 18.5, kcalPer100g: 300, defaultPortionGrams: 136, portionLabel: "1 bake (31g carbs)"),
        UKFoodItem(id: "uk-mcd-bigmac", name: "McDonald's Big Mac", brand: "McDonald's UK", category: "UK Takeaway", carbsPer100g: 19.5, fibrePer100g: 1.5, proteinPer100g: 12.5, fatPer100g: 11.5, kcalPer100g: 232, defaultPortionGrams: 215, portionLabel: "1 burger (42g carbs)"),
        UKFoodItem(id: "uk-mcd-med-fries", name: "McDonald's Medium Fries", brand: "McDonald's UK", category: "UK Takeaway", carbsPer100g: 36.8, fibrePer100g: 3.8, proteinPer100g: 3.5, fatPer100g: 14.9, kcalPer100g: 296, defaultPortionGrams: 114, portionLabel: "1 medium (42g carbs)"),
        UKFoodItem(id: "uk-nandos-spicy-rice", name: "Nando's Spicy Rice (Regular)", brand: "Nando's UK", category: "UK Takeaway", carbsPer100g: 27.5, fibrePer100g: 1.9, proteinPer100g: 4.5, fatPer100g: 4.2, kcalPer100g: 168, defaultPortionGrams: 190, portionLabel: "Regular side (52g carbs)"),
        UKFoodItem(id: "uk-dominos-pepperoni", name: "Domino's Pepperoni Passion (Classic Crust)", brand: "Domino's UK", category: "UK Takeaway", carbsPer100g: 29.5, fibrePer100g: 1.9, proteinPer100g: 13.0, fatPer100g: 12.8, kcalPer100g: 286, defaultPortionGrams: 300, portionLabel: "3 medium slices (88.5g carbs, high FPU)"),
        UKFoodItem(id: "uk-chip-shop-chips", name: "Fish & Chip Shop Chips", brand: "UK Chippy", category: "UK Takeaway", carbsPer100g: 30.1, fibrePer100g: 2.6, proteinPer100g: 3.4, fatPer100g: 10.5, kcalPer100g: 232, defaultPortionGrams: 300, portionLabel: "Standard portion (90g carbs)"),
        UKFoodItem(id: "uk-battered-cod", name: "Battered Cod Fillet (Chip Shop)", brand: "UK Chippy", category: "UK Takeaway", carbsPer100g: 7.5, fibrePer100g: 0.4, proteinPer100g: 16.0, fatPer100g: 13.5, kcalPer100g: 215, defaultPortionGrams: 220, portionLabel: "1 medium fillet (16.5g carbs)")
    ]
}
