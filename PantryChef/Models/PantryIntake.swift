import Foundation

enum PantryIntakeWarningSeverity: String, Hashable {
    case blocking
    case warning
    case informational
}

enum PantryIntakeWarningKind: String, Hashable {
    case missingItem = "missing-item"
    case unsupportedInput = "unsupported-input"
    case invalidFacetCombination = "invalid-facet-combination"
    case missingRequiredState = "missing-required-state"
    case missingQuantity = "missing-quantity"
}

enum PantryIntakeRowState: String, Hashable {
    case empty
    case incomplete
    case valid
    case invalid
}

struct PantryItemDefaultPreference: Codable, Hashable, Sendable {
    let catalogItemID: String
    let facets: [PantryFacetSelection]
    let storage: PantryStorage
    let quantity: Double?
    let unit: MeasurementUnit?
    let expiryOffsetDays: Int?
    let notes: String?

    init?(draft: PantryIntakeRowDraft, referenceDate: Date = Date()) {
        guard let selectedItem = draft.selectedItem, let storage = draft.storage else { return nil }

        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: referenceDate)

        self.catalogItemID = selectedItem.id
        self.facets = draft.selectedFacets
        self.storage = storage
        self.quantity = draft.parsedQuantity
        self.unit = draft.unit ?? selectedItem.suggestedUnit(for: draft.selectedFacets)
        self.expiryOffsetDays = draft.resolvedExpiryDate.map {
            calendar.dateComponents([.day], from: baseDate, to: calendar.startOfDay(for: $0)).day ?? 0
        }
        self.notes = draft.notes.trimmed.nilIfEmpty
    }
}

struct PantryIntakeWarning: Identifiable, Hashable {
    let kind: PantryIntakeWarningKind
    let severity: PantryIntakeWarningSeverity
    let message: String

    var id: String {
        "\(kind.rawValue):\(message)"
    }
}

struct PantryIntakeRowDraft: Identifiable {
    let id: UUID
    var searchText: String = ""
    var isCustomItem = false
    var customCategory: FoodCategory = .other
    var selectedItemID: String?
    var selectedFacetValues: [PantryFacetKey: String] = [:]
    var customFacetKeys: Set<PantryFacetKey> = []
    var storage: PantryStorage?
    var quantityText: String = ""
    var quantityWasEdited = false
    var unit: MeasurementUnit?
    var unitWasEdited = false
    var manualExpiryDate: Date? = Date()
    var expiryDateWasEdited = false
    var notes: String = ""

    init(id: UUID = UUID(), item: PantryItem? = nil) {
        self.id = id
        manualExpiryDate = Date()
        guard let item else { return }
        searchText = item.name
        isCustomItem = item.catalogItemID == nil
        customCategory = item.category
        selectedItemID = item.catalogItemID
        selectedFacetValues = Dictionary(uniqueKeysWithValues: item.facets.map { ($0.key, $0.value) })
        storage = item.storage
        quantityText = item.quantity.map { PantryIntakeRowDraft.quantityString($0) } ?? ""
        quantityWasEdited = item.quantity != nil
        unit = item.unit
        unitWasEdited = false
        manualExpiryDate = item.expiryDate
        expiryDateWasEdited = item.freshnessSource == .userProvided
        notes = item.notes ?? ""

        if !isCustomItem, selectedItemID == nil, let resolved = PantryCatalog.resolveExact(name: item.name) {
            selectedItemID = resolved.id
            if storage == nil {
                storage = resolved.defaultStorage
            }
            applyCatalogDefaults(for: resolved)
            if unit == nil {
                unit = resolved.suggestedUnit(for: selectedFacets)
            }
            refreshSuggestedUnit(for: resolved)
            refreshSuggestedQuantity(for: resolved)
        }
    }

    init(itemDefinition: PantryCatalogItemDefinition, preference: PantryItemDefaultPreference? = nil) {
        self.init()
        selectItem(itemDefinition)
        if let preference {
            applyUserDefault(preference)
        }
    }

    /// Creates a blank draft linked to a catalog item but with no defaults applied.
    init(blankFor itemDefinition: PantryCatalogItemDefinition) {
        self.init()
        selectedItemID = itemDefinition.id
        isCustomItem = itemDefinition.isUserDefined
    }

    var selectedItem: PantryCatalogItemDefinition? {
        PantryCatalog.item(id: selectedItemID)
    }

    var matchingItems: [PantryCatalogItemDefinition] {
        guard !searchText.trimmed.isEmpty else { return [] }
        return CatalogSearchEngine.search(searchText).map(\.item)
    }

    var estimatedExpiryDate: Date? {
        // Use catalog freshness if available
        if let window = estimatedFreshnessWindow {
            return Calendar.current.date(byAdding: .day, value: window.upperBound, to: Date())
        }
        // Fallback defaults by storage type
        guard let storage else { return nil }
        switch storage {
        case .frozen:
            return Calendar.current.date(byAdding: .year, value: 1, to: Date())
        case .pantry:
            return Calendar.current.date(byAdding: .month, value: 6, to: Date())
        case .refrigerated:
            return Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date())
        }
    }

    var facetDefinitions: [PantryFacetDefinition] {
        if isCustomItem {
            return customFacetKeys.sorted(by: { $0.rawValue < $1.rawValue }).map { key in
                let value = selectedFacetValues[key] ?? ""
                return PantryFacetDefinition(key: key, options: value.isEmpty ? [] : [value])
            }
        }
        return selectedItem?.facets ?? []
    }

    var selectedFacets: [PantryFacetSelection] {
        if isCustomItem {
            return customFacetKeys.compactMap { key in
                guard let value = selectedFacetValues[key], !value.isEmpty else { return nil }
                return PantryFacetSelection(key: key, value: value)
            }
        }
        return facetDefinitions.compactMap { definition in
            guard let value = selectedFacetValues[definition.key], definition.options.contains(value) else {
                return nil
            }
            return PantryFacetSelection(key: definition.key, value: value)
        }
    }

    var parsedQuantity: Double? {
        guard !quantityText.trimmed.isEmpty else { return nil }
        return Double(quantityText.trimmed)
    }

    var quantityIsInvalid: Bool {
        !quantityText.trimmed.isEmpty && parsedQuantity == nil
    }

    var estimatedFreshnessWindow: ClosedRange<Int>? {
        guard let selectedItem, let storage else { return nil }
        return selectedItem.freshnessRange(for: storage)
    }

    var resolvedExpiryDate: Date? {
        if !expiryDateWasEdited {
            return estimatedExpiryDate
        }
        return manualExpiryDate
    }

    var warnings: [PantryIntakeWarning] {
        var warnings: [PantryIntakeWarning] = []

        guard let selectedItem else {
            if isCustomItem {
                if searchText.trimmed.isEmpty {
                    warnings.append(PantryIntakeWarning(kind: .missingItem, severity: .blocking, message: "Enter a custom pantry item name."))
                }

                if storage == nil {
                    warnings.append(PantryIntakeWarning(kind: .missingRequiredState, severity: .blocking, message: "Choose where this item will be stored."))
                }

                if quantityIsInvalid {
                    warnings.append(PantryIntakeWarning(kind: .unsupportedInput, severity: .blocking, message: "Enter a valid numeric quantity."))
                }

                if !searchText.trimmed.isEmpty {
                    warnings.append(PantryIntakeWarning(kind: .unsupportedInput, severity: .informational, message: "Custom pantry items are stored without catalog identity and only match identical unresolved recipe ingredients."))
                }
            } else {
                let severity: PantryIntakeWarningSeverity = searchText.trimmed.isEmpty ? .blocking : .warning
                let message = searchText.trimmed.isEmpty
                    ? "Select a pantry item from the catalog or add a custom pantry item."
                    : "\"\(searchText.trimmed)\" is not supported by the current pantry catalog."
                let kind: PantryIntakeWarningKind = searchText.trimmed.isEmpty ? .missingItem : .unsupportedInput
                warnings.append(PantryIntakeWarning(kind: kind, severity: severity, message: message))
            }
            return warnings
        }

        if storage == nil {
            warnings.append(PantryIntakeWarning(kind: .missingRequiredState, severity: .blocking, message: "Choose where this item will be stored."))
        }

        for definition in facetDefinitions {
            if let value = selectedFacetValues[definition.key], !definition.options.contains(value) {
                warnings.append(PantryIntakeWarning(kind: .invalidFacetCombination, severity: .blocking, message: "\(value) is not a valid \(definition.key.title.lowercased()) for \(selectedItem.name)."))
            }
        }

        if quantityIsInvalid {
            warnings.append(PantryIntakeWarning(kind: .unsupportedInput, severity: .blocking, message: "Enter a valid numeric quantity."))
        }

        return warnings
    }

    var rowState: PantryIntakeRowState {
        if searchText.trimmed.isEmpty && selectedItemID == nil && !isCustomItem {
            return .empty
        }
        if warnings.contains(where: { $0.severity == .blocking }) {
            return .invalid
        }
        if isCustomItem {
            return .valid
        }
        if selectedItemID == nil || storage == nil {
            return .incomplete
        }
        return .valid
    }

    var hasBlockingWarnings: Bool {
        warnings.contains(where: { $0.severity == .blocking })
    }

    var displayName: String {
        selectedItem?.displayName(for: selectedFacets) ?? searchText.trimmed
    }

    var canonicalName: String {
        selectedItem?.name ?? searchText.trimmed
    }

    func matchesDefaultPreference(_ preference: PantryItemDefaultPreference?, referenceDate: Date = Date()) -> Bool {
        guard let preference else { return false }
        return PantryItemDefaultPreference(draft: self, referenceDate: referenceDate) == preference
    }

    mutating func selectItem(_ item: PantryCatalogItemDefinition) {
        isCustomItem = false
        customCategory = item.category
        selectedItemID = item.id
        searchText = item.name
        if storage == nil {
            storage = item.defaultStorage
        }
        quantityWasEdited = false
        unitWasEdited = false
        pruneInvalidFacetSelections(for: item)
        applyCatalogDefaults(for: item)
        refreshSuggestedUnit(for: item)
        refreshSuggestedQuantity(for: item)
        refreshPrefilledExpiryDate()
        if item.category.defaultsToOnHand {
            quantityText = ""
            unit = nil
        }
    }

    mutating func resetToCatalogDefaults() {
        guard let selectedItem else { return }

        searchText = selectedItem.name
        selectedFacetValues = [:]
        storage = selectedItem.defaultStorage
        quantityText = ""
        quantityWasEdited = false
        unit = nil
        unitWasEdited = false
        manualExpiryDate = Date()
        expiryDateWasEdited = false
        notes = ""

        applyCatalogDefaults(for: selectedItem)
        refreshSuggestedUnit(for: selectedItem)
        refreshSuggestedQuantity(for: selectedItem)
        refreshPrefilledExpiryDate()
    }

    mutating func applyUserDefault(_ preference: PantryItemDefaultPreference, referenceDate: Date = Date()) {
        guard let selectedItem, selectedItem.id == preference.catalogItemID else { return }

        resetToCatalogDefaults()

        for facet in preference.facets {
            guard selectedItem.options(for: facet.key).contains(facet.value) else { continue }
            selectedFacetValues[facet.key] = facet.value
        }

        storage = preference.storage

        if let quantity = preference.quantity {
            quantityText = Self.quantityString(quantity)
        }

        if let unit = preference.unit {
            self.unit = unit
        }

        if let expiryOffsetDays = preference.expiryOffsetDays {
            let startOfToday = Calendar.current.startOfDay(for: referenceDate)
            manualExpiryDate = Calendar.current.date(byAdding: .day, value: expiryOffsetDays, to: startOfToday)
            expiryDateWasEdited = true
        } else {
            refreshPrefilledExpiryDate()
        }

        notes = preference.notes ?? ""
    }

    mutating func updateSearchText(_ text: String) {
        searchText = text
        if selectedItemID != nil {
            clearSelection(keepingSearchText: true)
        }
    }

    mutating func enableCustomItemMode() {
        isCustomItem = true
        selectedItemID = nil
        selectedFacetValues = [:]
        if storage == nil {
            storage = .pantry
        }
    }

    mutating func disableCustomItemMode() {
        isCustomItem = false
        if selectedItemID == nil {
            storage = nil
            if !expiryDateWasEdited {
                manualExpiryDate = Date()
            }
        }
    }

    mutating func clearSelection(keepingSearchText: Bool = false) {
        let currentSearchText = searchText
        isCustomItem = false
        selectedItemID = nil
        selectedFacetValues = [:]
        storage = nil
        quantityWasEdited = false
        unit = nil
        unitWasEdited = false
        manualExpiryDate = Date()
        expiryDateWasEdited = false
        if keepingSearchText {
            searchText = currentSearchText
        } else {
            searchText = ""
        }
    }

    mutating func setStorage(_ storage: PantryStorage) {
        self.storage = storage
        refreshPrefilledExpiryDate()
    }

    mutating func clearStorage() {
        storage = nil
        if !expiryDateWasEdited {
            manualExpiryDate = Date()
        }
    }

    mutating func setExpiryDate(_ date: Date) {
        manualExpiryDate = date
        expiryDateWasEdited = true
    }

    mutating func setUnit(_ unit: MeasurementUnit) {
        self.unit = unit
        unitWasEdited = true

        if let selectedItem {
            refreshSuggestedQuantity(for: selectedItem)
        }
    }

    mutating func setQuantityText(_ value: String) {
        quantityText = value
        quantityWasEdited = true
    }

    mutating func setFacet(_ key: PantryFacetKey, value: String?) {
        if let value, !value.isEmpty {
            selectedFacetValues[key] = value
        } else {
            selectedFacetValues.removeValue(forKey: key)
        }

        if let selectedItem {
            refreshSuggestedUnit(for: selectedItem)
            refreshSuggestedQuantity(for: selectedItem)
        }
    }

    func buildItem(existingID: UUID? = nil, existingDateAdded: Date? = nil) -> PantryItem? {
        guard rowState == .valid, let storage else { return nil }
        let notesValue = notes.trimmed.isEmpty ? nil : notes.trimmed

        if isCustomItem {
            return PantryItem(
                id: existingID ?? UUID(),
                name: searchText.trimmed,
                category: customCategory,
                quantity: parsedQuantity,
                unit: parsedQuantity == nil ? nil : unit,
                expiryDate: resolvedExpiryDate,
                dateAdded: existingDateAdded ?? Date(),
                notes: notesValue,
                catalogItemID: selectedItemID,
                facets: selectedFacets,
                storage: storage,
                freshnessSource: expiryDateWasEdited ? .userProvided : PantryFreshnessSource.none,
                quantityMode: parsedQuantity == nil ? .presenceOnly : .exact
            )
        }

        guard let selectedItem else { return nil }
        return PantryItem(
            id: existingID ?? UUID(),
            name: selectedItem.displayName(for: selectedFacets),
            category: selectedItem.category,
            quantity: parsedQuantity,
            unit: parsedQuantity == nil ? nil : (unit ?? selectedItem.suggestedUnit(for: selectedFacets)),
            expiryDate: resolvedExpiryDate,
            dateAdded: existingDateAdded ?? Date(),
            notes: notesValue,
            catalogItemID: selectedItem.id,
            facets: selectedFacets,
            storage: storage,
            freshnessSource: expiryDateWasEdited ? .userProvided : .estimated,
            quantityMode: parsedQuantity == nil ? .presenceOnly : .exact
        )
    }

    func freshnessSummaryText() -> String? {
        guard let window = estimatedFreshnessWindow, let storage else { return nil }
        return "Estimated freshness: \(window.lowerBound)-\(window.upperBound) days when stored in \(storage.rawValue.lowercased())."
    }

    private mutating func pruneInvalidFacetSelections(for item: PantryCatalogItemDefinition) {
        let validKeys = Set(item.facets.map { $0.key })
        selectedFacetValues = selectedFacetValues.filter { validKeys.contains($0.key) }
        for definition in item.facets {
            if let value = selectedFacetValues[definition.key], !definition.options.contains(value) {
                selectedFacetValues.removeValue(forKey: definition.key)
            }
        }
    }

    private mutating func applyCatalogDefaults(for item: PantryCatalogItemDefinition) {
        for selection in item.defaultSelections {
            guard selectedFacetValues[selection.key] == nil else { continue }
            guard item.options(for: selection.key).contains(selection.value) else { continue }
            selectedFacetValues[selection.key] = selection.value
        }
    }

    private mutating func refreshPrefilledExpiryDate() {
        guard !expiryDateWasEdited else { return }
        manualExpiryDate = estimatedExpiryDate
    }

    private mutating func refreshSuggestedUnit(for item: PantryCatalogItemDefinition) {
        guard !unitWasEdited else { return }
        unit = item.suggestedUnit(for: selectedFacets)
    }

    private mutating func refreshSuggestedQuantity(for item: PantryCatalogItemDefinition) {
        guard !quantityWasEdited else { return }
        guard let suggestedQuantity = item.suggestedQuantity() else { return }
        quantityText = Self.quantityString(suggestedQuantity)
    }

    static func quantityString(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }
}

// MARK: - Custom Ingredient Definition

struct AIIngredientDefinition {
    let category: FoodCategory
    let defaultStorage: PantryStorage
    let defaultUnit: MeasurementUnit?
    let facets: [PantryFacetKey: [String]]
}

struct CustomIngredientDraft {
    var name: String
    var category: FoodCategory = .other
    var defaultStorage: PantryStorage = .pantry
    var defaultUnit: MeasurementUnit? = nil
    var facets: [PantryFacetKey: [String]] = [:]
    var defaultSelections: [PantryFacetKey: String] = [:]

    var nameCollisionWarning: String? {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return nil }
        if let existing = PantryCatalog.resolveExact(name: trimmed) {
            return "\"\(existing.titleCasedName)\" already exists in the catalog. Consider using that instead."
        }
        return nil
    }

    var sortedFacetKeys: [PantryFacetKey] {
        facets.keys.sorted { $0.rawValue < $1.rawValue }
    }

    var unusedFacetKeys: [PantryFacetKey] {
        PantryFacetKey.allCases.filter { facets[$0] == nil }
    }

    mutating func addFacetOption(_ key: PantryFacetKey, value: String) {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return }
        var options = facets[key] ?? []
        guard !options.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        options.append(trimmed)
        facets[key] = options
    }

    mutating func removeFacetOption(_ key: PantryFacetKey, value: String) {
        facets[key]?.removeAll { $0 == value }
        if defaultSelections[key] == value {
            defaultSelections.removeValue(forKey: key)
        }
        if facets[key]?.isEmpty == true {
            facets.removeValue(forKey: key)
        }
    }

    mutating func removeFacet(_ key: PantryFacetKey) {
        facets.removeValue(forKey: key)
        defaultSelections.removeValue(forKey: key)
    }

    mutating func applyAIDefinition(_ definition: AIIngredientDefinition) {
        category = definition.category
        defaultStorage = definition.defaultStorage
        defaultUnit = definition.defaultUnit
        facets = definition.facets.filter { !$0.value.isEmpty }
    }

    static func titleCase(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    func buildDefinition() -> PantryCatalogItemDefinition {
        let sanitizedName = name.trimmed.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let itemID = "user-\(sanitizedName)"

        let facetDefs: [PantryFacetDefinition] = sortedFacetKeys.compactMap { key in
            guard let options = facets[key], !options.isEmpty else { return nil }
            return PantryFacetDefinition(key: key, options: options)
        }

        let facetDefaults: [PantryFacetSelection] = sortedFacetKeys.compactMap { key in
            guard let value = defaultSelections[key] else { return nil }
            // Only include if the value is actually one of the facet options
            guard let options = facets[key], options.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return nil }
            return PantryFacetSelection(key: key, value: value)
        }

        return PantryCatalogItemDefinition(
            id: itemID,
            name: Self.titleCase(name.trimmed),
            category: category,
            defaultUnit: defaultUnit,
            defaultQuantity: nil,
            defaultStorage: defaultStorage,
            aliases: [],
            facets: facetDefs,
            defaultSelections: facetDefaults,
            substitutions: [],
            unitOverrides: [:],
            freshnessByStorage: [:],
            isUserDefined: true
        )
    }
}