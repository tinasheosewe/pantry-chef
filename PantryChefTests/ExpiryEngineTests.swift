import XCTest
@testable import PantryChef

/// The blended fraction-of-life freshness model (spec §7): time spent in each
/// storage consumes a proportion of total life; moving re-projects the remainder.
/// Tested against the catalog-free pure math so it doesn't depend on the bundled
/// catalog (which isn't loaded in the test target).
final class ExpiryEngineTests: XCTestCase {

    func testSpendingAFullSafeLifetimeConsumesAllOfIt() {
        XCTAssertEqual(ExpiryEngine.consumedAfterStint(priorFraction: 0, daysInStint: 10, safeDays: 10),
                       1.0, accuracy: 0.0001)
    }

    func testHalfASafeLifetimeConsumesHalf() {
        XCTAssertEqual(ExpiryEngine.consumedAfterStint(priorFraction: 0, daysInStint: 5, safeDays: 10),
                       0.5, accuracy: 0.0001)
    }

    func testConsumptionAccumulatesAcrossStintsAndClampsAtOne() {
        let after = ExpiryEngine.consumedAfterStint(priorFraction: 0.8, daysInStint: 5, safeDays: 10) // +0.5
        XCTAssertEqual(after, 1.0, accuracy: 0.0001)   // clamped, not 1.3
    }

    func testFreshDaysLeftScalesWithRemainingFraction() {
        XCTAssertEqual(ExpiryEngine.freshDaysLeft(safeDays: 90, consumedFraction: 0), 90)
        XCTAssertEqual(ExpiryEngine.freshDaysLeft(safeDays: 90, consumedFraction: 0.5), 45)
        XCTAssertEqual(ExpiryEngine.freshDaysLeft(safeDays: 90, consumedFraction: 1), 0)
    }

    func testUnknownSafeLifetimeIsUnprojectable() {
        XCTAssertNil(ExpiryEngine.freshDaysLeft(safeDays: nil, consumedFraction: 0))
        XCTAssertEqual(ExpiryEngine.consumedAfterStint(priorFraction: 0.3, daysInStint: 99, safeDays: nil),
                       0.3, accuracy: 0.0001)
    }

    func testBlendedMoveExample_pantryThenFridge() {
        // 2 days of a 5-day pantry life = 0.4 consumed; moved to a 7-day fridge life
        // leaves 0.6 × 7 ≈ 4 days.
        let consumed = ExpiryEngine.consumedAfterStint(priorFraction: 0, daysInStint: 2, safeDays: 5)
        XCTAssertEqual(consumed, 0.4, accuracy: 0.0001)
        XCTAssertEqual(ExpiryEngine.freshDaysLeft(safeDays: 7, consumedFraction: consumed), 4)
    }

    func testStockItemMovedFoldsTheStintAndResetsAnchor() {
        let now = Date()
        let item = StockItem(
            key: "x", name: "X", plate: .init(categories: [.produce], seed: 1),
            section: .have, measure: .perishable(detail: "300 g", daysLeft: 5),
            lastConfirmed: now, catalogItemID: nil, category: .produce,
            storage: .refrigerated, storageSince: now.addingTimeInterval(-2 * 86_400))
        let moved = item.moved(to: .frozen, now: now)
        XCTAssertEqual(moved.storage, .frozen)
        XCTAssertEqual(moved.storageSince.timeIntervalSince(now), 0, accuracy: 1)
        // No catalog identity here, so the projection is a no-op but the move is clean.
        XCTAssertEqual(moved.consumedFraction, 0, accuracy: 0.0001)
    }
}
