import Foundation

@MainActor
protocol RecipeGatewayProtocol {
    func addRecipe(_ recipe: Recipe) async
    func updateRecipe(_ recipe: Recipe) async
    func deleteRecipe(_ recipe: Recipe) async
    func toggleFavoriteWithSave(_ recipe: Recipe) async
    func generateRecipe(query: String, preferences: RecipeGenerationPreferences) async -> AppState.NormalizedAIRecipe?
    func importRecipeFromURL(_ urlString: String) async -> AppState.ReviewableImportedRecipe?
    func importRecipeFromText(_ text: String) async -> AppState.ReviewableImportedRecipe?
    func modifyRecipe(_ recipe: Recipe, feedback: String) async -> AppState.NormalizedAIRecipe?
    func cacheDiscoverRecipe(_ recipe: Recipe) async -> Recipe?
}

@MainActor
struct RecipeGateway: RecipeGatewayProtocol {
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - CRUD

    func addRecipe(_ recipe: Recipe) async {
        await appState.addRecipe(recipe)
    }

    func updateRecipe(_ recipe: Recipe) async {
        await appState.updateRecipe(recipe)
    }

    func deleteRecipe(_ recipe: Recipe) async {
        await appState.deleteRecipe(recipe)
    }

    func toggleFavoriteWithSave(_ recipe: Recipe) async {
        await appState.toggleFavoriteWithSave(recipe)
    }

    // MARK: - AI / Import

    func generateRecipe(query: String, preferences: RecipeGenerationPreferences) async -> AppState.NormalizedAIRecipe? {
        guard let recipe = await appState.generateRecipe(query: query, preferences: preferences) else {
            return nil
        }

        return await appState.cacheDiscoverRecipe(recipe)
    }

    func importRecipeFromURL(_ urlString: String) async -> AppState.ReviewableImportedRecipe? {
        await appState.importRecipeFromURL(urlString)
    }

    func importRecipeFromText(_ text: String) async -> AppState.ReviewableImportedRecipe? {
        await appState.importRecipeFromText(text)
    }

    func modifyRecipe(_ recipe: Recipe, feedback: String) async -> AppState.NormalizedAIRecipe? {
        await appState.modifyRecipe(recipe, feedback: feedback)
    }

    func cacheDiscoverRecipe(_ recipe: Recipe) async -> Recipe? {
        await appState.cacheDiscoverRecipe(recipe)
    }
}

@MainActor
extension AppState {
    var recipeGateway: any RecipeGatewayProtocol {
        RecipeGateway(appState: self)
    }
}