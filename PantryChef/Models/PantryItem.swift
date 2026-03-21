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
    var imageURL: String?
    var catalogItemID: String?
    var facets: [PantryFacetSelection]
    var storage: PantryStorage
    var freshnessSource: PantryFreshnessSource

    init(
        id: UUID = UUID(),
        name: String,
        category: FoodCategory = .other,
        quantity: Double? = nil,
        unit: MeasurementUnit? = nil,
        expiryDate: Date? = nil,
        dateAdded: Date = Date(),
        notes: String? = nil,
        imageURL: String? = nil,
        catalogItemID: String? = nil,
        facets: [PantryFacetSelection] = [],
        storage: PantryStorage? = nil,
        freshnessSource: PantryFreshnessSource? = nil
    ) {
        let catalogItem = catalogItemID.flatMap { PantryCatalog.item(id: $0) } ?? PantryCatalog.resolveExact(name: name)
        let effectiveFacets = Self.normalizeFacets(facets, for: catalogItem)

        self.id = id
        self.name = catalogItem?.displayName(for: effectiveFacets) ?? name
        self.category = catalogItem?.category ?? category
        self.quantity = quantity
        self.unit = quantity == nil ? nil : (unit ?? catalogItem?.defaultUnit)
        self.expiryDate = expiryDate
        self.dateAdded = dateAdded
        self.notes = notes?.trimmed.nilIfEmpty
        self.imageURL = imageURL
        self.catalogItemID = catalogItem?.id ?? catalogItemID
        self.facets = effectiveFacets
        self.storage = storage ?? catalogItem?.defaultStorage ?? .pantry
        self.freshnessSource = freshnessSource ?? (expiryDate == nil ? .none : .userProvided)
    }

    var isCatalogBacked: Bool {
        catalogItemID != nil
    }

    var expiryStatus: ExpiryStatus {
        guard let expiryDate else { return .fresh }
        let now = Date()
        if expiryDate < now {
            return .expired
        }
        let threeDaysFromNow = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
        if expiryDate <= threeDaysFromNow {
            return .expiringSoon
        }
        return .fresh
    }

    var daysUntilExpiry: Int? {
        guard let expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day
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
        PantryItem(name: "Onions", category: .produce, quantity: 3, unit: .whole,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()), storage: .pantry, freshnessSource: .estimated),
        PantryItem(name: "Garlic", category: .produce, quantity: 1, unit: .whole,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 21, to: Date()), storage: .pantry, freshnessSource: .estimated),
        PantryItem(name: "Olive Oil", category: .oils, quantity: 500, unit: .milliliter, storage: .pantry),
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
}
