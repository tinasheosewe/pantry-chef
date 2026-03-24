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

    func addItem(_ item: PantryItem) async {
        await appState.addPantryItem(item)
    }

    func deleteItem(_ item: PantryItem) async {
        await appState.removePantryItem(item)
    }

    func updateItem(_ item: PantryItem) async {
        await appState.updatePantryItem(item)
    }

    @discardableResult
    func addStagedItems(_ drafts: [PantryIntakeRowDraft]) async -> Int {
        var addedCount = 0
        for draft in drafts {
            guard let item = draft.buildItem() else { continue }
            await appState.addPantryItem(item)
            addedCount += 1
        }
        return addedCount
    }
}

@MainActor
struct ShoppingActions {
    let appState: AppState

    func toggleItem(_ item: ShoppingItem) async {
        await appState.toggleShoppingItem(item)
    }

    func removeCheckedItems() async {
        await appState.removeCheckedShoppingItems()
    }

    func addItem(_ item: ShoppingItem) async {
        await appState.addShoppingItem(item)
    }

    func removeItem(_ item: ShoppingItem) async {
        await appState.removeShoppingItem(item)
    }

    func addCheckedToPantry() async {
        let checkedItems = appState.shoppingItems.filter { $0.isChecked }
        for item in checkedItems {
            let pantryItem = PantryItem(
                name: item.name,
                category: item.category,
                quantity: item.quantity,
                unit: item.unit,
                catalogItemID: item.catalogItemID,
                facets: item.facets
            )
            await appState.addPantryItem(pantryItem)
        }
        await appState.removeCheckedShoppingItems()
    }
}

@MainActor
struct MealPlanActions {
    let appState: AppState

    func assignRecipe(_ recipe: Recipe, to slot: MealPlanViewModel.MealSlot) async {
        let entry = MealPlanEntry(
            date: slot.date,
            mealType: slot.mealType,
            recipe: recipe
        )
        await appState.addToMealPlan(entry, replaceExistingSlot: slot.replaceExisting)
    }

    func assignPreparedDish(_ dish: PreparedDish, to slot: MealPlanViewModel.MealSlot) async {
        let entry = MealPlanEntry(
            date: slot.date,
            mealType: slot.mealType,
            preparedDish: dish
        )
        await appState.addToMealPlan(entry, replaceExistingSlot: slot.replaceExisting)
    }

    func assignSelections(_ selections: [MealSelectionItem], to slot: MealPlanViewModel.MealSlot) async {
        let entries = selections.map { $0.makeEntry(date: slot.date, mealType: slot.mealType) }
        await appState.addToMealPlan(entries, replaceExistingSlot: slot.replaceExisting)
    }

    func removeEntry(_ entry: MealPlanEntry) async {
        await appState.removeFromMealPlan(entry)
    }

    func removeEntries(_ entries: [MealPlanEntry]) async {
        for entry in entries {
            await appState.removeFromMealPlan(entry)
        }
    }

    func updateEntry(_ entry: MealPlanEntry) async {
        await appState.updateMealPlanEntry(entry)
    }

    func logEntriesEaten(_ entries: [MealPlanEntry]) async {
        await appState.logMealPlanEntriesEaten(entries)
    }

    func generateShoppingList() async {
        await appState.generateShoppingListFromMealPlan()
    }

    func addShoppingItems(_ items: [ShoppingItem]) async {
        await appState.addShoppingItems(items)
    }
}

@MainActor
struct RecipeActions {
    let appState: AppState

    func addRecipe(_ recipe: Recipe) async {
        await appState.addRecipe(recipe)
    }

    func deleteRecipe(_ recipe: Recipe) async {
        await appState.deleteRecipe(recipe)
    }

    func toggleFavorite(_ recipe: Recipe) async {
        await appState.toggleFavoriteWithSave(recipe)
    }
}

@MainActor
struct PreparedDishActions {
    let appState: AppState

    func addDish(_ dish: PreparedDish) async {
        await appState.addPreparedDish(dish)
    }

    func updateDish(_ dish: PreparedDish) async {
        await appState.updatePreparedDish(dish)
    }

    func deleteDish(_ dish: PreparedDish) async {
        await appState.removePreparedDish(dish)
    }
}
