import Foundation

/// A resolution-independent colour with Double components, kept free of SwiftUI so
/// the plate *logic* (composition, renderer, tests) has zero UI dependency. The
/// SwiftUI layer converts these to `Color` at draw time.
struct RGBA: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    /// Linear blend toward `other` by `t` in 0...1.
    func blended(to other: RGBA, _ t: Double) -> RGBA {
        let u = min(max(t, 0), 1)
        return RGBA(r: r + (other.r - r) * u,
                    g: g + (other.g - g) * u,
                    b: b + (other.b - b) * u,
                    a: a + (other.a - a) * u)
    }

    func darkened(_ amount: Double) -> RGBA { blended(to: RGBA(r: 0, g: 0, b: 0), amount) }
    func lightened(_ amount: Double) -> RGBA { blended(to: RGBA(r: 1, g: 1, b: 1), amount) }
}

/// One ingredient family's share of a dish, used to compose its plate's look.
struct CategoryWeight: Equatable, Sendable {
    let category: FoodCategory
    let weight: Double
}

/// The deterministic input to the plate renderer: which ingredient families a dish
/// is made of, plus a stable seed (e.g. a recipe id hash) so the same dish always
/// renders the same plate while different dishes look distinct.
struct PlateComposition: Equatable, Sendable {
    /// Category shares, most prominent first. Empty is valid (renders a plain plate).
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

/// A speck of food/garnish on the plate.
struct Fleck: Equatable, Sendable {
    /// Position in the unit disc (centre origin, radius 1).
    let x: Double
    let y: Double
    let radius: Double
    let color: RGBA
}

/// The fully-resolved, deterministic description of a procedural plate. Pure data:
/// the SwiftUI `PlateView` simply draws it, and tests assert on it directly.
struct PlateSpec: Equatable, Sendable {
    let ceramic: RGBA       // the plate rim/base
    let food: RGBA          // the central food mound
    let flecks: [Fleck]     // ingredient/garnish specks
}
