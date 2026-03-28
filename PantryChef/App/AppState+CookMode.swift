import Foundation

// MARK: - Cook Mode

extension AppState {
    func pantryCookReviewItems(for recipe: Recipe) -> [PantryCookReviewItem] {
        let ingredients = recipe.ingredients.filter { !$0.isOptional }
        var accumulators: [UUID: PantryCookReviewAccumulator] = [:]
        var order: [UUID] = []

        for ingredient in ingredients {
            guard let pantryItem = pantryItems.first(where: {
                IngredientMatcher.pantryItemMatchesIngredient($0, ingredient: ingredient)
            }) else {
                continue
            }

            if accumulators[pantryItem.id] == nil {
                accumulators[pantryItem.id] = PantryCookReviewAccumulator(pantryItem: pantryItem)
                order.append(pantryItem.id)
            }

            let subtractableAmount = subtractableRecipeAmount(for: ingredient, pantryItem: pantryItem)
            accumulators[pantryItem.id]?.append(ingredient, subtractableAmount: subtractableAmount)
        }

        return order
            .compactMap { accumulators[$0]?.build() }
            .sorted { lhs, rhs in
                if lhs.quantityMode != rhs.quantityMode {
                    return lhs.quantityMode == .exact
                }
                return lhs.pantryItem.name.localizedCaseInsensitiveCompare(rhs.pantryItem.name) == .orderedAscending
            }
    }

    func applyPantryCookReview(_ items: [PantryCookReviewItem]) async {
        for item in items {
            guard let currentItem = pantryItems.first(where: { $0.id == item.pantryItem.id }) else {
                continue
            }

            switch item.selection {
            case .keep:
                continue
            case .remove:
                await removePantryItem(currentItem)
            case .subtractRecipeAmount:
                guard let subtractQuantity = item.subtractQuantity else {
                    continue
                }

                let remainingQuantity = (currentItem.quantity ?? 0) - subtractQuantity
                if remainingQuantity <= 0 {
                    await removePantryItem(currentItem)
                } else {
                    var updatedItem = currentItem
                    updatedItem.quantity = remainingQuantity
                    await updatePantryItem(updatedItem)
                }
            }
        }
    }

    func subtractableRecipeAmount(for ingredient: Ingredient, pantryItem: PantryItem) -> Double? {
        guard pantryItem.isTrackingExactQuantity else {
            return nil
        }

        guard let pantryUnit = pantryItem.unit else {
            return ingredient.unit == nil ? ingredient.quantity : nil
        }

        guard let ingredientUnit = ingredient.unit else {
            return nil
        }

        if pantryUnit == ingredientUnit {
            return ingredient.quantity
        }

        if let converted = UnitConverter.convert(ingredient.quantity, from: ingredientUnit, to: pantryUnit) {
            return converted
        }

        return convertCountUnit(ingredient.quantity, from: ingredientUnit, to: pantryUnit)
    }
}
