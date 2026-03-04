import SwiftUI

@Observable
@MainActor
final class AppState {
    // MARK: - Services (protocol-typed for testability)
    let storageService: StorageServiceProtocol
    let aiService: AIServiceProtocol

    // MARK: - Shared State
    var pantryItems: [PantryItem] = []
    var recipes: [Recipe] = []
    var mealPlan: [MealPlanEntry] = []
    var shoppingItems: [ShoppingItem] = []
    var isLoading = false
    var errorMessage: String?

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

    // MARK: - Init (DI-friendly)
    init() {
        self.storageService = StorageService()
        self.aiService = AIService()
        // Seed in-memory data synchronously — zero async overhead
        pantryItems = PantryItem.samples
        recipes = Recipe.samples
    }

    init(storageService: StorageServiceProtocol, aiService: AIServiceProtocol) {
        self.storageService = storageService
        self.aiService = aiService
        pantryItems = PantryItem.samples
        recipes = Recipe.samples
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
            recipes = fetchedRecipes
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
            recipes.append(saved)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRecipe(_ recipe: Recipe) async {
        do {
            try await storageService.deleteRecipe(recipe)
            recipes.removeAll { $0.id == recipe.id }
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
                let pName = pantryItem.name.lowercased()
                let iName = ingredient.name.lowercased()
                return (pName.contains(iName) || iName.contains(pName)) &&
                    (pantryItem.quantity ?? 0) >= ingredient.quantity
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
    }

    func toggleShoppingItem(_ item: ShoppingItem) {
        if let index = shoppingItems.firstIndex(where: { $0.id == item.id }) {
            shoppingItems[index].isChecked.toggle()
        }
    }

    // MARK: - Cook Mode
    func markRecipeAsCooked(_ recipe: Recipe) async {
        // Deduct ingredients from pantry
        for ingredient in recipe.ingredients {
            if let index = pantryItems.firstIndex(where: {
                let pName = $0.name.lowercased()
                let iName = ingredient.name.lowercased()
                return pName.contains(iName) || iName.contains(pName)
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
}
