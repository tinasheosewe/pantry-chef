import Foundation

// MARK: - Pantry Actions

extension AppState {
    func addPantryItem(_ item: PantryItem) async {
        await pantryDomainService.addPantryItem(item, state: self)
    }

    func removePantryItems(catalogItemID: String) async {
        let matchingItems = pantryItems.filter { $0.catalogItemID == catalogItemID }
        for item in matchingItems {
            await removePantryItem(item)
        }
    }

    func removePantryItem(_ item: PantryItem) async {
        await pantryDomainService.removePantryItem(item, state: self)
    }

    func updatePantryItem(_ item: PantryItem) async {
        await pantryDomainService.updatePantryItem(item, state: self)
    }

    func pantryItemsCanMerge(_ existing: PantryItem, _ addition: PantryItem) -> Bool {
        pantryDomainService.pantryItemsCanMerge(existing, addition, state: self)
    }

    func mergePantryItem(_ existing: PantryItem, with addition: PantryItem) -> PantryItem {
        pantryDomainService.mergePantryItem(existing, with: addition, state: self)
    }

    func normalizedPantryIdentityFacets(_ item: PantryItem) -> [PantryFacetSelection] {
        pantryDomainService.normalizedPantryIdentityFacets(item)
    }

    func pantryItemIdentityKey(_ item: PantryItem) -> PantryItemIdentityKey {
        pantryDomainService.pantryItemIdentityKey(item)
    }
}
