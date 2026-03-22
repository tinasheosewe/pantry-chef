import Foundation

struct ShoppingItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var quantity: Double?
    var unit: MeasurementUnit?
    var category: FoodCategory
    var isChecked: Bool
    var recipeSource: String? // Which recipe needed this
    var catalogItemID: String?

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double? = nil,
        unit: MeasurementUnit? = nil,
        category: FoodCategory = .other,
        isChecked: Bool = false,
        recipeSource: String? = nil,
        catalogItemID: String? = nil
    ) {
        let resolvedCatalogItem = IngredientMatcher.resolvedCatalogItem(for: name, catalogItemID: catalogItemID)

        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category == .other ? (resolvedCatalogItem?.category ?? category) : category
        self.isChecked = isChecked
        self.recipeSource = recipeSource
        self.catalogItemID = resolvedCatalogItem?.id ?? catalogItemID
    }

    init(ingredient: Ingredient, recipeSource: String? = nil) {
        self.init(
            name: ingredient.name,
            quantity: ingredient.quantity,
            unit: ingredient.unit,
            category: ingredient.category,
            recipeSource: recipeSource,
            catalogItemID: IngredientMatcher.resolvedCatalogItemID(for: ingredient.name, catalogItemID: ingredient.catalogItemID)
        )
    }

    var resolvedCatalogItem: PantryCatalogItemDefinition? {
        IngredientMatcher.resolvedCatalogItem(for: name, catalogItemID: catalogItemID)
    }

    var identityKey: String {
        if let resolvedCatalogItem {
            return "catalog:\(resolvedCatalogItem.id)"
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
}
