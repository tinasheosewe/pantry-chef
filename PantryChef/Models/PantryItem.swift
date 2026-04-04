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
                   expiryDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()), catalogItemID: "milk", storage: .refrigerated, freshnessSource: .estimated),
        PantryItem(name: "Chicken Breast", category: .protein, quantity: 500, unit: .gram,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()), catalogItemID: "chicken", facets: [.init(key: .variant, value: "breast")], storage: .refrigerated, freshnessSource: .estimated),
        PantryItem(name: "Tofu", category: .protein, quantity: 400, unit: .gram,
                   catalogItemID: "tofu", facets: [.init(key: .variant, value: "extra firm")], storage: .refrigerated),
        PantryItem(name: "Onions", category: .produce, quantity: 3, unit: .whole,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()), catalogItemID: "onion", storage: .pantry, freshnessSource: .estimated),
        PantryItem(name: "Garlic", category: .produce, quantity: 1, unit: .whole,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 21, to: Date()), catalogItemID: "garlic", storage: .pantry, freshnessSource: .estimated),
        PantryItem(name: "Olive Oil", category: .oils, quantity: 500, unit: .milliliter, catalogItemID: "olive-oil", storage: .pantry),
        PantryItem(name: "Coconut Aminos", category: .condiments, quantity: 250, unit: .milliliter,
                   catalogItemID: "coconut-aminos", storage: .pantry),
        PantryItem(name: "Vegetable Broth", category: .canned, quantity: 1, unit: .liter,
                   catalogItemID: "broth", facets: [.init(key: .base, value: "vegetable")], storage: .pantry),
        PantryItem(name: "Salt", category: .spices, quantity: 1, unit: .package, catalogItemID: "salt", storage: .pantry),
        PantryItem(name: "Black Pepper", category: .spices, quantity: 1, unit: .package, catalogItemID: "black-pepper", storage: .pantry),
        PantryItem(name: "Rice", category: .grains, quantity: 2, unit: .kilogram, catalogItemID: "rice", storage: .pantry),
        PantryItem(name: "Eggs", category: .dairy, quantity: 6, unit: .piece,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()), catalogItemID: "egg", storage: .refrigerated, freshnessSource: .estimated),
        PantryItem(name: "Muffin", category: .grains, quantity: 2, unit: .piece,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()), catalogItemID: "muffin", storage: .pantry, freshnessSource: .estimated),
    ]

    private static func normalizeFacets(_ facets: [PantryFacetSelection], for item: PantryCatalogItemDefinition?) -> [PantryFacetSelection] {
        guard let item else {
            var facetsByKey: [PantryFacetKey: PantryFacetSelection] = [:]
            for facet in facets where facetsByKey[facet.key] == nil {
                facetsByKey[facet.key] = facet
            }
            return PantryFacetKey.allCases.compactMap { facetsByKey[$0] }
        }

        return item.normalizedSelections(from: facets)
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

// MARK: - Pantry Item Batch

/// A group of pantry items with the same identity (ingredient, storage, variant) but potentially different expiry dates.
/// Used for UI grouping with accordion display when multiple batches exist.
struct PantryItemBatch: Identifiable {
    let items: [PantryItem]

    var id: UUID { items.first?.id ?? UUID() }

    /// The first item serves as the representative for displaying name, category, etc.
    var representativeItem: PantryItem { items[0] }

    /// Whether this batch contains multiple items with different expiry dates.
    var hasMultipleBatches: Bool { items.count > 1 }

    /// The earliest expiry date among all items in this batch.
    var earliestExpiry: Date? {
        items.compactMap(\.expiryDate).min()
    }

    /// The expiry status based on the earliest expiry date.
    var expiryStatus: ExpiryStatus {
        .from(date: earliestExpiry)
    }

    /// Days until the earliest expiry, used for display.
    var daysUntilExpiry: Int? {
        ExpiryStatus.daysRemaining(until: earliestExpiry)
    }

    /// Total quantity across all items, if they all use the same unit.
    var totalQuantity: Double? {
        guard items.allSatisfy({ $0.quantity != nil }) else { return nil }
        let units = Set(items.compactMap(\.unit))
        guard units.count == 1 else { return nil }
        return items.compactMap(\.quantity).reduce(0, +)
    }

    /// The common unit if all items share the same unit.
    var commonUnit: MeasurementUnit? {
        let units = Set(items.compactMap(\.unit))
        return units.count == 1 ? units.first : nil
    }

    /// Display quantity showing total across batches.
    var displayQuantity: String {
        if let total = totalQuantity, let unit = commonUnit {
            let unitStr = unit.rawValue
            if total == total.rounded() {
                return "\(Int(total)) \(unitStr)"
            }
            return String(format: "%.1f %@", total, unitStr)
        }
        return representativeItem.displayQuantity
    }
}

