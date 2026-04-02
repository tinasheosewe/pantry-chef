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

enum PantryQuantityMode: String, Codable, CaseIterable, Sendable {
    case exact
    case presenceOnly

    var title: String {
        switch self {
        case .exact:
            return "Exact quantity"
        case .presenceOnly:
            return "Presence only"
        }
    }

    static func merged(_ lhs: PantryQuantityMode, _ rhs: PantryQuantityMode) -> PantryQuantityMode {
        if lhs == .presenceOnly || rhs == .presenceOnly {
            return .presenceOnly
        }
        return .exact
    }
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

struct PantryCatalogItemDefinition: Identifiable, Hashable, Sendable, Codable {
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

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, category, defaultUnit, defaultQuantity, defaultStorage
        case aliases, facets, defaultSelections, freshnessByStorage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(FoodCategory.self, forKey: .category)
        defaultUnit = try c.decodeIfPresent(MeasurementUnit.self, forKey: .defaultUnit)
        defaultQuantity = try c.decodeIfPresent(Double.self, forKey: .defaultQuantity)
        defaultStorage = try c.decode(PantryStorage.self, forKey: .defaultStorage)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        facets = try c.decodeIfPresent([PantryFacetDefinition].self, forKey: .facets) ?? []
        defaultSelections = try c.decodeIfPresent([PantryFacetSelection].self, forKey: .defaultSelections) ?? []
        substitutions = []
        unitOverrides = [:]

        // Decode freshnessByStorage: { "Pantry": [180, 365], ... } → [PantryStorage: ClosedRange<Int>]
        let rawFreshness = try c.decodeIfPresent([String: [Int]].self, forKey: .freshnessByStorage) ?? [:]
        var parsed: [PantryStorage: ClosedRange<Int>] = [:]
        for (key, value) in rawFreshness {
            guard let storage = PantryStorage(rawValue: key), value.count == 2 else { continue }
            parsed[storage] = value[0]...value[1]
        }
        freshnessByStorage = parsed
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(defaultUnit, forKey: .defaultUnit)
        try c.encodeIfPresent(defaultQuantity, forKey: .defaultQuantity)
        try c.encode(defaultStorage, forKey: .defaultStorage)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(facets, forKey: .facets)
        try c.encode(defaultSelections, forKey: .defaultSelections)
        var rawFreshness: [String: [Int]] = [:]
        for (storage, range) in freshnessByStorage {
            rawFreshness[storage.rawValue] = [range.lowerBound, range.upperBound]
        }
        try c.encode(rawFreshness, forKey: .freshnessByStorage)
    }

    // MARK: - Memberwise init (for builder)

    init(
        id: String,
        name: String,
        category: FoodCategory,
        defaultUnit: MeasurementUnit?,
        defaultQuantity: Double?,
        defaultStorage: PantryStorage,
        aliases: [String],
        facets: [PantryFacetDefinition],
        defaultSelections: [PantryFacetSelection],
        substitutions: [PantrySubstitutionDefinition],
        unitOverrides: [PantryFacetKey: [String: MeasurementUnit]],
        freshnessByStorage: [PantryStorage: ClosedRange<Int>]
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.defaultUnit = defaultUnit
        self.defaultQuantity = defaultQuantity
        self.defaultStorage = defaultStorage
        self.aliases = aliases
        self.facets = facets
        self.defaultSelections = defaultSelections
        self.substitutions = substitutions
        self.unitOverrides = unitOverrides
        self.freshnessByStorage = freshnessByStorage
    }

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
        let orderedSelections = orderedKeys.compactMap { key in
            selections.first(where: { $0.key == key })
        }
        guard !orderedSelections.isEmpty else { return name }

        var prefixWords: [String] = []
        var suffixWords: [String] = []

        for selection in orderedSelections {
            if Self.suffixFacetValues.contains(selection.value.lowercased()) {
                suffixWords.append(selection.value)
            } else {
                prefixWords.append(selection.value)
            }
        }

        return (prefixWords + [name] + suffixWords).map(Self.titleCase).joined(separator: " ")
    }

    private static func titleCase(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static let suffixFacetValues: Set<String> = [
        "breast", "thigh", "wing", "drumstick", "tenderloin", "sirloin", "shank", "brisket",
        "rib", "ribs", "loin", "shoulder", "belly", "leg", "chop", "chops", "fillet", "stew"
    ]
}

enum PantryCatalog {
    /// Universal ingredient modifiers that should be stripped during normalization.
    /// These are common qualifiers that apply across many ingredient types.
    static let universalModifiers: Set<String> = [
        // Size
        "large", "small", "medium",
        // Preservation
        "fresh", "dried", "frozen", "canned", "packed",
        // Preparation
        "whole", "chopped", "diced", "minced", "sliced", "ground",
        // State
        "raw", "cooked", "boneless", "skinless",
        // Quality
        "organic", "ripe", "baby",
        // Fat content
        "extra", "virgin", "light", "heavy",
        "low fat", "low-fat", "fat free", "fat-free",
        "unsalted", "salted",
        // Flour types
        "plain", "all purpose", "all-purpose", "self rising", "self-rising", "unbleached",
        // Texture
        "fine", "coarse", "firm", "soft", "thin", "thick"
    ]

    /// Universal synonym groups for cross-regional ingredient naming.
    /// These connect equivalent ingredients that may have different names across regions.
    static let universalSynonyms: [[String]] = [
        ["green onion", "scallion", "spring onion"],
        ["shallot", "french shallot"],
        ["bell pepper", "capsicum", "sweet pepper"],
        ["chili pepper", "chilli", "chile", "hot pepper"],
        ["jalapeno", "jalapeño"],
        ["cilantro", "coriander", "coriander leaf"],
        ["parsley", "flat leaf parsley", "italian parsley"],
        ["cornstarch", "corn starch", "corn flour"],
        ["potato starch", "potato flour"],
        ["shrimp", "prawn"],
        ["heavy cream", "whipping cream", "double cream"],
        ["sour cream", "crème fraîche"],
        ["greek yogurt", "greek yoghurt", "strained yogurt"],
        ["all purpose flour", "plain flour", "ap flour"],
        ["bread flour", "strong flour"],
        ["olive oil", "extra virgin olive oil", "evoo"],
        ["vegetable oil", "canola oil", "neutral oil"],
        ["soy sauce", "shoyu", "tamari"],
        ["fish sauce", "nam pla"],
        ["sugar", "granulated sugar", "white sugar"],
        ["brown sugar", "dark brown sugar", "light brown sugar"],
        ["powdered sugar", "confectioner sugar", "icing sugar"],
        ["garbanzo", "chickpea"],
        ["eggplant", "aubergine"],
        ["zucchini", "courgette"],
        ["arugula", "rocket"],
        ["beet", "beetroot"],
        ["stock", "broth"],
        ["chicken stock", "chicken broth"],
        ["beef stock", "beef broth"],
        ["vegetable stock", "vegetable broth"],
        ["baking soda", "bicarbonate of soda", "bicarb"],
        ["baking powder", "raising agent"],
        ["cream cheese", "neufchatel"]
    ]

    static let allItems: [PantryCatalogItemDefinition] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            fatalError("catalog.json not found in app bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([PantryCatalogItemDefinition].self, from: data)
        } catch {
            fatalError("Failed to decode catalog.json: \(error)")
        }
    }()

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
        IngredientLexicon.lookupKey(value)
    }
}

