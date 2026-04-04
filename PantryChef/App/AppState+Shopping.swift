import Foundation

// MARK: - Shopping Actions

extension AppState {
    func previewShoppingListFromMealPlan() -> [ShoppingItem] {
        shoppingDomainService.previewShoppingListFromMealPlan(state: self)
    }

    func generateShoppingListFromMealPlan() async {
        await shoppingDomainService.generateShoppingListFromMealPlan(state: self)
    }

    func addShoppingItems(_ items: [ShoppingItem]) async {
        await shoppingDomainService.addShoppingItems(items, state: self)
    }

    func toggleShoppingItem(_ item: ShoppingItem) async {
        await shoppingDomainService.toggleShoppingItem(item, state: self)
    }

    func setShoppingItems(_ items: [ShoppingItem]) async {
        await shoppingDomainService.setShoppingItems(items, state: self)
    }

    func addShoppingItem(_ item: ShoppingItem) async {
        await shoppingDomainService.addShoppingItem(item, state: self)
    }

    func removeShoppingItem(_ item: ShoppingItem) async {
        await shoppingDomainService.removeShoppingItem(item, state: self)
    }

    func updateShoppingItem(_ item: ShoppingItem) async {
        await shoppingDomainService.updateShoppingItem(item, state: self)
    }

    func replaceShoppingItems(_ items: [ShoppingItem]) async {
        await shoppingDomainService.replaceShoppingItems(items, state: self)
    }

    func removeCheckedShoppingItems() async {
        await shoppingDomainService.removeCheckedShoppingItems(state: self)
    }

    func persistShoppingItems() async {
        do {
            try await storageService.saveShoppingItems(shoppingItems)
        } catch {
            pushError(.storage(error))
        }
    }

    // MARK: - Shopping Helpers

    func shouldIncludeInShoppingList(_ ingredient: Ingredient) -> Bool {
        ShoppingListPolicy.shouldIncludeInShoppingList(ingredient, pantryItems: pantryItems)
    }

    func isExcludedShoppingIngredient(named name: String) -> Bool {
        ShoppingListPolicy.isExcludedShoppingIngredient(named: name)
    }

    func mergeShoppingItems(existing: [ShoppingItem], additions: [ShoppingItem]) -> [ShoppingItem] {
        ShoppingListPolicy.mergeShoppingItems(
            existing: existing,
            additions: additions,
            mergeRecipeSources: mergedRecipeSources,
            combineQuantity: combinedQuantity
        )
    }

    func mergeShoppingItem(_ existing: ShoppingItem, with addition: ShoppingItem) -> ShoppingItem {
        ShoppingListPolicy.mergeShoppingItems(
            existing: [existing],
            additions: [addition],
            mergeRecipeSources: mergedRecipeSources,
            combineQuantity: combinedQuantity
        ).first ?? existing
    }
}
