import Foundation

enum PantryStorage: String, Codable, CaseIterable, Identifiable, Sendable {
    case pantry = "Pantry"
    case refrigerated = "Refrigerated"
    case frozen = "Frozen"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pantry: return "cabinet"
        case .refrigerated: return "refrigerator"
        case .frozen: return "snowflake"
        }
    }
}

enum PantryFreshnessSource: String, Codable, CaseIterable, Sendable {
    case none
    case estimated
    case userProvided
}

enum PantryFacetKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case variant
    case form
    case preservation
    case processing
    case preparation
    case texture
    case concentration
    case base

    var id: String { rawValue }

    var title: String {
        switch self {
        case .variant: return "Variant"
        case .form: return "Form"
        case .preservation: return "Preservation"
        case .processing: return "Processing"
        case .preparation: return "Preparation"
        case .texture: return "Texture"
        case .concentration: return "Concentration"
        case .base: return "Base"
        }
    }
}

struct PantryFacetSelection: Codable, Hashable, Identifiable, Sendable {
    let key: PantryFacetKey
    let value: String

    var id: String {
        "\(key.rawValue):\(value)"
    }
}

struct PantryFacetDefinition: Codable, Hashable, Sendable {
    let key: PantryFacetKey
    let options: [String]
}

struct PantrySubstitutionDefinition: Hashable, Sendable {
    let substituteItemID: String
    let substituteFacets: [PantryFacetSelection]
    let ratio: String
    let tasteImpact: SubstitutionImpact
    let textureImpact: SubstitutionImpact
    let cookingImpact: CookingImpact
    let nutritionImpact: String?
    let notes: String?
    let dietary: [DietaryTag]?
}

struct PantryCatalogItemDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let category: FoodCategory
    let defaultUnit: MeasurementUnit?
    let defaultQuantity: Double?
    let defaultStorage: PantryStorage
    let aliases: [String]
    let facets: [PantryFacetDefinition]
    let defaultSelections: [PantryFacetSelection]
    let substitutions: [PantrySubstitutionDefinition]
    let unitOverrides: [PantryFacetKey: [String: MeasurementUnit]]
    let freshnessByStorage: [PantryStorage: ClosedRange<Int>]

    func supports(_ key: PantryFacetKey) -> Bool {
        facets.contains { $0.key == key }
    }

    func options(for key: PantryFacetKey) -> [String] {
        facets.first(where: { $0.key == key })?.options ?? []
    }

    func freshnessRange(for storage: PantryStorage) -> ClosedRange<Int>? {
        freshnessByStorage[storage]
    }

    func suggestedUnit(for selections: [PantryFacetSelection]) -> MeasurementUnit? {
        for selection in selections {
            if let override = unitOverrides[selection.key]?[selection.value] {
                return override
            }
        }

        return defaultUnit
    }

    func suggestedQuantity() -> Double? {
        defaultQuantity
    }

    func displayName(for selections: [PantryFacetSelection]) -> String {
        let orderedKeys: [PantryFacetKey] = [.variant, .form, .preservation, .processing, .preparation, .texture, .concentration, .base]
        let words = orderedKeys.compactMap { key in
            selections.first(where: { $0.key == key })?.value
        }
        guard !words.isEmpty else { return name }
        return (words + [name]).map(Self.titleCase).joined(separator: " ")
    }

    private static func titleCase(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

enum PantryCatalog {
    static let allItems: [PantryCatalogItemDefinition] = [
        item(
            id: "flour",
            name: "Flour",
            category: .bakingSupplies,
            defaultUnit: .gram,
            defaultQuantity: 1000,
            defaultStorage: .pantry,
            aliases: ["flour", "all purpose flour", "all-purpose flour"],
            facets: [.variant(["all-purpose", "bread", "cake", "self-rising"]), .texture(["fine"])],
            defaultSelections: [.init(key: .variant, value: "all-purpose")],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 240...365, .frozen: 365...540]
        ),
        item(
            id: "rice",
            name: "Rice",
            category: .grains,
            defaultUnit: .gram,
            defaultQuantity: 1000,
            defaultStorage: .pantry,
            aliases: ["rice"],
            facets: [.variant(["white", "brown", "jasmine", "basmati"])],
            defaultSelections: [.init(key: .variant, value: "white")],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 240...365, .frozen: 365...540]
        ),
        item(
            id: "pasta",
            name: "Pasta",
            category: .pasta,
            defaultUnit: .gram,
            defaultQuantity: 500,
            defaultStorage: .pantry,
            aliases: ["pasta", "noodles"],
            facets: [.form(["spaghetti", "penne", "fusilli"]), .base(["wheat", "chickpea"])],
            defaultSelections: [.init(key: .form, value: "spaghetti")],
            substitutions: [
                substitution(
                    itemID: "pasta",
                    facets: [.init(key: .base, value: "chickpea")],
                    ratio: "1:1",
                    tasteImpact: .moderate,
                    textureImpact: .slight,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "Higher protein and fiber",
                    notes: "Works best when shape stays similar.",
                    dietary: [.glutenFree]
                )
            ],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 240...365, .frozen: 365...540]
        ),
        item(
            id: "oats",
            name: "Oats",
            category: .grains,
            defaultUnit: .gram,
            defaultQuantity: 500,
            defaultStorage: .pantry,
            aliases: ["oats", "rolled oats"],
            facets: [.form(["rolled", "steel-cut", "quick"])],
            defaultSelections: [.init(key: .form, value: "rolled")],
            freshnessByStorage: [.pantry: 120...240, .refrigerated: 180...300, .frozen: 240...365]
        ),
        item(
            id: "milk",
            name: "Milk",
            category: .dairy,
            defaultUnit: .liter,
            defaultQuantity: 1,
            defaultStorage: .refrigerated,
            aliases: ["milk", "whole milk", "skim milk"],
            facets: [.variant(["whole", "semi-skimmed", "skim"]), .preservation(["fresh", "shelf-stable"]), .base(["dairy", "oat", "almond", "soy"])],
            defaultSelections: [.init(key: .variant, value: "whole")],
            substitutions: [
                substitution(
                    itemID: "milk",
                    facets: [.init(key: .base, value: "oat")],
                    ratio: "1:1",
                    tasteImpact: .slight,
                    textureImpact: .slight,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "Usually lower protein than dairy milk",
                    notes: "Reliable in porridge, sauces, and baking.",
                    dietary: [.vegan, .dairyFree]
                ),
                substitution(
                    itemID: "milk",
                    facets: [.init(key: .base, value: "almond")],
                    ratio: "1:1",
                    tasteImpact: .moderate,
                    textureImpact: .slight,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "Lower calories, lower protein",
                    notes: "Best where a lighter body is acceptable.",
                    dietary: [.vegan, .dairyFree]
                )
            ],
            freshnessByStorage: [.pantry: 30...120, .refrigerated: 5...10, .frozen: 30...90]
        ),
        item(
            id: "yogurt",
            name: "Yogurt",
            category: .dairy,
            defaultUnit: .gram,
            defaultQuantity: 500,
            defaultStorage: .refrigerated,
            aliases: ["yogurt", "yoghurt", "greek yogurt"],
            facets: [.variant(["plain", "greek"]), .base(["dairy", "coconut"]), .preservation(["fresh"])],
            defaultSelections: [.init(key: .variant, value: "plain")],
            substitutions: [
                substitution(
                    itemID: "yogurt",
                    facets: [.init(key: .variant, value: "greek")],
                    ratio: "1:1",
                    tasteImpact: .slight,
                    textureImpact: .moderate,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "Higher protein, thicker texture",
                    notes: "Thin with a little water if the recipe expects a looser yogurt.",
                    dietary: nil
                ),
                substitution(
                    itemID: "yogurt",
                    facets: [.init(key: .base, value: "coconut")],
                    ratio: "1:1",
                    tasteImpact: .moderate,
                    textureImpact: .slight,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "Dairy-free with lower protein",
                    notes: "Adds some sweetness depending on brand.",
                    dietary: [.vegan, .dairyFree]
                )
            ],
            freshnessByStorage: [.refrigerated: 5...14, .frozen: 30...60]
        ),
        item(
            id: "cheese",
            name: "Cheese",
            category: .dairy,
            defaultUnit: .gram,
            defaultQuantity: 200,
            defaultStorage: .refrigerated,
            aliases: ["cheese", "cheddar", "cheddar cheese", "mozzarella", "mozzarella cheese", "parmesan", "parmesan cheese"],
            facets: [.variant(["cheddar", "mozzarella", "parmesan"]), .form(["block", "shredded", "sliced"])],
            defaultSelections: [.init(key: .variant, value: "cheddar"), .init(key: .form, value: "block")],
            substitutions: [
                substitution(
                    itemID: "cheese",
                    facets: [.init(key: .variant, value: "mozzarella"), .init(key: .form, value: "shredded")],
                    ratio: "1:1",
                    tasteImpact: .slight,
                    textureImpact: .slight,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "Usually milder and slightly lower sodium",
                    notes: "Best for melts and bakes.",
                    dietary: [.vegetarian]
                ),
                substitution(
                    itemID: "cheese",
                    facets: [.init(key: .variant, value: "parmesan")],
                    ratio: "1/2:1",
                    tasteImpact: .moderate,
                    textureImpact: .slight,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "More intense flavor per gram",
                    notes: "Use less because parmesan is saltier and sharper.",
                    dietary: [.vegetarian]
                )
            ],
            freshnessByStorage: [.refrigerated: 7...30, .frozen: 60...180]
        ),
        item(
            id: "cream",
            name: "Cream",
            category: .dairy,
            defaultUnit: .milliliter,
            defaultQuantity: 300,
            defaultStorage: .refrigerated,
            aliases: ["cream", "double cream", "heavy cream", "heavy whipping cream"],
            facets: [.variant(["single", "double", "heavy"])],
            defaultSelections: [.init(key: .variant, value: "double")],
            substitutions: [
                substitution(
                    itemID: "yogurt",
                    facets: [.init(key: .variant, value: "greek")],
                    ratio: "1:1",
                    tasteImpact: .moderate,
                    textureImpact: .slight,
                    cookingImpact: .moderateAdjustment,
                    nutritionImpact: "Lower fat and more protein",
                    notes: "Whisk in off heat to reduce curdling.",
                    dietary: [.vegetarian]
                ),
                substitution(
                    itemID: "milk",
                    facets: [.init(key: .variant, value: "whole"), .init(key: .base, value: "dairy")],
                    ratio: "1:1",
                    tasteImpact: .slight,
                    textureImpact: .significant,
                    cookingImpact: .moderateAdjustment,
                    nutritionImpact: "Much lower fat",
                    notes: "Sauces will be thinner unless reduced or thickened.",
                    dietary: [.vegetarian]
                )
            ],
            freshnessByStorage: [.refrigerated: 5...10, .frozen: 30...60]
        ),
        item(
            id: "sour-cream",
            name: "Sour Cream",
            category: .dairy,
            defaultUnit: .milliliter,
            defaultQuantity: 250,
            defaultStorage: .refrigerated,
            aliases: ["sour cream"],
            facets: [],
            freshnessByStorage: [.refrigerated: 7...14]
        ),
        item(
            id: "butter",
            name: "Butter",
            category: .oils,
            defaultUnit: .gram,
            defaultQuantity: 250,
            defaultStorage: .refrigerated,
            aliases: ["butter", "salted butter", "unsalted butter"],
            facets: [.variant(["salted", "unsalted"])],
            defaultSelections: [.init(key: .variant, value: "unsalted")],
            substitutions: [
                substitution(
                    itemID: "olive-oil",
                    ratio: "3/4:1",
                    tasteImpact: .slight,
                    textureImpact: .moderate,
                    cookingImpact: .moderateAdjustment,
                    nutritionImpact: "Higher unsaturated fat",
                    notes: "Best in savory cooking and many baked goods, but not where solid fat is essential.",
                    dietary: [.vegan, .dairyFree]
                ),
                substitution(
                    itemID: "vegetable-oil",
                    ratio: "3/4:1",
                    tasteImpact: .slight,
                    textureImpact: .moderate,
                    cookingImpact: .moderateAdjustment,
                    nutritionImpact: "Similar calories with less saturated fat",
                    notes: "Neutral option for cakes, muffins, and sauteing.",
                    dietary: [.vegan, .dairyFree]
                )
            ],
            freshnessByStorage: [.refrigerated: 14...30, .frozen: 90...180]
        ),
        item(
            id: "olive-oil",
            name: "Olive Oil",
            category: .oils,
            defaultUnit: .milliliter,
            defaultQuantity: 500,
            defaultStorage: .pantry,
            aliases: ["olive oil", "extra virgin olive oil"],
            facets: [.variant(["extra virgin"])],
            defaultSelections: [.init(key: .variant, value: "extra virgin")],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 180...365]
        ),
        item(
            id: "vegetable-oil",
            name: "Vegetable Oil",
            category: .oils,
            defaultUnit: .milliliter,
            defaultQuantity: 500,
            defaultStorage: .pantry,
            aliases: ["vegetable oil", "canola oil", "sunflower oil"],
            facets: [.base(["canola", "sunflower"])],
            defaultSelections: [.init(key: .base, value: "canola")],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 180...365]
        ),
        item(
            id: "sesame-oil",
            name: "Sesame Oil",
            category: .oils,
            defaultUnit: .milliliter,
            defaultQuantity: 250,
            defaultStorage: .pantry,
            aliases: ["sesame oil", "toasted sesame oil"],
            facets: [.variant(["toasted", "light"])],
            defaultSelections: [.init(key: .variant, value: "toasted")],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 180...365]
        ),
        item(
            id: "tomato",
            name: "Tomato",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 4,
            defaultStorage: .pantry,
            aliases: ["tomato", "tomatoes"],
            facets: [.variant(["cherry", "plum"])],
            substitutions: [
                substitution(
                    itemID: "canned-tomato",
                    facets: [.init(key: .form, value: "diced")],
                    ratio: "1 can for 3 to 4 tomatoes",
                    tasteImpact: .slight,
                    textureImpact: .moderate,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "Similar overall nutrition",
                    notes: "Best in soups, sauces, and other cooked dishes.",
                    dietary: [.vegan, .vegetarian, .glutenFree, .dairyFree]
                ),
                substitution(
                    itemID: "tomato-paste",
                    facets: [.init(key: .concentration, value: "double")],
                    ratio: "1 tbsp paste plus 3 tbsp water per tomato",
                    tasteImpact: .significant,
                    textureImpact: .moderate,
                    cookingImpact: .moderateAdjustment,
                    nutritionImpact: "More concentrated flavor and sugars",
                    notes: "Use only in cooked recipes where a deeper tomato base is acceptable.",
                    dietary: [.vegan, .vegetarian, .glutenFree, .dairyFree]
                )
            ],
            freshnessByStorage: [.pantry: 3...7, .refrigerated: 5...10]
        ),
        item(
            id: "avocado",
            name: "Avocado",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 2,
            defaultStorage: .pantry,
            aliases: ["avocado", "avocados"],
            facets: [],
            freshnessByStorage: [.pantry: 2...5, .refrigerated: 4...7]
        ),
        item(
            id: "banana",
            name: "Banana",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 6,
            defaultStorage: .pantry,
            aliases: ["banana", "bananas"],
            facets: [],
            freshnessByStorage: [.pantry: 2...6, .refrigerated: 5...10, .frozen: 30...90]
        ),
        item(
            id: "bell-pepper",
            name: "Bell Pepper",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 2,
            defaultStorage: .refrigerated,
            aliases: ["bell pepper", "bell peppers", "capsicum", "red pepper", "green pepper"],
            facets: [.variant(["red", "green", "yellow"])],
            defaultSelections: [.init(key: .variant, value: "red")],
            freshnessByStorage: [.refrigerated: 5...10]
        ),
        item(
            id: "broccoli",
            name: "Broccoli",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 1,
            defaultStorage: .refrigerated,
            aliases: ["broccoli"],
            facets: [],
            freshnessByStorage: [.refrigerated: 4...7, .frozen: 60...180]
        ),
        item(
            id: "carrot",
            name: "Carrot",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 4,
            defaultStorage: .refrigerated,
            aliases: ["carrot", "carrots"],
            facets: [],
            freshnessByStorage: [.refrigerated: 14...30]
        ),
        item(
            id: "cucumber",
            name: "Cucumber",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 1,
            defaultStorage: .refrigerated,
            aliases: ["cucumber", "cucumbers"],
            facets: [],
            freshnessByStorage: [.refrigerated: 5...10]
        ),
        item(
            id: "ginger",
            name: "Ginger",
            category: .produce,
            defaultUnit: .gram,
            defaultQuantity: 100,
            defaultStorage: .refrigerated,
            aliases: ["ginger", "fresh ginger", "ginger root"],
            facets: [],
            freshnessByStorage: [.refrigerated: 14...30, .frozen: 60...180]
        ),
        item(
            id: "green-onion",
            name: "Green Onion",
            category: .produce,
            defaultUnit: .piece,
            defaultQuantity: 4,
            defaultStorage: .refrigerated,
            aliases: ["green onion", "green onions", "spring onion", "spring onions", "scallion", "scallions"],
            facets: [],
            freshnessByStorage: [.refrigerated: 5...10]
        ),
        item(
            id: "lime",
            name: "Lime",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 2,
            defaultStorage: .pantry,
            aliases: ["lime", "limes"],
            facets: [],
            freshnessByStorage: [.pantry: 5...10, .refrigerated: 10...21]
        ),
        item(
            id: "zucchini",
            name: "Zucchini",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 2,
            defaultStorage: .refrigerated,
            aliases: ["zucchini", "courgette"],
            facets: [],
            freshnessByStorage: [.refrigerated: 4...7]
        ),
        item(
            id: "onion",
            name: "Onion",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 2,
            defaultStorage: .pantry,
            aliases: ["onion", "onions"],
            facets: [.variant(["yellow", "red", "white"])],
            defaultSelections: [.init(key: .variant, value: "yellow")],
            freshnessByStorage: [.pantry: 14...45, .refrigerated: 21...60]
        ),
        item(
            id: "garlic",
            name: "Garlic",
            category: .produce,
            defaultUnit: .clove,
            defaultQuantity: 6,
            defaultStorage: .pantry,
            aliases: ["garlic"],
            facets: [.preparation(["whole", "minced"])],
            freshnessByStorage: [.pantry: 21...60, .refrigerated: 30...90, .frozen: 60...180]
        ),
        item(
            id: "potato",
            name: "Potato",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 4,
            defaultStorage: .pantry,
            aliases: ["potato", "potatoes"],
            facets: [.variant(["russet", "red", "sweet"])],
            defaultSelections: [.init(key: .variant, value: "russet")],
            freshnessByStorage: [.pantry: 14...45, .refrigerated: 14...30]
        ),
        item(
            id: "spinach",
            name: "Spinach",
            category: .produce,
            defaultUnit: .gram,
            defaultQuantity: 250,
            defaultStorage: .refrigerated,
            aliases: ["spinach"],
            facets: [.preservation(["fresh", "frozen"]), .preparation(["whole", "chopped"])],
            freshnessByStorage: [.refrigerated: 3...7, .frozen: 60...180]
        ),
        item(
            id: "lemon",
            name: "Lemon",
            category: .produce,
            defaultUnit: .whole,
            defaultQuantity: 2,
            defaultStorage: .pantry,
            aliases: ["lemon", "lemons"],
            facets: [],
            freshnessByStorage: [.pantry: 7...14, .refrigerated: 14...30, .frozen: 30...90]
        ),
        item(
            id: "egg",
            name: "Egg",
            category: .protein,
            defaultUnit: .piece,
            defaultQuantity: 12,
            defaultStorage: .refrigerated,
            aliases: ["egg", "eggs"],
            facets: [.form(["whole"])],
            defaultSelections: [.init(key: .form, value: "whole")],
            substitutions: [
                substitution(
                    itemID: "yogurt",
                    facets: [.init(key: .variant, value: "plain")],
                    ratio: "1/4 cup per egg",
                    tasteImpact: .slight,
                    textureImpact: .moderate,
                    cookingImpact: .moderateAdjustment,
                    nutritionImpact: "Lower protein and cholesterol",
                    notes: "Useful mainly for cakes, muffins, and quick breads, not for egg-forward dishes.",
                    dietary: [.vegetarian]
                )
            ],
            freshnessByStorage: [.refrigerated: 14...28]
        ),
        item(
            id: "chicken-breast",
            name: "Chicken Breast",
            category: .protein,
            defaultUnit: .gram,
            defaultQuantity: 500,
            defaultStorage: .refrigerated,
            aliases: ["chicken", "chicken breast", "chicken breasts", "chicken thigh", "chicken thighs", "boneless skinless chicken breast", "boneless skinless chicken thighs"],
            facets: [.preservation(["fresh", "frozen"])],
            defaultSelections: [.init(key: .preservation, value: "fresh")],
            substitutions: [
                substitution(
                    itemID: "tofu",
                    facets: [.init(key: .variant, value: "extra firm")],
                    ratio: "1:1 by weight",
                    tasteImpact: .significant,
                    textureImpact: .moderate,
                    cookingImpact: .moderateAdjustment,
                    nutritionImpact: "Lower saturated fat, lower protein density",
                    notes: "Best in stir-fries, curries, and saucy dishes.",
                    dietary: [.vegan, .vegetarian, .dairyFree]
                ),
                substitution(
                    itemID: "canned-beans",
                    facets: [.init(key: .base, value: "chickpea")],
                    ratio: "1 can for 400 to 450 g chicken",
                    tasteImpact: .significant,
                    textureImpact: .significant,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "More fiber, less protein per serving",
                    notes: "Best in salads, stews, soups, and curries.",
                    dietary: [.vegan, .vegetarian, .glutenFree, .dairyFree]
                )
            ],
            freshnessByStorage: [.refrigerated: 1...3, .frozen: 60...180]
        ),
        item(
            id: "ground-beef",
            name: "Ground Beef",
            category: .protein,
            defaultUnit: .gram,
            defaultQuantity: 500,
            defaultStorage: .refrigerated,
            aliases: ["ground beef", "mince"],
            facets: [.preservation(["fresh", "frozen"])],
            defaultSelections: [.init(key: .preservation, value: "fresh")],
            substitutions: [
                substitution(
                    itemID: "tofu",
                    facets: [.init(key: .variant, value: "firm")],
                    ratio: "1:1 by weight",
                    tasteImpact: .significant,
                    textureImpact: .moderate,
                    cookingImpact: .moderateAdjustment,
                    nutritionImpact: "Lower saturated fat and more calcium",
                    notes: "Crumble and brown well before seasoning.",
                    dietary: [.vegan, .vegetarian, .dairyFree]
                ),
                substitution(
                    itemID: "canned-beans",
                    facets: [.init(key: .base, value: "black bean")],
                    ratio: "1 can for 400 to 450 g beef",
                    tasteImpact: .significant,
                    textureImpact: .significant,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "More fiber, less fat",
                    notes: "Best in tacos, chilis, and heavily seasoned sauces.",
                    dietary: [.vegan, .vegetarian, .glutenFree, .dairyFree]
                )
            ],
            freshnessByStorage: [.refrigerated: 1...2, .frozen: 60...120]
        ),
        item(
            id: "tofu",
            name: "Tofu",
            category: .protein,
            defaultUnit: .gram,
            defaultQuantity: 400,
            defaultStorage: .refrigerated,
            aliases: ["tofu"],
            facets: [.variant(["firm", "extra firm", "silken"])],
            defaultSelections: [.init(key: .variant, value: "firm")],
            freshnessByStorage: [.refrigerated: 3...7, .frozen: 30...90]
        ),
        item(
            id: "canned-tuna",
            name: "Canned Tuna",
            category: .canned,
            defaultUnit: .can,
            defaultQuantity: 2,
            defaultStorage: .pantry,
            aliases: ["canned tuna", "tuna"],
            facets: [.base(["in water", "in oil"])],
            defaultSelections: [.init(key: .base, value: "in water")],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 2...4]
        ),
        item(
            id: "canned-beans",
            name: "Canned Beans",
            category: .canned,
            defaultUnit: .can,
            defaultQuantity: 1,
            defaultStorage: .pantry,
            aliases: ["canned beans", "beans"],
            facets: [.base(["black bean", "kidney bean", "chickpea"])],
            defaultSelections: [.init(key: .base, value: "black bean")],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 3...5]
        ),
        item(
            id: "canned-tomato",
            name: "Canned Tomato",
            category: .canned,
            defaultUnit: .can,
            defaultQuantity: 1,
            defaultStorage: .pantry,
            aliases: ["canned tomato", "canned tomatoes"],
            facets: [.form(["whole", "diced", "crushed"])],
            defaultSelections: [.init(key: .form, value: "diced")],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 3...5]
        ),
        item(
            id: "tomato-paste",
            name: "Tomato Paste",
            category: .canned,
            defaultUnit: .can,
            defaultQuantity: 1,
            defaultStorage: .pantry,
            aliases: ["tomato paste"],
            facets: [.concentration(["double", "triple"])],
            defaultSelections: [.init(key: .concentration, value: "double")],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 5...10]
        ),
        item(
            id: "coconut-milk",
            name: "Coconut Milk",
            category: .canned,
            defaultUnit: .can,
            defaultQuantity: 1,
            defaultStorage: .pantry,
            aliases: ["coconut milk"],
            facets: [],
            freshnessByStorage: [.pantry: 120...365, .refrigerated: 3...5]
        ),
        item(
            id: "hummus",
            name: "Hummus",
            category: .condiments,
            defaultUnit: .gram,
            defaultQuantity: 250,
            defaultStorage: .refrigerated,
            aliases: ["hummus"],
            facets: [],
            freshnessByStorage: [.refrigerated: 5...10]
        ),
        item(
            id: "miso-paste",
            name: "Miso Paste",
            category: .condiments,
            defaultUnit: .gram,
            defaultQuantity: 200,
            defaultStorage: .refrigerated,
            aliases: ["miso paste", "miso"],
            facets: [],
            freshnessByStorage: [.refrigerated: 30...90]
        ),
        item(
            id: "soy-sauce",
            name: "Soy Sauce",
            category: .condiments,
            defaultUnit: .milliliter,
            defaultQuantity: 250,
            defaultStorage: .pantry,
            aliases: ["soy sauce", "light soy sauce", "dark soy sauce"],
            facets: [.variant(["regular", "light", "dark"])],
            defaultSelections: [.init(key: .variant, value: "regular")],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 180...365]
        ),
        item(
            id: "tomato-sauce",
            name: "Tomato Sauce",
            category: .condiments,
            defaultUnit: .milliliter,
            defaultQuantity: 500,
            defaultStorage: .pantry,
            aliases: ["tomato sauce", "pizza sauce", "passata"],
            facets: [],
            freshnessByStorage: [.pantry: 120...365, .refrigerated: 3...5]
        ),
        item(
            id: "fish-sauce",
            name: "Fish Sauce",
            category: .condiments,
            defaultUnit: .milliliter,
            defaultQuantity: 200,
            defaultStorage: .pantry,
            aliases: ["fish sauce"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 180...365]
        ),
        item(
            id: "lemon-juice",
            name: "Lemon Juice",
            category: .condiments,
            defaultUnit: .milliliter,
            defaultQuantity: 250,
            defaultStorage: .refrigerated,
            aliases: ["lemon juice"],
            facets: [],
            freshnessByStorage: [.refrigerated: 7...21]
        ),
        item(
            id: "broth",
            name: "Broth",
            category: .canned,
            defaultUnit: .liter,
            defaultQuantity: 1,
            defaultStorage: .pantry,
            aliases: ["broth", "stock", "beef broth", "chicken broth", "vegetable broth", "beef stock", "chicken stock", "vegetable stock"],
            facets: [.base(["chicken", "beef", "vegetable"])],
            defaultSelections: [.init(key: .base, value: "chicken")],
            substitutions: [
                substitution(
                    itemID: "broth",
                    facets: [.init(key: .base, value: "vegetable")],
                    ratio: "1:1",
                    tasteImpact: .slight,
                    textureImpact: .none,
                    cookingImpact: .none,
                    nutritionImpact: "Usually slightly lower protein",
                    notes: "Neutral option for soups, grains, and pan sauces.",
                    dietary: [.vegan, .vegetarian, .dairyFree, .glutenFree]
                ),
                substitution(
                    itemID: "broth",
                    facets: [.init(key: .base, value: "beef")],
                    ratio: "1:1",
                    tasteImpact: .moderate,
                    textureImpact: .none,
                    cookingImpact: .none,
                    nutritionImpact: "Similar overall nutrition",
                    notes: "Best in braises and darker sauces, less suitable for delicate dishes.",
                    dietary: [.dairyFree, .glutenFree]
                )
            ],
            freshnessByStorage: [.pantry: 120...365, .refrigerated: 4...7, .frozen: 30...90]
        ),
        item(
            id: "sugar",
            name: "Sugar",
            category: .bakingSupplies,
            defaultUnit: .gram,
            defaultQuantity: 1000,
            defaultStorage: .pantry,
            aliases: ["sugar", "brown sugar"],
            facets: [.variant(["granulated", "brown", "powdered"])],
            defaultSelections: [.init(key: .variant, value: "granulated")],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "cornstarch",
            name: "Cornstarch",
            category: .bakingSupplies,
            defaultUnit: .gram,
            defaultQuantity: 250,
            defaultStorage: .pantry,
            aliases: ["cornstarch", "corn flour"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "honey",
            name: "Honey",
            category: .bakingSupplies,
            defaultUnit: .milliliter,
            defaultQuantity: 340,
            defaultStorage: .pantry,
            aliases: ["honey"],
            facets: [],
            freshnessByStorage: [.pantry: 365...730]
        ),
        item(
            id: "baking-powder",
            name: "Baking Powder",
            category: .bakingSupplies,
            defaultUnit: .gram,
            defaultQuantity: 100,
            defaultStorage: .pantry,
            aliases: ["baking powder"],
            facets: [],
            freshnessByStorage: [.pantry: 120...240]
        ),
        item(
            id: "baking-soda",
            name: "Baking Soda",
            category: .bakingSupplies,
            defaultUnit: .gram,
            defaultQuantity: 100,
            defaultStorage: .pantry,
            aliases: ["baking soda"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "vanilla-extract",
            name: "Vanilla Extract",
            category: .bakingSupplies,
            defaultUnit: .milliliter,
            defaultQuantity: 50,
            defaultStorage: .pantry,
            aliases: ["vanilla extract", "vanilla"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "salt",
            name: "Salt",
            category: .spices,
            defaultUnit: .gram,
            defaultQuantity: 250,
            defaultStorage: .pantry,
            aliases: ["salt", "sea salt", "kosher salt"],
            facets: [.variant(["table", "sea", "kosher"])],
            defaultSelections: [.init(key: .variant, value: "table")],
            freshnessByStorage: [.pantry: 365...730]
        ),
        item(
            id: "black-pepper",
            name: "Black Pepper",
            category: .spices,
            defaultUnit: .gram,
            defaultQuantity: 50,
            defaultStorage: .pantry,
            aliases: ["black pepper", "pepper"],
            facets: [.form(["ground", "whole"])],
            defaultSelections: [.init(key: .form, value: "ground")],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "cinnamon",
            name: "Cinnamon",
            category: .spices,
            defaultUnit: .gram,
            defaultQuantity: 50,
            defaultStorage: .pantry,
            aliases: ["cinnamon"],
            facets: [.form(["ground", "stick"])],
            defaultSelections: [.init(key: .form, value: "ground")],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "basil",
            name: "Basil",
            category: .spices,
            defaultUnit: .bunch,
            defaultQuantity: 1,
            defaultStorage: .refrigerated,
            aliases: ["basil", "fresh basil"],
            facets: [],
            freshnessByStorage: [.refrigerated: 3...7, .frozen: 30...90]
        ),
        item(
            id: "cilantro",
            name: "Cilantro",
            category: .spices,
            defaultUnit: .bunch,
            defaultQuantity: 1,
            defaultStorage: .refrigerated,
            aliases: ["cilantro", "coriander leaves", "fresh coriander"],
            facets: [],
            freshnessByStorage: [.refrigerated: 3...7, .frozen: 30...90]
        ),
        item(
            id: "chili-powder",
            name: "Chili Powder",
            category: .spices,
            defaultUnit: .gram,
            defaultQuantity: 50,
            defaultStorage: .pantry,
            aliases: ["chili powder", "chilli powder"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "cumin",
            name: "Cumin",
            category: .spices,
            defaultUnit: .gram,
            defaultQuantity: 50,
            defaultStorage: .pantry,
            aliases: ["cumin", "ground cumin"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "garam-masala",
            name: "Garam Masala",
            category: .spices,
            defaultUnit: .gram,
            defaultQuantity: 50,
            defaultStorage: .pantry,
            aliases: ["garam masala"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "oregano",
            name: "Oregano",
            category: .spices,
            defaultUnit: .gram,
            defaultQuantity: 30,
            defaultStorage: .pantry,
            aliases: ["oregano", "dried oregano"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "parsley",
            name: "Parsley",
            category: .spices,
            defaultUnit: .bunch,
            defaultQuantity: 1,
            defaultStorage: .refrigerated,
            aliases: ["parsley", "fresh parsley"],
            facets: [],
            freshnessByStorage: [.refrigerated: 3...7, .frozen: 30...90]
        ),
        item(
            id: "red-pepper-flakes",
            name: "Red Pepper Flakes",
            category: .spices,
            defaultUnit: .gram,
            defaultQuantity: 25,
            defaultStorage: .pantry,
            aliases: ["red pepper flakes", "chili flakes", "chilli flakes"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "thyme",
            name: "Thyme",
            category: .spices,
            defaultUnit: .gram,
            defaultQuantity: 25,
            defaultStorage: .pantry,
            aliases: ["thyme", "fresh thyme", "dried thyme"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 5...10]
        ),
        item(
            id: "turmeric",
            name: "Turmeric",
            category: .spices,
            defaultUnit: .gram,
            defaultQuantity: 50,
            defaultStorage: .pantry,
            aliases: ["turmeric", "ground turmeric"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "paprika",
            name: "Paprika",
            category: .spices,
            defaultUnit: .gram,
            defaultQuantity: 50,
            defaultStorage: .pantry,
            aliases: ["paprika", "smoked paprika"],
            facets: [.variant(["sweet", "smoked", "hot"])],
            defaultSelections: [.init(key: .variant, value: "sweet")],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "bread",
            name: "Bread",
            category: .grains,
            defaultUnit: .slice,
            defaultQuantity: 1,
            defaultStorage: .pantry,
            aliases: ["bread", "loaf"],
            facets: [.variant(["white", "wholemeal", "sourdough"]), .form(["loaf", "sliced"])],
            defaultSelections: [.init(key: .variant, value: "white"), .init(key: .form, value: "loaf")],
            substitutions: [
                substitution(
                    itemID: "tortilla",
                    facets: [.init(key: .base, value: "wheat")],
                    ratio: "1 tortilla per 2 slices",
                    tasteImpact: .moderate,
                    textureImpact: .moderate,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "Usually similar calories with less thickness",
                    notes: "Best for wraps, quesadillas, and quick sandwiches.",
                    dietary: nil
                )
            ],
            unitOverrides: [.form: ["loaf": .loaf, "sliced": .slice]],
            freshnessByStorage: [.pantry: 3...7, .refrigerated: 5...10, .frozen: 30...90]
        ),
        item(
            id: "pizza-dough",
            name: "Pizza Dough",
            category: .grains,
            defaultUnit: .pound,
            defaultQuantity: 1,
            defaultStorage: .refrigerated,
            aliases: ["pizza dough"],
            facets: [],
            freshnessByStorage: [.refrigerated: 2...5, .frozen: 30...90]
        ),
        item(
            id: "pita",
            name: "Pita",
            category: .grains,
            defaultUnit: .piece,
            defaultQuantity: 4,
            defaultStorage: .pantry,
            aliases: ["pita", "pita bread"],
            facets: [],
            freshnessByStorage: [.pantry: 3...7, .refrigerated: 5...10, .frozen: 30...90]
        ),
        item(
            id: "red-lentils",
            name: "Red Lentils",
            category: .grains,
            defaultUnit: .gram,
            defaultQuantity: 500,
            defaultStorage: .pantry,
            aliases: ["red lentils", "red lentil", "lentils"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "tortilla",
            name: "Tortilla",
            category: .grains,
            defaultUnit: .piece,
            defaultQuantity: 8,
            defaultStorage: .pantry,
            aliases: ["tortilla", "tortillas", "wrap"],
            facets: [.base(["wheat", "corn"])],
            defaultSelections: [.init(key: .base, value: "wheat")],
            freshnessByStorage: [.pantry: 7...21, .refrigerated: 14...30, .frozen: 30...90]
        ),
        item(
            id: "rice-noodles",
            name: "Rice Noodles",
            category: .pasta,
            defaultUnit: .gram,
            defaultQuantity: 250,
            defaultStorage: .pantry,
            aliases: ["rice noodles", "rice noodle"],
            facets: [],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "muffin",
            name: "Muffin",
            category: .grains,
            defaultUnit: .piece,
            defaultQuantity: 4,
            defaultStorage: .pantry,
            aliases: ["muffin", "muffins"],
            facets: [.variant(["blueberry", "chocolate chip", "bran"]), .preservation(["fresh", "frozen"])],
            defaultSelections: [.init(key: .variant, value: "blueberry"), .init(key: .preservation, value: "fresh")],
            freshnessByStorage: [.pantry: 2...5, .refrigerated: 4...7, .frozen: 30...90]
        ),
        item(
            id: "peanuts",
            name: "Peanuts",
            category: .nuts,
            defaultUnit: .gram,
            defaultQuantity: 250,
            defaultStorage: .pantry,
            aliases: ["peanuts", "peanut"],
            facets: [],
            freshnessByStorage: [.pantry: 90...180, .refrigerated: 120...240]
        ),
        item(
            id: "shrimp",
            name: "Shrimp",
            category: .protein,
            defaultUnit: .gram,
            defaultQuantity: 300,
            defaultStorage: .refrigerated,
            aliases: ["shrimp", "prawn", "prawns"],
            facets: [.preservation(["fresh", "frozen"])],
            defaultSelections: [.init(key: .preservation, value: "fresh")],
            freshnessByStorage: [.refrigerated: 1...2, .frozen: 60...180]
        ),
        item(
            id: "bean-sprouts",
            name: "Bean Sprouts",
            category: .produce,
            defaultUnit: .gram,
            defaultQuantity: 200,
            defaultStorage: .refrigerated,
            aliases: ["bean sprouts", "bean sprout"],
            facets: [],
            freshnessByStorage: [.refrigerated: 2...5]
        ),
        item(
            id: "water",
            name: "Water",
            category: .other,
            defaultUnit: .liter,
            defaultQuantity: 1,
            defaultStorage: .pantry,
            aliases: ["water"],
            facets: [],
            freshnessByStorage: [.pantry: 365...730]
        )
    ]

    private static let itemsByID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    private static let aliasIndex: [String: String] = {
        var result: [String: String] = [:]
        for item in allItems {
            result[normalizeLookupKey(item.name)] = item.id
            for alias in item.aliases {
                result[normalizeLookupKey(alias)] = item.id
            }
        }
        return result
    }()

    static func item(id: String?) -> PantryCatalogItemDefinition? {
        guard let id else { return nil }
        return itemsByID[id]
    }

    static func resolveExact(name: String) -> PantryCatalogItemDefinition? {
        let normalized = normalizeLookupKey(name)
        guard let id = aliasIndex[normalized] else { return nil }
        return itemsByID[id]
    }

    static func search(_ query: String) -> [PantryCatalogItemDefinition] {
        let normalizedQuery = normalizeLookupKey(query)
        guard !normalizedQuery.isEmpty else {
            return allItems.sorted { $0.name < $1.name }
        }

        return allItems
            .filter { item in
                normalizeLookupKey(item.name).contains(normalizedQuery) ||
                item.aliases.contains(where: { normalizeLookupKey($0).contains(normalizedQuery) })
            }
            .sorted { $0.name < $1.name }
    }

    private static func normalizeLookupKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func item(
        id: String,
        name: String,
        category: FoodCategory,
        defaultUnit: MeasurementUnit?,
        defaultQuantity: Double?,
        defaultStorage: PantryStorage,
        aliases: [String],
        facets: [PantryFacetDefinition],
        defaultSelections: [PantryFacetSelection] = [],
        substitutions: [PantrySubstitutionDefinition] = [],
        unitOverrides: [PantryFacetKey: [String: MeasurementUnit]] = [:],
        freshnessByStorage: [PantryStorage: ClosedRange<Int>]
    ) -> PantryCatalogItemDefinition {
        PantryCatalogItemDefinition(
            id: id,
            name: name,
            category: category,
            defaultUnit: defaultUnit,
            defaultQuantity: defaultQuantity,
            defaultStorage: defaultStorage,
            aliases: aliases,
            facets: facets,
            defaultSelections: defaultSelections,
            substitutions: substitutions,
            unitOverrides: unitOverrides,
            freshnessByStorage: freshnessByStorage
        )
    }

    private static func substitution(
        itemID: String,
        facets: [PantryFacetSelection] = [],
        ratio: String,
        tasteImpact: SubstitutionImpact,
        textureImpact: SubstitutionImpact,
        cookingImpact: CookingImpact,
        nutritionImpact: String? = nil,
        notes: String? = nil,
        dietary: [DietaryTag]? = nil
    ) -> PantrySubstitutionDefinition {
        PantrySubstitutionDefinition(
            substituteItemID: itemID,
            substituteFacets: facets,
            ratio: ratio,
            tasteImpact: tasteImpact,
            textureImpact: textureImpact,
            cookingImpact: cookingImpact,
            nutritionImpact: nutritionImpact,
            notes: notes,
            dietary: dietary
        )
    }
}

private extension PantryFacetDefinition {
    static func variant(_ options: [String]) -> PantryFacetDefinition {
        PantryFacetDefinition(key: .variant, options: options)
    }

    static func form(_ options: [String]) -> PantryFacetDefinition {
        PantryFacetDefinition(key: .form, options: options)
    }

    static func preservation(_ options: [String]) -> PantryFacetDefinition {
        PantryFacetDefinition(key: .preservation, options: options)
    }

    static func processing(_ options: [String]) -> PantryFacetDefinition {
        PantryFacetDefinition(key: .processing, options: options)
    }

    static func preparation(_ options: [String]) -> PantryFacetDefinition {
        PantryFacetDefinition(key: .preparation, options: options)
    }

    static func texture(_ options: [String]) -> PantryFacetDefinition {
        PantryFacetDefinition(key: .texture, options: options)
    }

    static func concentration(_ options: [String]) -> PantryFacetDefinition {
        PantryFacetDefinition(key: .concentration, options: options)
    }

    static func base(_ options: [String]) -> PantryFacetDefinition {
        PantryFacetDefinition(key: .base, options: options)
    }
}