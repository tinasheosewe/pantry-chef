import XCTest
@testable import PantryChef

@MainActor
final class ScenarioBaselineTests: XCTestCase {
    func testPantrySearchScenarioUsesNormalizedQuery() async {
        let (appState, _, _) = makeTestAppState()
        let viewModel = PantryViewModel(appState: appState)
        await appState.addPantryItem(makePantryItem(name: "Milk", category: .dairy))
        await appState.addPantryItem(makePantryItem(name: "Chicken", category: .protein))

        viewModel.searchText = "  Milk  "
        viewModel.applySearchTextImmediately()

        XCTAssertEqual(viewModel.filteredItems.map(\ .name), ["Milk"])
    }

    func testRecipeSearchScenarioUsesNormalizedQuery() async {
        let (appState, _, _) = makeTestAppState()
        let viewModel = RecipeViewModel(appState: appState)
        await appState.addRecipe(makeRecipe(title: "Chicken Soup"))
        await appState.addRecipe(makeRecipe(title: "Beef Stew"))

        viewModel.searchText = " chicken "
        viewModel.applySearchTextImmediately()

        XCTAssertEqual(viewModel.filteredRecipes.map(\ .title), ["Chicken Soup"])
    }

    func testMealPlanToShoppingScenarioGeneratesOnlyMissingIngredients() async {
        let (appState, _, _) = makeTestAppState()
        appState.pantryItems = [
            makePantryItem(name: "Onion", category: .produce, quantity: 1, unit: .whole),
            makePantryItem(name: "Olive Oil", category: .oils, quantity: 2, unit: .tablespoon),
        ]

        let recipe = makeRecipe(
            title: "Tomato Pasta",
            ingredients: [
                Ingredient(name: "Onion", quantity: 1, unit: .whole, category: .produce),
                Ingredient(name: "Tomatoes", quantity: 3, unit: .whole, category: .produce),
                Ingredient(name: "Olive Oil", quantity: 1, unit: .tablespoon, category: .oils),
                Ingredient(name: "Tomatoes", quantity: 3, unit: .whole, category: .produce),
            ]
        )

        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe))
        await appState.generateShoppingListFromMealPlan()

        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(appState.shoppingItems.first?.name, "Tomatoes")
    }

    func testWhatCanIMakeScenarioFiltersToMakeableRecipes() async {
        let (appState, _, _) = makeTestAppState()
        let viewModel = RecipeViewModel(appState: appState)

        appState.pantryItems = [
            makePantryItem(name: "Eggs", category: .dairy, quantity: 6, unit: .piece),
            makePantryItem(name: "Bread", category: .grains, quantity: 4, unit: .slice),
            makePantryItem(name: "Butter", category: .dairy, quantity: 100, unit: .gram),
        ]

        await appState.addRecipe(makeRecipe(
            title: "Toast",
            ingredients: [
                Ingredient(name: "Bread", quantity: 2, unit: .slice, category: .grains),
                Ingredient(name: "Butter", quantity: 10, unit: .gram, category: .dairy),
            ]
        ))
        await appState.addRecipe(makeRecipe(
            title: "Omelette",
            ingredients: [
                Ingredient(name: "Eggs", quantity: 2, unit: .piece, category: .dairy),
                Ingredient(name: "Cheese", quantity: 50, unit: .gram, category: .dairy),
            ]
        ))

        viewModel.activateWhatCanIMake()
        let titles = viewModel.filteredRecipes.map(\ .title)

        XCTAssertEqual(titles, ["Toast"])
    }
}
