import SwiftUI

@MainActor
enum SearchQuerySupport {
    static func normalized(_ text: String) -> String {
        text.trimmed
    }

    static func filtered<T>(_ items: [T], query: String, text: (T) -> String) -> [T] {
        guard !query.isEmpty else { return items }
        return items.filter { text($0).localizedCaseInsensitiveContains(query) }
    }

    static func schedule(
        text: String,
        debouncer: TaskDebouncer,
        after delay: UInt64 = DebounceDurations.quickSearch,
        update: @escaping @MainActor (String) -> Void
    ) {
        debouncer.cancel()
        let normalized = normalized(text)
        debouncer.schedule(after: delay) {
            update(normalized)
        }
    }
}

@MainActor
protocol AsyncActionHandling: AnyObject {
    var isLoading: Bool { get set }
    var appState: AppState { get }
}

extension AsyncActionHandling {
    func runTask(_ operation: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            await operation()
        }
    }

    func runLoadingTask(_ operation: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            await performLoadingTask(operation)
        }
    }

    func performLoadingTask(_ operation: @escaping @MainActor () async -> Void) async {
        isLoading = true
        defer { isLoading = false }
        await operation()
    }

    func captureError(_ error: any Error) {
        appState.errorMessage = error.localizedDescription
    }
}

@MainActor
struct PantryActions {
    let appState: AppState

    private var inventoryGateway: InventoryGateway {
        appState.inventoryGateway
    }

    func addItem(_ item: PantryItem) async {
        await inventoryGateway.upsertPantryItem(item)
    }

    func deleteItem(_ item: PantryItem) async {
        await inventoryGateway.removePantryItem(item)
    }

    func updateItem(_ item: PantryItem) async {
        await inventoryGateway.upsertPantryItem(item)
    }

    @discardableResult
    func addStagedItems(_ drafts: [PantryIntakeRowDraft]) async -> Int {
        var addedCount = 0
        for draft in drafts {
            guard let item = draft.buildItem() else { continue }
            await inventoryGateway.upsertPantryItem(item)
            addedCount += 1
        }
        return addedCount
    }
}

@MainActor
struct ShoppingActions {
    let appState: AppState

    private var inventoryGateway: InventoryGateway {
        appState.inventoryGateway
    }

    func toggleItem(_ item: ShoppingItem) async {
        await inventoryGateway.toggleShoppingItem(item)
    }

    func removeCheckedItems() async {
        await inventoryGateway.removeCheckedShoppingItems()
    }

    func addItem(_ item: ShoppingItem) async {
        await inventoryGateway.upsertShoppingItem(item)
    }

    func removeItem(_ item: ShoppingItem) async {
        await inventoryGateway.removeShoppingItem(item)
    }

    func updateItem(_ item: ShoppingItem) async {
        await inventoryGateway.upsertShoppingItem(item)
    }

    func completeCheckedToPantry(with items: [ShoppingItem]) async {
        await inventoryGateway.replaceShoppingItems(items)
        await addCheckedToPantry()
    }

    func addCheckedToPantry() async {
        await inventoryGateway.transferCheckedShoppingItemsToPantry()
    }
}

@MainActor
struct MealPlanActions {
    let appState: AppState

    private var mealPlanGateway: MealPlanGateway {
        appState.mealPlanGateway
    }

    func assignRecipe(_ recipe: Recipe, to slot: MealPlanViewModel.MealSlot) async {
        await mealPlanGateway.planRecipe(recipe, on: slot.date, mealType: slot.mealType, replaceExisting: slot.replaceExisting)
    }

    func assignPreparedDish(_ dish: PreparedDish, to slot: MealPlanViewModel.MealSlot) async {
        await mealPlanGateway.planPreparedDish(dish, on: slot.date, mealType: slot.mealType, replaceExisting: slot.replaceExisting)
    }

    func assignSelections(_ selections: [MealSelectionItem], to slot: MealPlanViewModel.MealSlot) async {
        await mealPlanGateway.planSelections(selections, on: slot.date, mealType: slot.mealType, replaceExisting: slot.replaceExisting)
    }

    func removeEntry(_ entry: MealPlanEntry) async {
        await mealPlanGateway.removeEntries([entry])
    }

    func removeEntries(_ entries: [MealPlanEntry]) async {
        await mealPlanGateway.removeEntries(entries)
    }

    func updateEntry(_ entry: MealPlanEntry) async {
        await mealPlanGateway.updateEntry(entry)
    }

    func logEntriesEaten(_ selections: [MealPlanEatenLoggingSelection]) async {
        await mealPlanGateway.logEntriesEaten(selections)
    }

    func generateShoppingList() async {
        let items = appState.previewShoppingListFromMealPlan()
        await mealPlanGateway.addShoppingItems(items)
    }

    func addShoppingItems(_ items: [ShoppingItem]) async {
        await mealPlanGateway.addShoppingItems(items)
    }

    func addEntriesToCookQueue(_ entries: [MealPlanEntry], asParallelBatch: Bool) async {
        await mealPlanGateway.addEntriesToCookQueue(entries, asParallelBatch: asParallelBatch)
    }
}

@MainActor
struct RecipeActions {
    let appState: AppState

    private var recipeGateway: RecipeGateway {
        appState.recipeGateway
    }

    func addRecipe(_ recipe: Recipe) async {
        await recipeGateway.addRecipe(recipe)
    }

    func deleteRecipe(_ recipe: Recipe) async {
        await recipeGateway.deleteRecipe(recipe)
    }

    func toggleFavorite(_ recipe: Recipe) async {
        await recipeGateway.toggleFavoriteWithSave(recipe)
    }
}

@MainActor
struct PreparedDishActions {
    let appState: AppState

    private var inventoryGateway: InventoryGateway {
        appState.inventoryGateway
    }

    func addDish(_ dish: PreparedDish) async {
        await inventoryGateway.upsertPreparedDish(dish)
    }

    func updateDish(_ dish: PreparedDish) async {
        await inventoryGateway.upsertPreparedDish(dish)
    }

    func deleteDish(_ dish: PreparedDish) async {
        await inventoryGateway.removePreparedDish(dish)
    }

    func adjustServings(_ dish: PreparedDish, delta: Int) async -> Bool {
        await inventoryGateway.adjustPreparedDishServings(dish, delta: delta)
    }
}
