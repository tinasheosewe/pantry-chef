import Foundation

// MARK: - Storage Service Protocol (SOLID: Dependency Inversion)
/// Defines the contract for data persistence.
/// Swap between InMemoryStorageService and SupabaseStorageService without changing consumers.
protocol StorageServiceProtocol: AnyObject, Sendable {
    // Pantry
    func fetchPantryItems() async throws -> [PantryItem]
    func addPantryItem(_ item: PantryItem) async throws -> PantryItem
    func updatePantryItem(_ item: PantryItem) async throws -> PantryItem
    func deletePantryItem(_ item: PantryItem) async throws

    // Recipes
    func fetchRecipes() async throws -> [Recipe]
    func addRecipe(_ recipe: Recipe) async throws -> Recipe
    func updateRecipe(_ recipe: Recipe) async throws -> Recipe
    func deleteRecipe(_ recipe: Recipe) async throws

    // Meal Plan
    func fetchMealPlan() async throws -> [MealPlanEntry]
    func addMealPlanEntry(_ entry: MealPlanEntry) async throws -> MealPlanEntry
    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws -> MealPlanEntry
    func deleteMealPlanEntry(_ entry: MealPlanEntry) async throws

    // Shopping
    func fetchShoppingItems() async throws -> [ShoppingItem]
    func saveShoppingItems(_ items: [ShoppingItem]) async throws
}

// MARK: - AI Service Protocol
/// Defines the contract for AI-powered features.
protocol AIServiceProtocol: AnyObject, Sendable {
    func generateShoppingList(recipe: Recipe, pantry: [PantryItem]) async -> [ShoppingItem]
    func suggestRecipes(pantry: [PantryItem]) async -> [Recipe]
    func suggestSubstitutions(recipe: Recipe, pantry: [PantryItem]) async -> [SubstitutionSuggestion]
    func makeItHealthier(recipe: Recipe) async -> HealthierSuggestion?
    func leftoverTransformer(ingredients: [String]) async -> [Recipe]
    func parseRecipeFromURL(_ url: String) async -> RecipeImportResult?
    func parseRecipeFromText(_ extractedText: String) async -> RecipeImportResult?
    func chat(message: String, context: String) async -> String
}

// MARK: - Speech Service Protocol
/// Defines the contract for TTS and voice recognition.
protocol SpeechServiceProtocol: AnyObject {
    var isSpeaking: Bool { get }
    var isListening: Bool { get }

    func speak(_ text: String, rate: Float)
    func stop()
    func pause()
    func resume()
    func startListening(onResult: @escaping (String) -> Void)
    func stopListening()
}

extension SpeechServiceProtocol {
    func speak(_ text: String) { speak(text, rate: 0.48) }
}
