import Foundation

/// In-memory storage service conforming to StorageServiceProtocol.
/// Swap to a Supabase-backed implementation when you're ready to go cloud.
@MainActor
final class StorageService: StorageServiceProtocol {

    // MARK: - In-Memory Stores
    private var pantryStore: [PantryItem] = PantryItem.samples
    private var recipeStore: [Recipe] = Recipe.samples
    private var mealPlanStore: [MealPlanEntry] = []
    private var shoppingStore: [ShoppingItem] = []

    // MARK: - Pantry Items

    func fetchPantryItems() async throws -> [PantryItem] {
        pantryStore.sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }
    }

    func addPantryItem(_ item: PantryItem) async throws -> PantryItem {
        pantryStore.append(item)
        return item
    }

    func updatePantryItem(_ item: PantryItem) async throws -> PantryItem {
        if let idx = pantryStore.firstIndex(where: { $0.id == item.id }) {
            pantryStore[idx] = item
        }
        return item
    }

    func deletePantryItem(_ item: PantryItem) async throws {
        pantryStore.removeAll { $0.id == item.id }
    }

    // MARK: - Recipes

    func fetchRecipes() async throws -> [Recipe] {
        recipeStore.sorted { $0.dateAdded > $1.dateAdded }
    }

    func addRecipe(_ recipe: Recipe) async throws -> Recipe {
        recipeStore.append(recipe)
        return recipe
    }

    func updateRecipe(_ recipe: Recipe) async throws -> Recipe {
        if let idx = recipeStore.firstIndex(where: { $0.id == recipe.id }) {
            recipeStore[idx] = recipe
        }
        return recipe
    }

    func deleteRecipe(_ recipe: Recipe) async throws {
        recipeStore.removeAll { $0.id == recipe.id }
    }

    // MARK: - Meal Plan

    func fetchMealPlan() async throws -> [MealPlanEntry] {
        mealPlanStore.sorted { $0.date < $1.date }
    }

    func addMealPlanEntry(_ entry: MealPlanEntry) async throws -> MealPlanEntry {
        mealPlanStore.append(entry)
        return entry
    }

    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws -> MealPlanEntry {
        if let idx = mealPlanStore.firstIndex(where: { $0.id == entry.id }) {
            mealPlanStore[idx] = entry
        }
        return entry
    }

    func deleteMealPlanEntry(_ entry: MealPlanEntry) async throws {
        mealPlanStore.removeAll { $0.id == entry.id }
    }

    // MARK: - Shopping Items

    func fetchShoppingItems() async throws -> [ShoppingItem] {
        shoppingStore.sorted { $0.category.rawValue < $1.category.rawValue }
    }

    func saveShoppingItems(_ items: [ShoppingItem]) async throws {
        shoppingStore = items
    }
}
