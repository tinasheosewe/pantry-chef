import SwiftData
import XCTest
@testable import PantryChef

final class StorageServiceIntegrationTests: XCTestCase {
    func testColdStartBootstrapSeedsInitialData() async throws {
        let sut = StorageService(isStoredInMemoryOnly: true, shouldBootstrap: true)

        let pantry = try await sut.fetchPantryItems()
        let recipes = try await sut.fetchRecipes()

        XCTAssertEqual(pantry.count, PantryItem.samples.count)
        XCTAssertEqual(recipes.count, Recipe.samples.count)
    }

    func testColdStartWithoutBootstrapStartsEmpty() async throws {
        let sut = StorageService(isStoredInMemoryOnly: true, shouldBootstrap: false)

        let pantry = try await sut.fetchPantryItems()
        let recipes = try await sut.fetchRecipes()
        let mealPlan = try await sut.fetchMealPlan()
        let shopping = try await sut.fetchShoppingItems()

        XCTAssertTrue(pantry.isEmpty)
        XCTAssertTrue(recipes.isEmpty)
        XCTAssertTrue(mealPlan.isEmpty)
        XCTAssertTrue(shopping.isEmpty)
    }

    func testCrudSmokeAcrossPantryRecipeMealPlanAndShopping() async throws {
        let sut = StorageService(isStoredInMemoryOnly: true, shouldBootstrap: false)

        let pantryItem = PantryItem(
            name: "Integration Tomatoes",
            category: .produce,
            quantity: 3,
            unit: .whole
        )
        _ = try await sut.addPantryItem(pantryItem)
        var pantry = try await sut.fetchPantryItems()
        XCTAssertEqual(pantry.count, 1)

        var updatedPantryItem = pantryItem
        updatedPantryItem.quantity = 5
        _ = try await sut.updatePantryItem(updatedPantryItem)
        pantry = try await sut.fetchPantryItems()
        XCTAssertEqual(pantry.first?.quantity, 5)

        let taskID = UUID()
        let recipe = Recipe(
            title: "Integration Pasta",
            ingredients: [Ingredient(name: "Pasta", quantity: 200, unit: .gram, category: .grains)],
            steps: [
                RecipeStep(
                    stepNumber: 1,
                    instruction: "Boil pasta",
                    timerMinutes: 8,
                    tasks: [
                        StepTask(
                            id: taskID,
                            action: .boil,
                            ingredient: "pasta",
                            quantity: 200,
                            unit: "g",
                            durationSeconds: 480,
                            type: .passive,
                            dependsOn: []
                        )
                    ]
                ),
            ],
            source: .user
        )

        let addedRecipe = try await sut.addRecipe(recipe)
        var recipes = try await sut.fetchRecipes()
        XCTAssertEqual(recipes.count, 1)
        XCTAssertEqual(recipes[0].steps[0].tasks.count, 1)
        XCTAssertEqual(recipes[0].steps[0].tasks[0].id, taskID)

        var updatedRecipe = addedRecipe
        updatedRecipe.isFavorite = true
        _ = try await sut.updateRecipe(updatedRecipe)
        recipes = try await sut.fetchRecipes()
        XCTAssertEqual(recipes.first?.isFavorite, true)

        let mealPlan = MealPlanEntry(
            date: Date(),
            mealType: .dinner,
            recipe: updatedRecipe,
            notes: "integration test"
        )

        _ = try await sut.addMealPlanEntry(mealPlan)
        var mealPlans = try await sut.fetchMealPlan()
        XCTAssertEqual(mealPlans.count, 1)
        XCTAssertEqual(mealPlans.first?.recipe?.id, updatedRecipe.id)

        var updatedMealPlan = mealPlan
        updatedMealPlan.customMealName = "Custom dinner"
        _ = try await sut.updateMealPlanEntry(updatedMealPlan)
        mealPlans = try await sut.fetchMealPlan()
        XCTAssertEqual(mealPlans.first?.customMealName, "Custom dinner")

        let shoppingItems = [
            ShoppingItem(name: "Garlic", quantity: 2, unit: .clove, category: .produce),
            ShoppingItem(name: "Olive Oil", quantity: 1, unit: .liter, category: .oils),
        ]

        try await sut.saveShoppingItems(shoppingItems)
        var savedShopping = try await sut.fetchShoppingItems()
        XCTAssertEqual(savedShopping.count, 2)

        savedShopping[0].isChecked = true
        try await sut.saveShoppingItems(savedShopping)
        let checked = try await sut.fetchShoppingItems().first(where: { $0.id == savedShopping[0].id })
        XCTAssertEqual(checked?.isChecked, true)

        try await sut.deleteMealPlanEntry(updatedMealPlan)
        let mealPlanAfterDelete = try await sut.fetchMealPlan()
        XCTAssertTrue(mealPlanAfterDelete.isEmpty)

        try await sut.deleteRecipe(updatedRecipe)
        let recipesAfterDelete = try await sut.fetchRecipes()
        XCTAssertTrue(recipesAfterDelete.isEmpty)

        try await sut.deletePantryItem(updatedPantryItem)
        let pantryAfterDelete = try await sut.fetchPantryItems()
        XCTAssertTrue(pantryAfterDelete.isEmpty)
    }

    func testRecordVersioningFieldsSetToCurrentVersion() throws {
        let pantry = PantryItem(name: "Milk", category: .dairy)
        let pantryRecord = PantryItemRecord(from: pantry)
        XCTAssertEqual(pantryRecord.schemaVersion, StorageSchema.currentVersion)

        let recipe = Recipe(title: "Versioned", steps: [RecipeStep(stepNumber: 1, instruction: "Step")])
        let recipeRecord = try RecipeRecord(from: recipe)
        XCTAssertEqual(recipeRecord.schemaVersion, StorageSchema.currentVersion)

        let mealPlan = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        let mealPlanRecord = MealPlanRecord(from: mealPlan)
        XCTAssertEqual(mealPlanRecord.schemaVersion, StorageSchema.currentVersion)

        let shopping = ShoppingItem(name: "Salt", quantity: 1, unit: .pinch, category: .spices)
        let shoppingRecord = ShoppingItemRecord(from: shopping)
        XCTAssertEqual(shoppingRecord.schemaVersion, StorageSchema.currentVersion)
    }
}
