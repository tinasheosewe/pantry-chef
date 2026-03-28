import Foundation

struct PantryItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var category: FoodCategory
    var quantity: Double?
    var unit: MeasurementUnit?
    var expiryDate: Date?
    var dateAdded: Date
    var notes: String?
    var catalogItemID: String?
    var facets: [PantryFacetSelection]
    var storage: PantryStorage
    var freshnessSource: PantryFreshnessSource
    var quantityMode: PantryQuantityMode

    init(
        id: UUID = UUID(),
        name: String,
        category: FoodCategory = .other,
        quantity: Double? = nil,
        unit: MeasurementUnit? = nil,
        expiryDate: Date? = nil,
        dateAdded: Date = Date(),
        notes: String? = nil,
        catalogItemID: String? = nil,
        facets: [PantryFacetSelection] = [],
        storage: PantryStorage? = nil,
        freshnessSource: PantryFreshnessSource? = nil,
        quantityMode: PantryQuantityMode? = nil
    ) {
        let catalogItem = IngredientMatcher.resolvedCatalogItem(for: name, catalogItemID: catalogItemID)
        let effectiveFacets = Self.normalizeFacets(facets, for: catalogItem)
        let effectiveQuantityMode = Self.normalizedQuantityMode(quantityMode, quantity: quantity)
        let effectiveQuantity = effectiveQuantityMode == .exact ? quantity : nil

        self.id = id
        self.name = catalogItem?.displayName(for: effectiveFacets) ?? name
        self.category = catalogItem?.category ?? category
        self.quantity = effectiveQuantity
        self.unit = effectiveQuantity == nil ? nil : (unit ?? catalogItem?.suggestedUnit(for: effectiveFacets))
        self.expiryDate = expiryDate
        self.dateAdded = dateAdded
        self.notes = notes?.trimmed.nilIfEmpty
        self.catalogItemID = catalogItem?.id ?? catalogItemID
        self.facets = effectiveFacets
        self.storage = storage ?? catalogItem?.defaultStorage ?? .pantry
        self.freshnessSource = freshnessSource ?? (expiryDate == nil ? .none : .userProvided)
        self.quantityMode = effectiveQuantityMode
    }

    var isCatalogBacked: Bool {
        catalogItemID != nil
    }

    var isTrackingExactQuantity: Bool {
        quantityMode == .exact
    }

    var expiryStatus: ExpiryStatus {
        .from(date: expiryDate)
    }

    var daysUntilExpiry: Int? {
        ExpiryStatus.daysRemaining(until: expiryDate)
    }

    var displayQuantity: String {
        guard let quantity else { return "" }
        let unitStr = unit?.rawValue ?? ""
        if quantity == quantity.rounded() {
            return "\(Int(quantity)) \(unitStr)"
        }
        return String(format: "%.1f %@", quantity, unitStr)
    }

    // MARK: - Sample Data
    static let samples: [PantryItem] = [
        PantryItem(name: "Milk", category: .dairy, quantity: 1, unit: .liter,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()), storage: .refrigerated, freshnessSource: .estimated),
        PantryItem(name: "Chicken Breast", category: .protein, quantity: 500, unit: .gram,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()), storage: .refrigerated, freshnessSource: .estimated),
        PantryItem(name: "Tofu", category: .protein, quantity: 400, unit: .gram,
                   catalogItemID: "tofu", facets: [.init(key: .variant, value: "extra firm")], storage: .refrigerated),
        PantryItem(name: "Onions", category: .produce, quantity: 3, unit: .whole,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()), storage: .pantry, freshnessSource: .estimated),
        PantryItem(name: "Garlic", category: .produce, quantity: 1, unit: .whole,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 21, to: Date()), storage: .pantry, freshnessSource: .estimated),
        PantryItem(name: "Olive Oil", category: .oils, quantity: 500, unit: .milliliter, storage: .pantry),
        PantryItem(name: "Coconut Aminos", category: .condiments, quantity: 250, unit: .milliliter,
                   catalogItemID: "coconut-aminos", storage: .pantry),
        PantryItem(name: "Vegetable Broth", category: .canned, quantity: 1, unit: .liter,
                   catalogItemID: "broth", facets: [.init(key: .base, value: "vegetable")], storage: .pantry),
        PantryItem(name: "Salt", category: .spices, quantity: 1, unit: .package, storage: .pantry),
        PantryItem(name: "Black Pepper", category: .spices, quantity: 1, unit: .package, storage: .pantry),
        PantryItem(name: "Rice", category: .grains, quantity: 2, unit: .kilogram, storage: .pantry),
        PantryItem(name: "Eggs", category: .dairy, quantity: 6, unit: .piece,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()), storage: .refrigerated, freshnessSource: .estimated),
        PantryItem(name: "Muffin", category: .grains, quantity: 2, unit: .piece,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()), storage: .pantry, freshnessSource: .estimated),
    ]

    private static func normalizeFacets(_ facets: [PantryFacetSelection], for item: PantryCatalogItemDefinition?) -> [PantryFacetSelection] {
        var facetsByKey: [PantryFacetKey: PantryFacetSelection] = [:]

        for facet in facets {
            guard facetsByKey[facet.key] == nil else { continue }
            if let item {
                guard item.supports(facet.key), item.options(for: facet.key).contains(facet.value) else {
                    continue
                }
            }
            facetsByKey[facet.key] = facet
        }

        let orderedKeys = item?.facets.map(\.key) ?? PantryFacetKey.allCases
        return orderedKeys.compactMap { facetsByKey[$0] }
    }

    private static func normalizedQuantityMode(_ quantityMode: PantryQuantityMode?, quantity: Double?) -> PantryQuantityMode {
        switch quantityMode {
        case .exact where quantity != nil:
            return .exact
        case .presenceOnly:
            return .presenceOnly
        default:
            return quantity == nil ? .presenceOnly : .exact
        }
    }
}
