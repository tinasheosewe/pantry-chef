import XCTest
@testable import PantryChef

/// The nutrition estimate is deterministic — gram weight × per-100g macros, summed and
/// divided by servings — so a recipe page can show believable, labelled numbers offline.
final class NutritionEstimatorTests: XCTestCase {

    private func dish(_ lines: [RecipeLine], servings: Int = 2) -> Dish {
        Dish(name: "Test", plate: .init(categories: [.protein], seed: 1), time: "20 min",
             servings: servings, ingredients: lines)
    }

    func testMassAmountTimesMacrosDividedByServings() {
        // 400 g chicken thigh @ 209 kcal/100g = 836 kcal total, over 2 servings = 418.
        let d = dish([RecipeLine(key: "chicken thighs", amount: "400 g", name: "Chicken thighs",
                                 catalogItemID: "chicken-thigh")])
        let n = NutritionEstimator.estimate(d)
        XCTAssertEqual(n?.calories, 418)
        XCTAssertEqual(n?.protein, 52)   // 26/100 × 400 = 104, /2 = 52
        XCTAssertEqual(n?.fat, 22)       // 11/100 × 400 = 44, /2 = 22
    }

    func testServingsDividesThePerServingValue() {
        let lines = [RecipeLine(key: "chicken thighs", amount: "400 g", name: "Chicken thighs",
                                catalogItemID: "chicken-thigh")]
        let two = NutritionEstimator.estimate(dish(lines, servings: 2))!
        let four = NutritionEstimator.estimate(dish(lines, servings: 4))!
        XCTAssertEqual(four.calories, two.calories / 2, "more servings → fewer calories each")
    }

    func testUnknownIngredientFallsBackToItsCategory() {
        // An olive-oil line: 1 tbsp ≈ 13.6 g @ 884 kcal/100g ≈ 120 kcal total, /2 = 60.
        let d = dish([RecipeLine(key: "olive oil", amount: "1 tbsp", name: "Olive oil",
                                 catalogItemID: "olive-oil")])
        let n = NutritionEstimator.estimate(d)
        XCTAssertNotNil(n)
        XCTAssertGreaterThan(n!.calories, 40)
        XCTAssertEqual(n!.carbs, 0, "oil has no carbs")
    }

    func testNoIngredientsYieldsNoEstimate() {
        XCTAssertNil(NutritionEstimator.estimate(dish([])), "nothing to estimate from → nil, not zeros")
    }

    func testEstimateIsPositiveForAFullSeedRecipe() {
        // Every seeded recipe should produce a believable, positive estimate.
        let store = KitchenStore()
        let sample = store.library.prefix(20)
        for d in sample {
            if let n = NutritionEstimator.estimate(d) {
                XCTAssertGreaterThan(n.calories, 0, "\(d.name) should have positive calories")
                XCTAssertLessThan(n.calories, 4000, "\(d.name) per-serving calories shouldn't be absurd")
            }
        }
    }
}
