import SwiftUI

@Observable
@MainActor
final class PantryBulkAddViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case search = "Search"
        case review = "Review"

        var id: String { rawValue }
    }

    var selectedTab: Tab = .search
    var catalogSearchText = ""
    private(set) var debouncedCatalogSearchText = ""
    var selectedCatalogCategory: FoodCategory?
    var searchComposerText = ""
    var unresolvedTokens: [String] = []
    var stagedRows: [PantryIntakeRowDraft] = []
    var expandedItemIDs: Set<String> = []
    @ObservationIgnored private let catalogSearchDebouncer = TaskDebouncer()
    @ObservationIgnored private let preferenceStore: PantryItemPreferenceStoreProtocol

    @ObservationIgnored private var catalogChangeObserver: Any?

    init(preferenceStore: PantryItemPreferenceStoreProtocol) {
        self.preferenceStore = preferenceStore
        updateCatalogSearch()
        catalogChangeObserver = NotificationCenter.default.addObserver(
            forName: .pantryCatalogDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateCatalogSearch()
            }
        }
    }

    deinit {
        if let observer = catalogChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var categoryCounts: [(FoodCategory, Int)] {
        FoodCategory.allCases.compactMap { category in
            let count = PantryCatalog.allItems.filter { $0.category == category }.count
            guard count > 0 else { return nil }
            return (category, count)
        }
    }

    private(set) var catalogSearchResults: [CatalogSearchResult] = []
    private(set) var filteredCatalogItems: [PantryCatalogItemDefinition] = []

    /// When set, this item is forced to the top of search results once, then cleared.
    var highlightedItemID: String?

    func updateCatalogSearch() {
        let normalizedQuery = debouncedCatalogSearchText.trimmed
        let freq = PantryAddFrequencyTracker.frequencies()
        if normalizedQuery.isEmpty {
            catalogSearchResults = []
            var items = PantryCatalog.allItems.sorted {
                let f0 = freq[$0.id] ?? 0
                let f1 = freq[$1.id] ?? 0
                if f0 != f1 { return f0 > f1 }
                return $0.name < $1.name
            }
            if let selectedCatalogCategory {
                items = items.filter { $0.category == selectedCatalogCategory }
            }
            filteredCatalogItems = promoteHighlightedItem(in: items)
            return
        }

        let results = CatalogSearchEngine.search(normalizedQuery)
        var filtered = results
        if let selectedCatalogCategory {
            filtered = filtered.filter { $0.item.category == selectedCatalogCategory }
        }
        // Stable sort: relevance is primary (already sorted), frequency as tiebreaker
        filtered.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return (freq[$0.item.id] ?? 0) > (freq[$1.item.id] ?? 0)
        }
        catalogSearchResults = filtered
        filteredCatalogItems = promoteHighlightedItem(in: filtered.map(\.item))
    }

    private func promoteHighlightedItem(in items: [PantryCatalogItemDefinition]) -> [PantryCatalogItemDefinition] {
        guard let highlightID = highlightedItemID else { return items }
        var result = items
        if let idx = result.firstIndex(where: { $0.id == highlightID }) {
            let item = result.remove(at: idx)
            result.insert(item, at: 0)
        } else if let item = PantryCatalog.item(id: highlightID) {
            result.insert(item, at: 0)
        }
        return result
    }

    func catalogDisplayName(for item: PantryCatalogItemDefinition) -> String {
        catalogSearchResults.first(where: { $0.catalogItemID == item.id })?.displayName ?? item.titleCasedName
    }

    func catalogResolvedFacets(for item: PantryCatalogItemDefinition) -> [PantryFacetSelection] {
        catalogSearchResults.first(where: { $0.catalogItemID == item.id })?.facets ?? []
    }

    var commonItems: [PantryCatalogItemDefinition] {
        let featuredIDs = ["milk", "egg", "rice", "bread", "cheese", "butter", "chicken", "beef", "yogurt", "onion", "tomato", "olive-oil", "broth"]
        return featuredIDs.compactMap(PantryCatalog.item(id:)).filter { item in
            selectedCatalogCategory == nil || item.category == selectedCatalogCategory
        }
    }

    var searchPreviewResults: [PantryCatalogItemDefinition] {
        let token = trailingSearchToken
        guard !token.isEmpty else { return [] }
        return Array(CatalogSearchEngine.search(token).prefix(AppConfig.pantrySearchMaxResults).map(\.item))
    }

    var trailingSearchToken: String {
        tokenize(searchComposerText).last ?? searchComposerText.trimmed
    }

    var validRowCount: Int {
        stagedRows.filter { $0.rowState == .valid }.count
    }

    var invalidRowCount: Int {
        stagedRows.filter { $0.rowState != .valid }.count
    }

    var hasStagedRows: Bool {
        !stagedRows.isEmpty
    }

    var isShowingCategoryBrowser: Bool {
        selectedCatalogCategory == nil && debouncedCatalogSearchText.isEmpty && highlightedItemID == nil
    }

    func reset() {
        selectedTab = .search
        catalogSearchText = ""
        debouncedCatalogSearchText = ""
        selectedCatalogCategory = nil
        searchComposerText = ""
        unresolvedTokens = []
        stagedRows = []
        expandedItemIDs = []
        highlightedItemID = nil
        updateCatalogSearch()
    }

    /// Centralized handler for any catalog navigation change (search text, category, etc.).
    /// Resets transient UI state that shouldn't persist across navigation.
    private func onCatalogNavigationChanged() {
        highlightedItemID = nil
        expandedItemIDs = []
    }

    func onCatalogSearchTextChanged() {
        onCatalogNavigationChanged()
        SearchQuerySupport.schedule(text: catalogSearchText, debouncer: catalogSearchDebouncer) {
            self.debouncedCatalogSearchText = $0
            self.updateCatalogSearch()
        }
    }

    func applyCatalogSearchImmediately() {
        debouncedCatalogSearchText = SearchQuerySupport.normalized(catalogSearchText)
        updateCatalogSearch()
    }

    func onCatalogCategoryChanged() {
        onCatalogNavigationChanged()
        updateCatalogSearch()
    }

    func stageCatalogItem(_ item: PantryCatalogItemDefinition) {
        var d = draft(for: item)
        let resolvedFacets = catalogResolvedFacets(for: item)
        if !resolvedFacets.isEmpty {
            // Search specified facets — clear catalog defaults so only
            // the search-resolved facets are pre-selected.
            d.selectedFacetValues = [:]
            for facet in resolvedFacets {
                d.selectedFacetValues[facet.key] = facet.value
            }
        }
        stagedRows.append(d)
    }

    func draft(for item: PantryCatalogItemDefinition) -> PantryIntakeRowDraft {
        PantryIntakeRowDraft(itemDefinition: item, preference: preferenceStore.preference(for: item.id))
    }

    func isCatalogItemSelected(_ item: PantryCatalogItemDefinition) -> Bool {
        stagedRows.contains { $0.selectedItemID == item.id }
    }

    func toggleCatalogItemSelection(_ item: PantryCatalogItemDefinition) {
        if isCatalogItemSelected(item) {
            stagedRows.removeAll { $0.selectedItemID == item.id }
            expandedItemIDs.remove(item.id)
        } else {
            stageCatalogItem(item)
            expandedItemIDs.insert(item.id)
        }
    }

    func toggleExpanded(_ itemID: String) {
        if expandedItemIDs.contains(itemID) {
            expandedItemIDs.remove(itemID)
        } else {
            expandedItemIDs.insert(itemID)
        }
    }

    func addAnotherInstance(_ item: PantryCatalogItemDefinition) {
        stagedRows.append(PantryIntakeRowDraft(blankFor: item))
    }

    func stagedDrafts(for itemID: String) -> [PantryIntakeRowDraft] {
        stagedRows.filter { $0.selectedItemID == itemID }
    }

    func removeStagedInstance(draftID: UUID) {
        guard let idx = stagedRows.firstIndex(where: { $0.id == draftID }) else { return }
        let itemID = stagedRows[idx].selectedItemID
        stagedRows.remove(at: idx)
        if let itemID, !stagedRows.contains(where: { $0.selectedItemID == itemID }) {
            expandedItemIDs.remove(itemID)
        }
    }

    @discardableResult
    func stageSearchEntries() -> Int {
        let tokens = tokenize(searchComposerText)
        unresolvedTokens = []
        guard !tokens.isEmpty else { return 0 }

        var addedCount = 0
        for token in tokens {
            if let item = resolveSearchToken(token) {
                stageCatalogItem(item)
                addedCount += 1
            } else {
                unresolvedTokens.append(token)
            }
        }

        if addedCount > 0 {
            selectedTab = .review
            searchComposerText = ""
        }

        return addedCount
    }

    func stageSingleSearchMatch(_ item: PantryCatalogItemDefinition) {
        stageCatalogItem(item)
        searchComposerText = ""
        unresolvedTokens = []
        selectedTab = .review
    }

    func updateStagedRow(_ draft: PantryIntakeRowDraft) {
        stagedRows.update(draft)
    }

    func updateStagedFacet(draftID: UUID, key: PantryFacetKey, value: String?) {
        guard let idx = stagedRows.firstIndex(where: { $0.id == draftID }) else { return }
        stagedRows[idx].setFacet(key, value: value)
    }

    func updateStagedStorage(draftID: UUID, storage: PantryStorage) {
        guard let idx = stagedRows.firstIndex(where: { $0.id == draftID }) else { return }
        stagedRows[idx].setStorage(storage)
    }

    func updateStagedUnit(draftID: UUID, unit: MeasurementUnit?) {
        guard let idx = stagedRows.firstIndex(where: { $0.id == draftID }) else { return }
        if let unit {
            stagedRows[idx].setUnit(unit)
        } else {
            stagedRows[idx].unit = nil
            stagedRows[idx].unitWasEdited = false
        }
    }

    func updateStagedQuantity(draftID: UUID, quantity: String) {
        guard let idx = stagedRows.firstIndex(where: { $0.id == draftID }) else { return }
        stagedRows[idx].setQuantityText(quantity)
    }

    func updateStagedQuantity(draftID: UUID, quantity: Double?) {
        guard let idx = stagedRows.firstIndex(where: { $0.id == draftID }) else { return }
        if let quantity {
            stagedRows[idx].setQuantityText(PantryIntakeRowDraft.quantityString(quantity))
        } else {
            stagedRows[idx].quantityText = ""
            stagedRows[idx].quantityWasEdited = false
        }
    }

    func removeStagedRow(_ draft: PantryIntakeRowDraft) {
        stagedRows.removeAll { $0.id == draft.id }
    }

    func hasSavedDefault(for catalogItemID: String?) -> Bool {
        guard let catalogItemID else { return false }
        return preferenceStore.preference(for: catalogItemID) != nil
    }

    func savedDefault(for catalogItemID: String?) -> PantryItemDefaultPreference? {
        guard let catalogItemID else { return nil }
        return preferenceStore.preference(for: catalogItemID)
    }

    func saveDefault(for draft: PantryIntakeRowDraft) {
        guard let preference = PantryItemDefaultPreference(draft: draft) else { return }
        preferenceStore.savePreference(preference)
    }

    func removeDefault(for catalogItemID: String) {
        preferenceStore.removePreference(for: catalogItemID)
    }

    private func resolveSearchToken(_ token: String) -> PantryCatalogItemDefinition? {
        if let exact = PantryCatalog.resolveExact(name: token) {
            return exact
        }

        let results = CatalogSearchEngine.search(token)
        return results.count == 1 ? results[0].item : nil
    }

    private func tokenize(_ input: String) -> [String] {
        input
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map(\.trimmed)
            .filter { !$0.isEmpty }
    }
}

@Observable
@MainActor
final class PantryViewModel: AsyncActionHandling {
    var searchText = ""
    private(set) var debouncedSearchText = ""
    var selectedCategory: FoodCategory?
    var showAddItem = false
    var bulkAdd: PantryBulkAddViewModel
    var showVoiceInput = false
    var sortOrder: SortOrder = .category
    var isLoading = false
    @ObservationIgnored private let searchDebouncer = TaskDebouncer()
    @ObservationIgnored private let pantryActions: PantryActions

    enum SortOrder: String, CaseIterable {
        case category = "Category"
        case expiry = "Expiry Date"
        case name = "Name"
        case dateAdded = "Date Added"
    }

    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        self.bulkAdd = PantryBulkAddViewModel(preferenceStore: appState.pantryItemPreferenceStore)
        self.debouncedSearchText = ""
        self.pantryActions = PantryActions(appState: appState)
    }

    var filteredItems: [PantryItem] {
        var items = SearchQuerySupport.filtered(
            appState.pantryItems,
            query: debouncedSearchText
        ) { $0.name }

        if let category = selectedCategory {
            items = items.filter { $0.category == category }
        }

        switch sortOrder {
        case .category:
            items.sort { $0.category.rawValue < $1.category.rawValue }
        case .expiry:
            items.sort { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }
        case .name:
            items.sort { $0.name < $1.name }
        case .dateAdded:
            items.sort { $0.dateAdded > $1.dateAdded }
        }

        return items
    }

    var groupedByCategory: [(FoodCategory, [PantryItem])] {
        let grouped = Dictionary(grouping: filteredItems, by: { $0.category })
        return grouped.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    /// Groups items by category, then by identity within each category.
    /// Items with the same identity but different expiry dates are grouped together as a batch.
    var groupedByCategoryAndIdentity: [(FoodCategory, [PantryItemBatch])] {
        groupedByCategory.map { category, items in
            let batches = Dictionary(grouping: items) { appState.pantryItemIdentityKey($0) }
                .map { _, groupedItems -> PantryItemBatch in
                    let sortedItems = groupedItems.sorted { left, right in
                        // Sort by expiry date ascending (nil last)
                        switch (left.expiryDate, right.expiryDate) {
                        case let (l?, r?): return l < r
                        case (nil, .some): return false
                        case (.some, nil): return true
                        case (nil, nil): return left.dateAdded > right.dateAdded
                        }
                    }
                    return PantryItemBatch(items: sortedItems)
                }
                .sorted { left, right in
                    // Sort batches by earliest expiry date
                    switch (left.earliestExpiry, right.earliestExpiry) {
                    case let (l?, r?): return l < r
                    case (nil, .some): return false
                    case (.some, nil): return true
                    case (nil, nil): return left.representativeItem.name < right.representativeItem.name
                    }
                }
            return (category, batches)
        }
    }

    var activeCategoryCount: [FoodCategory: Int] {
        Dictionary(grouping: appState.pantryItems, by: { $0.category })
            .mapValues { $0.count }
    }

    func prepareBulkAdd() {
        bulkAdd.reset()
        showAddItem = true
    }

    func addItem(_ item: PantryItem) async {
        await pantryActions.addItem(item)
    }

    func addItem(_ item: PantryItem) {
        runTask { [self] in
            await self.addItem(item)
        }
    }

    func deleteItem(_ item: PantryItem) async {
        await pantryActions.deleteItem(item)
    }

    func deleteItem(_ item: PantryItem) {
        runTask { [self] in
            await self.deleteItem(item)
        }
    }

    func updateItem(_ item: PantryItem) async {
        await pantryActions.updateItem(item)
    }

    func updateItem(_ item: PantryItem) {
        runTask { [self] in
            await self.updateItem(item)
        }
    }

    @discardableResult
    func addStagedItems(_ drafts: [PantryIntakeRowDraft]) async -> Int {
        await pantryActions.addStagedItems(drafts)
    }

    func onSearchTextChanged() {
        SearchQuerySupport.schedule(text: searchText, debouncer: searchDebouncer) {
            self.debouncedSearchText = $0
        }
    }

    func applySearchTextImmediately() {
        debouncedSearchText = SearchQuerySupport.normalized(searchText)
    }
}
