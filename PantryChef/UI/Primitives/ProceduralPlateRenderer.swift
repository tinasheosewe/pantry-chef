import Foundation

/// A small, fast, fully deterministic PRNG (SplitMix64). Seeded identically, it
/// always produces the same sequence — the backbone of reproducible plate art.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Builds a `PlateSpec` from a dish's ingredient composition (tier-0 imagery, spec
/// §10). Pure and deterministic: the same composition always yields the same plate,
/// while different dishes look distinct. No SwiftUI, no I/O — trivially testable.
enum ProceduralPlateRenderer {

    /// Plate-art tuning. Named knobs, one place — never bare literals in the logic.
    private enum K {
        static let minFlecks = 5
        static let maxFlecks = 16
        static let flecksPerCategory = 3
        static let foodDiscRadius = 0.62     // food mound radius within the unit plate
        static let minFleckRadius = 0.05
        static let maxFleckRadius = 0.12
        static let fleckColorJitter = 0.18   // how far a fleck strays from its tone
        /// Fallback food tone when a dish has no resolved categories.
        static let neutralFood = RGBA(r: 0.80, g: 0.74, b: 0.62)
    }

    static func render(_ composition: PlateComposition) -> PlateSpec {
        var rng = SeededGenerator(seed: composition.seed)
        let palette = normalized(composition.weights)

        let food = foodBaseColor(palette)
        let count = fleckCount(distinctCategories: palette.count)
        var flecks: [Fleck] = []
        flecks.reserveCapacity(count)
        for _ in 0..<count {
            flecks.append(makeFleck(using: &rng, palette: palette))
        }
        return PlateSpec(ceramic: PlatePalette.ceramic, food: food, flecks: flecks)
    }

    // MARK: - Composition

    /// Drops non-positive weights and rescales the rest to sum to 1.
    private static func normalized(_ weights: [CategoryWeight]) -> [CategoryWeight] {
        let positive = weights.filter { $0.weight > 0 }
        let total = positive.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return [] }
        return positive.map { CategoryWeight(category: $0.category, weight: $0.weight / total) }
    }

    /// Weighted blend of category tones; neutral when there's nothing to go on.
    private static func foodBaseColor(_ palette: [CategoryWeight]) -> RGBA {
        guard !palette.isEmpty else { return K.neutralFood }
        var r = 0.0, g = 0.0, b = 0.0
        for cw in palette {
            let tone = PlatePalette.tone(for: cw.category)
            r += tone.r * cw.weight
            g += tone.g * cw.weight
            b += tone.b * cw.weight
        }
        return RGBA(r: r, g: g, b: b)
    }

    private static func fleckCount(distinctCategories: Int) -> Int {
        let raw = max(1, distinctCategories) * K.flecksPerCategory
        return min(K.maxFlecks, max(K.minFlecks, raw))
    }

    // MARK: - Flecks

    private static func makeFleck(using rng: inout SeededGenerator, palette: [CategoryWeight]) -> Fleck {
        let tone = sampleTone(using: &rng, palette: palette)
        let jitter = Double.random(in: -K.fleckColorJitter...K.fleckColorJitter, using: &rng)
        let color = jitter >= 0 ? tone.lightened(jitter) : tone.darkened(-jitter)

        // Uniform point in the food disc: r = sqrt(u) keeps density even by area.
        let radius = K.foodDiscRadius * Double.random(in: 0...1, using: &rng).squareRoot()
        let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
        let size = Double.random(in: K.minFleckRadius...K.maxFleckRadius, using: &rng)

        return Fleck(x: radius * cos(angle), y: radius * sin(angle), radius: size, color: color)
    }

    /// Picks a category tone in proportion to its weight; falls back to neutral.
    private static func sampleTone(using rng: inout SeededGenerator, palette: [CategoryWeight]) -> RGBA {
        guard !palette.isEmpty else { return K.neutralFood }
        let u = Double.random(in: 0..<1, using: &rng)
        var cumulative = 0.0
        for cw in palette {
            cumulative += cw.weight
            if u < cumulative { return PlatePalette.tone(for: cw.category) }
        }
        return PlatePalette.tone(for: palette[palette.count - 1].category)
    }
}
