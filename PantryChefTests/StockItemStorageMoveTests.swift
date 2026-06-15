import XCTest
@testable import PantryChef

/// `StockItem.moved` honours the Settings preference: the default re-projects the
/// freshness clock for the new location, while `adjustDaysLeft: false` only relabels
/// where the item is kept and leaves the user's own estimate untouched.
final class StockItemStorageMoveTests: XCTestCase {
    private let now = Date()
    private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    private func fridgeItem() -> StockItem {
        StockItem(key: "spinach", name: "Baby spinach",
                  plate: .init(categories: [.produce], seed: 1),
                  section: .useSoon, measure: .perishable(detail: "300 g", daysLeft: 4),
                  lastConfirmed: daysAgo(2), catalogItemID: "spinach",
                  category: .produce, storage: .refrigerated, storageSince: daysAgo(2))
    }

    func testAdjustingReprojectsTheClock() {
        let moved = fridgeItem().moved(to: .frozen, now: now, adjustDaysLeft: true)
        XCTAssertEqual(moved.storage, .frozen)
        XCTAssertEqual(moved.storageSince, now, "the new stint anchors at the move")
        XCTAssertGreaterThan(moved.consumedFraction, 0, "time already spent is folded in")
    }

    func testNotAdjustingOnlyRelabelsStorage() {
        let original = fridgeItem()
        let moved = original.moved(to: .frozen, now: now, adjustDaysLeft: false)
        XCTAssertEqual(moved.storage, .frozen)
        // Everything that drives the freshness estimate is left exactly as it was.
        if case .perishable(_, let days) = moved.measure {
            XCTAssertEqual(days, 4, "days-left must be untouched")
        } else { XCTFail("measure changed shape") }
        XCTAssertEqual(moved.storageSince, original.storageSince)
        XCTAssertEqual(moved.consumedFraction, original.consumedFraction)
    }

    func testNoOpWhenStorageUnchanged() {
        let original = fridgeItem()
        XCTAssertEqual(original.moved(to: .refrigerated, now: now), original)
    }
}
