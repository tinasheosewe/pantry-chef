import XCTest
@testable import PantryChef
import RealtimeAPI

// MARK: - Mock Services

@MainActor
final class MockStorageService: StorageServiceProtocol {
    enum Operation: Hashable {
        case fetchPantryItems
        case fetchRecipes
        case fetchMealPlan
        case fetchShoppingItems
        case addPantryItem
        case updatePantryItem
        case deletePantryItem
        case addRecipe
        case updateRecipe
        case deleteRecipe
        case addMealPlanEntry
        case updateMealPlanEntry
        case deleteMealPlanEntry
        case saveShoppingItems
    }

    var pantryStore: [PantryItem] = []
    var recipeStore: [Recipe] = []
    var mealPlanStore: [MealPlanEntry] = []
    var shoppingStore: [ShoppingItem] = []

    var addPantryItemCallCount = 0
    var updatePantryItemCallCount = 0
    var deletePantryItemCallCount = 0
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
    func addPantryItem(_ item: PantryItem) async throws -> PantryItem {
        if shouldFail(.addPantryItem) { throw TestError.mock }
        addPantryItemCallCount += 1
        pantryStore.append(item)
        return item
    }
    func updatePantryItem(_ item: PantryItem) async throws -> PantryItem {
        if shouldFail(.updatePantryItem) { throw TestError.mock }
        updatePantryItemCallCount += 1
        if let idx = pantryStore.firstIndex(where: { $0.id == item.id }) {
            pantryStore[idx] = item
        }
        return item
    }
    func deletePantryItem(_ item: PantryItem) async throws {
        if shouldFail(.deletePantryItem) { throw TestError.mock }
        deletePantryItemCallCount += 1
        pantryStore.removeAll { $0.id == item.id }
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
}

final class MockAIService: AIServiceProtocol {
    var shoppingListToReturn: [ShoppingItem] = []
    var recipesToReturn: [Recipe] = []
    var substitutionsToReturn: [SubstitutionSuggestion] = []
    var healthierToReturn: HealthierSuggestion?
    var importResultToReturn: RecipeImportResult?

    var generateShoppingListCallCount = 0
    var suggestRecipesCallCount = 0
    var suggestSubstitutionsCallCount = 0
    var parseRecipeFromURLCallCount = 0
    var parseRecipeFromTextCallCount = 0

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
    func estimateStepDurations(for steps: [RecipeStep], recipeTitle: String) async -> [RecipeStep] {
        return steps
    }
    func generateRecipe(query: String, preferences: RecipeGenerationPreferences) async -> Recipe? {
        return recipesToReturn.first
    }
    func generateStatusMessages(query: String, preferences: RecipeGenerationPreferences) async -> [String] {
        return ["Cooking..."]
    }
    func modifyRecipe(_ recipe: Recipe, feedback: String, pantryIngredients: [String]) async -> Recipe? {
        return recipesToReturn.first
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
    let appState = AppState(storageService: storage, aiService: ai, shouldLoadOnInit: false)
    // Clear seeded data so tests start clean
    appState.pantryItems = []
    appState.recipes = []
    return (appState, storage, ai)
}

func makePantryItem(
    name: String = "Test Item",
    category: FoodCategory = .other,
    quantity: Double? = 1,
    unit: MeasurementUnit? = .piece,
    expiryDate: Date? = nil
) -> PantryItem {
    PantryItem(name: name, category: category, quantity: quantity, unit: unit, expiryDate: expiryDate)
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
    nutrition: NutritionInfo? = nil,
    isFavorite: Bool = false
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
        nutrition: nutrition,
        isFavorite: isFavorite
    )
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
        XCTAssertNil(item.expiryDate)
        XCTAssertNil(item.notes)
        XCTAssertNil(item.imageURL)
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
            notes: "Free range",
            imageURL: "https://example.com/eggs.jpg"
        )
        XCTAssertEqual(item.name, "Egg")
        XCTAssertEqual(item.category, .protein)
        XCTAssertEqual(item.quantity, 12)
        XCTAssertEqual(item.unit, .piece)
        XCTAssertEqual(item.notes, "Free range")
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

    func testMissingQuantityBlocksRowValidationAndBuild() throws {
        var draft = PantryIntakeRowDraft()
        draft.selectItem(try XCTUnwrap(PantryCatalog.item(id: "milk")))
        draft.setQuantityText("")

        XCTAssertEqual(draft.rowState, .invalid)
        XCTAssertTrue(draft.warnings.contains { $0.kind == .missingQuantity })
        XCTAssertNil(draft.buildItem())
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
                Ingredient(name: "milk", quantity: 250, unit: .milliliter, category: .dairy),
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
        XCTAssertEqual(appState.shoppingItems.first?.name, "all purpose flour")
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
        XCTAssertEqual(item.displayText, "4 whole Tomatoes")
    }

    func testDisplayTextNoQuantity() {
        let item = ShoppingItem(name: "Bread", quantity: nil, unit: nil, category: .grains)
        XCTAssertEqual(item.displayText, "Bread")
    }

    func testDisplayTextQuantityOnly() {
        let item = ShoppingItem(name: "Butter", quantity: 250, unit: .gram, category: .dairy)
        XCTAssertEqual(item.displayText, "250 g Butter")
    }

    func testIsCheckedDefault() {
        let item = ShoppingItem(name: "Test")
        XCTAssertFalse(item.isChecked)
    }

    func testSampleData() {
        XCTAssertFalse(ShoppingItem.samples.isEmpty)
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
            imageURL: nil,
            dietaryTags: [.vegan]
        )
        let recipe = result.toRecipe()
        XCTAssertEqual(recipe.title, "Imported Recipe")
        XCTAssertEqual(recipe.servings, 2)
        XCTAssertEqual(recipe.dietaryTags, [.vegan])
        XCTAssertEqual(recipe.ingredients.count, 1)
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
            imageURL: nil,
            dietaryTags: nil
        )
        let recipe = result.toRecipe()
        XCTAssertEqual(recipe.servings, 4, "Should default to 4 servings")
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
        let entry = MealPlanEntry(date: Date(), mealType: .dinner)
        await appState.addToMealPlan(entry)
        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(storage.addMealPlanCallCount, 1)
    }

    func testRemoveFromMealPlan() async {
        let (appState, storage, _) = makeTestAppState()
        let entry = MealPlanEntry(date: Date(), mealType: .dinner)
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
        await appState.addPantryItem(makePantryItem(name: "Chicken Breast", category: .protein, quantity: 500))
        // Add recipe to meal plan
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Chicken", quantity: 400, unit: .gram, category: .protein),
            Ingredient(name: "Soy Sauce", quantity: 2, unit: .tablespoon, category: .condiments),
        ])
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe)
        await appState.addToMealPlan(entry)
        // Generate
        await appState.generateShoppingListFromMealPlan()
        // "Chicken" should be matched by "Chicken Breast" (fuzzy), "Soy Sauce" should be missing
        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(appState.shoppingItems[0].name, "Soy Sauce")
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
        discoverRecipe.source = .spoonacular(id: 42)

        await appState.toggleFavoriteWithSave(discoverRecipe)

        XCTAssertEqual(storage.addRecipeCallCount, 1)
        XCTAssertEqual(appState.recipes.count, 1)
        XCTAssertTrue(appState.recipes[0].isFavorite)
        XCTAssertTrue(appState.recipes[0].source.isUserRecipe)
    }

    func testToggleFavoriteWithSaveRemovesLinkedDiscoverCopyWhenUnfavorited() async {
        let (appState, storage, _) = makeTestAppState()
        var discoverRecipe = makeRecipe(title: "Discover Dish")
        discoverRecipe.source = .spoonacular(id: 42)
        discoverRecipe.isFavorite = true
        appState.discoverRecipes = [discoverRecipe]
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
            imageURL: discoverRecipe.imageURL,
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

    // MARK: - Cook Deduction (fuzzy matching)

    func testMarkRecipeAsCookedDeductsIngredients() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addPantryItem(makePantryItem(name: "Chicken Breast", category: .protein, quantity: 600, unit: .gram))
        await appState.addPantryItem(makePantryItem(name: "Rice", category: .grains, quantity: 3, unit: .cup))

        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Chicken", quantity: 500, unit: .gram, category: .protein),
            Ingredient(name: "Rice", quantity: 2, unit: .cup, category: .grains),
        ])
        await appState.markRecipeAsCooked(recipe)

        // Chicken Breast: 600 - 500 = 100
        let chicken = appState.pantryItems.first { $0.name == "Chicken Breast" }
        XCTAssertNotNil(chicken)
        XCTAssertEqual(chicken?.quantity, 100)

        // Rice: 3 - 2 = 1
        let rice = appState.pantryItems.first { $0.name == "Rice" }
        XCTAssertNotNil(rice)
        XCTAssertEqual(rice?.quantity, 1)
    }

    func testMarkRecipeAsCookedRemovesItemWhenDepleted() async {
        let (appState, _, _) = makeTestAppState()
        await appState.addPantryItem(makePantryItem(name: "Eggs", category: .dairy, quantity: 3, unit: .piece))
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Eggs", quantity: 3, unit: .piece),
        ])
        await appState.markRecipeAsCooked(recipe)
        XCTAssertFalse(appState.pantryItems.contains { $0.name == "Eggs" },
                        "Should remove item when quantity runs out")
    }

    // MARK: - Load All Data

    func testLoadAllData() async {
        let (appState, storage, _) = makeTestAppState()
        storage.pantryStore = [makePantryItem(name: "Loaded")]
        storage.recipeStore = [makeRecipe(title: "Loaded Recipe")]
        storage.mealPlanStore = [MealPlanEntry(date: Date(), mealType: .dinner)]
        storage.shoppingStore = [ShoppingItem(name: "Loaded Shopping")]

        await appState.loadAllData()
        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.recipes.count, 1)
        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(appState.shoppingItems.count, 1)
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
        XCTAssertEqual(vm.filteredRecipes.count, 1)
        XCTAssertEqual(vm.filteredRecipes[0].title, "Chicken Soup")
    }

    func testFilterBySearchTextDescription() async {
        let (vm, appState, _, _) = makeSUT()
        let recipe = Recipe(title: "Mystery", description: "A creamy pasta dish")
        await appState.addRecipe(recipe)
        vm.searchText = "pasta"
        vm.applySearchTextImmediately()
        XCTAssertEqual(vm.filteredRecipes.count, 1)
    }

    func testFilterByFavorites() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Fav", isFavorite: true))
        await appState.addRecipe(makeRecipe(title: "NotFav", isFavorite: false))
        vm.showOnlyFavorites = true
        XCTAssertEqual(vm.filteredRecipes.count, 1)
        XCTAssertEqual(vm.filteredRecipes[0].title, "Fav")
    }

    func testFilterByDifficulty() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Easy", difficulty: .easy))
        await appState.addRecipe(makeRecipe(title: "Hard", difficulty: .hard))
        vm.selectedDifficulty = .easy
        XCTAssertEqual(vm.filteredRecipes.count, 1)
        XCTAssertEqual(vm.filteredRecipes[0].title, "Easy")
    }

    func testFilterByMealType() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Breakfast", mealType: .breakfast))
        await appState.addRecipe(makeRecipe(title: "Dinner", mealType: .dinner))
        vm.selectedMealType = .breakfast
        XCTAssertEqual(vm.filteredRecipes.count, 1)
        XCTAssertEqual(vm.filteredRecipes[0].title, "Breakfast")
    }

    func testFilterByDietaryTags() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Vegan", dietaryTags: [.vegan, .glutenFree]))
        await appState.addRecipe(makeRecipe(title: "Regular", dietaryTags: []))
        vm.selectedDietaryTags = [.vegan]
        XCTAssertEqual(vm.filteredRecipes.count, 1)
        XCTAssertEqual(vm.filteredRecipes[0].title, "Vegan")
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
        XCTAssertEqual(vm.filteredRecipes.count, 1)
        XCTAssertEqual(vm.filteredRecipes[0].title, "Easy Vegan Dinner")
    }

    // MARK: - Sorting

    func testSortByName() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Zebra Cake"))
        await appState.addRecipe(makeRecipe(title: "Apple Pie"))
        vm.sortOrder = .name
        XCTAssertEqual(vm.filteredRecipes[0].title, "Apple Pie")
        XCTAssertEqual(vm.filteredRecipes[1].title, "Zebra Cake")
    }

    func testSortByDifficulty() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Hard", difficulty: .hard))
        await appState.addRecipe(makeRecipe(title: "Easy", difficulty: .easy))
        vm.sortOrder = .difficulty
        XCTAssertEqual(vm.filteredRecipes[0].title, "Easy")
    }

    func testSortByTime() async {
        let (vm, appState, _, _) = makeSUT()
        await appState.addRecipe(makeRecipe(title: "Long", prepTimeMinutes: 30, cookTimeMinutes: 60))
        await appState.addRecipe(makeRecipe(title: "Quick", prepTimeMinutes: 5, cookTimeMinutes: 10))
        vm.sortOrder = .time
        XCTAssertEqual(vm.filteredRecipes[0].title, "Quick")
    }

    // MARK: - Actions

    func testToggleFavoriteUsesUpdate() async {
        let (vm, appState, storage, _) = makeSUT()
        let recipe = makeRecipe(title: "TestFav", isFavorite: false)
        await appState.addRecipe(recipe)
        await vm.toggleFavorite(recipe)
        XCTAssertEqual(storage.updateRecipeCallCount, 1, "toggleFavorite should call updateRecipe, not addRecipe")
        XCTAssertEqual(appState.recipes.count, 1, "Should not duplicate recipe")
        XCTAssertTrue(appState.recipes[0].isFavorite)
    }

    func testToggleFavoriteUnfavorite() async {
        let (vm, appState, _, _) = makeSUT()
        let recipe = makeRecipe(title: "Fav", isFavorite: true)
        await appState.addRecipe(recipe)
        await vm.toggleFavorite(recipe)
        XCTAssertFalse(appState.recipes[0].isFavorite)
    }

    func testAddRecipe() async {
        let (vm, appState, _, _) = makeSUT()
        await vm.addRecipe(makeRecipe(title: "New"))
        XCTAssertEqual(appState.recipes.count, 1)
    }

    func testDeleteRecipe() async {
        let (vm, appState, _, _) = makeSUT()
        let recipe = makeRecipe(title: "Delete")
        await vm.addRecipe(recipe)
        await vm.deleteRecipe(recipe)
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
            imageURL: nil,
            dietaryTags: nil
        )
        await vm.importFromURL("https://example.com/recipe")
        XCTAssertNotNil(vm.importedRecipe)
        XCTAssertEqual(vm.importedRecipe?.title, "Imported")
        XCTAssertEqual(ai.parseRecipeFromURLCallCount, 1)
    }

    func testImportFromURLFails() async {
        let (vm, _, _, ai) = makeSUT()
        ai.importResultToReturn = nil
        await vm.importFromURL("https://bad.url")
        XCTAssertNil(vm.importedRecipe)
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
        let bulk = PantryBulkAddViewModel()
        let item = try XCTUnwrap(PantryCatalog.item(id: "milk"))

        bulk.stageCatalogItem(item)

        let staged = try XCTUnwrap(bulk.stagedRows.first)
        XCTAssertEqual(staged.selectedItemID, "milk")
        XCTAssertEqual(staged.storage, .refrigerated)
        XCTAssertEqual(staged.quantityText, "1")
        XCTAssertEqual(staged.unit, .liter)
    }

    func testStageSearchEntriesAddsRecognizedItemsAndTracksUnresolvedTerms() {
        let bulk = PantryBulkAddViewModel()
        bulk.searchComposerText = "milk, dragonfruit\ncheese"

        let addedCount = bulk.stageSearchEntries()

        XCTAssertEqual(addedCount, 2)
        XCTAssertEqual(bulk.stagedRows.count, 2)
        XCTAssertEqual(bulk.unresolvedTokens, ["dragonfruit"])
        XCTAssertEqual(bulk.selectedTab, .staging)
        XCTAssertTrue(bulk.searchComposerText.isEmpty)
    }

    func testSearchPreviewResultsUsesTrailingToken() {
        let bulk = PantryBulkAddViewModel()
        bulk.searchComposerText = "milk\nchicken"

        let resultIDs = bulk.searchPreviewResults.prefix(3).map(\.id)

        XCTAssertTrue(resultIDs.contains("chicken-breast"))
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
        XCTAssertEqual(vm.items[0].name, "Milk")
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
        await vm.addCheckedToPantry()
        // Milk should be in pantry, Bread should remain in shopping
        XCTAssertEqual(appState.pantryItems.count, 1)
        XCTAssertEqual(appState.pantryItems[0].name, "Milk")
        XCTAssertEqual(appState.pantryItems[0].category, .dairy)
        // Only unchecked items remain
        XCTAssertEqual(appState.shoppingItems.count, 1)
        XCTAssertEqual(appState.shoppingItems[0].name, "Bread")
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
        XCTAssertEqual(appState.mealPlan.count, 1)
        XCTAssertEqual(vm.entries.count, 1)
    }

    func testRemoveEntry() async {
        let (vm, appState) = makeSUT()
        let entry = MealPlanEntry(date: Date(), mealType: .dinner, recipe: makeRecipe())
        await appState.addToMealPlan(entry)
        vm.entries.append(entry)
        await vm.removeEntry(entry)
        XCTAssertTrue(appState.mealPlan.isEmpty)
        XCTAssertTrue(vm.entries.isEmpty)
    }

    // MARK: - Select Slot

    func testSelectSlot() {
        let (vm, _) = makeSUT()
        vm.selectSlot(date: Date(), mealType: .lunch)
        XCTAssertNotNil(vm.selectedSlot)
        XCTAssertEqual(vm.selectedSlot?.mealType, .lunch)
        XCTAssertTrue(vm.showRecipePicker)
    }

    // MARK: - Shopping List Generation

    func testGenerateShoppingList() async {
        let (vm, appState) = makeSUT()
        let recipe = makeRecipe(ingredients: [
            Ingredient(name: "Flour", quantity: 2, unit: .cup),
        ])
        await appState.addToMealPlan(MealPlanEntry(date: Date(), mealType: .dinner, recipe: recipe))
        await vm.generateShoppingList()
        XCTAssertFalse(appState.shoppingItems.isEmpty)
    }

    // MARK: - Computed Properties

    func testTotalPlannedMeals() async {
        let (vm, _) = makeSUT()
        let recipe = makeRecipe()
        let slot = MealPlanViewModel.MealSlot(date: Date(), mealType: .dinner)
        await vm.assignRecipe(recipe, to: slot)
        XCTAssertEqual(vm.totalPlannedMeals, 1)
    }

    func testWeekDateRangeText() {
        let (vm, _) = makeSUT()
        let text = vm.weekDateRangeText
        XCTAssertTrue(text.contains("–"), "Should contain an en-dash separator")
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
        let entry = MealPlanEntry(date: Date(), mealType: .dinner)
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
    // MARK: - Mic Mute/Unmute
    // ================================================================

    func testToggleMicMuteToMuted() {
        let (vm, mock) = makeSUT()
        XCTAssertFalse(vm.isMicMuted)

        vm.toggleMicMute()

        XCTAssertTrue(vm.isMicMuted)
        XCTAssertEqual(mock.stopCaptureCallCount, 1)
        XCTAssertEqual(mock.startCaptureCallCount, 0)
    }

    func testToggleMicMuteToUnmuted() {
        let (vm, mock) = makeSUT()
        vm.isMicMuted = true

        vm.toggleMicMute()

        XCTAssertFalse(vm.isMicMuted)
        XCTAssertEqual(mock.startCaptureCallCount, 1)
        XCTAssertEqual(mock.stopCaptureCallCount, 0)
    }

    func testToggleMicMuteCycle() {
        let (vm, mock) = makeSUT()

        vm.toggleMicMute()  // mute
        XCTAssertTrue(vm.isMicMuted)
        XCTAssertEqual(mock.stopCaptureCallCount, 1)

        vm.toggleMicMute()  // unmute
        XCTAssertFalse(vm.isMicMuted)
        XCTAssertEqual(mock.startCaptureCallCount, 1)

        vm.toggleMicMute()  // mute again
        XCTAssertTrue(vm.isMicMuted)
        XCTAssertEqual(mock.stopCaptureCallCount, 2)
    }

    func testStopConversationResetsMicMute() {
        let (vm, _) = makeSUT()
        vm.isMicMuted = true
        vm.isConversationActive = true

        vm.stopConversation()

        XCTAssertFalse(vm.isMicMuted)
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
        vm.isMicMuted = true

        vm.stopConversation()

        XCTAssertFalse(vm.isConversationActive)
        XCTAssertTrue(vm.conversationTranscript.isEmpty)
        XCTAssertFalse(vm.isModelSpeaking)
        XCTAssertFalse(vm.isUserSpeaking)
        XCTAssertTrue(vm.conversationStatus.isEmpty)
        XCTAssertNil(vm.conversationError)
        XCTAssertFalse(vm.isMicMuted)
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
}
