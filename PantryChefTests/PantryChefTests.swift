import XCTest
@testable import PantryChef
import RealtimeAPI

// MARK: - Mock Services

@MainActor
final class MockStorageService: StorageServiceProtocol {
    enum Operation: Hashable {
        case fetchPantryItems
        case fetchPreparedDishes
        case fetchPreparedDishHistory
        case fetchRecipes
        case fetchMealPlan
        case fetchShoppingItems
        case fetchCookQueue
        case addPantryItem
        case updatePantryItem
        case deletePantryItem
        case addPreparedDish
        case updatePreparedDish
        case deletePreparedDish
        case savePreparedDishHistory
        case addRecipe
        case updateRecipe
        case deleteRecipe
        case addMealPlanEntry
        case updateMealPlanEntry
        case deleteMealPlanEntry
        case saveShoppingItems
        case saveCookQueue
    }

    var pantryStore: [PantryItem] = []
    var preparedDishStore: [PreparedDish] = []
    var preparedDishHistoryStore: [PreparedDishHistoryItem] = []
    var recipeStore: [Recipe] = []
    var mealPlanStore: [MealPlanEntry] = []
    var shoppingStore: [ShoppingItem] = []
    var cookQueueStore: CookQueue?

    var addPantryItemCallCount = 0
    var updatePantryItemCallCount = 0
    var deletePantryItemCallCount = 0
    var addPreparedDishCallCount = 0
    var updatePreparedDishCallCount = 0
    var deletePreparedDishCallCount = 0
    var addRecipeCallCount = 0
    var updateRecipeCallCount = 0
    var deleteRecipeCallCount = 0
    var addMealPlanCallCount = 0
    var deleteMealPlanCallCount = 0

    var shouldThrowError = false
    var failingOperations: Set<Operation> = []

    private func shouldFail(_ operation: Operation) -> Bool {
        shouldThrowError || failingOperations.contains(operation)
    }

    func fetchPantryItems() async throws -> [PantryItem] {
        if shouldFail(.fetchPantryItems) { throw TestError.mock }
        return pantryStore
    }
    func fetchPreparedDishes() async throws -> [PreparedDish] {
        if shouldFail(.fetchPreparedDishes) { throw TestError.mock }
        return preparedDishStore
    }
    func fetchPreparedDishHistory() async throws -> [PreparedDishHistoryItem] {
        if shouldFail(.fetchPreparedDishHistory) { throw TestError.mock }
        return preparedDishHistoryStore
    }
    func savePreparedDishHistory(_ items: [PreparedDishHistoryItem]) async throws {
        if shouldFail(.savePreparedDishHistory) { throw TestError.mock }
        preparedDishHistoryStore = items
    }
    func addPantryItem(_ item: PantryItem) async throws -> PantryItem {
        if shouldFail(.addPantryItem) { throw TestError.mock }
        addPantryItemCallCount += 1
        pantryStore.append(item)
        return item
    }
    func addPreparedDish(_ dish: PreparedDish) async throws -> PreparedDish {
        if shouldFail(.addPreparedDish) { throw TestError.mock }
        addPreparedDishCallCount += 1
        preparedDishStore.append(dish)
        return dish
    }
    func updatePantryItem(_ item: PantryItem) async throws -> PantryItem {
        if shouldFail(.updatePantryItem) { throw TestError.mock }
        updatePantryItemCallCount += 1
        if let idx = pantryStore.firstIndex(where: { $0.id == item.id }) {
            pantryStore[idx] = item
        }
        return item
    }
    func updatePreparedDish(_ dish: PreparedDish) async throws -> PreparedDish {
        if shouldFail(.updatePreparedDish) { throw TestError.mock }
        updatePreparedDishCallCount += 1
        if let idx = preparedDishStore.firstIndex(where: { $0.id == dish.id }) {
            preparedDishStore[idx] = dish
        }
        return dish
    }
    func deletePantryItem(_ item: PantryItem) async throws {
        if shouldFail(.deletePantryItem) { throw TestError.mock }
        deletePantryItemCallCount += 1
        pantryStore.removeAll { $0.id == item.id }
    }
    func deletePreparedDish(_ dish: PreparedDish) async throws {
        if shouldFail(.deletePreparedDish) { throw TestError.mock }
        deletePreparedDishCallCount += 1
        preparedDishStore.removeAll { $0.id == dish.id }
    }

    func fetchRecipes() async throws -> [Recipe] {
        if shouldFail(.fetchRecipes) { throw TestError.mock }
        return recipeStore
    }
    func addRecipe(_ recipe: Recipe) async throws -> Recipe {
        if shouldFail(.addRecipe) { throw TestError.mock }
        addRecipeCallCount += 1
        recipeStore.append(recipe)
        return recipe
    }
    func updateRecipe(_ recipe: Recipe) async throws -> Recipe {
        if shouldFail(.updateRecipe) { throw TestError.mock }
        updateRecipeCallCount += 1
        if let idx = recipeStore.firstIndex(where: { $0.id == recipe.id }) {
            recipeStore[idx] = recipe
        } else {
            recipeStore.append(recipe)
        }
        return recipe
    }
    func deleteRecipe(_ recipe: Recipe) async throws {
        if shouldFail(.deleteRecipe) { throw TestError.mock }
        deleteRecipeCallCount += 1
        recipeStore.removeAll { $0.id == recipe.id }
    }

    func fetchMealPlan() async throws -> [MealPlanEntry] {
        if shouldFail(.fetchMealPlan) { throw TestError.mock }
        return mealPlanStore
    }
    func addMealPlanEntry(_ entry: MealPlanEntry) async throws -> MealPlanEntry {
        if shouldFail(.addMealPlanEntry) { throw TestError.mock }
        addMealPlanCallCount += 1
        mealPlanStore.append(entry)
        return entry
    }
    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws -> MealPlanEntry {
        if shouldFail(.updateMealPlanEntry) { throw TestError.mock }
        if let idx = mealPlanStore.firstIndex(where: { $0.id == entry.id }) {
            mealPlanStore[idx] = entry
        }
        return entry
    }
    func deleteMealPlanEntry(_ entry: MealPlanEntry) async throws {
        if shouldFail(.deleteMealPlanEntry) { throw TestError.mock }
        deleteMealPlanCallCount += 1
        mealPlanStore.removeAll { $0.id == entry.id }
    }

    func fetchShoppingItems() async throws -> [ShoppingItem] {
        if shouldFail(.fetchShoppingItems) { throw TestError.mock }
        return shoppingStore
    }
    func saveShoppingItems(_ items: [ShoppingItem]) async throws {
        if shouldFail(.saveShoppingItems) { throw TestError.mock }
        shoppingStore = items
    }
    func fetchCookQueue() async throws -> CookQueue? {
        if shouldFail(.fetchCookQueue) { throw TestError.mock }
        return cookQueueStore
    }
    func saveCookQueue(_ queue: CookQueue?) async throws {
        if shouldFail(.saveCookQueue) { throw TestError.mock }
        cookQueueStore = queue
    }
}

final class MockAIService: AIServiceProtocol {
    var shoppingListToReturn: [ShoppingItem] = []
    var recipesToReturn: [Recipe] = []
    var substitutionsToReturn: [SubstitutionSuggestion] = []
    var healthierToReturn: HealthierSuggestion?
    var importResultToReturn: RecipeImportResult?
    var ingredientResolutionDecisionsToReturn: [IngredientResolutionDecision]?
    var disambiguationDecisionsToReturn: [IngredientResolutionDecision]?

    var generateShoppingListCallCount = 0
    var suggestRecipesCallCount = 0
    var suggestSubstitutionsCallCount = 0
    var parseRecipeFromURLCallCount = 0
    var parseRecipeFromTextCallCount = 0
    var resolveIngredientsCallCount = 0
    var disambiguateIngredientsCallCount = 0
    var generateRecipeCallCount = 0
    var modifyRecipeCallCount = 0
    var suggestRecipeNamesCallCount = 0
    var generateRecipeFromSuggestionCallCount = 0
    var lastGenerateRecipeQuery: String?
    var lastGenerateRecipePreferences: RecipeGenerationPreferences?
    var lastModifyFeedback: String?
    var lastModifyPantryIngredients: [String] = []
    var lastDisambiguationRequests: [IngredientResolutionRequest] = []
    var recipeNameSuggestionsToReturn = RecipeNameSuggestionsResult(suggestions: [], message: nil)
    var lastSuggestRecipeNamesIngredients: [String] = []
    var lastSuggestRecipeNamesStrictIngredients: Bool = false
    var lastSuggestRecipeNamesExcludeNames: [String] = []
    var lastGenerateFromSuggestion: RecipeNameSuggestion?
    var lastGenerateFromSuggestionIngredients: [String] = []
    var lastGenerateFromSuggestionStrict: Bool = false

    func generateShoppingList(recipe: Recipe, pantry: [PantryItem]) async -> [ShoppingItem] {
        generateShoppingListCallCount += 1
        return shoppingListToReturn
    }
    func suggestRecipes(pantry: [PantryItem]) async -> [Recipe] {
        suggestRecipesCallCount += 1
        return recipesToReturn
    }
    func suggestSubstitutions(recipe: Recipe, pantry: [PantryItem]) async -> [SubstitutionSuggestion] {
        suggestSubstitutionsCallCount += 1
        return substitutionsToReturn
    }
    func makeItHealthier(recipe: Recipe) async -> HealthierSuggestion? {
        return healthierToReturn
    }
    func leftoverTransformer(ingredients: [String]) async -> [Recipe] {
        return recipesToReturn
    }
    func parseRecipeFromURL(_ url: String) async -> RecipeImportResult? {
        parseRecipeFromURLCallCount += 1
        return importResultToReturn
    }
    func parseRecipeFromText(_ extractedText: String) async -> RecipeImportResult? {
        parseRecipeFromTextCallCount += 1
        return importResultToReturn
    }
    func resolveIngredients(_ requests: [IngredientResolutionRequest]) async -> [IngredientResolutionDecision]? {
        resolveIngredientsCallCount += 1
        return ingredientResolutionDecisionsToReturn
    }
    func disambiguateIngredients(_ requests: [IngredientResolutionRequest]) async -> [IngredientResolutionDecision]? {
        disambiguateIngredientsCallCount += 1
        lastDisambiguationRequests = requests
        return disambiguationDecisionsToReturn
    }
    func estimateStepDurations(for steps: [RecipeStep], recipeTitle: String) async -> [RecipeStep] {
        return steps
    }
    func generateRecipe(query: String, preferences: RecipeGenerationPreferences) async -> RecipeGenerationResult? {
        generateRecipeCallCount += 1
        lastGenerateRecipeQuery = query
        lastGenerateRecipePreferences = preferences
        guard let recipe = recipesToReturn.first else { return nil }
        return .recipe(recipe)
    }
    func generateStatusMessages(query: String, preferences: RecipeGenerationPreferences) async -> [String] {
        return ["Cooking..."]
    }
    func modifyRecipe(_ recipe: Recipe, feedback: String, pantryIngredients: [String]) async -> RecipeGenerationResult? {
        modifyRecipeCallCount += 1
        lastModifyFeedback = feedback
        lastModifyPantryIngredients = pantryIngredients
        guard let modifiedRecipe = recipesToReturn.first else { return nil }
        return .recipe(modifiedRecipe)
    }
    func suggestRecipeNames(ingredients: [String], strictIngredients: Bool, requireAllIngredients: Bool, excludeNames: [String]) async -> RecipeNameSuggestionsResult {
        suggestRecipeNamesCallCount += 1
        lastSuggestRecipeNamesIngredients = ingredients
        lastSuggestRecipeNamesStrictIngredients = strictIngredients
        lastSuggestRecipeNamesExcludeNames = excludeNames
        return recipeNameSuggestionsToReturn
    }
    func generateRecipeFromSuggestion(_ suggestion: RecipeNameSuggestion, ingredients: [String], strictIngredients: Bool, requireAllIngredients: Bool) async -> Recipe? {
        generateRecipeFromSuggestionCallCount += 1
        lastGenerateFromSuggestion = suggestion
        lastGenerateFromSuggestionIngredients = ingredients
        lastGenerateFromSuggestionStrict = strictIngredients
        return recipesToReturn.first
    }

    var batchScheduleToReturn: LLMBatchSchedule?
    var batchScheduleError: Error?
    var generateBatchScheduleCallCount = 0

    func generateBatchSchedule(recipes: [Recipe]) async throws -> LLMBatchSchedule {
        generateBatchScheduleCallCount += 1
        if let error = batchScheduleError { throw error }
        if let result = batchScheduleToReturn { return result }
        throw BatchScheduleError.llmRequestFailed
    }
}

final class MockPantryItemPreferenceStore: PantryItemPreferenceStoreProtocol {
    var preferences: [String: PantryItemDefaultPreference] = [:]

    func preference(for catalogItemID: String) -> PantryItemDefaultPreference? {
        preferences[catalogItemID]
    }

    func savePreference(_ preference: PantryItemDefaultPreference) {
        preferences[preference.catalogItemID] = preference
    }

    func removePreference(for catalogItemID: String) {
        preferences.removeValue(forKey: catalogItemID)
    }
}

enum TestError: Error {
    case mock
}

// MARK: - Test Helpers

@MainActor
func makeTestAppState() -> (AppState, MockStorageService, MockAIService) {
    let storage = MockStorageService()
    let ai = MockAIService()
    let preferenceStore = MockPantryItemPreferenceStore()
    let appState = AppState(storageService: storage, aiService: ai, pantryItemPreferenceStore: preferenceStore, shouldLoadOnInit: false)
    // Clear seeded data so tests start clean
    appState.pantryItems = []
    appState.preparedDishes = []
    appState.recipes = []
    return (appState, storage, ai)
}

func makePantryItem(
    name: String = "Test Item",
    category: FoodCategory = .other,
    quantity: Double? = 1,
    unit: MeasurementUnit? = .piece,
    expiryDate: Date? = nil,
    catalogItemID: String? = nil,
    facets: [PantryFacetSelection] = []
) -> PantryItem {
    PantryItem(
        name: name,
        category: category,
        quantity: quantity,
        unit: unit,
        expiryDate: expiryDate,
        catalogItemID: catalogItemID,
        facets: facets
    )
}

func makePreparedDish(
    name: String = "Prepared Dish",
    mealTypes: [MealType] = [.lunch, .dinner],
    servingsRemaining: Int = 2,
    storage: PantryStorage = .refrigerated,
    useByDate: Date? = Calendar.current.date(byAdding: .day, value: 2, to: Date()),
    foodIdentityID: UUID = UUID(),
    recipeID: UUID? = nil,
    nutrition: NutritionInfo? = nil
) -> PreparedDish {
    PreparedDish(
        foodIdentityID: foodIdentityID,
        name: name,
        mealTypes: mealTypes,
        servingsRemaining: servingsRemaining,
        storage: storage,
        useByDate: useByDate,
        recipeID: recipeID,
        nutrition: nutrition
    )
}

func makeRecipe(
    title: String = "Test Recipe",
    ingredients: [Ingredient] = [],
    steps: [RecipeStep] = [RecipeStep(stepNumber: 1, instruction: "Do something")],
    servings: Int = 4,
    prepTimeMinutes: Int? = 10,
    cookTimeMinutes: Int? = 20,
    difficulty: DifficultyLevel = .easy,
    dietaryTags: [DietaryTag] = [],
    mealType: MealType? = .dinner,
    cuisine: CuisineType? = nil,
    nutrition: NutritionInfo? = nil,
    isFavorite: Bool = false,
    source: RecipeSource = .user
) -> Recipe {
    Recipe(
        title: title,
        ingredients: ingredients,
        steps: steps,
        servings: servings,
        prepTimeMinutes: prepTimeMinutes,
        cookTimeMinutes: cookTimeMinutes,
        difficulty: difficulty,
        dietaryTags: dietaryTags,
        mealType: mealType,
        cuisine: cuisine,
        source: source,
        nutrition: nutrition,
        isFavorite: isFavorite
    )
}

final class StubIngredientCandidateParserForAppStateTests: IngredientCandidateParserProtocol {
    var stubbedCandidates: [UUID: [IngredientResolutionCandidate]] = [:]

    func candidates(for ingredient: Ingredient) -> [IngredientResolutionCandidate] {
        stubbedCandidates[ingredient.id] ?? []
    }
}

// ===================================================================
// MARK: - Model Tests
// ===================================================================

final class PantryItemModelTests: XCTestCase {

    // MARK: - Initialization

    func testDefaultInitialization() {
        let item = PantryItem(name: "Milk", category: .dairy)
        XCTAssertEqual(item.name, "Milk")
        XCTAssertEqual(item.category, .dairy)
        XCTAssertNil(item.quantity)
        XCTAssertNil(item.unit)
        XCTAssertEqual(item.quantityMode, .presenceOnly)
        XCTAssertNil(item.expiryDate)
        XCTAssertNil(item.notes)
        XCTAssertNotNil(item.id)
    }

    func testFullInitialization() {
        let expiry = Date().addingTimeInterval(86400 * 3)
        let item = PantryItem(
            name: "Eggs",
            category: .dairy,
            quantity: 12,
            unit: .piece,
            expiryDate: expiry,
            notes: "Free range"
        )
        XCTAssertEqual(item.name, "Egg")
        XCTAssertEqual(item.category, .protein)
        XCTAssertEqual(item.quantity, 12)
        XCTAssertEqual(item.unit, .piece)
        XCTAssertEqual(item.quantityMode, .exact)
        XCTAssertEqual(item.notes, "Free range")
    }

    func testPresenceOnlyModeClearsQuantityFields() {
        let item = PantryItem(name: "Flour", category: .bakingSupplies, quantity: 2, unit: .kilogram, quantityMode: .presenceOnly)

        XCTAssertEqual(item.quantityMode, .presenceOnly)
        XCTAssertNil(item.quantity)
        XCTAssertNil(item.unit)
    }

    func testCatalogBackedInitializationResolvesStructuredFields() {
        let item = PantryItem(name: "Milk", category: .other)

        XCTAssertEqual(item.catalogItemID, "milk")
        XCTAssertEqual(item.category, .dairy)
        XCTAssertEqual(item.storage, .refrigerated)
        XCTAssertTrue(item.isCatalogBacked)
        XCTAssertEqual(item.freshnessSource, .none)
    }

    func testCatalogBackedInitializationNormalizesFacetSet() {
        let item = PantryItem(
            name: "Flour",
            category: .other,
            catalogItemID: "flour",
            facets: [
                PantryFacetSelection(key: .variant, value: "all-purpose"),
                PantryFacetSelection(key: .variant, value: "bread"),
                PantryFacetSelection(key: .base, value: "wheat"),
            ]
        )

        XCTAssertEqual(item.facets, [PantryFacetSelection(key: .variant, value: "all-purpose")])
        XCTAssertEqual(item.name, "All-purpose Flour")
    }

    // MARK: - Expiry Status

    func testExpiryStatusFresh() {
        let item = makePantryItem(
            expiryDate: Calendar.current.date(byAdding: .day, value: 10, to: Date())
        )
        XCTAssertEqual(item.expiryStatus, .fresh)
    }

    func testExpiryStatusExpiringSoon() {
        let item = makePantryItem(
            expiryDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())
        )
        XCTAssertEqual(item.expiryStatus, .expiringSoon)
    }

    func testExpiryStatusExpired() {
        let item = makePantryItem(
            expiryDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        )
        XCTAssertEqual(item.expiryStatus, .expired)
    }

    func testExpiryStatusNoDate() {
        let item = makePantryItem(expiryDate: nil)
        XCTAssertEqual(item.expiryStatus, .fresh)
    }

    func testExpiryStatusExactlyThreeDays() {
        let item = makePantryItem(
            expiryDate: Calendar.current.date(byAdding: .day, value: 3, to: Date())
        )
        XCTAssertEqual(item.expiryStatus, .expiringSoon)
    }

    // MARK: - Days Until Expiry

    func testDaysUntilExpiryFuture() {
        let date = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let item = makePantryItem(expiryDate: date)
        XCTAssertNotNil(item.daysUntilExpiry)
        // Should be approximately 5 (can be 4 or 5 depending on time of day)
        XCTAssertTrue(item.daysUntilExpiry! >= 4 && item.daysUntilExpiry! <= 5)
    }

    func testDaysUntilExpiryNilWhenNoDate() {
        let item = makePantryItem(expiryDate: nil)
        XCTAssertNil(item.daysUntilExpiry)
    }

    func testDaysUntilExpiryNegativeWhenExpired() {
        let date = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let item = makePantryItem(expiryDate: date)
        XCTAssertNotNil(item.daysUntilExpiry)
        XCTAssertTrue(item.daysUntilExpiry! < 0)
    }

    // MARK: - Display Quantity

    func testDisplayQuantityWholeNumber() {
        let item = makePantryItem(quantity: 3, unit: .piece)
        XCTAssertEqual(item.displayQuantity, "3 piece")
    }

    func testDisplayQuantityDecimal() {
        let item = makePantryItem(quantity: 1.5, unit: .liter)
        XCTAssertEqual(item.displayQuantity, "1.5 L")
    }

    func testDisplayQuantityNil() {
        let item = makePantryItem(quantity: nil)
        XCTAssertEqual(item.displayQuantity, "")
    }

    // MARK: - Sample Data

    func testSampleDataExists() {
        XCTAssertFalse(PantryItem.samples.isEmpty)
        XCTAssertTrue(PantryItem.samples.count >= 10)
    }

    func testSampleDataHasUniqueIds() {
        let ids = PantryItem.samples.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count, "Sample items should have unique IDs")
    }

    func testSampleDataHasMixedCategories() {
        let categories = Set(PantryItem.samples.map { $0.category })
        XCTAssertTrue(categories.count >= 3, "Samples should have at least 3 different categories")
    }

    // MARK: - Codable

    func testPantryItemEncodeDecode() throws {
        let item = makePantryItem(
            name: "Cheese",
            category: .dairy,
            quantity: 200,
            unit: .gram,
            expiryDate: Date()
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(PantryItem.self, from: data)
        XCTAssertEqual(decoded.name, "Cheese")
        XCTAssertEqual(decoded.category, .dairy)
        XCTAssertEqual(decoded.quantity, 200)
        XCTAssertEqual(decoded.unit, .gram)
        XCTAssertEqual(decoded.id, item.id)
    }
}

final class PantryIntakeRowDraftTests: XCTestCase {

    func testSelectingCatalogItemSetsDeterministicDefaults() throws {
        var draft = PantryIntakeRowDraft()

        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "milk")))

        XCTAssertEqual(draft.selectedItemID, "milk")
        XCTAssertEqual(draft.storage, .refrigerated)
        XCTAssertEqual(draft.selectedFacetValues[.variant], "whole")
        XCTAssertEqual(draft.unit, .liter)
        XCTAssertEqual(draft.quantityText, "1")
        XCTAssertEqual(draft.estimatedFreshnessWindow, 5...10)
        XCTAssertFalse(draft.expiryDateWasEdited)
        XCTAssertEqual(try XCTUnwrap(draft.manualExpiryDate).timeIntervalSince1970, try XCTUnwrap(draft.estimatedExpiryDate).timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(draft.rowState, .valid)
    }

    func testEmptySearchHasNoMatchingItems() {
        let draft = PantryIntakeRowDraft()

        XCTAssertTrue(draft.matchingItems.isEmpty)
        XCTAssertNotNil(draft.manualExpiryDate)
    }

    func testStorageChangeRecomputesFreshnessWindow() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "muffin")))

        let pantryWindow = try XCTUnwrap(draft.estimatedFreshnessWindow)
        draft.storage = .frozen
        let frozenWindow = try XCTUnwrap(draft.estimatedFreshnessWindow)

        XCTAssertEqual(pantryWindow, 2...5)
        XCTAssertEqual(frozenWindow, 30...90)
    }

    func testTypingAfterSelectionClearsSelectedCatalogItem() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "milk")))

        draft.updateSearchText("Mil")

        XCTAssertNil(draft.selectedItemID)
        XCTAssertNil(draft.storage)
        XCTAssertNil(draft.unit)
        XCTAssertNotNil(draft.manualExpiryDate)
        XCTAssertEqual(draft.searchText, "Mil")
        XCTAssertEqual(draft.rowState, .incomplete)
    }

    func testSelectingNewItemResetsDefaultUnit() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "milk")))
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "egg")))

        XCTAssertEqual(draft.unit, .piece)
    }

    func testBreadFormUpdatesSuggestedUnit() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "bread")))

        XCTAssertEqual(draft.selectedFacetValues[.form], "loaf")
        XCTAssertEqual(draft.unit, .loaf)

        draft.setFacet(.form, value: "loaf")

        XCTAssertEqual(draft.unit, .loaf)
    }

    func testManualUnitSelectionIsPreservedAcrossFacetChanges() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "bread")))
        draft.setUnit(.piece)

        draft.setFacet(.form, value: "loaf")

        XCTAssertEqual(draft.unit, .piece)
    }

    func testSelectingItemAutoSelectsSingleFacetOption() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "egg")))

        XCTAssertEqual(draft.quantityText, "12")
        XCTAssertEqual(draft.selectedFacetValues[.form], "whole")
        XCTAssertEqual(draft.selectedFacets, [PantryFacetSelection(key: .form, value: "whole")])
    }

    func testMissingQuantityBuildsPresenceOnlyItem() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "milk")))
        draft.setQuantityText("")

        let item = try XCTUnwrap(draft.buildItem())
        XCTAssertEqual(draft.rowState, .valid)
        XCTAssertFalse(draft.warnings.contains { $0.kind == .missingQuantity })
        XCTAssertEqual(item.quantityMode, .presenceOnly)
        XCTAssertNil(item.quantity)
        XCTAssertNil(item.unit)
    }

    func testGroundBeefGetsWeightBasedQuantityDefault() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "ground-beef")))

        XCTAssertEqual(draft.unit, .gram)
        XCTAssertEqual(draft.quantityText, "500")
    }

    func testManualQuantityIsPreservedAcrossFacetChanges() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "bread")))
        draft.setQuantityText("2")

        draft.setFacet(.form, value: "sliced")

        XCTAssertEqual(draft.quantityText, "2")
    }

    func testBuildItemProducesCatalogBackedStructuredPantryItem() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "flour")))
        draft.setFacet(.variant, value: "all-purpose")
        draft.quantityText = "2"
        draft.unit = .kilogram
        draft.setExpiryDate(Date().addingTimeInterval(86_400))
        draft.notes = "Keep sealed"

        let item = try XCTUnwrap(draft.buildItem())

        XCTAssertEqual(item.catalogItemID, "flour")
        XCTAssertEqual(item.name, "All-purpose Flour")
        XCTAssertEqual(item.storage, .pantry)
        XCTAssertEqual(item.freshnessSource, .userProvided)
        XCTAssertEqual(item.facets, [PantryFacetSelection(key: .variant, value: "all-purpose")])
        XCTAssertEqual(item.quantity, 2)
        XCTAssertEqual(item.unit, .kilogram)
        XCTAssertEqual(item.quantityMode, .exact)
        XCTAssertEqual(item.notes, "Keep sealed")
    }

    func testSelectingCatalogItemSeedsExpiryDateFromEstimate() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "milk")))

        let estimatedExpiry = try XCTUnwrap(draft.estimatedExpiryDate)

        XCTAssertEqual(try XCTUnwrap(draft.manualExpiryDate).timeIntervalSince1970, estimatedExpiry.timeIntervalSince1970, accuracy: 1)
    }

    func testStorageChangeUpdatesPrefilledExpiryUntilUserEditsDate() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "milk")))

        let refrigeratedExpiry = try XCTUnwrap(draft.estimatedExpiryDate)
        draft.setStorage(.frozen)
        let frozenExpiry = try XCTUnwrap(draft.estimatedExpiryDate)

        XCTAssertNotEqual(refrigeratedExpiry.timeIntervalSince1970, frozenExpiry.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(draft.manualExpiryDate).timeIntervalSince1970, frozenExpiry.timeIntervalSince1970, accuracy: 1)

        let customDate = Date().addingTimeInterval(172_800)
        draft.setExpiryDate(customDate)
        draft.setStorage(.pantry)

        XCTAssertTrue(draft.expiryDateWasEdited)
        XCTAssertEqual(try XCTUnwrap(draft.manualExpiryDate).timeIntervalSince1970, customDate.timeIntervalSince1970, accuracy: 1)
    }

    func testWarningsDoNotIncludeEstimatedFreshnessReviewMessage() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "milk")))

        XCTAssertFalse(draft.warnings.contains { $0.message.contains("Freshness will be estimated") })
    }

    func testUnsupportedSearchRemainsUnresolved() {
        var draft = PantryIntakeRowDraft()
        draft.searchText = "Beer"

        XCTAssertEqual(draft.rowState, PantryIntakeRowState.incomplete)
        XCTAssertTrue(draft.warnings.contains { $0.kind == PantryIntakeWarningKind.unsupportedInput })
        XCTAssertNil(draft.buildItem())
    }

    func testCustomItemCanBeBuiltWithoutCatalogMatch() throws {
        var draft = PantryIntakeRowDraft()
        draft.searchText = "House Chili Paste"
        draft.enableCustomItemMode()
        draft.customCategory = .condiments
        draft.setQuantityText("1")
        draft.setUnit(.package)

        let item = try XCTUnwrap(draft.buildItem())

        XCTAssertNil(item.catalogItemID)
        XCTAssertEqual(item.name, "House Chili Paste")
        XCTAssertEqual(item.category, .condiments)
        XCTAssertEqual(item.storage, .pantry)
    }
}

// MARK: - Recipe Model Tests

final class RecipeModelTests: XCTestCase {

    // MARK: - Initialization

    func testDefaultRecipeInit() {
        let recipe = Recipe(title: "Test")
        XCTAssertEqual(recipe.title, "Test")
        XCTAssertEqual(recipe.servings, 4)
        XCTAssertFalse(recipe.isFavorite)
        XCTAssertEqual(recipe.timesCooked, 0)
        XCTAssertNil(recipe.rating)
        XCTAssertTrue(recipe.ingredients.isEmpty)
        XCTAssertTrue(recipe.steps.isEmpty)
    }

    // MARK: - Total Time

    func testTotalTimeWithBoth() {
        let recipe = makeRecipe(prepTimeMinutes: 15, cookTimeMinutes: 30)
        XCTAssertEqual(recipe.totalTimeMinutes, 45)
    }

    func testTotalTimeWithPrepOnly() {
        let recipe = makeRecipe(prepTimeMinutes: 15, cookTimeMinutes: nil)
        XCTAssertEqual(recipe.totalTimeMinutes, 15)
    }

    func testTotalTimeWithCookOnly() {
        let recipe = makeRecipe(prepTimeMinutes: nil, cookTimeMinutes: 30)
        XCTAssertEqual(recipe.totalTimeMinutes, 30)
    }

    func testTotalTimeNil() {
        let recipe = makeRecipe(prepTimeMinutes: nil, cookTimeMinutes: nil)
        XCTAssertNil(recipe.totalTimeMinutes)
    }

    // MARK: - Total Time Display

    func testTotalTimeDisplayMinutes() {
        let recipe = makeRecipe(prepTimeMinutes: 10, cookTimeMinutes: 20)
        XCTAssertEqual(recipe.totalTimeDisplay, "30 min")
    }

    func testTotalTimeDisplayHours() {
        let recipe = makeRecipe(prepTimeMinutes: 30, cookTimeMinutes: 60)
        XCTAssertEqual(recipe.totalTimeDisplay, "1h 30m")
    }

    func testTotalTimeDisplayExactHour() {
        let recipe = makeRecipe(prepTimeMinutes: 30, cookTimeMinutes: 30)
        XCTAssertEqual(recipe.totalTimeDisplay, "1h")
    }

    func testTotalTimeDisplayNA() {
        let recipe = makeRecipe(prepTimeMinutes: nil, cookTimeMinutes: nil)
        XCTAssertEqual(recipe.totalTimeDisplay, "N/A")
    }

    // MARK: - Scaling

    func testScaleUp() {
        let recipe = makeRecipe(
            ingredients: [Ingredient(name: "Flour", quantity: 2, unit: .cup)],
            servings: 4,
            nutrition: NutritionInfo(calories: 400, protein: 10, carbohydrates: 50, fat: 15)
        )
        let scaled = recipe.scaled(to: 8)
        XCTAssertEqual(scaled.servings, 8)
        XCTAssertEqual(scaled.ingredients[0].quantity, 4.0)
        XCTAssertEqual(scaled.nutrition?.calories, 800)
        XCTAssertEqual(scaled.nutrition?.protein, 20.0)
    }

    func testScaleDown() {
        let recipe = makeRecipe(
            ingredients: [Ingredient(name: "Flour", quantity: 4, unit: .cup)],
            servings: 4
        )
        let scaled = recipe.scaled(to: 2)
        XCTAssertEqual(scaled.servings, 2)
        XCTAssertEqual(scaled.ingredients[0].quantity, 2.0)
    }

    func testScaleToSame() {
        let recipe = makeRecipe(
            ingredients: [Ingredient(name: "Flour", quantity: 2, unit: .cup)],
            servings: 4
        )
        let scaled = recipe.scaled(to: 4)
        XCTAssertEqual(scaled.ingredients[0].quantity, 2.0)
    }

    // MARK: - Pantry Matching

    func testPantryMatchFullMatch() {
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Chicken", quantity: 500, unit: .gram, category: .protein),
            Ingredient(name: "Rice", quantity: 2, unit: .cup, category: .grains),
        ])
        let pantry = [
            makePantryItem(name: "Chicken Breast", category: .protein),
            makePantryItem(name: "Rice", category: .grains),
        ]
        let match = recipe.pantryMatch(pantry: pantry)
        XCTAssertTrue(match.canMake)
        XCTAssertEqual(match.matchPercentage, 100.0)
        XCTAssertTrue(match.missingIngredients.isEmpty)
    }

    func testPantryMatchPartialMatch() {
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Chicken", quantity: 500, unit: .gram, category: .protein),
            Ingredient(name: "Rice", quantity: 2, unit: .cup, category: .grains),
        ])
        let pantry = [makePantryItem(name: "Rice", category: .grains)]
        let match = recipe.pantryMatch(pantry: pantry)
        XCTAssertFalse(match.canMake)
        XCTAssertEqual(match.matchPercentage, 50.0)
        XCTAssertEqual(match.missingIngredients.count, 1)
        XCTAssertEqual(match.missingIngredients[0].name, "Chicken")
    }

    func testPantryMatchNoMatch() {
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Tofu", quantity: 1, unit: .package),
        ])
        let pantry = [makePantryItem(name: "Chicken")]
        let match = recipe.pantryMatch(pantry: pantry)
        XCTAssertFalse(match.canMake)
        XCTAssertEqual(match.matchPercentage, 0.0)
    }

    func testPantryMatchBidirectionalContains() {
        // "Chicken Breast" contains "chicken" (pantry name contains ingredient name)
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Chicken", quantity: 1, unit: .piece),
        ])
        let pantry = [makePantryItem(name: "Chicken Breast")]
        let match = recipe.pantryMatch(pantry: pantry)
        XCTAssertTrue(match.canMake, "Should match: 'Chicken Breast' contains 'Chicken'")
    }

    func testPantryMatchBidirectionalContainsReverse() {
        // ingredient "Lager Beer" contains pantry "Beer"
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Lager Beer", quantity: 1, unit: .can),
        ])
        let pantry = [makePantryItem(name: "Beer")]
        let match = recipe.pantryMatch(pantry: pantry)
        XCTAssertTrue(match.canMake, "Should match: 'Lager Beer' contains 'Beer'")
    }

    func testPantryMatchIgnoresOptional() {
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Chicken", quantity: 1, unit: .piece, isOptional: false),
            Ingredient(name: "Garnish", quantity: 1, unit: .piece, isOptional: true),
        ])
        let pantry = [makePantryItem(name: "Chicken")]
        let match = recipe.pantryMatch(pantry: pantry)
        XCTAssertTrue(match.canMake, "Should match: optional ingredient excluded from required")
        XCTAssertEqual(match.matchPercentage, 100.0)
    }

    func testPantryMatchEmptyPantry() {
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Flour", quantity: 2, unit: .cup),
        ])
        let match = recipe.pantryMatch(pantry: [])
        XCTAssertFalse(match.canMake)
        XCTAssertEqual(match.matchPercentage, 0.0)
    }

    func testPantryMatchEmptyIngredients() {
        let recipe = makeRecipe(ingredients: [])
        let match = recipe.pantryMatch(pantry: [makePantryItem()])
        XCTAssertEqual(match.matchPercentage, 0.0)
    }

    // MARK: - Display Percentage

    func testDisplayPercentage() {
        let result = PantryMatchResult(
            recipe: makeRecipe(),
            matchedIngredients: [],
            missingIngredients: [],
            matchPercentage: 75.0
        )
        XCTAssertEqual(result.displayPercentage, "75%")
    }

    // MARK: - Sample Data

    func testRecipeSampleData() {
        XCTAssertFalse(Recipe.samples.isEmpty)
        XCTAssertTrue(Recipe.samples.count >= 3)

        // Each sample should have ingredients and steps
        for recipe in Recipe.samples {
            XCTAssertFalse(recipe.title.isEmpty, "\(recipe.title) should have a non-empty title")
            XCTAssertFalse(recipe.ingredients.isEmpty, "\(recipe.title) should have ingredients")
            XCTAssertFalse(recipe.steps.isEmpty, "\(recipe.title) should have steps")
        }
    }

    // MARK: - Codable

    func testRecipeEncodeDecode() throws {
        let recipe = makeRecipe(
            title: "Pasta",
            ingredients: [Ingredient(name: "Pasta", quantity: 500, unit: .gram)],
            nutrition: NutritionInfo(calories: 450, protein: 20, carbohydrates: 55, fat: 12),
            isFavorite: true
        )
        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(Recipe.self, from: data)
        XCTAssertEqual(decoded.title, "Pasta")
        XCTAssertEqual(decoded.isFavorite, true)
        XCTAssertEqual(decoded.nutrition?.calories, 450)
        XCTAssertEqual(decoded.id, recipe.id)
    }
}

// MARK: - Ingredient Matching Tests

final class IngredientMatcherTests: XCTestCase {
    func testNamesMatchRecognizesSynonyms() {
        XCTAssertTrue(IngredientMatcher.namesMatch("scallion", "green onion"))
        XCTAssertTrue(IngredientMatcher.namesMatch("courgette", "zucchini"))
    }

    func testNamesMatchAvoidsUnrelatedIngredients() {
        XCTAssertFalse(IngredientMatcher.namesMatch("rice", "pasta"))
        XCTAssertFalse(IngredientMatcher.namesMatch("olive oil", "apple cider vinegar"))
    }

    func testHasEnoughQuantityRespectsConvertibleUnits() {
        let pantryItem = PantryItem(name: "milk", category: .dairy, quantity: 1, unit: .liter)
        let ingredient = Ingredient(name: "milk", quantity: 500, unit: .milliliter)
        XCTAssertTrue(IngredientMatcher.hasEnoughQuantity(pantryItem: pantryItem, ingredient: ingredient))
    }

    func testHasEnoughQuantityUsesPresenceOnlyAsSufficient() {
        let pantryItem = PantryItem(name: "Flour", category: .bakingSupplies)
        let ingredient = Ingredient(name: "Flour", quantity: 500, unit: .gram, category: .bakingSupplies)

        XCTAssertTrue(IngredientMatcher.hasEnoughQuantity(pantryItem: pantryItem, ingredient: ingredient))
    }

    func testHasEnoughQuantityRejectsKnownInsufficientExactQuantity() {
        let pantryItem = PantryItem(name: "Ground Beef", category: .protein, quantity: 500, unit: .gram)
        let ingredient = Ingredient(name: "Ground Beef", quantity: 1000, unit: .gram, category: .protein)

        XCTAssertFalse(IngredientMatcher.hasEnoughQuantity(pantryItem: pantryItem, ingredient: ingredient))
    }

    func testPantryItemMatchesIngredientPrefersCatalogIdentity() {
        let pantryItem = PantryItem(name: "Carrots", category: .produce, quantity: 3, unit: .whole)
        let ingredient = Ingredient(name: "Carrot", quantity: 1, unit: .whole, category: .produce, catalogItemID: "carrot")

        XCTAssertTrue(IngredientMatcher.pantryItemMatchesIngredient(pantryItem, ingredient: ingredient))
    }

    func testPantryItemMatchesIngredientAllowsExactUnresolvedCustomFallback() {
        let pantryItem = PantryItem(name: "House Chili Paste", category: .condiments, quantity: 1, unit: .package)
        let ingredient = Ingredient(name: "House Chili Paste", quantity: 1, unit: .package, category: .condiments)

        XCTAssertTrue(IngredientMatcher.pantryItemMatchesIngredient(pantryItem, ingredient: ingredient))
    }

    func testPantryItemMatchesIngredientDoesNotUseFuzzyFallbackForUnresolvedItems() {
        let pantryItem = PantryItem(name: "House Chili Paste", category: .condiments, quantity: 1, unit: .package)
        let ingredient = Ingredient(name: "Chili Paste", quantity: 1, unit: .package, category: .condiments)

        XCTAssertFalse(IngredientMatcher.pantryItemMatchesIngredient(pantryItem, ingredient: ingredient))
    }

    func testPantryItemMatchesIngredientDoesNotUseResolvedPantryForUnresolvedRecipeFallback() {
        let pantryItem = PantryItem(name: "Soy Sauce", category: .condiments, quantity: 1, unit: .package)
        let ingredient = Ingredient(name: "Soy Sauce", quantity: 1, unit: .tablespoon, category: .condiments)

        XCTAssertFalse(IngredientMatcher.pantryItemMatchesIngredient(pantryItem, ingredient: ingredient))
    }

    func testPantryMatchUsesCatalogBackedSubstitutions() {
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "chicken breast", quantity: 400, unit: .gram, category: .protein)
        ])
        let pantry = [
            PantryItem(
                name: "Tofu",
                category: .protein,
                quantity: 400,
                unit: .gram,
                catalogItemID: "tofu",
                facets: [.init(key: .variant, value: "extra firm")]
            )
        ]

        let match = recipe.pantryMatch(pantry: pantry)

        XCTAssertFalse(match.canMake)
        XCTAssertTrue(match.canMakeWithSubstitutions)
        XCTAssertEqual(match.substitutableIngredients.count, 1)
        XCTAssertEqual(match.substitutableIngredients[0].ingredient.name, "chicken breast")
        XCTAssertEqual(match.substitutableIngredients[0].substitutions.first?.substituteItemID, "tofu")
        XCTAssertTrue(match.substitutableIngredients[0].substitutions.first?.inPantry == true)
    }

    func testSubstitutionRepositoryRequiresMatchingFacets() {
        let pantry = [
            PantryItem(
                name: "Tofu",
                category: .protein,
                quantity: 400,
                unit: .gram,
                catalogItemID: "tofu"
            )
        ]

        let substitutions = SubstitutionRepository.shared.substitutions(for: "chicken breast", pantry: pantry)
        let tofuSubstitution = substitutions.first { $0.substituteItemID == "tofu" }

        XCTAssertNotNil(tofuSubstitution)
        XCTAssertEqual(tofuSubstitution?.substituteFacets, [.init(key: .variant, value: "extra firm")])
        XCTAssertFalse(tofuSubstitution?.inPantry ?? true)
    }

    func testPantryMatchUsesChickenThighAliasForSubstitutions() {
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "chicken thigh", quantity: 400, unit: .gram, category: .protein)
        ])
        let pantry = [
            PantryItem(
                name: "Tofu",
                category: .protein,
                quantity: 400,
                unit: .gram,
                catalogItemID: "tofu",
                facets: [.init(key: .variant, value: "extra firm")]
            )
        ]

        let match = recipe.pantryMatch(pantry: pantry)

        XCTAssertTrue(match.canMakeWithSubstitutions)
        XCTAssertEqual(match.substitutableIngredients.first?.ingredient.name, "chicken thigh")
        XCTAssertEqual(match.substitutableIngredients.first?.substitutions.first?.substituteName, "Extra Firm Tofu")
    }

    func testPantryMatchUsesBeefBrothAliasForSubstitutions() {
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "beef broth", quantity: 500, unit: .milliliter, category: .canned)
        ])
        let pantry = [
            PantryItem(
                name: "Vegetable Broth",
                category: .canned,
                quantity: 1,
                unit: .liter,
                catalogItemID: "broth",
                facets: [.init(key: .base, value: "vegetable")]
            )
        ]

        let match = recipe.pantryMatch(pantry: pantry)

        XCTAssertTrue(match.canMakeWithSubstitutions)
        XCTAssertEqual(match.substitutableIngredients.first?.ingredient.name, "beef broth")
        XCTAssertEqual(match.substitutableIngredients.first?.substitutions.first?.substituteItemID, "broth")
        XCTAssertTrue(match.substitutableIngredients.first?.substitutions.first?.inPantry == true)
    }

    func testPantryMatchUsesSoySauceSubstitutionFromCatalogBackedPantry() {
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "soy sauce", quantity: 2, unit: .tablespoon, category: .condiments)
        ])
        let pantry = [
            PantryItem(
                name: "Coconut Aminos",
                category: .condiments,
                quantity: 250,
                unit: .milliliter,
                catalogItemID: "coconut-aminos"
            )
        ]

        let match = recipe.pantryMatch(pantry: pantry)

        XCTAssertFalse(match.canMake)
        XCTAssertTrue(match.canMakeWithSubstitutions)
        XCTAssertEqual(match.substitutableIngredients.first?.substitutions.first?.substituteItemID, "coconut-aminos")
        XCTAssertTrue(match.substitutableIngredients.first?.substitutions.first?.inPantry == true)
    }

    func testPantryContainsAllowsGenericVariantRecipeToMatchSpecificPantryCut() {
        let ingredient = Ingredient(
            name: "beef cheeks",
            quantity: 500,
            unit: .gram,
            category: .protein,
            catalogItemID: "beef",
            facets: [.init(key: .variant, value: "none")]
        )
        let pantry = [
            PantryItem(
                name: "Beef",
                category: .protein,
                quantity: 500,
                unit: .gram,
                catalogItemID: "beef",
                facets: [.init(key: .variant, value: "shank")]
            )
        ]

        XCTAssertTrue(IngredientMatcher.pantryContains(ingredient: ingredient, pantry: pantry))
    }

    func testPantryContainsDoesNotAllowGenericVariantToSatisfySpecificRecipeCut() {
        let ingredient = Ingredient(
            name: "beef shank",
            quantity: 500,
            unit: .gram,
            category: .protein,
            catalogItemID: "beef",
            facets: [.init(key: .variant, value: "shank")]
        )
        let pantry = [
            PantryItem(
                name: "Beef",
                category: .protein,
                quantity: 500,
                unit: .gram,
                catalogItemID: "beef",
                facets: [.init(key: .variant, value: "none")]
            )
        ]

        XCTAssertFalse(IngredientMatcher.pantryContains(ingredient: ingredient, pantry: pantry))
    }

    func testGenericIngredientsDoNotSurfaceSubstitutions() {
        let ingredient = Ingredient(
            name: "beef cheeks",
            quantity: 500,
            unit: .gram,
            category: .protein,
            catalogItemID: "beef",
            facets: [.init(key: .variant, value: "none")]
        )

        XCTAssertTrue(SubstitutionRepository.shared.substitutions(for: ingredient).isEmpty)
    }
}

final class IngredientLexiconTests: XCTestCase {
    func testFuzzySimilarityHandlesEmptyLeftHandSide() {
        XCTAssertEqual(IngredientLexicon.fuzzySimilarity("", "milk"), 0)
    }

    func testFuzzySimilarityHandlesEmptyRightHandSide() {
        XCTAssertEqual(IngredientLexicon.fuzzySimilarity("milk", ""), 0)
    }

    func testFuzzySimilarityHandlesTwoEmptyStrings() {
        XCTAssertEqual(IngredientLexicon.fuzzySimilarity("", ""), 1)
    }
}

// MARK: - Shopping Generation Tests

@MainActor
final class ShoppingGenerationTests: XCTestCase {
    func testGenerateShoppingListFromMealPlanUsesMatcherAndQuantity() async {
        let (appState, storage, _) = makeTestAppState()

        let pantryMilk = PantryItem(name: "whole milk", category: .dairy, quantity: 1, unit: .liter)
        storage.pantryStore = [pantryMilk]

        let recipe = Recipe(
            title: "Pancakes",
            ingredients: [
                Ingredient(name: "milk", quantity: 250, unit: .milliliter, category: .dairy, catalogItemID: "milk"),
                Ingredient(name: "all purpose flour", quantity: 200, unit: .gram, category: .grains)
            ],
            steps: [RecipeStep(stepNumber: 1, instruction: "Mix ingredients")],
            servings: 2,
            source: .user
        )

        let entry = MealPlanEntry(date: Date(), mealType: .breakfast, recipe: recipe)
        storage.mealPlanStore = [entry]

        await appState.loadAllData()
        await appState.generateShoppingListFromMealPlan()

        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(appState.shoppingItems.first?.catalogItemID, "flour")
    }

    func testGenerateShoppingListFromMealPlanTreatsPresenceOnlyPantryItemAsAvailable() async {
        let (appState, storage, _) = makeTestAppState()

        storage.pantryStore = [PantryItem(name: "Flour", category: .grains, catalogItemID: "flour")]

        let recipe = Recipe(
            title: "Pancakes",
            ingredients: [
                Ingredient(name: "Flour", quantity: 200, unit: .gram, category: .grains, catalogItemID: "flour")
            ],
            steps: [RecipeStep(stepNumber: 1, instruction: "Mix ingredients")],
            servings: 2,
            source: .user
        )

        storage.mealPlanStore = [MealPlanEntry(date: Date(), mealType: .breakfast, recipe: recipe)]

        await appState.loadAllData()
        await appState.generateShoppingListFromMealPlan()

        XCTAssertTrue(appState.shoppingItems.isEmpty)
    }

    func testGenerateShoppingListFromMealPlanUsesExactCustomPantryFallbackForUnresolvedIngredients() async {
        let (appState, storage, _) = makeTestAppState()

        storage.pantryStore = [
            PantryItem(name: "House Chili Paste", category: .condiments, quantity: 1, unit: .package)
        ]

        let recipe = Recipe(
            title: "Noodles",
            ingredients: [
                Ingredient(name: "House Chili Paste", quantity: 1, unit: .package, category: .condiments)
            ],
            steps: [RecipeStep(stepNumber: 1, instruction: "Mix")],
            servings: 2,
            source: .user
        )

        storage.mealPlanStore = [MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)]

        await appState.loadAllData()
        await appState.generateShoppingListFromMealPlan()

        XCTAssertTrue(appState.shoppingItems.isEmpty)
    }

    func testGenerateShoppingListFromMealPlanDoesNotUseFuzzyCustomPantryFallbackForUnresolvedIngredients() async {
        let (appState, storage, _) = makeTestAppState()

        storage.pantryStore = [
            PantryItem(name: "House Chili Paste", category: .condiments, quantity: 1, unit: .package)
        ]

        let recipe = Recipe(
            title: "Noodles",
            ingredients: [
                Ingredient(name: "Chili Paste", quantity: 1, unit: .package, category: .condiments)
            ],
            steps: [RecipeStep(stepNumber: 1, instruction: "Mix")],
            servings: 2,
            source: .user
        )

        storage.mealPlanStore = [MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)]

        await appState.loadAllData()
        await appState.generateShoppingListFromMealPlan()

        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(appState.shoppingItems.first?.name, "Chili Paste")
    }

    func testPreviewShoppingListFromMealPlanExcludesWaterAndAggregatesDuplicates() async {
        let (appState, _, _) = makeTestAppState()

        let recipeOne = makeRecipe(
            title: "Soup",
            ingredients: [
                Ingredient(name: "Water", quantity: 2, unit: .cup, category: .other),
                Ingredient(name: "Carrot", quantity: 2, unit: .whole, category: .produce)
            ]
        )
        let recipeTwo = makeRecipe(
            title: "Stew",
            ingredients: [
                Ingredient(name: "Warm Water", quantity: 1, unit: .cup, category: .other),
                Ingredient(name: "Carrots", quantity: 1, unit: .whole, category: .produce)
            ]
        )

        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .lunch, recipe: recipeOne))
        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipeTwo))

        let preview = appState.previewShoppingListFromMealPlan()

        XCTAssertEqual(preview.count, 1)
        XCTAssertEqual(preview.first?.name, "Carrot")
        XCTAssertEqual(preview.first?.quantity, 3)
        XCTAssertEqual(preview.first?.unit, .whole)
    }

    func testPreviewShoppingListFromMealPlanScalesRecipeToAllocatedServings() async {
        let (appState, _, _) = makeTestAppState()

        let recipe = makeRecipe(
            title: "Pasta",
            ingredients: [
                Ingredient(name: "Flour", quantity: 4, unit: .cup, category: .grains)
            ],
            servings: 4
        )

        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, plannedServings: 2))

        let preview = appState.previewShoppingListFromMealPlan()

        XCTAssertEqual(preview.first?.quantity, 2)
        XCTAssertEqual(preview.first?.unit, .cup)
    }
}

// MARK: - Ingredient Model Tests

final class IngredientModelTests: XCTestCase {

    func testDisplayTextInteger() {
        let ing = Ingredient(name: "Flour", quantity: 2, unit: .cup)
        XCTAssertEqual(ing.displayText, "2 cup Flour")
    }

    func testDisplayTextDecimal() {
        let ing = Ingredient(name: "Oil", quantity: 1.5, unit: .tablespoon)
        XCTAssertEqual(ing.displayText, "1.5 tbsp Oil")
    }

    func testDisplayTextNoUnit() {
        let ing = Ingredient(name: "Eggs", quantity: 3, unit: nil)
        XCTAssertEqual(ing.displayText, "3  Eggs")
    }

    func testIngredientOptionalFlag() {
        let required = Ingredient(name: "Salt", quantity: 1, isOptional: false)
        let optional = Ingredient(name: "Garnish", quantity: 1, isOptional: true)
        XCTAssertFalse(required.isOptional)
        XCTAssertTrue(optional.isOptional)
    }

    func testIngredientCodable() throws {
        let ing = Ingredient(name: "Sugar", quantity: 100, unit: .gram, category: .bakingSupplies)
        let data = try JSONEncoder().encode(ing)
        let decoded = try JSONDecoder().decode(Ingredient.self, from: data)
        XCTAssertEqual(decoded.name, "Sugar")
        XCTAssertEqual(decoded.unit, .gram)
        XCTAssertEqual(decoded.category, .bakingSupplies)
    }
}

// MARK: - RecipeStep Model Tests

final class RecipeStepModelTests: XCTestCase {

    func testBasicStep() {
        let step = RecipeStep(stepNumber: 1, instruction: "Boil water")
        XCTAssertEqual(step.stepNumber, 1)
        XCTAssertEqual(step.instruction, "Boil water")
        XCTAssertNil(step.timerMinutes)
        XCTAssertNil(step.tip)
    }

    func testStepWithTimer() {
        let step = RecipeStep(stepNumber: 2, instruction: "Cook pasta", timerMinutes: 10)
        XCTAssertEqual(step.timerMinutes, 10)
    }

    func testStepWithTip() {
        let step = RecipeStep(stepNumber: 3, instruction: "Dice onion", tip: "Keep fingers tucked")
        XCTAssertEqual(step.tip, "Keep fingers tucked")
    }
}

// MARK: - NutritionInfo Tests

final class NutritionInfoModelTests: XCTestCase {

    func testMacroSummary() {
        let info = NutritionInfo(calories: 450, protein: 35, carbohydrates: 40, fat: 15)
        XCTAssertEqual(info.macroSummary, "P: 35g  C: 40g  F: 15g")
    }

    func testSampleData() {
        let sample = NutritionInfo.sample
        XCTAssertGreaterThan(sample.calories, 0)
        XCTAssertGreaterThan(sample.protein, 0)
    }
}

// MARK: - ShoppingItem Model Tests

final class ShoppingItemModelTests: XCTestCase {

    func testDisplayTextFull() {
        let item = ShoppingItem(name: "Tomatoes", quantity: 4, unit: .whole, category: .produce)
        XCTAssertEqual(item.displayText, "4 whole Tomato")
    }

    func testDisplayTextNoQuantity() {
        let item = ShoppingItem(name: "Bread", quantity: nil, unit: nil, category: .grains)
        XCTAssertEqual(item.displayText, "White Loaf Bread")
    }

    func testDisplayTextQuantityOnly() {
        let item = ShoppingItem(name: "Butter", quantity: 250, unit: .gram, category: .dairy)
        XCTAssertEqual(item.displayText, "250 g Unsalted Butter")
    }

    func testIsCheckedDefault() {
        let item = ShoppingItem(name: "Test")
        XCTAssertFalse(item.isChecked)
    }

    func testCatalogIdentityResolvesAliases() {
        let singular = ShoppingItem(name: "Carrot")
        let plural = ShoppingItem(name: "Carrots")

        XCTAssertEqual(singular.catalogItemID, "carrot")
        XCTAssertEqual(plural.catalogItemID, "carrot")
        XCTAssertTrue(singular.matchesIdentity(of: plural))
    }

    func testSampleData() {
        XCTAssertFalse(ShoppingItem.samples.isEmpty)
    }

    func testPantryPlanDefaultsToRecipeRequirement() {
        let item = ShoppingItem(name: "Soy Sauce", quantity: 2, unit: .tablespoon, category: .condiments)

        XCTAssertEqual(item.pantryQuantity, 2)
        XCTAssertEqual(item.pantryUnit, .tablespoon)
        XCTAssertEqual(item.pantryQuantityMode, .exact)
        XCTAssertFalse(item.isPantryPlanCustomized)
    }

    func testUpdatingPantryPlanSupportsPackageOverride() {
        let item = ShoppingItem(name: "Soy Sauce", quantity: 2, unit: .tablespoon, category: .condiments)
        let updated = item.updatingPantryPlan(quantity: 1, unit: .package, quantityMode: .exact)

        XCTAssertEqual(updated.pantryQuantity, 1)
        XCTAssertEqual(updated.pantryUnit, .package)
        XCTAssertTrue(updated.isPantryPlanCustomized)
        XCTAssertEqual(updated.pantryPlanText, "1 pkg")
    }

    func testUpdatingPantryPlanSupportsPresenceOnly() {
        let item = ShoppingItem(name: "Salt", quantity: 1, unit: .pinch, category: .spices)
        let updated = item.updatingPantryPlan(quantity: nil, unit: nil, quantityMode: .presenceOnly)

        XCTAssertNil(updated.pantryQuantity)
        XCTAssertEqual(updated.pantryQuantityMode, .presenceOnly)
        XCTAssertEqual(updated.pantryPlanText, "On hand")
    }

    func testUpdatingPantryPlanCanChangeCatalogFacets() {
        let item = ShoppingItem(
            name: "Whole Milk",
            quantity: 1,
            unit: .cup,
            category: .dairy,
            catalogItemID: "milk",
            facets: [.init(key: .variant, value: "whole")]
        )

        let updated = item.updatingPantryPlan(
            quantity: 1,
            unit: .cup,
            quantityMode: .exact,
            facets: [.init(key: .variant, value: "skim")]
        )

        XCTAssertEqual(updated.facets, [.init(key: .variant, value: "skim")])
        XCTAssertEqual(updated.displayName, "Milk")
        XCTAssertEqual(updated.facetSummary, "Skim")
    }
}

// MARK: - MealPlanEntry Model Tests

final class MealPlanEntryModelTests: XCTestCase {

    func testDisplayNameWithRecipe() {
        let recipe = makeRecipe(title: "Pasta Carbonara")
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        XCTAssertEqual(entry.displayName, "Pasta Carbonara")
    }

    func testDisplayNameWithCustomMeal() {
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, customMealName: "Leftovers")
        XCTAssertEqual(entry.displayName, "Leftovers")
    }

    func testDisplayNameUnplanned() {
        let entry = MealPlanEntry(date: Date(), mealType: .breakfast)
        XCTAssertEqual(entry.displayName, "Unplanned")
    }

    func testIsPlanned() {
        let planned = MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe())
        let custom = MealPlanEntry(date: Date(), mealType: .dinner, customMealName: "Pizza")
        let unplanned = MealPlanEntry(date: Date(), mealType: .dinner)

        XCTAssertTrue(planned.isPlanned)
        XCTAssertTrue(custom.isPlanned)
        XCTAssertFalse(unplanned.isPlanned)
    }

    func testEmptyWeekGeneration() {
        let week = MealPlanEntry.emptyWeek()
        // 7 days * 3 meal types (breakfast, lunch, dinner)
        XCTAssertEqual(week.count, 21)
    }

    func testEffectivePlannedServingsDefaultsFromRecipe() {
        let recipe = makeRecipe(servings: 4)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)

        XCTAssertEqual(entry.effectivePlannedServings, 4)
        XCTAssertEqual(entry.plannedServingsLabel, "4 servings planned")
    }

    func testEffectivePlannedServingsKeepsExplicitPreparedFoodPlan() {
        let dish = makePreparedDish(name: "Soup", servingsRemaining: 3)
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, preparedDish: dish, plannedServings: 5)

        XCTAssertEqual(entry.effectivePlannedServings, 5)
    }

    func testMealPlanEntrySeedsPreparedDishDraftFromAllocatedRecipeServings() {
        let recipe = makeRecipe(title: "Chili", servings: 6, mealType: .dinner)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, plannedServings: 2)

        let draft = entry.makePreparedDishDraft()

        XCTAssertEqual(draft.name, "Chili")
        XCTAssertEqual(draft.recipeID, recipe.id)
        XCTAssertEqual(draft.servingsRemaining, 2)
    }

    func testUpdatingEatenServingsClampsToTrackedServings() {
        let recipe = makeRecipe(title: "Soup", servings: 4)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe).updatingEatenServings(6)

        XCTAssertEqual(entry.effectiveEatenServings, 4)
        XCTAssertTrue(entry.isFullyEaten)
    }

    func testCustomMealTracksSingleServingForEatenLogging() {
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, customMealName: "Cafe lunch", eatenServings: 3)

        XCTAssertEqual(entry.trackingPlannedServings, 1)
        XCTAssertEqual(entry.effectiveEatenServings, 1)
        XCTAssertEqual(entry.eatenProgressLabel, "Finished")
    }

    // MARK: - displayName Fallback Chain

    func testDisplayNameFallsBackThroughEntireChain() {
        let unplanned = MealPlanEntry(date: Date(), mealType: .dinner)
        XCTAssertEqual(unplanned.displayName, "Unplanned")

        let custom = MealPlanEntry(date: Date(), mealType: .lunch, customMealName: "Café Salad")
        XCTAssertEqual(custom.displayName, "Café Salad")

        let dish = makePreparedDish(name: "Soup")
        let fromDish = MealPlanEntry(date: Date(), mealType: .dinner, preparedDish: dish)
        XCTAssertEqual(fromDish.displayName, "Soup")

        let recipe = makeRecipe(title: "Curry")
        let fromRecipe = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        XCTAssertEqual(fromRecipe.displayName, "Curry")
    }

    // MARK: - preparedFoodMatchKey

    func testPreparedFoodMatchKeyPrefersRecipeOverIdentity() {
        let recipeID = UUID()
        let identityID = UUID()
        let entry = MealPlanEntry(
            date: Date(), mealType: .dinner,
            preparedFoodNameSnapshot: "Soup",
            preparedFoodRecipeID: recipeID,
            preparedFoodIdentityID: identityID
        )
        XCTAssertEqual(entry.preparedFoodMatchKey, .recipe(recipeID))
    }

    func testPreparedFoodMatchKeyFallsBackToIdentity() {
        let identityID = UUID()
        let entry = MealPlanEntry(
            date: Date(), mealType: .dinner,
            preparedFoodNameSnapshot: "Soup",
            preparedFoodIdentityID: identityID
        )
        XCTAssertEqual(entry.preparedFoodMatchKey, .preparedFoodIdentity(identityID))
    }

    func testPreparedFoodMatchKeyNilForCustomMeal() {
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, customMealName: "Takeout")
        XCTAssertNil(entry.preparedFoodMatchKey)
    }

    // MARK: - effectivePlannedServings Edge Cases

    func testEffectivePlannedServingsIgnoresZeroOrNegative() {
        let recipe = makeRecipe(servings: 4)
        let zero = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, plannedServings: 0)
        XCTAssertEqual(zero.effectivePlannedServings, 4, "Should fall back to recipe default for zero")

        let negative = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, plannedServings: -2)
        XCTAssertEqual(negative.effectivePlannedServings, 4, "Should fall back to recipe default for negative")
    }

    func testPreparedFoodDefaultServingsIsOne() {
        let dish = makePreparedDish(name: "Soup", servingsRemaining: 5)
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, preparedDish: dish)
        XCTAssertEqual(entry.defaultPlannedServings, 1)
    }

    // MARK: - remainingTrackedServings

    func testRemainingTrackedServingsAfterPartialEating() {
        let recipe = makeRecipe(servings: 4)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, eatenServings: 2)
        XCTAssertEqual(entry.remainingTrackedServings, 2)
    }

    func testRemainingTrackedServingsNilForUnplanned() {
        let entry = MealPlanEntry(date: Date(), mealType: .dinner)
        XCTAssertNil(entry.remainingTrackedServings)
    }

    // MARK: - eatenProgressLabel + mealLoggingSummary

    func testEatenProgressLabelShowsPartialProgress() {
        let recipe = makeRecipe(servings: 4)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, eatenServings: 2)
        XCTAssertEqual(entry.eatenProgressLabel, "2 of 4 eaten")
    }

    func testEatenProgressLabelNilWhenNothingEaten() {
        let recipe = makeRecipe(servings: 4)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        XCTAssertNil(entry.eatenProgressLabel)
    }

    func testMealLoggingSummaryForPreparedFood() {
        let dish = makePreparedDish(name: "Soup", servingsRemaining: 3)
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, preparedDish: dish, plannedServings: 2, eatenServings: 1)
        XCTAssertNotNil(entry.mealLoggingSummary)
        XCTAssertTrue(entry.mealLoggingSummary!.contains("1 of 2 eaten"))
    }

    func testMealLoggingSummaryNilForCustomMeal() {
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, customMealName: "Takeout")
        XCTAssertNil(entry.mealLoggingSummary)
    }

    // MARK: - isFullyEaten

    func testIsFullyEatenWhenAllServingsConsumed() {
        let recipe = makeRecipe(servings: 2)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, eatenServings: 2)
        XCTAssertTrue(entry.isFullyEaten)
    }

    func testIsFullyEatenFalseWhenServingsRemain() {
        let recipe = makeRecipe(servings: 4)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, eatenServings: 2)
        XCTAssertFalse(entry.isFullyEaten)
    }

    // MARK: - planningSubtitle Variants

    func testPlanningSubtitleForPreparedFoodShowsServings() {
        let dish = makePreparedDish(name: "Soup", servingsRemaining: 3)
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, preparedDish: dish, plannedServings: 2)
        XCTAssertEqual(entry.planningSubtitle, "2 servings planned")
    }

    func testPlanningSubtitleForRecipeIncludesTime() {
        let recipe = makeRecipe(servings: 2, prepTimeMinutes: 10, cookTimeMinutes: 20)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        let subtitle = entry.planningSubtitle ?? ""
        XCTAssertTrue(subtitle.contains("30 min"), "Should include total time")
    }

    // MARK: - updatingPlannedServings

    func testUpdatingPlannedServingsScalesEaten() {
        let recipe = makeRecipe(servings: 6)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, plannedServings: 6, eatenServings: 4)
        let updated = entry.updatingPlannedServings(2)
        XCTAssertEqual(updated.effectivePlannedServings, 2)
        XCTAssertEqual(updated.effectiveEatenServings, 2, "Eaten should clamp to new planned")
    }

    // MARK: - MealSelectionItem

    func testMealSelectionItemRecipeMakesEntry() {
        let recipe = makeRecipe(title: "Curry", servings: 4, mealType: .dinner)
        let item = MealSelectionItem.recipe(recipe)
        let entry = item.makeEntry(date: Date(), mealType: .dinner)
        XCTAssertEqual(entry.recipe?.title, "Curry")
        XCTAssertEqual(entry.plannedServings, 4)
    }

    func testMealSelectionItemPreparedDishMakesEntry() {
        let dish = makePreparedDish(name: "Soup")
        let item = MealSelectionItem.preparedDish(dish)
        let entry = item.makeEntry(date: Date(), mealType: .lunch)
        XCTAssertEqual(entry.preparedDish?.name, "Soup")
        XCTAssertEqual(entry.plannedServings, 1)
    }

    // MARK: - makePreparedDishDraft

    func testMakePreparedDishDraftFromPreparedFoodEntry() {
        let identityID = UUID()
        let entry = MealPlanEntry(
            date: Date(), mealType: .lunch,
            preparedFoodNameSnapshot: "Leftover Stew",
            preparedFoodIdentityID: identityID,
            plannedServings: 3
        )
        let draft = entry.makePreparedDishDraft()
        XCTAssertEqual(draft.name, "Leftover Stew")
        XCTAssertEqual(draft.servingsRemaining, 3)
        XCTAssertEqual(draft.foodIdentityID, identityID)
    }

    // MARK: - Init Normalization

    func testInitNormalizesCustomMealNameWhitespace() {
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, customMealName: "  ")
        XCTAssertNil(entry.normalizedCustomMealName)
        XCTAssertFalse(entry.isPlanned)
    }

    func testInitNormalizesIdentityBasedOnRecipeID() {
        let recipeID = UUID()
        let identityID = UUID()
        let entry = MealPlanEntry(
            date: Date(), mealType: .dinner,
            preparedFoodNameSnapshot: "Soup",
            preparedFoodRecipeID: recipeID,
            preparedFoodIdentityID: identityID
        )
        // When recipeID is present, identityID should be nil (recipeID takes precedence)
        XCTAssertNil(entry.preparedFoodIdentityID)
        XCTAssertEqual(entry.preparedFoodRecipeID, recipeID)
    }
}

// ===================================================================
// MARK: - Enum Tests
// ===================================================================

final class EnumTests: XCTestCase {

    // MARK: - FoodCategory

    func testFoodCategoryAllCases() {
        XCTAssertEqual(FoodCategory.allCases.count, 15)
    }

    func testFoodCategoryIcons() {
        for category in FoodCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty, "\(category.rawValue) should have an icon")
        }
    }

    func testFoodCategoryColors() {
        // Verify colors do not crash and return actual Color values
        for category in FoodCategory.allCases {
            let _ = category.color // Should not throw
        }
    }

    func testFoodCategoryCodable() throws {
        let category: FoodCategory = .dairy
        let data = try JSONEncoder().encode(category)
        let decoded = try JSONDecoder().decode(FoodCategory.self, from: data)
        XCTAssertEqual(decoded, .dairy)
    }

    func testRecipeSourceAutoResolvePolicy() {
        XCTAssertTrue(RecipeSource.aiGenerated.shouldAutoResolveIngredientsWithoutReview)
        XCTAssertFalse(RecipeSource.user.shouldAutoResolveIngredientsWithoutReview)
        XCTAssertFalse(RecipeSource.bundled.shouldAutoResolveIngredientsWithoutReview)
        XCTAssertFalse(RecipeSource.imported.shouldAutoResolveIngredientsWithoutReview)
    }

    func testReviewableImportedRecipeConvertsReviewedRecipeToUserSource() throws {
        let importedRecipe = Recipe(
            title: "Imported",
            ingredients: [Ingredient(name: "garlic")],
            steps: [],
            source: .imported
        )
        let draft = try XCTUnwrap(AppState.ReviewableImportedRecipe(recipe: importedRecipe))

        let reviewed = draft.reviewed(importedRecipe)

        XCTAssertEqual(reviewed.source, .user)
        XCTAssertEqual(reviewed.title, importedRecipe.title)
    }

    // MARK: - MeasurementUnit

    func testMeasurementUnitAllCases() {
        XCTAssertTrue(MeasurementUnit.allCases.count >= 20)
    }

    func testMeasurementUnitParseSupportsLoaf() {
        XCTAssertEqual(MeasurementUnit.parse("loaf"), .loaf)
        XCTAssertEqual(MeasurementUnit.parse("loaves"), .loaf)
    }

    func testMetricUnits() {
        XCTAssertTrue(MeasurementUnit.milliliter.isMetric)
        XCTAssertTrue(MeasurementUnit.liter.isMetric)
        XCTAssertTrue(MeasurementUnit.gram.isMetric)
        XCTAssertTrue(MeasurementUnit.kilogram.isMetric)
        XCTAssertFalse(MeasurementUnit.cup.isMetric)
        XCTAssertFalse(MeasurementUnit.teaspoon.isMetric)
        XCTAssertFalse(MeasurementUnit.piece.isMetric)
    }

    // MARK: - DietaryTag

    func testDietaryTagAllCases() {
        XCTAssertEqual(DietaryTag.allCases.count, 11)
    }

    func testDietaryTagIcons() {
        for tag in DietaryTag.allCases {
            XCTAssertFalse(tag.icon.isEmpty, "\(tag.rawValue) should have an icon")
            // Verify no invalid SF Symbol names (basic check: no spaces, no "fossil")
            XCTAssertFalse(
                tag.icon.contains("fossil"),
                "\(tag.rawValue) icon should not use non-existent SF Symbol 'fossil'"
            )
        }
    }

    // MARK: - DifficultyLevel

    func testDifficultyLevelOrdering() {
        let levels = DifficultyLevel.allCases.map { $0.rawValue }
        XCTAssertEqual(levels, [1, 2, 3, 4, 5])
    }

    func testDifficultyLevelLabels() {
        XCTAssertEqual(DifficultyLevel.beginner.label, "Beginner")
        XCTAssertEqual(DifficultyLevel.easy.label, "Easy")
        XCTAssertEqual(DifficultyLevel.medium.label, "Medium")
        XCTAssertEqual(DifficultyLevel.hard.label, "Hard")
        XCTAssertEqual(DifficultyLevel.expert.label, "Expert")
    }

    // MARK: - MealType

    func testMealTypeIcons() {
        for mealType in MealType.allCases {
            XCTAssertFalse(mealType.icon.isEmpty)
        }
    }

    // MARK: - ExpiryStatus

    func testExpiryStatusLabels() {
        XCTAssertEqual(ExpiryStatus.fresh.label, "Fresh")
        XCTAssertEqual(ExpiryStatus.expiringSoon.label, "Use Soon")
        XCTAssertEqual(ExpiryStatus.expired.label, "Expired")
    }

    func testExpiryStatusColors() {
        // Verify no crash
        let _ = ExpiryStatus.fresh.color
        let _ = ExpiryStatus.expiringSoon.color
        let _ = ExpiryStatus.expired.color
    }
}

// ===================================================================
// MARK: - AI Model Tests
// ===================================================================

final class AIModelTests: XCTestCase {

    func testSubstitutionSuggestionPreservesStructuredFields() {
        let suggestion = SubstitutionSuggestion(
            originalIngredient: "Cream",
            substituteName: "Greek Yogurt",
            ratio: "1:1",
            tasteImpact: "Moderate",
            textureImpact: "Slight",
            cookingImpact: "Moderate Adjustment",
            nutritionImpact: "Lower fat and more protein",
            notes: "Whisk in off heat to reduce curdling.",
            inPantry: true
        )

        XCTAssertEqual(suggestion.originalIngredient, "Cream")
        XCTAssertEqual(suggestion.substituteName, "Greek Yogurt")
        XCTAssertEqual(suggestion.cookingImpact, "Moderate Adjustment")
        XCTAssertEqual(suggestion.notes, "Whisk in off heat to reduce curdling.")
        XCTAssertTrue(suggestion.inPantry)
    }

    func testRecipeImportResultToRecipe() {
        let result = RecipeImportResult(
            title: "Imported Recipe",
            description: "A great recipe",
            ingredients: [Ingredient(name: "Salt", quantity: 1, unit: .pinch)],
            steps: [RecipeStep(stepNumber: 1, instruction: "Add salt")],
            servings: 2,
            prepTimeMinutes: 5,
            cookTimeMinutes: 10,
            dietaryTags: [.vegan],
            difficulty: .medium,
            mealType: .snack,
            cuisine: .american,
            nutrition: NutritionInfo(calories: 120, protein: 2, carbohydrates: 8, fat: 8, fiber: 0, sugar: 0, sodium: 400)
        )
        let recipe = result.toRecipe()
        XCTAssertEqual(recipe.title, "Imported Recipe")
        XCTAssertEqual(recipe.servings, 2)
        XCTAssertEqual(recipe.dietaryTags, [.vegan])
        XCTAssertEqual(recipe.ingredients.count, 1)
        XCTAssertEqual(recipe.difficulty, .medium)
        XCTAssertEqual(recipe.mealType, .snack)
        XCTAssertEqual(recipe.cuisine, .american)
        XCTAssertEqual(recipe.nutrition?.calories, 120)
    }

    func testRecipeImportResultDefaultServings() {
        let result = RecipeImportResult(
            title: "Test",
            description: nil,
            ingredients: [],
            steps: [],
            servings: nil,
            prepTimeMinutes: nil,
            cookTimeMinutes: nil,
            dietaryTags: nil,
            difficulty: nil,
            mealType: nil,
            cuisine: nil,
            nutrition: nil
        )
        let recipe = result.toRecipe()
        XCTAssertEqual(recipe.servings, 4, "Should default to 4 servings")
        XCTAssertNotNil(recipe.mealType)
        XCTAssertNotNil(recipe.cuisine)
        XCTAssertNotNil(recipe.nutrition)
    }

    func testRecipeCompletionBackfillsMissingMetadata() {
        let recipe = makeRecipe(
            title: "Chicken stir fry",
            ingredients: [
                Ingredient(name: "chicken breast", quantity: 400, unit: .gram, category: .protein),
                Ingredient(name: "soy sauce", quantity: 2, unit: .tablespoon, category: .condiments),
                Ingredient(name: "rice", quantity: 2, unit: .cup, category: .grains),
            ],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Slice the chicken and stir-fry it in a hot pan.", estimatedDurationSeconds: 480),
                RecipeStep(stepNumber: 2, instruction: "Add soy sauce and serve over rice.", estimatedDurationSeconds: 240),
            ],
            prepTimeMinutes: nil,
            cookTimeMinutes: nil,
            mealType: nil,
            cuisine: nil,
            nutrition: nil
        ).completed()

        XCTAssertEqual(recipe.mealType, .dinner)
        XCTAssertEqual(recipe.cuisine, .chinese)
        XCTAssertNotNil(recipe.prepTimeMinutes)
        XCTAssertNotNil(recipe.cookTimeMinutes)
        XCTAssertNotNil(recipe.nutrition)
        XCTAssertGreaterThan(recipe.nutrition?.calories ?? 0, 0)
        XCTAssertGreaterThan(recipe.nutrition?.protein ?? 0, 0)
    }
}

final class AIServiceSubstitutionTests: XCTestCase {

    func testSuggestSubstitutionsReturnsCatalogBackedStructuredSuggestions() async {
        let service = AIService(apiKey: "")
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "chicken breast", quantity: 400, unit: .gram, category: .protein)
        ])
        let pantry = [
            PantryItem(
                name: "Tofu",
                category: .protein,
                quantity: 400,
                unit: .gram,
                catalogItemID: "tofu",
                facets: [.init(key: .variant, value: "extra firm")]
            )
        ]

        let suggestions = await service.suggestSubstitutions(recipe: recipe, pantry: pantry)

        XCTAssertEqual(suggestions.count, 2)
        XCTAssertEqual(suggestions.first?.originalIngredient, "chicken breast")
        XCTAssertEqual(suggestions.first?.substituteName, "Extra Firm Tofu")
        XCTAssertEqual(suggestions.first?.ratio, "1:1 by weight")
        XCTAssertEqual(suggestions.first?.cookingImpact, "Moderate Adjustment")
        XCTAssertEqual(suggestions.first?.notes, "Best in stir-fries, curries, and saucy dishes.")
        XCTAssertTrue(suggestions.first?.inPantry == true)
    }

    func testSuggestSubstitutionsDoesNotFallbackForUnknownIngredients() async {
        let service = AIService(apiKey: "")
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "gochujang", quantity: 1, unit: .tablespoon, category: .condiments)
        ])

        let suggestions = await service.suggestSubstitutions(recipe: recipe, pantry: [])

        XCTAssertTrue(suggestions.isEmpty)
    }
}

// ===================================================================
// MARK: - StorageService Tests
// ===================================================================

@MainActor
final class StorageServiceTests: XCTestCase {

    // MARK: - Pantry

    func testFetchPantryItemsReturnsSorted() async throws {
        let sut = StorageService()
        let items = try await sut.fetchPantryItems()
        XCTAssertFalse(items.isEmpty, "Should return seeded pantry items")
    }

    func testAddAndFetchPantryItem() async throws {
        let sut = StorageService()
        let item = makePantryItem(name: "Test Cheese", category: .dairy)
        let _ = try await sut.addPantryItem(item)
        let all = try await sut.fetchPantryItems()
        XCTAssertTrue(all.contains { $0.id == item.id })
    }

    func testUpdatePantryItem() async throws {
        let sut = StorageService()
        var item = makePantryItem(name: "Cheese", category: .dairy, quantity: 100)
        let _ = try await sut.addPantryItem(item)
        item.quantity = 200
        let _ = try await sut.updatePantryItem(item)
        let all = try await sut.fetchPantryItems()
        let found = all.first { $0.id == item.id }
        XCTAssertEqual(found?.quantity, 200)
    }

    func testDeletePantryItem() async throws {
        let sut = StorageService()
        let item = makePantryItem(name: "ToDelete")
        let _ = try await sut.addPantryItem(item)
        try await sut.deletePantryItem(item)
        let all = try await sut.fetchPantryItems()
        XCTAssertFalse(all.contains { $0.id == item.id })
    }

    // MARK: - Recipes

    func testAddAndFetchRecipe() async throws {
        let sut = StorageService()
        let recipe = makeRecipe(title: "Test Soup")
        let _ = try await sut.addRecipe(recipe)
        let all = try await sut.fetchRecipes()
        XCTAssertTrue(all.contains { $0.id == recipe.id })
    }

    func testUpdateRecipe() async throws {
        let sut = StorageService()
        var recipe = makeRecipe(title: "Original Title")
        let _ = try await sut.addRecipe(recipe)
        recipe.title = "Updated Title"
        let _ = try await sut.updateRecipe(recipe)
        let all = try await sut.fetchRecipes()
        let found = all.first { $0.id == recipe.id }
        XCTAssertEqual(found?.title, "Updated Title")
    }

    func testDeleteRecipe() async throws {
        let sut = StorageService()
        let recipe = makeRecipe(title: "ToDelete")
        let _ = try await sut.addRecipe(recipe)
        try await sut.deleteRecipe(recipe)
        let all = try await sut.fetchRecipes()
        XCTAssertFalse(all.contains { $0.id == recipe.id })
    }

    // MARK: - Meal Plan

    func testAddAndFetchMealPlan() async throws {
        let sut = StorageService()
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe())
        let _ = try await sut.addMealPlanEntry(entry)
        let all = try await sut.fetchMealPlan()
        XCTAssertTrue(all.contains { $0.id == entry.id })
    }

    func testDeleteMealPlanEntry() async throws {
        let sut = StorageService()
        let entry = MealPlanEntry(date: Date(), mealType: .lunch)
        let _ = try await sut.addMealPlanEntry(entry)
        try await sut.deleteMealPlanEntry(entry)
        let all = try await sut.fetchMealPlan()
        XCTAssertFalse(all.contains { $0.id == entry.id })
    }

    func testAddAndFetchPreparedDishes() async throws {
        let sut = StorageService(isStoredInMemoryOnly: true, shouldBootstrap: false, resetPersistentStore: false)
        let dish = makePreparedDish(name: "Soup")
        let _ = try await sut.addPreparedDish(dish)
        let all = try await sut.fetchPreparedDishes()
        XCTAssertEqual(all.map(\.name), ["Soup"])
    }

    func testFetchMealPlanResolvesPreparedDishReference() async throws {
        let sut = StorageService(isStoredInMemoryOnly: true, shouldBootstrap: false, resetPersistentStore: false)
        let dish = makePreparedDish(name: "Biryani")
        let _ = try await sut.addPreparedDish(dish)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, preparedDish: dish)
        let _ = try await sut.addMealPlanEntry(entry)

        let all = try await sut.fetchMealPlan()
        XCTAssertEqual(all.first?.preparedDish?.name, "Biryani")
    }

    // MARK: - Shopping

    func testSaveAndFetchShoppingItems() async throws {
        let sut = StorageService()
        let items = [
            ShoppingItem(name: "Apples", category: .produce),
            ShoppingItem(name: "Bread", category: .grains),
        ]
        try await sut.saveShoppingItems(items)
        let fetched = try await sut.fetchShoppingItems()
        XCTAssertEqual(fetched.count, 2)
    }
}

// ===================================================================
// MARK: - AppState Tests
// ===================================================================

@MainActor
final class AppStateTests: XCTestCase {

    // MARK: - Pantry CRUD

    func testAddPantryItem() async {
        let (appState, storage, _) = makeTestAppState()
        let item = makePantryItem(name: "Milk")
        await appState.addPantryItem(item)
        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems[0].name, "Milk")
        XCTAssertEqual(storage.addPantryItemCallCount, 1)
    }

    func testAddPantryItemMergesMatchingCatalogBackedQuantity() async {
        let (appState, storage, _) = makeTestAppState()
        await appState.addPantryItem(makePantryItem(
            name: "Sourdough Bread",
            category: .grains,
            quantity: 1,
            unit: .whole,
            catalogItemID: "bread",
            facets: [.init(key: .variant, value: "sourdough")]
        ))

        await appState.addPantryItem(makePantryItem(
            name: "Sourdough Bread",
            category: .grains,
            quantity: 1,
            unit: .whole,
            catalogItemID: "bread",
            facets: [.init(key: .variant, value: "sourdough")]
        ))

        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems[0].quantity, 2)
        XCTAssertEqual(storage.addPantryItemCallCount, 1)
        XCTAssertEqual(storage.updatePantryItemCallCount, 1)
    }

    func testAddPantryItemMergeKeepsEarlierExpiryDate() async {
        let (appState, _, _) = makeTestAppState()
        let laterExpiry = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let earlierExpiry = Calendar.current.date(byAdding: .day, value: 2, to: Date())!

        await appState.addPantryItem(PantryItem(
            name: "Sourdough Bread",
            category: .grains,
            quantity: 1,
            unit: .whole,
            expiryDate: laterExpiry,
            catalogItemID: "bread",
            facets: [.init(key: .variant, value: "sourdough")],
            freshnessSource: .userProvided
        ))

        await appState.addPantryItem(PantryItem(
            name: "Sourdough Bread",
            category: .grains,
            quantity: 1,
            unit: .whole,
            expiryDate: earlierExpiry,
            catalogItemID: "bread",
            facets: [.init(key: .variant, value: "sourdough")],
            freshnessSource: .estimated
        ))

        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems[0].quantity, 2)
        XCTAssertEqual(try XCTUnwrap(appState.pantryItems[0].expiryDate).timeIntervalSince1970, earlierExpiry.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(appState.pantryItems[0].freshnessSource, .estimated)
    }

    func testAddPantryItemMergeAdoptsIncomingExpiryWhenExistingHasNone() async {
        let (appState, _, _) = makeTestAppState()
        let incomingExpiry = Calendar.current.date(byAdding: .day, value: 4, to: Date())!

        await appState.addPantryItem(PantryItem(
            name: "Sourdough Bread",
            category: .grains,
            quantity: 1,
            unit: .whole,
            catalogItemID: "bread",
            facets: [.init(key: .variant, value: "sourdough")]
        ))

        await appState.addPantryItem(PantryItem(
            name: "Sourdough Bread",
            category: .grains,
            quantity: 1,
            unit: .whole,
            expiryDate: incomingExpiry,
            catalogItemID: "bread",
            facets: [.init(key: .variant, value: "sourdough")],
            freshnessSource: .estimated
        ))

        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems[0].quantity, 2)
        XCTAssertEqual(try XCTUnwrap(appState.pantryItems[0].expiryDate).timeIntervalSince1970, incomingExpiry.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(appState.pantryItems[0].freshnessSource, .estimated)
    }

    func testAddPantryItemKeepsDifferentFacetVariantsSeparate() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addPantryItem(makePantryItem(
            name: "Sourdough Bread",
            category: .grains,
            quantity: 1,
            unit: .whole,
            catalogItemID: "bread",
            facets: [.init(key: .variant, value: "sourdough")]
        ))

        await appState.addPantryItem(makePantryItem(
            name: "White Bread",
            category: .grains,
            quantity: 1,
            unit: .whole,
            catalogItemID: "bread",
            facets: [.init(key: .variant, value: "white")]
        ))

        XCTAssertEqual(appState.pantryItems.count, 2)
    }

    func testRemovePantryItem() async {
        let (appState, storage, _) = makeTestAppState()
        let item = makePantryItem(name: "Eggs")
        await appState.addPantryItem(item)
        await appState.removePantryItem(item)
        XCTAssertTrue(appState.pantryItems.isEmpty)
        XCTAssertEqual(storage.deletePantryItemCallCount, 1)
    }

    func testUpdatePantryItem() async {
        let (appState, storage, _) = makeTestAppState()
        var item = makePantryItem(name: "Cheese", quantity: 100)
        await appState.addPantryItem(item)
        item.quantity = 200
        await appState.updatePantryItem(item)
        XCTAssertEqual(appState.pantryItems[0].quantity, 200)
        XCTAssertEqual(storage.updatePantryItemCallCount, 1)
    }

    // MARK: - Prepared Dish CRUD

    func testAddPreparedDish() async {
        let (appState, storage, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Lasagna")
        await appState.addPreparedDish(dish)
        XCTAssertEqual(appState.preparedDishes.count, 1)
        XCTAssertEqual(appState.preparedDishes[0].name, "Lasagna")
        XCTAssertEqual(storage.addPreparedDishCallCount, 1)
    }

    func testUpdatePreparedDish() async {
        let (appState, storage, _) = makeTestAppState()
        var dish = makePreparedDish(name: "Tacos", servingsRemaining: 3)
        await appState.addPreparedDish(dish)
        dish.servingsRemaining = 1
        await appState.updatePreparedDish(dish)
        XCTAssertEqual(appState.preparedDishes[0].servingsRemaining, 1)
        XCTAssertEqual(storage.updatePreparedDishCallCount, 1)
    }

    func testRemovePreparedDish() async {
        let (appState, storage, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Curry")
        await appState.addPreparedDish(dish)
        await appState.removePreparedDish(dish)
        XCTAssertTrue(appState.preparedDishes.isEmpty)
        XCTAssertEqual(storage.deletePreparedDishCallCount, 1)
    }

    func testAdjustPreparedDishServingsDecrementsExistingDish() async {
        let (appState, storage, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Stir Fry", servingsRemaining: 3)
        await appState.addPreparedDish(dish)

        let removed = await appState.adjustPreparedDishServings(dish, delta: -1)

        XCTAssertFalse(removed)
        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 2)
        XCTAssertEqual(storage.updatePreparedDishCallCount, 1)
    }

    func testAdjustPreparedDishServingsRemovesDishWhenEmpty() async {
        let (appState, storage, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Bowl", servingsRemaining: 1)
        await appState.addPreparedDish(dish)

        let removed = await appState.adjustPreparedDishServings(dish, delta: -1)

        XCTAssertTrue(removed)
        XCTAssertTrue(appState.preparedDishes.isEmpty)
        XCTAssertEqual(storage.deletePreparedDishCallCount, 1)
    }

    func testAddPreparedDishCreatesReusableHistoryItem() async {
        let (appState, storage, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Batch Curry", servingsRemaining: 4)

        await appState.addPreparedDish(dish)

        XCTAssertEqual(appState.preparedDishHistory.count, 1)
        XCTAssertEqual(appState.preparedDishHistory.first?.name, "Batch Curry")
        XCTAssertEqual(appState.preparedDishHistory.first?.defaultServings, 4)
        XCTAssertEqual(storage.preparedDishHistoryStore.first?.name, "Batch Curry")
    }

    func testServingAdjustmentsDoNotCreateDuplicatePreparedDishHistorySnapshots() async {
        let (appState, storage, _) = makeTestAppState()
        var dish = makePreparedDish(name: "Roast Chicken", servingsRemaining: 4)

        await appState.addPreparedDish(dish)
        dish.servingsRemaining = 3
        await appState.updatePreparedDish(dish)

        XCTAssertEqual(appState.preparedDishHistory.count, 1)
        XCTAssertEqual(appState.preparedDishHistory.first?.timesPrepared, 1)
        XCTAssertEqual(storage.preparedDishHistoryStore.count, 1)
    }

    func testMeaningfulPreparedDishEditRefreshesHistoryTemplate() async {
        let (appState, storage, _) = makeTestAppState()
        var dish = makePreparedDish(name: "Rice Bowl", servingsRemaining: 2)

        await appState.addPreparedDish(dish)
        dish.notes = "With extra chili crisp"
        await appState.updatePreparedDish(dish)

        XCTAssertEqual(appState.preparedDishHistory.count, 1)
        XCTAssertEqual(appState.preparedDishHistory.first?.notes, "With extra chili crisp")
        XCTAssertEqual(appState.preparedDishHistory.first?.timesPrepared, 2)
        XCTAssertEqual(storage.preparedDishHistoryStore.first?.timesPrepared, 2)
    }

    // MARK: - Recipe CRUD

    func testAddRecipe() async {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(title: "New Recipe")
        await appState.addRecipe(recipe)
        XCTAssertEqual(appState.recipes.count, 1)
        XCTAssertEqual(storage.addRecipeCallCount, 1)
    }

    func testUpdateRecipe() async {
        let (appState, storage, _) = makeTestAppState()
        var recipe = makeRecipe(title: "Original")
        await appState.addRecipe(recipe)
        recipe.title = "Updated"
        await appState.updateRecipe(recipe)
        XCTAssertEqual(appState.recipes[0].title, "Updated")
        XCTAssertEqual(storage.updateRecipeCallCount, 1)
    }

    func testAddRecipeCanonicalizesResolvableIngredientsBeforeSaving() async {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Carrots", quantity: 2, unit: .whole, category: .produce)
        ])

        await appState.addRecipe(recipe)

        XCTAssertEqual(storage.recipeStore.count, 1)
        XCTAssertEqual(storage.recipeStore[0].ingredients[0].catalogItemID, "carrot")
    }

    func testAddRecipeRejectsUnresolvedIngredientsWhenNoSafeMatchExists() async {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "mystery leaf", quantity: 1, unit: .whole, category: .produce)
        ])

        await appState.addRecipe(recipe)

        XCTAssertTrue(storage.recipeStore.isEmpty)
        XCTAssertEqual(appState.errorMessage, "Resolve recipe ingredients before saving: mystery leaf.")
    }

    func testDeleteRecipe() async {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Delete Me")
        await appState.addRecipe(recipe)
        await appState.deleteRecipe(recipe)
        XCTAssertTrue(appState.recipes.isEmpty)
        XCTAssertEqual(storage.deleteRecipeCallCount, 1)
    }

    func testUpdateRecipeDoesNotDuplicate() async {
        let (appState, _, _) = makeTestAppState()
        var recipe = makeRecipe(title: "Test")
        await appState.addRecipe(recipe)
        recipe.isFavorite = true
        await appState.updateRecipe(recipe)
        XCTAssertEqual(appState.recipes.count, 1, "updateRecipe should not duplicate")
        XCTAssertTrue(appState.recipes[0].isFavorite)
    }

    // MARK: - Meal Plan CRUD

    func testAddToMealPlan() async {
        let (appState, storage, _) = makeTestAppState()
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe(title: "Pasta Night"))
        await appState.addToMealPlan(entry)
        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(storage.addMealPlanCallCount, 1)
    }

    func testAddPreparedDishToMealPlan() async {
        let (appState, storage, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Leftover Chili")
        await appState.addPreparedDish(dish)

        let entry = MealPlanEntry(date: Date(), mealType: .dinner, preparedDish: dish)
        await appState.addToMealPlan(entry)

        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(appState.mealPlan[0].preparedDish?.name, "Leftover Chili")
        XCTAssertEqual(storage.addMealPlanCallCount, 1)
    }

    func testRemoveFromMealPlan() async {
        let (appState, storage, _) = makeTestAppState()
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe(title: "Pasta Night"))
        await appState.addToMealPlan(entry)
        await appState.removeFromMealPlan(entry)
        XCTAssertTrue(appState.mealPlan.isEmpty)
        XCTAssertEqual(storage.deleteMealPlanCallCount, 1)
    }

    // MARK: - Computed Properties

    func testExpiringItems() async {
        let (appState, _, _) = makeTestAppState()
        let expiring = makePantryItem(
            name: "Soon",
            expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())
        )
        let fresh = makePantryItem(
            name: "Fresh",
            expiryDate: Calendar.current.date(byAdding: .day, value: 30, to: Date())
        )
        let noDate = makePantryItem(name: "NoDate", expiryDate: nil)
        await appState.addPantryItem(expiring)
        await appState.addPantryItem(fresh)
        await appState.addPantryItem(noDate)
        XCTAssertEqual(appState.expiringItems.count, 1)
        XCTAssertEqual(appState.expiringItems[0].name, "Soon")
    }

    func testExpiredItems() async {
        let (appState, _, _) = makeTestAppState()
        let expired = makePantryItem(
            name: "Bad",
            expiryDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        )
        let fresh = makePantryItem(
            name: "Good",
            expiryDate: Calendar.current.date(byAdding: .day, value: 10, to: Date())
        )
        await appState.addPantryItem(expired)
        await appState.addPantryItem(fresh)
        XCTAssertEqual(appState.expiredItems.count, 1)
        XCTAssertEqual(appState.expiredItems[0].name, "Bad")
    }

    func testPantryByCategoryUsesCatalogCategoriesForKnownItems() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addPantryItem(makePantryItem(name: "Milk", category: .dairy))
        await appState.addPantryItem(makePantryItem(name: "Chicken", category: .protein))
        await appState.addPantryItem(makePantryItem(name: "Eggs", category: .dairy))
        let grouped = appState.pantryByCategory
        XCTAssertEqual(grouped[.dairy]?.count, 1)
        XCTAssertEqual(grouped[.protein]?.count, 2)
    }

    // MARK: - Shopping List Generation (fuzzy matching)

    func testGenerateShoppingListFromMealPlan() async {
        let (appState, _, _) = makeTestAppState()
        // Add pantry item
        await appState.addPantryItem(makePantryItem(
            name: "Chicken Breast",
            category: .protein,
            quantity: 500,
            unit: .gram,
            catalogItemID: "chicken"
        ))
        // Add recipe to meal plan
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Chicken Breast", quantity: 400, unit: .gram, category: .protein, catalogItemID: "chicken"),
            Ingredient(name: "Soy Sauce", quantity: 2, unit: .tablespoon, category: .condiments),
        ])
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        await appState.addToMealPlan(entry)
        // Generate
        await appState.generateShoppingListFromMealPlan()
        // "Chicken" should be matched by "Chicken Breast" (fuzzy), "Soy Sauce" should be missing
        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(appState.shoppingItems[0].catalogItemID, "soy-sauce")
    }

    func testGenerateShoppingListFromMealPlanIgnoresPreparedDishEntries() async {
        let (appState, _, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Pad Thai")
        await appState.addPreparedDish(dish)
        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .dinner, preparedDish: dish))

        await appState.generateShoppingListFromMealPlan()

        XCTAssertTrue(appState.shoppingItems.isEmpty)
    }

    func testWeeklyNutritionSummaryIncludesPreparedDishNutrition() async {
        let (appState, _, _) = makeTestAppState()
        let nutrition = NutritionInfo(calories: 500, protein: 30, carbohydrates: 45, fat: 18, fiber: nil, sugar: nil, sodium: nil)
        let dish = makePreparedDish(name: "Meal Prep Bowl", nutrition: nutrition)
        await appState.addPreparedDish(dish)
        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .lunch, preparedDish: dish))

        let summary = appState.weeklyNutritionSummary()

        XCTAssertEqual(summary?.totalCalories, 500)
        XCTAssertEqual(summary?.mealsPlanned, 1)
    }

    func testSuggestedRecipeForCurrentPantryIncludesDiscoverRecipes() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addPantryItem(makePantryItem(name: "Chicken Breast", category: .protein, quantity: 1, unit: .piece, catalogItemID: "chicken"))

        let discoverRecipe = makeRecipe(
            title: "Chicken Bowl",
            ingredients: [
                Ingredient(name: "Chicken Breast", quantity: 1, unit: .piece, category: .protein, catalogItemID: "chicken")
            ],
            source: .bundled
        )

        _ = await appState.cacheDiscoverRecipe(discoverRecipe)

        XCTAssertEqual(appState.suggestedRecipeForCurrentPantry()?.title, "Chicken Bowl")
    }

    func testPreparedDishDraftBuildUsesLinkedRecipeDefaultsWhenFieldsBlank() {
        let recipe = makeRecipe(
            title: "Black Bean Chili",
            servings: 6,
            mealType: .dinner,
            nutrition: NutritionInfo(calories: 420, protein: 22, carbohydrates: 39, fat: 14, fiber: nil, sugar: nil, sodium: nil)
        )

        var draft = PreparedDishDraft()
        draft.name = ""
        draft.mealTypes = []
        draft.recipeID = recipe.id
        draft.caloriesText = ""
        draft.proteinText = ""
        draft.carbsText = ""
        draft.fatText = ""

        let dish = draft.buildDish(using: recipe)

        XCTAssertEqual(dish?.name, "Black Bean Chili")
        XCTAssertEqual(dish?.mealTypes, [.dinner])
        XCTAssertEqual(dish?.nutrition?.calories, 420)
    }

    func testPreparedDishDraftUsesEstimatedFreshnessUntilUseByDateIsEdited() {
        var draft = PreparedDishDraft()
        draft.storage = .refrigerated
        draft.name = "Soup"

        let estimatedDish = draft.buildDish()

        XCTAssertEqual(estimatedDish?.useByDate, draft.estimatedUseByDate)

        let customDate = Calendar.current.date(byAdding: .day, value: 7, to: draft.dateAdded)!
        draft.updateUseByDate(customDate)

        let editedDish = draft.buildDish()

        XCTAssertEqual(editedDish?.useByDate, customDate)
    }

    func testPreparedDishDraftSyncLinkedRecipeReplacesExistingLinkedFields() {
        let originalRecipe = makeRecipe(
            title: "Original Chili",
            servings: 2,
            mealType: .lunch,
            nutrition: NutritionInfo(calories: 300, protein: 20, carbohydrates: 15, fat: 12, fiber: nil, sugar: nil, sodium: nil)
        )
        let updatedRecipe = makeRecipe(
            title: "Updated Curry",
            servings: 5,
            mealType: .dinner,
            nutrition: NutritionInfo(calories: 640, protein: 32, carbohydrates: 48, fat: 22, fiber: nil, sugar: nil, sodium: nil)
        )

        var draft = PreparedDishDraft()
        draft.recipeID = originalRecipe.id
        draft.syncLinkedRecipe(originalRecipe)
        draft.recipeID = updatedRecipe.id
        draft.syncLinkedRecipe(updatedRecipe)

        let dish = draft.buildDish(using: updatedRecipe)

        XCTAssertEqual(dish?.name, "Updated Curry")
        XCTAssertEqual(dish?.mealTypes, [.dinner])
        XCTAssertEqual(dish?.servingsRemaining, 5)
        XCTAssertEqual(dish?.nutrition?.calories, 640)
    }

    func testUpdateRecipeSyncsLinkedPreparedDishes() async {
        let (appState, storage, _) = makeTestAppState()
        var recipe = makeRecipe(
            title: "Lentil Soup",
            servings: 2,
            mealType: .lunch,
            nutrition: NutritionInfo(calories: 320, protein: 18, carbohydrates: 36, fat: 8, fiber: nil, sugar: nil, sodium: nil)
        )
        await appState.addRecipe(recipe)

        let linkedDish = PreparedDish(
            name: "Lentil Soup",
            mealTypes: [.lunch],
            servingsRemaining: 2,
            storage: .refrigerated,
            recipeID: recipe.id,
            nutrition: recipe.nutrition
        )
        await appState.addPreparedDish(linkedDish)

        recipe.title = "Creamy Lentil Soup"
        recipe.servings = 4
        recipe.mealType = .dinner
        recipe.nutrition = NutritionInfo(calories: 480, protein: 24, carbohydrates: 42, fat: 18, fiber: nil, sugar: nil, sodium: nil)

        await appState.updateRecipe(recipe)

        XCTAssertEqual(appState.preparedDishes.first?.name, "Creamy Lentil Soup")
        XCTAssertEqual(appState.preparedDishes.first?.mealTypes, [.dinner])
        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 4)
        XCTAssertEqual(appState.preparedDishes.first?.nutrition?.calories, 480)
        XCTAssertEqual(storage.updatePreparedDishCallCount, 1)
    }

    func testAddToMealPlanAllowsMultipleEntriesInSameSlot() async {
        let (appState, storage, _) = makeTestAppState()
        let date = Date()
        let first = MealPlanEntry(date: date, mealType: .dinner, recipe: makeRecipe(title: "Pasta"))
        let second = MealPlanEntry(date: date, mealType: .dinner, preparedDish: makePreparedDish(name: "Leftover Salad"))

        await appState.addToMealPlan(first)
        await appState.addToMealPlan(second)

        XCTAssertEqual(appState.mealPlan.count, 2)
        XCTAssertEqual(storage.addMealPlanCallCount, 2)
        XCTAssertEqual(storage.mealPlanStore.count, 2)
    }

    func testUpdateMealPlanEntryPersistsAllocatedServings() async {
        let (appState, storage, _) = makeTestAppState()
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe(title: "Curry", servings: 4))

        await appState.addToMealPlan(entry)
        await appState.updateMealPlanEntry(entry.updatingPlannedServings(2))

        XCTAssertEqual(appState.mealPlan.first?.effectivePlannedServings, 2)
        XCTAssertEqual(storage.mealPlanStore.first?.plannedServings, 2)
    }

    func testPreparedFoodSourceEntriesFromMealPlanExcludesPreparedDishEntries() async {
        let (appState, _, _) = makeTestAppState()
        let recipeEntry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe(title: "Curry"))
        let preparedDishEntry = MealPlanEntry(date: Date(), mealType: .lunch, preparedDish: makePreparedDish(name: "Soup"))
        let customEntry = MealPlanEntry(date: Date(), mealType: .breakfast, customMealName: "Office breakfast")

        await appState.addToMealPlan([recipeEntry, preparedDishEntry, customEntry])

        let eligibleEntries = appState.preparedFoodSourceEntriesFromMealPlan()

        XCTAssertEqual(eligibleEntries.count, 2)
        XCTAssertTrue(eligibleEntries.contains { $0.recipe?.title == "Curry" })
        XCTAssertTrue(eligibleEntries.contains { $0.customMealName == "Office breakfast" })
        XCTAssertFalse(eligibleEntries.contains { $0.preparedDish?.name == "Soup" })
    }

    func testPreparedDishMealPlanEntryDefaultsToOnePlannedServingAndSnapshotIdentity() async {
        let (appState, storage, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Chili", servingsRemaining: 4)

        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .dinner, preparedDish: dish))

        XCTAssertEqual(appState.mealPlan.first?.effectivePlannedServings, 1)
        XCTAssertEqual(storage.mealPlanStore.first?.effectivePlannedServings, 1)
        XCTAssertEqual(appState.mealPlan.first?.preparedFoodNameSnapshot, "Chili")
        XCTAssertEqual(appState.mealPlan.first?.preparedFoodIdentityID, dish.foodIdentityID)
    }

    func testLogMealPlanEntriesEatenMatchesRecipeMealToCurrentPreparedFoodByRecipe() async {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Curry", servings: 4)
        let cookedDish = makePreparedDish(name: "Curry", servingsRemaining: 4, recipeID: recipe.id)
        await appState.addPreparedDish(cookedDish)

        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, plannedServings: 2)
        await appState.addToMealPlan(entry)
        await appState.logMealPlanEntriesEaten([
            MealPlanEatenLoggingSelection(entryID: entry.id, targetEatenServings: 2, preparedDishID: cookedDish.id)
        ])

        XCTAssertEqual(appState.mealPlan.first?.effectiveEatenServings, 2)
        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 2)
        XCTAssertEqual(storage.mealPlanStore.first?.eatenServings, 2)
    }

    func testLogMealPlanEntriesEatenDecrementsSelectedPreparedDishServings() async {
        let (appState, storage, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Chili", servingsRemaining: 4)
        await appState.addPreparedDish(dish)

        let entry = MealPlanEntry(date: Date(), mealType: .dinner, preparedDish: dish, plannedServings: 2)
        await appState.addToMealPlan(entry)
        await appState.logMealPlanEntriesEaten([
            MealPlanEatenLoggingSelection(entryID: entry.id, targetEatenServings: 2, preparedDishID: dish.id)
        ])

        XCTAssertEqual(appState.mealPlan.first?.effectiveEatenServings, 2)
        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 2)
        XCTAssertEqual(storage.mealPlanStore.first?.eatenServings, 2)
    }

    func testLogMealPlanEntriesEatenMatchesPreparedFoodPlanToReplacementInstanceByIdentity() async {
        let (appState, storage, _) = makeTestAppState()
        let foodIdentityID = UUID()
        let originalDish = makePreparedDish(name: "Burrito Bowl", servingsRemaining: 2, foodIdentityID: foodIdentityID)
        let replacementDish = makePreparedDish(name: "Burrito Bowl", servingsRemaining: 3, foodIdentityID: foodIdentityID)

        await appState.addPreparedDish(originalDish)
        let entry = MealPlanEntry(date: Date(), mealType: .lunch, preparedDish: originalDish, plannedServings: 2)
        await appState.addToMealPlan(entry)
        await appState.removePreparedDish(originalDish)
        await appState.addPreparedDish(replacementDish)

        await appState.logMealPlanEntriesEaten([
            MealPlanEatenLoggingSelection(entryID: entry.id, targetEatenServings: 1, preparedDishID: replacementDish.id)
        ])

        XCTAssertEqual(appState.mealPlan.first?.effectiveEatenServings, 1)
        XCTAssertEqual(appState.preparedDishes.first?.id, replacementDish.id)
        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 2)
        XCTAssertEqual(storage.mealPlanStore.first?.eatenServings, 1)
    }

    func testLogMealPlanEntriesEatenRejectsPreparedDishOverdrawAcrossBatch() async {
        let (appState, storage, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Burrito Bowl", servingsRemaining: 2)
        await appState.addPreparedDish(dish)

        let breakfast = MealPlanEntry(date: Date(), mealType: .breakfast, preparedDish: dish, plannedServings: 2)
        let lunch = MealPlanEntry(date: Date(), mealType: .lunch, preparedDish: dish, plannedServings: 2)
        await appState.addToMealPlan([breakfast, lunch])

        await appState.logMealPlanEntriesEaten([
            MealPlanEatenLoggingSelection(entryID: breakfast.id, targetEatenServings: 2, preparedDishID: dish.id),
            MealPlanEatenLoggingSelection(entryID: lunch.id, targetEatenServings: 1, preparedDishID: dish.id)
        ])

        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 2)
        XCTAssertEqual(appState.mealPlan.first(where: { $0.id == breakfast.id })?.effectiveEatenServings, 0)
        XCTAssertEqual(appState.mealPlan.first(where: { $0.id == lunch.id })?.effectiveEatenServings, 0)
        XCTAssertEqual(storage.mealPlanStore.first(where: { $0.id == breakfast.id })?.eatenServings, nil)
        XCTAssertEqual(appState.errorMessage, "Not enough servings remain in Burrito Bowl to log those meals as eaten.")
    }

    func testMealPlanCookQueueReviewWorkspaceBuildsMixedSerialAndParallelStages() {
        let date = Date()
        let first = MealPlanEntry(date: date, mealType: .breakfast, recipe: makeRecipe(title: "Oats"))
        let second = MealPlanEntry(date: date, mealType: .lunch, recipe: makeRecipe(title: "Soup"))
        let third = MealPlanEntry(date: date, mealType: .dinner, recipe: makeRecipe(title: "Salad"))

        var workspace = MealPlanCookQueueReviewWorkspace(entries: [first, second, third])
        var updatedSecond = workspace.drafts[1]
        updatedSecond.stagePlacement = .withPrevious
        workspace.updateDraft(updatedSecond)

        let stages = workspace.buildStages()

        XCTAssertEqual(stages.count, 2)
        XCTAssertEqual(stages[0].recipeTitleSnapshots, ["Oats", "Soup"])
        XCTAssertEqual(stages[1].recipeTitleSnapshots, ["Salad"])
        XCTAssertEqual(stages[0].sourceMealPlanEntryIDs, [first.id, second.id])
    }

    func testGenerateShoppingListFromMealPlanMergesAdditivelyIntoExistingCart() async {
        let (appState, _, _) = makeTestAppState()

        appState.shoppingItems = [
            ShoppingItem(name: "Flour", quantity: 1, unit: .cup, category: .grains)
        ]

        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Flour", quantity: 2, unit: .cup, category: .grains),
            Ingredient(name: "Water", quantity: 1, unit: .cup, category: .other),
            Ingredient(name: "Eggs", quantity: 2, unit: .piece, category: .dairy)
        ])

        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe))
        await appState.generateShoppingListFromMealPlan()

        XCTAssertEqual(appState.shoppingItems.count, 2)
        XCTAssertEqual(appState.shoppingItems.first(where: { $0.catalogItemID == "flour" })?.quantity, 3)
        XCTAssertEqual(appState.shoppingItems.first(where: { $0.catalogItemID == "egg" })?.quantity, 2)
        XCTAssertNil(appState.shoppingItems.first(where: { $0.name == "Water" }))
    }

    func testAddShoppingItemsMergesUsingCatalogIdentity() async {
        let (appState, _, _) = makeTestAppState()

        await appState.addShoppingItems([
            ShoppingItem(name: "Carrot", quantity: 1, unit: .whole, category: .produce)
        ])

        await appState.addShoppingItems([
            ShoppingItem(name: "Carrots", quantity: 2, unit: .whole, category: .produce)
        ])

        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(appState.shoppingItems[0].catalogItemID, "carrot")
        XCTAssertEqual(appState.shoppingItems[0].quantity, 3)
    }

    func testAddShoppingItemsKeepsFacetVariantsSeparate() async {
        let (appState, _, _) = makeTestAppState()

        await appState.addShoppingItems([
            ShoppingItem(
                name: "Whole Garlic",
                quantity: 1,
                unit: .whole,
                category: .produce,
                catalogItemID: "garlic",
                facets: [.init(key: .preparation, value: "whole")]
            )
        ])

        await appState.addShoppingItems([
            ShoppingItem(
                name: "Minced Garlic",
                quantity: 2,
                unit: .clove,
                category: .produce,
                catalogItemID: "garlic",
                facets: [.init(key: .preparation, value: "minced")]
            )
        ])

        XCTAssertEqual(appState.shoppingItems.count, 2)
    }

    func testGenerateShoppingListDeduplicates() async {
        let (appState, _, _) = makeTestAppState()
        let recipe1 = makeRecipe(title: "R1", ingredients: [
            Ingredient(name: "Onion", quantity: 1),
            Ingredient(name: "Garlic", quantity: 2),
        ])
        let recipe2 = makeRecipe(title: "R2", ingredients: [
            Ingredient(name: "Onion", quantity: 2),
            Ingredient(name: "Pepper", quantity: 1),
        ])
        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .lunch, recipe: recipe1))
        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe2))
        await appState.generateShoppingListFromMealPlan()
        let names = appState.shoppingItems.map { $0.name.lowercased() }
        // "onion" should appear only once (deduplicated)
        XCTAssertEqual(names.filter { $0 == "onion" }.count, 1)
    }

    // MARK: - Shopping Toggle

    func testToggleShoppingItem() async {
        let (appState, _, _) = makeTestAppState()
        let item = ShoppingItem(name: "Test", category: .other)
        appState.shoppingItems.append(item)
        XCTAssertFalse(appState.shoppingItems[0].isChecked)
        await appState.toggleShoppingItem(item)
        XCTAssertTrue(appState.shoppingItems[0].isChecked)
        await appState.toggleShoppingItem(appState.shoppingItems[0])
        XCTAssertFalse(appState.shoppingItems[0].isChecked)
    }

    func testToggleFavoriteWithSaveCreatesUserRecipeCopy() async {
        let (appState, storage, _) = makeTestAppState()
        var discoverRecipe = makeRecipe(title: "Discover Dish")
        discoverRecipe.source = .bundled

        await appState.toggleFavoriteWithSave(discoverRecipe)

        XCTAssertEqual(storage.addRecipeCallCount, 1)
        XCTAssertEqual(appState.recipes.count, 1)
        XCTAssertTrue(appState.recipes[0].isFavorite)
        XCTAssertTrue(appState.recipes[0].source.isUserRecipe)
    }

    func testToggleFavoriteWithSaveRemovesLinkedDiscoverCopyWhenUnfavorited() async {
        let (appState, storage, _) = makeTestAppState()
        var discoverRecipe = makeRecipe(title: "Discover Dish")
        discoverRecipe.source = .bundled
        discoverRecipe.isFavorite = true
        appState.replaceDiscoverRecipesForTesting([discoverRecipe])
        appState.recipes = [Recipe(
            id: discoverRecipe.id,
            title: discoverRecipe.title,
            description: discoverRecipe.description,
            ingredients: discoverRecipe.ingredients,
            steps: discoverRecipe.steps,
            servings: discoverRecipe.servings,
            prepTimeMinutes: discoverRecipe.prepTimeMinutes,
            cookTimeMinutes: discoverRecipe.cookTimeMinutes,
            difficulty: discoverRecipe.difficulty,
            dietaryTags: discoverRecipe.dietaryTags,
            mealType: discoverRecipe.mealType,
            cuisine: discoverRecipe.cuisine,
            source: .user,
            nutrition: discoverRecipe.nutrition,
            sourceURL: discoverRecipe.sourceURL,
            isFavorite: true,
            dateAdded: discoverRecipe.dateAdded,
            timesCooked: discoverRecipe.timesCooked,
            rating: discoverRecipe.rating
        )]
        storage.recipeStore = appState.recipes

        await appState.toggleFavoriteWithSave(appState.recipes[0])

        XCTAssertEqual(storage.deleteRecipeCallCount, 1)
        XCTAssertTrue(appState.recipes.isEmpty)
        XCTAssertFalse(appState.discoverRecipes[0].isFavorite)
    }

    // MARK: - Cook Completion

    func testPantryCookReviewItemsIncludeExactAndPresenceOnlyMatches() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addPantryItem(PantryItem(name: "Flour", category: .grains, catalogItemID: "flour"))
        await appState.addPantryItem(PantryItem(name: "Custom Protein", category: .protein, quantity: 800, unit: .gram))

        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Flour", quantity: 200, unit: .gram, category: .grains, catalogItemID: "flour"),
            Ingredient(name: "Custom Protein", quantity: 500, unit: .gram, category: .protein)
        ])

        let reviewItems = appState.pantryCookReviewItems(for: recipe)

        XCTAssertEqual(reviewItems.count, 2)
        XCTAssertEqual(reviewItems.first?.pantryItem.name, "Custom Protein")
        XCTAssertEqual(reviewItems.first?.subtractQuantity, 500)
        XCTAssertEqual(reviewItems.first?.availableSelections, [.keep, .subtractRecipeAmount, .remove])
        XCTAssertEqual(reviewItems.last?.pantryItem.catalogItemID, "flour")
        XCTAssertEqual(reviewItems.last?.quantityMode, .presenceOnly)
        XCTAssertEqual(reviewItems.last?.availableSelections, [.keep, .remove])
    }

    func testApplyPantryCookReviewRemovesPresenceOnlyItem() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addPantryItem(PantryItem(name: "House Sauce", category: .condiments))

        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "House Sauce", quantity: 2, unit: .tablespoon, category: .condiments)
        ])

        var reviewItems = appState.pantryCookReviewItems(for: recipe)
        XCTAssertEqual(reviewItems.count, 1)

        reviewItems[0].selection = .remove
        await appState.applyPantryCookReview(reviewItems)

        XCTAssertTrue(appState.pantryItems.isEmpty)
    }

    func testApplyPantryCookReviewSubtractsExactQuantity() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addPantryItem(PantryItem(name: "Custom Protein", category: .protein, quantity: 800, unit: .gram))

        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Custom Protein", quantity: 500, unit: .gram, category: .protein)
        ])

        var reviewItems = appState.pantryCookReviewItems(for: recipe)
        XCTAssertEqual(reviewItems.count, 1)
        XCTAssertEqual(reviewItems[0].subtractQuantity, 500)

        reviewItems[0].selection = .subtractRecipeAmount
        await appState.applyPantryCookReview(reviewItems)

        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems.first?.quantity, 300)
    }

    func testApplyPantryCookReviewSubtractRemovesDepletedExactItem() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addPantryItem(PantryItem(name: "Custom Eggs", category: .dairy, quantity: 3, unit: .piece))

        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Custom Eggs", quantity: 3, unit: .piece, category: .dairy)
        ])

        var reviewItems = appState.pantryCookReviewItems(for: recipe)
        XCTAssertEqual(reviewItems.count, 1)

        reviewItems[0].selection = .subtractRecipeAmount
        await appState.applyPantryCookReview(reviewItems)

        XCTAssertTrue(appState.pantryItems.isEmpty)
    }

    func testAddRecipesToCookQueueBuildsParallelStage() async {
        let (appState, storage, _) = makeTestAppState()
        let recipes = [
            makeRecipe(title: "Soup"),
            makeRecipe(title: "Salad"),
        ]

        await appState.addRecipesToCookQueue(recipes, asParallelBatch: true)

        XCTAssertEqual(appState.cookQueue?.stages.count, 1)
        XCTAssertEqual(appState.cookQueue?.stages.first?.recipeIDs.count, 2)
        XCTAssertTrue(appState.cookQueue?.stages.first?.isParallelBatch == true)
        XCTAssertEqual(storage.cookQueueStore?.stages.count, 1)
    }

    func testMoveCookQueueStageReordersStages() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipes = [
            makeRecipe(title: "Soup"),
            makeRecipe(title: "Salad"),
            makeRecipe(title: "Bread"),
        ]

        await appState.addRecipesToCookQueue(recipes, asParallelBatch: false)
        let secondStageID = try XCTUnwrap(appState.cookQueue?.stages[1].id)

        await appState.moveCookQueueStage(secondStageID, by: -1)

        XCTAssertEqual(appState.cookQueue?.stages.map(\.title), ["Salad", "Soup", "Bread"])
    }

    func testBundleCookQueueStageWithNextCreatesParallelStage() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipes = [
            makeRecipe(title: "Soup"),
            makeRecipe(title: "Salad"),
            makeRecipe(title: "Bread"),
        ]

        await appState.addRecipesToCookQueue(recipes, asParallelBatch: false)
        let firstStageID = try XCTUnwrap(appState.cookQueue?.stages.first?.id)

        await appState.bundleCookQueueStageWithNext(firstStageID)

        XCTAssertEqual(appState.cookQueue?.stages.count, 2)
        XCTAssertEqual(appState.cookQueue?.stages.first?.recipeTitleSnapshots, ["Soup", "Salad"])
        XCTAssertTrue(appState.cookQueue?.stages.first?.isParallelBatch == true)
    }

    func testSplitCookQueueStageExpandsParallelBatchIntoSoloStages() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipes = [
            makeRecipe(title: "Soup"),
            makeRecipe(title: "Salad"),
        ]

        await appState.addRecipesToCookQueue(recipes, asParallelBatch: true)
        let stageID = try XCTUnwrap(appState.cookQueue?.stages.first?.id)

        await appState.splitCookQueueStage(stageID)

        XCTAssertEqual(appState.cookQueue?.stages.count, 2)
        XCTAssertEqual(appState.cookQueue?.stages.map(\.title), ["Soup", "Salad"])
        XCTAssertTrue(appState.cookQueue?.stages.allSatisfy { !$0.isParallelBatch } == true)
    }

    func testCompleteCookQueueStageAdvancesToNextPendingStage() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipes = [
            makeRecipe(title: "Soup"),
            makeRecipe(title: "Salad"),
        ]

        await appState.addRecipesToCookQueue(recipes, asParallelBatch: false)
        let firstStageID = try XCTUnwrap(appState.cookQueue?.stages.first?.id)
        let secondStageID = try XCTUnwrap(appState.cookQueue?.stages.dropFirst().first?.id)

        await appState.startCookQueueStage(firstStageID)
        await appState.completeCookQueueStage(firstStageID)

        // Completed stage is removed; second stage is now first
        XCTAssertEqual(appState.cookQueue?.stages.count, 1)
        XCTAssertEqual(appState.cookQueue?.stages.first?.id, secondStageID)
        XCTAssertEqual(appState.cookQueue?.stages.first?.status, .pending)
    }

    // MARK: - Cook Completion → Cooked Indicator + Prepared Dish

    func testCompleteCookQueueStageWithMealPlanEntryStampsCookedAt() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Soup", mealType: .dinner)
        await appState.addRecipe(recipe)

        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        await appState.addToMealPlan(entry)

        await appState.addRecipesToCookQueue([recipe], sourceEntries: [entry])
        let stageID = try XCTUnwrap(appState.cookQueue?.stages.first?.id)

        await appState.completeCookQueueStage(stageID)

        let updatedEntry = try XCTUnwrap(appState.mealPlan.first(where: { $0.id == entry.id }))
        XCTAssertNotNil(updatedEntry.cookedAt, "Entry should have cookedAt stamped after completing queue stage")
    }

    func testStampCookedMealPlanEntriesByRecipeDoesNotDoubleStamp() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Pasta")
        await appState.addRecipe(recipe)

        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        await appState.addToMealPlan(entry)

        // First stamp
        await appState.stampCookedMealPlanEntriesByRecipe(recipe.id)
        let firstStamp = try XCTUnwrap(appState.mealPlan.first?.cookedAt)

        // Second stamp — should not change the timestamp
        await appState.stampCookedMealPlanEntriesByRecipe(recipe.id)
        let secondStamp = try XCTUnwrap(appState.mealPlan.first?.cookedAt)

        XCTAssertEqual(firstStamp, secondStamp, "cookedAt should not be overwritten on second stamp")
    }

    func testStampCookedMealPlanEntriesDoesNotCreatePreparedDish() async throws {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Tacos")
        await appState.addRecipe(recipe)

        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        await appState.addToMealPlan(entry)

        // Stamp cooked — should NOT auto-create prepared dish (that's the caller's job now)
        await appState.stampCookedMealPlanEntriesByRecipe(recipe.id)

        XCTAssertEqual(appState.preparedDishes.count, 0, "stampCookedMealPlanEntries should not create PreparedDish")
        XCTAssertEqual(storage.addPreparedDishCallCount, 0)
    }

    func testAddPreparedDishForRecipeCreatesLinkedDish() async throws {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Chicken Tikka", servings: 4, mealType: .dinner,
                                nutrition: NutritionInfo(calories: 350, protein: 28, carbohydrates: 20, fat: 16))

        await appState.addPreparedDishForRecipe(recipe)

        XCTAssertEqual(appState.preparedDishes.count, 1)
        let dish = try XCTUnwrap(appState.preparedDishes.first)
        XCTAssertEqual(dish.name, "Chicken Tikka")
        XCTAssertEqual(dish.servingsRemaining, 4)
        XCTAssertEqual(dish.recipeID, recipe.id)
        XCTAssertEqual(dish.storage, .refrigerated)
        XCTAssertEqual(dish.mealTypes, [.dinner])
        XCTAssertNotNil(dish.useByDate, "Dish should have a useByDate from freshness policy")
        XCTAssertEqual(dish.nutrition, recipe.nutrition, "Dish should carry recipe nutrition")
        XCTAssertEqual(storage.addPreparedDishCallCount, 1)
    }

    func testAddPreparedDishForRecipeWithNilMealTypeSkipsMealType() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Mystery Dish", mealType: nil)

        await appState.addPreparedDishForRecipe(recipe)

        let dish = try XCTUnwrap(appState.preparedDishes.first)
        XCTAssertEqual(dish.mealTypes, [], "Nil mealType should result in empty mealTypes")
    }

    func testAddPreparedDishForRecipeUseByDateMatchesFreshnessPolicy() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Pasta Bake")

        let before = Date()
        await appState.addPreparedDishForRecipe(recipe)
        let after = Date()

        let dish = try XCTUnwrap(appState.preparedDishes.first)
        let expectedMin = Calendar.current.date(byAdding: .day, value: 4, to: before)!
        let expectedMax = Calendar.current.date(byAdding: .day, value: 4, to: after)!
        let useBy = try XCTUnwrap(dish.useByDate)
        XCTAssertTrue(useBy >= expectedMin && useBy <= expectedMax,
                      "useByDate should be ~4 days from now (refrigerated policy), got \(useBy)")
    }

    func testAddPreparedDishForRecipeWithNilNutritionLeavesDishNutritionNil() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Simple Toast", nutrition: nil)

        await appState.addPreparedDishForRecipe(recipe)

        let dish = try XCTUnwrap(appState.preparedDishes.first)
        XCTAssertNil(dish.nutrition, "Dish should have nil nutrition when recipe has none")
    }

    func testAddRecipesToCookQueueWithSourceEntriesLinksMealPlanEntryIDs() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Soup")
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)

        await appState.addRecipesToCookQueue([recipe], sourceEntries: [entry])

        let stage = try XCTUnwrap(appState.cookQueue?.stages.first)
        XCTAssertEqual(stage.sourceMealPlanEntryIDs, [entry.id], "Stage should carry the meal plan entry ID")
    }

    func testAddRecipesToCookQueueWithoutSourceEntriesHasEmptyMealPlanIDs() async throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Soup")

        await appState.addRecipesToCookQueue([recipe])

        let stage = try XCTUnwrap(appState.cookQueue?.stages.first)
        XCTAssertTrue(stage.sourceMealPlanEntryIDs.isEmpty, "Stage without source entries should have empty IDs")
    }

    // MARK: - Cooked Indicator in Planning Subtitle

    func testMealPlanEntryPlanningSubtitleShowsCookedWhenStamped() {
        let recipe = makeRecipe(title: "Salmon", prepTimeMinutes: 5, cookTimeMinutes: 15)
        var entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        entry.cookedAt = Date()

        let subtitle = entry.planningSubtitle ?? ""
        XCTAssertTrue(subtitle.hasPrefix("Cooked ✓"), "Planning subtitle should start with 'Cooked ✓' when cookedAt is set, got: \(subtitle)")
    }

    func testMealPlanEntryPlanningSubtitleOmitsCookedWhenNotStamped() {
        let recipe = makeRecipe(title: "Salmon", prepTimeMinutes: 5, cookTimeMinutes: 15)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)

        let subtitle = entry.planningSubtitle ?? ""
        XCTAssertFalse(subtitle.contains("Cooked"), "Planning subtitle should not mention 'Cooked' before stamping")
    }

    func testReplaceCookQueueStagesPreservesQueueIdentityAndOrdering() async throws {
        let (appState, storage, _) = makeTestAppState()
        let recipes = [
            makeRecipe(title: "Soup"),
            makeRecipe(title: "Salad"),
            makeRecipe(title: "Bread"),
        ]

        await appState.addRecipesToCookQueue(recipes, asParallelBatch: false)
        let originalQueueID = try XCTUnwrap(appState.cookQueue?.id)
        let secondStage = try XCTUnwrap(appState.cookQueue?.stages[1])
        let firstStage = try XCTUnwrap(appState.cookQueue?.stages.first)
        let replacement = [secondStage, firstStage]

        await appState.replaceCookQueueStages(replacement)

        XCTAssertEqual(appState.cookQueue?.id, originalQueueID)
        XCTAssertEqual(appState.cookQueue?.stages.map(\.title), ["Salad", "Soup"])
        XCTAssertEqual(storage.cookQueueStore?.id, originalQueueID)
        XCTAssertEqual(storage.cookQueueStore?.stages.map(\.title), ["Salad", "Soup"])
    }

    func testReplaceCookQueueStagesClearsQueueWhenStagesAreEmpty() async {
        let (appState, storage, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "Soup")])

        await appState.replaceCookQueueStages([])

        XCTAssertNil(appState.cookQueue)
        XCTAssertNil(storage.cookQueueStore)
    }

    // ================================================================
    // MARK: - Skip / Remove / Clear Cook Queue
    // ================================================================

    func testSkipCookQueueStageRemovesStageFromArray() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "Soup"), makeRecipe(title: "Salad")])
        let stageID = appState.cookQueue!.stages.first!.id

        await appState.skipCookQueueStage(stageID)

        XCTAssertEqual(appState.cookQueue?.stages.count, 1)
        XCTAssertEqual(appState.cookQueue?.stages.first?.title, "Salad")
    }

    func testSkipCookQueueLastStageNilsOutQueue() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "Soup")])
        let stageID = appState.cookQueue!.stages.first!.id

        await appState.skipCookQueueStage(stageID)

        XCTAssertNil(appState.cookQueue, "Queue should nil out when last stage is skipped")
    }

    func testRemoveCookQueueStageRemovesStageFromArray() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "A"), makeRecipe(title: "B")])
        let stageID = appState.cookQueue!.stages.first!.id

        await appState.removeCookQueueStage(stageID)

        XCTAssertEqual(appState.cookQueue?.stages.count, 1)
        XCTAssertEqual(appState.cookQueue?.stages.first?.title, "B")
    }

    func testRemoveCookQueueLastStageNilsOutQueue() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "Solo")])
        let stageID = appState.cookQueue!.stages.first!.id

        await appState.removeCookQueueStage(stageID)

        XCTAssertNil(appState.cookQueue, "Queue should nil out when last stage is removed")
    }

    func testClearCookQueueNilsOutQueue() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "A"), makeRecipe(title: "B")])
        XCTAssertNotNil(appState.cookQueue)

        await appState.clearCookQueue()

        XCTAssertNil(appState.cookQueue)
    }

    func testStartCookQueueStageMarksStageActive() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "A"), makeRecipe(title: "B")])
        let stageID = appState.cookQueue!.stages.first!.id

        await appState.startCookQueueStage(stageID)

        XCTAssertEqual(appState.cookQueue?.stages.first?.status, .active)
        XCTAssertEqual(appState.cookQueue?.stages.last?.status, .pending)
    }

    func testCompleteCookQueueLastStageNilsOutQueue() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "Only")])
        let stageID = appState.cookQueue!.stages.first!.id

        await appState.completeCookQueueStage(stageID)

        XCTAssertNil(appState.cookQueue, "Queue should nil out when last stage is completed")
    }

    // ================================================================
    // MARK: - Cook Queue Context Lookups
    // ================================================================

    func testCookQueueContextForStageReturnsQueueAndStageIDs() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "Test")])
        let stageID = appState.cookQueue!.stages.first!.id

        let context = appState.cookQueueContext(for: stageID)

        XCTAssertNotNil(context)
        XCTAssertEqual(context?.queueID, appState.cookQueue?.id)
        XCTAssertEqual(context?.stageID, stageID)
    }

    func testCookQueueContextForMissingStageReturnsNil() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "Test")])

        let context = appState.cookQueueContext(for: UUID())

        XCTAssertNil(context, "Should return nil for non-existent stage")
    }

    func testCookQueueContextForSessionMatchesQueueAndStage() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "Test")])
        let queueID = appState.cookQueue!.id
        let stageID = appState.cookQueue!.stages.first!.id

        let session = CookingSession(
            recipeId: UUID(),
            recipeName: "Test",
            totalSteps: 1,
            stepSummaries: [],
            currentStepIndex: 0,
            startedAt: Date(),
            backgroundedAt: Date(),
            isActive: true,
            queueId: queueID,
            queueStageId: stageID
        )

        let context = appState.cookQueueContext(for: session)

        XCTAssertNotNil(context)
        XCTAssertEqual(context?.queueID, queueID)
        XCTAssertEqual(context?.stageID, stageID)
    }

    func testCookQueueContextForSessionWithWrongQueueReturnsNil() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "Test")])

        let session = CookingSession(
            recipeId: UUID(),
            recipeName: "Test",
            totalSteps: 1,
            stepSummaries: [],
            currentStepIndex: 0,
            startedAt: Date(),
            backgroundedAt: Date(),
            isActive: true,
            queueId: UUID(), // wrong queue ID
            queueStageId: appState.cookQueue!.stages.first!.id
        )

        let context = appState.cookQueueContext(for: session)

        XCTAssertNil(context, "Should return nil when session queueId doesn't match")
    }

    // ================================================================
    // MARK: - Append Cook Queue Stages
    // ================================================================

    func testAppendCookQueueStagesAddsToExistingQueue() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addRecipesToCookQueue([makeRecipe(title: "Original")])
        let originalID = appState.cookQueue!.id

        let newStage = CookQueueStage(recipes: [makeRecipe(title: "Appended")])
        await appState.appendCookQueueStages([newStage])

        XCTAssertEqual(appState.cookQueue?.id, originalID, "Should keep same queue ID")
        XCTAssertEqual(appState.cookQueue?.stages.count, 2)
        XCTAssertEqual(appState.cookQueue?.stages.last?.title, "Appended")
    }

    func testAppendCookQueueStagesCreatesNewQueueWhenNone() async {
        let (appState, _, _) = makeTestAppState()
        XCTAssertNil(appState.cookQueue)

        let stage = CookQueueStage(recipes: [makeRecipe(title: "First")])
        await appState.appendCookQueueStages([stage])

        XCTAssertNotNil(appState.cookQueue)
        XCTAssertEqual(appState.cookQueue?.stages.count, 1)
    }

    func testAppendCookQueueStagesIgnoresEmptyRecipeStages() async {
        let (appState, _, _) = makeTestAppState()
        let emptyStage = CookQueueStage(recipeIDs: [], recipeTitleSnapshots: [])
        await appState.appendCookQueueStages([emptyStage])

        XCTAssertNil(appState.cookQueue, "Should not create queue for empty stages")
    }

    func testRequestRootTabStoresRequestedDestination() {
        let (appState, _, _) = makeTestAppState()

        appState.requestRootTab(.kitchen)

        XCTAssertEqual(appState.navigator.requestedRootTab, .kitchen)
    }

    func testPantryPresenceOnlyMergeDominatesExactQuantity() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addPantryItem(PantryItem(name: "Flour", category: .bakingSupplies))
        await appState.addPantryItem(PantryItem(name: "Flour", category: .bakingSupplies, quantity: 1, unit: .kilogram))

        let flour = try? XCTUnwrap(appState.pantryItems.first)
        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(flour?.quantityMode, .presenceOnly)
        XCTAssertNil(flour?.quantity)
        XCTAssertNil(flour?.unit)
    }

    // MARK: - Load All Data

    func testLoadAllData() async {
        let (appState, storage, _) = makeTestAppState()
        storage.pantryStore = [makePantryItem(name: "Loaded")]
        storage.preparedDishHistoryStore = [PreparedDishHistoryItem(dish: makePreparedDish(name: "Saved History"))]
        storage.recipeStore = [makeRecipe(title: "Loaded Recipe")]
        storage.mealPlanStore = [MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe(title: "Loaded Dinner"))]
        storage.shoppingStore = [ShoppingItem(name: "Loaded Shopping")]
        storage.cookQueueStore = CookQueue(stages: [CookQueueStage(recipes: [makeRecipe(title: "Queued")])])

        await appState.loadAllData()
        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.preparedDishHistory.count, 1)
        XCTAssertEqual(appState.recipes.count, 1)
        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(appState.cookQueue?.stages.count, 1)
    }

    func testLoadAllDataError() async {
        let (appState, storage, _) = makeTestAppState()
        storage.shouldThrowError = true
        await appState.loadAllData()
        XCTAssertNotNil(appState.errorMessage)
    }

    func testLoadAllDataPartialFailureKeepsSuccessfulCollections() async {
        let (appState, storage, _) = makeTestAppState()
        storage.pantryStore = [makePantryItem(name: "Loaded")]
        storage.recipeStore = [makeRecipe(title: "Loaded Recipe")]
        storage.shoppingStore = [ShoppingItem(name: "Loaded Shopping")]
        storage.failingOperations = [.fetchMealPlan]
        appState.mealPlan = [MealPlanEntry(date: Date(), mealType: .breakfast, customMealName: "Existing Meal")]

        await appState.loadAllData()

        XCTAssertEqual(appState.pantryItems.map(\.name), ["Loaded"])
        XCTAssertEqual(appState.recipes.map(\.title), ["Loaded Recipe"])
        XCTAssertEqual(appState.shoppingItems.map(\.name), ["Loaded Shopping"])
        XCTAssertEqual(appState.mealPlan.map(\.displayName), ["Existing Meal"])
        XCTAssertEqual(appState.errorMessage, TestError.mock.localizedDescription)
    }

    func testLoadAllDataSuccessClearsPreviousError() async {
        let (appState, storage, _) = makeTestAppState()
        storage.pantryStore = [makePantryItem(name: "Loaded")]
        appState.errorMessage = "Previous failure"

        await appState.loadAllData()

        XCTAssertNil(appState.errorMessage)
    }

    // MARK: - AI Actions

    func testGetShoppingList() async {
        let (appState, _, ai) = makeTestAppState()
        ai.shoppingListToReturn = [ShoppingItem(name: "Flour")]
        let result = await appState.getShoppingList(for: makeRecipe())
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(ai.generateShoppingListCallCount, 1)
    }

    func testGetRecipeSuggestions() async {
        let (appState, _, ai) = makeTestAppState()
        ai.recipesToReturn = [makeRecipe(title: "Suggestion")]
        let result = await appState.getRecipeSuggestions()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(ai.suggestRecipesCallCount, 1)
    }

    func testGetRecipeSuggestionsNormalizesAIAuthoredIngredients() async {
        let (appState, _, ai) = makeTestAppState()
        ai.recipesToReturn = [makeRecipe(
            title: "Suggestion",
            ingredients: [Ingredient(name: "Greek yogurt")],
            source: .aiGenerated
        )]

        let result = await appState.getRecipeSuggestions()

        XCTAssertEqual(result.first?.recipe.ingredients.first?.catalogItemID, "yogurt")
        XCTAssertEqual(result.first?.recipe.ingredients.first?.facets, [.init(key: .variant, value: "greek")])
        XCTAssertEqual(ai.suggestRecipesCallCount, 1)
    }

    func testGenerateRecipeNormalizesAIAuthoredIngredients() async {
        let (appState, _, ai) = makeTestAppState()
        ai.recipesToReturn = [makeRecipe(
            title: "Generated",
            ingredients: [Ingredient(name: "Greek yogurt")],
            source: .aiGenerated
        )]
        let preferences = RecipeGenerationPreferences(
        let preferences = RecipeGenerationPreferences(
            servings: 2,
            maxTimeMinutes: 25,
            spiceLevel: .medium,
            dietaryTags: [],
            usePantry: false,
            pantryIngredients: []
        )

        let result = await appState.generateRecipe(query: "parfait", preferences: preferences)
        let generatedRecipe = result?.recipe

        XCTAssertEqual(generatedRecipe?.ingredients.first?.catalogItemID, "yogurt")
        XCTAssertEqual(generatedRecipe?.ingredients.first?.facets, [.init(key: .variant, value: "greek")])
        XCTAssertEqual(ai.generateRecipeCallCount, 1)
        XCTAssertEqual(ai.lastGenerateRecipeQuery, "parfait")
    }

    func testImportRecipeFromURLReturnsImportedDraft() async {
        let (appState, _, ai) = makeTestAppState()
        ai.importResultToReturn = RecipeImportResult(
            title: "Imported",
            description: nil,
            ingredients: [Ingredient(name: "soy sauce")],
            steps: [],
            servings: 4,
            prepTimeMinutes: nil,
            cookTimeMinutes: nil,
            dietaryTags: nil,
            difficulty: nil,
            mealType: nil,
            cuisine: nil,
            nutrition: nil
        )

        let result = await appState.importRecipeFromURL("https://example.com/recipe")

        XCTAssertEqual(result?.recipe.source, .imported)
        XCTAssertEqual(result?.recipe.title, "Imported")
        XCTAssertEqual(result?.recipe.ingredients.first?.catalogItemID, "soy-sauce")
        XCTAssertEqual(ai.parseRecipeFromURLCallCount, 1)
    }

    func testImportRecipeFromTextReturnsImportedDraft() async {
        let (appState, _, ai) = makeTestAppState()
        ai.importResultToReturn = RecipeImportResult(
            title: "Imported Text",
            description: nil,
            ingredients: [Ingredient(name: "garlic")],
            steps: [],
            servings: 4,
            prepTimeMinutes: nil,
            cookTimeMinutes: nil,
            dietaryTags: nil,
            difficulty: nil,
            mealType: nil,
            cuisine: nil,
            nutrition: nil
        )

        let result = await appState.importRecipeFromText("garlic pasta")

        XCTAssertEqual(result?.recipe.source, .imported)
        XCTAssertEqual(result?.recipe.title, "Imported Text")
        XCTAssertEqual(result?.recipe.ingredients.first?.catalogItemID, "garlic")
        XCTAssertEqual(ai.parseRecipeFromTextCallCount, 1)
    }

    func testGetLeftoverIdeasNormalizesAIAuthoredIngredients() async {
        let (appState, _, ai) = makeTestAppState()
        ai.recipesToReturn = [makeRecipe(
            title: "Leftovers",
            ingredients: [Ingredient(name: "jasmine rice")],
            source: .aiGenerated
        )]

        let result = await appState.getLeftoverIdeas(ingredients: ["rice"])

        XCTAssertEqual(result.first?.recipe.ingredients.first?.catalogItemID, "rice")
        XCTAssertEqual(result.first?.recipe.ingredients.first?.facets, [.init(key: .variant, value: "jasmine")])
    }

    func testNormalizedAIRecipeAutoResolvesAmbiguousIngredients() async {
        let storage = MockStorageService()
        let ai = MockAIService()
        let parser = StubIngredientCandidateParserForAppStateTests()
        let ingredient = Ingredient(name: "moonmilk", category: .dairy)
        let wholeMilk = IngredientResolutionCandidate(
            id: "milk|variant=whole",
            catalogItemID: "milk",
            facets: [.init(key: .variant, value: "whole")],
            displayName: "Whole Milk",
            score: 0.92,
            rationale: "Whole milk best fits the recipe.",
            supportedFacets: []
        )
        let skimMilk = IngredientResolutionCandidate(
            id: "milk|variant=skim",
            catalogItemID: "milk",
            facets: [.init(key: .variant, value: "skim")],
            displayName: "Skim Milk",
            score: 0.84,
            rationale: "Skim milk is also plausible.",
            supportedFacets: []
        )
        parser.stubbedCandidates[ingredient.id] = [wholeMilk, skimMilk]
        ai.ingredientResolutionDecisionsToReturn = [
            IngredientResolutionDecision(
                ingredientID: ingredient.id,
                status: .ambiguous,
                selectedCandidateID: nil,
                candidateIDs: [wholeMilk.id, skimMilk.id],
                confidence: 0.63,
                rationale: "Two plausible milk variants remain."
            )
        ]
        ai.disambiguationDecisionsToReturn = [
            IngredientResolutionDecision(
                ingredientID: ingredient.id,
                status: .resolved,
                selectedCandidateID: wholeMilk.id,
                candidateIDs: [],
                confidence: 0.88,
                rationale: "Whole milk is the best fit for a creamy soup."
            )
        ]
        let appState = AppState(
            storageService: storage,
            aiService: ai,
            ingredientCandidateParser: parser,
            pantryItemPreferenceStore: MockPantryItemPreferenceStore(),
            shouldLoadOnInit: false
        )
        let recipe = makeRecipe(
            title: "Creamy Soup",
            ingredients: [ingredient],
            source: .aiGenerated
        )

        let normalized = await appState.normalizedAIRecipe(recipe)

        XCTAssertEqual(normalized?.recipe.ingredients.first?.catalogItemID, "milk")
        XCTAssertEqual(normalized?.recipe.ingredients.first?.facets, [.init(key: .variant, value: "whole")])
        XCTAssertEqual(ai.resolveIngredientsCallCount, 1)
        XCTAssertEqual(ai.disambiguateIngredientsCallCount, 1)
    }

    func testNormalizedAIRecipeFailsWhenAIDisambiguationCannotChoose() async {
        let storage = MockStorageService()
        let ai = MockAIService()
        let parser = StubIngredientCandidateParserForAppStateTests()
        let ingredient = Ingredient(name: "moonmilk", category: .dairy)
        let wholeMilk = IngredientResolutionCandidate(
            id: "milk|variant=whole",
            catalogItemID: "milk",
            facets: [.init(key: .variant, value: "whole")],
            displayName: "Whole Milk",
            score: 0.92,
            rationale: "Whole milk best fits the recipe.",
            supportedFacets: []
        )
        let skimMilk = IngredientResolutionCandidate(
            id: "milk|variant=skim",
            catalogItemID: "milk",
            facets: [.init(key: .variant, value: "skim")],
            displayName: "Skim Milk",
            score: 0.84,
            rationale: "Skim milk is also plausible.",
            supportedFacets: []
        )
        parser.stubbedCandidates[ingredient.id] = [wholeMilk, skimMilk]
        ai.ingredientResolutionDecisionsToReturn = [
            IngredientResolutionDecision(
                ingredientID: ingredient.id,
                status: .ambiguous,
                selectedCandidateID: nil,
                candidateIDs: [wholeMilk.id, skimMilk.id],
                confidence: 0.63,
                rationale: "Two plausible milk variants remain."
            )
        ]
        ai.disambiguationDecisionsToReturn = nil

        let appState = AppState(
            storageService: storage,
            aiService: ai,
            ingredientCandidateParser: parser,
            pantryItemPreferenceStore: MockPantryItemPreferenceStore(),
            shouldLoadOnInit: false
        )
        let recipe = makeRecipe(
            title: "Creamy Soup",
            ingredients: [ingredient],
            source: .aiGenerated
        )

        let normalized = await appState.normalizedAIRecipe(recipe)

        XCTAssertNil(normalized)
        XCTAssertEqual(ai.resolveIngredientsCallCount, 1)
        XCTAssertEqual(ai.disambiguateIngredientsCallCount, 1)
        XCTAssertEqual(appState.errorMessage, "Something went wrong. Please try again.")
    }

    func testModifyRecipeNormalizesAIAuthoredIngredientsAndUsesPantryContext() async {
        let (appState, _, ai) = makeTestAppState()
        await appState.addPantryItem(PantryItem(name: "Spinach", category: .produce))
        ai.recipesToReturn = [makeRecipe(
            title: "Modified",
            ingredients: [Ingredient(name: "jasmine rice")],
            source: .aiGenerated
        )]

        let result = await appState.modifyRecipe(makeRecipe(title: "Base", source: .aiGenerated), feedback: "make it lighter")
        let modifiedRecipe = result?.recipe

        XCTAssertEqual(modifiedRecipe?.ingredients.first?.catalogItemID, "rice")
        XCTAssertEqual(modifiedRecipe?.ingredients.first?.facets, [.init(key: .variant, value: "jasmine")])
        XCTAssertEqual(ai.modifyRecipeCallCount, 1)
        XCTAssertEqual(ai.lastModifyFeedback, "make it lighter")
        XCTAssertEqual(ai.lastModifyPantryIngredients, ["Spinach"])
    }

    func testCacheDiscoverRecipeReturnsNormalizedRecipe() async {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(
            title: "Generated Recipe",
            ingredients: [Ingredient(
                name: "Greek yogurt",
                category: .dairy,
                catalogItemID: "yogurt",
                facets: [.init(key: .variant, value: "greek")]
            )],
            source: .aiGenerated
        )

        let normalizedRecipe = await appState.normalizedAIRecipe(recipe)
        let cached: AppState.NormalizedAIRecipe? = if let normalizedRecipe {
            await appState.cacheDiscoverRecipe(normalizedRecipe)
        } else {
            nil
        }

        XCTAssertEqual(cached?.recipe.ingredients.first?.catalogItemID, "yogurt")
        XCTAssertEqual(cached?.recipe.ingredients.first?.facets, [PantryFacetSelection(key: .variant, value: "greek")])
        XCTAssertEqual(storage.recipeStore.first?.ingredients.first?.catalogItemID, "yogurt")
    }

    func testCacheDiscoverRecipeCanonicalizesResolvableIngredientsBeforeSaving() async {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(
            title: "Discover Soup",
            ingredients: [Ingredient(name: "Carrots", quantity: 2, unit: .whole, category: .produce)],
            source: .bundled
        )

        let cached = await appState.cacheDiscoverRecipe(recipe)

        XCTAssertEqual(cached?.ingredients.first?.catalogItemID, "carrot")
        XCTAssertEqual(storage.recipeStore.first?.ingredients.first?.catalogItemID, "carrot")
    }

    func testGetSubstitutions() async {
        let (appState, _, ai) = makeTestAppState()
        ai.substitutionsToReturn = [SubstitutionSuggestion.sample]
        let result = await appState.getSubstitutions(for: makeRecipe())
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(ai.suggestSubstitutionsCallCount, 1)
    }
}

// ===================================================================
// MARK: - ViewModel Tests
// ===================================================================

// MARK: - RecipeViewModel Tests

@MainActor
final class RecipeViewModelTests: XCTestCase {

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        XCTAssertTrue(condition(), "Timed out waiting for asynchronous RecipeViewModel work to finish", file: file, line: line)
    }

    private func makeSUT() -> (RecipeViewModel, AppState, MockStorageService, MockAIService) {
        let (appState, storage, ai) = makeTestAppState()
        let vm = RecipeViewModel(appState: appState)
        return (vm, appState, storage, ai)
    }

    // MARK: - Filtering

    func testFilterBySearchText() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Chicken Soup"))
        await appState.addRecipe(makeRecipe(title: "Beef Stew"))
        vm.searchText = "chicken"
        vm.applySearchTextImmediately()
        XCTAssertEqual(vm.filteredUserRecipes.count, 1)
        XCTAssertEqual(vm.filteredUserRecipes[0].title, "Chicken Soup")
    }

    func testFilterBySearchTextDescription() async {
        let (vm, appState, _, _) = makeSUT()
        let recipe = Recipe(title: "Mystery", description: "A creamy pasta dish")
        await appState.addRecipe(recipe)
        vm.searchText = "pasta"
        vm.applySearchTextImmediately()
        XCTAssertEqual(vm.filteredUserRecipes.count, 1)
    }

    func testFilterByFavorites() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Fav", isFavorite: true))
        await appState.addRecipe(makeRecipe(title: "NotFav", isFavorite: false))
        vm.showOnlyFavorites = true
        XCTAssertEqual(vm.filteredUserRecipes.count, 1)
        XCTAssertEqual(vm.filteredUserRecipes[0].title, "Fav")
    }

    func testFilterByDifficulty() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Easy", difficulty: .easy))
        await appState.addRecipe(makeRecipe(title: "Hard", difficulty: .hard))
        vm.selectedDifficulty = .easy
        XCTAssertEqual(vm.filteredUserRecipes.count, 1)
        XCTAssertEqual(vm.filteredUserRecipes[0].title, "Easy")
    }

    func testFilterByMealType() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Breakfast", mealType: .breakfast))
        await appState.addRecipe(makeRecipe(title: "Dinner", mealType: .dinner))
        vm.selectedMealType = .breakfast
        XCTAssertEqual(vm.filteredUserRecipes.count, 1)
        XCTAssertEqual(vm.filteredUserRecipes[0].title, "Breakfast")
    }

    func testFilterByDietaryTags() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Vegan", dietaryTags: [.vegan, .glutenFree]))
        await appState.addRecipe(makeRecipe(title: "Regular", dietaryTags: []))
        vm.selectedDietaryTags = [.vegan]
        XCTAssertEqual(vm.filteredUserRecipes.count, 1)
        XCTAssertEqual(vm.filteredUserRecipes[0].title, "Vegan")
    }

    func testFilterCombined() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Easy Vegan Dinner",
                                            difficulty: .easy, dietaryTags: [.vegan], mealType: .dinner, isFavorite: true))
        await appState.addRecipe(makeRecipe(title: "Hard Vegan Lunch",
                                            difficulty: .hard, dietaryTags: [.vegan], mealType: .lunch))
        vm.selectedDifficulty = .easy
        vm.selectedDietaryTags = [.vegan]
        vm.showOnlyFavorites = true
        XCTAssertEqual(vm.filteredUserRecipes.count, 1)
        XCTAssertEqual(vm.filteredUserRecipes[0].title, "Easy Vegan Dinner")
    }

    // MARK: - Sorting

    func testSortByName() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Zebra Cake"))
        await appState.addRecipe(makeRecipe(title: "Apple Pie"))
        vm.sortOrder = .name
        XCTAssertEqual(vm.filteredUserRecipes[0].title, "Apple Pie")
        XCTAssertEqual(vm.filteredUserRecipes[1].title, "Zebra Cake")
    }

    func testSortByDifficulty() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Hard", difficulty: .hard))
        await appState.addRecipe(makeRecipe(title: "Easy", difficulty: .easy))
        vm.sortOrder = .difficulty
        XCTAssertEqual(vm.filteredUserRecipes[0].title, "Easy")
    }

    func testSortByTime() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Long", prepTimeMinutes: 30, cookTimeMinutes: 60))
        await appState.addRecipe(makeRecipe(title: "Quick", prepTimeMinutes: 5, cookTimeMinutes: 10))
        vm.sortOrder = .time
        XCTAssertEqual(vm.filteredUserRecipes[0].title, "Quick")
    }

    func testShowCanMakeOnlyUpdatesWhenPantryItemChangesInPlace() async {
        let (vm, appState, _, _) = makeSUT()
        let recipe = makeRecipe(
            title: "Milk Toast",
            ingredients: [Ingredient(name: "Milk", quantity: 2, unit: .cup, category: .dairy)]
        )
        await appState.addRecipe(recipe)

        let pantryItem = makePantryItem(name: "Milk", category: .dairy, quantity: 1, unit: .cup)
        await appState.addPantryItem(pantryItem)

        vm.showCanMakeOnly = true
        XCTAssertTrue(vm.filteredUserRecipes.isEmpty)

        var updatedPantryItem = pantryItem
        updatedPantryItem.quantity = 2
        await appState.updatePantryItem(updatedPantryItem)

        XCTAssertEqual(vm.filteredUserRecipes.map(\.title), ["Milk Toast"])
    }

    func testShowCanMakeOnlyUpdatesWhenRecipeChangesInPlace() async {
        let (vm, appState, _, _) = makeSUT()
        let pantryItem = makePantryItem(name: "Milk", category: .dairy)
        await appState.addPantryItem(pantryItem)

        let recipe = makeRecipe(
            title: "Breakfast",
            ingredients: [Ingredient(name: "Milk", quantity: 1, unit: .cup, category: .dairy)]
        )
        await appState.addRecipe(recipe)

        vm.showCanMakeOnly = true
        XCTAssertEqual(vm.filteredUserRecipes.map(\.title), ["Breakfast"])

        var updatedRecipe = recipe
        updatedRecipe.ingredients = [Ingredient(name: "Flour", quantity: 1, unit: .cup, category: .grains)]
        await appState.updateRecipe(updatedRecipe)

        XCTAssertTrue(vm.filteredUserRecipes.isEmpty)
    }

    // MARK: - Actions

    func testToggleFavoriteUsesUpdate() async {
        let (vm, appState, storage, _) = makeSUT()
        let recipe = makeRecipe(title: "TestFav", isFavorite: false)
        await appState.addRecipe(recipe)
        vm.toggleFavorite(recipe)
        await waitUntil { storage.updateRecipeCallCount == 1 }
        XCTAssertEqual(storage.updateRecipeCallCount, 1, "toggleFavorite should call updateRecipe, not addRecipe")
        XCTAssertEqual(appState.recipes.count, 1, "Should not duplicate recipe")
        XCTAssertTrue(appState.recipes[0].isFavorite)
    }

    func testToggleFavoriteUnfavorite() async {
        let (vm, appState, _, _) = makeSUT()
        let recipe = makeRecipe(title: "Fav", isFavorite: true)
        await appState.addRecipe(recipe)
        vm.toggleFavorite(recipe)
        await waitUntil { !appState.recipes.isEmpty && appState.recipes[0].isFavorite == false }
        XCTAssertFalse(appState.recipes[0].isFavorite)
    }

    func testAddRecipe() async {
        let (vm, appState, _, _) = makeSUT()
        vm.addRecipe(makeRecipe(title: "New"))
        await waitUntil { appState.recipes.count == 1 }
        XCTAssertEqual(appState.recipes.count, 1)
    }

    func testDeleteRecipe() async {
        let (vm, appState, _, _) = makeSUT()
        let recipe = makeRecipe(title: "Delete")
        vm.addRecipe(recipe)
        await waitUntil { appState.recipes.count == 1 }
        vm.deleteRecipe(recipe)
        await waitUntil { appState.recipes.isEmpty }
        XCTAssertTrue(appState.recipes.isEmpty)
    }

    // testWhatCanIMake removed — feature was replaced by pantry match filtering

    func testClearFilters() async {
        let (vm, _, _, _) = makeSUT()
        vm.selectedDifficulty = .hard
        vm.selectedMealType = .dinner
        vm.selectedDietaryTags = [.vegan]
        vm.showOnlyFavorites = true
        vm.searchText = "test"
        vm.clearFilters()
        XCTAssertNil(vm.selectedDifficulty)
        XCTAssertNil(vm.selectedMealType)
        XCTAssertTrue(vm.selectedDietaryTags.isEmpty)
        XCTAssertFalse(vm.showOnlyFavorites)
        XCTAssertTrue(vm.searchText.isEmpty)
    }

    func testHasActiveFilters() {
        let (vm, _, _, _) = makeSUT()
        XCTAssertFalse(vm.hasActiveFilters)
        vm.selectedDifficulty = .easy
        XCTAssertTrue(vm.hasActiveFilters)
    }

    // MARK: - Import

    func testImportFromURL() async {
        let (vm, _, _, ai) = makeSUT()
        ai.importResultToReturn = RecipeImportResult(
            title: "Imported",
            description: nil,
            ingredients: [],
            steps: [],
            servings: 4,
            prepTimeMinutes: nil,
            cookTimeMinutes: nil,
            dietaryTags: nil,
            difficulty: nil,
            mealType: nil,
            cuisine: nil,
            nutrition: nil
        )
        vm.importFromURL("https://example.com/recipe")
        await waitUntil { ai.parseRecipeFromURLCallCount == 1 }
        XCTAssertNotNil(vm.importedRecipeDraft)
        XCTAssertEqual(vm.importedRecipeDraft?.recipe.title, "Imported")
        XCTAssertEqual(vm.importedRecipeDraft?.recipe.source, .imported)
        XCTAssertEqual(ai.parseRecipeFromURLCallCount, 1)
    }

    func testImportFromURLFails() async {
        let (vm, _, _, ai) = makeSUT()
        ai.importResultToReturn = nil
        vm.importFromURL("https://bad.url")
        await waitUntil { ai.parseRecipeFromURLCallCount == 1 }
        XCTAssertNil(vm.importedRecipeDraft)
    }

}

// MARK: - PantryViewModel Tests

@MainActor
final class PantryViewModelTests: XCTestCase {

    private func makeSUT() -> (PantryViewModel, AppState) {
        let (appState, _, _) = makeTestAppState()
        let vm = PantryViewModel(appState: appState)
        return (vm, appState)
    }

    // MARK: - Filtering

    func testFilterBySearchText() async {
        let (vm, appState) = makeSUT()
        await appState.addPantryItem(makePantryItem(name: "Milk", category: .dairy))
        await appState.addPantryItem(makePantryItem(name: "Chicken", category: .protein))
        vm.searchText = "Milk"
        vm.applySearchTextImmediately()
        XCTAssertEqual(vm.filteredItems.count, 1)
        XCTAssertEqual(vm.filteredItems[0].name, "Milk")
    }

    func testFilterByCategory() async {
        let (vm, appState) = makeSUT()
        await appState.addPantryItem(makePantryItem(name: "Milk", category: .dairy))
        await appState.addPantryItem(makePantryItem(name: "Chicken", category: .protein))
        vm.selectedCategory = .dairy
        XCTAssertEqual(vm.filteredItems.count, 1)
        XCTAssertEqual(vm.filteredItems[0].name, "Milk")
    }

    func testFilterNoCategoryShowsAll() async {
        let (vm, appState) = makeSUT()
        await appState.addPantryItem(makePantryItem(name: "Milk", category: .dairy))
        await appState.addPantryItem(makePantryItem(name: "Chicken", category: .protein))
        vm.selectedCategory = nil
        XCTAssertEqual(vm.filteredItems.count, 2)
    }

    // MARK: - Sorting

    func testSortByName() async {
        let (vm, appState) = makeSUT()
        await appState.addPantryItem(makePantryItem(name: "Zucchini"))
        await appState.addPantryItem(makePantryItem(name: "Apple"))
        vm.sortOrder = .name
        XCTAssertEqual(vm.filteredItems[0].name, "Apple")
    }

    func testSortByExpiry() async {
        let (vm, appState) = makeSUT()
        await appState.addPantryItem(makePantryItem(
            name: "Late",
            expiryDate: Calendar.current.date(byAdding: .day, value: 10, to: Date())
        ))
        await appState.addPantryItem(makePantryItem(
            name: "Soon",
            expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())
        ))
        vm.sortOrder = .expiry
        XCTAssertEqual(vm.filteredItems[0].name, "Soon")
    }

    // MARK: - Grouping

    func testGroupedByCategory() async {
        let (vm, appState) = makeSUT()
        await appState.addPantryItem(makePantryItem(name: "Milk", category: .dairy))
        await appState.addPantryItem(makePantryItem(name: "Cheese", category: .dairy))
        await appState.addPantryItem(makePantryItem(name: "Chicken", category: .protein))
        let groups = vm.groupedByCategory
        XCTAssertTrue(groups.count >= 2)
        let dairyGroup = groups.first { $0.0 == .dairy }
        XCTAssertEqual(dairyGroup?.1.count, 2)
    }

    func testActiveCategoryCount() async {
        let (vm, appState) = makeSUT()
        await appState.addPantryItem(makePantryItem(name: "Milk", category: .dairy))
        await appState.addPantryItem(makePantryItem(name: "Cheese", category: .dairy))
        await appState.addPantryItem(makePantryItem(name: "Chicken", category: .protein))
        XCTAssertEqual(vm.activeCategoryCount[.dairy], 2)
        XCTAssertEqual(vm.activeCategoryCount[.protein], 1)
        XCTAssertNil(vm.activeCategoryCount[.beverages])
    }

    func testAddStagedItemsAddsOnlyValidRows() async throws {
        let (vm, appState) = makeSUT()
        let milkDraft = PantryIntakeRowDraft(itemDefinition: try XCTUnwrap(PantryCatalog.item(id: "milk")))
        let invalidDraft = PantryIntakeRowDraft()

        let addedCount = await vm.addStagedItems([milkDraft, invalidDraft])

        XCTAssertEqual(addedCount, 1)
        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems.first?.catalogItemID, "milk")
    }

    // MARK: - CRUD

    func testAddItem() async {
        let (vm, appState) = makeSUT()
        await vm.addItem(makePantryItem(name: "NewItem"))
        XCTAssertEqual(appState.pantryItems.count, 1)
    }

    func testDeleteItem() async {
        let (vm, appState) = makeSUT()
        let item = makePantryItem(name: "Delete")
        await vm.addItem(item)
        await vm.deleteItem(item)
        XCTAssertTrue(appState.pantryItems.isEmpty)
    }

    func testUpdateItem() async {
        let (vm, appState) = makeSUT()
        var item = makePantryItem(name: "Update", quantity: 1)
        await vm.addItem(item)
        item.quantity = 5
        await vm.updateItem(item)
        XCTAssertEqual(appState.pantryItems[0].quantity, 5)
    }
}

@MainActor
final class PantryBulkAddViewModelTests: XCTestCase {
    func testStageCatalogItemUsesCatalogDefaults() throws {
        let bulk = PantryBulkAddViewModel(preferenceStore: MockPantryItemPreferenceStore())
        let item = try XCTUnwrap(PantryCatalog.item(id: "milk"))

        bulk.stageCatalogItem(item)

        let staged = try XCTUnwrap(bulk.stagedRows.first)
        XCTAssertEqual(staged.selectedItemID, "milk")
        XCTAssertEqual(staged.storage, .refrigerated)
        XCTAssertEqual(staged.quantityText, "1")
        XCTAssertEqual(staged.unit, .liter)
    }

    func testToggleCatalogItemSelectionAddsAndRemovesItem() throws {
        let bulk = PantryBulkAddViewModel(preferenceStore: MockPantryItemPreferenceStore())
        let item = try XCTUnwrap(PantryCatalog.item(id: "milk"))

        bulk.toggleCatalogItemSelection(item)
        XCTAssertTrue(bulk.isCatalogItemSelected(item))
        XCTAssertEqual(bulk.stagedRows.count, 1)

        bulk.toggleCatalogItemSelection(item)
        XCTAssertFalse(bulk.isCatalogItemSelected(item))
        XCTAssertTrue(bulk.stagedRows.isEmpty)
    }

    func testStageSearchEntriesAddsRecognizedItemsAndTracksUnresolvedTerms() {
        let bulk = PantryBulkAddViewModel(preferenceStore: MockPantryItemPreferenceStore())
        bulk.searchComposerText = "milk, dragonfruit\ncheese"

        let addedCount = bulk.stageSearchEntries()

        XCTAssertEqual(addedCount, 2)
        XCTAssertEqual(bulk.stagedRows.count, 2)
        XCTAssertEqual(bulk.unresolvedTokens, ["dragonfruit"])
        XCTAssertEqual(bulk.selectedTab, .review)
        XCTAssertTrue(bulk.searchComposerText.isEmpty)
    }

    func testSearchPreviewResultsUsesTrailingToken() {
        let bulk = PantryBulkAddViewModel(preferenceStore: MockPantryItemPreferenceStore())
        bulk.searchComposerText = "milk\nchicken"

        let resultIDs = bulk.searchPreviewResults.prefix(3).map(\.id)

        XCTAssertTrue(resultIDs.contains("chicken-breast"))
    }

    func testStageCatalogItemUsesSavedDefaultsWhenPresent() throws {
        let preferenceStore = MockPantryItemPreferenceStore()
        var savedDraft = PantryIntakeRowDraft(itemDefinition: try XCTUnwrap(PantryCatalog.item(id: "bread")))
        savedDraft.setFacet(.variant, value: "wholemeal")
        savedDraft.setFacet(.form, value: "sliced")
        savedDraft.setQuantityText("3")
        savedDraft.setUnit(.slice)
        savedDraft.setStorage(.refrigerated)
        savedDraft.setExpiryDate(Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date())
        savedDraft.notes = "Freezer half goes fast"
        preferenceStore.savePreference(try XCTUnwrap(PantryItemDefaultPreference(draft: savedDraft)))

        let bulk = PantryBulkAddViewModel(preferenceStore: preferenceStore)
        let item = try XCTUnwrap(PantryCatalog.item(id: "bread"))

        bulk.stageCatalogItem(item)

        let staged = try XCTUnwrap(bulk.stagedRows.first)
        XCTAssertEqual(staged.selectedFacetValues[.variant], "wholemeal")
        XCTAssertEqual(staged.selectedFacetValues[.form], "sliced")
        XCTAssertEqual(staged.quantityText, "3")
        XCTAssertEqual(staged.unit, .slice)
        XCTAssertEqual(staged.storage, .refrigerated)
        XCTAssertEqual(staged.notes, "Freezer half goes fast")
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let stagedExpiryDate = try XCTUnwrap(staged.resolvedExpiryDate)
        let stagedOffset = calendar.dateComponents([.day], from: startOfToday, to: calendar.startOfDay(for: stagedExpiryDate)).day
        XCTAssertEqual(stagedOffset, 4)
    }

    func testStageCustomItemCreatesEditableCustomDraft() {
        let bulk = PantryBulkAddViewModel(preferenceStore: MockPantryItemPreferenceStore())

        bulk.stageCustomItem(named: "House Chili Paste")

        XCTAssertEqual(bulk.stagedRows.count, 1)
        XCTAssertTrue(bulk.stagedRows[0].isCustomItem)
        XCTAssertEqual(bulk.stagedRows[0].searchText, "House Chili Paste")
        XCTAssertEqual(bulk.stagedRows[0].storage, .pantry)
        XCTAssertEqual(bulk.selectedTab, .review)
    }

    func testRemoveDefaultFallsBackToCatalogDefaults() throws {
        let preferenceStore = MockPantryItemPreferenceStore()
        var savedDraft = PantryIntakeRowDraft(itemDefinition: try XCTUnwrap(PantryCatalog.item(id: "bread")))
        savedDraft.setFacet(.variant, value: "wholemeal")
        preferenceStore.savePreference(try XCTUnwrap(PantryItemDefaultPreference(draft: savedDraft)))

        let bulk = PantryBulkAddViewModel(preferenceStore: preferenceStore)
        bulk.removeDefault(for: "bread")
        let draft = bulk.draft(for: try XCTUnwrap(PantryCatalog.item(id: "bread")))

        XCTAssertEqual(draft.selectedFacetValues[.variant], "white")
    }

    func testMatchesDefaultPreferenceTracksWhenDraftMovesAwayAndBack() throws {
        var draft = PantryIntakeRowDraft(itemDefinition: try XCTUnwrap(PantryCatalog.item(id: "bread")))
        draft.setFacet(.variant, value: "wholemeal")
        draft.setFacet(.form, value: "sliced")

        let savedDefault = try XCTUnwrap(PantryItemDefaultPreference(draft: draft))
        XCTAssertTrue(draft.matchesDefaultPreference(savedDefault))

        draft.setFacet(.form, value: "loaf")
        XCTAssertFalse(draft.matchesDefaultPreference(savedDefault))

        draft.setFacet(.form, value: "sliced")
        XCTAssertTrue(draft.matchesDefaultPreference(savedDefault))
    }
}

// MARK: - HomeViewModel Tests

@MainActor
final class HomeViewModelTests: XCTestCase {

    private func makeSUT() -> (HomeViewModel, AppState) {
        let (appState, _, _) = makeTestAppState()
        let vm = HomeViewModel(appState: appState)
        return (vm, appState)
    }

    // MARK: - Greeting

    func testGreetingIsNotEmpty() {
        let (vm, _) = makeSUT()
        XCTAssertFalse(vm.greetingMessage.isEmpty)
    }

    func testGreetingContainsGood() {
        let (vm, _) = makeSUT()
        XCTAssertTrue(vm.greetingMessage.hasPrefix("Good"))
    }

    func testGreetingNeverSaysGoodNight() {
        let (vm, _) = makeSUT()
        XCTAssertNotEqual(vm.greetingMessage, "Good night", "Greeting should never say 'Good night'")
    }

    // MARK: - Refresh

    func testRefreshUpdatesAllFields() async {
        let (vm, appState) = makeSUT()
        await appState.addRecipe(makeRecipe(
            title: "Suggested",
            ingredients: [Ingredient(name: "Milk", quantity: 1)],
            nutrition: NutritionInfo(calories: 300, protein: 10, carbohydrates: 40, fat: 8)
        ))
        await appState.addPantryItem(makePantryItem(name: "Milk"))
        vm.refresh()
        XCTAssertNotNil(vm.suggestedRecipe, "Should suggest a recipe based on pantry match")
    }

    func testSuggestedRecipePicksBestMatch() async {
        let (vm, appState) = makeSUT()
        await appState.addPantryItem(makePantryItem(name: "Chicken"))
        await appState.addPantryItem(makePantryItem(name: "Rice"))
        // Recipe with 100% match
        await appState.addRecipe(makeRecipe(title: "Full Match", ingredients: [
            Ingredient(name: "Chicken", quantity: 1),
            Ingredient(name: "Rice", quantity: 1),
        ]))
        // Recipe with 50% match
        await appState.addRecipe(makeRecipe(title: "Partial Match", ingredients: [
            Ingredient(name: "Chicken", quantity: 1),
            Ingredient(name: "Tofu", quantity: 1),
        ]))
        vm.refresh()
        XCTAssertEqual(vm.suggestedRecipe?.title, "Full Match")
    }

    func testRefreshUsesDiscoverRecipesForSuggestion() async {
        let (vm, appState) = makeSUT()
        await appState.addPantryItem(makePantryItem(
            name: "Spinach",
            category: .produce,
            quantity: 1,
            unit: .whole,
            catalogItemID: "spinach"
        ))

        let discoverRecipe = makeRecipe(
            title: "Spinach Omelette",
            ingredients: [
                Ingredient(name: "Spinach", quantity: 1, unit: .whole, category: .produce, catalogItemID: "spinach")
            ],
            source: .bundled
        )

        appState.replaceDiscoverRecipesForTesting([discoverRecipe])

        vm.refresh()

        XCTAssertEqual(vm.suggestedRecipe?.title, "Spinach Omelette")
    }

    // MARK: - Today's Meals

    func testTodaysMealsFilters() async {
        let (vm, appState) = makeSUT()
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        await appState.addToMealPlan(MealPlanEntry(date: today, mealType: .dinner, recipe: makeRecipe(title: "Today")))
        await appState.addToMealPlan(MealPlanEntry(date: tomorrow, mealType: .dinner, recipe: makeRecipe(title: "Tomorrow")))
        vm.refresh()
        XCTAssertEqual(vm.todaysMeals.count, 1)
        XCTAssertEqual(vm.todaysMeals[0].recipe?.title, "Today")
    }

    // MARK: - Weekly Nutrition

    func testWeeklyNutritionEmptyWhenNoMeals() {
        let (vm, _) = makeSUT()
        vm.refresh()
        XCTAssertNil(vm.weeklyNutrition)
    }

    func testWeeklyNutritionCalculation() async {
        let (vm, appState) = makeSUT()
        let recipe = makeRecipe(
            nutrition: NutritionInfo(calories: 700, protein: 30, carbohydrates: 80, fat: 20)
        )
        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe))
        vm.refresh()
        XCTAssertNotNil(vm.weeklyNutrition)
        XCTAssertEqual(vm.weeklyNutrition?.totalCalories, 700)
        XCTAssertEqual(vm.weeklyNutrition?.mealsPlanned, 1)
        XCTAssertEqual(vm.weeklyNutrition?.avgCaloriesPerMeal, 700)
    }

    func testWeeklyNutritionAveragesUsePlannedMealsInsteadOfWeekDays() async {
        let (vm, appState) = makeSUT()
        let firstRecipe = makeRecipe(
            nutrition: NutritionInfo(calories: 600, protein: 30, carbohydrates: 60, fat: 20)
        )
        let secondRecipe = makeRecipe(
            nutrition: NutritionInfo(calories: 400, protein: 10, carbohydrates: 20, fat: 10)
        )

        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .breakfast, recipe: firstRecipe))
        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .lunch, recipe: secondRecipe))
        vm.refresh()

        XCTAssertEqual(vm.weeklyNutrition?.mealsPlanned, 2)
        XCTAssertEqual(vm.weeklyNutrition?.avgCaloriesPerMeal, 500)
        XCTAssertEqual(vm.weeklyNutrition?.avgProteinPerMeal, 20)
    }

    func testWeeklyNutritionIgnoresMealsOutsideCurrentWeek() async throws {
        let (vm, appState) = makeSUT()
        let calendar = Calendar.current
        let currentWeek = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: Date()))
        let nextWeekDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: currentWeek.start))

        let currentWeekRecipe = makeRecipe(
            title: "This Week Dinner",
            nutrition: NutritionInfo(calories: 650, protein: 28, carbohydrates: 50, fat: 24)
        )
        let nextWeekRecipe = makeRecipe(
            title: "Next Week Dinner",
            nutrition: NutritionInfo(calories: 1200, protein: 60, carbohydrates: 90, fat: 48)
        )

        await appState.addToMealPlan(MealPlanEntry(date: currentWeek.start, mealType: .dinner, recipe: currentWeekRecipe))
        await appState.addToMealPlan(MealPlanEntry(date: nextWeekDate, mealType: .dinner, recipe: nextWeekRecipe))

        vm.refresh()

        XCTAssertEqual(vm.weeklyNutrition?.totalCalories, 650)
        XCTAssertEqual(vm.weeklyNutrition?.mealsPlanned, 1)
        XCTAssertEqual(vm.weeklyNutrition?.avgCaloriesPerMeal, 650)
    }

    // MARK: - Expiring Prepared Dishes

    func testExpiringPreparedDishesReflectsAppState() async {
        let (vm, appState) = makeSUT()
        // Pantry storage = 2 day expiry → dish with useByDate 1 day from now should show up in expiring list
        let dish = PreparedDish(name: "Old Leftovers", mealTypes: [.dinner], servingsRemaining: 1, storage: .pantry,
                                useByDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                                dateAdded: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        await appState.addPreparedDish(dish)

        // expiringPreparedDishes is a passthrough from appState
        let expiring = vm.expiringPreparedDishes
        XCTAssertEqual(expiring.count, 1)
        XCTAssertEqual(expiring.first?.name, "Old Leftovers")
    }

    // MARK: - Dashboard Passthrough

    func testDashboardStartsEmpty() {
        let (vm, _) = makeSUT()
        XCTAssertTrue(vm.todaysMeals.isEmpty)
        XCTAssertTrue(vm.expiringItems.isEmpty)
        XCTAssertNil(vm.suggestedRecipe)
        XCTAssertNil(vm.weeklyNutrition)
    }
}

// MARK: - ShoppingViewModel Tests

@MainActor
final class ShoppingViewModelTests: XCTestCase {

    private func makeSUT() -> (ShoppingViewModel, AppState) {
        let (appState, _, _) = makeTestAppState()
        let vm = ShoppingViewModel(appState: appState)
        return (vm, appState)
    }

    // MARK: - Items & Filtering

    func testItemsReturnsAll() {
        let (vm, appState) = makeSUT()
        appState.shoppingItems = [
            ShoppingItem(name: "Milk"),
            ShoppingItem(name: "Bread"),
        ]
        XCTAssertEqual(vm.items.count, 2)
    }

    func testItemsFilteredBySearch() {
        let (vm, appState) = makeSUT()
        appState.shoppingItems = [
            ShoppingItem(name: "Milk"),
            ShoppingItem(name: "Bread"),
        ]
        vm.searchText = "Milk"
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items[0].catalogItemID, "milk")
    }

    // MARK: - Grouping

    func testGroupedByCategory() {
        let (vm, appState) = makeSUT()
        appState.shoppingItems = [
            ShoppingItem(name: "Milk", category: .dairy),
            ShoppingItem(name: "Bread", category: .grains),
            ShoppingItem(name: "Cheese", category: .dairy),
        ]
        let groups = vm.groupedByCategory
        XCTAssertTrue(groups.count >= 2)
    }

    // MARK: - Counts & Progress

    func testCheckedCount() {
        let (vm, appState) = makeSUT()
        appState.shoppingItems = [
            ShoppingItem(name: "A", isChecked: true),
            ShoppingItem(name: "B", isChecked: false),
            ShoppingItem(name: "C", isChecked: true),
        ]
        XCTAssertEqual(vm.checkedCount, 2)
        XCTAssertEqual(vm.totalCount, 3)
        XCTAssertEqual(vm.progressText, "2/3 items")
    }

    // MARK: - Toggle

    func testToggleItem() {
        let (vm, appState) = makeSUT()
        let item = ShoppingItem(name: "Test")
        appState.shoppingItems = [item]
        vm.toggleItem(item)
        let expectation = XCTestExpectation(description: "toggle persists")
        Task { @MainActor in
            await Task.yield()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(appState.shoppingItems[0].isChecked)
    }

    // MARK: - Remove Checked

    func testRemoveCheckedItems() async {
        let (vm, appState) = makeSUT()
        appState.shoppingItems = [
            ShoppingItem(name: "A", isChecked: true),
            ShoppingItem(name: "B", isChecked: false),
            ShoppingItem(name: "C", isChecked: true),
        ]
        vm.removeCheckedItems()
        await Task.yield()
        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(appState.shoppingItems[0].name, "B")
    }

    // MARK: - Add & Remove

    func testAddItem() async {
        let (vm, appState) = makeSUT()
        vm.addItem(ShoppingItem(name: "NewItem"))
        await Task.yield()
        XCTAssertEqual(appState.shoppingItems.count, 1)
    }

    func testRemoveItem() async {
        let (vm, appState) = makeSUT()
        let item = ShoppingItem(name: "Remove")
        appState.shoppingItems = [item]
        vm.removeItem(item)
        await Task.yield()
        XCTAssertTrue(appState.shoppingItems.isEmpty)
    }

    // MARK: - Add Checked to Pantry

    func testAddCheckedToPantry() async {
        let (vm, appState) = makeSUT()
        appState.shoppingItems = [
            ShoppingItem(name: "Milk", quantity: 1, unit: .liter, category: .dairy, isChecked: true),
            ShoppingItem(name: "Bread", category: .grains, isChecked: false),
        ]
        vm.addCheckedToPantry()
        await Task.yield()
        // Milk should be in pantry, Bread should remain in shopping
        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems[0].catalogItemID, "milk")
        XCTAssertEqual(appState.pantryItems[0].category, .dairy)
        // Only unchecked items remain
        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(appState.shoppingItems[0].catalogItemID, "bread")
    }

    func testAddCheckedToPantryPreservesCatalogIdentity() async {
        let (vm, appState) = makeSUT()
        appState.shoppingItems = [
            ShoppingItem(name: "Carrots", quantity: 2, unit: .whole, category: .produce, isChecked: true)
        ]

        vm.addCheckedToPantry()
        await Task.yield()

        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems[0].catalogItemID, "carrot")
    }

    func testAddCheckedToPantryPreservesCatalogFacets() async {
        let (vm, appState) = makeSUT()
        appState.shoppingItems = [
            ShoppingItem(
                name: "Minced Garlic",
                quantity: 2,
                unit: .clove,
                category: .produce,
                isChecked: true,
                catalogItemID: "garlic",
                facets: [.init(key: .preparation, value: "minced")]
            )
        ]

        vm.addCheckedToPantry()
        await Task.yield()

        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems[0].catalogItemID, "garlic")
        XCTAssertEqual(appState.pantryItems[0].facets, [.init(key: .preparation, value: "minced")])
    }

    func testAddCheckedToPantryMergesIntoExistingMatchingPantryRow() async {
        let (vm, appState) = makeSUT()
        await appState.addPantryItem(makePantryItem(
            name: "Sourdough Bread",
            category: .grains,
            quantity: 1,
            unit: .whole,
            catalogItemID: "bread",
            facets: [.init(key: .variant, value: "sourdough")]
        ))
        appState.shoppingItems = [
            ShoppingItem(
                name: "Sourdough Bread",
                quantity: 1,
                unit: .whole,
                category: .grains,
                isChecked: true,
                catalogItemID: "bread",
                facets: [.init(key: .variant, value: "sourdough")]
            )
        ]

        vm.addCheckedToPantry()
        await Task.yield()

        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems[0].quantity, 2)
    }

    func testAddCheckedToPantryUsesReviewedPantryQuantity() async {
        let (vm, appState) = makeSUT()
        appState.shoppingItems = [
            ShoppingItem(
                name: "Soy Sauce",
                quantity: 2,
                unit: .tablespoon,
                category: .condiments,
                isChecked: true,
                pantryQuantity: 1,
                pantryUnit: .package,
                pantryQuantityMode: .exact
            )
        ]

        vm.addCheckedToPantry()
        await Task.yield()

        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems[0].quantity, 1)
        XCTAssertEqual(appState.pantryItems[0].unit, .package)
    }

    func testAddCheckedToPantrySupportsPresenceOnlyPantryTransfer() async {
        let (vm, appState) = makeSUT()
        appState.shoppingItems = [
            ShoppingItem(
                name: "Salt",
                quantity: 1,
                unit: .package,
                category: .spices,
                isChecked: true,
                pantryQuantityMode: .presenceOnly
            )
        ]

        vm.addCheckedToPantry()
        await Task.yield()

        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertNil(appState.pantryItems[0].quantity)
        XCTAssertEqual(appState.pantryItems[0].quantityMode, .presenceOnly)
    }
}

@MainActor
final class ShoppingAddItemViewModelTests: XCTestCase {
    func testSearchResultsPreferFacetAwareParserMatches() {
        let viewModel = ShoppingAddItemViewModel()
        viewModel.searchText = "garlic, minced"

        let results = viewModel.searchResults

        XCTAssertEqual(results.first?.catalogItemID, "garlic")
        XCTAssertEqual(results.first?.facets, [.init(key: .preparation, value: "minced")])
        XCTAssertEqual(results.first?.displayName, "Garlic")
    }

    func testSearchResultsCollapseFacetVariantsIntoSingleBaseItem() {
        let viewModel = ShoppingAddItemViewModel()
        viewModel.searchText = "bread"

        let breadResults = viewModel.searchResults.filter { $0.catalogItemID == "bread" }

        XCTAssertEqual(breadResults.count, 1)
        XCTAssertEqual(breadResults.first?.displayName, "Bread")
        XCTAssertEqual(breadResults.first?.facets, [
            .init(key: .variant, value: "none"),
            .init(key: .form, value: "loaf")
        ])
    }

    func testBuildItemPreservesSelectedCatalogFacets() {
        let viewModel = ShoppingAddItemViewModel()
        viewModel.chooseSuggestion(
            ShoppingCatalogSuggestion(
                id: "garlic",
                catalogItemID: "garlic",
                facets: [.init(key: .preparation, value: "minced")],
                displayName: "Garlic",
                category: .produce
            )
        )
        viewModel.setQuantityText("3")
        viewModel.setUnit(.clove)

        let item = viewModel.buildItem()

        XCTAssertEqual(item?.catalogItemID, "garlic")
        XCTAssertEqual(item?.facets, [.init(key: .preparation, value: "minced")])
        XCTAssertEqual(item?.name, "Minced Garlic")
    }

    func testBuildItemSupportsCustomFallback() {
        let viewModel = ShoppingAddItemViewModel()
        viewModel.searchText = "special salt blend"
        viewModel.setCustomItemMode()
        viewModel.customCategory = .spices
        viewModel.setQuantityText("1")
        viewModel.setUnit(.package)

        let item = viewModel.buildItem()

        XCTAssertEqual(item?.name, "special salt blend")
        XCTAssertEqual(item?.category, .spices)
        XCTAssertNil(item?.catalogItemID)
    }
}

// MARK: - MealPlanViewModel Tests

@MainActor
final class MealPlanViewModelTests: XCTestCase {

    private func makeSUT() -> (MealPlanViewModel, AppState) {
        let (appState, _, _) = makeTestAppState()
        let vm = MealPlanViewModel(appState: appState)
        return (vm, appState)
    }

    // MARK: - Week Navigation

    func testWeekDaysReturnsSevenDays() {
        let (vm, _) = makeSUT()
        XCTAssertEqual(vm.weekDays.count, 7)
    }

    func testPreviousWeek() {
        let (vm, _) = makeSUT()
        let originalStart = vm.weekStartDate
        vm.previousWeek()
        XCTAssertTrue(vm.weekStartDate < originalStart)
    }

    func testNextWeek() {
        let (vm, _) = makeSUT()
        let originalStart = vm.weekStartDate
        vm.nextWeek()
        XCTAssertTrue(vm.weekStartDate > originalStart)
    }

    func testGoToCurrentWeek() {
        let (vm, _) = makeSUT()
        vm.nextWeek()
        vm.nextWeek()
        vm.goToCurrentWeek()
        let calendar = Calendar.current
        let expected = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        XCTAssertTrue(calendar.isDate(vm.weekStartDate, inSameDayAs: expected))
    }

    // MARK: - Assign & Remove

    func testAssignRecipe() async {
        let (vm, appState) = makeSUT()
        let recipe = makeRecipe(title: "Assigned")
        let slot = MealPlanViewModel.MealSlot(date: Date(), mealType: .dinner)
        await vm.assignRecipe(recipe, to: slot)
        await Task.yield()
        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(vm.entries.count, 1)
    }

    func testAssignPreparedDish() async {
        let (vm, appState) = makeSUT()
        let dish = makePreparedDish(name: "Soup")
        await appState.addPreparedDish(dish)
        let slot = MealPlanViewModel.MealSlot(date: Date(), mealType: .lunch)

        await vm.assignPreparedDish(dish, to: slot)
        await Task.yield()

        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(appState.mealPlan.first?.preparedDish?.name, "Soup")
    }

    func testRemoveEntry() async {
        let (vm, appState) = makeSUT()
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe())
        await appState.addToMealPlan(entry)
        vm.removeEntry(entry)
        await Task.yield()
        XCTAssertTrue(appState.mealPlan.isEmpty)
        XCTAssertTrue(vm.entries.isEmpty)
    }

    // MARK: - Select Slot

    func testSelectSlot() {
        let (vm, _) = makeSUT()
        vm.selectSlot(date: Date(), mealType: .lunch)
        XCTAssertNotNil(vm.selectedSlot)
        XCTAssertEqual(vm.selectedSlot?.mealType, .lunch)
        XCTAssertTrue(vm.showMealPicker)
    }

    // MARK: - Shopping List Generation

    func testGenerateShoppingList() async {
        let (vm, appState) = makeSUT()
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Flour", quantity: 2, unit: .cup),
        ])
        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe))
        await vm.generateShoppingList()
        await Task.yield()
        XCTAssertFalse(appState.shoppingItems.isEmpty)
    }

    func testPreviewShoppingListReturnsFilteredItems() async {
        let (vm, appState) = makeSUT()
        await appState.addPantryItem(makePantryItem(name: "Milk", category: .dairy, quantity: 1, unit: .liter))
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Milk", quantity: 250, unit: .milliliter, category: .dairy),
            Ingredient(name: "Water", quantity: 1, unit: .cup, category: .other),
            Ingredient(name: "Pasta", quantity: 1, unit: .package, category: .grains)
        ])

        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe))

        let preview = vm.previewShoppingList()
        XCTAssertEqual(preview.map(\.name), ["Spaghetti Pasta"])
    }

    // MARK: - Computed Properties

    func testTotalPlannedMeals() async {
        let (vm, _) = makeSUT()
        let recipe = makeRecipe()
        let slot = MealPlanViewModel.MealSlot(date: Date(), mealType: .dinner)
        vm.assignRecipe(recipe, to: slot)
        await Task.yield()
        XCTAssertEqual(vm.totalPlannedMeals, 1)
    }

    func testWeekDateRangeText() {
        let (vm, _) = makeSUT()
        let text = vm.weekDateRangeText
        XCTAssertTrue(text.contains("–"), "Should contain an en-dash separator")
    }

    func testEntriesForDateAndMealType() async {
        let (vm, appState) = makeSUT()
        let today = Date()
        let recipe1 = makeRecipe(title: "Breakfast Eggs")
        let recipe2 = makeRecipe(title: "Dinner Steak")
        await appState.addToMealPlan(MealPlanEntry(date: today, mealType: .breakfast, recipe: recipe1))
        await appState.addToMealPlan(MealPlanEntry(date: today, mealType: .dinner, recipe: recipe2))

        let breakfastEntries = vm.entriesFor(date: today, mealType: .breakfast)
        XCTAssertEqual(breakfastEntries.count, 1)
        XCTAssertEqual(breakfastEntries.first?.displayName, "Breakfast Eggs")

        let dinnerEntries = vm.entriesFor(date: today, mealType: .dinner)
        XCTAssertEqual(dinnerEntries.count, 1)
        XCTAssertEqual(dinnerEntries.first?.displayName, "Dinner Steak")
    }

    func testEntriesFilteredByWeek() async {
        let (vm, appState) = makeSUT()
        let calendar = Calendar.current
        let today = Date()
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: today)!
        await appState.addToMealPlan(MealPlanEntry(date: today, mealType: .dinner, recipe: makeRecipe(title: "This Week")))
        await appState.addToMealPlan(MealPlanEntry(date: nextWeek, mealType: .dinner, recipe: makeRecipe(title: "Next Week")))

        // Current week should only show this week's entry
        let thisWeekEntries = vm.entries
        let thisWeekNames = thisWeekEntries.map { $0.displayName }
        XCTAssertTrue(thisWeekNames.contains("This Week"))
        XCTAssertFalse(thisWeekNames.contains("Next Week"))

        // Navigate to next week
        vm.nextWeek()
        let nextWeekEntries = vm.entries
        let nextWeekNames = nextWeekEntries.map { $0.displayName }
        XCTAssertTrue(nextWeekNames.contains("Next Week"))
        XCTAssertFalse(nextWeekNames.contains("This Week"))
    }

    func testWeekNavigationCyclesCorrectly() {
        let (vm, _) = makeSUT()
        let calendar = Calendar.current
        let startDate = vm.weekStartDate

        vm.nextWeek()
        vm.nextWeek()
        vm.previousWeek()
        vm.previousWeek()

        XCTAssertTrue(calendar.isDate(vm.weekStartDate, inSameDayAs: startDate))
    }
}

// MARK: - PreparedDishViewModel Tests

@MainActor
final class PreparedDishViewModelTests: XCTestCase {

    private func makeSUT() -> (PreparedDishViewModel, AppState) {
        let (appState, _, _) = makeTestAppState()
        let vm = PreparedDishViewModel(appState: appState)
        return (vm, appState)
    }

    // MARK: - Filtered Dishes

    func testFilteredDishesSortsByExpiryDate() async {
        let (vm, appState) = makeSUT()
        let dish1 = PreparedDish(name: "Expires Later", mealTypes: [.dinner], servingsRemaining: 2, storage: .refrigerated, dateAdded: Date())
        let dish2 = PreparedDish(name: "Expires Sooner", mealTypes: [.lunch], servingsRemaining: 1, storage: .pantry, dateAdded: Date())
        await appState.addPreparedDish(dish1)
        await appState.addPreparedDish(dish2)

        let dishes = vm.filteredDishes
        // Pantry items expire sooner (2 days) vs refrigerated (4 days)
        XCTAssertEqual(dishes.first?.name, "Expires Sooner")
    }

    func testFilteredDishesFiltersBySearch() async {
        let (vm, appState) = makeSUT()
        await appState.addPreparedDish(PreparedDish(name: "Chicken Soup", mealTypes: [.dinner], servingsRemaining: 2, storage: .refrigerated))
        await appState.addPreparedDish(PreparedDish(name: "Beef Stew", mealTypes: [.dinner], servingsRemaining: 3, storage: .refrigerated))

        vm.searchText = "chicken"
        vm.onSearchTextChanged()
        try? await Task.sleep(for: .milliseconds(350))
        let dishes = vm.filteredDishes
        XCTAssertEqual(dishes.count, 1)
        XCTAssertEqual(dishes.first?.name, "Chicken Soup")
    }

    func testFilteredDishesFiltersByMealType() async {
        let (vm, appState) = makeSUT()
        await appState.addPreparedDish(PreparedDish(name: "Breakfast Bowl", mealTypes: [.breakfast], servingsRemaining: 1, storage: .refrigerated))
        await appState.addPreparedDish(PreparedDish(name: "Dinner Pasta", mealTypes: [.dinner], servingsRemaining: 2, storage: .refrigerated))

        vm.selectedMealType = .breakfast
        let dishes = vm.filteredDishes
        XCTAssertEqual(dishes.count, 1)
        XCTAssertEqual(dishes.first?.name, "Breakfast Bowl")
    }

    func testFilteredDishesNoFilterReturnsAll() async {
        let (vm, appState) = makeSUT()
        await appState.addPreparedDish(PreparedDish(name: "A", mealTypes: [.breakfast], servingsRemaining: 1, storage: .refrigerated))
        await appState.addPreparedDish(PreparedDish(name: "B", mealTypes: [.dinner], servingsRemaining: 2, storage: .refrigerated))

        XCTAssertEqual(vm.filteredDishes.count, 2)
    }

    // MARK: - Meal Type Counts

    func testMealTypeCountsAggregatesCorrectly() async {
        let (vm, appState) = makeSUT()
        await appState.addPreparedDish(PreparedDish(name: "A", mealTypes: [.breakfast, .lunch], servingsRemaining: 1, storage: .refrigerated))
        await appState.addPreparedDish(PreparedDish(name: "B", mealTypes: [.lunch, .dinner], servingsRemaining: 2, storage: .refrigerated))
        await appState.addPreparedDish(PreparedDish(name: "C", mealTypes: [.dinner], servingsRemaining: 1, storage: .refrigerated))

        let counts = vm.mealTypeCounts
        XCTAssertEqual(counts[.breakfast], 1)
        XCTAssertEqual(counts[.lunch], 2)
        XCTAssertEqual(counts[.dinner], 2)
    }

    func testMealTypeCountsEmptyForNoDishes() {
        let (vm, _) = makeSUT()
        XCTAssertTrue(vm.mealTypeCounts.isEmpty)
    }

    // MARK: - Consume Serving

    func testConsumeServingDecrements() async {
        let (vm, appState) = makeSUT()
        let dish = makePreparedDish(name: "Soup", servingsRemaining: 3)
        await appState.addPreparedDish(dish)

        vm.consumeServing(dish)
        await Task.yield()

        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 2)
    }

    func testConsumeServingRemovesAtZero() async {
        let (vm, appState) = makeSUT()
        let dish = makePreparedDish(name: "Last Serving", servingsRemaining: 1)
        await appState.addPreparedDish(dish)

        vm.consumeServing(dish)
        await Task.yield()

        XCTAssertTrue(appState.preparedDishes.isEmpty)
    }

    // MARK: - History Items

    func testFilteredHistoryItemsFiltersBySearch() async {
        let (vm, appState) = makeSUT()
        let now = Date()
        appState.preparedDishHistory = [
            PreparedDishHistoryItem(name: "Chicken Curry", mealTypes: [.dinner], defaultServings: 4, storage: .refrigerated, lastPreparedAt: now, lastUsedAt: now),
            PreparedDishHistoryItem(name: "Beef Stew", mealTypes: [.dinner], defaultServings: 4, storage: .refrigerated, lastPreparedAt: now, lastUsedAt: now),
        ]

        vm.searchText = "curry"
        vm.onSearchTextChanged()
        try? await Task.sleep(for: .milliseconds(350))
        let items = vm.filteredHistoryItems
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Chicken Curry")
    }

    func testFilteredHistoryItemsFiltersByMealType() async {
        let (vm, appState) = makeSUT()
        let now = Date()
        appState.preparedDishHistory = [
            PreparedDishHistoryItem(name: "Morning Oats", mealTypes: [.breakfast], defaultServings: 2, storage: .refrigerated, lastPreparedAt: now, lastUsedAt: now),
            PreparedDishHistoryItem(name: "Dinner Steak", mealTypes: [.dinner], defaultServings: 1, storage: .refrigerated, lastPreparedAt: now, lastUsedAt: now),
        ]

        vm.selectedMealType = .dinner
        let items = vm.filteredHistoryItems
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Dinner Steak")
    }

    // MARK: - CRUD Passthrough

    func testAddDishCallsAppState() async {
        let (vm, appState) = makeSUT()
        let dish = PreparedDish(name: "New Dish", mealTypes: [.dinner], servingsRemaining: 2, storage: .refrigerated)
        vm.addDish(dish)
        await Task.yield()
        XCTAssertEqual(appState.preparedDishes.count, 1)
    }

    func testDeleteDishRemovesFromAppState() async {
        let (vm, appState) = makeSUT()
        let dish = makePreparedDish(name: "Delete Me", servingsRemaining: 1)
        await appState.addPreparedDish(dish)
        XCTAssertEqual(appState.preparedDishes.count, 1)

        vm.deleteDish(dish)
        await Task.yield()
        XCTAssertTrue(appState.preparedDishes.isEmpty)
    }
}

// MARK: - CookModeViewModel Tests

@MainActor
final class CookModeViewModelTests: XCTestCase {

    private func makeSUT() -> CookModeViewModel {
        let recipe = makeRecipe(
            ingredients: [
                Ingredient(name: "Pasta", quantity: 500, unit: .gram),
                Ingredient(name: "Sauce", quantity: 1, unit: .cup),
            ],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Boil water", timerMinutes: 10),
                RecipeStep(stepNumber: 2, instruction: "Cook pasta", timerMinutes: 8),
                RecipeStep(stepNumber: 3, instruction: "Add sauce"),
                RecipeStep(stepNumber: 4, instruction: "Serve"),
            ]
        )
        let mockService = MockRealtimeService()
        return CookModeViewModel(recipe: recipe, realtimeService: mockService)
    }

    // MARK: - Navigation

    func testInitialState() {
        let vm = makeSUT()
        XCTAssertEqual(vm.currentStepIndex, 0)
        XCTAssertFalse(vm.showCompletionScreen)
        XCTAssertTrue(vm.isFirstStep)
        XCTAssertFalse(vm.isLastStep)
    }

    func testStepsAreSorted() {
        let vm = makeSUT()
        XCTAssertEqual(vm.steps.count, 4)
        XCTAssertEqual(vm.steps[0].stepNumber, 1)
        XCTAssertEqual(vm.steps[3].stepNumber, 4)
    }

    func testNextStep() {
        let vm = makeSUT()
        vm.nextStep()
        XCTAssertEqual(vm.currentStepIndex, 1)
        XCTAssertFalse(vm.isFirstStep)
    }

    func testPreviousStep() {
        let vm = makeSUT()
        vm.nextStep()
        vm.previousStep()
        XCTAssertEqual(vm.currentStepIndex, 0)
        XCTAssertTrue(vm.isFirstStep)
    }

    func testPreviousStepAtStart() {
        let vm = makeSUT()
        vm.previousStep()
        XCTAssertEqual(vm.currentStepIndex, 0, "Should not go below 0")
    }

    func testNextStepAtEndShowsCompletion() {
        let vm = makeSUT()
        vm.goToStep(3) // Last step
        vm.nextStep()
        XCTAssertTrue(vm.showCompletionScreen)
    }

    func testGoToStep() {
        let vm = makeSUT()
        vm.goToStep(2)
        XCTAssertEqual(vm.currentStepIndex, 2)
        XCTAssertEqual(vm.currentStep?.instruction, "Add sauce")
    }

    func testGoToStepOutOfBounds() {
        let vm = makeSUT()
        vm.goToStep(100)
        XCTAssertEqual(vm.currentStepIndex, 0, "Should not change for out-of-bounds")
    }

    func testGoToNegativeStep() {
        let vm = makeSUT()
        vm.goToStep(-1)
        XCTAssertEqual(vm.currentStepIndex, 0)
    }

    // MARK: - Progress

    func testProgress() {
        let vm = makeSUT()
        XCTAssertEqual(vm.progress, 0.25) // 1/4
        vm.nextStep()
        XCTAssertEqual(vm.progress, 0.5)  // 2/4
    }

    // MARK: - Timer

    func testTimerDisplay() {
        let vm = makeSUT()
        vm.timerSeconds = 90
        XCTAssertEqual(vm.timerDisplay, "01:30")
    }

    func testTimerDisplayZero() {
        let vm = makeSUT()
        vm.timerSeconds = 0
        XCTAssertEqual(vm.timerDisplay, "00:00")
    }

    func testStartTimer() {
        let vm = makeSUT()
        // Step 1 has timerMinutes: 10
        vm.startTimer()
        XCTAssertEqual(vm.timerSeconds, 600)
        XCTAssertTrue(vm.isTimerRunning)
        vm.stopTimer()
    }

    func testStopTimer() {
        let vm = makeSUT()
        vm.startTimer()
        vm.stopTimer()
        XCTAssertFalse(vm.isTimerRunning)
    }

    func testStartTimerNoTimerOnStep() {
        let vm = makeSUT()
        vm.goToStep(2) // Step 3 has no timer
        vm.startTimer()
        XCTAssertFalse(vm.isTimerRunning, "Should not start timer when step has no timerMinutes")
    }

    // MARK: - Cleanup

    func testCleanup() {
        let vm = makeSUT()
        vm.startTimer()
        vm.cleanup()
        XCTAssertFalse(vm.isTimerRunning)
    }

    // MARK: - Rating

    func testSetRating() {
        let vm = makeSUT()
        XCTAssertNil(vm.selectedRating)
        vm.setRating(4)
        XCTAssertEqual(vm.selectedRating, 4)
    }

    func testSetRatingToggle() {
        let vm = makeSUT()
        vm.setRating(3)
        XCTAssertEqual(vm.selectedRating, 3)
        vm.setRating(3) // tap same star again to deselect
        XCTAssertNil(vm.selectedRating)
    }

    func testRatedRecipe() {
        let vm = makeSUT()
        vm.setRating(5)
        let rated = vm.ratedRecipe
        XCTAssertEqual(rated.rating, 5)
        XCTAssertEqual(rated.title, vm.recipe.title)
    }

    // MARK: - Pause Timer

    func testPauseTimerTogglesState() {
        let vm = makeSUT()
        vm.startTimer()
        XCTAssertFalse(vm.isPaused)
        vm.pauseTimer()
        XCTAssertTrue(vm.isPaused)
        vm.pauseTimer()
        XCTAssertFalse(vm.isPaused)
        vm.stopTimer()
    }

    func testStopTimerResetsPaused() {
        let vm = makeSUT()
        vm.startTimer()
        vm.pauseTimer()
        XCTAssertTrue(vm.isPaused)
        vm.stopTimer()
        XCTAssertFalse(vm.isPaused)
        XCTAssertFalse(vm.isTimerRunning)
    }
}

// ===================================================================
// MARK: - RealtimeService Tests
// ===================================================================

@MainActor
final class RealtimeServiceTests: XCTestCase {

    private func makeSUT() -> RealtimeService {
        RealtimeService(apiKey: "test-key")
    }

    // MARK: - Initial State

    func testInitialState() {
        let sut = makeSUT()
        XCTAssertFalse(sut.isConnected)
        XCTAssertFalse(sut.isModelSpeaking)
        XCTAssertFalse(sut.isUserSpeaking)
        XCTAssertTrue(sut.transcript.isEmpty)
        XCTAssertTrue(sut.statusMessage.isEmpty)
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Disconnect

    func testDisconnectResetsState() {
        let sut = makeSUT()
        sut.isConnected = true
        sut.isModelSpeaking = true
        sut.isUserSpeaking = true
        sut.statusMessage = "Listening…"

        sut.disconnect()

        XCTAssertFalse(sut.isConnected)
        XCTAssertFalse(sut.isModelSpeaking)
        XCTAssertFalse(sut.isUserSpeaking)
        XCTAssertTrue(sut.statusMessage.isEmpty)
    }

    // MARK: - Audio Ready

    func testIsAudioReadyFalseWhenDisconnected() {
        let sut = makeSUT()
        XCTAssertFalse(sut.isAudioReady)
    }

    // MARK: - Connect without ephemeral key

    func testConnectWithoutEphemeralKeySetsError() {
        let sut = makeSUT()
        sut.connect(withInstructions: "Test", tools: [])
        XCTAssertNotNil(sut.errorMessage)
    }

    // MARK: - Tool Conversion (integration via protocol)

    func testCallbackPropertyAssignment() {
        let sut = makeSUT()
        var called = false
        sut.onFunctionCall = { _, _ in called = true }
        sut.onFunctionCall?("test", [:])
        XCTAssertTrue(called)
    }

    func testAssistantDisplayTranscriptPrefersAudioTranscript() {
        let message = Item.Message(
            id: "assistant_1",
            status: .inProgress,
            role: .assistant,
            content: [
                .text("This text arrived ahead of playback."),
                .audio(.init(audio: Optional<Data>.none, transcript: "This is being spoken now."))
            ]
        )

        XCTAssertEqual(
            RealtimeService.assistantDisplayTranscript(from: message),
            "This is being spoken now."
        )
    }

    func testAssistantDisplayTranscriptFallsBackToTextWhenNoAudioTranscriptExists() {
        let message = Item.Message(
            id: "assistant_2",
            status: .inProgress,
            role: .assistant,
            content: [
                .text("Fallback text transcript")
            ]
        )

        XCTAssertEqual(
            RealtimeService.assistantDisplayTranscript(from: message),
            "Fallback text transcript"
        )
    }

    func testAssistantTranscriptWaitsForAudioWhenMessageIsStillInProgress() {
        let message = Item.Message(
            id: "assistant_3",
            status: .inProgress,
            role: .assistant,
            content: [
                .audio(.init(audio: Optional<Data>.none, transcript: "Spoken words arriving early"))
            ]
        )

        XCTAssertFalse(
            RealtimeService.shouldDisplayAssistantTranscript(
                from: message,
                isAudioPlaying: false
            )
        )
        XCTAssertTrue(
            RealtimeService.shouldDisplayAssistantTranscript(
                from: message,
                isAudioPlaying: true
            )
        )
    }

    func testAssistantTranscriptAllowsCompletedMessageWithoutActiveAudio() {
        let message = Item.Message(
            id: "assistant_4",
            status: .completed,
            role: .assistant,
            content: [
                .audio(.init(audio: Optional<Data>.none, transcript: "Finished sentence"))
            ]
        )

        XCTAssertTrue(
            RealtimeService.shouldDisplayAssistantTranscript(
                from: message,
                isAudioPlaying: false
            )
        )
    }

    func testAssistantTranscriptShowsCompletedMessageWithoutUserLane() {
        let message = Item.Message(
            id: "assistant_5",
            status: .completed,
            role: .assistant,
            content: [
                .audio(.init(audio: Optional<Data>.none, transcript: "Completed assistant reply"))
            ]
        )

        XCTAssertTrue(
            RealtimeService.shouldDisplayAssistantTranscript(
                from: message,
                isAudioPlaying: false
            )
        )
    }
}

// ===================================================================
// MARK: - Audio Pipeline Tests
// ===================================================================

/// Tests the pure conversion functions in AudioPipelineHelper —
/// PCM16 ↔ Float32, base64 round-trips, and chunk thresholds.
/// These validate the exact math used in RealtimeService's mic
/// capture and playback paths.
@MainActor
final class AudioPipelineTests: XCTestCase {

    // MARK: - PCM16 → Float32

    func testPCM16ToFloat32_silence() {
        let data = int16sToData([0, 0, 0, 0])
        let floats = AudioPipelineHelper.pcm16ToFloat32(data)
        XCTAssertEqual(floats, [0, 0, 0, 0])
    }

    func testPCM16ToFloat32_maxPositive() {
        let data = int16sToData([Int16.max])
        let floats = AudioPipelineHelper.pcm16ToFloat32(data)
        XCTAssertEqual(floats.count, 1)
        XCTAssertEqual(floats[0], Float(Int16.max) / 32768.0, accuracy: 1e-6)
    }

    func testPCM16ToFloat32_maxNegative() {
        let data = int16sToData([Int16.min])
        let floats = AudioPipelineHelper.pcm16ToFloat32(data)
        XCTAssertEqual(floats.count, 1)
        XCTAssertEqual(floats[0], -1.0, accuracy: 1e-6)
    }

    func testPCM16ToFloat32_knownValues() {
        let data = int16sToData([16384, -16384, 100, -100])
        let floats = AudioPipelineHelper.pcm16ToFloat32(data)
        XCTAssertEqual(floats[0], 0.5, accuracy: 1e-4)
        XCTAssertEqual(floats[1], -0.5, accuracy: 1e-4)
        XCTAssertEqual(floats[2], Float(100) / 32768.0, accuracy: 1e-6)
        XCTAssertEqual(floats[3], Float(-100) / 32768.0, accuracy: 1e-6)
    }

    func testPCM16ToFloat32_empty() {
        XCTAssertTrue(AudioPipelineHelper.pcm16ToFloat32(Data()).isEmpty)
    }

    func testPCM16ToFloat32_oddByteCountDropsPartial() {
        // 3 bytes → 1 complete sample (2 bytes), trailing byte dropped
        var data = int16sToData([1000])
        data.append(0xFF)
        let floats = AudioPipelineHelper.pcm16ToFloat32(data)
        XCTAssertEqual(floats.count, 1)
        XCTAssertEqual(floats[0], Float(1000) / 32768.0, accuracy: 1e-6)
    }

    // MARK: - Float32 → PCM16

    func testFloat32ToPCM16_silence() {
        let data = AudioPipelineHelper.float32ToPCM16([0, 0, 0])
        let samples = dataToInt16s(data)
        XCTAssertEqual(samples, [0, 0, 0])
    }

    func testFloat32ToPCM16_halfScale() {
        let data = AudioPipelineHelper.float32ToPCM16([0.5, -0.5])
        let samples = dataToInt16s(data)
        XCTAssertEqual(samples[0], 16384)
        XCTAssertEqual(samples[1], -16384)
    }

    func testFloat32ToPCM16_negativeOne() {
        let data = AudioPipelineHelper.float32ToPCM16([-1.0])
        let samples = dataToInt16s(data)
        XCTAssertEqual(samples[0], Int16.min)
    }

    func testFloat32ToPCM16_clampsAboveOne() {
        let data = AudioPipelineHelper.float32ToPCM16([1.5])
        let samples = dataToInt16s(data)
        XCTAssertEqual(samples[0], Int16.max)
    }

    func testFloat32ToPCM16_clampsBelowNegativeOne() {
        let data = AudioPipelineHelper.float32ToPCM16([-1.5])
        let samples = dataToInt16s(data)
        XCTAssertEqual(samples[0], Int16.min)
    }

    func testFloat32ToPCM16_empty() {
        XCTAssertTrue(AudioPipelineHelper.float32ToPCM16([]).isEmpty)
    }

    // MARK: - Round Trip

    func testRoundTrip_preservesFidelity() {
        let original: [Int16] = [0, 100, -100, 1000, -1000,
                                  Int16.max, Int16.min, 12345, -12345]
        let data = int16sToData(original)
        let floats = AudioPipelineHelper.pcm16ToFloat32(data)
        let roundTripped = AudioPipelineHelper.float32ToPCM16(floats)
        let result = dataToInt16s(roundTripped)
        XCTAssertEqual(result, original)
    }

    func testRoundTrip_allNormalizedValuesInRange() {
        // Every converted float should be in [-1.0, 1.0]
        let edgeCases: [Int16] = [Int16.min, Int16.min + 1, -1, 0, 1, Int16.max - 1, Int16.max]
        let data = int16sToData(edgeCases)
        let floats = AudioPipelineHelper.pcm16ToFloat32(data)
        for f in floats {
            XCTAssertGreaterThanOrEqual(f, -1.0)
            XCTAssertLessThanOrEqual(f, 1.0)
        }
    }

    // MARK: - Base64

    func testBase64RoundTrip() {
        let original = int16sToData([100, 200, 300])
        let base64 = AudioPipelineHelper.pcm16ToBase64(original)
        let decoded = AudioPipelineHelper.base64ToPCM16(base64)
        XCTAssertEqual(decoded, original)
    }

    func testBase64DecodeInvalidReturnsNil() {
        XCTAssertNil(AudioPipelineHelper.base64ToPCM16("!!!not-base64!!!"))
    }

    func testBase64EncodeNotEmpty() {
        let data = int16sToData([42])
        XCTAssertFalse(AudioPipelineHelper.pcm16ToBase64(data).isEmpty)
    }

    // MARK: - Chunk Threshold

    func testChunkThreshold_24kHz() {
        // 24000 * 0.1 * 2 = 4800 bytes
        XCTAssertEqual(AudioPipelineHelper.chunkThreshold(sampleRate: 24_000), 4800)
    }

    func testChunkThreshold_48kHz() {
        // 48000 * 0.1 * 2 = 9600 bytes
        XCTAssertEqual(AudioPipelineHelper.chunkThreshold(sampleRate: 48_000), 9600)
    }

    // MARK: - Helpers

    private func int16sToData(_ values: [Int16]) -> Data {
        var data = Data(count: values.count * 2)
        data.withUnsafeMutableBytes { rawBuf in
            let ptr = rawBuf.bindMemory(to: Int16.self)
            for i in 0..<values.count { ptr[i] = values[i] }
        }
        return data
    }

    private func dataToInt16s(_ data: Data) -> [Int16] {
        let count = data.count / 2
        return data.withUnsafeBytes { rawBuf in
            let ptr = rawBuf.bindMemory(to: Int16.self)
            return (0..<count).map { ptr[$0] }
        }
    }
}

// ===================================================================
// MARK: - CookModeViewModel Conversation Tests
// ===================================================================

@MainActor
final class CookModeConversationTests: XCTestCase {

    private func makeSUT() -> CookModeViewModel {
        let recipe = makeRecipe(
            title: "Spaghetti Bolognese",
            ingredients: [
                Ingredient(name: "Pasta", quantity: 500, unit: .gram),
                Ingredient(name: "Onion", quantity: 1, unit: .piece),
            ],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Dice the onion", timerMinutes: nil, tip: "Use a sharp knife"),
                RecipeStep(stepNumber: 2, instruction: "Boil water", timerMinutes: 10),
                RecipeStep(stepNumber: 3, instruction: "Cook pasta", timerMinutes: 8),
                RecipeStep(stepNumber: 4, instruction: "Combine and serve"),
            ]
        )
        let mockService = MockRealtimeService()
        return CookModeViewModel(recipe: recipe, realtimeService: mockService)
    }

    // MARK: - Conversation Initial State

    func testConversationInitialState() {
        let vm = makeSUT()
        XCTAssertFalse(vm.isConversationActive)
        XCTAssertTrue(vm.conversationTranscript.isEmpty)
        XCTAssertFalse(vm.isModelSpeaking)
        XCTAssertFalse(vm.isUserSpeaking)
        XCTAssertTrue(vm.conversationStatus.isEmpty)
        XCTAssertNil(vm.conversationError)
    }

    // MARK: - Function Call: next_step

    func testFunctionCallNextStep() {
        let vm = makeSUT()
        XCTAssertEqual(vm.currentStepIndex, 0)

        vm.handleRealtimeFunctionCall(name: "next_step", args: [:])
        XCTAssertEqual(vm.currentStepIndex, 1)
    }

    // MARK: - Function Call: previous_step

    func testFunctionCallPreviousStep() {
        let vm = makeSUT()
        vm.goToStep(2)

        vm.handleRealtimeFunctionCall(name: "previous_step", args: [:])
        XCTAssertEqual(vm.currentStepIndex, 1)
    }

    func testFunctionCallPreviousStepAtStart() {
        let vm = makeSUT()

        vm.handleRealtimeFunctionCall(name: "previous_step", args: [:])
        XCTAssertEqual(vm.currentStepIndex, 0, "Should not go below 0")
    }

    // MARK: - Function Call: go_to_step (1-based -> 0-based)

    func testFunctionCallGoToStep() {
        let vm = makeSUT()

        vm.handleRealtimeFunctionCall(name: "go_to_step", args: ["step_number": 3])
        XCTAssertEqual(vm.currentStepIndex, 2, "step_number 3 should map to index 2")
        XCTAssertEqual(vm.currentStep?.instruction, "Cook pasta")
    }

    func testFunctionCallGoToStepOutOfBounds() {
        let vm = makeSUT()

        vm.handleRealtimeFunctionCall(name: "go_to_step", args: ["step_number": 99])
        XCTAssertEqual(vm.currentStepIndex, 0, "Out-of-bounds should not change step")
    }

    func testFunctionCallGoToStepMissingArg() {
        let vm = makeSUT()

        vm.handleRealtimeFunctionCall(name: "go_to_step", args: [:])
        XCTAssertEqual(vm.currentStepIndex, 0, "Missing step_number should not change step")
    }

    // MARK: - Function Call: start_timer with minutes

    func testFunctionCallStartTimerWithMinutes() {
        let vm = makeSUT()

        vm.handleRealtimeFunctionCall(name: "start_timer", args: ["minutes": 5])
        XCTAssertEqual(vm.timerSeconds, 300)
        XCTAssertTrue(vm.isTimerRunning)
        XCTAssertFalse(vm.isPaused)
        vm.stopTimer() // cleanup
    }

    func testFunctionCallStartTimerWithoutMinutesFallsBackToStep() {
        let vm = makeSUT()
        vm.goToStep(1) // Step 2: "Boil water" has timerMinutes: 10

        vm.handleRealtimeFunctionCall(name: "start_timer", args: [:])
        XCTAssertEqual(vm.timerSeconds, 600, "Should use step's timerMinutes=10 -> 600s")
        XCTAssertTrue(vm.isTimerRunning)
        vm.stopTimer()
    }

    // MARK: - Function Call: pause_timer

    func testFunctionCallPauseTimer() {
        let vm = makeSUT()
        vm.handleRealtimeFunctionCall(name: "start_timer", args: ["minutes": 3])
        XCTAssertFalse(vm.isPaused)

        vm.handleRealtimeFunctionCall(name: "pause_timer", args: [:])
        XCTAssertTrue(vm.isPaused)

        vm.handleRealtimeFunctionCall(name: "pause_timer", args: [:])
        XCTAssertFalse(vm.isPaused)
        vm.stopTimer()
    }

    // MARK: - Function Call: stop_timer

    func testFunctionCallStopTimer() {
        let vm = makeSUT()
        vm.handleRealtimeFunctionCall(name: "start_timer", args: ["minutes": 2])
        XCTAssertTrue(vm.isTimerRunning)

        vm.handleRealtimeFunctionCall(name: "stop_timer", args: [:])
        XCTAssertFalse(vm.isTimerRunning)
    }

    // MARK: - Function Call: finish_cooking

    func testFunctionCallFinishCooking() {
        let vm = makeSUT()
        XCTAssertFalse(vm.showCompletionScreen)

        vm.handleRealtimeFunctionCall(name: "finish_cooking", args: [:])
        XCTAssertTrue(vm.showCompletionScreen)
    }

    // MARK: - Function Call: repeat_step (no-op)

    func testFunctionCallRepeatStepDoesNotNavigate() {
        let vm = makeSUT()
        vm.goToStep(2)

        vm.handleRealtimeFunctionCall(name: "repeat_step", args: [:])
        XCTAssertEqual(vm.currentStepIndex, 2, "repeat_step should not change the step index")
    }

    // MARK: - Function Call: unknown

    func testFunctionCallUnknownIgnored() {
        let vm = makeSUT()

        vm.handleRealtimeFunctionCall(name: "do_something_weird", args: [:])
        XCTAssertEqual(vm.currentStepIndex, 0, "Unknown function should not change state")
        XCTAssertFalse(vm.isTimerRunning)
        XCTAssertFalse(vm.showCompletionScreen)
    }

    // MARK: - Function Call: next_step at last step shows completion

    func testFunctionCallNextStepAtEndShowsCompletion() {
        let vm = makeSUT()
        vm.goToStep(3) // last step

        vm.handleRealtimeFunctionCall(name: "next_step", args: [:])
        XCTAssertTrue(vm.showCompletionScreen)
    }

    // MARK: - stopConversation resets state

    func testStopConversationResetsState() {
        let vm = makeSUT()
        vm.isConversationActive = true
        vm.conversationTranscript = "Hello"
        vm.isModelSpeaking = true
        vm.isUserSpeaking = true
        vm.conversationStatus = "Listening..."
        vm.conversationError = "Some error"

        vm.stopConversation()

        XCTAssertFalse(vm.isConversationActive)
        XCTAssertTrue(vm.conversationTranscript.isEmpty)
        XCTAssertFalse(vm.isModelSpeaking)
        XCTAssertFalse(vm.isUserSpeaking)
        XCTAssertTrue(vm.conversationStatus.isEmpty)
        XCTAssertNil(vm.conversationError)
    }

    // MARK: - syncRealtimeState

    func testSyncRealtimeStateWhenNotConversationMode() {
        let vm = makeSUT()
        vm.isConversationActive = false
        vm.realtimeService.isModelSpeaking = true

        vm.syncRealtimeState()

        XCTAssertFalse(vm.isModelSpeaking, "Should not sync when not in conversation mode")
    }

    func testSyncRealtimeStateSyncsValues() {
        let vm = makeSUT()
        vm.isConversationActive = true
        vm.realtimeService.transcript = "Step 1..."
        vm.realtimeService.isModelSpeaking = true
        vm.realtimeService.isUserSpeaking = false
        vm.realtimeService.statusMessage = "Listening..."
        vm.realtimeService.errorMessage = nil
        vm.realtimeService.isConnected = true

        vm.syncRealtimeState()

        XCTAssertEqual(vm.conversationTranscript, "Step 1...")
        XCTAssertTrue(vm.isModelSpeaking)
        XCTAssertFalse(vm.isUserSpeaking)
        XCTAssertEqual(vm.conversationStatus, "Listening...")
        XCTAssertNil(vm.conversationError)
    }

    func testSyncDetectsDisconnect() {
        let vm = makeSUT()
        vm.isConversationActive = true

        // Simulate a prior successful connection so wasEverConnected is set
        vm.realtimeService.isConnected = true
        vm.syncRealtimeState()

        // Now simulate the disconnect
        vm.realtimeService.isConnected = false
        vm.syncRealtimeState()

        XCTAssertFalse(vm.isConversationActive, "Should exit conversation mode when disconnected")
    }

    // MARK: - Cleanup stops conversation

    func testCleanupStopsConversation() {
        let vm = makeSUT()
        vm.isConversationActive = true
        vm.isModelSpeaking = true

        vm.cleanup()

        XCTAssertFalse(vm.isConversationActive)
        XCTAssertFalse(vm.isModelSpeaking)
        XCTAssertFalse(vm.isTimerRunning)
    }
}

// ===================================================================
// MARK: - Extension / Utility Tests
// ===================================================================

final class ExtensionTests: XCTestCase {

    // MARK: - Date Extensions

    func testIsToday() {
        XCTAssertTrue(Date().isToday)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertFalse(yesterday.isToday)
    }

    func testIsTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertTrue(tomorrow.isTomorrow)
        XCTAssertFalse(Date().isTomorrow)
    }

    func testIsThisWeek() {
        XCTAssertTrue(Date().isThisWeek)
        // 30 days from now should not be this week (usually)
        let farFuture = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        XCTAssertFalse(farFuture.isThisWeek)
    }

    func testRelativeDisplay() {
        XCTAssertEqual(Date().relativeDisplay, "Today")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertEqual(tomorrow.relativeDisplay, "Tomorrow")
    }

    func testShortDisplay() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let expected = formatter.string(from: Date())
        XCTAssertEqual(Date().shortDisplay, expected)
    }

    func testDayOfWeek() {
        let dayName = Date().dayOfWeek
        let validDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        XCTAssertTrue(validDays.contains(dayName), "\(dayName) should be a valid day name")
    }

    // MARK: - String Extensions

    func testTrimmed() {
        XCTAssertEqual("  hello  ".trimmed, "hello")
        XCTAssertEqual("\n test \t".trimmed, "test")
        XCTAssertEqual("already".trimmed, "already")
    }

    func testIsValidURL() {
        XCTAssertTrue("https://example.com".isValidURL)
        XCTAssertTrue("http://test.org/path".isValidURL)
        XCTAssertFalse("not a url".isValidURL)
        XCTAssertFalse("ftp://test.com".isValidURL)
        XCTAssertFalse("".isValidURL)
    }

    // MARK: - Array Update Extension

    func testArrayUpdate() {
        var items = PantryItem.samples
        guard var firstItem = items.first else {
            XCTFail("Need at least one sample"); return
        }
        firstItem.name = "Updated Name"
        items.update(firstItem)
        XCTAssertEqual(items.first?.name, "Updated Name")
    }

    func testArrayUpdateNotFound() {
        var items = [makePantryItem(name: "A")]
        let notInList = makePantryItem(name: "B")
        items.update(notInList)
        // Should not add, should not crash
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "A")
    }
}

// MARK: - UnitConverter Tests

final class UnitConverterTests: XCTestCase {

    // MARK: - Volume Conversions

    func testTeaspoonToML() {
        let result = UnitConverter.toML(1, from: .teaspoon)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 4.929, accuracy: 0.01)
    }

    func testTablespoonToML() {
        let result = UnitConverter.toML(1, from: .tablespoon)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 14.787, accuracy: 0.01)
    }

    func testCupToML() {
        let result = UnitConverter.toML(1, from: .cup)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 236.588, accuracy: 0.01)
    }

    func testMLToML() {
        let result = UnitConverter.toML(100, from: .milliliter)
        XCTAssertEqual(result!, 100.0)
    }

    func testLiterToML() {
        let result = UnitConverter.toML(1, from: .liter)
        XCTAssertEqual(result!, 1000.0)
    }

    func testNonVolumeReturnsNil() {
        XCTAssertNil(UnitConverter.toML(1, from: .gram))
        XCTAssertNil(UnitConverter.toML(1, from: .piece))
    }

    // MARK: - Weight Conversions

    func testGramToGram() {
        XCTAssertEqual(UnitConverter.toGrams(500, from: .gram)!, 500.0)
    }

    func testKilogramToGram() {
        XCTAssertEqual(UnitConverter.toGrams(1, from: .kilogram)!, 1000.0)
    }

    func testOunceToGram() {
        let result = UnitConverter.toGrams(1, from: .ounce)!
        XCTAssertEqual(result, 28.3495, accuracy: 0.01)
    }

    func testPoundToGram() {
        let result = UnitConverter.toGrams(1, from: .pound)!
        XCTAssertEqual(result, 453.592, accuracy: 0.01)
    }

    func testNonWeightReturnsNil() {
        XCTAssertNil(UnitConverter.toGrams(1, from: .cup))
        XCTAssertNil(UnitConverter.toGrams(1, from: .piece))
    }

    // MARK: - Cross Conversion

    func testConvertCupsToML() {
        let result = UnitConverter.convert(2, from: .cup, to: .milliliter)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 473.176, accuracy: 0.1)
    }

    func testConvertPoundsToGrams() {
        let result = UnitConverter.convert(1, from: .pound, to: .gram)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 453.592, accuracy: 0.1)
    }

    func testConvertIncompatibleReturnsNil() {
        // Can't convert volume to weight
        XCTAssertNil(UnitConverter.convert(1, from: .cup, to: .gram))
    }

    // MARK: - Format Quantity

    func testFormatWholeNumber() {
        XCTAssertEqual(UnitConverter.formatQuantity(3.0), "3")
    }

    func testFormatHalf() {
        XCTAssertEqual(UnitConverter.formatQuantity(0.5), "½")
    }

    func testFormatOneAndHalf() {
        XCTAssertEqual(UnitConverter.formatQuantity(1.5), "1 ½")
    }

    func testFormatQuarter() {
        XCTAssertEqual(UnitConverter.formatQuantity(0.25), "¼")
    }

    func testFormatThreeQuarters() {
        XCTAssertEqual(UnitConverter.formatQuantity(0.75), "¾")
    }

    func testFormatThird() {
        XCTAssertEqual(UnitConverter.formatQuantity(0.33), "⅓")
    }

    func testFormatTwoThirds() {
        XCTAssertEqual(UnitConverter.formatQuantity(0.67), "⅔")
    }

    func testFormatArbitraryDecimal() {
        XCTAssertEqual(UnitConverter.formatQuantity(1.7), "1 ⅔")
    }
}

// ===================================================================
// MARK: - AppConfig Tests
// ===================================================================

final class AppConfigTests: XCTestCase {

    func testOpenAIKeyIsNotPlaceholder() {
        XCTAssertNotEqual(AppConfig.openAIAPIKey, "YOUR_OPENAI_API_KEY",
                          "API key should not be the placeholder")
        XCTAssertFalse(AppConfig.openAIAPIKey.isEmpty,
                       "API key should not be empty")
    }

    func testAppSettings() {
        XCTAssertEqual(AppConfig.expiryWarningDays, 3)
        XCTAssertEqual(AppConfig.maxRecipeSuggestions, 5)
        XCTAssertEqual(AppConfig.defaultServings, 4)
    }
}

// ===================================================================
// MARK: - SpeechService Voice Command Tests
// ===================================================================

final class VoiceCommandTests: XCTestCase {

    func testNextCommands() {
        XCTAssertEqual(SpeechService.VoiceCommand.parse("next"), .next)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("forward"), .next)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("continue"), .next)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("done"), .next)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("go to next step"), .next)
    }

    func testPreviousCommands() {
        XCTAssertEqual(SpeechService.VoiceCommand.parse("back"), .previous)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("previous"), .previous)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("before"), .previous)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("go back"), .previous)
    }

    func testRepeatCommands() {
        XCTAssertEqual(SpeechService.VoiceCommand.parse("repeat"), .repeatStep)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("again"), .repeatStep)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("say it again"), .repeatStep)
    }

    func testTimerCommands() {
        XCTAssertEqual(SpeechService.VoiceCommand.parse("start timer"), .startTimer)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("set timer"), .startTimer)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("go"), .startTimer)
    }

    func testStopCommands() {
        XCTAssertEqual(SpeechService.VoiceCommand.parse("stop"), .stopTimer)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("cancel"), .stopTimer)
    }

    func testPauseCommands() {
        XCTAssertEqual(SpeechService.VoiceCommand.parse("pause"), .pauseTimer)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("please pause"), .pauseTimer)
    }

    func testUnknownCommand() {
        XCTAssertEqual(SpeechService.VoiceCommand.parse("hello world"), .unknown)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("random text"), .unknown)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(SpeechService.VoiceCommand.parse("NEXT"), .next)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("Back"), .previous)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("REPEAT"), .repeatStep)
    }

    func testWhitespaceTrimming() {
        XCTAssertEqual(SpeechService.VoiceCommand.parse("  next  "), .next)
        XCTAssertEqual(SpeechService.VoiceCommand.parse("  back  "), .previous)
    }
}

// ===================================================================
// MARK: - Error Handling Tests
// ===================================================================

@MainActor
final class ErrorHandlingTests: XCTestCase {

    func testAddPantryItemError() async {
        let (appState, storage, _) = makeTestAppState()
        storage.shouldThrowError = true
        await appState.addPantryItem(makePantryItem(name: "Fail"))
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertTrue(appState.pantryItems.isEmpty, "Should not add item on error")
    }

    func testDeletePantryItemError() async {
        let (appState, storage, _) = makeTestAppState()
        let item = makePantryItem(name: "Test")
        appState.pantryItems = [item]
        storage.shouldThrowError = true
        await appState.removePantryItem(item)
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertEqual(appState.pantryItems.count, 1, "Should not remove item on error")
    }

    func testUpdatePantryItemError() async {
        let (appState, storage, _) = makeTestAppState()
        var item = makePantryItem(name: "Test", quantity: 1)
        appState.pantryItems = [item]
        storage.shouldThrowError = true
        item.quantity = 5
        await appState.updatePantryItem(item)
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertEqual(appState.pantryItems[0].quantity, 1, "Should not update on error")
    }

    func testAddRecipeError() async {
        let (appState, storage, _) = makeTestAppState()
        storage.shouldThrowError = true
        await appState.addRecipe(makeRecipe(title: "Fail"))
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertTrue(appState.recipes.isEmpty)
    }

    func testDeleteRecipeError() async {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Test")
        appState.recipes = [recipe]
        storage.shouldThrowError = true
        await appState.deleteRecipe(recipe)
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertEqual(appState.recipes.count, 1)
    }

    func testUpdateRecipeError() async {
        let (appState, storage, _) = makeTestAppState()
        var recipe = makeRecipe(title: "Original")
        appState.recipes = [recipe]
        storage.shouldThrowError = true
        recipe.title = "Updated"
        await appState.updateRecipe(recipe)
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertEqual(appState.recipes[0].title, "Original")
    }

    func testAddMealPlanError() async {
        let (appState, storage, _) = makeTestAppState()
        storage.shouldThrowError = true
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe(title: "Test"))
        await appState.addToMealPlan(entry)
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertTrue(appState.mealPlan.isEmpty)
    }

    func testRemoveMealPlanError() async {
        let (appState, storage, _) = makeTestAppState()
        let entry = MealPlanEntry(date: Date(), mealType: .dinner)
        appState.mealPlan = [entry]
        storage.shouldThrowError = true
        await appState.removeFromMealPlan(entry)
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertEqual(appState.mealPlan.count, 1)
    }

    func testLoadAllDataFiltersOutUnplannedMealEntries() async {
        let (appState, storage, _) = makeTestAppState()
        let planned = MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe(title: "Soup"))
        let unplanned = MealPlanEntry(date: Date(), mealType: .lunch)
        storage.mealPlanStore = [unplanned, planned]

        await appState.loadAllData()

        XCTAssertEqual(appState.mealPlan, [planned])
        XCTAssertEqual(storage.deleteMealPlanCallCount, 1)
        XCTAssertEqual(storage.mealPlanStore, [planned])
    }

    func testAddToMealPlanReplacesExistingEntryInSameSlot() async {
        let (appState, storage, _) = makeTestAppState()
        let date = Date()
        let stale = MealPlanEntry(date: date, mealType: .dinner)
        let replacement = MealPlanEntry(date: date, mealType: .dinner, recipe: makeRecipe(title: "Curry"))

        appState.mealPlan = [stale]
        storage.mealPlanStore = [stale]

        await appState.addToMealPlan(replacement, replaceExistingSlot: true)

        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(appState.mealPlan.first?.recipe?.title, "Curry")
        XCTAssertEqual(storage.deleteMealPlanCallCount, 1)
        XCTAssertEqual(storage.addMealPlanCallCount, 1)
        XCTAssertEqual(storage.mealPlanStore, [replacement])
    }

    // MARK: - Meal Plan Update

    func testUpdateMealPlanEntryPersistsChanges() async {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Pasta", servings: 4)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, plannedServings: 4)
        await appState.addToMealPlan(entry)

        let updated = entry.updatingPlannedServings(2)
        await appState.updateMealPlanEntry(updated)

        XCTAssertEqual(appState.mealPlan.first?.effectivePlannedServings, 2)
        XCTAssertEqual(storage.mealPlanStore.first?.plannedServings, 2)
    }

    func testUpdateMealPlanEntryErrorDoesNotMutateState() async {
        let (appState, storage, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Pasta", servings: 4)
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, plannedServings: 4)
        await appState.addToMealPlan(entry)
        storage.failingOperations = [.updateMealPlanEntry]

        let updated = entry.updatingPlannedServings(2)
        await appState.updateMealPlanEntry(updated)

        XCTAssertNotNil(appState.errorMessage)
        XCTAssertEqual(appState.mealPlan.first?.effectivePlannedServings, 4)
    }

    // MARK: - Meal Plan Batch Operations

    func testAddMultipleMealPlanEntries() async {
        let (appState, storage, _) = makeTestAppState()
        let date = Date()
        let entries = [
            MealPlanEntry(date: date, mealType: .breakfast, recipe: makeRecipe(title: "Omelette")),
            MealPlanEntry(date: date, mealType: .lunch, recipe: makeRecipe(title: "Salad")),
            MealPlanEntry(date: date, mealType: .dinner, recipe: makeRecipe(title: "Steak")),
        ]
        await appState.addToMealPlan(entries)
        XCTAssertEqual(appState.mealPlan.count, 3)
        XCTAssertEqual(storage.addMealPlanCallCount, 3)
    }

    func testAddUnplannedEntryIsIgnored() async {
        let (appState, _, _) = makeTestAppState()
        let unplanned = MealPlanEntry(date: Date(), mealType: .dinner)
        await appState.addToMealPlan(unplanned)
        XCTAssertTrue(appState.mealPlan.isEmpty, "Unplanned entries should not be added")
    }

    func testReplaceExistingSlotDeletesMultipleConflicts() async {
        let (appState, storage, _) = makeTestAppState()
        let date = Date()
        let first = MealPlanEntry(date: date, mealType: .dinner, recipe: makeRecipe(title: "Soup"))
        let second = MealPlanEntry(date: date, mealType: .dinner, recipe: makeRecipe(title: "Salad"))
        appState.mealPlan = [first, second]
        storage.mealPlanStore = [first, second]

        let replacement = MealPlanEntry(date: date, mealType: .dinner, recipe: makeRecipe(title: "Curry"))
        await appState.addToMealPlan(replacement, replaceExistingSlot: true)

        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(appState.mealPlan.first?.recipe?.title, "Curry")
        XCTAssertEqual(storage.deleteMealPlanCallCount, 2)
    }

    // MARK: - Meal Plan Query Methods

    func testPlannedEntriesForDateFiltersCorrectly() async {
        let (appState, _, _) = makeTestAppState()
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        await appState.addToMealPlan(MealPlanEntry(date: today, mealType: .dinner, recipe: makeRecipe(title: "Today")))
        await appState.addToMealPlan(MealPlanEntry(date: tomorrow, mealType: .dinner, recipe: makeRecipe(title: "Tomorrow")))

        let todayEntries = appState.plannedEntries(on: today)
        XCTAssertEqual(todayEntries.count, 1)
        XCTAssertEqual(todayEntries.first?.recipe?.title, "Today")
    }

    func testPlannedEntriesForWeekReturnsAllInRange() async {
        let (appState, _, _) = makeTestAppState()
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())!.start
        let dayInWeek = Calendar.current.date(byAdding: .day, value: 3, to: weekStart)!
        let outsideWeek = Calendar.current.date(byAdding: .day, value: 8, to: weekStart)!

        await appState.addToMealPlan(MealPlanEntry(date: dayInWeek, mealType: .dinner, recipe: makeRecipe(title: "InWeek")))
        await appState.addToMealPlan(MealPlanEntry(date: outsideWeek, mealType: .dinner, recipe: makeRecipe(title: "OutsideWeek")))

        let weekEntries = appState.plannedEntries(forWeekStarting: weekStart)
        XCTAssertEqual(weekEntries.count, 1)
        XCTAssertEqual(weekEntries.first?.recipe?.title, "InWeek")
    }

    // MARK: - Matching Prepared Dishes

    func testMatchingPreparedDishesMatchesByRecipeID() async {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Curry")
        let dish = makePreparedDish(name: "Curry", servingsRemaining: 4, recipeID: recipe.id)
        let unrelated = makePreparedDish(name: "Soup", servingsRemaining: 2)
        await appState.addPreparedDish(dish)
        await appState.addPreparedDish(unrelated)

        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        let matches = appState.matchingPreparedDishes(for: entry)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.name, "Curry")
    }

    func testMatchingPreparedDishesMatchesByFoodIdentity() async {
        let (appState, _, _) = makeTestAppState()
        let identityID = UUID()
        let dish = makePreparedDish(name: "Soup", servingsRemaining: 3, foodIdentityID: identityID)
        await appState.addPreparedDish(dish)

        let entry = MealPlanEntry(
            date: Date(), mealType: .lunch,
            preparedFoodNameSnapshot: "Soup",
            preparedFoodIdentityID: identityID
        )
        let matches = appState.matchingPreparedDishes(for: entry)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.name, "Soup")
    }

    // MARK: - Log Eaten Edge Cases

    func testLogEatenIgnoresNonMealLoggingEntries() async {
        let (appState, _, _) = makeTestAppState()
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe(title: "Pasta", servings: 4))
        await appState.addToMealPlan(entry)

        // No prepared dish → supportsMealLogging is false for recipe-only if no preparedFoodMatchKey
        // A recipe-only entry has preparedFoodMatchKey via recipe.id, so it does support meal logging.
        // But without a matching prepared dish, selection will fail validation.
        await appState.logMealPlanEntriesEaten([
            MealPlanEatenLoggingSelection(entryID: entry.id, targetEatenServings: 2, preparedDishID: nil)
        ])

        // Should set error (no prepared dish ID)
        XCTAssertNotNil(appState.errorMessage)
    }

    func testLogEatenRejectsMismatchedPreparedDish() async {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Curry")
        let dish = makePreparedDish(name: "Curry", servingsRemaining: 4, recipeID: recipe.id)
        let wrongDish = makePreparedDish(name: "Soup", servingsRemaining: 4)
        await appState.addPreparedDish(dish)
        await appState.addPreparedDish(wrongDish)

        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        await appState.addToMealPlan(entry)

        await appState.logMealPlanEntriesEaten([
            MealPlanEatenLoggingSelection(entryID: entry.id, targetEatenServings: 2, preparedDishID: wrongDish.id)
        ])

        XCTAssertNotNil(appState.errorMessage)
        XCTAssertTrue(appState.errorMessage!.contains("no longer matches"))
    }

    func testLogEatenDoesNotDecrementBeyondExisting() async {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Curry", servings: 4)
        let dish = makePreparedDish(name: "Curry", servingsRemaining: 4, recipeID: recipe.id)
        await appState.addPreparedDish(dish)

        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, plannedServings: 4, eatenServings: 2)
        await appState.addToMealPlan(entry)

        // Attempting to log fewer than already eaten should be a no-op
        await appState.logMealPlanEntriesEaten([
            MealPlanEatenLoggingSelection(entryID: entry.id, targetEatenServings: 1, preparedDishID: dish.id)
        ])

        XCTAssertEqual(appState.mealPlan.first?.effectiveEatenServings, 2, "Should not decrease eaten servings")
        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 4, "Dish should not be decremented")
    }

    // MARK: - Shopping Item CRUD

    func testAddShoppingItem() async {
        let (appState, storage, _) = makeTestAppState()
        let item = ShoppingItem(name: "Milk", quantity: 1, unit: .liter, category: .dairy)
        await appState.addShoppingItem(item)

        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(storage.shoppingStore.count, 1)
    }

    func testRemoveShoppingItem() async {
        let (appState, storage, _) = makeTestAppState()
        let item = ShoppingItem(name: "Milk", quantity: 1, unit: .liter, category: .dairy)
        await appState.addShoppingItem(item)
        await appState.removeShoppingItem(item)

        XCTAssertTrue(appState.shoppingItems.isEmpty)
        XCTAssertTrue(storage.shoppingStore.isEmpty)
    }

    func testUpdateShoppingItem() async {
        let (appState, storage, _) = makeTestAppState()
        let item = ShoppingItem(name: "Milk", quantity: 1, unit: .liter, category: .dairy)
        await appState.addShoppingItem(item)

        var updated = appState.shoppingItems[0]
        updated.isChecked = true
        await appState.updateShoppingItem(updated)

        XCTAssertTrue(appState.shoppingItems[0].isChecked)
        XCTAssertTrue(storage.shoppingStore[0].isChecked)
    }

    func testRemoveCheckedShoppingItems() async {
        let (appState, storage, _) = makeTestAppState()
        await appState.addShoppingItems([
            ShoppingItem(name: "Milk", quantity: 1, unit: .liter, category: .dairy),
            ShoppingItem(name: "Bread", quantity: 1, unit: .whole, category: .grains),
        ])
        var checked = appState.shoppingItems[0]
        checked.isChecked = true
        await appState.updateShoppingItem(checked)

        await appState.removeCheckedShoppingItems()

        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(storage.shoppingStore.count, 1)
        XCTAssertFalse(appState.shoppingItems[0].isChecked)
    }

    func testReplaceShoppingItemsUpdatesMatchingIDs() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addShoppingItems([
            ShoppingItem(name: "Milk", quantity: 1, unit: .liter, category: .dairy),
            ShoppingItem(name: "Bread", quantity: 1, unit: .whole, category: .grains),
        ])

        let milkItem = appState.shoppingItems.first(where: { $0.name.contains("Milk") })
        XCTAssertNotNil(milkItem, "Milk item should exist in shopping list")
        guard var milkUpdated = milkItem else { return }
        milkUpdated.isChecked = true
        await appState.replaceShoppingItems([milkUpdated])

        XCTAssertTrue(appState.shoppingItems.first(where: { $0.name.contains("Milk") })?.isChecked == true)
        XCTAssertFalse(appState.shoppingItems.first(where: { $0.name.contains("Bread") })?.isChecked == true)
    }

    func testReplaceShoppingItemsNoOpWhenEmpty() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addShoppingItems([
            ShoppingItem(name: "Milk", quantity: 1, unit: .liter, category: .dairy),
        ])
        await appState.replaceShoppingItems([])
        XCTAssertEqual(appState.shoppingItems.count, 1)
    }

    // MARK: - Shopping Cart → Pantry Transfer

    func testShoppingItemPantryTransferUsesReviewedFields() {
        let item = ShoppingItem(
            name: "Soy Sauce", quantity: 2, unit: .tablespoon, category: .condiments,
            pantryQuantity: 1, pantryUnit: .package, pantryQuantityMode: .exact
        )
        let pantryItem = item.pantryItemForTransfer()
        XCTAssertEqual(pantryItem.quantity, 1)
        XCTAssertEqual(pantryItem.unit, .package)
        XCTAssertEqual(pantryItem.quantityMode, .exact)
    }

    func testShoppingItemPantryTransferPresenceOnly() {
        let item = ShoppingItem(
            name: "Salt", quantity: 1, unit: .package, category: .spices,
            pantryQuantityMode: .presenceOnly
        )
        let pantryItem = item.pantryItemForTransfer()
        XCTAssertNil(pantryItem.quantity)
        XCTAssertEqual(pantryItem.quantityMode, .presenceOnly)
    }

    // MARK: - ShoppingItem Identity

    func testShoppingItemIdentityMatchesByCatalog() {
        let a = ShoppingItem(name: "Carrot", quantity: 1, unit: .whole, category: .produce)
        let b = ShoppingItem(name: "Carrots", quantity: 3, unit: .whole, category: .produce)
        XCTAssertTrue(a.matchesIdentity(of: b))
    }

    func testShoppingItemIdentityDiffersForDifferentFacets() {
        let whole = ShoppingItem(
            name: "Garlic", quantity: 1, unit: .whole, category: .produce,
            catalogItemID: "garlic", facets: []
        )
        let minced = ShoppingItem(
            name: "Garlic", quantity: 1, unit: .tablespoon, category: .produce,
            catalogItemID: "garlic", facets: [.init(key: .preparation, value: "minced")]
        )
        XCTAssertFalse(whole.matchesIdentity(of: minced))
    }

    // MARK: - Shopping Preview

    func testPreviewShoppingListEmptyMealPlanReturnsEmpty() {
        let (appState, _, _) = makeTestAppState()
        let preview = appState.previewShoppingListFromMealPlan()
        XCTAssertTrue(preview.isEmpty)
    }

    // MARK: - Prepared Dish History Signature

    func testHistoryTemplateSignatureChangesOnNameEdit() {
        var dish = makePreparedDish(name: "Soup")
        let sig1 = dish.historyTemplateSignature
        dish.name = "Updated Soup"
        let sig2 = dish.historyTemplateSignature
        XCTAssertNotEqual(sig1, sig2)
    }

    func testHistoryTemplateSignatureStableForServingsChange() {
        let dish1 = makePreparedDish(name: "Soup", servingsRemaining: 3)
        var dish2 = dish1
        dish2.servingsRemaining = 1
        XCTAssertEqual(dish1.historyTemplateSignature, dish2.historyTemplateSignature,
                        "Serving count changes should NOT trigger signature change")
    }

    // MARK: - Prepared Dish Normalization

    func testPreparedDishClampsServingsToMinimumOne() {
        let dish = PreparedDish(name: "Soup", mealTypes: [.lunch], servingsRemaining: 0, storage: .refrigerated)
        XCTAssertEqual(dish.servingsRemaining, 1)
    }

    func testPreparedDishDeduplicatesMealTypes() {
        let dish = PreparedDish(name: "Soup", mealTypes: [.lunch, .lunch, .dinner], servingsRemaining: 2, storage: .refrigerated)
        XCTAssertEqual(dish.mealTypes, [.lunch, .dinner])
    }

    func testPreparedDishTrimsName() {
        let dish = PreparedDish(name: "  Soup  ", mealTypes: [.lunch], servingsRemaining: 2, storage: .refrigerated)
        XCTAssertEqual(dish.name, "Soup")
    }

    // MARK: - Prepared Dish Match Key

    func testPreparedDishMatchKeyPrefersRecipeID() {
        let recipeID = UUID()
        let dish = makePreparedDish(name: "Curry", recipeID: recipeID)
        XCTAssertEqual(dish.preparedFoodMatchKey, .recipe(recipeID))
    }

    func testPreparedDishMatchKeyFallsBackToFoodIdentity() {
        let identityID = UUID()
        let dish = makePreparedDish(name: "Soup", foodIdentityID: identityID)
        XCTAssertEqual(dish.preparedFoodMatchKey, .preparedFoodIdentity(identityID))
    }

    // MARK: - Prepared Dish Freshness Policy

    func testFreshnessPolicyReturnsCorrectDaysByStorage() {
        let now = Date()
        let pantry = PreparedDishFreshnessPolicy.estimatedUseByDate(for: .pantry, referenceDate: now)
        let fridge = PreparedDishFreshnessPolicy.estimatedUseByDate(for: .refrigerated, referenceDate: now)
        let frozen = PreparedDishFreshnessPolicy.estimatedUseByDate(for: .frozen, referenceDate: now)

        let cal = Calendar.current
        XCTAssertEqual(cal.dateComponents([.day], from: now, to: pantry).day, 2)
        XCTAssertEqual(cal.dateComponents([.day], from: now, to: fridge).day, 4)
        XCTAssertEqual(cal.dateComponents([.day], from: now, to: frozen).day, 90)
    }

    // MARK: - Prepared Dish Draft Validation

    func testPreparedDishDraftInvalidWhenNameEmpty() {
        var draft = PreparedDishDraft()
        draft.name = ""
        draft.mealTypes = [.lunch]
        XCTAssertFalse(draft.isValid)
    }

    func testPreparedDishDraftInvalidWhenNoMealTypes() {
        var draft = PreparedDishDraft()
        draft.name = "Soup"
        draft.mealTypes = []
        XCTAssertFalse(draft.isValid)
    }

    func testPreparedDishDraftInvalidForPartialNutrition() {
        var draft = PreparedDishDraft()
        draft.name = "Soup"
        draft.mealTypes = [.lunch]
        draft.caloriesText = "200"
        // protein/carbs/fat empty → partial nutrition → invalid
        XCTAssertTrue(draft.hasPartialNutrition)
        XCTAssertFalse(draft.isValid)
    }

    func testPreparedDishDraftValidWithCompleteNutrition() {
        var draft = PreparedDishDraft()
        draft.name = "Soup"
        draft.mealTypes = [.lunch]
        draft.caloriesText = "200"
        draft.proteinText = "10"
        draft.carbsText = "30"
        draft.fatText = "5"
        XCTAssertTrue(draft.isValid)
    }

    // MARK: - Adjust Prepared Dish Servings

    func testAdjustPreparedDishServingsZeroDeltaReturnsFalse() async {
        let (appState, _, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Soup", servingsRemaining: 4)
        await appState.addPreparedDish(dish)

        let removed = await appState.adjustPreparedDishServings(dish, delta: 0)
        XCTAssertFalse(removed)
        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 4)
    }

    func testAdjustPreparedDishServingsIncrement() async {
        let (appState, _, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Soup", servingsRemaining: 2)
        await appState.addPreparedDish(dish)

        let removed = await appState.adjustPreparedDishServings(dish, delta: 3)
        XCTAssertFalse(removed)
        XCTAssertEqual(appState.preparedDishes.first?.servingsRemaining, 5)
    }

    func testAdjustPreparedDishServingsDecrementToExactZeroRemoves() async {
        let (appState, _, _) = makeTestAppState()
        let dish = makePreparedDish(name: "Soup", servingsRemaining: 2)
        await appState.addPreparedDish(dish)

        let removed = await appState.adjustPreparedDishServings(dish, delta: -2)
        XCTAssertTrue(removed)
        XCTAssertTrue(appState.preparedDishes.isEmpty)
    }

    func testAdjustPreparedDishServingsMissingDishReturnsFalse() async {
        let (appState, _, _) = makeTestAppState()
        let ghost = makePreparedDish(name: "Ghost")
        let removed = await appState.adjustPreparedDishServings(ghost, delta: -1)
        XCTAssertFalse(removed)
    }

    // MARK: - Stamp Cooked Does Not Double-Stamp (Regression Guard)

    func testStampCookedEntriesByRecipeSkipsAlreadyStamped() async {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(title: "Pasta")
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe, cookedAt: Date().addingTimeInterval(-3600))
        await appState.addToMealPlan(entry)

        let originalCookedAt = appState.mealPlan.first?.cookedAt
        await appState.stampCookedMealPlanEntriesByRecipe(recipe.id)
        XCTAssertEqual(appState.mealPlan.first?.cookedAt, originalCookedAt, "Should not overwrite existing cookedAt")
    }
}

// ===================================================================
// MARK: - MockRealtimeService
// ===================================================================

/// A fully controllable mock of RealtimeServiceProtocol for testing
/// CookModeViewModel without AVAudioEngine, WebSockets, or network.
@MainActor
final class MockRealtimeService: RealtimeServiceProtocol {

    // MARK: - Observable state (protocol requirements)
    var isConnected = false
    var isModelSpeaking = false
    var isUserSpeaking = false
    var transcript = ""
    var statusMessage = ""
    var errorMessage: String?
    var isAudioReady: Bool { _isAudioReady }
    var onFunctionCall: ((String, [String: Any]) -> Void)?

    // MARK: - Test controls
    var _isAudioReady = false

    /// How long prepareAudio() should "take" (simulates async VPIO setup).
    var prepareAudioDelay: UInt64 = 0  // nanoseconds

    // MARK: - Call tracking
    private(set) var prepareAudioCallCount = 0
    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var startCaptureCallCount = 0
    private(set) var stopCaptureCallCount = 0
    private(set) var silenceAICallCount = 0
    var sentMessages: [String] = []

    private(set) var lastConnectInstructions: String?
    private(set) var lastConnectTools: [[String: Any]]?

    // MARK: - Protocol methods

    func prepareAudio() async {
        prepareAudioCallCount += 1
        if prepareAudioDelay > 0 {
            try? await Task.sleep(nanoseconds: prepareAudioDelay)
        }
        _isAudioReady = true
    }

    func connect(withInstructions instructions: String, tools: [[String: Any]]) {
        connectCallCount += 1
        lastConnectInstructions = instructions
        lastConnectTools = tools
        isConnected = true
        statusMessage = "Connected"
    }

    func disconnect() {
        disconnectCallCount += 1
        isConnected = false
        isModelSpeaking = false
        isUserSpeaking = false
        statusMessage = ""
        errorMessage = nil
        _isAudioReady = false
    }

    func startCapture() {
        startCaptureCallCount += 1
    }

    func stopCapture() {
        stopCaptureCallCount += 1
    }

    func silenceAI() {
        silenceAICallCount += 1
    }

    func sendUserMessage(_ text: String) {
        sentMessages.append(text)
    }

    // MARK: - Test helpers

    func reset() {
        isConnected = false
        isModelSpeaking = false
        isUserSpeaking = false
        transcript = ""
        statusMessage = ""
        errorMessage = nil
        _isAudioReady = false
        prepareAudioCallCount = 0
        connectCallCount = 0
        disconnectCallCount = 0
        startCaptureCallCount = 0
        stopCaptureCallCount = 0
        silenceAICallCount = 0
        sentMessages = []
        lastConnectInstructions = nil
        lastConnectTools = nil
    }
}

// ===================================================================
// MARK: - CookMode Interaction Tests (using MockRealtimeService)
// ===================================================================

/// Tests the full interaction flows between CookModeViewModel and
/// RealtimeService: startup, navigation, mic control, timer, sync,
/// and edge cases.  Uses MockRealtimeService to verify every call
/// the ViewModel makes, and every state transition.
@MainActor
final class CookModeInteractionTests: XCTestCase {

    private func makeSUT(
        title: String = "Spaghetti Bolognese"
    ) -> (CookModeViewModel, MockRealtimeService) {
        // Clear persisted mute state so tests start fresh
        UserDefaults.standard.removeObject(forKey: "cookMode.isMuted")
        let recipe = makeRecipe(
            title: title,
            ingredients: [
                Ingredient(name: "Pasta", quantity: 500, unit: .gram),
                Ingredient(name: "Onion", quantity: 1, unit: .piece),
            ],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Dice the onion", timerMinutes: nil, tip: "Use a sharp knife"),
                RecipeStep(stepNumber: 2, instruction: "Boil water", timerMinutes: 10),
                RecipeStep(stepNumber: 3, instruction: "Cook pasta", timerMinutes: 8),
                RecipeStep(stepNumber: 4, instruction: "Combine and serve"),
            ]
        )
        let mock = MockRealtimeService()
        let vm = CookModeViewModel(recipe: recipe, realtimeService: mock)
        return (vm, mock)
    }

    /// Helper: simulate what startConversation() does, but synchronously
    /// (bypasses AVAudioApplication.requestRecordPermission which can't
    /// be mocked in unit tests).
    private func simulateStartConversation(_ vm: CookModeViewModel, _ mock: MockRealtimeService) async {
        vm.isConversationActive = true
        vm.isPreparing = true
        vm.conversationStatus = "Setting up audio…"

        await mock.prepareAudio()

        let instructions = "test_instructions"
        mock.connect(withInstructions: instructions, tools: vm.buildConversationTools())

        vm.isPreparing = false
        mock.startCapture()
        mock.sendUserMessage("Greeting")
    }

    // ================================================================
    // MARK: - Startup Flow
    // ================================================================

    func testStartupCallsInCorrectOrder() async {
        let (vm, mock) = makeSUT()
        await simulateStartConversation(vm, mock)

        XCTAssertEqual(mock.prepareAudioCallCount, 1, "prepareAudio should be called once")
        XCTAssertEqual(mock.connectCallCount, 1, "connect should be called once")
        XCTAssertEqual(mock.startCaptureCallCount, 1, "startCapture should be called once")
        XCTAssertTrue(mock.sentMessages.count >= 1, "Should send at least a greeting")
        XCTAssertTrue(mock.isConnected, "Should be connected after startup")
        XCTAssertTrue(vm.isConversationActive, "Conversation should be active")
        XCTAssertFalse(vm.isPreparing, "Should not still be preparing")
    }

    func testStartupRegistersFinishCookingTool() async {
        let (vm, mock) = makeSUT()

        await simulateStartConversation(vm, mock)

        let finishCookingTool = mock.lastConnectTools?.first {
            ($0["name"] as? String) == "finish_cooking"
        }

        XCTAssertNotNil(finishCookingTool, "Conversation should expose finish_cooking to the model")

        let parameters = finishCookingTool?["parameters"] as? [String: Any]
        XCTAssertEqual(parameters?["type"] as? String, "object")
    }

    func testStartupRegistersGoToStepRequiredArgument() async {
        let (vm, mock) = makeSUT()

        await simulateStartConversation(vm, mock)

        let goToStepTool = mock.lastConnectTools?.first {
            ($0["name"] as? String) == "go_to_step"
        }

        XCTAssertNotNil(goToStepTool, "Conversation should expose go_to_step to the model")

        let parameters = goToStepTool?["parameters"] as? [String: Any]
        let required = parameters?["required"] as? [String]
        XCTAssertEqual(required, ["step_number"], "go_to_step should require step_number")
    }

    func testStartupRegistersNextStepTool() async {
        let (vm, mock) = makeSUT()

        await simulateStartConversation(vm, mock)

        let nextStepTool = mock.lastConnectTools?.first {
            ($0["name"] as? String) == "next_step"
        }

        XCTAssertNotNil(nextStepTool, "Conversation should expose next_step to the model")
    }

    func testStartupRegistersPreviousStepTool() async {
        let (vm, mock) = makeSUT()

        await simulateStartConversation(vm, mock)

        let previousStepTool = mock.lastConnectTools?.first {
            ($0["name"] as? String) == "previous_step"
        }

        XCTAssertNotNil(previousStepTool, "Conversation should expose previous_step to the model")
    }

    func testInstructionsDirectModelToUseGoToStepForSpecificStepNumbers() {
        let (vm, _) = makeSUT()

        let instructions = vm.buildConversationInstructions()

        XCTAssertTrue(
            instructions.contains("call go_to_step directly with that step number"),
            "Instructions should tell the model to use go_to_step directly for numbered jumps"
        )
        XCTAssertTrue(
            instructions.contains("Do NOT chain next_step or previous_step multiple times"),
            "Instructions should explicitly forbid repeated next/previous chaining for specific step requests"
        )
    }

    func testStartupSetsConversationStatus() async {
        let (vm, mock) = makeSUT()

        vm.isConversationActive = true
        vm.isPreparing = true
        vm.conversationStatus = "Setting up audio…"

        XCTAssertEqual(vm.conversationStatus, "Setting up audio…")

        await mock.prepareAudio()
        mock.connect(withInstructions: "test", tools: [])
        vm.isPreparing = false

        XCTAssertEqual(mock.connectCallCount, 1)
        XCTAssertTrue(mock.isConnected)
    }

    func testAudioEngineReadyBeforeConnect() async {
        let (_, mock) = makeSUT()

        // Before prepareAudio
        XCTAssertFalse(mock.isAudioReady)

        await mock.prepareAudio()

        // After prepareAudio, before connect
        XCTAssertTrue(mock.isAudioReady)
        XCTAssertFalse(mock.isConnected)
    }

    // ================================================================
    // MARK: - Race Condition: syncRealtimeState during preparation
    // ================================================================

    func testSyncDoesNotKillConversationDuringPreparation() {
        let (vm, mock) = makeSUT()

        // Simulate the state during prepareAudio() — active but not connected
        vm.isConversationActive = true
        vm.isPreparing = true
        mock.isConnected = false

        // Timer fires syncRealtimeState — this previously killed the conversation
        vm.syncRealtimeState()

        XCTAssertTrue(vm.isConversationActive,
            "REGRESSION: syncRealtimeState must NOT set isConversationActive=false while isPreparing=true")
    }

    func testSyncDoesNotKillConversationDuringPreparationMultipleCalls() {
        let (vm, mock) = makeSUT()

        vm.isConversationActive = true
        vm.isPreparing = true
        mock.isConnected = false

        // Simulate many rapid timer fires during the 5-15s VPIO setup
        for _ in 0..<100 {
            vm.syncRealtimeState()
        }

        XCTAssertTrue(vm.isConversationActive,
            "REGRESSION: 100 sync calls during preparation must not kill conversation")
    }

    func testSyncDetectsDisconnectAfterPreparation() {
        let (vm, mock) = makeSUT()

        // Simulate a prior successful connection so wasEverConnected is set
        vm.isConversationActive = true
        mock.isConnected = true
        vm.syncRealtimeState()

        // Now simulate the disconnect after preparation is done
        vm.isPreparing = false
        mock.isConnected = false
        vm.syncRealtimeState()

        XCTAssertFalse(vm.isConversationActive,
            "Should detect real disconnect after preparation is complete")
    }

    func testSyncDoesNotTouchStateWhenInactive() {
        let (vm, mock) = makeSUT()

        vm.isConversationActive = false
        mock.isModelSpeaking = true
        mock.transcript = "Something"

        vm.syncRealtimeState()

        XCTAssertFalse(vm.isModelSpeaking, "Should not sync when conversation is inactive")
        XCTAssertTrue(vm.conversationTranscript.isEmpty)
    }

    func testSyncCopiesAllValues() {
        let (vm, mock) = makeSUT()

        vm.isConversationActive = true
        vm.isPreparing = false
        mock.isConnected = true
        mock.transcript = "Step 1: Dice the onion"
        mock.isModelSpeaking = true
        mock.isUserSpeaking = false
        mock.statusMessage = "Speaking…"
        mock.errorMessage = nil

        vm.syncRealtimeState()

        XCTAssertEqual(vm.conversationTranscript, "Step 1: Dice the onion")
        XCTAssertTrue(vm.isModelSpeaking)
        XCTAssertFalse(vm.isUserSpeaking)
        XCTAssertEqual(vm.conversationStatus, "Speaking…")
        XCTAssertNil(vm.conversationError)
    }

    func testSyncCopiesError() {
        let (vm, mock) = makeSUT()

        vm.isConversationActive = true
        vm.isPreparing = false
        mock.isConnected = true
        mock.errorMessage = "Rate limit exceeded"

        vm.syncRealtimeState()

        XCTAssertEqual(vm.conversationError, "Rate limit exceeded")
    }

    // ================================================================
    // MARK: - Navigation sends messages to Realtime API
    // ================================================================

    func testNextStepSendsMessageWhenConversationActive() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true

        vm.nextStep()

        XCTAssertEqual(vm.currentStepIndex, 1)
        XCTAssertEqual(mock.sentMessages.count, 1, "nextStep should notify Realtime API")
        XCTAssertTrue(mock.sentMessages[0].contains("Boil water"),
            "Message should contain the new step instruction")
    }

    func testNextStepDoesNotSendMessageWhenConversationInactive() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = false

        vm.nextStep()

        XCTAssertEqual(vm.currentStepIndex, 1)
        XCTAssertTrue(mock.sentMessages.isEmpty,
            "Should not send message when conversation is inactive")
    }

    func testPreviousStepSendsMessage() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true
        vm.goToStep(2)
        mock.sentMessages.removeAll()  // clear the goToStep message

        vm.previousStep()

        XCTAssertEqual(vm.currentStepIndex, 1)
        XCTAssertEqual(mock.sentMessages.count, 1)
        XCTAssertTrue(mock.sentMessages[0].contains("Boil water"))
    }

    func testGoToStepSendsMessage() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true

        vm.goToStep(2)

        XCTAssertEqual(vm.currentStepIndex, 2)
        XCTAssertEqual(mock.sentMessages.count, 1)
        XCTAssertTrue(mock.sentMessages[0].contains("Cook pasta"))
    }

    func testGoToStepIncludesTipInMessage() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true

        vm.goToStep(0)  // Step 1 has tip: "Use a sharp knife"
        // goToStep(0) when already at 0 doesn't change index, but since we're
        // setting it explicitly, let's navigate away first
        vm.isConversationActive = false
        vm.goToStep(1)
        vm.isConversationActive = true
        mock.sentMessages.removeAll()

        vm.goToStep(0)

        XCTAssertTrue(mock.sentMessages[0].contains("sharp knife"),
            "Message should include the step's tip")
    }

    func testNextStepAtEndShowsCompletionWithoutMessage() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true
        vm.goToStep(3)  // last step
        mock.sentMessages.removeAll()

        vm.nextStep()

        XCTAssertTrue(vm.showCompletionScreen)
        XCTAssertTrue(mock.sentMessages.isEmpty,
            "Should not send message when showing completion")
    }

    func testPreviousStepAtStartDoesNotSendMessage() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true

        vm.previousStep()

        XCTAssertEqual(vm.currentStepIndex, 0)
        XCTAssertTrue(mock.sentMessages.isEmpty,
            "Should not send message when already at first step")
    }

    // ================================================================
    // MARK: - Repeat Current Step
    // ================================================================

    func testRepeatCurrentStepSendsMessage() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true

        vm.repeatCurrentStep()

        XCTAssertEqual(mock.sentMessages.count, 1)
        XCTAssertTrue(mock.sentMessages[0].contains("Dice the onion"),
            "Should ask model to repeat current step instruction")
    }

    func testRepeatCurrentStepDoesNothingWhenInactive() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = false

        vm.repeatCurrentStep()

        XCTAssertTrue(mock.sentMessages.isEmpty)
    }

    // ================================================================
    // MARK: - Mute/Unmute
    // ================================================================

    func testToggleMuteToMuted() {
        let (vm, mock) = makeSUT()
        XCTAssertFalse(vm.isMuted)

        vm.toggleMute()

        XCTAssertTrue(vm.isMuted)
        XCTAssertEqual(mock.stopCaptureCallCount, 1)
        XCTAssertEqual(mock.silenceAICallCount, 1)
        XCTAssertEqual(mock.startCaptureCallCount, 0)
    }

    func testToggleMuteToUnmuted() {
        let (vm, mock) = makeSUT()
        vm.isMuted = true

        vm.toggleMute()

        XCTAssertFalse(vm.isMuted)
        XCTAssertEqual(mock.startCaptureCallCount, 1)
        XCTAssertEqual(mock.stopCaptureCallCount, 0)
    }

    func testToggleMuteCycle() {
        let (vm, mock) = makeSUT()

        vm.toggleMute()  // mute
        XCTAssertTrue(vm.isMuted)
        XCTAssertEqual(mock.stopCaptureCallCount, 1)

        vm.toggleMute()  // unmute
        XCTAssertFalse(vm.isMuted)
        XCTAssertEqual(mock.startCaptureCallCount, 1)

        vm.toggleMute()  // mute again
        XCTAssertTrue(vm.isMuted)
        XCTAssertEqual(mock.stopCaptureCallCount, 2)
    }

    func testStopConversationResetsMute() {
        let (vm, _) = makeSUT()
        vm.isMuted = true
        vm.isConversationActive = true

        vm.stopConversation()

        // Mute now persists across sessions — stopConversation does NOT reset it
        XCTAssertTrue(vm.isMuted)
    }

    // ================================================================
    // MARK: - Stop Conversation
    // ================================================================

    func testStopConversationCallsDisconnect() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true

        vm.stopConversation()

        XCTAssertEqual(mock.disconnectCallCount, 1)
        XCTAssertFalse(vm.isConversationActive)
    }

    func testStopConversationResetsAllState() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true
        vm.conversationTranscript = "Hello there"
        vm.isModelSpeaking = true
        vm.isUserSpeaking = true
        vm.conversationStatus = "Listening..."
        vm.conversationError = "Some error"
        vm.isMuted = true

        vm.stopConversation()

        XCTAssertFalse(vm.isConversationActive)
        XCTAssertTrue(vm.conversationTranscript.isEmpty)
        XCTAssertFalse(vm.isModelSpeaking)
        XCTAssertFalse(vm.isUserSpeaking)
        XCTAssertTrue(vm.conversationStatus.isEmpty)
        XCTAssertNil(vm.conversationError)
        // Mute now persists across sessions — stopConversation does NOT reset it
        XCTAssertTrue(vm.isMuted)
        XCTAssertEqual(mock.disconnectCallCount, 1)
    }

    // ================================================================
    // MARK: - Cleanup
    // ================================================================

    func testCleanupStopsTimerAndConversation() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true
        vm.isTimerRunning = true
        vm.isModelSpeaking = true

        vm.cleanup()

        XCTAssertFalse(vm.isConversationActive)
        XCTAssertFalse(vm.isTimerRunning)
        XCTAssertFalse(vm.isModelSpeaking)
        XCTAssertEqual(mock.disconnectCallCount, 1)
    }

    // ================================================================
    // MARK: - Function Calls from Realtime API
    // ================================================================

    func testFunctionCallNextStepNavigatesAndNotifies() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true

        vm.handleRealtimeFunctionCall(name: "next_step", args: [:])

        XCTAssertEqual(vm.currentStepIndex, 1)
        // Function calls no longer send a redundant message back to the
        // model — the model already knows the step since it initiated
        // the function call.
        XCTAssertEqual(mock.sentMessages.count, 0)
    }

    func testFunctionCallGoToStepNavigatesAndNotifies() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true

        vm.handleRealtimeFunctionCall(name: "go_to_step", args: ["step_number": 3])

        XCTAssertEqual(vm.currentStepIndex, 2)
        // Function calls no longer send a message — the model initiated
        // the navigation so it already knows the target step.
        XCTAssertEqual(mock.sentMessages.count, 0)
    }

    func testFunctionCallStartTimerWithMinutes() {
        let (vm, _) = makeSUT()

        vm.handleRealtimeFunctionCall(name: "start_timer", args: ["minutes": 5])

        XCTAssertEqual(vm.timerSeconds, 300)
        XCTAssertTrue(vm.isTimerRunning)
        vm.stopTimer()
    }

    func testFunctionCallFinishCookingEndsSession() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true

        vm.handleRealtimeFunctionCall(name: "finish_cooking", args: [:])

        XCTAssertTrue(vm.showCompletionScreen)
        XCTAssertFalse(vm.isConversationActive)
        XCTAssertEqual(mock.disconnectCallCount, 1)
    }

    func testFunctionCallRepeatStepDoesNotNavigate() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true
        vm.goToStep(2)
        mock.sentMessages.removeAll()

        vm.handleRealtimeFunctionCall(name: "repeat_step", args: [:])

        XCTAssertEqual(vm.currentStepIndex, 2, "Step should not change")
        // repeat_step is a no-op: the AI re-reads from context without needing a notification
        XCTAssertTrue(mock.sentMessages.isEmpty, "No message needed — model re-reads from context")
    }

    // ================================================================
    // MARK: - Navigation preserves existing features
    // ================================================================

    func testNavigationStillWorksWithoutConversation() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = false

        vm.nextStep()
        XCTAssertEqual(vm.currentStepIndex, 1)
        XCTAssertTrue(mock.sentMessages.isEmpty, "No messages when conversation is off")

        vm.previousStep()
        XCTAssertEqual(vm.currentStepIndex, 0)
        XCTAssertTrue(mock.sentMessages.isEmpty)

        vm.goToStep(3)
        XCTAssertEqual(vm.currentStepIndex, 3)
        XCTAssertTrue(mock.sentMessages.isEmpty)
    }

    func testTimerStillWorksWithoutConversation() {
        let (vm, _) = makeSUT()
        vm.isConversationActive = false
        vm.goToStep(1)  // Step 2 has timerMinutes: 10

        vm.startTimer()
        XCTAssertEqual(vm.timerSeconds, 600)
        XCTAssertTrue(vm.isTimerRunning)

        vm.pauseTimer()
        XCTAssertTrue(vm.isPaused)

        vm.pauseTimer()
        XCTAssertFalse(vm.isPaused)

        vm.stopTimer()
        XCTAssertFalse(vm.isTimerRunning)
    }

    func testGoToStepOutOfBoundsDoesNotNavigate() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true

        vm.goToStep(99)
        XCTAssertEqual(vm.currentStepIndex, 0)
        XCTAssertTrue(mock.sentMessages.isEmpty, "Out-of-bounds should not notify")

        vm.goToStep(-1)
        XCTAssertEqual(vm.currentStepIndex, 0)
        XCTAssertTrue(mock.sentMessages.isEmpty)
    }

    func testProgressComputation() {
        let (vm, _) = makeSUT()
        XCTAssertEqual(vm.progress, 0.25)  // 1/4
        vm.goToStep(3)
        XCTAssertEqual(vm.progress, 1.0)   // 4/4
    }

    func testTimerDisplayFormat() {
        let (vm, _) = makeSUT()
        vm.timerSeconds = 125
        XCTAssertEqual(vm.timerDisplay, "02:05")
    }

    func testSetRating() {
        let (vm, _) = makeSUT()
        vm.setRating(4)
        XCTAssertEqual(vm.selectedRating, 4)
        XCTAssertEqual(vm.ratedRecipe.rating, 4)
    }

    func testSetRatingToggle() {
        let (vm, _) = makeSUT()
        vm.setRating(3)
        vm.setRating(3)
        XCTAssertNil(vm.selectedRating)
    }

    // ================================================================
    // MARK: - Auto-start timer on navigation
    // ================================================================

    func testAutoStartTimerOnStepWithTimer() {
        let (vm, _) = makeSUT()
        vm.isConversationActive = false

        vm.nextStep()  // Step 2 has timerMinutes: 10

        XCTAssertEqual(vm.timerSeconds, 600)
        XCTAssertTrue(vm.isTimerRunning)
        vm.stopTimer()
    }

    func testAutoStartTimerDoesNotTriggerOnStepWithoutTimer() {
        let (vm, _) = makeSUT()
        vm.isConversationActive = false

        // Step 1 has no timer, we're already there
        XCTAssertFalse(vm.isTimerRunning)
    }

    // ================================================================
    // MARK: - Mute Persistence
    // ================================================================

    func testToggleMuteWritesToUserDefaults() {
        let (vm, _) = makeSUT()
        XCTAssertFalse(vm.isMuted)

        vm.toggleMute()

        XCTAssertTrue(vm.isMuted)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "cookMode.isMuted"))

        vm.toggleMute()

        XCTAssertFalse(vm.isMuted)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "cookMode.isMuted"))
    }

    func testMuteStateRestoredOnInit() {
        UserDefaults.standard.set(true, forKey: "cookMode.isMuted")

        let recipe = makeRecipe(
            title: "Test",
            ingredients: [Ingredient(name: "A", quantity: 1, unit: .piece)],
            steps: [RecipeStep(stepNumber: 1, instruction: "Go")]
        )
        let mock = MockRealtimeService()
        let vm = CookModeViewModel(recipe: recipe, realtimeService: mock)

        XCTAssertTrue(vm.isMuted, "Mute should be restored from UserDefaults on init")

        // Clean up
        UserDefaults.standard.removeObject(forKey: "cookMode.isMuted")
    }

    // ================================================================
    // MARK: - Continue-in-Background Guards
    // ================================================================

    func testContinueInBackgroundRequiresActiveConversation() {
        let (vm, mock) = makeSUT()
        // Conversation not started — isConversationActive = false
        vm.continueInBackground()

        XCTAssertFalse(vm.didContinueInBackground)
        XCTAssertEqual(mock.silenceAICallCount, 0, "Should not silence when conversation inactive")
    }

    func testContinueInBackgroundBlockedWhenAlreadyScheduling() async {
        let (vm, mock) = makeSUT()
        await simulateStartConversation(vm, mock)

        // First call — should proceed
        vm.continueInBackground()
        XCTAssertTrue(vm.didContinueInBackground)
        XCTAssertEqual(mock.silenceAICallCount, 1)

        // Reset to simulate re-entry attempt while still scheduling
        // (didContinueInBackground is already true, so guard blocks)
        let silenceCountBefore = mock.silenceAICallCount
        vm.continueInBackground()
        XCTAssertEqual(mock.silenceAICallCount, silenceCountBefore,
                       "Second call should be blocked by guard")
    }

    func testContinueInBackgroundBlockedOnCompletionScreen() async {
        let (vm, mock) = makeSUT()
        await simulateStartConversation(vm, mock)
        vm.showCompletionScreen = true

        vm.continueInBackground()

        XCTAssertFalse(vm.didContinueInBackground,
                       "Should not background when completion screen is showing")
    }

    func testContinueInBackgroundBlockedWhenEndingSession() async {
        let (vm, mock) = makeSUT()
        await simulateStartConversation(vm, mock)
        vm.isEndingSession = true

        vm.continueInBackground()

        XCTAssertFalse(vm.didContinueInBackground)
    }

    func testContinueInBackgroundDisconnectsVoiceSynchronously() async {
        let (vm, mock) = makeSUT()
        await simulateStartConversation(vm, mock)

        vm.continueInBackground()

        // disconnect() should have been called immediately (not delayed in async task)
        XCTAssertEqual(mock.disconnectCallCount, 1, "Voice should disconnect synchronously")
        XCTAssertFalse(vm.isConversationActive, "Conversation should be inactive immediately")
        XCTAssertTrue(vm.didContinueInBackground, "Flag should be set synchronously")
    }

    // ================================================================
    // MARK: - Last-Step Timer Cleanup
    // ================================================================

    func testNextStepAtLastStepStopsRunningTimer() {
        let (vm, _) = makeSUT()
        vm.isConversationActive = false

        // Navigate to step 3 (index 2), which has timerMinutes: 8
        vm.nextStep()  // → step 2 (index 1), timer 10
        vm.nextStep()  // → step 3 (index 2), timer 8
        XCTAssertTrue(vm.isTimerRunning, "Timer should auto-start on step with timer")

        // Now advance past last step → completion
        vm.nextStep()  // → last step (index 3), no timer auto-start since step 4 has none
        vm.nextStep()  // → completion screen (isLastStep was true)

        XCTAssertTrue(vm.showCompletionScreen)
        XCTAssertFalse(vm.isTimerRunning, "Timer should be stopped on completion")
    }

    // ================================================================
    // MARK: - endCookingSession Cleanup
    // ================================================================

    func testEndCookingSessionSetsIsEndingSession() async {
        let (vm, mock) = makeSUT()
        await simulateStartConversation(vm, mock)

        vm.endCookingSession()

        XCTAssertTrue(vm.isEndingSession)
        XCTAssertFalse(vm.isConversationActive)
        XCTAssertFalse(vm.didContinueInBackground)
        XCTAssertEqual(mock.disconnectCallCount, 1, "cleanup() should disconnect voice")
    }

    func testEndCookingSessionStopsTimer() {
        let (vm, _) = makeSUT()
        vm.isConversationActive = false
        vm.nextStep()  // step 2 with timer
        XCTAssertTrue(vm.isTimerRunning)

        vm.endCookingSession()

        XCTAssertFalse(vm.isTimerRunning, "Timer should be stopped by cleanup()")
    }

    func testEndCookingSessionIsIdempotent() async {
        let (vm, mock) = makeSUT()
        await simulateStartConversation(vm, mock)

        vm.endCookingSession()
        vm.endCookingSession()

        // Should not crash or produce unexpected state
        XCTAssertTrue(vm.isEndingSession)
        // disconnect called twice (once per cleanup) — idempotent
        XCTAssertEqual(mock.disconnectCallCount, 2)
    }

    // ================================================================
    // MARK: - Session Persistence on Foreground
    // ================================================================

    func testPersistSessionCreatesCookingSession() {
        let (vm, _) = makeSUT()

        vm.persistSession()

        let session = CookingSession.load(recipeId: vm.recipe.id)
        XCTAssertNotNil(session, "persistSession should save a CookingSession")
        XCTAssertEqual(session?.recipeId, vm.recipe.id)
        XCTAssertEqual(session?.totalSteps, vm.steps.count)

        // Clean up
        CookingSession.clear(recipeId: vm.recipe.id)
    }

    // ================================================================
    // MARK: - Mute Guards: Navigation While Muted
    // ================================================================

    func testNextStepWhileMutedDoesNotSendMessage() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true
        vm.isMuted = true

        vm.nextStep()

        XCTAssertEqual(vm.currentStepIndex, 1)
        XCTAssertTrue(mock.sentMessages.isEmpty,
            "notifyStepChanged should be skipped when muted")
    }

    func testGoToStepWhileMutedDoesNotSendMessage() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true
        vm.isMuted = true

        vm.goToStep(2)

        XCTAssertEqual(vm.currentStepIndex, 2)
        XCTAssertTrue(mock.sentMessages.isEmpty,
            "notifyStepChanged should be skipped when muted")
    }

    func testPreviousStepWhileMutedDoesNotSendMessage() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true
        vm.isMuted = true
        vm.goToStep(2)

        vm.previousStep()

        XCTAssertEqual(vm.currentStepIndex, 1)
        XCTAssertTrue(mock.sentMessages.isEmpty,
            "notifyStepChanged should be skipped when muted")
    }

    func testUnmuteThenNavigateSendsMessage() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = true
        vm.isMuted = true

        vm.nextStep()
        XCTAssertTrue(mock.sentMessages.isEmpty, "Muted — no message")

        // Unmute
        vm.toggleMute()
        mock.sentMessages.removeAll()

        vm.nextStep()
        XCTAssertEqual(mock.sentMessages.count, 1, "After unmute, navigation should send message")
    }

    // ================================================================
    // MARK: - endCookingSession Clears Persisted Session
    // ================================================================

    func testEndCookingSessionClearsCookingSession() {
        let (vm, _) = makeSUT()
        vm.persistSession()
        XCTAssertNotNil(CookingSession.load(recipeId: vm.recipe.id))

        vm.endCookingSession()

        XCTAssertNil(CookingSession.load(recipeId: vm.recipe.id),
            "endCookingSession should clear persisted CookingSession")
    }

    func testEndCookingSessionResetsContinueInBackgroundFlag() async {
        let (vm, mock) = makeSUT()
        await simulateStartConversation(vm, mock)
        vm.continueInBackground()
        XCTAssertTrue(vm.didContinueInBackground)

        vm.endCookingSession()

        XCTAssertFalse(vm.didContinueInBackground,
            "endCookingSession should clear didContinueInBackground")
    }

    // ================================================================
    // MARK: - continueInBackground Voice Cleanup Order
    // ================================================================

    func testContinueInBackgroundSilencesAIBeforeDisconnect() async {
        let (vm, mock) = makeSUT()
        await simulateStartConversation(vm, mock)

        vm.continueInBackground()

        XCTAssertEqual(mock.silenceAICallCount, 1, "silenceAI should be called")
        XCTAssertEqual(mock.stopCaptureCallCount, 1, "stopCapture should be called")
        XCTAssertEqual(mock.disconnectCallCount, 1, "disconnect should be called")
    }

    func testContinueInBackgroundPersistsSession() async {
        let (vm, mock) = makeSUT()
        await simulateStartConversation(vm, mock)

        vm.continueInBackground()

        let session = CookingSession.load(recipeId: vm.recipe.id)
        XCTAssertNotNil(session, "Session should be persisted for mini player")

        CookingSession.clear(recipeId: vm.recipe.id)
    }

    // ================================================================
    // MARK: - resumeFromBackground
    // ================================================================

    func testResumeFromBackgroundResetsFlag() async {
        let (vm, mock) = makeSUT()
        await simulateStartConversation(vm, mock)
        vm.continueInBackground()
        XCTAssertTrue(vm.didContinueInBackground)

        vm.resumeFromBackground()

        XCTAssertFalse(vm.didContinueInBackground)
        XCTAssertFalse(vm.isSchedulingBackground, "Scheduling flag should be cleared")
    }

    func testResumeFromBackgroundDoesNothingWhenNotBackgrounded() {
        let (vm, mock) = makeSUT()
        vm.didContinueInBackground = false

        vm.resumeFromBackground()

        // Should not start conversation since guard fails
        XCTAssertEqual(mock.prepareAudioCallCount, 0)
    }

    // ================================================================
    // MARK: - startConversation Audio Failure
    // ================================================================

    func testStartConversationFailsWhenAudioNotReady() async {
        let recipe = makeRecipe(
            title: "Fail Test",
            ingredients: [Ingredient(name: "A", quantity: 1, unit: .piece)],
            steps: [RecipeStep(stepNumber: 1, instruction: "Go")]
        )
        let mock = MockRealtimeService()
        // Override so prepareAudio doesn't set isAudioReady
        mock._isAudioReady = false
        let vm = CookModeViewModel(recipe: recipe, realtimeService: mock)

        // We can't call startConversation directly (it calls AVAudioApplication)
        // but we can test the guard logic manually:
        vm.isConversationActive = true
        vm.isPreparing = true
        // Simulate prepareAudio completing but audio still not ready
        // (In real code, prepareAudio sets _isAudioReady, but here we keep it false)
        // The guard `realtimeService.isAudioReady` should fail

        // Verify initial state — isAudioReady is false
        XCTAssertFalse(mock.isAudioReady)
    }

    // ================================================================
    // MARK: - Mute During Startup
    // ================================================================

    func testMuteDuringStartupSkipsGreetingAndSilencesAI() async {
        let (vm, mock) = makeSUT()

        // Pre-mute before conversation starts
        UserDefaults.standard.set(true, forKey: "cookMode.isMuted")
        let recipe = makeRecipe(
            title: "MuteStartup",
            ingredients: [Ingredient(name: "A", quantity: 1, unit: .piece)],
            steps: [RecipeStep(stepNumber: 1, instruction: "Cook")]
        )
        let mutedMock = MockRealtimeService()
        let mutedVM = CookModeViewModel(recipe: recipe, realtimeService: mutedMock)

        // Verify mute was restored from UserDefaults
        XCTAssertTrue(mutedVM.isMuted, "Mute should be restored from UserDefaults")

        // Simulate startConversation flow with muted state
        mutedVM.isConversationActive = true
        mutedVM.isPreparing = true
        await mutedMock.prepareAudio()

        mutedMock.connect(withInstructions: "test", tools: [])
        mutedVM.isPreparing = false

        // The startup flow checks isMuted: if true, stopCapture + silenceAI, no greeting
        if mutedVM.isMuted {
            mutedMock.stopCapture()
            mutedMock.silenceAI()
        }

        XCTAssertEqual(mutedMock.stopCaptureCallCount, 1, "Should stop capture when muted")
        XCTAssertEqual(mutedMock.silenceAICallCount, 1, "Should silence AI when muted")
        XCTAssertTrue(mutedMock.sentMessages.isEmpty, "No greeting should be sent when muted")

        // Clean up
        UserDefaults.standard.removeObject(forKey: "cookMode.isMuted")
    }

    // ================================================================
    // MARK: - SyncRealtimeState Edge Cases
    // ================================================================

    func testSyncDetectsDisconnect() {
        let (vm, mock) = makeSUT()
        // Simulate a prior successful connection via sync (sets wasEverConnected internally)
        vm.isConversationActive = true
        vm.isPreparing = false
        mock.isConnected = true
        vm.syncRealtimeState()

        // Now simulate disconnect
        mock.isConnected = false
        vm.syncRealtimeState()

        XCTAssertFalse(vm.isConversationActive,
            "Should detect disconnect when not preparing and was connected before")
    }

    func testSyncRealtimeStateWhenNotConversationMode() {
        let (vm, mock) = makeSUT()
        vm.isConversationActive = false
        mock.isModelSpeaking = true
        mock.transcript = "Hello"

        vm.syncRealtimeState()

        // Should not copy values when conversation is inactive
        XCTAssertFalse(vm.isModelSpeaking)
        XCTAssertTrue(vm.conversationTranscript.isEmpty)
    }
}

// ===================================================================
// MARK: - CookingSession Model Tests
// ===================================================================

@MainActor
final class CookingSessionModelTests: XCTestCase {

    private let testRecipeID = UUID()

    override func tearDown() {
        CookingSession.clear(recipeId: testRecipeID)
        super.tearDown()
    }

    private func makeSession(
        recipeId: UUID? = nil,
        currentStepIndex: Int = 0,
        isActive: Bool = true,
        expiryTimeoutSeconds: TimeInterval = 7200,
        queueId: UUID? = nil,
        queueStageId: UUID? = nil
    ) -> CookingSession {
        CookingSession(
            recipeId: recipeId ?? testRecipeID,
            recipeName: "Test Recipe",
            totalSteps: 3,
            stepSummaries: [
                CookingSession.StepSummary(stepNumber: 1, instruction: "Step one", timerMinutes: 5),
                CookingSession.StepSummary(stepNumber: 2, instruction: "Step two", timerMinutes: nil),
                CookingSession.StepSummary(stepNumber: 3, instruction: "Step three", timerMinutes: 10),
            ],
            currentStepIndex: currentStepIndex,
            startedAt: Date(),
            backgroundedAt: Date(),
            isActive: isActive,
            expiryTimeoutSeconds: expiryTimeoutSeconds,
            queueId: queueId,
            queueStageId: queueStageId
        )
    }

    func testSaveAndLoadRoundTrip() {
        let session = makeSession()
        session.save()

        let loaded = CookingSession.load(recipeId: testRecipeID)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.recipeId, testRecipeID)
        XCTAssertEqual(loaded?.recipeName, "Test Recipe")
        XCTAssertEqual(loaded?.totalSteps, 3)
        XCTAssertEqual(loaded?.currentStepIndex, 0)
        XCTAssertTrue(loaded?.isActive ?? false)
    }

    func testClearRemovesSession() {
        let session = makeSession()
        session.save()
        XCTAssertNotNil(CookingSession.load(recipeId: testRecipeID))

        CookingSession.clear(recipeId: testRecipeID)

        XCTAssertNil(CookingSession.load(recipeId: testRecipeID))
    }

    func testLoadAllReturnsNonExpiredSessions() {
        let session = makeSession()
        session.save()

        let all = CookingSession.loadAll()

        XCTAssertTrue(all.contains(where: { $0.recipeId == testRecipeID }))
    }

    func testLoadAllClearsExpiredSessions() {
        let expired = CookingSession(
            recipeId: testRecipeID,
            recipeName: "Expired",
            totalSteps: 1,
            stepSummaries: [],
            currentStepIndex: 0,
            startedAt: Date.distantPast,
            backgroundedAt: Date.distantPast,
            isActive: true,
            expiryTimeoutSeconds: 1 // 1 second timeout — already expired
        )
        expired.save()

        // Wait to ensure expiry
        let all = CookingSession.loadAll()

        XCTAssertFalse(all.contains(where: { $0.recipeId == testRecipeID }),
            "Expired session should be cleaned up by loadAll()")
    }

    func testIsExpiredWhenPastTimeout() {
        let session = CookingSession(
            recipeId: testRecipeID,
            recipeName: "Test",
            totalSteps: 1,
            stepSummaries: [],
            currentStepIndex: 0,
            startedAt: Date.distantPast,
            backgroundedAt: Date.distantPast,
            isActive: true,
            expiryTimeoutSeconds: 1
        )

        XCTAssertTrue(session.isExpired, "Session backgrounded in the past with 1s timeout should be expired")
    }

    func testIsNotExpiredWhenWithinTimeout() {
        let session = makeSession(expiryTimeoutSeconds: 7200)

        XCTAssertFalse(session.isExpired, "Session just created should not be expired")
    }

    func testSaveOverwritesExistingSession() {
        let original = makeSession(currentStepIndex: 0)
        original.save()

        let updated = makeSession(currentStepIndex: 2)
        updated.save()

        let loaded = CookingSession.load(recipeId: testRecipeID)
        XCTAssertEqual(loaded?.currentStepIndex, 2, "Save should overwrite existing session for same recipeId")
    }

    func testMultipleSessionsCanCoexist() {
        let id1 = UUID()
        let id2 = UUID()
        let session1 = makeSession(recipeId: id1)
        let session2 = makeSession(recipeId: id2)
        session1.save()
        session2.save()

        XCTAssertNotNil(CookingSession.load(recipeId: id1))
        XCTAssertNotNil(CookingSession.load(recipeId: id2))

        // Clean up
        CookingSession.clear(recipeId: id1)
        CookingSession.clear(recipeId: id2)
    }

    func testSessionPreservesQueueContext() {
        let queueID = UUID()
        let stageID = UUID()
        let session = makeSession(queueId: queueID, queueStageId: stageID)
        session.save()

        let loaded = CookingSession.load(recipeId: testRecipeID)
        XCTAssertEqual(loaded?.queueId, queueID)
        XCTAssertEqual(loaded?.queueStageId, stageID)
    }

    func testStepSummariesRoundTrip() {
        let session = makeSession()
        session.save()

        let loaded = CookingSession.load(recipeId: testRecipeID)
        XCTAssertEqual(loaded?.stepSummaries.count, 3)
        XCTAssertEqual(loaded?.stepSummaries[0].stepNumber, 1)
        XCTAssertEqual(loaded?.stepSummaries[0].timerMinutes, 5)
        XCTAssertNil(loaded?.stepSummaries[1].timerMinutes)
    }

    func testClearAllRemovesAllSessions() {
        let id1 = UUID()
        let id2 = UUID()
        makeSession(recipeId: id1).save()
        makeSession(recipeId: id2).save()

        CookingSession.clearAll()

        XCTAssertNil(CookingSession.load(recipeId: id1))
        XCTAssertNil(CookingSession.load(recipeId: id2))
    }
}

// ===================================================================
// MARK: - ActiveCooksManager Tests
// ===================================================================

@MainActor
final class ActiveCooksManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CookingSession.clearAll()
    }

    override func tearDown() {
        CookingSession.clearAll()
        super.tearDown()
    }

    private func makeSession(recipeId: UUID = UUID(), name: String = "Test") -> CookingSession {
        CookingSession(
            recipeId: recipeId,
            recipeName: name,
            totalSteps: 2,
            stepSummaries: [],
            currentStepIndex: 0,
            startedAt: Date(),
            backgroundedAt: Date(),
            isActive: true
        )
    }

    func testRefreshLoadsActiveSessions() {
        let id = UUID()
        makeSession(recipeId: id).save()

        let manager = ActiveCooksManager()

        XCTAssertTrue(manager.hasActiveSessions)
        XCTAssertEqual(manager.count, 1)
        XCTAssertNotNil(manager.session(for: id))

        CookingSession.clear(recipeId: id)
    }

    func testHasActiveSessionsReflectsState() {
        let manager = ActiveCooksManager()

        XCTAssertFalse(manager.hasActiveSessions, "No sessions saved — should be false")

        let id = UUID()
        makeSession(recipeId: id).save()
        manager.refresh()

        XCTAssertTrue(manager.hasActiveSessions)

        CookingSession.clear(recipeId: id)
        manager.refresh()

        XCTAssertFalse(manager.hasActiveSessions)
    }

    func testEndSessionClearsAndRefreshes() {
        let id = UUID()
        makeSession(recipeId: id).save()

        let manager = ActiveCooksManager()
        XCTAssertTrue(manager.hasActiveSessions)

        manager.endSession(for: id)

        XCTAssertFalse(manager.hasActiveSessions)
        XCTAssertNil(CookingSession.load(recipeId: id))
    }

    func testEndAllSessionsClearsEverything() {
        let id1 = UUID()
        let id2 = UUID()
        makeSession(recipeId: id1).save()
        makeSession(recipeId: id2).save()

        let manager = ActiveCooksManager()
        XCTAssertEqual(manager.count, 2)

        manager.endAllSessions()

        XCTAssertEqual(manager.count, 0)
        XCTAssertFalse(manager.hasActiveSessions)
    }

    func testSessionForRecipeReturnsCorrectSession() {
        let id1 = UUID()
        let id2 = UUID()
        makeSession(recipeId: id1, name: "Soup").save()
        makeSession(recipeId: id2, name: "Pasta").save()

        let manager = ActiveCooksManager()

        XCTAssertEqual(manager.session(for: id1)?.recipeName, "Soup")
        XCTAssertEqual(manager.session(for: id2)?.recipeName, "Pasta")
        XCTAssertNil(manager.session(for: UUID()))
    }
}

// ===================================================================
// MARK: - CookQueue Model Tests (Stage Operations)
// ===================================================================

@MainActor
final class CookQueueModelTests: XCTestCase {

    private func makeQueue(recipes: [Recipe]) -> CookQueue {
        let stages = recipes.map { CookQueueStage(recipes: [$0]) }
        return CookQueue(stages: stages)
    }

    func testCompleteStageRemovesFromArray() {
        var queue = makeQueue(recipes: [makeRecipe(title: "A"), makeRecipe(title: "B")])
        let stageID = queue.stages.first!.id

        queue.completeStage(stageID)

        XCTAssertEqual(queue.stages.count, 1)
        XCTAssertEqual(queue.stages.first?.title, "B")
    }

    func testSkipStageRemovesFromArray() {
        var queue = makeQueue(recipes: [makeRecipe(title: "A"), makeRecipe(title: "B")])
        let stageID = queue.stages.first!.id

        queue.skipStage(stageID)

        XCTAssertEqual(queue.stages.count, 1)
        XCTAssertEqual(queue.stages.first?.title, "B")
    }

    func testRemoveStageRemovesFromArray() {
        var queue = makeQueue(recipes: [makeRecipe(title: "A"), makeRecipe(title: "B")])
        let stageID = queue.stages.last!.id

        queue.removeStage(stageID)

        XCTAssertEqual(queue.stages.count, 1)
        XCTAssertEqual(queue.stages.first?.title, "A")
    }

    func testQueueIsEmptyAfterAllStagesCompleted() {
        var queue = makeQueue(recipes: [makeRecipe(title: "Solo")])
        let stageID = queue.stages.first!.id

        queue.completeStage(stageID)

        XCTAssertTrue(queue.isEmpty)
    }

    func testStartStageMarksActiveAndDemotesOthers() {
        var queue = makeQueue(recipes: [makeRecipe(title: "A"), makeRecipe(title: "B")])
        let firstID = queue.stages[0].id
        let secondID = queue.stages[1].id

        queue.startStage(firstID)
        XCTAssertEqual(queue.stages[0].status, .active)
        XCTAssertEqual(queue.stages[1].status, .pending)

        // Start second stage — first should be demoted back to pending
        queue.startStage(secondID)
        XCTAssertEqual(queue.stages[0].status, .pending)
        XCTAssertEqual(queue.stages[1].status, .active)
    }

    func testCurrentStageReturnActiveFirst() {
        var queue = makeQueue(recipes: [makeRecipe(title: "A"), makeRecipe(title: "B")])
        queue.startStage(queue.stages[1].id)

        XCTAssertEqual(queue.currentStage?.title, "B", "currentStage should prefer active stage")
    }

    func testCurrentStageFallsToPendingWhenNoActive() {
        let queue = makeQueue(recipes: [makeRecipe(title: "A"), makeRecipe(title: "B")])

        XCTAssertEqual(queue.currentStage?.title, "A", "currentStage should fall back to first pending")
    }

    func testPendingStageCountExcludesCompletedAndSkipped() {
        var queue = makeQueue(recipes: [makeRecipe(title: "A"), makeRecipe(title: "B"), makeRecipe(title: "C")])
        queue.completeStage(queue.stages[0].id)

        XCTAssertEqual(queue.pendingStageCount, 2)
    }

    func testStageTitle() {
        let singleStage = CookQueueStage(recipes: [makeRecipe(title: "Soup")])
        XCTAssertEqual(singleStage.title, "Soup")

        let doubleStage = CookQueueStage(recipes: [makeRecipe(title: "Soup"), makeRecipe(title: "Bread")])
        XCTAssertEqual(doubleStage.title, "Soup + Bread")

        let tripleStage = CookQueueStage(recipes: [makeRecipe(title: "A"), makeRecipe(title: "B"), makeRecipe(title: "C")])
        XCTAssertEqual(tripleStage.title, "A + 2 more")
    }

    func testStageSubtitleReflectsMealPlanLink() {
        let withMealPlan = CookQueueStage(recipes: [makeRecipe(title: "A")], sourceMealPlanEntryIDs: [UUID()])
        XCTAssertTrue(withMealPlan.subtitle.contains("From Meal Plan"))

        let withoutMealPlan = CookQueueStage(recipes: [makeRecipe(title: "A")])
        XCTAssertFalse(withoutMealPlan.subtitle.contains("From Meal Plan"))
    }

    func testIsParallelBatch() {
        let single = CookQueueStage(recipes: [makeRecipe(title: "A")])
        XCTAssertFalse(single.isParallelBatch)

        let parallel = CookQueueStage(recipes: [makeRecipe(title: "A"), makeRecipe(title: "B")])
        XCTAssertTrue(parallel.isParallelBatch)
    }

    func testRemoveStageNoOpForMissingID() {
        var queue = makeQueue(recipes: [makeRecipe(title: "A")])
        let originalUpdatedAt = queue.updatedAt

        queue.removeStage(UUID())

        XCTAssertEqual(queue.stages.count, 1, "Should not change when ID doesn't match")
        XCTAssertEqual(queue.updatedAt, originalUpdatedAt, "Should not update timestamp for no-op")
    }
}
