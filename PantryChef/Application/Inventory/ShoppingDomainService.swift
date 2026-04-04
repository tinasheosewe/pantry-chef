import Foundation

@MainActor
protocol ShoppingDomainState: AnyObject {
    var mealPlan: [MealPlanEntry] { get }
    var pantryItems: [PantryItem] { get }
    var shoppingItems: [ShoppingItem] { get set }
    var storageService: StorageServiceProtocol { get }

    func pushError(_ error: AppError)
    func markShoppingChanged()
    func setShoppingItemsValue(_ items: [ShoppingItem])
    func mergedRecipeSources(_ lhs: String?, _ rhs: String?) -> String?
    func combinedQuantity(
        existingQuantity: Double?,
        existingUnit: MeasurementUnit?,
        addedQuantity: Double?,
        addedUnit: MeasurementUnit?
    ) -> QuantityMergeOutcome
}

@MainActor
protocol ShoppingDomainServicing {
    func previewShoppingListFromMealPlan(state: any ShoppingDomainState) -> [ShoppingItem]
    func generateShoppingListFromMealPlan(state: any ShoppingDomainState) async
    func addShoppingItems(_ items: [ShoppingItem], state: any ShoppingDomainState) async
    func toggleShoppingItem(_ item: ShoppingItem, state: any ShoppingDomainState) async
    func setShoppingItems(_ items: [ShoppingItem], state: any ShoppingDomainState) async
    func addShoppingItem(_ item: ShoppingItem, state: any ShoppingDomainState) async
    func removeShoppingItem(_ item: ShoppingItem, state: any ShoppingDomainState) async
    func updateShoppingItem(_ item: ShoppingItem, state: any ShoppingDomainState) async
    func replaceShoppingItems(_ items: [ShoppingItem], state: any ShoppingDomainState) async
    func removeCheckedShoppingItems(state: any ShoppingDomainState) async
}

@MainActor
struct ShoppingDomainService: ShoppingDomainServicing {
    func previewShoppingListFromMealPlan(state: any ShoppingDomainState) -> [ShoppingItem] {
        let recipes = state.mealPlan.compactMap(\.scaledRecipeForPlanning)
        let candidates = recipes.flatMap { recipe in
            recipe.ingredients.compactMap { ingredient -> ShoppingItem? in
                guard shouldIncludeInShoppingList(ingredient, pantryItems: state.pantryItems) else { return nil }
                return ShoppingItem(ingredient: ingredient, recipeSource: recipe.title)
            }
        }

        return mergeShoppingItems(existing: [], additions: candidates, state: state)
    }

    func generateShoppingListFromMealPlan(state: any ShoppingDomainState) async {
        await addShoppingItems(previewShoppingListFromMealPlan(state: state), state: state)
    }

    func addShoppingItems(_ items: [ShoppingItem], state: any ShoppingDomainState) async {
        state.setShoppingItemsValue(mergeShoppingItems(existing: state.shoppingItems, additions: items, state: state))
        await persistShoppingItems(state: state)
    }

    func toggleShoppingItem(_ item: ShoppingItem, state: any ShoppingDomainState) async {
        guard let index = state.shoppingItems.firstIndex(where: { $0.id == item.id }) else { return }
        state.shoppingItems[index].isChecked.toggle()
        state.markShoppingChanged()
        await persistShoppingItems(state: state)
    }

    func setShoppingItems(_ items: [ShoppingItem], state: any ShoppingDomainState) async {
        state.setShoppingItemsValue(items)
        await persistShoppingItems(state: state)
    }

    func addShoppingItem(_ item: ShoppingItem, state: any ShoppingDomainState) async {
        await addShoppingItems([item], state: state)
    }

    func removeShoppingItem(_ item: ShoppingItem, state: any ShoppingDomainState) async {
        let originalCount = state.shoppingItems.count
        state.shoppingItems.removeAll { $0.id == item.id }
        if state.shoppingItems.count != originalCount {
            state.markShoppingChanged()
        }
        await persistShoppingItems(state: state)
    }

    func updateShoppingItem(_ item: ShoppingItem, state: any ShoppingDomainState) async {
        guard let index = state.shoppingItems.firstIndex(where: { $0.id == item.id }) else { return }
        state.shoppingItems[index] = item
        state.markShoppingChanged()
        await persistShoppingItems(state: state)
    }

    func replaceShoppingItems(_ items: [ShoppingItem], state: any ShoppingDomainState) async {
        guard !items.isEmpty else { return }

        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var didChange = false

        for index in state.shoppingItems.indices {
            guard let updated = itemsByID[state.shoppingItems[index].id] else { continue }
            state.shoppingItems[index] = updated
            didChange = true
        }

        guard didChange else { return }
        state.markShoppingChanged()
        await persistShoppingItems(state: state)
    }

    func removeCheckedShoppingItems(state: any ShoppingDomainState) async {
        let originalCount = state.shoppingItems.count
        state.shoppingItems.removeAll { $0.isChecked }
        if state.shoppingItems.count != originalCount {
            state.markShoppingChanged()
        }
        await persistShoppingItems(state: state)
    }

    private func persistShoppingItems(state: any ShoppingDomainState) async {
        do {
            try await state.storageService.saveShoppingItems(state.shoppingItems)
        } catch {
            state.pushError(.storage(error))
        }
    }

    private func shouldIncludeInShoppingList(_ ingredient: Ingredient, pantryItems: [PantryItem]) -> Bool {
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

    private func isExcludedShoppingIngredient(named name: String) -> Bool {
        let normalized = IngredientLexicon.lookupKey(name)
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

    private func mergeShoppingItems(
        existing: [ShoppingItem],
        additions: [ShoppingItem],
        state: any ShoppingDomainState
    ) -> [ShoppingItem] {
        var merged = existing

        for item in additions {
            guard !isExcludedShoppingIngredient(named: item.name) else { continue }

            if let index = merged.firstIndex(where: { $0.matchesIdentity(of: item) }) {
                merged[index] = mergeShoppingItem(merged[index], with: item, state: state)
            } else {
                merged.append(item)
            }
        }

        return merged
    }

    private func mergeShoppingItem(
        _ existing: ShoppingItem,
        with addition: ShoppingItem,
        state: any ShoppingDomainState
    ) -> ShoppingItem {
        var merged = existing
        merged.catalogItemID = existing.catalogItemID ?? addition.catalogItemID
        merged.name = merged.resolvedCatalogItem?.displayName(for: merged.facets) ?? (
            existing.name.count <= addition.name.count ? existing.name : addition.name
        )

        if merged.category == .other {
            merged.category = addition.category
        }

        merged.recipeSource = state.mergedRecipeSources(existing.recipeSource, addition.recipeSource)

        switch state.combinedQuantity(
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

@MainActor
extension AppState: ShoppingDomainState {}