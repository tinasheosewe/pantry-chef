import XCTest
@testable import PantryChef

/// The trust loop's model contract (spec §7): a stock item's certainty decays from
/// `lastConfirmed`, staples are effectively always-confirmed, and only stale
/// perishables/leftovers ask to be checked.
final class StockItemCertaintyTests: XCTestCase {
    private let now = Date()
    private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    private func perishable(daysLeft: Int?, confirmed: Date) -> StockItem {
        StockItem(key: "spinach", name: "Spinach",
                  plate: .init(categories: [.produce], seed: 1),
                  section: .useSoon, measure: .perishable(detail: "300 g", daysLeft: daysLeft.map(Double.init)),
                  lastConfirmed: confirmed)
    }

    func testFreshlyConfirmedPerishableIsCertainAndNeedsNoCheck() {
        let item = perishable(daysLeft: 5, confirmed: now)
        XCTAssertEqual(item.certainty(now: now), .confirmed)
        XCTAssertFalse(item.needsCheck(now: now))
    }

    func testStalePerishableDecaysAndAsksToBeChecked() {
        // Half-life ≈ 5 days; ~22 days later we're well past "uncertain".
        let item = perishable(daysLeft: 5, confirmed: daysAgo(22))
        XCTAssertLessThanOrEqual(item.certainty(now: now), .uncertain)
        XCTAssertTrue(item.needsCheck(now: now))
    }

    func testStapleNeverNeedsCheckEvenWhenAncient() {
        let item = StockItem(key: "flour", name: "Flour",
                             plate: .init(categories: [.bakingSupplies], seed: 2),
                             section: .staples, measure: .staple(.inStock),
                             lastConfirmed: daysAgo(120))
        XCTAssertEqual(item.certainty(now: now), .confirmed)
        XCTAssertFalse(item.needsCheck(now: now))
    }

    func testReconfirmingResetsCertainty() {
        var item = perishable(daysLeft: 5, confirmed: daysAgo(30))
        XCTAssertTrue(item.needsCheck(now: now))
        item.lastConfirmed = now   // what reconfirm(_:) does
        XCTAssertEqual(item.certainty(now: now), .confirmed)
        XCTAssertFalse(item.needsCheck(now: now))
    }
}
