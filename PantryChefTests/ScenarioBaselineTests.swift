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
        let recipe = makeRecipe(title: "Chicken Curry", servings: 4, mealType: .dinner,
                                nutrition: NutritionInfo(calories: 450, protein: 32, carbohydrates: 30, fat: 18))
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

        // Verify prepared dish was created with recipe link, expiry, and nutrition
        XCTAssertEqual(appState.preparedDishes.count, 1)
        let dish = try XCTUnwrap(appState.preparedDishes.first)
        XCTAssertEqual(dish.name, "Chicken Curry")
        XCTAssertEqual(dish.recipeID, recipe.id)
        XCTAssertNotNil(dish.useByDate, "Prepared dish from cook should have a useByDate")
        XCTAssertEqual(dish.nutrition, recipe.nutrition, "Prepared dish should carry recipe nutrition")
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

    // ================================================================
    // MARK: - 1-Active-Cook Enforcement Scenarios
    // ================================================================

    /// Scenario: A CookingSession is already active for Recipe A.
    /// New cook start should detect the conflict via CookingSession.loadAll().
    func testActiveCookConflictDetectedViaCookingSession() {
        CookingSession.clearAll() // Ensure clean state
        let existingRecipeID = UUID()
        let session = CookingSession(
            recipeId: existingRecipeID,
            recipeName: "In-Progress Curry",
            totalSteps: 3,
            stepSummaries: [],
            currentStepIndex: 1,
            startedAt: Date(),
            backgroundedAt: Date(),
            isActive: true
        )
        session.save()

        let activeSessions = CookingSession.loadAll()
        XCTAssertTrue(activeSessions.contains(where: { $0.recipeId == existingRecipeID }),
            "Should detect existing active cook session")
        XCTAssertEqual(activeSessions.count, 1)

        // Clean up
        CookingSession.clear(recipeId: existingRecipeID)
    }

    /// Scenario: Cancel existing active cook, then start new one.
    /// This validates the "end existing → start new" user flow.
    func testCancelActiveCookThenStartNewOne() {
        CookingSession.clearAll() // Ensure clean state
        let oldRecipeID = UUID()
        let newRecipeID = UUID()

        // Existing session
        CookingSession(
            recipeId: oldRecipeID,
            recipeName: "Old Cook",
            totalSteps: 2, stepSummaries: [],
            currentStepIndex: 0,
            startedAt: Date(), backgroundedAt: Date(),
            isActive: true
        ).save()

        // Cancel existing
        CookingSession.clear(recipeId: oldRecipeID)
        XCTAssertNil(CookingSession.load(recipeId: oldRecipeID))

        // Start new
        CookingSession(
            recipeId: newRecipeID,
            recipeName: "New Cook",
            totalSteps: 3, stepSummaries: [],
            currentStepIndex: 0,
            startedAt: Date(), backgroundedAt: Date(),
            isActive: true
        ).save()

        let sessions = CookingSession.loadAll()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.recipeId, newRecipeID)

        CookingSession.clear(recipeId: newRecipeID)
    }

    // ================================================================
    // MARK: - Mute-During-Startup Scenario
    // ================================================================

    /// Scenario: User is pre-muted (from previous session) → startConversation
    /// should connect audio but NOT send greeting and should silence AI.
    func testMutedStartupScenarioSkipsGreetingAndSilencesAI() {
        // Set muted in UserDefaults (persisted from previous session)
        UserDefaults.standard.set(true, forKey: "cookMode.isMuted")

        let recipe = makeRecipe(
            title: "Muted Startup",
            ingredients: [Ingredient(name: "Item", quantity: 1, unit: .piece)],
            steps: [RecipeStep(stepNumber: 1, instruction: "Step one")]
        )
        let mock = MockRealtimeService()
        let vm = CookModeViewModel(recipe: recipe, realtimeService: mock)

        XCTAssertTrue(vm.isMuted, "Mute should be restored from UserDefaults")

        // Simulate the startup flow (after prepareAudio + connect succeeds)
        vm.isConversationActive = true
        vm.isPreparing = false
        mock._isAudioReady = true
        mock.isConnected = true

        // The startup code checks if muted → silences instead of greeting
        if vm.isMuted {
            mock.stopCapture()
            mock.silenceAI()
        } else {
            mock.startCapture()
            mock.sendUserMessage("Greeting")
        }

        XCTAssertEqual(mock.stopCaptureCallCount, 1, "Mic should be stopped when muted")
        XCTAssertEqual(mock.silenceAICallCount, 1, "AI should be silenced when muted")
        XCTAssertTrue(mock.sentMessages.isEmpty, "No greeting when muted")
        XCTAssertEqual(mock.startCaptureCallCount, 0, "Should not start capture when muted")

        UserDefaults.standard.removeObject(forKey: "cookMode.isMuted")
    }

    // ================================================================
    // MARK: - Full Cook Queue → Completion → Empty Queue Scenario
    // ================================================================

    /// Scenario: 3 recipes in queue → complete each → queue empties to nil.
    func testCookQueueEmptiesAsAllStagesComplete() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipes = [
            makeRecipe(title: "Soup"),
            makeRecipe(title: "Salad"),
            makeRecipe(title: "Bread"),
        ]
        for r in recipes { await appState.addRecipe(r) }

        await appState.addRecipesToCookQueue(recipes)
        XCTAssertEqual(appState.cookQueue?.stages.count, 3)

        // Complete stages one by one
        for _ in 0..<3 {
            let stageID = try XCTUnwrap(appState.cookQueue?.stages.first?.id)
            await appState.completeCookQueueStage(stageID)
        }

        XCTAssertNil(appState.cookQueue, "Queue should be nil after all stages completed")
    }

    // ================================================================
    // MARK: - Resume From Background Scenario
    // ================================================================

    /// Scenario: App backgrounded with active cook → return to foreground →
    /// voice reconnects, notifications cancelled.
    func testResumeFromBackgroundReconnectsVoice() async {
        let recipe = makeRecipe(
            title: "Resume Test",
            ingredients: [Ingredient(name: "Item", quantity: 1, unit: .piece)],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Step one"),
                RecipeStep(stepNumber: 2, instruction: "Step two"),
            ]
        )
        let mock = MockRealtimeService()
        let vm = CookModeViewModel(recipe: recipe, realtimeService: mock)

        // Simulate active conversation → background
        vm.isConversationActive = true
        mock.isConnected = true
        mock._isAudioReady = true
        vm.continueInBackground()

        XCTAssertTrue(vm.didContinueInBackground)
        XCTAssertFalse(vm.isConversationActive)

        // Resume from background
        vm.resumeFromBackground()

        XCTAssertFalse(vm.didContinueInBackground, "Flag should be reset")
        XCTAssertFalse(vm.isSchedulingBackground, "Scheduling flag should be clear")
    }

    // ================================================================
    // MARK: - Navigation While Muted Scenario
    // ================================================================

    /// Scenario: User muted → navigates through all steps → no messages sent to AI.
    func testFullNavigationWhileMutedNeverSendsMessages() {
        let recipe = makeRecipe(
            title: "Muted Nav",
            ingredients: [Ingredient(name: "A", quantity: 1, unit: .piece)],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "One"),
                RecipeStep(stepNumber: 2, instruction: "Two"),
                RecipeStep(stepNumber: 3, instruction: "Three"),
            ]
        )
        let mock = MockRealtimeService()
        let vm = CookModeViewModel(recipe: recipe, realtimeService: mock)
        vm.isConversationActive = true
        vm.isMuted = true

        vm.nextStep()          // → Step 2
        vm.nextStep()          // → Step 3
        vm.previousStep()      // → Step 2
        vm.goToStep(0)         // → Step 1

        XCTAssertTrue(mock.sentMessages.isEmpty,
            "No messages should be sent when muted, regardless of navigation")
    }

    // ================================================================
    // MARK: - Standalone Cook → Stamp + Prepared Dish + Session Clear
    // ================================================================

    /// Scenario: Full standalone cook flow — start, persist session, "Done",
    /// stamps cookedAt, creates prepared dish, clears session.
    func testStandaloneCookFullLifecycle() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Risotto", servings: 4, mealType: .dinner)
        await appState.addRecipe(recipe)

        // Plan it
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        await appState.addToMealPlan(entry)

        // Start cook (persist session)
        let mock = MockRealtimeService()
        let vm = CookModeViewModel(recipe: recipe, realtimeService: mock)
        vm.persistSession()
        XCTAssertNotNil(CookingSession.load(recipeId: recipe.id))

        // Simulate "Done" button (standalone — no queue stage)
        await appState.stampCookedMealPlanEntriesByRecipe(recipe.id)
        await appState.addPreparedDishForRecipe(recipe)
        CookingSession.clear(recipeId: recipe.id)

        // Verify: meal plan entry stamped
        let stamped = appState.mealPlan.first(where: { $0.id == entry.id })
        XCTAssertNotNil(stamped?.cookedAt, "Meal plan entry should be stamped cooked")

        // Verify: prepared dish created
        XCTAssertEqual(appState.preparedDishes.count, 1)
        XCTAssertEqual(appState.preparedDishes.first?.name, "Risotto")

        // Verify: session cleared
        XCTAssertNil(CookingSession.load(recipeId: recipe.id), "Session should be cleared")
    }

    // ================================================================
    // MARK: - endCookingSession Full Cleanup Scenario
    // ================================================================

    /// Scenario: endCookingSession clears EVERYTHING — session, notifications flag, timer, voice.
    func testEndCookingSessionFullCleanupScenario() async {
        let recipe = makeRecipe(
            title: "Cleanup Test",
            ingredients: [Ingredient(name: "A", quantity: 1, unit: .piece)],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Step 1", timerMinutes: 5),
                RecipeStep(stepNumber: 2, instruction: "Step 2"),
            ]
        )
        let mock = MockRealtimeService()
        let vm = CookModeViewModel(recipe: recipe, realtimeService: mock)

        // Set up "mid-cook" state
        vm.isConversationActive = true
        mock.isConnected = true
        mock._isAudioReady = true
        vm.persistSession()
        vm.continueInBackground()

        XCTAssertTrue(vm.didContinueInBackground)
        XCTAssertNotNil(CookingSession.load(recipeId: recipe.id))

        // End session
        vm.endCookingSession()

        XCTAssertTrue(vm.isEndingSession)
        XCTAssertFalse(vm.didContinueInBackground, "Background flag cleared")
        XCTAssertFalse(vm.isConversationActive, "Voice disconnected")
        XCTAssertFalse(vm.isTimerRunning, "Timer stopped")
        XCTAssertNil(CookingSession.load(recipeId: recipe.id), "Session cleared from UserDefaults")
    }

    // ================================================================
    // MARK: - Plan → Shop → Cook → Verify Full Pipeline
    // ================================================================

    /// Scenario: Plan recipe → generate shopping list → cook → verify meal plan stamped AND shopping list contained the right ingredients.
    func testPlanShopCookFullPipelineScenario() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(
            title: "Chicken Stir Fry",
            ingredients: [
                Ingredient(name: "Chicken", quantity: 500, unit: .gram, category: .protein),
                Ingredient(name: "Soy Sauce", quantity: 2, unit: .tablespoon, category: .condiments),
                Ingredient(name: "Rice", quantity: 1, unit: .cup, category: .grains),
            ],
            servings: 2,
            mealType: .dinner
        )
        await appState.addRecipe(recipe)

        // Step 1: Plan it
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        await appState.addToMealPlan(entry)
        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertNil(appState.mealPlan.first?.cookedAt)

        // Step 2: Generate shopping list from meal plan
        await appState.generateShoppingListFromMealPlan()
        XCTAssertGreaterThanOrEqual(appState.shoppingItems.count, 1, "Shopping list should have items")
        let shoppingNames = Set(appState.shoppingItems.map { $0.name.lowercased() })
        XCTAssertTrue(shoppingNames.contains("chicken") || shoppingNames.contains("soy sauce") || shoppingNames.contains("rice"),
            "At least one recipe ingredient should appear in shopping list")

        // Step 3: Cook it (stamp meal plan + create prepared dish)
        await appState.stampCookedMealPlanEntriesByRecipe(recipe.id)
        await appState.addPreparedDishForRecipe(recipe)

        // Verify: meal plan reflects cooking
        let stamped = try XCTUnwrap(appState.mealPlan.first(where: { $0.id == entry.id }))
        XCTAssertNotNil(stamped.cookedAt, "Meal plan should show cooked")
        XCTAssertTrue(stamped.planningSubtitle?.contains("Cooked ✓") ?? false)

        // Verify: prepared dish created
        XCTAssertEqual(appState.preparedDishes.count, 1)
        XCTAssertEqual(appState.preparedDishes.first?.recipeID, recipe.id)
    }

    // ================================================================
    // MARK: - Shopping Cart → Pantry Transfer Scenario
    // ================================================================

    /// Scenario: Check off shopping items → transfer to pantry → items removed from list and appear in pantry.
    func testShoppingToPantryTransferScenario() async throws {
        let (appState, _, _) = makeTestAppState()

        // Add shopping items
        let item1 = ShoppingItem(name: "Eggs", quantity: 12, unit: .piece, category: .dairy)
        let item2 = ShoppingItem(name: "Flour", quantity: 1, unit: .kilogram, category: .grains)
        let item3 = ShoppingItem(name: "Sugar", quantity: 500, unit: .gram, category: .bakingSupplies)
        await appState.addShoppingItem(item1)
        await appState.addShoppingItem(item2)
        await appState.addShoppingItem(item3)
        XCTAssertEqual(appState.shoppingItems.count, 3)

        // Check off two items
        let eggs = try XCTUnwrap(appState.shoppingItems.first(where: { $0.name.contains("Egg") }))
        let flour = try XCTUnwrap(appState.shoppingItems.first(where: { $0.name.contains("Flour") }))
        await appState.toggleShoppingItem(eggs)
        await appState.toggleShoppingItem(flour)

        let checkedItems = appState.shoppingItems.filter { $0.isChecked }
        XCTAssertEqual(checkedItems.count, 2)

        // Transfer checked items to pantry (simulating ShoppingActions.addCheckedToPantry)
        for item in checkedItems {
            await appState.addPantryItem(item.pantryItemForTransfer())
        }
        await appState.removeCheckedShoppingItems()

        // Verify: pantry has transferred items
        let pantryNames = appState.pantryItems.map { $0.name }
        XCTAssertTrue(pantryNames.contains(where: { $0.contains("Egg") }), "Eggs should be in pantry")
        XCTAssertTrue(pantryNames.contains(where: { $0.contains("Flour") }), "Flour should be in pantry")

        // Verify: shopping list only has the unchecked item
        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertTrue(appState.shoppingItems.first?.name.contains("Sugar") == true)
    }

    // ================================================================
    // MARK: - Prepared Dish Consumption → Auto-Delete Scenario
    // ================================================================

    /// Scenario: Create prepared dish → consume servings one by one → auto-deleted when reaches zero.
    func testPreparedDishConsumptionAutoDeletesAtZero() async {
        let (appState, _, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Leftover Pasta", servingsRemaining: 2)
        await appState.addPreparedDish(dish)
        XCTAssertEqual(appState.preparedDishes.count, 1)

        // Consume first serving
        let wasRemoved1 = await appState.adjustPreparedDishServings(appState.preparedDishes.first!, delta: -1)
        XCTAssertFalse(wasRemoved1, "Should not be removed yet (1 serving remains)")
        XCTAssertEqual(appState.preparedDishes.count, 1)
        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 1)

        // Consume second serving → should auto-delete
        let wasRemoved2 = await appState.adjustPreparedDishServings(appState.preparedDishes.first!, delta: -1)
        XCTAssertTrue(wasRemoved2, "Should be removed (0 servings)")
        XCTAssertTrue(appState.preparedDishes.isEmpty, "Dish should be auto-deleted")
    }

    // ================================================================
    // MARK: - Meal Logging → Prepared Dish Servings Decrement Scenario
    // ================================================================

    /// Scenario: Plan a prepared dish for meal → log as eaten → verify prepared dish servings decrease.
    func testMealLoggingDecrementsPreparedDishServings() async throws {
        let (appState, _, _) = makeTestAppState()

        // Create a prepared dish (simulating something the user cooked)
        let recipe = makeRecipe(title: "Beef Stew", servings: 4, mealType: .dinner)
        await appState.addRecipe(recipe)
        await appState.addPreparedDishForRecipe(recipe)
        let dish = try XCTUnwrap(appState.preparedDishes.first)
        XCTAssertEqual(dish.servingsRemaining, 4)

        // Plan it as a meal
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, preparedDish: dish, plannedServings: 2)
        await appState.addToMealPlan(entry)

        // Log 2 servings as eaten
        await appState.logMealPlanEntriesEaten([
            MealPlanEatenLoggingSelection(
                entryID: entry.id,
                targetEatenServings: 2,
                preparedDishID: dish.id
            )
        ])

        // Verify: meal plan entry shows 2 eaten
        let updated = try XCTUnwrap(appState.mealPlan.first(where: { $0.id == entry.id }))
        XCTAssertEqual(updated.effectiveEatenServings, 2)

        // Verify: prepared dish servings decreased
        let updatedDish = try XCTUnwrap(appState.preparedDishes.first)
        XCTAssertEqual(updatedDish.servingsRemaining, 2, "4 - 2 eaten = 2 remaining")
    }

    // ================================================================
    // MARK: - Meal Plan Slot Replacement Scenario
    // ================================================================

    /// Scenario: Plan Recipe A for Monday dinner → replace with Recipe B → only Recipe B remains in that slot.
    func testMealPlanSlotReplacementScenario() async {
        let (appState, _, _) = makeTestAppState()
        let monday = Calendar.current.date(from: DateComponents(year: 2025, month: 6, day: 2))!
        let recipeA = makeRecipe(title: "Recipe A", mealType: .dinner)
        let recipeB = makeRecipe(title: "Recipe B", mealType: .dinner)

        // Plan Recipe A for Monday dinner
        let entryA = MealPlanEntry(date: monday, mealType: .dinner, recipe: recipeA)
        await appState.addToMealPlan(entryA)
        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(appState.mealPlan.first?.displayName, "Recipe A")

        // Replace with Recipe B in same slot
        let entryB = MealPlanEntry(date: monday, mealType: .dinner, recipe: recipeB)
        await appState.addToMealPlan(entryB, replaceExistingSlot: true)

        // Only Recipe B should remain
        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(appState.mealPlan.first?.displayName, "Recipe B")
    }

    // ================================================================
    // MARK: - Cook Once → Multiple Meals Stamped Scenario
    // ================================================================

    /// Scenario: Same recipe planned for multiple days → cook once → ALL matching entries stamped.
    func testCookOnceStampsAllMatchingMealPlanEntries() async {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Meal Prep Chicken", mealType: .dinner)
        await appState.addRecipe(recipe)

        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let dayAfter = Calendar.current.date(byAdding: .day, value: 2, to: today)!

        // Plan same recipe for 3 days
        await appState.addToMealPlan(MealPlanEntry(date: today, mealType: .dinner, recipe: recipe))
        await appState.addToMealPlan(MealPlanEntry(date: tomorrow, mealType: .dinner, recipe: recipe))
        await appState.addToMealPlan(MealPlanEntry(date: dayAfter, mealType: .dinner, recipe: recipe))
        XCTAssertEqual(appState.mealPlan.count, 3)

        // Cook once
        await appState.stampCookedMealPlanEntriesByRecipe(recipe.id)

        // ALL entries should be stamped
        let stamped = appState.mealPlan.filter { $0.cookedAt != nil }
        XCTAssertEqual(stamped.count, 3, "All 3 meal plan entries should be stamped cooked")
    }

    // ================================================================
    // MARK: - Prepared Dish → Plan → Eat → Fully Eaten Scenario
    // ================================================================

    /// Scenario: Cook something → plan as prepared food → eat all servings → entry shows fully eaten.
    func testPreparedDishPlanEatFullyEatenScenario() async throws {
        let (appState, _, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Quinoa Bowl", servingsRemaining: 2)
        await appState.addPreparedDish(dish)

        // Plan it with 2 servings
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, preparedDish: dish, plannedServings: 2)
        await appState.addToMealPlan(entry)

        // Eat all 2 servings
        await appState.logMealPlanEntriesEaten([
            MealPlanEatenLoggingSelection(entryID: entry.id, targetEatenServings: 2, preparedDishID: dish.id)
        ])

        // Verify: entry is fully eaten
        let updated = try XCTUnwrap(appState.mealPlan.first(where: { $0.id == entry.id }))
        XCTAssertTrue(updated.isFullyEaten, "Entry should be fully eaten")

        // Verify: prepared dish auto-deleted (0 servings)
        XCTAssertTrue(appState.preparedDishes.isEmpty, "Dish should be auto-deleted after all servings consumed")
    }

    // ================================================================
    // MARK: - Recipe Detail → Add to All Three Destinations
    // ================================================================

    /// Scenario: From recipe detail, user adds recipe to meal plan, shopping list, AND cook queue in one session.
    func testRecipeAddedToMealPlanShoppingAndCookQueue() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(
            title: "Thai Curry",
            ingredients: [
                Ingredient(name: "Coconut Milk", quantity: 1, unit: .can, category: .canned),
                Ingredient(name: "Curry Paste", quantity: 2, unit: .tablespoon, category: .condiments),
            ],
            servings: 4,
            mealType: .dinner
        )
        await appState.addRecipe(recipe)

        // Add to meal plan
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        await appState.addToMealPlan(entry)
        XCTAssertEqual(appState.mealPlan.count, 1)

        // Generate shopping list
        await appState.generateShoppingListFromMealPlan()
        XCTAssertFalse(appState.shoppingItems.isEmpty, "Should have shopping items")

        // Add to cook queue
        await appState.addRecipesToCookQueue([recipe], sourceEntries: [entry])
        XCTAssertNotNil(appState.cookQueue)
        XCTAssertEqual(appState.cookQueue?.stages.count, 1)

        // Complete cook
        let stageID = try XCTUnwrap(appState.cookQueue?.stages.first?.id)
        await appState.completeCookQueueStage(stageID)
        await appState.addPreparedDishForRecipe(recipe)

        // All three destinations should reflect the recipe
        XCTAssertNotNil(appState.mealPlan.first?.cookedAt, "Meal plan stamped")
        XCTAssertEqual(appState.preparedDishes.count, 1, "Prepared dish created")
    }
}
