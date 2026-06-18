import XCTest
@testable import PantryChef

/// The shopping list dedups by name and is *additive*: adding more of something
/// already listed sums the quantities rather than overwriting or duplicating.
@MainActor
final class ShoppingListTests: XCTestCase {

    // MARK: - combinedAmount (the pure additive math)

    func testSameUnitAmountsSum() {
        XCTAssertEqual(KitchenStore.combinedAmount("2 L", "2 L"), "4 L")
        XCTAssertEqual(KitchenStore.combinedAmount("300 g", "200 g"), "500 g")
    }

    func testUnitlessQuantitiesSum() {
        XCTAssertEqual(KitchenStore.combinedAmount("12", "6"), "18")
    }

    func testDifferentUnitsKeepBoth() {
        XCTAssertEqual(KitchenStore.combinedAmount("2 L", "500 ml"), "2 L + 500 ml")
    }

    func testBlankSideLeavesTheOtherUntouched() {
        XCTAssertEqual(KitchenStore.combinedAmount("2 L", nil), "2 L")
        XCTAssertEqual(KitchenStore.combinedAmount(nil, "2 L"), "2 L")
        XCTAssertNil(KitchenStore.combinedAmount(nil, nil))
        XCTAssertNil(KitchenStore.combinedAmount("", ""))
    }

    func testNonNumericQuantityKeepsBoth() {
        XCTAssertEqual(KitchenStore.combinedAmount("a pinch", "1 tsp"), "a pinch + 1 tsp")
    }

    func testFractionalSumStaysClean() {
        XCTAssertEqual(KitchenStore.combinedAmount("1.5 kg", "0.5 kg"), "2 kg")
    }

    // MARK: - addToList is additive + dedups

    func testAddingAlreadyListedItemIsAdditive() {
        let store = KitchenStore()
        store.shoppingList = []
        store.addToList(name: "Milk", amount: "2 L")
        store.addToList(name: "milk", amount: "2 L")   // same item, different case
        let milk = store.shoppingList.filter { $0.name.lowercased() == "milk" }
        XCTAssertEqual(milk.count, 1, "should dedup to one line")
        XCTAssertEqual(milk.first?.amount, "4 L", "quantities should add")
    }

    func testAddingNewItemAppends() {
        let store = KitchenStore()
        store.shoppingList = []
        store.addToList(name: "Eggs", amount: "12")
        store.addToList(name: "Lemon")
        XCTAssertEqual(store.shoppingList.count, 2)
    }

    // MARK: - aisle grouping

    func testGroupingIsInDisplayOrderAndDropsEmpties() {
        let store = KitchenStore()
        store.shoppingList = [ShoppingEntry(name: "Milk"), ShoppingEntry(name: "Spinach")]
        let groups = store.shoppingByCategory(store.shoppingList)
        // Produce sorts before Dairy in displayOrder, so spinach's group leads milk's.
        let cats = groups.map { $0.0 }
        if let p = cats.firstIndex(of: .produce), let d = cats.firstIndex(of: .dairy) {
            XCTAssertLessThan(p, d)
        }
        XCTAssertEqual(groups.reduce(0) { $0 + $1.1.count }, 2, "every entry is grouped exactly once")
    }
}
