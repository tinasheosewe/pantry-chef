import Foundation

extension Notification.Name {
    static let pantryCatalogDidChange = Notification.Name("PantryCatalogDidChange")
}

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
    var defaultUnit: MeasurementUnit?
    let defaultQuantity: Double?
    var defaultStorage: PantryStorage
    let aliases: [String]
    var facets: [PantryFacetDefinition]
    var defaultSelections: [PantryFacetSelection]
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

    static func titleCase(_ value: String) -> String {
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
        case .nameCollision(_, let existingItemName):
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
    private(set) static var aliasExtensions: [String: [String]] = [:]
    private(set) static var defaultOverrides: [String: [String: String]] = [:]
    private static var store: UserCatalogStoreProtocol?
    private static let supportedDefaultOverrideKeys: Set<String> = ["defaultStorage", "defaultUnit"]

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
                return mutableItem
            }
        }
        // Apply default overrides (storage, unit) to bundle items
        if !defaultOverrides.isEmpty {
            merged = merged.map { item in
                guard let overrides = defaultOverrides[item.id] else { return item }
                var mutableItem = item
                if let storageRaw = overrides["defaultStorage"],
                   let storage = PantryStorage(rawValue: storageRaw) {
                    mutableItem.defaultStorage = storage
                }
                if let unitRaw = overrides["defaultUnit"],
                   let unit = MeasurementUnit(rawValue: unitRaw) {
                    mutableItem.defaultUnit = unit
                }
                return mutableItem
            }
        }
        merged += userItems
        allItems = merged
        itemsByID = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        aliasIndex = buildAliasIndex(from: merged)
        // Merge user alias extensions into the alias index
        for (itemID, aliases) in aliasExtensions {
            for alias in aliases {
                aliasIndex[normalizeLookupKey(alias)] = itemID
            }
        }
        facetOptionIndex = buildFacetOptionIndex(from: merged)
        nameKeySet = Set(merged.map { normalizeLookupKey($0.name) })
        facetTokenToItems = buildFacetTokenToItems(from: merged)
        tokenIndex = buildTokenIndex(from: merged)
        CatalogSearchEngine.invalidateCache()
        NotificationCenter.default.post(name: .pantryCatalogDidChange, object: nil)
    }

    // MARK: - Loading

    static func loadUserData(from store: UserCatalogStoreProtocol) {
        self.store = store
        userItems = store.loadUserItems()
        let loadedFacetExtensions = store.loadFacetExtensions()
        facetExtensions = sanitizeFacetExtensions(loadedFacetExtensions)
        if facetExtensions != loadedFacetExtensions {
            store.saveFacetExtensions(facetExtensions)
        }
        aliasExtensions = store.loadAliasExtensions()
        let loadedDefaultOverrides = store.loadDefaultOverrides()
        defaultOverrides = sanitizeDefaultOverrides(loadedDefaultOverrides)
        if defaultOverrides != loadedDefaultOverrides {
            store.saveDefaultOverrides(defaultOverrides)
        }
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

        // Check user item ID collision
        if userItems.contains(where: { $0.id == itemID }) {
            return .failure(.duplicateUserItem(existingItemID: itemID))
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
        if facetExtensions.removeValue(forKey: id) != nil {
            store?.saveFacetExtensions(facetExtensions)
        }
        if aliasExtensions.removeValue(forKey: id) != nil {
            store?.saveAliasExtensions(aliasExtensions)
        }
        if defaultOverrides.removeValue(forKey: id) != nil {
            store?.saveDefaultOverrides(defaultOverrides)
        }
        rebuildIndices()
    }

    private static func existing(isUserItem id: String) -> Bool {
        userItems.contains { $0.id == id }
    }

    // MARK: - Mutation: Facet Extensions

    @discardableResult
    static func addFacetExtension(catalogItemID: String, key: PantryFacetKey, value: String) -> Result<Void, UserCatalogError> {
        guard let item = bundleItem(id: catalogItemID), item.supports(key) else {
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

    /// Returns the original bundle-catalog item (before extensions), or nil if not a catalog item.
    static func bundleItem(id: String) -> PantryCatalogItemDefinition? {
        bundleItems.first { $0.id == id }
    }

    /// Replace all facet extensions for a catalog item. Supports both addition and removal.
    static func setFacetExtensions(catalogItemID: String, extensions: [String: [String]]) {
        let sanitized = sanitizeFacetExtensions([catalogItemID: extensions])[catalogItemID] ?? [:]
        if sanitized.isEmpty {
            facetExtensions.removeValue(forKey: catalogItemID)
        } else {
            facetExtensions[catalogItemID] = sanitized
        }
        store?.saveFacetExtensions(facetExtensions)
        rebuildIndices()
    }

    /// Set default overrides (storage, unit) for a catalog item.
    static func setDefaultOverrides(catalogItemID: String, overrides: [String: String]) {
        let sanitized = sanitizeDefaultOverrideValues(overrides)
        if sanitized.isEmpty {
            defaultOverrides.removeValue(forKey: catalogItemID)
        } else {
            defaultOverrides[catalogItemID] = sanitized
        }
        store?.saveDefaultOverrides(defaultOverrides)
        rebuildIndices()
    }

    // MARK: - Mutation: Alias Extensions

    static func addAliasExtensions(catalogItemID: String, aliases: [String]) {
        guard itemsByID[catalogItemID] != nil else { return }
        var existing = aliasExtensions[catalogItemID] ?? []
        let existingSet = Set(existing.map { $0.lowercased() })
        for alias in aliases where !existingSet.contains(alias.lowercased()) {
            existing.append(alias)
        }
        aliasExtensions[catalogItemID] = existing
        store?.saveAliasExtensions(aliasExtensions)
        rebuildIndices()
    }

    static func setAliasExtensions(catalogItemID: String, aliases: [String]) {
        let sanitized = sanitizeAliasExtensions(aliases)
        if sanitized.isEmpty {
            aliasExtensions.removeValue(forKey: catalogItemID)
        } else {
            aliasExtensions[catalogItemID] = sanitized
        }
        store?.saveAliasExtensions(aliasExtensions)
        rebuildIndices()
    }

    /// Apply a merge result from AI verification: add facet options (additive) and alias extensions.
    static func applyMerge(
        catalogItemID: String,
        mergedFacets: [PantryFacetKey: [String]],
        mergedAliases: [String]
    ) {
        guard let item = itemsByID[catalogItemID], !item.isUserDefined else { return }

        // Additive facet merge: union existing + LLM-returned options
        for (key, newOptions) in mergedFacets {
            guard item.supports(key) else { continue }
            let existingOptions = Set(item.options(for: key).map { $0.lowercased() })
            for option in newOptions where !existingOptions.contains(option.lowercased()) {
                facetExtensions[catalogItemID, default: [:]][key.rawValue, default: []].append(option)
            }
        }
        store?.saveFacetExtensions(facetExtensions)

        // Additive alias merge
        if !mergedAliases.isEmpty {
            addAliasExtensions(catalogItemID: catalogItemID, aliases: mergedAliases)
        } else {
            rebuildIndices()
        }
    }

    static func removeAliasExtensions(catalogItemID: String) {
        aliasExtensions.removeValue(forKey: catalogItemID)
        store?.saveAliasExtensions(aliasExtensions)
        rebuildIndices()
    }

    /// Remove all user extensions (facets + aliases) for a catalog item, restoring original definition.
    static func resetExtensions(catalogItemID: String) {
        var changed = false
        if facetExtensions.removeValue(forKey: catalogItemID) != nil {
            store?.saveFacetExtensions(facetExtensions)
            changed = true
        }
        if aliasExtensions.removeValue(forKey: catalogItemID) != nil {
            store?.saveAliasExtensions(aliasExtensions)
            changed = true
        }
        if defaultOverrides.removeValue(forKey: catalogItemID) != nil {
            store?.saveDefaultOverrides(defaultOverrides)
            changed = true
        }
        if changed { rebuildIndices() }
    }

    static func hasUserModifications(catalogItemID: String) -> Bool {
        facetExtensions[catalogItemID] != nil
            || aliasExtensions[catalogItemID] != nil
            || defaultOverrides[catalogItemID] != nil
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

    private static func sanitizeFacetExtensions(_ raw: [String: [String: [String]]]) -> [String: [String: [String]]] {
        var sanitized: [String: [String: [String]]] = [:]

        for (itemID, itemExtensions) in raw {
            guard let item = bundleItem(id: itemID) else { continue }
            let allowedKeys = Set(item.facets.map { $0.key.rawValue })
            var sanitizedExtensions: [String: [String]] = [:]

            for (keyRaw, values) in itemExtensions where allowedKeys.contains(keyRaw) {
                let cleaned = sanitizeFacetExtensionValues(values)
                if !cleaned.isEmpty {
                    sanitizedExtensions[keyRaw] = cleaned
                }
            }

            if !sanitizedExtensions.isEmpty {
                sanitized[itemID] = sanitizedExtensions
            }
        }

        return sanitized
    }

    private static func sanitizeFacetExtensionValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var cleaned: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = trimmed.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            cleaned.append(trimmed)
        }

        return cleaned
    }

    private static func sanitizeDefaultOverrides(_ raw: [String: [String: String]]) -> [String: [String: String]] {
        var sanitized: [String: [String: String]] = [:]

        for (itemID, overrides) in raw {
            guard bundleItem(id: itemID) != nil else { continue }
            let cleaned = sanitizeDefaultOverrideValues(overrides)
            if !cleaned.isEmpty {
                sanitized[itemID] = cleaned
            }
        }

        return sanitized
    }

    private static func sanitizeDefaultOverrideValues(_ overrides: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]

        if let storageRaw = overrides["defaultStorage"],
           let storage = PantryStorage(rawValue: storageRaw) {
            sanitized["defaultStorage"] = storage.rawValue
        }

        if let unitRaw = overrides["defaultUnit"],
           let unit = MeasurementUnit(rawValue: unitRaw) {
            sanitized["defaultUnit"] = unit.rawValue
        }

        return sanitized.filter { supportedDefaultOverrideKeys.contains($0.key) }
    }

    private static func sanitizeAliasExtensions(_ aliases: [String]) -> [String] {
        var seen: Set<String> = []
        var cleaned: [String] = []

        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = normalizeLookupKey(trimmed)
            guard seen.insert(normalized).inserted else { continue }
            cleaned.append(trimmed)
        }

        return cleaned
    }
}

