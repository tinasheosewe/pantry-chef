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
    var facets: [PantryFacetKey: [String]] = [:]
    var defaultSelections: [PantryFacetKey: String] = [:]

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
            freshnessByStorage: [:],
            isUserDefined: true
        )
    }
}