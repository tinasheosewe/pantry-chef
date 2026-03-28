import Foundation

// MARK: - Recipe Actions & Normalization

extension AppState {
    func addRecipe(_ recipe: Recipe) async {
        await recipeDomainService.addRecipe(recipe, state: self)
    }

    func updateRecipe(_ recipe: Recipe) async {
        await recipeDomainService.updateRecipe(recipe, state: self)
    }

    /// Toggle favorite and handle cross-list movement:
    /// - Favoriting a discover/AI recipe saves a copy into My Recipes (with isFavorite = true)
    /// - Unfavoriting a saved-from-discover recipe removes it from My Recipes
    func toggleFavoriteWithSave(_ recipe: Recipe) async {
        await recipeDomainService.toggleFavoriteWithSave(recipe, state: self)
    }

    func deleteRecipe(_ recipe: Recipe) async {
        await recipeDomainService.deleteRecipe(recipe, state: self)
    }

    func cacheDiscoverRecipe(_ recipe: NormalizedAIRecipe) async -> NormalizedAIRecipe? {
        await recipeDomainService.cacheDiscoverRecipe(recipe, state: self)
    }

    func cacheDiscoverRecipe(_ recipe: Recipe) async -> Recipe? {
        await recipeDomainService.cacheDiscoverRecipe(recipe, state: self)
    }

    // MARK: - Recipe Normalization

    func normalizedAIRecipe(_ recipe: Recipe) async -> NormalizedAIRecipe? {
        await recipeDomainService.normalizedAIRecipe(recipe, state: self)
    }

    func normalizeAIRecipes(_ recipes: [Recipe]) async -> [NormalizedAIRecipe] {
        await recipeDomainService.normalizeAIRecipes(recipes, state: self)
    }

    func canonicalizedRecipeForPersistence(_ recipe: Recipe) async -> Recipe {
        await recipeDomainService.canonicalizedRecipeForPersistence(recipe, state: self)
    }

    func preparedRecipeForIntake(_ recipe: Recipe) async throws -> Recipe {
        try await recipeDomainService.preparedRecipeForIntake(recipe, state: self)
    }

    func requireResolvedRecipeForPersistence(_ recipe: Recipe) async throws -> Recipe {
        try await recipeDomainService.requireResolvedRecipeForPersistence(recipe, state: self)
    }

    func requireNormalizedAIRecipe(_ recipe: Recipe) async throws -> NormalizedAIRecipe {
        try await recipeDomainService.requireNormalizedAIRecipe(recipe, state: self)
    }

    func importedRecipeDraft(from recipe: Recipe) async -> ReviewableImportedRecipe? {
        await recipeDomainService.importedRecipeDraft(from: recipe, state: self)
    }

    // MARK: - Discover Helpers

    func discoverEntries(from recipes: [Recipe]) -> [DiscoverRecipeRecord] {
        recipes.compactMap(DiscoverRecipeRecord.persisted)
    }

    func persistedDiscoverRecipes() -> [Recipe] {
        discoverRecipeStore
            .map(\.recipe)
            .filter { $0.source != .bundled }
    }

    func mergedDiscoverRecipes(withPersisted persisted: [Recipe]) -> [DiscoverRecipeRecord] {
        let seed = recipeRepository.seedRecipes
        var result: [Recipe] = []
        var seen = Set<UUID>()

        for recipe in seed + persisted {
            if seen.insert(recipe.id).inserted {
                result.append(recipe)
            }
        }
        return discoverEntries(from: result)
    }

    func syncPreparedDishesLinked(to recipe: Recipe) async {
        await preparedDishDomainService.syncPreparedDishesLinked(to: recipe, state: self)
    }
}
