import Foundation

/// Per-serving macros for a dish. Whole numbers only (no false precision). Codable so
/// a dish can carry hand-authored or AI-generated facts; absent those, the
/// `NutritionEstimator` derives a clearly-labelled estimate from the ingredient list.
struct NutritionFacts: Codable, Equatable, Sendable {
    var calories: Int
    var protein: Int   // grams
    var carbs: Int     // grams
    var fat: Int       // grams
}

/// Derives per-serving nutrition from a recipe's ingredient list — offline and fully
/// deterministic (so it's unit-testable and costs nothing). It resolves each line to a
/// gram weight (mass directly; volume/count through the catalog's density enrichment;
/// a category portion otherwise) and multiplies by a per-100g macro profile (a small
/// table of common ingredients, with a per-category fallback). Rough by nature — the
/// UI labels it an estimate, and an explicit `dish.nutrition` always overrides it.
enum NutritionEstimator {

    private struct Macro { let kcal, protein, carbs, fat: Double }   // per 100 g

    static func estimate(_ dish: Dish) -> NutritionFacts? {
        let servings = max(1, dish.servings)
        var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
        var counted = false
        for line in dish.ingredients {
            guard let grams = grams(for: line) else { continue }
            let m = macro(for: line)
            let f = grams / 100
            kcal += f * m.kcal; protein += f * m.protein; carbs += f * m.carbs; fat += f * m.fat
            counted = true
        }
        guard counted, kcal > 0 else { return nil }
        func perServing(_ total: Double) -> Int { Int((total / Double(servings)).rounded()) }
        return NutritionFacts(calories: perServing(kcal), protein: perServing(protein),
                              carbs: perServing(carbs), fat: perServing(fat))
    }

    // MARK: - Grams per line

    private static func grams(for line: RecipeLine) -> Double? {
        let item = line.catalogItemID.flatMap { PantryCatalog.item(id: $0) }
            ?? PantryCatalog.resolveExact(name: line.key)
        let category = item?.category ?? .other
        guard let amount = line.amount, let (qty, unit) = UnitConversion.parseAmount(amount) else {
            // No parseable "<qty> <unit>" — try a bare leading count → pieces, else a
            // single category portion (so "to taste" spices don't dominate a plate).
            if let amount = line.amount, let n = IntakeParser.quantity(amount.split(separator: " ").first.map(String.init) ?? "") {
                return n * pieceGrams(item: item, category: category)
            }
            return portionGrams(category)
        }
        switch unit {
        case .gram: return qty
        case .kilogram: return qty * 1000
        case .ounce: return qty * 28.35
        case .pound: return qty * 453.6
        case .milliliter, .fluidOunce: return qty * (unit == .fluidOunce ? 29.6 : 1)
        case .liter: return qty * 1000
        case .cup, .tablespoon, .teaspoon:
            if let item, let g = UnitConversion.grams(qty: qty, unit: unit, item: item) { return g }
            // Generic density ≈ water for an unknown ingredient.
            let perCup = 240.0
            switch unit { case .cup: return qty * perCup
                          case .tablespoon: return qty * perCup / 16
                          default: return qty * perCup / 48 }
        case .pinch, .splash, .toTaste:
            return 2   // negligible — a seasoning touch, not a load-bearing weight
        case .piece, .whole, .loaf, .slice, .clove, .bunch, .can, .package:
            return qty * pieceGrams(item: item, category: category)
        }
    }

    private static func pieceGrams(item: PantryCatalogItemDefinition?, category: FoodCategory) -> Double {
        item?.gramsPerPiece ?? defaultPieceGrams(category)
    }
    private static func defaultPieceGrams(_ category: FoodCategory) -> Double {
        switch category {
        case .produce: return 100; case .protein: return 140; case .dairy: return 50
        case .breads: return 60; case .legumes, .canned: return 120; default: return 80
        }
    }
    /// One typical recipe portion for a category when there's no usable amount.
    private static func portionGrams(_ category: FoodCategory) -> Double {
        switch category {
        case .spices: return 3; case .oils, .condiments: return 12
        case .produce: return 80; case .protein: return 130; case .dairy: return 40
        case .nuts: return 20; case .bakingSupplies: return 25
        default: return 60
        }
    }

    // MARK: - Macros per 100 g

    private static func macro(for line: RecipeLine) -> Macro {
        if let id = line.catalogItemID, let m = byID[id] { return m }
        let category = (line.catalogItemID.flatMap { PantryCatalog.item(id: $0) }
            ?? PantryCatalog.resolveExact(name: line.key))?.category ?? .other
        return byCategory[category] ?? byCategory[.other]!
    }

    /// Per-100g macros for the ingredients that recur across the seed library — enough
    /// to anchor the common cases; everything else falls back to its category.
    private static let byID: [String: Macro] = [
        "spinach": Macro(kcal: 23, protein: 2.9, carbs: 3.6, fat: 0.4),
        "chicken-thigh": Macro(kcal: 209, protein: 26, carbs: 0, fat: 11),
        "chicken-breast": Macro(kcal: 165, protein: 31, carbs: 0, fat: 3.6),
        "egg": Macro(kcal: 143, protein: 13, carbs: 1.1, fat: 9.5),
        "milk": Macro(kcal: 60, protein: 3.2, carbs: 5, fat: 3.3),
        "butter": Macro(kcal: 717, protein: 0.9, carbs: 0.1, fat: 81),
        "cheddar": Macro(kcal: 403, protein: 25, carbs: 1.3, fat: 33),
        "parmesan": Macro(kcal: 431, protein: 38, carbs: 4, fat: 29),
        "feta": Macro(kcal: 264, protein: 14, carbs: 4, fat: 21),
        "greek-yogurt": Macro(kcal: 97, protein: 9, carbs: 4, fat: 5),
        "beef-ground": Macro(kcal: 250, protein: 26, carbs: 0, fat: 15),
        "salmon-oily-fish": Macro(kcal: 208, protein: 20, carbs: 0, fat: 13),
        "white-rice": Macro(kcal: 360, protein: 7, carbs: 79, fat: 0.6),
        "orzo": Macro(kcal: 360, protein: 12, carbs: 74, fat: 1.5),
        "olive-oil": Macro(kcal: 884, protein: 0, carbs: 0, fat: 100),
        "onion": Macro(kcal: 40, protein: 1.1, carbs: 9, fat: 0.1),
        "garlic": Macro(kcal: 149, protein: 6, carbs: 33, fat: 0.5),
        "tomato": Macro(kcal: 18, protein: 0.9, carbs: 3.9, fat: 0.2),
        "canned-diced-tomatoes": Macro(kcal: 32, protein: 1.6, carbs: 7, fat: 0.3),
        "carrot": Macro(kcal: 41, protein: 0.9, carbs: 10, fat: 0.2),
        "broccoli": Macro(kcal: 34, protein: 2.8, carbs: 7, fat: 0.4),
        "lemon": Macro(kcal: 29, protein: 1.1, carbs: 9, fat: 0.3),
        "black-beans": Macro(kcal: 132, protein: 9, carbs: 24, fat: 0.5),
        "chickpea": Macro(kcal: 164, protein: 9, carbs: 27, fat: 2.6),
        "pea": Macro(kcal: 81, protein: 5, carbs: 14, fat: 0.4),
    ]

    private static let byCategory: [FoodCategory: Macro] = [
        .produce: Macro(kcal: 40, protein: 2, carbs: 8, fat: 0.3),
        .protein: Macro(kcal: 200, protein: 24, carbs: 0, fat: 11),
        .dairy: Macro(kcal: 150, protein: 8, carbs: 8, fat: 9),
        .breads: Macro(kcal: 270, protein: 9, carbs: 50, fat: 3),
        .pasta: Macro(kcal: 360, protein: 12, carbs: 74, fat: 1.5),
        .grains: Macro(kcal: 350, protein: 9, carbs: 73, fat: 2),
        .legumes: Macro(kcal: 140, protein: 9, carbs: 23, fat: 1),
        .canned: Macro(kcal: 80, protein: 4, carbs: 14, fat: 1),
        .frozenFoods: Macro(kcal: 110, protein: 5, carbs: 16, fat: 3),
        .condiments: Macro(kcal: 120, protein: 2, carbs: 14, fat: 5),
        .oils: Macro(kcal: 884, protein: 0, carbs: 0, fat: 100),
        .spices: Macro(kcal: 250, protein: 10, carbs: 50, fat: 8),
        .bakingSupplies: Macro(kcal: 380, protein: 7, carbs: 80, fat: 3),
        .nuts: Macro(kcal: 600, protein: 20, carbs: 20, fat: 50),
        .beverages: Macro(kcal: 45, protein: 0, carbs: 11, fat: 0),
        .alcohol: Macro(kcal: 90, protein: 0, carbs: 3, fat: 0),
        .snacks: Macro(kcal: 450, protein: 6, carbs: 60, fat: 20),
        .other: Macro(kcal: 110, protein: 4, carbs: 16, fat: 4),
    ]
}
