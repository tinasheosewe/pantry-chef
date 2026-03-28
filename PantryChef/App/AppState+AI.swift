import Foundation

// MARK: - AI Actions

extension AppState {
    func getShoppingList(for recipe: Recipe) async -> [ShoppingItem] {
        var items = await aiService.generateShoppingList(recipe: recipe, pantry: pantryItems)
        for i in items.indices {
            items[i].recipeSource = recipe.title
        }
        return items
    }

    func getRecipeSuggestions() async -> [NormalizedAIRecipe] {
        let suggestedRecipes = await aiService.suggestRecipes(pantry: pantryItems)
        return await normalizeAIRecipes(suggestedRecipes)
    }

    func generateRecipe(query: String, preferences: RecipeGenerationPreferences) async -> NormalizedAIRecipe? {
        guard let recipe = await aiService.generateRecipe(query: query, preferences: preferences) else {
            return nil
        }

        return await normalizedAIRecipe(recipe)
    }

    func importRecipeFromURL(_ urlString: String) async -> ReviewableImportedRecipe? {
        guard let result = await aiService.parseRecipeFromURL(urlString) else {
            return nil
        }

        return await importedRecipeDraft(from: result.toRecipe(source: .imported))
    }

    func importRecipeFromText(_ text: String) async -> ReviewableImportedRecipe? {
        guard let result = await aiService.parseRecipeFromText(text) else {
            return nil
        }

        return await importedRecipeDraft(from: result.toRecipe(source: .imported))
    }

    func getSubstitutions(for recipe: Recipe) async -> [SubstitutionSuggestion] {
        await aiService.suggestSubstitutions(recipe: recipe, pantry: pantryItems)
    }

    func getHealthierVersion(of recipe: Recipe) async -> HealthierSuggestion? {
        await aiService.makeItHealthier(recipe: recipe)
    }

    func getLeftoverIdeas(ingredients: [String]) async -> [NormalizedAIRecipe] {
        let recipes = await aiService.leftoverTransformer(ingredients: ingredients)
        return await normalizeAIRecipes(recipes)
    }

    func modifyRecipe(_ recipe: Recipe, feedback: String) async -> NormalizedAIRecipe? {
        let pantryNames = pantryItems.map(\.name)
        guard let modifiedRecipe = await aiService.modifyRecipe(recipe, feedback: feedback, pantryIngredients: pantryNames) else {
            return nil
        }

        return await normalizedAIRecipe(modifiedRecipe)
    }
}
