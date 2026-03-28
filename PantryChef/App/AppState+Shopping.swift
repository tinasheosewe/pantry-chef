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
        guard !isExcludedShoppingIngredient(named: ingredient.name) else {
            return false
        }

        let exactMatchIngredient: Ingredient
        if ingredient.catalogItemID != nil {
            exactMatchIngredient = ingredient
        } else if let catalogItemID = IngredientMatcher.resolvedCatalogItemID(for: ingredient.name) {
            exactMatchIngredient = ingredient.resolved(to: catalogItemID, facets: ingredient.facets)
        } else {
            exactMatchIngredient = ingredient
        }

        return !pantryItems.contains { pantryItem in
            IngredientMatcher.pantryItemMatchesIngredient(pantryItem, ingredient: exactMatchIngredient)
                && IngredientMatcher.hasEnoughQuantity(pantryItem: pantryItem, ingredient: exactMatchIngredient)
        }
    }

    func isExcludedShoppingIngredient(named name: String) -> Bool {
        let normalized = IngredientMatcher.normalize(name)
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let waterModifiers: Set<String> = ["cold", "hot", "warm", "ice", "iced", "boiling", "filtered"]
        let ignoredWaterTokens = waterModifiers.union(["water"])

        if normalized == "water" {
            return true
        }

        return !tokens.isEmpty
            && tokens.contains("water")
            && tokens.subtracting(ignoredWaterTokens).isEmpty
    }

    func mergeShoppingItems(existing: [ShoppingItem], additions: [ShoppingItem]) -> [ShoppingItem] {
        var merged = existing

        for item in additions {
            guard !isExcludedShoppingIngredient(named: item.name) else { continue }

            if let index = merged.firstIndex(where: { $0.matchesIdentity(of: item) }) {
                merged[index] = mergeShoppingItem(merged[index], with: item)
            } else {
                merged.append(item)
            }
        }

        return merged
    }

    func mergeShoppingItem(_ existing: ShoppingItem, with addition: ShoppingItem) -> ShoppingItem {
        var merged = existing
        merged.catalogItemID = existing.catalogItemID ?? addition.catalogItemID
        merged.name = merged.resolvedCatalogItem?.name ?? (
            existing.name.count <= addition.name.count ? existing.name : addition.name
        )

        if merged.category == .other {
            merged.category = addition.category
        }

        merged.recipeSource = mergedRecipeSources(existing.recipeSource, addition.recipeSource)

        switch combinedQuantity(
            existingQuantity: existing.quantity,
            existingUnit: existing.unit,
            addedQuantity: addition.quantity,
            addedUnit: addition.unit
        ) {
        case let .merged(quantity, unit):
            merged.quantity = quantity
            merged.unit = unit
        case .keepExisting:
            break
        case let .replaceExisting(quantity, unit):
            merged.quantity = quantity
            merged.unit = unit
        }

        return merged
    }
}
