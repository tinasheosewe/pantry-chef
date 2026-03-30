import Foundation

@MainActor
protocol RecipeDomainState: AnyObject {
    var pantryItems: [PantryItem] { get }
    var recipes: [Recipe] { get }
    var discoverRecipeStore: [AppState.DiscoverRecipeRecord] { get }
    var storageService: StorageServiceProtocol { get }
    var aiService: AIServiceProtocol { get }
    var recipeIngredientResolver: RecipeIngredientResolverProtocol { get }

    func pushError(_ error: AppError)
    func setRecipes(_ items: [Recipe])
    func setDiscoverRecipes(_ items: [AppState.DiscoverRecipeRecord])
    func persistedDiscoverRecipes() -> [Recipe]
    func mergedDiscoverRecipes(withPersisted persisted: [Recipe]) -> [AppState.DiscoverRecipeRecord]
    func syncPreparedDishesLinked(to recipe: Recipe) async
}

@MainActor
protocol RecipeDomainServicing {
    func addRecipe(_ recipe: Recipe, state: any RecipeDomainState) async
    func updateRecipe(_ recipe: Recipe, state: any RecipeDomainState) async
    func deleteRecipe(_ recipe: Recipe, state: any RecipeDomainState) async
    func toggleFavoriteWithSave(_ recipe: Recipe, state: any RecipeDomainState) async
    func generateRecipe(query: String, preferences: RecipeGenerationPreferences, state: any RecipeDomainState) async -> RecipeGenerationResult?
    func importRecipeFromURL(_ urlString: String, state: any RecipeDomainState) async -> AppState.ReviewableImportedRecipe?
    func importRecipeFromText(_ text: String, state: any RecipeDomainState) async -> AppState.ReviewableImportedRecipe?
    func modifyRecipe(_ recipe: Recipe, feedback: String, state: any RecipeDomainState) async -> RecipeGenerationResult?
    func cacheDiscoverRecipe(_ recipe: AppState.NormalizedAIRecipe, state: any RecipeDomainState) async -> AppState.NormalizedAIRecipe?
    func cacheDiscoverRecipe(_ recipe: Recipe, state: any RecipeDomainState) async -> Recipe?
    func normalizedAIRecipe(_ recipe: Recipe, state: any RecipeDomainState) async -> AppState.NormalizedAIRecipe?
    func normalizeAIRecipes(_ recipes: [Recipe], state: any RecipeDomainState) async -> [AppState.NormalizedAIRecipe]
    func canonicalizedRecipeForPersistence(_ recipe: Recipe, state: any RecipeDomainState) async -> Recipe
    func preparedRecipeForIntake(_ recipe: Recipe, state: any RecipeDomainState) async throws -> Recipe
    func requireResolvedRecipeForPersistence(_ recipe: Recipe, state: any RecipeDomainState) async throws -> Recipe
    func requireNormalizedAIRecipe(_ recipe: Recipe, state: any RecipeDomainState) async throws -> AppState.NormalizedAIRecipe
    func importedRecipeDraft(from recipe: Recipe, state: any RecipeDomainState) async -> AppState.ReviewableImportedRecipe?
    func getShoppingList(for recipe: Recipe, state: any RecipeDomainState) async -> [ShoppingItem]
    func getRecipeSuggestions(state: any RecipeDomainState) async -> [AppState.NormalizedAIRecipe]
    func getSubstitutions(for recipe: Recipe, state: any RecipeDomainState) async -> [SubstitutionSuggestion]
    func getHealthierVersion(of recipe: Recipe, state: any RecipeDomainState) async -> HealthierSuggestion?
    func getLeftoverIdeas(ingredients: [String], state: any RecipeDomainState) async -> [AppState.NormalizedAIRecipe]
    func suggestRecipeNames(ingredients: [String], strictIngredients: Bool, requireAllIngredients: Bool, excludeNames: [String], state: any RecipeDomainState) async -> RecipeNameSuggestionsResult
    func generateRecipeFromSuggestion(_ suggestion: RecipeNameSuggestion, ingredients: [String], strictIngredients: Bool, requireAllIngredients: Bool, state: any RecipeDomainState) async -> AppState.NormalizedAIRecipe?
}

@MainActor
struct RecipeDomainService: RecipeDomainServicing {
    func addRecipe(_ recipe: Recipe, state: any RecipeDomainState) async {
        do {
            let recipeToPersist = try await preparedRecipeForIntake(recipe, state: state)

            let saved = try await state.storageService.addRecipe(recipeToPersist)
            if saved.source.isUserRecipe {
                state.setRecipes(state.recipes + [saved])
            } else {
                state.setDiscoverRecipes(
                    state.mergedDiscoverRecipes(withPersisted: state.persistedDiscoverRecipes() + [saved])
                )
            }
        } catch {
            state.pushError(.storage(error))
        }
    }

    func updateRecipe(_ recipe: Recipe, state: any RecipeDomainState) async {
        do {
            let recipeToPersist = try await preparedRecipeForIntake(recipe, state: state)

            let updated = try await state.storageService.updateRecipe(recipeToPersist)
            if let index = state.recipes.firstIndex(where: { $0.id == recipe.id }) {
                var recipes = state.recipes
                recipes[index] = updated
                state.setRecipes(recipes)
            } else if let index = state.discoverRecipeStore.firstIndex(where: { $0.id == recipe.id }),
                      let discoverRecord = AppState.DiscoverRecipeRecord.persisted(updated) {
                var discoverRecipes = state.discoverRecipeStore
                discoverRecipes[index] = discoverRecord
                state.setDiscoverRecipes(discoverRecipes)
            }

            await state.syncPreparedDishesLinked(to: updated)
        } catch {
            state.pushError(.storage(error))
        }
    }

    func toggleFavoriteWithSave(_ recipe: Recipe, state: any RecipeDomainState) async {
        var updated = recipe
        updated.isFavorite.toggle()

        let isAlreadyInMyRecipes = state.recipes.contains { $0.id == recipe.id }
        let discoverRecipes = state.discoverRecipeStore.map(\.recipe)
        let hasLinkedDiscoverRecipe = discoverRecipes.contains { $0.id == recipe.id && !$0.source.isUserRecipe }

        if updated.isFavorite && !isAlreadyInMyRecipes {
            var savedCopy = updated
            savedCopy.source = .user
            await addRecipe(savedCopy, state: state)
        } else if !updated.isFavorite && isAlreadyInMyRecipes && (!recipe.source.isUserRecipe || hasLinkedDiscoverRecipe) {
            await removeFromMyRecipes(id: recipe.id, state: state)
        } else {
            await updateRecipe(updated, state: state)
        }

        if let idx = state.discoverRecipeStore.firstIndex(where: { $0.id == recipe.id }) {
            var discoverRecipes = state.discoverRecipeStore
            discoverRecipes[idx].recipe.isFavorite = updated.isFavorite
            state.setDiscoverRecipes(discoverRecipes)
        }
    }

    func deleteRecipe(_ recipe: Recipe, state: any RecipeDomainState) async {
        do {
            try await state.storageService.deleteRecipe(recipe)

            let updatedRecipes = state.recipes.filter { $0.id != recipe.id }
            if updatedRecipes.count != state.recipes.count {
                state.setRecipes(updatedRecipes)
            }

            if !recipe.source.isUserRecipe {
                let updatedDiscover = state.discoverRecipeStore.filter { $0.id != recipe.id }
                if updatedDiscover.count != state.discoverRecipeStore.count {
                    state.setDiscoverRecipes(updatedDiscover)
                }
            }
        } catch {
            state.pushError(.storage(error))
        }
    }

    func cacheDiscoverRecipe(_ recipe: AppState.NormalizedAIRecipe, state: any RecipeDomainState) async -> AppState.NormalizedAIRecipe? {
        do {
            _ = try await state.storageService.updateRecipe(recipe.rawValue)
            state.setDiscoverRecipes(
                state.mergedDiscoverRecipes(withPersisted: state.persistedDiscoverRecipes() + [recipe.rawValue])
            )
        } catch {
            state.pushError(.storage(error))
        }

        return recipe
    }

    func cacheDiscoverRecipe(_ recipe: Recipe, state: any RecipeDomainState) async -> Recipe? {
        let recipeToPersist: Recipe
        do {
            recipeToPersist = try await preparedRecipeForIntake(recipe, state: state)
        } catch {
            state.pushError(.storage(error))
            return nil
        }

        guard let discoverRecord = AppState.DiscoverRecipeRecord(nonAIRecipe: recipeToPersist) else {
            return nil
        }

        do {
            _ = try await state.storageService.updateRecipe(discoverRecord.recipe)
            state.setDiscoverRecipes(
                state.mergedDiscoverRecipes(withPersisted: state.persistedDiscoverRecipes() + [discoverRecord.recipe])
            )
        } catch {
            state.pushError(.storage(error))
        }

        return discoverRecord.recipe
    }

    func normalizedAIRecipe(_ recipe: Recipe, state: any RecipeDomainState) async -> AppState.NormalizedAIRecipe? {
        do {
            return try await requireNormalizedAIRecipe(recipe, state: state)
        } catch {
            state.pushError(.storage(error))
            return nil
        }
    }

    func normalizeAIRecipes(_ recipes: [Recipe], state: any RecipeDomainState) async -> [AppState.NormalizedAIRecipe] {
        var normalizedRecipes: [AppState.NormalizedAIRecipe] = []
        normalizedRecipes.reserveCapacity(recipes.count)

        for recipe in recipes {
            guard let normalizedRecipe = await normalizedAIRecipe(recipe, state: state) else {
                return []
            }
            normalizedRecipes.append(normalizedRecipe)
        }

        return normalizedRecipes
    }

    func canonicalizedRecipeForPersistence(_ recipe: Recipe, state: any RecipeDomainState) async -> Recipe {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await state.recipeIngredientResolver.resolve(recipe: canonicalRecipe)

        if resolutionDraft.isReadyToBuild {
            return resolutionDraft.builtRecipe()
        }

        return canonicalRecipe
    }

    func preparedRecipeForIntake(_ recipe: Recipe, state: any RecipeDomainState) async throws -> Recipe {
        if recipe.source == .aiGenerated {
            return try await requireNormalizedAIRecipe(recipe, state: state).rawValue
        }

        return try await requireResolvedRecipeForPersistence(recipe, state: state)
    }

    func requireResolvedRecipeForPersistence(_ recipe: Recipe, state: any RecipeDomainState) async throws -> Recipe {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await state.recipeIngredientResolver.resolve(recipe: canonicalRecipe)

        guard resolutionDraft.isReadyToBuild, !resolutionDraft.requiresIngredientEdits else {
            let unresolvedNames = unresolvedIngredientNames(in: resolutionDraft)
            throw AppState.RecipeIntakeNormalizationError.unresolvedIngredients(unresolvedNames)
        }

        return resolutionDraft.builtRecipe()
    }

    func requireNormalizedAIRecipe(_ recipe: Recipe, state: any RecipeDomainState) async throws -> AppState.NormalizedAIRecipe {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await state.recipeIngredientResolver.resolve(recipe: canonicalRecipe)
        let disambiguatedDraft = try await aiDisambiguatedRecipeDraft(from: resolutionDraft, state: state)
        return AppState.NormalizedAIRecipe(rawValue: disambiguatedDraft.builtRecipe())
    }

    func importedRecipeDraft(from recipe: Recipe, state: any RecipeDomainState) async -> AppState.ReviewableImportedRecipe? {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await state.recipeIngredientResolver.resolve(recipe: canonicalRecipe)
        let resolvedRecipe = resolutionDraft.isReadyToBuild ? resolutionDraft.builtRecipe() : canonicalRecipe
        return AppState.ReviewableImportedRecipe(recipe: resolvedRecipe)
    }

    func generateRecipe(query: String, preferences: RecipeGenerationPreferences, state: any RecipeDomainState) async -> RecipeGenerationResult? {
        guard !Task.isCancelled else { return nil }
        guard let result = await state.aiService.generateRecipe(query: query, preferences: preferences) else {
            if !Task.isCancelled {
                pushAIFailure("recipe generation", fallbackMessage: "Couldn't create a recipe right now. Please try again.", state: state)
            }
            return nil
        }

        switch result {
        case .recipe(let recipe):
            guard let normalized = await normalizedAIRecipe(recipe, state: state) else {
                return nil
            }
            return .recipe(normalized.recipe)
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func importRecipeFromURL(_ urlString: String, state: any RecipeDomainState) async -> AppState.ReviewableImportedRecipe? {
        guard !Task.isCancelled else { return nil }
        guard let result = await state.aiService.parseRecipeFromURL(urlString) else {
            if !Task.isCancelled {
                pushAIFailure("recipe import", fallbackMessage: "Couldn't parse that recipe URL right now. Please try again.", state: state)
            }
            return nil
        }

        return await importedRecipeDraft(from: result.toRecipe(source: .imported), state: state)
    }

    func importRecipeFromText(_ text: String, state: any RecipeDomainState) async -> AppState.ReviewableImportedRecipe? {
        guard !Task.isCancelled else { return nil }
        guard let result = await state.aiService.parseRecipeFromText(text) else {
            if !Task.isCancelled {
                pushAIFailure("recipe import", fallbackMessage: "Couldn't parse that recipe text right now. Please try again.", state: state)
            }
            return nil
        }

        return await importedRecipeDraft(from: result.toRecipe(source: .imported), state: state)
    }

    func getShoppingList(for recipe: Recipe, state: any RecipeDomainState) async -> [ShoppingItem] {
        var items = await state.aiService.generateShoppingList(recipe: recipe, pantry: state.pantryItems)
        for index in items.indices {
            items[index].recipeSource = recipe.title
        }
        return items
    }

    func getRecipeSuggestions(state: any RecipeDomainState) async -> [AppState.NormalizedAIRecipe] {
        guard !Task.isCancelled else { return [] }
        let suggestedRecipes = await state.aiService.suggestRecipes(pantry: state.pantryItems)
        guard !Task.isCancelled else { return [] }
        let normalized = await normalizeAIRecipes(suggestedRecipes, state: state)
        if normalized.isEmpty, !state.pantryItems.isEmpty {
            pushAIFailure("recipe suggestions", fallbackMessage: "Couldn't find recipe suggestions right now. Please try again.", state: state)
        }
        return normalized
    }

    func getSubstitutions(for recipe: Recipe, state: any RecipeDomainState) async -> [SubstitutionSuggestion] {
        await state.aiService.suggestSubstitutions(recipe: recipe, pantry: state.pantryItems)
    }

    func getHealthierVersion(of recipe: Recipe, state: any RecipeDomainState) async -> HealthierSuggestion? {
        guard !Task.isCancelled else { return nil }
        let suggestion = await state.aiService.makeItHealthier(recipe: recipe)
        if suggestion == nil, !Task.isCancelled {
            pushAIFailure("healthier suggestion", fallbackMessage: "Couldn't find healthier options right now. Please try again.", state: state)
        }
        return suggestion
    }

    func getLeftoverIdeas(ingredients: [String], state: any RecipeDomainState) async -> [AppState.NormalizedAIRecipe] {
        let recipes = await state.aiService.leftoverTransformer(ingredients: ingredients)
        return await normalizeAIRecipes(recipes, state: state)
    }

    func suggestRecipeNames(ingredients: [String], strictIngredients: Bool, requireAllIngredients: Bool, excludeNames: [String], state: any RecipeDomainState) async -> RecipeNameSuggestionsResult {
        await state.aiService.suggestRecipeNames(ingredients: ingredients, strictIngredients: strictIngredients, requireAllIngredients: requireAllIngredients, excludeNames: excludeNames)
    }

    func generateRecipeFromSuggestion(_ suggestion: RecipeNameSuggestion, ingredients: [String], strictIngredients: Bool, requireAllIngredients: Bool, state: any RecipeDomainState) async -> AppState.NormalizedAIRecipe? {
        guard !Task.isCancelled else { return nil }
        guard let recipe = await state.aiService.generateRecipeFromSuggestion(suggestion, ingredients: ingredients, strictIngredients: strictIngredients, requireAllIngredients: requireAllIngredients) else {
            if !Task.isCancelled {
                pushAIFailure("recipe generation", fallbackMessage: "Couldn't create a recipe right now. Please try again.", state: state)
            }
            return nil
        }

        return await bestEffortNormalizedAIRecipe(recipe, state: state)
    }

    func modifyRecipe(_ recipe: Recipe, feedback: String, state: any RecipeDomainState) async -> RecipeGenerationResult? {
        let pantryNames = state.pantryItems.map(\.name)
        guard !Task.isCancelled else { return nil }
        guard let result = await state.aiService.modifyRecipe(recipe, feedback: feedback, pantryIngredients: pantryNames) else {
            if !Task.isCancelled {
                pushAIFailure("recipe modification", fallbackMessage: "Couldn't modify the recipe right now. Please try again.", state: state)
            }
            return nil
        }

        switch result {
        case .recipe(let modifiedRecipe):
            let normalized = await bestEffortNormalizedAIRecipe(modifiedRecipe, state: state)
            return .recipe(normalized.recipe)
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    private func unresolvedIngredientNames(in draft: RecipeResolutionDraft) -> [String] {
        let ambiguous = draft.ambiguousIngredients.map { $0.ingredient.rawName }
        let unknown = draft.unknownIngredients.map { $0.ingredient.rawName }
        let names = ambiguous + unknown
        return names.isEmpty ? draft.recipe.ingredients.map(\.rawName) : names
    }

    private func aiDisambiguatedRecipeDraft(from draft: RecipeResolutionDraft, state: any RecipeDomainState) async throws -> RecipeResolutionDraft {
        guard !draft.requiresIngredientEdits else {
            throw AppState.AIRecipeNormalizationError.disambiguationFailed(draft.unknownIngredients.map { $0.ingredient.rawName })
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

        guard let decisions = await state.aiService.disambiguateIngredients(requests),
              decisions.count == requests.count else {
            throw AppState.AIRecipeNormalizationError.disambiguationFailed(ambiguousIngredients.map { $0.ingredient.rawName })
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
                throw AppState.AIRecipeNormalizationError.disambiguationFailed([ingredientDraft.ingredient.rawName])
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
            throw AppState.AIRecipeNormalizationError.disambiguationFailed(unresolvedNames)
        }

        return updatedDraft
    }

    /// Best-effort normalization for recipe modifications: resolves what it can,
    /// keeps unmatched ingredients as unresolved rather than failing entirely.
    private func bestEffortNormalizedAIRecipe(_ recipe: Recipe, state: any RecipeDomainState) async -> AppState.NormalizedAIRecipe {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await state.recipeIngredientResolver.resolve(recipe: canonicalRecipe)
        let finalDraft = await bestEffortDisambiguatedDraft(from: resolutionDraft, state: state)
        return AppState.NormalizedAIRecipe(rawValue: finalDraft.builtRecipe())
    }

    private func bestEffortDisambiguatedDraft(from draft: RecipeResolutionDraft, state: any RecipeDomainState) async -> RecipeResolutionDraft {
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

        guard let decisions = await state.aiService.disambiguateIngredients(requests),
              decisions.count == requests.count else {
            return draft
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
                continue
            }

            updatedDraft.ingredients[index].status = .resolved
            updatedDraft.ingredients[index].selectedCandidateID = candidate.id
            updatedDraft.ingredients[index].confidence = max(decision.confidence, candidate.score)
            updatedDraft.ingredients[index].rationale = decision.rationale
        }

        return updatedDraft
    }

    private func removeFromMyRecipes(id: UUID, state: any RecipeDomainState) async {
        guard let saved = state.recipes.first(where: { $0.id == id }) else { return }
        do {
            try await state.storageService.deleteRecipe(saved)
            state.setRecipes(state.recipes.filter { $0.id != id })
        } catch {
            state.pushError(.storage(error))
        }
    }

    private func pushAIFailure(_ operation: String, fallbackMessage: String, state: any RecipeDomainState) {
        state.pushError(.ai(operation: operation, message: fallbackMessage))
    }
}

@MainActor
extension AppState: RecipeDomainState {}