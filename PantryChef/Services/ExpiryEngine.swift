import Foundation

/// The food-freshness clock (distinct from ConfidenceEngine's *knowledge* clock):
/// how long an item stays good, blended across storage moves. Pure and
/// deterministic — `now` is always injected (spec §7, §15).
///
/// Model: each storage location grants the item a safe lifetime S (the catalog's
/// freshness range for that location). Spending `t` days in a location consumes
/// `t / S` of the item's total life; it spoils when the cumulative consumed
/// fraction reaches 1. So a tomato that spent half its pantry life before going to
/// the fridge starts the fridge with half its fridge life left — "proportion of
/// safe time spent in location 1, remainder in location 2."
enum ExpiryEngine {

    private static let secondsPerDay: TimeInterval = 86_400

    /// Representative safe days for a catalog item kept in `storage` — the midpoint
    /// of its freshness range there, falling back to its representative shelf life.
    /// nil when we have no catalog identity (can't project).
    static func safeDays(catalogItemID: String?, storage: PantryStorage) -> Int? {
        guard let id = catalogItemID, let item = PantryCatalog.item(id: id) else { return nil }
        return ResolutionClassifier.safeDays(item, in: storage)
    }

    // MARK: Pure math (catalog-free, fully unit-testable)

    /// Days left given a known safe lifetime and the fraction of life already used.
    static func freshDaysLeft(safeDays: Int?, consumedFraction: Double) -> Int? {
        guard let s = safeDays, s > 0 else { return nil }
        return max(0, Int((1 - clamp(consumedFraction)) * Double(s)))
    }

    /// Consumed fraction after a stint of `daysInStint` against a known safe lifetime.
    static func consumedAfterStint(priorFraction: Double, daysInStint: Double, safeDays: Int?) -> Double {
        guard let s = safeDays, s > 0 else { return clamp(priorFraction) }
        return clamp(priorFraction + max(0, daysInStint) / Double(s))
    }

    // MARK: Catalog conveniences (resolve safe days, then defer to the pure math)

    /// Days left for an item freshly placed in `storage`, given prior consumption.
    static func freshDaysLeft(catalogItemID: String?, storage: PantryStorage,
                              consumedFraction: Double) -> Int? {
        freshDaysLeft(safeDays: safeDays(catalogItemID: catalogItemID, storage: storage),
                      consumedFraction: consumedFraction)
    }

    /// Consumed fraction after spending `daysInStint` in `storage`.
    static func consumedAfterStint(priorFraction: Double, daysInStint: Double,
                                   storage: PantryStorage, catalogItemID: String?) -> Double {
        consumedAfterStint(priorFraction: priorFraction, daysInStint: daysInStint,
                           safeDays: safeDays(catalogItemID: catalogItemID, storage: storage))
    }

    /// Whole days between two dates (>= 0).
    static func daysBetween(_ earlier: Date, _ later: Date) -> Double {
        max(0, later.timeIntervalSince(earlier) / secondsPerDay)
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
