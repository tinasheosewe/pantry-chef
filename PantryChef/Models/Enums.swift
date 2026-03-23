import Foundation
import SwiftUI

// MARK: - Food Category
enum FoodCategory: String, Codable, CaseIterable, Identifiable {
    case dairy = "Dairy"
    case produce = "Produce"
    case protein = "Protein"
    case grains = "Grains & Cereals"
    case spices = "Spices & Herbs"
    case condiments = "Condiments & Sauces"
    case bakingSupplies = "Baking Supplies"
    case frozenFoods = "Frozen Foods"
    case canned = "Canned & Jarred"
    case beverages = "Beverages"
    case snacks = "Snacks"
    case oils = "Oils & Fats"
    case pasta = "Pasta & Noodles"
    case nuts = "Nuts & Seeds"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dairy: return "cup.and.saucer.fill"
        case .produce: return "leaf.fill"
        case .protein: return "fish.fill"
        case .grains: return "circle.grid.3x3.fill"
        case .spices: return "flame.fill"
        case .condiments: return "waterbottle.fill"
        case .bakingSupplies: return "birthday.cake.fill"
        case .frozenFoods: return "snowflake"
        case .canned: return "archivebox.fill"
        case .beverages: return "mug.fill"
        case .snacks: return "popcorn.fill"
        case .oils: return "drop.fill"
        case .pasta: return "fork.knife"
        case .nuts: return "oval.fill"
        case .other: return "bag.fill"
        }
    }

    var color: Color {
        switch self {
        case .dairy:          return Color(red: 0.38, green: 0.65, blue: 0.96) // sky blue
        case .produce:        return Color(red: 0.13, green: 0.77, blue: 0.37) // emerald
        case .protein:        return Color(red: 0.94, green: 0.44, blue: 0.44) // salmon
        case .grains:         return Color(red: 0.96, green: 0.72, blue: 0.26) // golden
        case .spices:         return Color(red: 0.98, green: 0.62, blue: 0.20) // amber
        case .condiments:     return Color(red: 0.62, green: 0.44, blue: 0.87) // lavender
        case .bakingSupplies: return Color(red: 0.94, green: 0.53, blue: 0.68) // rose
        case .frozenFoods:    return Color(red: 0.35, green: 0.78, blue: 0.88) // ice blue
        case .canned:         return Color(red: 0.73, green: 0.56, blue: 0.41) // warm brown
        case .beverages:      return Color(red: 0.06, green: 0.73, blue: 0.70) // teal
        case .snacks:         return Color(red: 0.96, green: 0.80, blue: 0.22) // bright yellow
        case .oils:           return Color(red: 0.88, green: 0.70, blue: 0.18) // golden oil
        case .pasta:          return Color(red: 0.48, green: 0.40, blue: 0.82) // soft indigo
        case .nuts:           return Color(red: 0.78, green: 0.66, blue: 0.48) // warm tan
        case .other:          return Color(red: 0.62, green: 0.65, blue: 0.70) // cool gray
        }
    }
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
        case let x where x.contains("dairy") || x.contains("cheese") || x.contains("milk"): return .dairy
        case let x where x.contains("produce") || x.contains("vegetable") || x.contains("fruit"): return .produce
        case let x where x.contains("protein") || x.contains("meat") || x.contains("seafood") || x.contains("poultry"): return .protein
        case let x where x.contains("grain") || x.contains("cereal") || x.contains("bread") || x.contains("bakery"): return .grains
        case let x where x.contains("spice") || x.contains("herb") || x.contains("seasoning"): return .spices
        case let x where x.contains("condiment") || x.contains("sauce"): return .condiments
        case let x where x.contains("baking"): return .bakingSupplies
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
        case .halal: return "checkmark.seal.fill"
        case .kosher: return "star.fill"
        }
    }
}

// MARK: - Difficulty Level
enum DifficultyLevel: Int, Codable, CaseIterable, Identifiable {
    case beginner = 1
    case easy = 2
    case medium = 3
    case hard = 4
    case expert = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .beginner: return "Beginner"
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .hard: return "Hard"
        case .expert: return "Expert"
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "1.circle.fill"
        case .easy: return "2.circle.fill"
        case .medium: return "3.circle.fill"
        case .hard: return "4.circle.fill"
        case .expert: return "5.circle.fill"
        }
    }
}

// MARK: - Meal Type
enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"
    case dessert = "Dessert"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .snack: return "carrot.fill"
        case .dessert: return "birthday.cake.fill"
        }
    }

    static func parse(_ string: String?) -> MealType? {
        guard let string else { return nil }
        let normalized = string
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: " ")
        guard !normalized.isEmpty else { return nil }

        if let direct = MealType.allCases.first(where: { $0.rawValue.lowercased() == normalized }) {
            return direct
        }

        switch normalized {
        case let value where value.contains("breakfast"): return .breakfast
        case let value where value.contains("lunch"): return .lunch
        case let value where value.contains("dinner"): return .dinner
        case let value where value.contains("snack"): return .snack
        case let value where value.contains("dessert"),
             let value where value.contains("sweet"): return .dessert
        default: return nil
        }
    }
}

// MARK: - Cuisine Type
enum CuisineType: String, Codable, CaseIterable, Identifiable {
    case italian = "Italian"
    case mexican = "Mexican"
    case chinese = "Chinese"
    case japanese = "Japanese"
    case indian = "Indian"
    case thai = "Thai"
    case french = "French"
    case mediterranean = "Mediterranean"
    case american = "American"
    case korean = "Korean"
    case vietnamese = "Vietnamese"
    case greek = "Greek"
    case middleEastern = "Middle Eastern"
    case ethiopian = "Ethiopian"
    case caribbean = "Caribbean"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .italian: return "🇮🇹"
        case .mexican: return "🇲🇽"
        case .chinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .indian: return "🇮🇳"
        case .thai: return "🇹🇭"
        case .french: return "🇫🇷"
        case .mediterranean: return "🫒"
        case .american: return "🇺🇸"
        case .korean: return "🇰🇷"
        case .vietnamese: return "🇻🇳"
        case .greek: return "🇬🇷"
        case .middleEastern: return "🧆"
        case .ethiopian: return "🇪🇹"
        case .caribbean: return "🌴"
        case .other: return "🍽️"
        }
    }

    static func parse(_ string: String?) -> CuisineType? {
        guard let string else { return nil }
        let normalized = string
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: " ")
        guard !normalized.isEmpty else { return nil }

        if let direct = CuisineType.allCases.first(where: { $0.rawValue.lowercased() == normalized }) {
            return direct
        }

        switch normalized {
        case let value where value.contains("ital"):
            return .italian
        case let value where value.contains("mex"):
            return .mexican
        case let value where value.contains("chin"):
            return .chinese
        case let value where value.contains("japan"):
            return .japanese
        case let value where value.contains("indian") || value.contains("india"):
            return .indian
        case let value where value.contains("thai"):
            return .thai
        case let value where value.contains("french") || value.contains("france"):
            return .french
        case let value where value.contains("mediterranean"):
            return .mediterranean
        case let value where value.contains("american") || value.contains("usa"):
            return .american
        case let value where value.contains("korean") || value.contains("korea"):
            return .korean
        case let value where value.contains("vietnamese") || value.contains("vietnam"):
            return .vietnamese
        case let value where value.contains("greek") || value.contains("greece"):
            return .greek
        case let value where value.contains("middle eastern") || value.contains("middleeast") || value.contains("levant") || value.contains("arabic"):
            return .middleEastern
        case let value where value.contains("ethiopian") || value.contains("ethiopia"):
            return .ethiopian
        case let value where value.contains("caribbean"):
            return .caribbean
        case let value where value.contains("other"):
            return .other
        default:
            return nil
        }
    }
}

// MARK: - Recipe Source
enum RecipeSource: Codable, Hashable {
    case user
    case bundled
    case imported
    case aiGenerated

    var label: String {
        switch self {
        case .user: return "My Recipe"
        case .bundled: return "Featured"
        case .imported: return "Imported"
        case .aiGenerated: return "Chef"
        }
    }

    var isUserRecipe: Bool { if case .user = self { return true } else { return false } }

    var shouldAutoResolveIngredientsWithoutReview: Bool {
        switch self {
        case .aiGenerated:
            return true
        case .user, .bundled, .imported:
            return false
        }
    }

    var shouldConvertToUserRecipeOnSave: Bool {
        switch self {
        case .imported:
            return true
        case .user, .bundled, .aiGenerated:
            return false
        }
    }
}

// MARK: - Substitution Impact
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

// MARK: - Expiry Status
enum ExpiryStatus {
    case fresh
    case expiringSoon // within 3 days
    case expired

    var color: Color {
        switch self {
        case .fresh: return Color(red: 0.30, green: 0.69, blue: 0.31)
        case .expiringSoon: return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .expired: return Color(red: 0.90, green: 0.30, blue: 0.24)
        }
    }

    var label: String {
        switch self {
        case .fresh: return "Fresh"
        case .expiringSoon: return "Use Soon"
        case .expired: return "Expired"
        }
    }
}
