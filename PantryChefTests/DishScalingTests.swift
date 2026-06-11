import XCTest
@testable import PantryChef

final class DishScalingTests: XCTestCase {

    private func dish(servings: Int, amounts: [String?]) -> Dish {
        Dish(name: "Test", plate: .init(categories: [.produce], seed: 1), time: "10 min",
             servings: servings,
             ingredients: amounts.enumerated().map { i, a in
                 RecipeLine(key: "k\(i)", amount: a, name: "Item \(i)")
             })
    }

    func testScalesNumericAmounts() {
        let scaled = dish(servings: 2, amounts: ["300 g", "1 cup", "2"]).scaled(to: 4)
        XCTAssertEqual(scaled.servings, 4)
        XCTAssertEqual(scaled.ingredients.map(\.amount), ["600 g", "2 cup", "4"])
    }

    func testScalesDownWithFractions() {
        let scaled = dish(servings: 4, amounts: ["300 g", "1 cup"]).scaled(to: 2)
        XCTAssertEqual(scaled.ingredients.map(\.amount), ["150 g", "0.5 cup"])
    }

    func testNonNumericAndNilAmountsPassThrough() {
        let scaled = dish(servings: 2, amounts: ["to taste", nil]).scaled(to: 6)
        XCTAssertEqual(scaled.ingredients.map(\.amount), ["to taste", nil])
    }

    func testSameServingsIsIdentity() {
        let d = dish(servings: 2, amounts: ["300 g"])
        XCTAssertEqual(d.scaled(to: 2), d)
    }

    func testScaledAmountWordQuantities() {
        XCTAssertEqual(Dish.scaledAmount("half cup", by: 2), "1 cup")
        XCTAssertEqual(Dish.scaledAmount("a pinch", by: 2), "2 pinch")
        XCTAssertNil(Dish.scaledAmount("to taste", by: 2))
    }
}
