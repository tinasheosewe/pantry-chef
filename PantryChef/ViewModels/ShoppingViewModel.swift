import SwiftUI

@Observable
@MainActor
final class ShoppingViewModel {
    var searchText = ""
    var isLoading = false

    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var items: [ShoppingItem] {
        var list = appState.shoppingItems
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return list
    }

    var groupedByCategory: [(FoodCategory, [ShoppingItem])] {
        let grouped = Dictionary(grouping: items, by: { $0.category })
        return grouped.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    var checkedCount: Int {
        appState.shoppingItems.filter { $0.isChecked }.count
    }

    var totalCount: Int {
        appState.shoppingItems.count
    }

    var progressText: String {
        "\(checkedCount)/\(totalCount) items"
    }

    func toggleItem(_ item: ShoppingItem) {
        Task { await appState.toggleShoppingItem(item) }
    }

    func removeCheckedItems() {
        Task { await appState.removeCheckedShoppingItems() }
    }

    func addItem(_ item: ShoppingItem) {
        Task { await appState.addShoppingItem(item) }
    }

    func removeItem(_ item: ShoppingItem) {
        Task { await appState.removeShoppingItem(item) }
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

struct ShoppingCatalogSuggestion: Identifiable, Hashable {
    let id: String
    let catalogItemID: String
    let facets: [PantryFacetSelection]
    let displayName: String
    let category: FoodCategory
    let rationale: String
}

@Observable
@MainActor
final class ShoppingAddItemViewModel {
    var searchText = ""
    var isCustomItem = false
    var customItemName = ""
    var customCategory: FoodCategory = .other
    var quantityText = ""
    var selectedUnit: MeasurementUnit?
    var selectedCatalogItemID: String?
    var selectedFacets: [PantryFacetSelection] = []

    private let parser = IngredientCandidateParser()
    private var quantityWasEdited = false
    private var unitWasEdited = false

    var searchResults: [ShoppingCatalogSuggestion] {
        let query = searchText.trimmed
        guard !query.isEmpty else {
            return Array(PantryCatalog.allItems.sorted { $0.name < $1.name }.prefix(20)).map(defaultSuggestion)
        }

        var suggestions: [ShoppingCatalogSuggestion] = []
        var seenIDs: Set<String> = []

        let ingredient = Ingredient(name: query)
        for candidate in parser.candidates(for: ingredient) {
            guard let item = PantryCatalog.item(id: candidate.catalogItemID) else { continue }
            let suggestion = ShoppingCatalogSuggestion(
                id: candidate.id,
                catalogItemID: item.id,
                facets: candidate.facets,
                displayName: candidate.displayName,
                category: item.category,
                rationale: candidate.rationale
            )
            if seenIDs.insert(suggestion.id).inserted {
                suggestions.append(suggestion)
            }
        }

        for item in PantryCatalog.search(query) {
            let suggestion = defaultSuggestion(item)
            if seenIDs.insert(suggestion.id).inserted {
                suggestions.append(suggestion)
            }
        }

        return Array(suggestions.prefix(20))
    }

    var selectedItem: PantryCatalogItemDefinition? {
        PantryCatalog.item(id: selectedCatalogItemID)
    }

    var canAdd: Bool {
        if isCustomItem {
            return customItemName.trimmed.nilIfEmpty != nil
        }

        return selectedItem != nil
    }

    var previewName: String {
        if isCustomItem {
            return customItemName.trimmed
        }

        return selectedItem?.displayName(for: selectedFacets) ?? ""
    }

    var previewCategory: FoodCategory {
        if isCustomItem {
            return customCategory
        }

        return selectedItem?.category ?? .other
    }

    var quantityValue: Double? {
        let trimmed = quantityText.trimmed
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    func chooseSuggestion(_ suggestion: ShoppingCatalogSuggestion) {
        isCustomItem = false
        selectedCatalogItemID = suggestion.catalogItemID
        selectedFacets = normalizedFacets(for: suggestion.facets, item: PantryCatalog.item(id: suggestion.catalogItemID))
        customItemName = ""
        searchText = suggestion.displayName
        syncDefaultsFromSelection()
    }

    func setCustomItemMode() {
        isCustomItem = true
        selectedCatalogItemID = nil
        selectedFacets = []
        if customItemName.trimmed.isEmpty {
            customItemName = searchText.trimmed
        }
        if !unitWasEdited {
            selectedUnit = nil
        }
    }

    func setCatalogMode() {
        isCustomItem = false
        if searchText.trimmed.isEmpty {
            searchText = customItemName.trimmed
        }
    }

    func setQuantityText(_ value: String) {
        quantityText = value
        quantityWasEdited = true
    }

    func setUnit(_ unit: MeasurementUnit?) {
        selectedUnit = unit
        unitWasEdited = true
    }

    func setFacetValue(_ value: String?, for key: PantryFacetKey) {
        guard let item = selectedItem else { return }

        var facetsByKey = Dictionary(uniqueKeysWithValues: selectedFacets.map { ($0.key, $0) })
        if let value, item.options(for: key).contains(value) {
            facetsByKey[key] = PantryFacetSelection(key: key, value: value)
        } else {
            facetsByKey.removeValue(forKey: key)
        }

        selectedFacets = normalizedFacets(for: Array(facetsByKey.values), item: item)

        if !unitWasEdited {
            selectedUnit = item.suggestedUnit(for: selectedFacets)
        }
    }

    func buildItem() -> ShoppingItem? {
        if isCustomItem {
            guard let name = customItemName.trimmed.nilIfEmpty else { return nil }
            let quantity = quantityValue
            return ShoppingItem(
                name: name,
                quantity: quantity,
                unit: quantity == nil ? nil : selectedUnit,
                category: customCategory
            )
        }

        guard let item = selectedItem else { return nil }
        let quantity = quantityValue

        return ShoppingItem(
            name: item.displayName(for: selectedFacets),
            quantity: quantity,
            unit: quantity == nil ? nil : (selectedUnit ?? item.suggestedUnit(for: selectedFacets)),
            category: item.category,
            catalogItemID: item.id,
            facets: selectedFacets
        )
    }

    private func syncDefaultsFromSelection() {
        guard let item = selectedItem else { return }

        if !quantityWasEdited {
            quantityText = item.suggestedQuantity().map {
                $0 == $0.rounded() ? String(Int($0)) : String(format: "%.1f", $0)
            } ?? ""
        }

        if !unitWasEdited {
            selectedUnit = item.suggestedUnit(for: selectedFacets)
        }
    }

    private func defaultSuggestion(_ item: PantryCatalogItemDefinition) -> ShoppingCatalogSuggestion {
        ShoppingCatalogSuggestion(
            id: "\(item.id)|default",
            catalogItemID: item.id,
            facets: item.defaultSelections,
            displayName: item.displayName(for: item.defaultSelections),
            category: item.category,
            rationale: "Catalog item"
        )
    }

    private func normalizedFacets(
        for facets: [PantryFacetSelection],
        item: PantryCatalogItemDefinition?
    ) -> [PantryFacetSelection] {
        guard let item else { return [] }

        var facetsByKey: [PantryFacetKey: PantryFacetSelection] = [:]
        for facet in item.defaultSelections {
            facetsByKey[facet.key] = facet
        }
        for facet in facets where item.options(for: facet.key).contains(facet.value) {
            facetsByKey[facet.key] = facet
        }

        return item.facets.compactMap { definition in
            facetsByKey[definition.key]
        }
    }
}
