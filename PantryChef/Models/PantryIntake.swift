import Foundation

// MARK: - Custom Ingredient Definition

struct AIIngredientDefinition {
    let category: FoodCategory
    let defaultStorage: PantryStorage
    let defaultUnit: MeasurementUnit?
    let facets: [PantryFacetKey: [String]]
}

struct CustomIngredientDraft {
    var name: String
    var category: FoodCategory = .other
    var defaultStorage: PantryStorage = .pantry
    var defaultUnit: MeasurementUnit? = nil
    /// Shelf life (days) in the default storage — required so a custom item is a
    /// complete, first-class ingredient with a real countdown (no incomplete items).
    var shelfLifeDays: Int? = nil
    var facets: [PantryFacetKey: [String]] = [:]
    var defaultSelections: [PantryFacetKey: String] = [:]

    /// A sensible default shelf life per storage, so the field is pre-filled and a
    /// custom item is never saved without freshness.
    static func defaultShelfLife(_ storage: PantryStorage) -> Int {
        switch storage {
        case .refrigerated: return 7
        case .frozen: return 120
        case .pantry: return 180
        }
    }

    /// Effective shelf life — the user's value, else the storage default.
    var effectiveShelfLifeDays: Int { shelfLifeDays ?? Self.defaultShelfLife(defaultStorage) }

    /// Why the draft can't be saved yet (nil = ok). Enforced before registration.
    var validationError: String? {
        name.trimmed.isEmpty ? "Give it a name." : nil
    }

    var nameCollisionWarning: String? {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return nil }
        if let existing = PantryCatalog.resolveExact(name: trimmed) {
            return "\"\(existing.titleCasedName)\" already exists in the catalog. Consider using that instead."
        }
        return nil
    }

    var sortedFacetKeys: [PantryFacetKey] {
        facets.keys.sorted { $0.rawValue < $1.rawValue }
    }

    var unusedFacetKeys: [PantryFacetKey] {
        PantryFacetKey.allCases.filter { facets[$0] == nil }
    }

    mutating func addFacetOption(_ key: PantryFacetKey, value: String) {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return }
        var options = facets[key] ?? []
        guard !options.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        options.append(trimmed)
        facets[key] = options
    }

    mutating func removeFacetOption(_ key: PantryFacetKey, value: String) {
        facets[key]?.removeAll { $0 == value }
        if defaultSelections[key] == value {
            defaultSelections.removeValue(forKey: key)
        }
        if facets[key]?.isEmpty == true {
            facets.removeValue(forKey: key)
        }
    }

    mutating func removeFacet(_ key: PantryFacetKey) {
        facets.removeValue(forKey: key)
        defaultSelections.removeValue(forKey: key)
    }

    mutating func applyAIDefinition(_ definition: AIIngredientDefinition) {
        category = definition.category
        defaultStorage = definition.defaultStorage
        defaultUnit = definition.defaultUnit
        facets = definition.facets.filter { !$0.value.isEmpty }
    }

    var titleCasedName: String {
        PantryCatalogItemDefinition.titleCase(name)
    }

    static func titleCase(_ value: String) -> String {
        PantryCatalogItemDefinition.titleCase(value)
    }

    func buildDefinition() -> PantryCatalogItemDefinition {
        let sanitizedName = name.trimmed.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let itemID = "user-\(sanitizedName)"

        let facetDefs: [PantryFacetDefinition] = sortedFacetKeys.compactMap { key in
            guard let options = facets[key], !options.isEmpty else { return nil }
            return PantryFacetDefinition(key: key, options: options)
        }

        let facetDefaults: [PantryFacetSelection] = sortedFacetKeys.compactMap { key in
            guard let value = defaultSelections[key] else { return nil }
            // Only include if the value is actually one of the facet options
            guard let options = facets[key], options.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return nil }
            return PantryFacetSelection(key: key, value: value)
        }

        return PantryCatalogItemDefinition(
            id: itemID,
            name: titleCasedName.trimmed,
            category: category,
            defaultUnit: defaultUnit,
            defaultQuantity: nil,
            defaultStorage: defaultStorage,
            aliases: [],
            facets: facetDefs,
            defaultSelections: facetDefaults,
            substitutions: [],
            unitOverrides: [:],
            freshnessByStorage: [defaultStorage: effectiveShelfLifeDays...effectiveShelfLifeDays],
            isUserDefined: true
        )
    }
}