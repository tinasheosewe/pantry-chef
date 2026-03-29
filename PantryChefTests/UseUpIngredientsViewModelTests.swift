import XCTest
@testable import PantryChef

@MainActor
final class UseUpIngredientsViewModelTests: XCTestCase {

    private func makeSUT() -> (UseUpIngredientsViewModel, AppState, MockAIService) {
        let (appState, _, ai) = makeTestAppState()
        let vm = UseUpIngredientsViewModel(appState: appState)
        return (vm, appState, ai)
    }

    private func makeSuggestion(
        name: String = "Test Recipe",
        description: String = "A test description",
        score: Int = 4,
        reason: String = "Works well together"
    ) -> RecipeNameSuggestion {
        RecipeNameSuggestion(name: name, description: description, confidenceScore: score, confidenceReason: reason)
    }

    // MARK: - Selection Tests

    func testTogglePantryItem_addsAndRemoves() {
        let (vm, appState, _) = makeSUT()
        let item = makePantryItem(name: "Chicken")
        appState.pantryItems = [item]

        vm.togglePantryItem(item)
        XCTAssertTrue(vm.selectedPantryIDs.contains(item.id))

        vm.togglePantryItem(item)
        XCTAssertFalse(vm.selectedPantryIDs.contains(item.id))
    }

    func testSelectedIngredientNames_unionsPantryAndExtras() {
        let (vm, appState, _) = makeSUT()
        let chicken = makePantryItem(name: "Chicken")
        let rice = makePantryItem(name: "Rice")
        appState.pantryItems = [chicken, rice]

        vm.togglePantryItem(chicken)
        vm.extraIngredients = ["Lemon"]

        let names = vm.selectedIngredientNames
        XCTAssertEqual(Set(names), Set(["Chicken", "Lemon"]))
    }

    func testAddExtraIngredient_appendsAndClearsField() {
        let (vm, _, _) = makeSUT()
        vm.extraIngredientText = "Lemon"
        vm.addExtraIngredient()

        XCTAssertEqual(vm.extraIngredients, ["Lemon"])
        XCTAssertEqual(vm.extraIngredientText, "")
    }

    func testAddExtraIngredient_ignoresDuplicates() {
        let (vm, _, _) = makeSUT()
        vm.extraIngredients = ["Lemon"]
        vm.extraIngredientText = "Lemon"
        vm.addExtraIngredient()

        XCTAssertEqual(vm.extraIngredients, ["Lemon"])
    }

    func testAddExtraIngredient_ignoresEmpty() {
        let (vm, _, _) = makeSUT()
        vm.extraIngredientText = "   "
        vm.addExtraIngredient()

        XCTAssertTrue(vm.extraIngredients.isEmpty)
    }

    func testRemoveExtraIngredient() {
        let (vm, _, _) = makeSUT()
        vm.extraIngredients = ["Lemon", "Lime"]
        vm.removeExtraIngredient("Lemon")

        XCTAssertEqual(vm.extraIngredients, ["Lime"])
    }

    func testCanGetSuggestions_falseWhenEmpty() {
        let (vm, _, _) = makeSUT()
        XCTAssertFalse(vm.canGetSuggestions)
    }

    func testCanGetSuggestions_trueWithSelection() {
        let (vm, appState, _) = makeSUT()
        let item = makePantryItem(name: "Chicken")
        appState.pantryItems = [item]
        vm.togglePantryItem(item)

        XCTAssertTrue(vm.canGetSuggestions)
    }

    func testCanGetSuggestions_trueWithExtrasOnly() {
        let (vm, _, _) = makeSUT()
        vm.extraIngredients = ["Lemon"]

        XCTAssertTrue(vm.canGetSuggestions)
    }

    func testStrictIngredients_defaultsFalse() {
        let (vm, _, _) = makeSUT()
        XCTAssertFalse(vm.strictIngredients)
    }

    // MARK: - Suggestion Tests

    func testFetchSuggestions_populatesListAndTransitionsPhase() async {
        let (vm, appState, ai) = makeSUT()
        let item = makePantryItem(name: "Chicken")
        appState.pantryItems = [item]
        vm.togglePantryItem(item)

        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(
            suggestions: [
                makeSuggestion(name: "Chicken Stir Fry", score: 5),
                makeSuggestion(name: "Chicken Soup", score: 3),
            ],
            message: nil
        )

        await vm.fetchSuggestions()

        XCTAssertEqual(vm.suggestions.count, 2)
        XCTAssertTrue(vm.showingSuggestions)
        XCTAssertNil(vm.noResultsMessage)
        XCTAssertEqual(ai.suggestRecipeNamesCallCount, 1)
        XCTAssertEqual(ai.lastSuggestRecipeNamesIngredients, ["Chicken"])
    }

    func testFetchSuggestions_sortedByConfidenceDescending() async {
        let (vm, appState, ai) = makeSUT()
        let item = makePantryItem(name: "Chicken")
        appState.pantryItems = [item]
        vm.togglePantryItem(item)

        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(
            suggestions: [
                makeSuggestion(name: "Low", score: 2),
                makeSuggestion(name: "High", score: 5),
                makeSuggestion(name: "Mid", score: 3),
            ],
            message: nil
        )

        await vm.fetchSuggestions()

        XCTAssertEqual(vm.suggestions.map(\.name), ["High", "Mid", "Low"])
    }

    func testFetchSuggestions_setsNoResultsMessage() async {
        let (vm, appState, ai) = makeSUT()
        let item = makePantryItem(name: "Ice Cream")
        appState.pantryItems = [item]
        vm.togglePantryItem(item)

        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(
            suggestions: [],
            message: "These ingredients don't pair well."
        )

        await vm.fetchSuggestions()

        XCTAssertTrue(vm.suggestions.isEmpty)
        XCTAssertEqual(vm.noResultsMessage, "These ingredients don't pair well.")
    }

    func testFetchMoreSuggestions_appendsWithoutDuplicates() async {
        let (vm, appState, ai) = makeSUT()
        let item = makePantryItem(name: "Chicken")
        appState.pantryItems = [item]
        vm.togglePantryItem(item)

        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(
            suggestions: [makeSuggestion(name: "Recipe A", score: 4)],
            message: nil
        )
        await vm.fetchSuggestions()

        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(
            suggestions: [makeSuggestion(name: "Recipe B", score: 3)],
            message: nil
        )
        await vm.fetchMoreSuggestions()

        XCTAssertEqual(vm.suggestions.count, 2)
        XCTAssertEqual(vm.suggestions.map(\.name), ["Recipe A", "Recipe B"])
        XCTAssertEqual(ai.lastSuggestRecipeNamesExcludeNames, ["Recipe A"])
    }

    func testFetchSuggestions_passesStrictIngredients() async {
        let (vm, appState, ai) = makeSUT()
        let item = makePantryItem(name: "Chicken")
        appState.pantryItems = [item]
        vm.togglePantryItem(item)
        vm.strictIngredients = true

        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(suggestions: [], message: nil)
        await vm.fetchSuggestions()

        XCTAssertTrue(ai.lastSuggestRecipeNamesStrictIngredients)
    }

    // MARK: - Generation Tests

    func testSelectAndGenerate_transitionsToViewingRecipe() async {
        let (vm, appState, ai) = makeSUT()
        let item = makePantryItem(name: "Chicken")
        appState.pantryItems = [item]
        vm.togglePantryItem(item)

        let recipe = makeRecipe(title: "Chicken Stir Fry", source: .aiGenerated)
        ai.recipesToReturn = [recipe]
        ai.disambiguationDecisionsToReturn = []

        let suggestion = makeSuggestion(name: "Chicken Stir Fry", score: 4, reason: "Classic combo")
        await vm.selectAndGenerate(suggestion)

        XCTAssertTrue(vm.showingRecipe)
        XCTAssertEqual(vm.selectedSuggestion?.name, suggestion.name)
        XCTAssertEqual(ai.generateRecipeFromSuggestionCallCount, 1)
        XCTAssertEqual(ai.lastGenerateFromSuggestion?.name, "Chicken Stir Fry")
        XCTAssertEqual(ai.lastGenerateFromSuggestion?.confidenceScore, 4)
        XCTAssertEqual(ai.lastGenerateFromSuggestion?.confidenceReason, "Classic combo")
        XCTAssertEqual(ai.lastGenerateFromSuggestionIngredients, ["Chicken"])
    }

    func testSelectAndGenerate_passesStrictIngredients() async {
        let (vm, appState, ai) = makeSUT()
        let item = makePantryItem(name: "Chicken")
        appState.pantryItems = [item]
        vm.togglePantryItem(item)
        vm.strictIngredients = true

        ai.recipesToReturn = [makeRecipe(source: .aiGenerated)]
        ai.disambiguationDecisionsToReturn = []

        await vm.selectAndGenerate(makeSuggestion())

        XCTAssertTrue(ai.lastGenerateFromSuggestionStrict)
    }

    func testRetryGeneration_retriesWithSameSuggestion() async {
        let (vm, appState, ai) = makeSUT()
        let item = makePantryItem(name: "Chicken")
        appState.pantryItems = [item]
        vm.togglePantryItem(item)

        // First attempt fails (no recipe returned)
        ai.recipesToReturn = []
        ai.disambiguationDecisionsToReturn = []
        await vm.selectAndGenerate(makeSuggestion(name: "Chicken Soup"))
        XCTAssertNil(vm.generatedRecipe)
        XCTAssertEqual(ai.generateRecipeFromSuggestionCallCount, 1)

        // Retry succeeds
        ai.recipesToReturn = [makeRecipe(title: "Chicken Soup", source: .aiGenerated)]
        await vm.retryGeneration()
        XCTAssertEqual(ai.generateRecipeFromSuggestionCallCount, 2)
    }

    // MARK: - Navigation Tests

    func testShowingSuggestions_defaultsFalse() {
        let (vm, _, _) = makeSUT()
        XCTAssertFalse(vm.showingSuggestions)
    }

    func testShowingRecipe_defaultsFalse() {
        let (vm, _, _) = makeSUT()
        XCTAssertFalse(vm.showingRecipe)
    }

    // MARK: - Scenario Tests

    func testFullFlow_selectIngredients_getSuggestions_generateRecipe() async {
        let (vm, appState, ai) = makeSUT()
        let chicken = makePantryItem(name: "Chicken")
        let rice = makePantryItem(name: "Rice")
        let onion = makePantryItem(name: "Onion")
        appState.pantryItems = [chicken, rice, onion]

        // Step 1: Select ingredients
        vm.togglePantryItem(chicken)
        vm.togglePantryItem(rice)
        vm.togglePantryItem(onion)
        XCTAssertEqual(vm.selectedCount, 3)

        // Step 2: Get suggestions
        let suggestions = [
            makeSuggestion(name: "Chicken Fried Rice", score: 5, reason: "Classic combination"),
            makeSuggestion(name: "Chicken Rice Bowl", score: 4, reason: "Simple and satisfying"),
        ]
        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(suggestions: suggestions, message: nil)
        await vm.fetchSuggestions()

        XCTAssertEqual(vm.suggestions.count, 2)
        XCTAssertTrue(vm.showingSuggestions)

        // Step 3: Pick a suggestion and generate
        let recipe = makeRecipe(title: "Chicken Fried Rice", source: .aiGenerated)
        ai.recipesToReturn = [recipe]
        ai.disambiguationDecisionsToReturn = []

        await vm.selectAndGenerate(vm.suggestions[0])

        XCTAssertTrue(vm.showingRecipe)
        XCTAssertEqual(ai.generateRecipeFromSuggestionCallCount, 1)
    }

    func testFreeTextExtraAppearsInAICall() async {
        let (vm, appState, ai) = makeSUT()
        let chicken = makePantryItem(name: "Chicken")
        appState.pantryItems = [chicken]

        vm.togglePantryItem(chicken)
        vm.extraIngredientText = "Lemon"
        vm.addExtraIngredient()

        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(suggestions: [], message: nil)
        await vm.fetchSuggestions()

        XCTAssertEqual(Set(ai.lastSuggestRecipeNamesIngredients), Set(["Chicken", "Lemon"]))
    }

    func testShowMoreTwice_accumulatesSuggestions() async {
        let (vm, appState, ai) = makeSUT()
        let item = makePantryItem(name: "Chicken")
        appState.pantryItems = [item]
        vm.togglePantryItem(item)

        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(
            suggestions: [makeSuggestion(name: "Batch 1", score: 4)],
            message: nil
        )
        await vm.fetchSuggestions()

        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(
            suggestions: [makeSuggestion(name: "Batch 2", score: 3)],
            message: nil
        )
        await vm.fetchMoreSuggestions()

        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(
            suggestions: [makeSuggestion(name: "Batch 3", score: 3)],
            message: nil
        )
        await vm.fetchMoreSuggestions()

        XCTAssertEqual(vm.suggestions.count, 3)
        XCTAssertEqual(ai.lastSuggestRecipeNamesExcludeNames, ["Batch 1", "Batch 2"])
    }

    func testEmptySuggestions_showsMessageAndAllowsGoBack() async {
        let (vm, appState, ai) = makeSUT()
        let item = makePantryItem(name: "Ice Cream")
        appState.pantryItems = [item]
        vm.togglePantryItem(item)

        ai.recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(
            suggestions: [],
            message: "These ingredients don't pair well. Adding rice would help."
        )
        await vm.fetchSuggestions()

        XCTAssertEqual(vm.noResultsMessage, "These ingredients don't pair well. Adding rice would help.")
        XCTAssertTrue(vm.showingSuggestions)
    }

    // MARK: - ConfidenceTier Tests

    func testConfidenceTier_mappings() {
        XCTAssertEqual(ConfidenceTier(score: 5).label, "Perfect Match")
        XCTAssertEqual(ConfidenceTier(score: 4).label, "Great Fit")
        XCTAssertEqual(ConfidenceTier(score: 3).label, "Worth a Try")
        XCTAssertEqual(ConfidenceTier(score: 2).label, "Creative Stretch")
        // Clamped
        XCTAssertEqual(ConfidenceTier(score: 1).label, "Creative Stretch")
        XCTAssertEqual(ConfidenceTier(score: 6).label, "Perfect Match")
    }

    func testConfidenceTier_icons() {
        XCTAssertEqual(ConfidenceTier(score: 5).icon, "star.fill")
        XCTAssertEqual(ConfidenceTier(score: 4).icon, "hand.thumbsup.fill")
        XCTAssertEqual(ConfidenceTier(score: 3).icon, "lightbulb.fill")
        XCTAssertEqual(ConfidenceTier(score: 2).icon, "flask.fill")
    }
}
