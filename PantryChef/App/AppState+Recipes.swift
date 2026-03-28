import Foundation

// MARK: - Recipe Actions & Normalization

extension AppState {
    func addRecipe(_ recipe: Recipe) async {
        do {
            let recipeToPersist = try await preparedRecipeForIntake(recipe)

            let saved = try await storageService.addRecipe(recipeToPersist)
            if saved.source.isUserRecipe {
                recipes.append(saved)
                markRecipesChanged()
            } else {
                setDiscoverRecipes(mergedDiscoverRecipes(withPersisted: persistedDiscoverRecipes() + [saved]))
            }
        } catch {
            pushError(.storage(error))
        }
    }

    func updateRecipe(_ recipe: Recipe) async {
        do {
            let recipeToPersist = try await preparedRecipeForIntake(recipe)

            let updated = try await storageService.updateRecipe(recipeToPersist)
            if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
                recipes[index] = updated
                markRecipesChanged()
            } else if let index = discoverRecipeStore.firstIndex(where: { $0.id == recipe.id }),
                      let discoverRecord = DiscoverRecipeRecord.persisted(updated) {
                discoverRecipeStore[index] = discoverRecord
                markDiscoverRecipesChanged()
            }

            await syncPreparedDishesLinked(to: updated)
        } catch {
            pushError(.storage(error))
        }
    }

    /// Toggle favorite and handle cross-list movement:
    /// - Favoriting a discover/AI recipe saves a copy into My Recipes (with isFavorite = true)
    /// - Unfavoriting a saved-from-discover recipe removes it from My Recipes
    func toggleFavoriteWithSave(_ recipe: Recipe) async {
        var updated = recipe
        updated.isFavorite.toggle()

        let isAlreadyInMyRecipes = recipes.contains { $0.id == recipe.id }
        let hasLinkedDiscoverRecipe = discoverRecipes.contains { $0.id == recipe.id && !$0.source.isUserRecipe }

        if updated.isFavorite && !isAlreadyInMyRecipes {
            // Save to My Recipes
            var savedCopy = updated
            savedCopy.source = .user
            await addRecipe(savedCopy)
        } else if !updated.isFavorite && isAlreadyInMyRecipes && (!recipe.source.isUserRecipe || hasLinkedDiscoverRecipe) {
            // Remove non-user recipes from My Recipes when un-hearted
            await removeFromMyRecipes(id: recipe.id)
        } else {
            // Normal update for user-created recipes
            await updateRecipe(updated)
        }

        // Also update in discover cache so the heart state is reflected there
        if let idx = discoverRecipeStore.firstIndex(where: { $0.id == recipe.id }) {
            discoverRecipeStore[idx].recipe.isFavorite = updated.isFavorite
            markDiscoverRecipesChanged()
        }
    }

    func deleteRecipe(_ recipe: Recipe) async {
        do {
            try await storageService.deleteRecipe(recipe)
            let originalRecipeCount = recipes.count
            recipes.removeAll { $0.id == recipe.id }
            if recipes.count != originalRecipeCount {
                markRecipesChanged()
            }
            if !recipe.source.isUserRecipe {
                let originalDiscoverCount = discoverRecipeStore.count
                discoverRecipeStore.removeAll { $0.id == recipe.id }
                if discoverRecipeStore.count != originalDiscoverCount {
                    markDiscoverRecipesChanged()
                }
            }
        } catch {
            pushError(.storage(error))
        }
    }

    func cacheDiscoverRecipe(_ recipe: NormalizedAIRecipe) async -> NormalizedAIRecipe? {
        do {
            _ = try await storageService.updateRecipe(recipe.rawValue)
            setDiscoverRecipes(mergedDiscoverRecipes(withPersisted: persistedDiscoverRecipes() + [recipe.rawValue]))
        } catch {
            pushError(.storage(error))
        }

        return recipe
    }

    func cacheDiscoverRecipe(_ recipe: Recipe) async -> Recipe? {
        let recipeToPersist: Recipe
        do {
            recipeToPersist = try await preparedRecipeForIntake(recipe)
        } catch {
            pushError(.storage(error))
            return nil
        }

        guard let discoverRecord = DiscoverRecipeRecord(nonAIRecipe: recipeToPersist) else {
            return nil
        }

        do {
            _ = try await storageService.updateRecipe(discoverRecord.recipe)
            setDiscoverRecipes(mergedDiscoverRecipes(withPersisted: persistedDiscoverRecipes() + [discoverRecord.recipe]))
        } catch {
            pushError(.storage(error))
        }

        return discoverRecord.recipe
    }

    // MARK: - Recipe Normalization

    func normalizedAIRecipe(_ recipe: Recipe) async -> NormalizedAIRecipe? {
        do {
            return try await requireNormalizedAIRecipe(recipe)
        } catch {
            pushError(.storage(error))
            return nil
        }
    }

    func normalizeAIRecipes(_ recipes: [Recipe]) async -> [NormalizedAIRecipe] {
        var normalizedRecipes: [NormalizedAIRecipe] = []
        normalizedRecipes.reserveCapacity(recipes.count)

        for recipe in recipes {
            guard let normalizedRecipe = await normalizedAIRecipe(recipe) else {
                return []
            }
            normalizedRecipes.append(normalizedRecipe)
        }

        return normalizedRecipes
    }

    func canonicalizedRecipeForPersistence(_ recipe: Recipe) async -> Recipe {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await recipeIngredientResolver.resolve(recipe: canonicalRecipe)

        if resolutionDraft.isReadyToBuild {
            return resolutionDraft.builtRecipe()
        }

        return canonicalRecipe
    }

    func preparedRecipeForIntake(_ recipe: Recipe) async throws -> Recipe {
        if recipe.source == .aiGenerated {
            return try await requireNormalizedAIRecipe(recipe).rawValue
        }

        return try await requireResolvedRecipeForPersistence(recipe)
    }

    func requireResolvedRecipeForPersistence(_ recipe: Recipe) async throws -> Recipe {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await recipeIngredientResolver.resolve(recipe: canonicalRecipe)

        guard resolutionDraft.isReadyToBuild, !resolutionDraft.requiresIngredientEdits else {
            let unresolvedNames = unresolvedIngredientNames(in: resolutionDraft)
            throw RecipeIntakeNormalizationError.unresolvedIngredients(unresolvedNames)
        }

        return resolutionDraft.builtRecipe()
    }

    func requireNormalizedAIRecipe(_ recipe: Recipe) async throws -> NormalizedAIRecipe {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await recipeIngredientResolver.resolve(recipe: canonicalRecipe)
        let disambiguatedDraft = try await aiDisambiguatedRecipeDraft(from: resolutionDraft)
        return NormalizedAIRecipe(rawValue: disambiguatedDraft.builtRecipe())
    }

    func importedRecipeDraft(from recipe: Recipe) async -> ReviewableImportedRecipe? {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await recipeIngredientResolver.resolve(recipe: canonicalRecipe)
        let resolvedRecipe = resolutionDraft.isReadyToBuild ? resolutionDraft.builtRecipe() : canonicalRecipe
        return ReviewableImportedRecipe(recipe: resolvedRecipe)
    }

    func unresolvedIngredientNames(in draft: RecipeResolutionDraft) -> [String] {
        let ambiguous = draft.ambiguousIngredients.map { $0.ingredient.rawName }
        let unknown = draft.unknownIngredients.map { $0.ingredient.rawName }
        let names = ambiguous + unknown
        return names.isEmpty ? draft.recipe.ingredients.map(\ .rawName) : names
    }

    func aiDisambiguatedRecipeDraft(from draft: RecipeResolutionDraft) async throws -> RecipeResolutionDraft {
        guard !draft.requiresIngredientEdits else {
            throw AIRecipeNormalizationError.disambiguationFailed(draft.unknownIngredients.map { $0.ingredient.rawName })
        }

        let ambiguousIngredients = draft.ambiguousIngredients
        guard !ambiguousIngredients.isEmpty else {
            return draft
        }

        let requests = ambiguousIngredients.map { ingredientDraft in
            IngredientResolutionRequest(
                ingredientID: ingredientDraft.ingredient.id,
                rawName: ingredientDraft.ingredient.rawName,
                quantity: ingredientDraft.ingredient.quantity,
                unit: ingredientDraft.ingredient.unit,
                category: ingredientDraft.ingredient.category,
                notes: ingredientDraft.ingredient.notes,
                candidates: ingredientDraft.candidates
            )
        }

        guard let decisions = await aiService.disambiguateIngredients(requests),
              decisions.count == requests.count else {
            throw AIRecipeNormalizationError.disambiguationFailed(ambiguousIngredients.map { $0.ingredient.rawName })
        }

        let decisionsByIngredient = Dictionary(uniqueKeysWithValues: decisions.map { ($0.ingredientID, $0) })
        var updatedDraft = draft

        for index in updatedDraft.ingredients.indices {
            guard updatedDraft.ingredients[index].status == .ambiguous else {
                continue
            }

            let ingredientDraft = updatedDraft.ingredients[index]
            guard let decision = decisionsByIngredient[ingredientDraft.ingredient.id],
                  decision.status == .resolved,
                  let selectedCandidateID = decision.selectedCandidateID,
                  let candidate = ingredientDraft.candidates.first(where: { $0.id == selectedCandidateID }) else {
                throw AIRecipeNormalizationError.disambiguationFailed([ingredientDraft.ingredient.rawName])
            }

            updatedDraft.ingredients[index].status = .resolved
            updatedDraft.ingredients[index].selectedCandidateID = candidate.id
            updatedDraft.ingredients[index].confidence = max(decision.confidence, candidate.score)
            updatedDraft.ingredients[index].rationale = decision.rationale
        }

        guard updatedDraft.isReadyToBuild, !updatedDraft.requiresIngredientEdits else {
            let unresolvedNames = updatedDraft.ingredients
                .filter { $0.status != .resolved }
                .map { $0.ingredient.rawName }
            throw AIRecipeNormalizationError.disambiguationFailed(unresolvedNames)
        }

        return updatedDraft
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
        let linkedDishes = preparedDishes.filter { $0.recipeID == recipe.id }
        guard !linkedDishes.isEmpty else { return }

        for dish in linkedDishes {
            var draft = PreparedDishDraft(dish: dish)
            draft.syncLinkedRecipe(recipe)

            guard let syncedDish = draft.buildDish(using: recipe) else { continue }

            do {
                let updatedDish = try await storageService.updatePreparedDish(syncedDish)
                if let index = preparedDishes.firstIndex(where: { $0.id == updatedDish.id }) {
                    preparedDishes[index] = updatedDish
                }
            } catch {
                pushError(.storage(error))
                return
            }
        }

        markPreparedDishesChanged()
    }

    func removeFromMyRecipes(id: UUID) async {
        guard let saved = recipes.first(where: { $0.id == id }) else { return }
        do {
            try await storageService.deleteRecipe(saved)
            recipes.removeAll { $0.id == id }
        } catch {
            pushError(.storage(error))
        }
    }
}
