import Foundation

@MainActor
protocol PantryDomainState: AnyObject {
    var pantryItems: [PantryItem] { get }
    var storageService: StorageServiceProtocol { get }

    func pushError(_ error: AppError)
    func setPantryItems(_ items: [PantryItem])
    func combinedQuantity(
        existingQuantity: Double?,
        existingUnit: MeasurementUnit?,
        addedQuantity: Double?,
        addedUnit: MeasurementUnit?
    ) -> QuantityMergeOutcome
    func convertCountUnit(_ value: Double, from: MeasurementUnit, to: MeasurementUnit) -> Double?
}

@MainActor
protocol PantryDomainServicing {
    func addPantryItem(_ item: PantryItem, state: any PantryDomainState) async
    func removePantryItem(_ item: PantryItem, state: any PantryDomainState) async
    func updatePantryItem(_ item: PantryItem, state: any PantryDomainState) async
    func pantryItemsCanMerge(_ existing: PantryItem, _ addition: PantryItem, state: any PantryDomainState) -> Bool
    func mergePantryItem(_ existing: PantryItem, with addition: PantryItem, state: any PantryDomainState) -> PantryItem
    func normalizedPantryIdentityFacets(_ item: PantryItem) -> [PantryFacetSelection]
    func pantryCookReviewItems(for recipe: Recipe, state: any PantryDomainState) -> [PantryCookReviewItem]
    func applyPantryCookReview(_ items: [PantryCookReviewItem], state: any PantryDomainState) async
    func subtractableRecipeAmount(for ingredient: Ingredient, pantryItem: PantryItem, state: any PantryDomainState) -> Double?
}

@MainActor
struct PantryDomainService: PantryDomainServicing {
    func addPantryItem(_ item: PantryItem, state: any PantryDomainState) async {
        if let existingIndex = state.pantryItems.firstIndex(where: { pantryItemsCanMerge($0, item, state: state) }) {
            var merged = state.pantryItems[existingIndex]
            merged = mergePantryItem(merged, with: item, state: state)
            await updatePantryItem(merged, state: state)
            return
        }

        do {
            let saved = try await state.storageService.addPantryItem(item)
            state.setPantryItems(state.pantryItems + [saved])
        } catch {
            state.pushError(.storage(error))
        }
    }

    func removePantryItem(_ item: PantryItem, state: any PantryDomainState) async {
        do {
            try await state.storageService.deletePantryItem(item)
            let updatedItems = state.pantryItems.filter { $0.id != item.id }
            guard updatedItems.count != state.pantryItems.count else { return }
            state.setPantryItems(updatedItems)
        } catch {
            state.pushError(.storage(error))
        }
    }

    func updatePantryItem(_ item: PantryItem, state: any PantryDomainState) async {
        // Check if updated item now matches another existing item (excluding itself)
        if let matchIndex = state.pantryItems.firstIndex(where: { $0.id != item.id && pantryItemsCanMerge($0, item, state: state) }) {
            // Merge into the existing item, then delete the updated item
            var merged = mergePantryItem(state.pantryItems[matchIndex], with: item, state: state)
            merged.id = state.pantryItems[matchIndex].id // Keep target's ID

            do {
                // Update the target item with merged data
                let updatedTarget = try await state.storageService.updatePantryItem(merged)
                // Delete the source item
                try await state.storageService.deletePantryItem(item)

                var items = state.pantryItems.filter { $0.id != item.id }
                if let targetIndex = items.firstIndex(where: { $0.id == updatedTarget.id }) {
                    items[targetIndex] = updatedTarget
                }
                state.setPantryItems(items)
            } catch {
                state.pushError(.storage(error))
            }
            return
        }

        do {
            let updated = try await state.storageService.updatePantryItem(item)
            guard let index = state.pantryItems.firstIndex(where: { $0.id == item.id }) else { return }
            var items = state.pantryItems
            items[index] = updated
            state.setPantryItems(items)
        } catch {
            state.pushError(.storage(error))
        }
    }

    func pantryItemsCanMerge(_ existing: PantryItem, _ addition: PantryItem, state: any PantryDomainState) -> Bool {
        let identitiesMatch: Bool
        if let existingCatalogItemID = existing.catalogItemID, let additionCatalogItemID = addition.catalogItemID {
            identitiesMatch = existingCatalogItemID == additionCatalogItemID
                && normalizedPantryIdentityFacets(existing) == normalizedPantryIdentityFacets(addition)
        } else if existing.catalogItemID == nil, addition.catalogItemID == nil {
            identitiesMatch = IngredientMatcher.normalize(existing.name) == IngredientMatcher.normalize(addition.name)
                && existing.category == addition.category
        } else {
            identitiesMatch = false
        }

        guard identitiesMatch, existing.storage == addition.storage else {
            return false
        }

        // Items with different expiry dates should NOT merge
        guard ExpiryStatus.sameCalendarDay(existing.expiryDate, addition.expiryDate) else {
            return false
        }

        let mergedQuantityMode = PantryQuantityMode.merged(existing.quantityMode, addition.quantityMode)
        guard mergedQuantityMode == .exact else {
            return true
        }

        switch state.combinedQuantity(
            existingQuantity: existing.quantity,
            existingUnit: existing.unit,
            addedQuantity: addition.quantity,
            addedUnit: addition.unit
        ) {
        case .merged, .replaceExisting:
            return true
        case .keepExisting:
            return existing.quantity == nil && addition.quantity == nil
        }
    }

    func mergePantryItem(_ existing: PantryItem, with addition: PantryItem, state: any PantryDomainState) -> PantryItem {
        var merged = existing
        merged.catalogItemID = existing.catalogItemID ?? addition.catalogItemID
        merged.quantityMode = PantryQuantityMode.merged(existing.quantityMode, addition.quantityMode)
        if merged.facets.isEmpty || addition.facets.count > merged.facets.count {
            merged.facets = addition.facets
        }

        if merged.quantityMode == .presenceOnly {
            merged.quantity = nil
            merged.unit = nil
        } else {
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
        }

        // Since items only merge when they have the same calendar-day expiry,
        // keep the existing expiry date (or adopt addition's if existing is nil)
        if merged.expiryDate == nil {
            merged.expiryDate = addition.expiryDate
            if addition.expiryDate != nil {
                merged.freshnessSource = addition.freshnessSource
            }
        }

        if merged.notes == nil {
            merged.notes = addition.notes
        }

        return merged
    }

    func normalizedPantryIdentityFacets(_ item: PantryItem) -> [PantryFacetSelection] {
        guard let catalogItemID = item.catalogItemID,
              let catalogItem = PantryCatalog.item(id: catalogItemID) else {
            return item.facets
        }

        var facetsByKey: [PantryFacetKey: PantryFacetSelection] = [:]
        for facet in catalogItem.defaultSelections {
            facetsByKey[facet.key] = facet
        }

        for facet in item.facets where catalogItem.options(for: facet.key).contains(facet.value) {
            facetsByKey[facet.key] = facet
        }

        return catalogItem.facets.compactMap { facetsByKey[$0.key] }
    }

    func pantryCookReviewItems(for recipe: Recipe, state: any PantryDomainState) -> [PantryCookReviewItem] {
        let ingredients = recipe.ingredients.filter { !$0.isOptional }
        var accumulators: [UUID: PantryCookReviewAccumulator] = [:]
        var order: [UUID] = []

        for ingredient in ingredients {
            guard let pantryItem = state.pantryItems.first(where: {
                IngredientMatcher.pantryItemMatchesIngredient($0, ingredient: ingredient)
            }) else {
                continue
            }

            if accumulators[pantryItem.id] == nil {
                accumulators[pantryItem.id] = PantryCookReviewAccumulator(pantryItem: pantryItem)
                order.append(pantryItem.id)
            }

            let subtractableAmount = subtractableRecipeAmount(for: ingredient, pantryItem: pantryItem, state: state)
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

    func applyPantryCookReview(_ items: [PantryCookReviewItem], state: any PantryDomainState) async {
        for item in items {
            guard let currentItem = state.pantryItems.first(where: { $0.id == item.pantryItem.id }) else {
                continue
            }

            switch item.selection {
            case .keep:
                continue
            case .remove:
                await removePantryItem(currentItem, state: state)
            case .subtractRecipeAmount:
                guard let subtractQuantity = item.subtractQuantity else {
                    continue
                }

                let remainingQuantity = (currentItem.quantity ?? 0) - subtractQuantity
                if remainingQuantity <= 0 {
                    await removePantryItem(currentItem, state: state)
                } else {
                    var updatedItem = currentItem
                    updatedItem.quantity = remainingQuantity
                    await updatePantryItem(updatedItem, state: state)
                }
            }
        }
    }

    func subtractableRecipeAmount(for ingredient: Ingredient, pantryItem: PantryItem, state: any PantryDomainState) -> Double? {
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

        return state.convertCountUnit(ingredient.quantity, from: ingredientUnit, to: pantryUnit)
    }
}

private struct PantryCookReviewAccumulator {
    let pantryItem: PantryItem
    var matchedIngredientNames: [String] = []
    var matchedIngredientTexts: [String] = []
    var subtractQuantity: Double = 0
    var subtractionFailed = false

    mutating func append(_ ingredient: Ingredient, subtractableAmount: Double?) {
        if !matchedIngredientNames.contains(ingredient.displayName) {
            matchedIngredientNames.append(ingredient.displayName)
        }
        matchedIngredientTexts.append(ingredient.displayText)

        guard pantryItem.isTrackingExactQuantity else {
            return
        }

        guard let subtractableAmount else {
            subtractionFailed = true
            return
        }

        subtractQuantity += subtractableAmount
    }

    func build() -> PantryCookReviewItem {
        PantryCookReviewItem(
            pantryItem: pantryItem,
            matchedIngredientNames: matchedIngredientNames,
            matchedIngredientTexts: matchedIngredientTexts,
            subtractQuantity: pantryItem.isTrackingExactQuantity && !subtractionFailed ? subtractQuantity : nil,
            subtractUnit: pantryItem.isTrackingExactQuantity ? pantryItem.unit : nil
        )
    }
}

@MainActor
extension AppState: PantryDomainState {}