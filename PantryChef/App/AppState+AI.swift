import Foundation

// MARK: - AI Actions

extension AppState {
    private func pushAIFailure(_ operation: String, fallbackMessage: String) {
        pushError(.ai(operation: operation, message: fallbackMessage))
    }

    func getShoppingList(for recipe: Recipe) async -> [ShoppingItem] {
        var items = await aiService.generateShoppingList(recipe: recipe, pantry: pantryItems)
        for i in items.indices {
            items[i].recipeSource = recipe.title
        }
        return items
    }

    func getRecipeSuggestions() async -> [NormalizedAIRecipe] {
        guard !Task.isCancelled else { return [] }
        let suggestedRecipes = await aiService.suggestRecipes(pantry: pantryItems)
        guard !Task.isCancelled else { return [] }
        let normalized = await normalizeAIRecipes(suggestedRecipes)
        if normalized.isEmpty, !pantryItems.isEmpty {
            pushAIFailure("recipe suggestions", fallbackMessage: "Couldn't generate recipe suggestions right now. Please try again.")
        }
        return normalized
    }

    func generateRecipe(query: String, preferences: RecipeGenerationPreferences) async -> NormalizedAIRecipe? {
        guard !Task.isCancelled else { return nil }
        guard let recipe = await aiService.generateRecipe(query: query, preferences: preferences) else {
            if !Task.isCancelled {
                pushAIFailure("recipe generation", fallbackMessage: "Couldn't generate a recipe right now. Please try again.")
            }
            return nil
        }

        return await normalizedAIRecipe(recipe)
    }

    func importRecipeFromURL(_ urlString: String) async -> ReviewableImportedRecipe? {
        guard !Task.isCancelled else { return nil }
        guard let result = await aiService.parseRecipeFromURL(urlString) else {
            if !Task.isCancelled {
                pushAIFailure("recipe import", fallbackMessage: "Couldn't parse that recipe URL right now. Please try again.")
            }
            return nil
        }

        return await importedRecipeDraft(from: result.toRecipe(source: .imported))
    }

    func importRecipeFromText(_ text: String) async -> ReviewableImportedRecipe? {
        guard !Task.isCancelled else { return nil }
        guard let result = await aiService.parseRecipeFromText(text) else {
            if !Task.isCancelled {
                pushAIFailure("recipe import", fallbackMessage: "Couldn't parse that recipe text right now. Please try again.")
            }
            return nil
        }

        return await importedRecipeDraft(from: result.toRecipe(source: .imported))
    }

    func getSubstitutions(for recipe: Recipe) async -> [SubstitutionSuggestion] {
        await aiService.suggestSubstitutions(recipe: recipe, pantry: pantryItems)
    }

    func getHealthierVersion(of recipe: Recipe) async -> HealthierSuggestion? {
        guard !Task.isCancelled else { return nil }
        let suggestion = await aiService.makeItHealthier(recipe: recipe)
        if suggestion == nil, !Task.isCancelled {
            pushAIFailure("healthier suggestion", fallbackMessage: "Couldn't generate healthier suggestions right now. Please try again.")
        }
        return suggestion
    }

    func getLeftoverIdeas(ingredients: [String]) async -> [NormalizedAIRecipe] {
        let recipes = await aiService.leftoverTransformer(ingredients: ingredients)
        return await normalizeAIRecipes(recipes)
    }

    func modifyRecipe(_ recipe: Recipe, feedback: String) async -> NormalizedAIRecipe? {
        let pantryNames = pantryItems.map(\.name)
        guard !Task.isCancelled else { return nil }
        guard let modifiedRecipe = await aiService.modifyRecipe(recipe, feedback: feedback, pantryIngredients: pantryNames) else {
            if !Task.isCancelled {
                pushAIFailure("recipe modification", fallbackMessage: "Couldn't modify the recipe right now. Please try again.")
            }
            return nil
        }

        return await normalizedAIRecipe(modifiedRecipe)
    }
}
