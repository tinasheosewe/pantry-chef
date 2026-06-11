import Foundation

/// Computes how confident the app is that a tracked item is still present, decaying
/// from the moment of last evidence on a half-life derived from the item's shelf
/// life and tracking class (spec §7). Pure and deterministic — no clock, no state,
/// no I/O; `now` is always injected so behaviour is fully reproducible in tests.
///
/// This owns the *knowledge* clock only. Food spoilage (expiry dates) is a separate
/// concern handled elsewhere; the two clocks are deliberately not conflated.
enum ConfidenceEngine {

    /// Continuous confidence in `0...1` that the item is still in the kitchen.
    /// 1.0 at the instant of confirmation, halving every knowledge half-life.
    static func confidence(
        lastConfirmed: Date,
        now: Date,
        shelfLifeDays: Int?,
        resolutionClass: ResolutionClass
    ) -> Double {
        let elapsedDays = max(0, now.timeIntervalSince(lastConfirmed) / secondsPerDay)
        let halfLife = knowledgeHalfLifeDays(shelfLifeDays: shelfLifeDays,
                                             resolutionClass: resolutionClass)
        return pow(0.5, elapsedDays / halfLife)
    }

    /// Bucketed certainty for wording and decisions.
    static func certainty(
        lastConfirmed: Date,
        now: Date,
        shelfLifeDays: Int?,
        resolutionClass: ResolutionClass
    ) -> ItemCertainty {
        bucket(confidence(lastConfirmed: lastConfirmed, now: now,
                          shelfLifeDays: shelfLifeDays, resolutionClass: resolutionClass))
    }

    /// Certainty for a catalog item kept in a given storage, reading its shelf life
    /// and tracking class straight from the catalog.
    static func certainty(
        for item: PantryCatalogItemDefinition,
        storage: PantryStorage,
        lastConfirmed: Date,
        now: Date
    ) -> ItemCertainty {
        certainty(lastConfirmed: lastConfirmed, now: now,
                  shelfLifeDays: shelfLife(of: item, in: storage),
                  resolutionClass: item.resolutionClass)
    }

    /// The knowledge half-life (days): the food shelf life scaled by the class's
    /// factor, floored so unknown or very short lives still behave sanely.
    static func knowledgeHalfLifeDays(
        shelfLifeDays: Int?,
        resolutionClass: ResolutionClass
    ) -> Double {
        let base = Double(shelfLifeDays ?? 0)
        return max(KitchenConfig.Confidence.minHalfLifeDays, base * halfLifeFactor(for: resolutionClass))
    }

    /// Maps a continuous confidence to a certainty bucket.
    static func bucket(_ confidence: Double) -> ItemCertainty {
        if confidence >= KitchenConfig.Confidence.confirmedAbove { return .confirmed }
        if confidence >= KitchenConfig.Confidence.probableAbove { return .probable }
        if confidence >= KitchenConfig.Confidence.uncertainAbove { return .uncertain }
        return .likelyGone
    }

    // MARK: - Private

    private static let secondsPerDay: TimeInterval = 86_400

    private static func halfLifeFactor(for resolutionClass: ResolutionClass) -> Double {
        switch resolutionClass {
        case .perishable: return KitchenConfig.Confidence.perishableHalfLifeFactor
        case .semiCountable: return KitchenConfig.Confidence.semiCountableHalfLifeFactor
        case .staple: return KitchenConfig.Confidence.stapleHalfLifeFactor
        }
    }

    private static func shelfLife(of item: PantryCatalogItemDefinition, in storage: PantryStorage) -> Int? {
        if let range = item.freshnessByStorage[storage] {
            return (range.lowerBound + range.upperBound) / 2
        }
        return ResolutionClassifier.representativeShelfLifeDays(item)
    }
}
