import Foundation

/// One ingredient family's share of a dish.
struct CategoryWeight: Equatable, Sendable {
    let category: FoodCategory
    let weight: Double
}

/// A dish's ingredient-family makeup plus a stable seed. Carried by every model
/// that shows a plate; the emoji face derives from it (and the dish name), and the
/// future AI-render tier will too.
struct PlateComposition: Equatable, Sendable {
    /// Category shares, most prominent first. Empty is valid.
    let weights: [CategoryWeight]
    let seed: UInt64

    init(weights: [CategoryWeight], seed: UInt64) {
        self.weights = weights
        self.seed = seed
    }

    /// Convenience: equal-weighted categories in the given order.
    init(categories: [FoodCategory], seed: UInt64) {
        self.init(weights: categories.map { CategoryWeight(category: $0, weight: 1) }, seed: seed)
    }
}
