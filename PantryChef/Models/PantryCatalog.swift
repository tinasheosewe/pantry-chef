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
    var facets: [PantryFacetDefinition]
    let defaultSelections: [PantryFacetSelection]
    let substitutions: [PantrySubstitutionDefinition]
    let unitOverrides: [PantryFacetKey: [String: MeasurementUnit]]
    let freshnessByStorage: [PantryStorage: ClosedRange<Int>]
    let isUserDefined: Bool

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, category, defaultUnit, defaultQuantity, defaultStorage
        case aliases, facets, defaultSelections, freshnessByStorage, isUserDefined
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
        isUserDefined = try c.decodeIfPresent(Bool.self, forKey: .isUserDefined) ?? false

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
        try c.encode(isUserDefined, forKey: .isUserDefined)
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
        freshnessByStorage: [PantryStorage: ClosedRange<Int>],
        isUserDefined: Bool = false
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
        self.isUserDefined = isUserDefined
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
        guard !orderedSelections.isEmpty else { return titleCasedName }

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

    var titleCasedName: String {
        Self.titleCase(name)
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

enum UserCatalogError: LocalizedError, Equatable {
    case idCollision(existingItemID: String)
    case nameCollision(existingItemID: String, existingItemName: String)
    case duplicateUserItem(existingItemID: String)
    case duplicateFacetValue(itemName: String, facetKey: String, value: String)
    case itemNotFound(itemID: String)

    var errorDescription: String? {
        switch self {
        case .idCollision(let existingItemID):
            return "An item with ID \"\(existingItemID)\" already exists in the catalog."
        case .nameCollision(let _, let existingItemName):
            return "\"\(existingItemName)\" already exists in the catalog. Add a facet value to that item instead."
        case .duplicateUserItem(let existingItemID):
            return "A custom item with ID \"\(existingItemID)\" already exists."
        case .duplicateFacetValue(let itemName, let facetKey, let value):
            return "\"\(value)\" already exists for \(facetKey) on \(itemName)."
        case .itemNotFound(let itemID):
            return "Item \"\(itemID)\" not found in catalog."
        }
    }
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

    // MARK: - Bundle items (immutable)

    private static let bundleItems: [PantryCatalogItemDefinition] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            fatalError("catalog.json not found in app bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([PantryCatalogItemDefinition].self, from: data)
            return items
        } catch {
            fatalError("Failed to decode catalog.json: \(error)")
        }
    }()

    // MARK: - User data (mutable)

    private(set) static var userItems: [PantryCatalogItemDefinition] = []
    private(set) static var facetExtensions: [String: [String: [String]]] = [:]
    private static var store: UserCatalogStoreProtocol?

    // MARK: - Merged items + indices

    private(set) static var allItems: [PantryCatalogItemDefinition] = {
        bundleItems
    }()

    private(set) static var itemsByID: [String: PantryCatalogItemDefinition] = {
        Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
    }()
    private(set) static var aliasIndex: [String: String] = {
        buildAliasIndex(from: allItems)
    }()
    private(set) static var facetOptionIndex: [String: [String]] = {
        buildFacetOptionIndex(from: allItems)
    }()
    static var nameKeySet: Set<String> = {
        Set(allItems.map { normalizeLookupKey($0.name) })
    }()
    static var facetTokenToItems: [String: [(itemID: String, key: PantryFacetKey, value: String)]] = {
        buildFacetTokenToItems(from: allItems)
    }()
    static var tokenIndex: [String: Set<String>] = {
        buildTokenIndex(from: allItems)
    }()

    // MARK: - Index builders

    private static func buildAliasIndex(from items: [PantryCatalogItemDefinition]) -> [String: String] {
        var result: [String: String] = [:]
        for item in items {
            result[normalizeLookupKey(item.name)] = item.id
            for alias in item.aliases {
                result[normalizeLookupKey(alias)] = item.id
            }
        }
        return result
    }

    private static func buildFacetOptionIndex(from items: [PantryCatalogItemDefinition]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for item in items {
            for facet in item.facets {
                for option in facet.options {
                    let key = normalizeLookupKey(option)
                    result[key, default: []].append(item.id)
                }
            }
        }
        return result
    }

    private static func buildFacetTokenToItems(from items: [PantryCatalogItemDefinition]) -> [String: [(itemID: String, key: PantryFacetKey, value: String)]] {
        var result: [String: [(itemID: String, key: PantryFacetKey, value: String)]] = [:]
        for item in items {
            for facet in item.facets {
                for option in facet.options {
                    let key = normalizeLookupKey(option)
                    result[key, default: []].append((itemID: item.id, key: facet.key, value: option))
                }
            }
        }
        return result
    }

    private static func buildTokenIndex(from items: [PantryCatalogItemDefinition]) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for item in items {
            for token in IngredientLexicon.tokenize(IngredientLexicon.lookupKey(item.name)) {
                result[token, default: []].insert(item.id)
            }
            for alias in item.aliases {
                for token in IngredientLexicon.tokenize(IngredientLexicon.lookupKey(alias)) {
                    result[token, default: []].insert(item.id)
                }
            }
        }
        return result
    }

    // MARK: - Rebuild

    private static func rebuildIndices() {
        var merged = bundleItems
        // Apply facet extensions to bundle items
        if !facetExtensions.isEmpty {
            merged = merged.map { item in
                guard let extensions = facetExtensions[item.id] else { return item }
                var mutableItem = item
                mutableItem.facets = item.facets.map { facetDef in
                    guard let newValues = extensions[facetDef.key.rawValue] else { return facetDef }
                    let existingSet = Set(facetDef.options)
                    let additions = newValues.filter { !existingSet.contains($0) }
                    guard !additions.isEmpty else { return facetDef }
                    return PantryFacetDefinition(key: facetDef.key, options: facetDef.options + additions)
                }
                // Add entirely new facet keys from extensions
                let existingKeys = Set(mutableItem.facets.map(\.key))
                for (keyRaw, values) in extensions {
                    guard let facetKey = PantryFacetKey(rawValue: keyRaw), !existingKeys.contains(facetKey) else { continue }
                    mutableItem.facets.append(PantryFacetDefinition(key: facetKey, options: values))
                }
                return mutableItem
            }
        }
        merged += userItems
        allItems = merged
        itemsByID = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        aliasIndex = buildAliasIndex(from: merged)
        facetOptionIndex = buildFacetOptionIndex(from: merged)
        nameKeySet = Set(merged.map { normalizeLookupKey($0.name) })
        facetTokenToItems = buildFacetTokenToItems(from: merged)
        tokenIndex = buildTokenIndex(from: merged)
    }

    // MARK: - Loading

    static func loadUserData(from store: UserCatalogStoreProtocol) {
        self.store = store
        userItems = store.loadUserItems()
        facetExtensions = store.loadFacetExtensions()
        rebuildIndices()
    }

    // MARK: - Mutation: User Items

    @discardableResult
    static func registerUserItem(_ item: PantryCatalogItemDefinition) -> Result<Void, UserCatalogError> {
        // Validate ID prefix
        let itemID = item.id
        guard itemID.hasPrefix("user-") else {
            return .failure(.idCollision(existingItemID: itemID))
        }

        // Check bundle ID collision
        if bundleItems.contains(where: { $0.id == itemID }) {
            return .failure(.idCollision(existingItemID: itemID))
        }

        // Check name/alias collision with bundle items
        let nameKey = normalizeLookupKey(item.name)
        let allKeys = [nameKey] + item.aliases.map { normalizeLookupKey($0) }
        for key in allKeys {
            if let existingID = aliasIndex[key] {
                if let existing = itemsByID[existingID], !existing.isUserDefined {
                    return .failure(.nameCollision(existingItemID: existingID, existingItemName: existing.name))
                }
                if existing(isUserItem: existingID) {
                    return .failure(.duplicateUserItem(existingItemID: existingID))
                }
            }
        }

        // Ensure isUserDefined is true
        var newItem = item
        if !newItem.isUserDefined {
            newItem = PantryCatalogItemDefinition(
                id: newItem.id, name: newItem.name, category: newItem.category,
                defaultUnit: newItem.defaultUnit, defaultQuantity: newItem.defaultQuantity,
                defaultStorage: newItem.defaultStorage, aliases: newItem.aliases,
                facets: newItem.facets, defaultSelections: newItem.defaultSelections,
                substitutions: newItem.substitutions, unitOverrides: newItem.unitOverrides,
                freshnessByStorage: newItem.freshnessByStorage, isUserDefined: true
            )
        }

        userItems.append(newItem)
        store?.saveUserItems(userItems)
        rebuildIndices()
        return .success(())
    }

    static func removeUserItem(id: String) {
        userItems.removeAll { $0.id == id }
        store?.saveUserItems(userItems)
        rebuildIndices()
    }

    private static func existing(isUserItem id: String) -> Bool {
        userItems.contains { $0.id == id }
    }

    // MARK: - Mutation: Facet Extensions

    @discardableResult
    static func addFacetExtension(catalogItemID: String, key: PantryFacetKey, value: String) -> Result<Void, UserCatalogError> {
        guard let item = itemsByID[catalogItemID] else {
            return .failure(.itemNotFound(itemID: catalogItemID))
        }

        // Check for duplicate value across bundle options + existing extensions
        let existingOptions = item.options(for: key)
        let normalizedValue = value.trimmingCharacters(in: .whitespaces)
        if existingOptions.contains(where: { $0.lowercased() == normalizedValue.lowercased() }) {
            return .failure(.duplicateFacetValue(itemName: item.name, facetKey: key.title, value: normalizedValue))
        }

        facetExtensions[catalogItemID, default: [:]][key.rawValue, default: []].append(normalizedValue)
        store?.saveFacetExtensions(facetExtensions)
        rebuildIndices()
        return .success(())
    }

    static func removeFacetExtension(catalogItemID: String, key: PantryFacetKey, value: String) {
        facetExtensions[catalogItemID]?[key.rawValue]?.removeAll { $0 == value }
        // Clean up empty entries
        if facetExtensions[catalogItemID]?[key.rawValue]?.isEmpty == true {
            facetExtensions[catalogItemID]?.removeValue(forKey: key.rawValue)
        }
        if facetExtensions[catalogItemID]?.isEmpty == true {
            facetExtensions.removeValue(forKey: catalogItemID)
        }
        store?.saveFacetExtensions(facetExtensions)
        rebuildIndices()
    }

    // MARK: - Queries

    /// Resolve a normalized lookup key to an item ID via the alias index.
    static func resolveAlias(_ lookupKey: String) -> String? {
        aliasIndex[lookupKey]
    }

    /// Returns item IDs that share at least one token with the given set.
    static func itemIDs(matchingAnyToken tokens: Set<String>) -> Set<String> {
        var result: Set<String> = []
        for token in tokens {
            if let ids = tokenIndex[token] {
                result.formUnion(ids)
            }
        }
        return result
    }

    /// Returns item IDs that have a facet option matching any of the given tokens.
    static func itemIDs(matchingFacetTokens tokens: Set<String>) -> Set<String> {
        var result: Set<String> = []
        for token in tokens {
            if let ids = facetOptionIndex[token] {
                for id in ids { result.insert(id) }
            }
        }
        return result
    }

    static func item(id: String?) -> PantryCatalogItemDefinition? {
        guard let id else { return nil }
        return itemsByID[id]
    }

    static func resolveExact(name: String) -> PantryCatalogItemDefinition? {
        let normalized = normalizeLookupKey(name)
        guard let id = aliasIndex[normalized] else { return nil }
        return itemsByID[id]
    }

    static func normalizeLookupKey(_ value: String) -> String {
        IngredientLexicon.lookupKey(value)
    }
}

