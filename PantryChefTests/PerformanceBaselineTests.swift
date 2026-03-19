import QuartzCore
import XCTest
@testable import PantryChef

@MainActor
final class PerformanceBaselineTests: XCTestCase {
    private enum Budget {
        static let recipeFilteringAverageSeconds = 0.250
        static let pantryMatchAverageSeconds = 1.100
    }

    func testRecipeFilteringPerformanceBaseline() {
        let (appState, _, _) = makeTestAppState()
        appState.recipes = (0..<600).map { index in
            makeRecipe(
                title: index % 7 == 0 ? "Chicken Dish \(index)" : "Recipe \(index)",
                ingredients: [
                    Ingredient(name: "Ingredient \(index)", quantity: 1, unit: .piece, category: .other),
                    Ingredient(name: "Salt", quantity: 1, unit: .pinch, category: .spices),
                ]
            )
        }

        let viewModel = RecipeViewModel(appState: appState)
        viewModel.searchText = "Chicken"
        viewModel.applySearchTextImmediately()

        measure(metrics: [XCTClockMetric()]) {
            _ = viewModel.filteredRecipes
        }

        let average = averageRuntime {
            _ = viewModel.filteredRecipes
        }
        XCTAssertLessThan(
            average,
            Budget.recipeFilteringAverageSeconds,
            "Recipe filtering average runtime exceeded budget: \(average)s > \(Budget.recipeFilteringAverageSeconds)s"
        )
    }

    func testPantryMatchPerformanceBaseline() {
        let pantry = (0..<120).map { index in
            makePantryItem(name: "Ingredient \(index)", category: .other, quantity: 2, unit: .piece)
        }
        let recipes = (0..<250).map { index in
            makeRecipe(
                title: "Recipe \(index)",
                ingredients: (0..<8).map { offset in
                    Ingredient(
                        name: "Ingredient \((index + offset) % 120)",
                        quantity: 1,
                        unit: .piece,
                        category: .other
                    )
                }
            )
        }

        measure(metrics: [XCTClockMetric()]) {
            _ = recipes.map { $0.pantryMatch(pantry: pantry) }
        }

        let average = averageRuntime {
            _ = recipes.map { $0.pantryMatch(pantry: pantry) }
        }
        XCTAssertLessThan(
            average,
            Budget.pantryMatchAverageSeconds,
            "Pantry match average runtime exceeded budget: \(average)s > \(Budget.pantryMatchAverageSeconds)s"
        )
    }

    private func averageRuntime(samples: Int = 5, operation: () -> Void) -> TimeInterval {
        operation()

        var durations: [TimeInterval] = []
        durations.reserveCapacity(samples)
        for _ in 0..<samples {
            let start = CACurrentMediaTime()
            operation()
            durations.append(CACurrentMediaTime() - start)
        }
        return durations.reduce(0, +) / Double(durations.count)
    }
}
