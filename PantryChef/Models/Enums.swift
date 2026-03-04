import Foundation

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
        case .grains: return "wheat.bundle.fill" // Note: use custom or SF alternative
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

    var color: String {
        switch self {
        case .dairy: return "categoryBlue"
        case .produce: return "categoryGreen"
        case .protein: return "categoryRed"
        case .grains: return "categoryAmber"
        case .spices: return "categoryOrange"
        case .condiments: return "categoryPurple"
        case .bakingSupplies: return "categoryPink"
        case .frozenFoods: return "categoryCyan"
        case .canned: return "categoryBrown"
        case .beverages: return "categoryTeal"
        case .snacks: return "categoryYellow"
        case .oils: return "categoryGold"
        case .pasta: return "categoryIndigo"
        case .nuts: return "categoryTan"
        case .other: return "categoryGray"
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
        case .dairyFree: return "drop.slash.fill" // Note: symbolic
        case .nutFree: return "exclamationmark.triangle.fill"
        case .lowCarb: return "chart.bar.fill"
        case .highProtein: return "bolt.fill"
        case .keto: return "flame.fill"
        case .paleo: return "fossil.shell.fill"
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
}

// MARK: - Expiry Status
enum ExpiryStatus {
    case fresh
    case expiringSoon // within 3 days
    case expired

    var color: String {
        switch self {
        case .fresh: return "freshGreen"
        case .expiringSoon: return "warningYellow"
        case .expired: return "expiredRed"
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
