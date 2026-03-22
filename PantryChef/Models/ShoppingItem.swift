import Foundation

struct ShoppingItem: Identifiable, Codable, Hashable {
    private static let facetDisplayOrder: [PantryFacetKey] = [
        .variant,
        .form,
        .preservation,
        .processing,
        .preparation,
        .texture,
        .concentration,
        .base,
    ]

    var id: UUID
    var name: String
    var quantity: Double?
    var unit: MeasurementUnit?
    var category: FoodCategory
    var isChecked: Bool
    var recipeSource: String? // Which recipe needed this
    var catalogItemID: String?
    var facets: [PantryFacetSelection]

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double? = nil,
        unit: MeasurementUnit? = nil,
        category: FoodCategory = .other,
        isChecked: Bool = false,
        recipeSource: String? = nil,
        catalogItemID: String? = nil,
        facets: [PantryFacetSelection] = []
    ) {
        let resolvedCatalogItem = IngredientMatcher.resolvedCatalogItem(for: name, catalogItemID: catalogItemID)
        let effectiveFacets = Self.normalizeFacets(facets, for: resolvedCatalogItem)

        self.id = id
        self.name = resolvedCatalogItem?.displayName(for: effectiveFacets) ?? name
        self.quantity = quantity
        self.unit = quantity == nil ? nil : (unit ?? resolvedCatalogItem?.suggestedUnit(for: effectiveFacets))
        self.category = category == .other ? (resolvedCatalogItem?.category ?? category) : category
        self.isChecked = isChecked
        self.recipeSource = recipeSource
        self.catalogItemID = resolvedCatalogItem?.id ?? catalogItemID
        self.facets = effectiveFacets
    }

    init(ingredient: Ingredient, recipeSource: String? = nil) {
        self.init(
            name: ingredient.name,
            quantity: ingredient.quantity,
            unit: ingredient.unit,
            category: ingredient.category,
            recipeSource: recipeSource,
            catalogItemID: IngredientMatcher.resolvedCatalogItemID(for: ingredient.name, catalogItemID: ingredient.catalogItemID),
            facets: ingredient.facets
        )
    }

    var resolvedCatalogItem: PantryCatalogItemDefinition? {
        IngredientMatcher.resolvedCatalogItem(for: name, catalogItemID: catalogItemID)
    }

    var displayName: String {
        resolvedCatalogItem?.name ?? name
    }

    var facetSummary: String? {
        guard !facets.isEmpty else { return nil }

        let orderedFacets = Self.facetDisplayOrder.compactMap { key in
            facets.first(where: { $0.key == key })
        }

        return orderedFacets
            .map { Self.humanizedFacetValue($0.value) }
            .joined(separator: " • ")
    }

    var identityKey: String {
        if let resolvedCatalogItem {
            let facetKey = facets
                .sorted { lhs, rhs in
                    if lhs.key.rawValue == rhs.key.rawValue {
                        return lhs.value < rhs.value
                    }
                    return lhs.key.rawValue < rhs.key.rawValue
                }
                .map { "\($0.key.rawValue)=\($0.value)" }
                .joined(separator: "|")

            return facetKey.isEmpty ? "catalog:\(resolvedCatalogItem.id)" : "catalog:\(resolvedCatalogItem.id)|\(facetKey)"
        }

        return "name:\(IngredientMatcher.normalize(name))"
    }

    func matchesIdentity(of other: ShoppingItem) -> Bool {
        identityKey == other.identityKey
    }

    var displayText: String {
        var parts: [String] = []
        if let quantity {
            if quantity == quantity.rounded() {
                parts.append("\(Int(quantity))")
            } else {
                parts.append(String(format: "%.1f", quantity))
            }
        }
        if let unit {
            parts.append(unit.rawValue)
        }
        parts.append(name)
        return parts.joined(separator: " ")
    }

    static let samples: [ShoppingItem] = [
        ShoppingItem(name: "Bell Pepper", quantity: 2, unit: .whole, category: .produce),
        ShoppingItem(name: "Soy Sauce", quantity: 1, unit: .package, category: .condiments),
        ShoppingItem(name: "Bread", quantity: 1, unit: .package, category: .grains),
        ShoppingItem(name: "Butter", quantity: 250, unit: .gram, category: .dairy),
        ShoppingItem(name: "Tomatoes", quantity: 4, unit: .whole, category: .produce),
    ]

    private static func normalizeFacets(
        _ facets: [PantryFacetSelection],
        for item: PantryCatalogItemDefinition?
    ) -> [PantryFacetSelection] {
        guard let item else { return [] }

        var facetsByKey: [PantryFacetKey: PantryFacetSelection] = [:]

        for facet in item.defaultSelections {
            facetsByKey[facet.key] = facet
        }

        for facet in facets {
            guard item.options(for: facet.key).contains(facet.value) else { continue }
            facetsByKey[facet.key] = facet
        }

        return item.facets.compactMap { definition in
            facetsByKey[definition.key]
        }
    }

    private static func humanizedFacetValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
