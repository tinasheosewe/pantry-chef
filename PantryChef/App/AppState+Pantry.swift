import Foundation

// MARK: - Pantry Actions

extension AppState {
    func addPantryItem(_ item: PantryItem) async {
        if let existingIndex = pantryItems.firstIndex(where: { pantryItemsCanMerge($0, item) }) {
            var merged = pantryItems[existingIndex]
            merged = mergePantryItem(merged, with: item)
            await updatePantryItem(merged)
            return
        }

        do {
            let saved = try await storageService.addPantryItem(item)
            pantryItems.append(saved)
            markPantryChanged()
        } catch {
            pushError(.storage(error))
        }
    }

    func removePantryItem(_ item: PantryItem) async {
        do {
            try await storageService.deletePantryItem(item)
            let originalCount = pantryItems.count
            pantryItems.removeAll { $0.id == item.id }
            if pantryItems.count != originalCount {
                markPantryChanged()
            }
        } catch {
            pushError(.storage(error))
        }
    }

    func updatePantryItem(_ item: PantryItem) async {
        do {
            let updated = try await storageService.updatePantryItem(item)
            if let index = pantryItems.firstIndex(where: { $0.id == item.id }) {
                pantryItems[index] = updated
                markPantryChanged()
            }
        } catch {
            pushError(.storage(error))
        }
    }

    func pantryItemsCanMerge(_ existing: PantryItem, _ addition: PantryItem) -> Bool {
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

        let mergedQuantityMode = PantryQuantityMode.merged(existing.quantityMode, addition.quantityMode)
        guard mergedQuantityMode == .exact else {
            return true
        }

        switch combinedQuantity(
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

    func mergePantryItem(_ existing: PantryItem, with addition: PantryItem) -> PantryItem {
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
        }

        if let existingExpiryDate = merged.expiryDate, let additionExpiryDate = addition.expiryDate {
            if additionExpiryDate < existingExpiryDate {
                merged.expiryDate = additionExpiryDate
                merged.freshnessSource = addition.freshnessSource
            }
        } else if merged.expiryDate == nil {
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
}
