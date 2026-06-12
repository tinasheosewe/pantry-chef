import Foundation

/// The single home for *tuning* values — numbers that shape behaviour but encode
/// no domain knowledge. Domain facts (shelf lives, units, swaps, palettes) live in
/// the catalog pipeline as validated data; only knobs live here. Grouped by
/// concern so each area owns its own constants without a shared dumping ground.
///
/// Rule of thumb: if a value would need editing because the *world* changed (a new
/// ingredient, a corrected shelf life), it does not belong here — it belongs in the
/// catalog. If it would change because we re-tuned *behaviour*, it belongs here.
enum KitchenConfig {

    /// Thresholds for classifying an ingredient's tracking semantics (spec §7).
    enum Resolution {
        /// At or above this representative shelf life (days), an item is treated as
        /// a pantry *staple* — tracked as a gauge, never decremented per pinch.
        static let stapleMinShelfLifeDays = 120
    }

    /// Knowledge-certainty decay (spec §7 trust layer): how fast the app stops
    /// trusting its own inventory record as time passes since the last evidence.
    enum Confidence {
        /// Multipliers turning an item's *food* shelf life into its *knowledge*
        /// half-life — how long until we're half as sure it's still in the kitchen.
        /// Staples linger in the cupboard far beyond perishables, so their record
        /// stays trustworthy much longer.
        static let perishableHalfLifeFactor = 1.0
        static let semiCountableHalfLifeFactor = 1.5
        static let stapleHalfLifeFactor = 4.0

        /// Floor on the knowledge half-life (days) so even short-dated items don't
        /// decay to "gone" the instant their food clock runs out, and so the math
        /// never divides by zero when shelf life is unknown.
        static let minHalfLifeDays = 2.0

        /// Confidence (0...1) bucket boundaries: at or above each → that certainty.
        static let confirmedAbove = 0.80
        static let probableAbove = 0.50
        static let uncertainAbove = 0.20
    }

    /// Tier-1 plate rendering (spec §10): spend and size knobs for the one-time
    /// AI plate renders. Art direction lives with `PlateRenderLibrary`.
    enum Render {
        /// Image model + quality per render call (the cost lever).
        static let model = "gpt-image-1"
        static let quality = "medium"
        /// Hard cap on *new* renders started per app launch, bounding worst-case
        /// spend even if the library suddenly grows. Cached plates are free.
        static let maxNewPerLaunch = 12
        /// Seconds before an image render attempt is abandoned.
        static let timeoutSeconds: TimeInterval = 120
        /// Longest side (px) a render is downscaled to before caching.
        static let cachedPixelSize: CGFloat = 640
    }
}
