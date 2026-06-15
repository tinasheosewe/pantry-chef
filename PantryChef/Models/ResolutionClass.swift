import Foundation

/// How an ingredient is tracked, derived from catalog data rather than any
/// hardcoded list of names. Drives quantity display and whether using the item
/// decrements stock per-use (spec §7, "track at decision resolution").
enum ResolutionClass: String, Codable, Sendable, CaseIterable {
    /// Short/medium life, measured by weight or volume; decremented per use.
    /// (spinach, salmon, milk, yogurt)
    case perishable
    /// Naturally counted in whole pieces; decremented per unit. (eggs, onions, lemons)
    case semiCountable
    /// Long-lived cupboard good; tracked as a gauge, never per-pinch. (flour, oil, rice, spices)
    case staple
}

/// Classifies an ingredient's tracking semantics purely and deterministically
/// from catalog data. The honest primary signal is shelf life: long-lived goods
/// are staples; among the rest, anything the catalog counts in pieces is
/// semi-countable, and the remainder is perishable. Category is consulted only as
/// a conservative fallback when an item carries no freshness data at all.
enum ResolutionClassifier {

    static func classify(_ item: PantryCatalogItemDefinition) -> ResolutionClass {
        if let days = representativeShelfLifeDays(item),
           days >= KitchenConfig.Resolution.stapleMinShelfLifeDays {
            return .staple
        }
        if hasShelfLifeData(item) {
            return item.isCountable ? .semiCountable : .perishable
        }
        // No freshness data: fall back to taxonomy, conservatively — never assume
        // long life, since over-tracking is recoverable but over-claiming is not.
        if item.category.isTypicallyShelfStable { return .staple }
        return item.isCountable ? .semiCountable : .perishable
    }

    /// Representative shelf life: the midpoint of the range for the item's default
    /// storage, falling back to the longest range it defines. Nil when no data.
    static func representativeShelfLifeDays(_ item: PantryCatalogItemDefinition) -> Int? {
        if let range = item.freshnessByStorage[item.defaultStorage] {
            return midpoint(range)
        }
        return item.freshnessByStorage.values.map(midpoint).max()
    }

    /// Safe days for an item kept in a *specific* storage — the midpoint of that
    /// storage's freshness range, falling back to the representative shelf life.
    /// The single source of this lookup; ExpiryEngine and ConfidenceEngine both
    /// call here rather than re-deriving it (DRY — consolidation audit §3).
    static func safeDays(_ item: PantryCatalogItemDefinition, in storage: PantryStorage) -> Int? {
        if let range = item.freshnessByStorage[storage] { return midpoint(range) }
        return representativeShelfLifeDays(item)
    }

    private static func midpoint(_ range: ClosedRange<Int>) -> Int {
        (range.lowerBound + range.upperBound) / 2
    }

    private static func hasShelfLifeData(_ item: PantryCatalogItemDefinition) -> Bool {
        !item.freshnessByStorage.isEmpty
    }
}

extension PantryCatalogItemDefinition {
    /// Naturally counted in whole pieces — the catalog knows its per-piece weight.
    var isCountable: Bool { gramsPerPiece != nil }

    /// This item's tracking semantics (see `ResolutionClassifier`).
    var resolutionClass: ResolutionClass { ResolutionClassifier.classify(self) }
}

extension FoodCategory {
    /// Whether items in this category are, by default, shelf-stable cupboard goods.
    /// Used only as a fallback when an item carries no freshness data — the
    /// per-item shelf life is always preferred when present.
    var isTypicallyShelfStable: Bool {
        switch self {
        case .oils, .spices, .grains, .pasta, .bakingSupplies,
             .canned, .legumes, .condiments, .nuts, .beverages, .alcohol:
            return true
        case .produce, .protein, .dairy, .breads, .frozenFoods, .snacks, .other:
            return false
        }
    }
}
