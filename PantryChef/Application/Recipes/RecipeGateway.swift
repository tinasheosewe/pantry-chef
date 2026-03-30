import Foundation

@MainActor
protocol RecipeGatewayProtocol {
    func addRecipe(_ recipe: Recipe) async
    func updateRecipe(_ recipe: Recipe) async
    func deleteRecipe(_ recipe: Recipe) async
    func toggleFavoriteWithSave(_ recipe: Recipe) async
    func generateRecipe(query: String, preferences: RecipeGenerationPreferences) async -> RecipeGenerationResult?
    func importRecipeFromURL(_ urlString: String) async -> AppState.ReviewableImportedRecipe?
    func importRecipeFromText(_ text: String) async -> AppState.ReviewableImportedRecipe?
    func modifyRecipe(_ recipe: Recipe, feedback: String) async -> RecipeGenerationResult?
    func cacheDiscoverRecipe(_ recipe: Recipe) async -> Recipe?
}

@MainActor
struct RecipeGateway: RecipeGatewayProtocol {
    private unowned let appState: AppState
    private let recipeDomainService: any RecipeDomainServicing

    init(appState: AppState, recipeDomainService: any RecipeDomainServicing) {
        self.appState = appState
        self.recipeDomainService = recipeDomainService
    }

    // MARK: - CRUD

    func addRecipe(_ recipe: Recipe) async {
        await recipeDomainService.addRecipe(recipe, state: appState)
    }

    func updateRecipe(_ recipe: Recipe) async {
        await recipeDomainService.updateRecipe(recipe, state: appState)
    }

    func deleteRecipe(_ recipe: Recipe) async {
        await recipeDomainService.deleteRecipe(recipe, state: appState)
    }

    func toggleFavoriteWithSave(_ recipe: Recipe) async {
        await recipeDomainService.toggleFavoriteWithSave(recipe, state: appState)
    }

    // MARK: - AI / Import

    func generateRecipe(query: String, preferences: RecipeGenerationPreferences) async -> RecipeGenerationResult? {
        guard let result = await recipeDomainService.generateRecipe(query: query, preferences: preferences, state: appState) else {
            return nil
        }

        switch result {
        case .recipe(let recipe):
            guard let cached = await recipeDomainService.cacheDiscoverRecipe(recipe, state: appState) else {
                return nil
            }
            return .recipe(cached)
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func importRecipeFromURL(_ urlString: String) async -> AppState.ReviewableImportedRecipe? {
        await recipeDomainService.importRecipeFromURL(urlString, state: appState)
    }

    func importRecipeFromText(_ text: String) async -> AppState.ReviewableImportedRecipe? {
        await recipeDomainService.importRecipeFromText(text, state: appState)
    }

    func modifyRecipe(_ recipe: Recipe, feedback: String) async -> RecipeGenerationResult? {
        await recipeDomainService.modifyRecipe(recipe, feedback: feedback, state: appState)
    }

    func cacheDiscoverRecipe(_ recipe: Recipe) async -> Recipe? {
        await recipeDomainService.cacheDiscoverRecipe(recipe, state: appState)
    }
}

@MainActor
extension AppState {
    var recipeGateway: any RecipeGatewayProtocol {
        RecipeGateway(appState: self, recipeDomainService: recipeDomainService)
    }
}