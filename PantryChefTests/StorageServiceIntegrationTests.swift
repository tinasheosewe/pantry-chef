import SwiftData
import XCTest
@testable import PantryChef

final class StorageServiceIntegrationTests: XCTestCase {
    func testColdStartBootstrapSeedsInitialData() async throws {
        let sut = StorageService(isStoredInMemoryOnly: true, shouldBootstrap: true, resetPersistentStore: false)

        let pantry = try await sut.fetchPantryItems()
        let recipes = try await sut.fetchRecipes()

        XCTAssertEqual(pantry.count, PantryItem.samples.count)
        XCTAssertEqual(recipes.count, BundledSeedRecipeLoader.loadRecipes().count)
        XCTAssertTrue(recipes.contains { $0.title == "Creamy Spinach and Feta Pasta" })
        XCTAssertTrue(
            recipes
                .flatMap(\.ingredients)
                .filter { !$0.rawName.localizedCaseInsensitiveContains("water") }
                .allSatisfy(\.isResolved)
        )
    }

    func testColdStartWithoutBootstrapStartsEmpty() async throws {
        let sut = StorageService(isStoredInMemoryOnly: true, shouldBootstrap: false, resetPersistentStore: false)

        let pantry = try await sut.fetchPantryItems()
        let recipes = try await sut.fetchRecipes()
        let mealPlan = try await sut.fetchMealPlan()
        let shopping = try await sut.fetchShoppingItems()
        let preparedDishHistory = try await sut.fetchPreparedDishHistory()
        let cookQueue = try await sut.fetchCookQueue()

        XCTAssertTrue(pantry.isEmpty)
        XCTAssertTrue(recipes.isEmpty)
        XCTAssertTrue(mealPlan.isEmpty)
        XCTAssertTrue(shopping.isEmpty)
        XCTAssertTrue(preparedDishHistory.isEmpty)
        XCTAssertNil(cookQueue)
    }

    func testCrudSmokeAcrossPantryRecipeMealPlanAndShopping() async throws {
        let sut = StorageService(isStoredInMemoryOnly: true, shouldBootstrap: false, resetPersistentStore: false)

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
            plannedServings: 2,
            eatenServings: 1,
            notes: "integration test"
        )

        _ = try await sut.addMealPlanEntry(mealPlan)
        var mealPlans = try await sut.fetchMealPlan()
        XCTAssertEqual(mealPlans.count, 1)
        XCTAssertEqual(mealPlans.first?.recipe?.id, updatedRecipe.id)
        XCTAssertEqual(mealPlans.first?.plannedServings, 2)
        XCTAssertEqual(mealPlans.first?.eatenServings, 1)

        var updatedMealPlan = mealPlan
        updatedMealPlan.customMealName = "Custom dinner"
        updatedMealPlan.eatenServings = 2
        _ = try await sut.updateMealPlanEntry(updatedMealPlan)
        mealPlans = try await sut.fetchMealPlan()
        XCTAssertEqual(mealPlans.first?.customMealName, "Custom dinner")
        XCTAssertEqual(mealPlans.first?.eatenServings, 2)

        let shoppingItems = [
            ShoppingItem(name: "Garlic", quantity: 2, unit: .clove, category: .produce, pantryQuantity: 1, pantryUnit: .package),
            ShoppingItem(name: "Olive Oil", quantity: 1, unit: .liter, category: .oils),
        ]
        let historyItems = [
            PreparedDishHistoryItem(dish: makePreparedDish(name: "Integration Leftovers", servingsRemaining: 3))
        ]
        let cookQueue = CookQueue(stages: [CookQueueStage(recipes: [updatedRecipe])])

        try await sut.saveShoppingItems(shoppingItems)
        try await sut.savePreparedDishHistory(historyItems)
        try await sut.saveCookQueue(cookQueue)
        var savedShopping = try await sut.fetchShoppingItems()
        XCTAssertEqual(savedShopping.count, 2)
        XCTAssertEqual(savedShopping.first(where: { $0.catalogItemID == "garlic" })?.pantryQuantity, 1)
        XCTAssertEqual(savedShopping.first(where: { $0.catalogItemID == "garlic" })?.pantryUnit, .package)
        let savedHistory = try await sut.fetchPreparedDishHistory()
        let savedCookQueue = try await sut.fetchCookQueue()
        XCTAssertEqual(savedHistory.first?.name, "Integration Leftovers")
        XCTAssertEqual(savedCookQueue?.stages.first?.recipeTitleSnapshots.first, updatedRecipe.title)

        savedShopping[0].isChecked = true
        savedShopping[0] = savedShopping[0].updatingPantryPlan(quantity: nil, unit: nil, quantityMode: .presenceOnly)
        try await sut.saveShoppingItems(savedShopping)
        let checked = try await sut.fetchShoppingItems().first(where: { $0.id == savedShopping[0].id })
        XCTAssertEqual(checked?.isChecked, true)
        XCTAssertEqual(checked?.pantryQuantityMode, .presenceOnly)

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

        let historyRecord = try PreparedDishHistoryRecord(from: PreparedDishHistoryItem(dish: makePreparedDish(name: "History")))
        XCTAssertEqual(historyRecord.schemaVersion, StorageSchema.currentVersion)

        let cookQueueRecord = try CookQueueRecord(from: CookQueue(stages: [CookQueueStage(recipes: [recipe])]))
        XCTAssertEqual(cookQueueRecord.schemaVersion, StorageSchema.currentVersion)
    }

    func testPantryRecordRoundTripsStructuredFacetRecords() throws {
        let item = PantryItem(
            name: "All-purpose Flour",
            category: .bakingSupplies,
            quantity: 2,
            unit: .kilogram,
            expiryDate: Date().addingTimeInterval(86_400),
            notes: "Keep sealed",
            catalogItemID: "flour",
            facets: [PantryFacetSelection(key: .variant, value: "all-purpose")],
            storage: .pantry,
            freshnessSource: .userProvided
        )

        let record = PantryItemRecord(from: item)
        let roundTripped = record.toDomain()

        XCTAssertEqual(record.facetRecords.count, 1)
        XCTAssertEqual(record.facetRecords.first?.keyRawValue, PantryFacetKey.variant.rawValue)
        XCTAssertEqual(record.facetRecords.first?.value, "all-purpose")
        XCTAssertEqual(roundTripped.catalogItemID, "flour")
        XCTAssertEqual(roundTripped.facets, [PantryFacetSelection(key: .variant, value: "all-purpose")])
        XCTAssertEqual(roundTripped.storage, .pantry)
        XCTAssertEqual(roundTripped.freshnessSource, .userProvided)
        XCTAssertEqual(roundTripped.quantityMode, .exact)
    }
}
