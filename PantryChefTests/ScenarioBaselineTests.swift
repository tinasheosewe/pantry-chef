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

        XCTAssertEqual(viewModel.filteredUserRecipes.map(\ .title), ["Chicken Soup"])
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
        XCTAssertEqual(appState.shoppingItems.first?.name, "Tomato")
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
        let titles = viewModel.filteredUserRecipes.map(\ .title)

        XCTAssertEqual(titles, ["Toast"])
    }

    func testMealLoggingScenarioMatchesReplacementPreparedFoodByIdentity() async {
        let (appState, _, _) = makeTestAppState()
        let foodIdentityID = UUID()
        let originalDish = makePreparedDish(name: "Lentil Soup", servingsRemaining: 2, foodIdentityID: foodIdentityID)
        let replacementDish = makePreparedDish(name: "Lentil Soup", servingsRemaining: 3, foodIdentityID: foodIdentityID)

        await appState.addPreparedDish(originalDish)
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, preparedDish: originalDish, plannedServings: 2)
        await appState.addToMealPlan(entry)

        await appState.removePreparedDish(originalDish)
        await appState.addPreparedDish(replacementDish)

        await appState.logMealPlanEntriesEaten([
            MealPlanEatenLoggingSelection(entryID: entry.id, targetEatenServings: 1, preparedDishID: replacementDish.id)
        ])

        XCTAssertEqual(appState.mealPlan.first?.effectiveEatenServings, 1)
        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 2)
    }

    func testCookReviewWorkspaceScenarioBuildsParallelStageFromAdjacentMeals() {
        let entries = [
            MealPlanEntry(date: Date(), mealType: .breakfast, recipe: makeRecipe(title: "Eggs")),
            MealPlanEntry(date: Date(), mealType: .lunch, recipe: makeRecipe(title: "Soup")),
            MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe(title: "Pasta")),
        ]

        var workspace = MealPlanCookQueueReviewWorkspace(entries: entries)
        var lunch = workspace.drafts[1]
        lunch.stagePlacement = .withPrevious
        workspace.updateDraft(lunch)

        let stages = workspace.buildStages()

        XCTAssertEqual(stages.count, 2)
        XCTAssertEqual(stages[0].recipeTitleSnapshots, ["Eggs", "Soup"])
        XCTAssertEqual(stages[1].recipeTitleSnapshots, ["Pasta"])
    }

    // MARK: - Cook Completion → Prepared Dish + Cooked Indicator Scenarios

    /// Scenario: Cook a recipe via queue that came from meal plan → expect cookedAt stamped AND prepared dish created.
    func testCookQueueFromMealPlanScenarioStampsCookedAndCreatesPreparedDish() async throws {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Chicken Curry", servings: 4, mealType: .dinner)
        await appState.addRecipe(recipe)

        // Plan it
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        await appState.addToMealPlan(entry)
        XCTAssertNil(appState.mealPlan.first?.cookedAt, "Not yet cooked")

        // Add to queue with meal plan entry link (simulates RecipeDetailView → "Add Queue")
        await appState.addRecipesToCookQueue([recipe], sourceEntries: [entry])
        let stageID = try XCTUnwrap(appState.cookQueue?.stages.first?.id)

        // Complete the stage (simulates Done button with queueStageID)
        await appState.completeCookQueueStage(stageID)

        // Verify cookedAt was stamped on the meal plan entry
        let updatedEntry = try XCTUnwrap(appState.mealPlan.first(where: { $0.id == entry.id }))
        XCTAssertNotNil(updatedEntry.cookedAt, "Meal plan entry should be stamped as cooked")

        // The Done button also calls addPreparedDishForRecipe — simulate that
        await appState.addPreparedDishForRecipe(recipe)

        // Verify prepared dish was created
        XCTAssertEqual(appState.preparedDishes.count, 1)
        XCTAssertEqual(appState.preparedDishes.first?.name, "Chicken Curry")
        XCTAssertEqual(appState.preparedDishes.first?.recipeID, recipe.id)
        XCTAssertEqual(storage.addPreparedDishCallCount, 1)
    }

    /// Scenario: Cook a recipe via queue that did NOT come from meal plan → still creates prepared dish.
    func testCookQueueFromLibraryScenarioStillCreatesPreparedDish() async throws {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Beef Stew", servings: 6, mealType: .dinner)
        await appState.addRecipe(recipe)

        // Add to queue directly (no meal plan entries)
        await appState.addRecipesToCookQueue([recipe])
        let stageID = try XCTUnwrap(appState.cookQueue?.stages.first?.id)

        // Complete stage + add prepared dish (simulates Done button)
        await appState.completeCookQueueStage(stageID)
        await appState.addPreparedDishForRecipe(recipe)

        // Verify prepared dish created even without meal plan
        XCTAssertEqual(appState.preparedDishes.count, 1)
        XCTAssertEqual(appState.preparedDishes.first?.name, "Beef Stew")
        XCTAssertEqual(storage.addPreparedDishCallCount, 1)
    }

    /// Scenario: Cook a standalone recipe (no queue) → stamps cookedAt on matching meal plan entries AND creates prepared dish.
    func testStandaloneCookScenarioStampsCookedAndCreatesPreparedDish() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Pasta Carbonara", servings: 2, mealType: .dinner)
        await appState.addRecipe(recipe)

        // Plan multiple meals with same recipe
        let entry1 = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        let entry2 = MealPlanEntry(date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, mealType: .lunch, recipe: recipe)
        await appState.addToMealPlan(entry1)
        await appState.addToMealPlan(entry2)

        // Standalone cook (no queue) — simulates Done button without queueStageID
        await appState.stampCookedMealPlanEntriesByRecipe(recipe.id)
        await appState.addPreparedDishForRecipe(recipe)

        // Both entries should be stamped
        let stamped = appState.mealPlan.filter { $0.recipe?.id == recipe.id && $0.cookedAt != nil }
        XCTAssertEqual(stamped.count, 2, "All matching meal plan entries should be stamped cooked")

        // Prepared dish created
        XCTAssertEqual(appState.preparedDishes.count, 1)
        XCTAssertEqual(appState.preparedDishes.first?.name, "Pasta Carbonara")
    }

    /// Scenario: Full round-trip — plan a recipe, add to cook queue from meal plan, complete cook, verify cooked indicator text.
    func testCookedIndicatorAppearsInPlanningSubtitleAfterCook() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Grilled Salmon", servings: 2, prepTimeMinutes: 5, cookTimeMinutes: 15, mealType: .dinner)
        await appState.addRecipe(recipe)

        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        await appState.addToMealPlan(entry)

        // Before cooking — subtitle should NOT contain "Cooked"
        let beforeEntry = try XCTUnwrap(appState.mealPlan.first(where: { $0.id == entry.id }))
        XCTAssertFalse(beforeEntry.planningSubtitle?.contains("Cooked") ?? false)

        // Stamp as cooked
        await appState.stampCookedMealPlanEntriesByRecipe(recipe.id)

        // After cooking — subtitle should contain "Cooked ✓"
        let afterEntry = try XCTUnwrap(appState.mealPlan.first(where: { $0.id == entry.id }))
        XCTAssertTrue(afterEntry.planningSubtitle?.contains("Cooked ✓") ?? false, "Planning subtitle should show 'Cooked ✓' after stamping")
    }

    // ================================================================
    // MARK: - Audio Exit Path Scenarios
    // ================================================================

    /// Scenario: User reaches last step via nextStep(), then taps "Done".
    /// Audio should be fully disconnected by the time completion screen shows.
    func testCompletionViaLastStepDisconnectsAudioBeforeDoneButton() {
        let recipe = makeRecipe(
            title: "Quick Soup",
            ingredients: [Ingredient(name: "Broth", quantity: 1, unit: .liter)],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Heat broth", timerMinutes: 5),
                RecipeStep(stepNumber: 2, instruction: "Serve"),
            ]
        )
        let mock = MockRealtimeService()
        let vm = CookModeViewModel(recipe: recipe, realtimeService: mock)

        // Simulate active conversation
        vm.isConversationActive = true
        mock.isConnected = true
        mock._isAudioReady = true

        // Advance to last step
        vm.nextStep()
        // Advance past last step → completion
        vm.nextStep()

        XCTAssertTrue(vm.showCompletionScreen)
        XCTAssertFalse(vm.isConversationActive, "Voice should disconnect on completion")
        XCTAssertEqual(mock.disconnectCallCount, 1, "disconnect should be called once")
    }

    /// Scenario: AI calls finish_cooking tool → session ends cleanly.
    func testAIFinishCookingToolCleansUpAudio() {
        let recipe = makeRecipe(
            title: "AI Finish Test",
            ingredients: [Ingredient(name: "Item", quantity: 1, unit: .piece)],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Do something"),
                RecipeStep(stepNumber: 2, instruction: "Do more"),
            ]
        )
        let mock = MockRealtimeService()
        let vm = CookModeViewModel(recipe: recipe, realtimeService: mock)

        vm.isConversationActive = true
        mock.isConnected = true
        mock._isAudioReady = true

        // Simulate AI calling finish_cooking
        vm.handleRealtimeFunctionCall(name: "finish_cooking", args: [:])

        XCTAssertTrue(vm.isEndingSession, "endCookingSession should set isEndingSession")
        XCTAssertTrue(vm.showCompletionScreen)
        XCTAssertFalse(vm.isConversationActive)
        XCTAssertEqual(mock.disconnectCallCount, 1)
    }

    /// Scenario: User backgrounds app mid-cook → voice disconnects immediately,
    /// didContinueInBackground is set synchronously before any async work.
    func testBackgroundTransitionDisconnectsVoiceImmediately() {
        let recipe = makeRecipe(
            title: "Background Test",
            ingredients: [Ingredient(name: "Item", quantity: 1, unit: .piece)],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Step one", timerMinutes: 5),
                RecipeStep(stepNumber: 2, instruction: "Step two", timerMinutes: 3),
            ]
        )
        let mock = MockRealtimeService()
        let vm = CookModeViewModel(recipe: recipe, realtimeService: mock)

        vm.isConversationActive = true
        mock.isConnected = true
        mock._isAudioReady = true

        // Simulate app backgrounding
        vm.continueInBackground()

        // These should all happen synchronously (before async task)
        XCTAssertTrue(vm.didContinueInBackground, "Flag should be set synchronously")
        XCTAssertFalse(vm.isConversationActive, "Voice should disconnect synchronously")
        XCTAssertEqual(mock.silenceAICallCount, 1)
        XCTAssertEqual(mock.stopCaptureCallCount, 1)
        XCTAssertEqual(mock.disconnectCallCount, 1)
    }
}
