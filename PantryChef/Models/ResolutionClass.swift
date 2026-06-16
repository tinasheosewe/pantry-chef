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
        anchorShelfLife(item)?.days
    }

    /// Safe days for an item kept in a *specific* storage — the midpoint of that
    /// storage's freshness range. When the catalog doesn't specify *this* storage,
    /// estimate it by scaling the item's best-known shelf life by the relative
    /// preservation weight of the two locations, so colder storage extends life (and
    /// a storage move stays reversible) instead of inheriting an unrelated number —
    /// the old fallback handed the freezer the fridge's days, making freezing a no-op.
    /// An explicit range always wins. The single source of this lookup; ExpiryEngine
    /// and ConfidenceEngine both call here rather than re-deriving it (DRY —
    /// consolidation audit §3).
    static func safeDays(_ item: PantryCatalogItemDefinition, in storage: PantryStorage) -> Int? {
        if let range = item.freshnessByStorage[storage] { return midpoint(range) }
        guard let anchor = anchorShelfLife(item) else { return nil }
        if anchor.storage == storage { return anchor.days }
        let scaled = Double(anchor.days) * preservationWeight(storage) / preservationWeight(anchor.storage)
        return max(1, Int(scaled.rounded()))
    }

    /// The item's most representative known shelf life and the storage it came from:
    /// its default storage when the catalog defines a range there, else the
    /// longest-keeping range it defines. nil when the item carries no freshness data.
    private static func anchorShelfLife(_ item: PantryCatalogItemDefinition) -> (storage: PantryStorage, days: Int)? {
        if let range = item.freshnessByStorage[item.defaultStorage] {
            return (item.defaultStorage, midpoint(range))
        }
        return item.freshnessByStorage
            .max { midpoint($0.value) < midpoint($1.value) }
            .map { ($0.key, midpoint($0.value)) }
    }

    /// Relative shelf-life weight per storage tier — roughly how much longer food
    /// keeps as it gets colder. Used only to estimate a storage the catalog leaves
    /// unspecified (an explicit range always wins). Calibrated to the catalog's own
    /// cross-storage medians at the conservative end (fridge ≈ 2× pantry, freezer
    /// ≈ 6× fridge) so we extend life without over-claiming it.
    private static func preservationWeight(_ storage: PantryStorage) -> Double {
        switch storage {
        case .pantry:       return 1
        case .refrigerated: return 2
        case .frozen:       return 12
        }
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
