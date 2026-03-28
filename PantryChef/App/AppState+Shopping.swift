import Foundation

// MARK: - Shopping Actions

extension AppState {
    func previewShoppingListFromMealPlan() -> [ShoppingItem] {
        let recipes = mealPlan.compactMap(\.scaledRecipeForPlanning)
        let candidates = recipes.flatMap { recipe in
            recipe.ingredients.compactMap { ingredient -> ShoppingItem? in
                guard shouldIncludeInShoppingList(ingredient) else { return nil }
                return ShoppingItem(ingredient: ingredient, recipeSource: recipe.title)
            }
        }

        return mergeShoppingItems(existing: [], additions: candidates)
    }

    func generateShoppingListFromMealPlan() async {
        await addShoppingItems(previewShoppingListFromMealPlan())
    }

    func addShoppingItems(_ items: [ShoppingItem]) async {
        setShoppingItemsValue(mergeShoppingItems(existing: shoppingItems, additions: items))
        await persistShoppingItems()
    }

    func toggleShoppingItem(_ item: ShoppingItem) async {
        if let index = shoppingItems.firstIndex(where: { $0.id == item.id }) {
            shoppingItems[index].isChecked.toggle()
            markShoppingChanged()
            await persistShoppingItems()
        }
    }

    func setShoppingItems(_ items: [ShoppingItem]) async {
        setShoppingItemsValue(items)
        await persistShoppingItems()
    }

    func addShoppingItem(_ item: ShoppingItem) async {
        await addShoppingItems([item])
    }

    func removeShoppingItem(_ item: ShoppingItem) async {
        let originalCount = shoppingItems.count
        shoppingItems.removeAll { $0.id == item.id }
        if shoppingItems.count != originalCount {
            markShoppingChanged()
        }
        await persistShoppingItems()
    }

    func updateShoppingItem(_ item: ShoppingItem) async {
        guard let index = shoppingItems.firstIndex(where: { $0.id == item.id }) else { return }
        shoppingItems[index] = item
        markShoppingChanged()
        await persistShoppingItems()
    }

    func replaceShoppingItems(_ items: [ShoppingItem]) async {
        guard !items.isEmpty else { return }

        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var didChange = false

        for index in shoppingItems.indices {
            guard let updated = itemsByID[shoppingItems[index].id] else { continue }
            shoppingItems[index] = updated
            didChange = true
        }

        guard didChange else { return }
        markShoppingChanged()
        await persistShoppingItems()
    }

    func removeCheckedShoppingItems() async {
        let originalCount = shoppingItems.count
        shoppingItems.removeAll { $0.isChecked }
        if shoppingItems.count != originalCount {
            markShoppingChanged()
        }
        await persistShoppingItems()
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
        case let (.merged(quantity, unit)):
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
