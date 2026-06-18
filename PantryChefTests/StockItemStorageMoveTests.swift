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

    /// Greek yogurt has no Frozen range in the catalog — the case the user hit. Its
    /// freezer life is *estimated* by scaling, so it exercises the fallback path.
    private func greekYogurt(fridgeDaysLeft: Int) -> StockItem {
        StockItem(key: "gy", name: "Greek yogurt",
                  plate: .init(categories: [.dairy], seed: 1),
                  section: .have, measure: .perishable(detail: "500 g", daysLeft: Double(fridgeDaysLeft)),
                  lastConfirmed: now, catalogItemID: "greek-yogurt",
                  category: .dairy, storage: .refrigerated, storageSince: now)
    }

    private func daysLeft(_ item: StockItem) -> Int? {
        if case .perishable(_, let d) = item.measure { return d.map { Int($0) } }
        return nil
    }

    func testAdjustingReprojectsTheClock() {
        let moved = fridgeItem().moved(to: .frozen, now: now, adjustDaysLeft: true)
        XCTAssertEqual(moved.storage, .frozen)
        XCTAssertEqual(moved.storageSince, now, "the new stint anchors at the move")
        // The shown estimate (4 of a ~5-day fridge life) carries over as consumed.
        XCTAssertGreaterThan(moved.consumedFraction, 0, "the used share carries over")
    }

    func testFreezingExtendsShelfLifeBeyondTheFridge() {
        let frozen = greekYogurt(fridgeDaysLeft: 3).moved(to: .frozen, now: now)
        XCTAssertGreaterThan(daysLeft(frozen) ?? 0, 3,
                             "freezing must extend the days-left, not inherit the fridge number")
    }

    func testStorageRoundTripRestoresTheOriginalDaysLeft() {
        let fridge = greekYogurt(fridgeDaysLeft: 3)
        let back = fridge.moved(to: .frozen, now: now).moved(to: .refrigerated, now: now)
        XCTAssertEqual(daysLeft(back), 3,
                       "fridge → freezer → fridge must land back on the original estimate")
    }

    func testRepeatedStorageChangesDoNotDrift() {
        var item = greekYogurt(fridgeDaysLeft: 5)
        let start = daysLeft(item)
        for _ in 0..<4 {
            item = item.moved(to: .frozen, now: now)
            item = item.moved(to: .refrigerated, now: now)
        }
        XCTAssertEqual(daysLeft(item), start, "a sequence of moves must stay stable, not creep")
    }

    func testColderStorageEstimatesAreLongerWhenTheCatalogIsSilent() {
        // Greek yogurt only defines a fridge range; pantry/freezer are estimated and
        // must respect the ordering pantry < fridge < freezer.
        let pantry = ExpiryEngine.safeDays(catalogItemID: "greek-yogurt", storage: .pantry)
        let fridge = ExpiryEngine.safeDays(catalogItemID: "greek-yogurt", storage: .refrigerated)
        let frozen = ExpiryEngine.safeDays(catalogItemID: "greek-yogurt", storage: .frozen)
        XCTAssertNotNil(frozen); XCTAssertNotNil(fridge); XCTAssertNotNil(pantry)
        XCTAssertGreaterThan(frozen ?? 0, fridge ?? 0)
        XCTAssertLessThan(pantry ?? .max, fridge ?? 0)
    }

    private func spinach(fridgeDaysLeft: Int) -> StockItem {
        StockItem(key: "spinach", name: "Baby spinach", plate: .init(categories: [.produce], seed: 1),
                  section: .useSoon, measure: .perishable(detail: "300 g", daysLeft: Double(fridgeDaysLeft)),
                  lastConfirmed: now, catalogItemID: "spinach",
                  category: .produce, storage: .refrigerated, storageSince: now)
    }

    /// The reported bug: spinach (explicit fridge AND freezer ranges) dropped 2 → 1 → 0
    /// across fridge ↔ freezer moves because the projection truncated a partial day each
    /// time. Round-trips must now hold steady.
    func testSpinachStorageRoundTripDoesNotDecay() {
        var item = spinach(fridgeDaysLeft: 2)
        let start = daysLeft(item)
        for _ in 0..<4 {
            item = item.moved(to: .frozen, now: now)
            XCTAssertGreaterThan(daysLeft(item) ?? 0, start ?? 0, "the freezer extends shelf life")
            item = item.moved(to: .refrigerated, now: now)
            XCTAssertEqual(daysLeft(item), start, "back in the fridge it must land on the original, not decay")
        }
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

    func testDaysLeftTicksDownWithTheCalendar() {
        // Logged today with 10 days, it reads 1 nine days on — and never goes negative.
        let item = greekYogurt(fridgeDaysLeft: 10)
        XCTAssertEqual(item.daysLeft(now: now), 10)
        XCTAssertEqual(item.daysLeft(now: now.addingTimeInterval(9 * 86_400)), 1)
        XCTAssertEqual(item.daysLeft(now: now.addingTimeInterval(30 * 86_400)), 0, "never negative")
    }

    func testMovingAfterTimePassesProjectsFromWhatIsLeftNow() {
        // Spinach with 4 fridge-days, logged 2 days ago, has 2 left now; moving it must
        // project from that 2 — the same as a fresh item that genuinely has 2 days left.
        let aged = fridgeItem().moved(to: .frozen, now: now)             // 4 days, aged 2
        let freshTwo = StockItem(key: "spinach", name: "Baby spinach",
                                 plate: .init(categories: [.produce], seed: 1),
                                 section: .useSoon, measure: .perishable(detail: "300 g", daysLeft: 2),
                                 lastConfirmed: now, catalogItemID: "spinach",
                                 category: .produce, storage: .refrigerated, storageSince: now)
            .moved(to: .frozen, now: now)
        XCTAssertEqual(daysLeft(aged), daysLeft(freshTwo))
    }
}
