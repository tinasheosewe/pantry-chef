import SwiftUI

@Observable
@MainActor
final class AppState {
    // MARK: - Services (protocol-typed for testability)
    let storageService: StorageServiceProtocol
    let aiService: AIServiceProtocol
    let recipeRepository = RecipeRepository.shared

    // MARK: - Shared State
    var pantryItems: [PantryItem] = []
    var recipes: [Recipe] = []    // User's own recipes
    var mealPlan: [MealPlanEntry] = []
    var shoppingItems: [ShoppingItem] = []
    var isLoading = false
    var errorMessage: String?

    /// Set by notification tap to deep-link into cook mode for a specific recipe.
    var deepLinkCookModeRecipeId: String?

    /// Tracks all active cooking sessions for the UI.
    let activeCooks = ActiveCooksManager()

    // MARK: - Computed
    var expiringItems: [PantryItem] {
        let threeDaysFromNow = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return pantryItems
            .filter { $0.expiryDate != nil && $0.expiryDate! <= threeDaysFromNow }
            .sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }
    }

    var expiredItems: [PantryItem] {
        pantryItems.filter { $0.expiryDate != nil && $0.expiryDate! < Date() }
    }

    var pantryByCategory: [FoodCategory: [PantryItem]] {
        Dictionary(grouping: pantryItems, by: { $0.category })
    }

    /// All non-user recipes (bundled + cached API) — eagerly loaded for observability
    var discoverRecipes: [Recipe] = []

    /// All recipes combined (user + discover) for unified search
    var allRecipes: [Recipe] {
        recipes + discoverRecipes
    }

    /// Resolve a recipe by UUID string across all known sources.
    func recipeByIdString(_ id: String) -> Recipe? {
        allRecipes.first { $0.id.uuidString == id }
    }

    /// Reload discover recipes from the repository (call after caching new recipes)
    func refreshDiscoverRecipes() {
        discoverRecipes = mergedDiscoverRecipes(withPersisted: discoverRecipes.filter { !$0.source.isUserRecipe })
    }

    // MARK: - Init (DI-friendly)
    init() {
        self.storageService = StorageService()
        self.aiService = AIService()
        // Start with sample defaults and then hydrate from durable storage.
        pantryItems = PantryItem.samples
        recipes = Recipe.samples
        discoverRecipes = recipeRepository.seedRecipes
        Task { await loadAllData() }
    }

    init(storageService: StorageServiceProtocol, aiService: AIServiceProtocol) {
        self.storageService = storageService
        self.aiService = aiService
        pantryItems = PantryItem.samples
        recipes = Recipe.samples
        discoverRecipes = recipeRepository.seedRecipes
        Task { await loadAllData() }
    }

    // MARK: - Data Loading (for refresh / future network-backed store)
    func loadAllData() async {
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            async let items = storageService.fetchPantryItems()
            async let recipeList = storageService.fetchRecipes()
            async let plan = storageService.fetchMealPlan()
            async let shopping = storageService.fetchShoppingItems()

            let (fetchedItems, fetchedRecipes, fetchedPlan, fetchedShopping) = try await (items, recipeList, plan, shopping)
            pantryItems = fetchedItems
            recipes = fetchedRecipes.filter { $0.source.isUserRecipe }
            let persistedDiscover = fetchedRecipes.filter { !$0.source.isUserRecipe }
            discoverRecipes = mergedDiscoverRecipes(withPersisted: persistedDiscover)
            mealPlan = fetchedPlan
            shoppingItems = fetchedShopping
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pantry Actions
    func addPantryItem(_ item: PantryItem) async {
        do {
            let saved = try await storageService.addPantryItem(item)
            pantryItems.append(saved)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removePantryItem(_ item: PantryItem) async {
        do {
            try await storageService.deletePantryItem(item)
            pantryItems.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePantryItem(_ item: PantryItem) async {
        do {
            let updated = try await storageService.updatePantryItem(item)
            if let index = pantryItems.firstIndex(where: { $0.id == item.id }) {
                pantryItems[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Recipe Actions
    func addRecipe(_ recipe: Recipe) async {
        do {
            let saved = try await storageService.addRecipe(recipe)
            if saved.source.isUserRecipe {
                recipes.append(saved)
            } else {
                discoverRecipes = mergedDiscoverRecipes(withPersisted: discoverRecipes.filter { !$0.source.isUserRecipe } + [saved])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateRecipe(_ recipe: Recipe) async {
        do {
            let updated = try await storageService.updateRecipe(recipe)
            if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
                recipes[index] = updated
            } else if let index = discoverRecipes.firstIndex(where: { $0.id == recipe.id }) {
                discoverRecipes[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle favorite and handle cross-list movement:
    /// - Favoriting a discover/AI recipe saves a copy into My Recipes (with isFavorite = true)
    /// - Unfavoriting a saved-from-discover recipe removes it from My Recipes
    func toggleFavoriteWithSave(_ recipe: Recipe) async {
        var updated = recipe
        updated.isFavorite.toggle()

        let isAlreadyInMyRecipes = recipes.contains { $0.id == recipe.id }

        if updated.isFavorite && !isAlreadyInMyRecipes {
            // Save to My Recipes
            await addRecipe(updated)
        } else if !updated.isFavorite && isAlreadyInMyRecipes && !recipe.source.isUserRecipe {
            // Remove non-user recipes from My Recipes when un-hearted
            await deleteRecipe(updated)
        } else {
            // Normal update for user-created recipes
            await updateRecipe(updated)
        }

        // Also update in discover cache so the heart state is reflected there
        if let idx = discoverRecipes.firstIndex(where: { $0.id == recipe.id }) {
            discoverRecipes[idx].isFavorite = updated.isFavorite
        }
    }

    func deleteRecipe(_ recipe: Recipe) async {
        do {
            try await storageService.deleteRecipe(recipe)
            recipes.removeAll { $0.id == recipe.id }
            discoverRecipes.removeAll { $0.id == recipe.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cacheDiscoverRecipe(_ recipe: Recipe) async {
        guard !recipe.source.isUserRecipe else { return }
        do {
            _ = try await storageService.updateRecipe(recipe)
            let persistedDiscover = discoverRecipes.filter { !$0.source.isUserRecipe && $0.source != .bundled }
            discoverRecipes = mergedDiscoverRecipes(withPersisted: persistedDiscover + [recipe])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - AI Actions
    func getShoppingList(for recipe: Recipe) async -> [ShoppingItem] {
        await aiService.generateShoppingList(recipe: recipe, pantry: pantryItems)
    }

    func getRecipeSuggestions() async -> [Recipe] {
        await aiService.suggestRecipes(pantry: pantryItems)
    }

    func getSubstitutions(for recipe: Recipe) async -> [SubstitutionSuggestion] {
        await aiService.suggestSubstitutions(recipe: recipe, pantry: pantryItems)
    }

    func getHealthierVersion(of recipe: Recipe) async -> HealthierSuggestion? {
        await aiService.makeItHealthier(recipe: recipe)
    }

    func getLeftoverIdeas(ingredients: [String]) async -> [Recipe] {
        await aiService.leftoverTransformer(ingredients: ingredients)
    }

    // MARK: - Meal Plan Actions
    func addToMealPlan(_ entry: MealPlanEntry) async {
        do {
            let saved = try await storageService.addMealPlanEntry(entry)
            mealPlan.append(saved)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFromMealPlan(_ entry: MealPlanEntry) async {
        do {
            try await storageService.deleteMealPlanEntry(entry)
            mealPlan.removeAll { $0.id == entry.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Shopping Actions
    func generateShoppingListFromMealPlan() async {
        let recipes = mealPlan.compactMap { $0.recipe }
        let allIngredients = recipes.flatMap { $0.ingredients }
        let missing = allIngredients.filter { ingredient in
            !pantryItems.contains { pantryItem in
                IngredientMatcher.namesMatch(pantryItem.name, ingredient.name) &&
                IngredientMatcher.hasEnoughQuantity(pantryItem: pantryItem, ingredient: ingredient)
            }
        }
        shoppingItems = missing.map { ingredient in
            ShoppingItem(
                name: ingredient.name,
                quantity: ingredient.quantity,
                unit: ingredient.unit,
                category: ingredient.category,
                isChecked: false
            )
        }
        // Deduplicate
        var seen = Set<String>()
        shoppingItems = shoppingItems.filter { seen.insert($0.name.lowercased()).inserted }
        await persistShoppingItems()
    }

    func toggleShoppingItem(_ item: ShoppingItem) {
        if let index = shoppingItems.firstIndex(where: { $0.id == item.id }) {
            shoppingItems[index].isChecked.toggle()
            Task { await persistShoppingItems() }
        }
    }

    func setShoppingItems(_ items: [ShoppingItem]) async {
        shoppingItems = items
        await persistShoppingItems()
    }

    func addShoppingItem(_ item: ShoppingItem) async {
        shoppingItems.append(item)
        await persistShoppingItems()
    }

    func removeShoppingItem(_ item: ShoppingItem) async {
        shoppingItems.removeAll { $0.id == item.id }
        await persistShoppingItems()
    }

    func removeCheckedShoppingItems() async {
        shoppingItems.removeAll { $0.isChecked }
        await persistShoppingItems()
    }

    // MARK: - Cook Mode
    func markRecipeAsCooked(_ recipe: Recipe) async {
        // Deduct ingredients from pantry
        for ingredient in recipe.ingredients {
            if let index = pantryItems.firstIndex(where: {
                IngredientMatcher.namesMatch($0.name, ingredient.name)
            }) {
                var item = pantryItems[index]
                let remaining = (item.quantity ?? 0) - ingredient.quantity
                if remaining <= 0 {
                    await removePantryItem(item)
                } else {
                    item.quantity = remaining
                    await updatePantryItem(item)
                }
            }
        }
    }

    private func persistShoppingItems() async {
        do {
            try await storageService.saveShoppingItems(shoppingItems)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mergedDiscoverRecipes(withPersisted persisted: [Recipe]) -> [Recipe] {
        let seed = recipeRepository.seedRecipes
        var result: [Recipe] = []
        var seen = Set<UUID>()

        for recipe in seed + persisted {
            if seen.insert(recipe.id).inserted {
                result.append(recipe)
            }
        }
        return result
    }
}
