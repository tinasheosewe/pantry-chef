import XCTest
@testable import PantryChef

// Shared test factories and mocks, salvaged from the former monolithic test file
// when the legacy UI layer was removed. Used by the kept service-level tests.

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

    var generateIngredientDefinitionToReturn: AIIngredientDefinition? = nil
    var verifyAndMergeIngredientToReturn: AIService.IngredientMergeResult? = nil
    var generateIngredientDefinitionCallCount = 0
    var verifyAndMergeIngredientCallCount = 0

    func generateIngredientDefinition(name: String) async -> AIIngredientDefinition? {
        generateIngredientDefinitionCallCount += 1
        return generateIngredientDefinitionToReturn
    }

    func verifyAndMergeIngredient(
        name: String,
        baseItem: PantryCatalogItemDefinition,
        generatedCategory: FoodCategory?,
        generatedFacets: [PantryFacetKey: [String]]
    ) async -> AIService.IngredientMergeResult? {
        verifyAndMergeIngredientCallCount += 1
        return verifyAndMergeIngredientToReturn
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
