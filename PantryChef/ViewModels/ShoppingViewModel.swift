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
        var seenCatalogIDs: Set<String> = []

        let ingredient = Ingredient(name: query)
        for candidate in parser.candidates(for: ingredient) {
            guard let item = PantryCatalog.item(id: candidate.catalogItemID) else { continue }
            let suggestion = ShoppingCatalogSuggestion(
                id: item.id,
                catalogItemID: item.id,
                facets: normalizedFacets(for: candidate.facets, item: item),
                displayName: item.name,
                category: item.category
            )
            if seenCatalogIDs.insert(suggestion.catalogItemID).inserted {
                suggestions.append(suggestion)
            }
        }

        for item in PantryCatalog.search(query) {
            let suggestion = defaultSuggestion(item)
            if seenCatalogIDs.insert(suggestion.catalogItemID).inserted {
                suggestions.append(suggestion)
            }
        }

        return Array(suggestions.prefix(20))
    }

    var selectedItem: PantryCatalogItemDefinition? {
        PantryCatalog.item(id: selectedCatalogItemID)
    }

    var selectedFacetSummary: String? {
        facetValueSummary(for: selectedFacets)
    }

    var canAdd: Bool {
        if isCustomItem {
            return customItemName.trimmed.nilIfEmpty != nil
        }

        return selectedItem != nil
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

    func suggestionBaseName(_ suggestion: ShoppingCatalogSuggestion) -> String {
        PantryCatalog.item(id: suggestion.catalogItemID)?.name ?? suggestion.displayName
    }

    func suggestionFacetSummary(_ suggestion: ShoppingCatalogSuggestion) -> String? {
        guard let item = PantryCatalog.item(id: suggestion.catalogItemID) else {
            return facetValueSummary(for: suggestion.facets)
        }

        return availableFacetSummary(for: item)
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
            id: item.id,
            catalogItemID: item.id,
            facets: item.defaultSelections,
            displayName: item.name,
            category: item.category
        )
    }

    private func availableFacetSummary(for item: PantryCatalogItemDefinition) -> String? {
        let groups = item.facets.compactMap { definition -> String? in
            let options = definition.options
                .filter { $0.caseInsensitiveCompare("generic") != .orderedSame }
                .map(humanizedFacetValue)

            guard !options.isEmpty else { return nil }
            return options.joined(separator: ", ")
        }

        guard !groups.isEmpty else { return nil }
        return groups.joined(separator: " • ")
    }

    private func facetValueSummary(for facets: [PantryFacetSelection]) -> String? {
        guard !facets.isEmpty else { return nil }

        return facets
            .map { humanizedFacetValue($0.value) }
            .joined(separator: " • ")
    }

    private func humanizedFacetValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
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
