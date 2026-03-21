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

struct PantryFacetDefinition: Hashable, Sendable {
    let key: PantryFacetKey
    let options: [String]
}

struct PantryCatalogItemDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let category: FoodCategory
    let defaultUnit: MeasurementUnit?
    let defaultStorage: PantryStorage
    let aliases: [String]
    let facets: [PantryFacetDefinition]
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
            defaultStorage: .pantry,
            aliases: ["flour", "all purpose flour", "all-purpose flour"],
            facets: [.variant(["all-purpose", "bread", "cake", "self-rising"]), .texture(["fine"])],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 240...365, .frozen: 365...540]
        ),
        item(
            id: "rice",
            name: "Rice",
            category: .grains,
            defaultUnit: .gram,
            defaultStorage: .pantry,
            aliases: ["rice"],
            facets: [.variant(["white", "brown", "jasmine", "basmati"])],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 240...365, .frozen: 365...540]
        ),
        item(
            id: "pasta",
            name: "Pasta",
            category: .pasta,
            defaultUnit: .gram,
            defaultStorage: .pantry,
            aliases: ["pasta", "noodles"],
            facets: [.form(["spaghetti", "penne", "fusilli"]), .base(["wheat", "chickpea"])],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 240...365, .frozen: 365...540]
        ),
        item(
            id: "oats",
            name: "Oats",
            category: .grains,
            defaultUnit: .gram,
            defaultStorage: .pantry,
            aliases: ["oats", "rolled oats"],
            facets: [.form(["rolled", "steel-cut", "quick"])],
            freshnessByStorage: [.pantry: 120...240, .refrigerated: 180...300, .frozen: 240...365]
        ),
        item(
            id: "milk",
            name: "Milk",
            category: .dairy,
            defaultUnit: .liter,
            defaultStorage: .refrigerated,
            aliases: ["milk", "whole milk", "skim milk"],
            facets: [.variant(["whole", "semi-skimmed", "skim"]), .preservation(["fresh", "shelf-stable"]), .base(["dairy", "oat", "almond", "soy"])],
            freshnessByStorage: [.pantry: 30...120, .refrigerated: 5...10, .frozen: 30...90]
        ),
        item(
            id: "yogurt",
            name: "Yogurt",
            category: .dairy,
            defaultUnit: .gram,
            defaultStorage: .refrigerated,
            aliases: ["yogurt", "yoghurt", "greek yogurt"],
            facets: [.variant(["plain", "greek"]), .base(["dairy", "coconut"]), .preservation(["fresh"])],
            freshnessByStorage: [.refrigerated: 5...14, .frozen: 30...60]
        ),
        item(
            id: "cheese",
            name: "Cheese",
            category: .dairy,
            defaultUnit: .gram,
            defaultStorage: .refrigerated,
            aliases: ["cheese", "cheddar", "mozzarella"],
            facets: [.variant(["cheddar", "mozzarella", "parmesan"]), .form(["block", "shredded", "sliced"])],
            freshnessByStorage: [.refrigerated: 7...30, .frozen: 60...180]
        ),
        item(
            id: "cream",
            name: "Cream",
            category: .dairy,
            defaultUnit: .milliliter,
            defaultStorage: .refrigerated,
            aliases: ["cream", "double cream", "heavy cream"],
            facets: [.variant(["single", "double", "heavy"])],
            freshnessByStorage: [.refrigerated: 5...10, .frozen: 30...60]
        ),
        item(
            id: "butter",
            name: "Butter",
            category: .oils,
            defaultUnit: .gram,
            defaultStorage: .refrigerated,
            aliases: ["butter", "salted butter", "unsalted butter"],
            facets: [.variant(["salted", "unsalted"])],
            freshnessByStorage: [.refrigerated: 14...30, .frozen: 90...180]
        ),
        item(
            id: "olive-oil",
            name: "Olive Oil",
            category: .oils,
            defaultUnit: .milliliter,
            defaultStorage: .pantry,
            aliases: ["olive oil", "extra virgin olive oil"],
            facets: [.variant(["extra virgin"])],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 180...365]
        ),
        item(
            id: "vegetable-oil",
            name: "Vegetable Oil",
            category: .oils,
            defaultUnit: .milliliter,
            defaultStorage: .pantry,
            aliases: ["vegetable oil", "canola oil", "sunflower oil"],
            facets: [.base(["canola", "sunflower"])],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 180...365]
        ),
        item(
            id: "tomato",
            name: "Tomato",
            category: .produce,
            defaultUnit: .whole,
            defaultStorage: .pantry,
            aliases: ["tomato", "tomatoes"],
            facets: [.variant(["cherry", "plum"])],
            freshnessByStorage: [.pantry: 3...7, .refrigerated: 5...10]
        ),
        item(
            id: "onion",
            name: "Onion",
            category: .produce,
            defaultUnit: .whole,
            defaultStorage: .pantry,
            aliases: ["onion", "onions"],
            facets: [.variant(["yellow", "red", "white"])],
            freshnessByStorage: [.pantry: 14...45, .refrigerated: 21...60]
        ),
        item(
            id: "garlic",
            name: "Garlic",
            category: .produce,
            defaultUnit: .clove,
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
            defaultStorage: .pantry,
            aliases: ["potato", "potatoes"],
            facets: [.variant(["russet", "red", "sweet"])],
            freshnessByStorage: [.pantry: 14...45, .refrigerated: 14...30]
        ),
        item(
            id: "spinach",
            name: "Spinach",
            category: .produce,
            defaultUnit: .gram,
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
            defaultStorage: .refrigerated,
            aliases: ["egg", "eggs"],
            facets: [.form(["whole"])],
            freshnessByStorage: [.refrigerated: 14...28]
        ),
        item(
            id: "chicken-breast",
            name: "Chicken Breast",
            category: .protein,
            defaultUnit: .gram,
            defaultStorage: .refrigerated,
            aliases: ["chicken", "chicken breast"],
            facets: [.preservation(["fresh", "frozen"])],
            freshnessByStorage: [.refrigerated: 1...3, .frozen: 60...180]
        ),
        item(
            id: "ground-beef",
            name: "Ground Beef",
            category: .protein,
            defaultUnit: .gram,
            defaultStorage: .refrigerated,
            aliases: ["ground beef", "mince"],
            facets: [.preservation(["fresh", "frozen"])],
            freshnessByStorage: [.refrigerated: 1...2, .frozen: 60...120]
        ),
        item(
            id: "tofu",
            name: "Tofu",
            category: .protein,
            defaultUnit: .gram,
            defaultStorage: .refrigerated,
            aliases: ["tofu"],
            facets: [.variant(["firm", "extra firm", "silken"])],
            freshnessByStorage: [.refrigerated: 3...7, .frozen: 30...90]
        ),
        item(
            id: "canned-tuna",
            name: "Canned Tuna",
            category: .canned,
            defaultUnit: .can,
            defaultStorage: .pantry,
            aliases: ["canned tuna", "tuna"],
            facets: [.base(["in water", "in oil"])],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 2...4]
        ),
        item(
            id: "canned-beans",
            name: "Canned Beans",
            category: .canned,
            defaultUnit: .can,
            defaultStorage: .pantry,
            aliases: ["canned beans", "beans"],
            facets: [.base(["black bean", "kidney bean", "chickpea"])],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 3...5]
        ),
        item(
            id: "canned-tomato",
            name: "Canned Tomato",
            category: .canned,
            defaultUnit: .can,
            defaultStorage: .pantry,
            aliases: ["canned tomato", "canned tomatoes"],
            facets: [.form(["whole", "diced", "crushed"])],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 3...5]
        ),
        item(
            id: "tomato-paste",
            name: "Tomato Paste",
            category: .canned,
            defaultUnit: .can,
            defaultStorage: .pantry,
            aliases: ["tomato paste"],
            facets: [.concentration(["double", "triple"])],
            freshnessByStorage: [.pantry: 180...365, .refrigerated: 5...10]
        ),
        item(
            id: "broth",
            name: "Broth",
            category: .canned,
            defaultUnit: .liter,
            defaultStorage: .pantry,
            aliases: ["broth", "stock"],
            facets: [.base(["chicken", "beef", "vegetable"])],
            freshnessByStorage: [.pantry: 120...365, .refrigerated: 4...7, .frozen: 30...90]
        ),
        item(
            id: "sugar",
            name: "Sugar",
            category: .bakingSupplies,
            defaultUnit: .gram,
            defaultStorage: .pantry,
            aliases: ["sugar", "brown sugar"],
            facets: [.variant(["granulated", "brown", "powdered"])],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "baking-powder",
            name: "Baking Powder",
            category: .bakingSupplies,
            defaultUnit: .gram,
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
            defaultStorage: .pantry,
            aliases: ["salt", "sea salt", "kosher salt"],
            facets: [.variant(["table", "sea", "kosher"])],
            freshnessByStorage: [.pantry: 365...730]
        ),
        item(
            id: "black-pepper",
            name: "Black Pepper",
            category: .spices,
            defaultUnit: .gram,
            defaultStorage: .pantry,
            aliases: ["black pepper", "pepper"],
            facets: [.form(["ground", "whole"])],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "cinnamon",
            name: "Cinnamon",
            category: .spices,
            defaultUnit: .gram,
            defaultStorage: .pantry,
            aliases: ["cinnamon"],
            facets: [.form(["ground", "stick"])],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "paprika",
            name: "Paprika",
            category: .spices,
            defaultUnit: .gram,
            defaultStorage: .pantry,
            aliases: ["paprika", "smoked paprika"],
            facets: [.variant(["sweet", "smoked", "hot"])],
            freshnessByStorage: [.pantry: 180...365]
        ),
        item(
            id: "bread",
            name: "Bread",
            category: .grains,
            defaultUnit: .slice,
            defaultStorage: .pantry,
            aliases: ["bread", "loaf"],
            facets: [.variant(["white", "wholemeal", "sourdough"]), .form(["loaf", "sliced"])],
            freshnessByStorage: [.pantry: 3...7, .refrigerated: 5...10, .frozen: 30...90]
        ),
        item(
            id: "tortilla",
            name: "Tortilla",
            category: .grains,
            defaultUnit: .piece,
            defaultStorage: .pantry,
            aliases: ["tortilla", "tortillas", "wrap"],
            facets: [.base(["wheat", "corn"])],
            freshnessByStorage: [.pantry: 7...21, .refrigerated: 14...30, .frozen: 30...90]
        ),
        item(
            id: "muffin",
            name: "Muffin",
            category: .grains,
            defaultUnit: .piece,
            defaultStorage: .pantry,
            aliases: ["muffin", "muffins"],
            facets: [.variant(["blueberry", "chocolate chip", "bran"]), .preservation(["fresh", "frozen"])],
            freshnessByStorage: [.pantry: 2...5, .refrigerated: 4...7, .frozen: 30...90]
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
            .sorted { lhs, rhs in
                let lhsStartsWithQuery = normalizeLookupKey(lhs.name).hasPrefix(normalizedQuery)
                let rhsStartsWithQuery = normalizeLookupKey(rhs.name).hasPrefix(normalizedQuery)
                if lhsStartsWithQuery != rhsStartsWithQuery {
                    return lhsStartsWithQuery
                }
                return lhs.name < rhs.name
            }
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
        defaultStorage: PantryStorage,
        aliases: [String],
        facets: [PantryFacetDefinition],
        freshnessByStorage: [PantryStorage: ClosedRange<Int>]
    ) -> PantryCatalogItemDefinition {
        PantryCatalogItemDefinition(
            id: id,
            name: name,
            category: category,
            defaultUnit: defaultUnit,
            defaultStorage: defaultStorage,
            aliases: aliases,
            facets: facets,
            freshnessByStorage: freshnessByStorage
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