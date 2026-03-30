import Foundation

// MARK: - AI Actions

extension AppState {
    func getShoppingList(for recipe: Recipe) async -> [ShoppingItem] {
        await recipeDomainService.getShoppingList(for: recipe, state: self)
    }

    func getRecipeSuggestions() async -> [NormalizedAIRecipe] {
        await recipeDomainService.getRecipeSuggestions(state: self)
    }

    func generateRecipe(query: String, preferences: RecipeGenerationPreferences) async -> RecipeGenerationResult? {
        await recipeDomainService.generateRecipe(query: query, preferences: preferences, state: self)
    }

    func importRecipeFromURL(_ urlString: String) async -> ReviewableImportedRecipe? {
        await recipeDomainService.importRecipeFromURL(urlString, state: self)
    }

    func importRecipeFromText(_ text: String) async -> ReviewableImportedRecipe? {
        await recipeDomainService.importRecipeFromText(text, state: self)
    }

    func getSubstitutions(for recipe: Recipe) async -> [SubstitutionSuggestion] {
        await recipeDomainService.getSubstitutions(for: recipe, state: self)
    }

    func getHealthierVersion(of recipe: Recipe) async -> HealthierSuggestion? {
        await recipeDomainService.getHealthierVersion(of: recipe, state: self)
    }

    func getLeftoverIdeas(ingredients: [String]) async -> [NormalizedAIRecipe] {
        await recipeDomainService.getLeftoverIdeas(ingredients: ingredients, state: self)
    }

    func suggestRecipeNames(ingredients: [String], strictIngredients: Bool, requireAllIngredients: Bool, excludeNames: [String]) async -> RecipeNameSuggestionsResult {
        await recipeDomainService.suggestRecipeNames(ingredients: ingredients, strictIngredients: strictIngredients, requireAllIngredients: requireAllIngredients, excludeNames: excludeNames, state: self)
    }

    func generateRecipeFromSuggestion(_ suggestion: RecipeNameSuggestion, ingredients: [String], strictIngredients: Bool, requireAllIngredients: Bool) async -> NormalizedAIRecipe? {
        await recipeDomainService.generateRecipeFromSuggestion(suggestion, ingredients: ingredients, strictIngredients: strictIngredients, requireAllIngredients: requireAllIngredients, state: self)
    }

    func modifyRecipe(_ recipe: Recipe, feedback: String) async -> RecipeGenerationResult? {
        await recipeDomainService.modifyRecipe(recipe, feedback: feedback, state: self)
    }
}
