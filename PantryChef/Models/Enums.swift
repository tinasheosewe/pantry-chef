import Foundation
import SwiftUI

// MARK: - Food Category
enum FoodCategory: String, Codable, CaseIterable, Identifiable {
    case alcohol = "Alcohol & Spirits"
    case bakingSupplies = "Baking & Sweeteners"
    case beverages = "Beverages"
    case breads = "Breads & Bakery"
    case canned = "Canned & Jarred"
    case condiments = "Condiments & Sauces"
    case dairy = "Dairy & Eggs"
    case frozenFoods = "Frozen Foods"
    case grains = "Grains & Cereals"
    case legumes = "Legumes & Beans"
    case nuts = "Nuts & Seeds"
    case oils = "Oils & Fats"
    case other = "Other"
    case pasta = "Pasta & Noodles"
    case produce = "Produce"
    case protein = "Protein"
    case snacks = "Snacks"
    case spices = "Spices & Herbs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .alcohol: return "wineglass.fill"
        case .bakingSupplies: return "birthday.cake.fill"
        case .beverages: return "mug.fill"
        case .breads: return "basket.fill"
        case .canned: return "archivebox.fill"
        case .condiments: return "waterbottle.fill"
        case .dairy: return "cup.and.saucer.fill"
        case .frozenFoods: return "snowflake"
        case .grains: return "circle.grid.3x3.fill"
        case .legumes: return "leaf.circle.fill"
        case .nuts: return "oval.fill"
        case .oils: return "drop.fill"
        case .other: return "bag.fill"
        case .pasta: return "fork.knife"
        case .produce: return "leaf.fill"
        case .protein: return "fish.fill"
        case .snacks: return "popcorn.fill"
        case .spices: return "flame.fill"
        }
    }

    /// A muted, earthy "field journal" hue per category — desaturated clays, ochres,
    /// olives and one cool slate, so the category spines read as printed ink on cream,
    /// not a bright Material rainbow (which jarred against the ink/cream/paprika world).
    var color: Color {
        switch self {
        case .produce:        return Color(red: 0.36, green: 0.49, blue: 0.31) // olive leaf
        case .protein:        return Color(red: 0.71, green: 0.37, blue: 0.30) // terracotta
        case .dairy:          return Color(red: 0.80, green: 0.66, blue: 0.40) // butter gold
        case .breads:         return Color(red: 0.73, green: 0.55, blue: 0.36) // crust
        case .pasta:          return Color(red: 0.79, green: 0.63, blue: 0.35) // semolina
        case .grains:         return Color(red: 0.68, green: 0.54, blue: 0.30) // wheat
        case .legumes:        return Color(red: 0.49, green: 0.45, blue: 0.27) // lentil
        case .canned:         return Color(red: 0.62, green: 0.45, blue: 0.34) // tin brown
        case .frozenFoods:    return Color(red: 0.44, green: 0.54, blue: 0.55) // frost slate
        case .condiments:     return Color(red: 0.55, green: 0.37, blue: 0.43) // plum
        case .oils:           return Color(red: 0.69, green: 0.57, blue: 0.29) // pressed oil
        case .spices:         return Color(red: 0.78, green: 0.45, blue: 0.22) // paprika
        case .bakingSupplies: return Color(red: 0.72, green: 0.51, blue: 0.51) // rose clay
        case .nuts:           return Color(red: 0.58, green: 0.44, blue: 0.31) // hazel
        case .beverages:      return Color(red: 0.45, green: 0.50, blue: 0.43) // sage brown
        case .alcohol:        return Color(red: 0.50, green: 0.27, blue: 0.32) // burgundy
        case .snacks:         return Color(red: 0.78, green: 0.56, blue: 0.25) // ochre
        case .other:          return Color(red: 0.46, green: 0.46, blue: 0.41) // warm gray
        }
    }

    var defaultsToOnHand: Bool {
        switch self {
        case .spices, .bakingSupplies, .condiments, .oils: return true
        default: return false
        }
    }

    /// A kitchen-sensible display order (what you reach for first / shop by aisle),
    /// not the enum's alphabetical raw order. Shared by the Pantry inventory and the
    /// shopping list so both group categories the same way.
    static let displayOrder: [FoodCategory] = [
        .produce, .protein, .dairy, .breads, .pasta, .grains, .legumes, .canned,
        .frozenFoods, .condiments, .oils, .spices, .bakingSupplies, .nuts,
        .beverages, .alcohol, .snacks, .other
    ]
}

// MARK: - Measurement Unit
enum MeasurementUnit: String, Codable, CaseIterable, Identifiable {
    // Volume
    case teaspoon = "tsp"
    case tablespoon = "tbsp"
    case cup = "cup"
    case fluidOunce = "fl oz"
    case milliliter = "ml"
    case liter = "L"

    // Weight
    case gram = "g"
    case kilogram = "kg"
    case ounce = "oz"
    case pound = "lb"

    // Count
    case piece = "piece"
    case whole = "whole"
    case loaf = "loaf"
    case slice = "slice"
    case clove = "clove"
    case bunch = "bunch"
    case can = "can"
    case package = "pkg"
    case pinch = "pinch"
    case splash = "splash"
    case toTaste = "to taste"

    var id: String { rawValue }

    var isMetric: Bool {
        switch self {
        case .milliliter, .liter, .gram, .kilogram: return true
        default: return false
        }
    }

    static func contextualUnits(for category: FoodCategory) -> [MeasurementUnit] {
        switch category {
        case .protein:
            return [.pound, .ounce, .kilogram, .gram, .piece, .whole, .package]
        case .dairy:
            return [.cup, .fluidOunce, .milliliter, .liter, .piece, .whole, .ounce, .gram, .package]
        case .produce:
            return [.piece, .bunch, .pound, .ounce, .kilogram, .gram, .whole]
        case .spices:
            return [.teaspoon, .tablespoon, .ounce, .gram, .milliliter, .pinch, .toTaste]
        case .oils:
            return [.tablespoon, .cup, .fluidOunce, .milliliter, .liter, .splash]
        case .grains, .pasta, .legumes:
            return [.cup, .pound, .ounce, .kilogram, .gram, .package]
        case .bakingSupplies:
            return [.cup, .tablespoon, .teaspoon, .ounce, .gram, .pound, .kilogram, .milliliter, .package]
        case .condiments:
            return [.tablespoon, .teaspoon, .cup, .fluidOunce, .milliliter, .ounce, .gram]
        case .beverages, .alcohol:
            return [.fluidOunce, .cup, .milliliter, .liter, .can]
        case .breads:
            return [.loaf, .slice, .piece, .whole, .gram, .ounce, .package]
        case .canned:
            return [.can, .cup, .ounce, .gram, .milliliter, .piece]
        case .frozenFoods:
            return [.package, .piece, .ounce, .pound, .gram, .kilogram, .cup]
        case .nuts, .snacks:
            return [.cup, .ounce, .gram, .pound, .kilogram, .package]
        case .other:
            return [.piece, .cup, .ounce, .gram, .pound, .kilogram, .tablespoon, .milliliter, .package]
        }
    }

    static func parse(_ string: String?) -> MeasurementUnit? {
        guard let raw = string?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "tsp", "teaspoon", "teaspoons": return .teaspoon
        case "tbsp", "tbs", "tablespoon", "tablespoons": return .tablespoon
        case "cup", "cups", "c": return .cup
        case "fl oz", "fluid ounce", "fluid ounces": return .fluidOunce
        case "ml", "milliliter", "milliliters": return .milliliter
        case "l", "liter", "liters": return .liter
        case "g", "gram", "grams": return .gram
        case "kg", "kilogram", "kilograms": return .kilogram
        case "oz", "ounce", "ounces": return .ounce
        case "lb", "lbs", "pound", "pounds": return .pound
        case "piece", "pieces", "pcs": return .piece
        case "whole": return .whole
        case "loaf", "loaves": return .loaf
        case "slice", "slices": return .slice
        case "clove", "cloves": return .clove
        case "bunch": return .bunch
        case "can", "cans": return .can
        case "pkg", "package", "packages": return .package
        case "pinch": return .pinch
        case "splash", "dash": return .splash
        case "to taste": return .toTaste
        default: return MeasurementUnit(rawValue: raw)
        }
    }
}

extension FoodCategory {
    static func infer(from string: String?) -> FoodCategory {
        guard let s = string?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return .other
        }
        if let direct = FoodCategory.allCases.first(where: { $0.rawValue.lowercased() == s }) {
            return direct
        }

        switch s {
        case let x where x.contains("alcohol") || x.contains("spirit") || x.contains("wine") || x.contains("beer") || x.contains("liquor") || x.contains("liqueur"): return .alcohol
        case let x where x.contains("dairy") || x.contains("cheese") || x.contains("milk") || x.contains("egg"): return .dairy
        case let x where x.contains("produce") || x.contains("vegetable") || x.contains("fruit"): return .produce
        case let x where x.contains("protein") || x.contains("meat") || x.contains("seafood") || x.contains("poultry"): return .protein
        case let x where x.contains("legume") || x.contains("bean") || x.contains("lentil"): return .legumes
        case let x where x.contains("bread") || x.contains("bakery"): return .breads
        case let x where x.contains("grain") || x.contains("cereal"): return .grains
        case let x where x.contains("spice") || x.contains("herb") || x.contains("seasoning"): return .spices
        case let x where x.contains("condiment") || x.contains("sauce"): return .condiments
        case let x where x.contains("baking") || x.contains("sweetener"): return .bakingSupplies
        case let x where x.contains("frozen"): return .frozenFoods
        case let x where x.contains("canned") || x.contains("jarred"): return .canned
        case let x where x.contains("beverage"): return .beverages
        case let x where x.contains("snack"): return .snacks
        case let x where x.contains("oil") || x.contains("fat") || x.contains("vinegar"): return .oils
        case let x where x.contains("pasta") || x.contains("noodle"): return .pasta
        case let x where x.contains("nut") || x.contains("seed"): return .nuts
        default: return .other
        }
    }
}

// MARK: - Dietary Tag
enum DietaryTag: String, Codable, CaseIterable, Identifiable {
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case glutenFree = "Gluten-Free"
    case dairyFree = "Dairy-Free"
    case nutFree = "Nut-Free"
    case lowCarb = "Low Carb"
    case highProtein = "High Protein"
    case keto = "Keto"
    case paleo = "Paleo"
    case pescatarian = "Pescatarian"
    case halal = "Halal"
    case kosher = "Kosher"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .vegetarian: return "leaf.fill"
        case .vegan: return "leaf.circle.fill"
        case .glutenFree: return "xmark.circle.fill"
        case .dairyFree: return "cup.and.saucer.fill"
        case .nutFree: return "exclamationmark.triangle.fill"
        case .lowCarb: return "chart.bar.fill"
        case .highProtein: return "bolt.fill"
        case .keto: return "flame.fill"
        case .paleo: return "leaf.arrow.circlepath"
        case .pescatarian: return "fish.fill"
        case .halal: return "checkmark.seal.fill"
        case .kosher: return "star.fill"
        }
    }
}

enum SubstitutionImpact: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case slight = "Slight"
    case moderate = "Moderate"
    case significant = "Significant"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .none: return Color(red: 0.30, green: 0.69, blue: 0.31)
        case .slight: return Color(red: 0.60, green: 0.76, blue: 0.25)
        case .moderate: return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .significant: return Color(red: 0.90, green: 0.30, blue: 0.24)
        }
    }

    /// Numeric severity for comparisons (0 = none … 3 = significant).
    var ordinal: Int {
        switch self {
        case .none: return 0
        case .slight: return 1
        case .moderate: return 2
        case .significant: return 3
        }
    }
}

enum CookingImpact: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case slightAdjustment = "Slight Adjustment"
    case moderateAdjustment = "Moderate Adjustment"
    case majorAdjustment = "Major Adjustment"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .none: return Color(red: 0.30, green: 0.69, blue: 0.31)
        case .slightAdjustment: return Color(red: 0.60, green: 0.76, blue: 0.25)
        case .moderateAdjustment: return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .majorAdjustment: return Color(red: 0.90, green: 0.30, blue: 0.24)
        }
    }
}

