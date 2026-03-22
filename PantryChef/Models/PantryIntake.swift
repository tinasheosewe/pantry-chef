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
    var selectedItemID: String?
    var selectedFacetValues: [PantryFacetKey: String] = [:]
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

        if selectedItemID == nil, let resolved = PantryCatalog.resolveExact(name: item.name) {
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

    init(itemDefinition: PantryCatalogItemDefinition) {
        self.init()
        selectItem(itemDefinition)
    }

    var selectedItem: PantryCatalogItemDefinition? {
        PantryCatalog.item(id: selectedItemID)
    }

    var matchingItems: [PantryCatalogItemDefinition] {
        guard !searchText.trimmed.isEmpty else { return [] }
        return PantryCatalog.search(searchText)
    }

    var estimatedExpiryDate: Date? {
        guard let window = estimatedFreshnessWindow else { return nil }
        return Calendar.current.date(byAdding: .day, value: window.upperBound, to: Date())
    }

    var facetDefinitions: [PantryFacetDefinition] {
        selectedItem?.facets ?? []
    }

    var selectedFacets: [PantryFacetSelection] {
        facetDefinitions.compactMap { definition in
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
            let severity: PantryIntakeWarningSeverity = searchText.trimmed.isEmpty ? .blocking : .warning
            let message = searchText.trimmed.isEmpty
                ? "Select a pantry item from the catalog."
                : "\"\(searchText.trimmed)\" is not supported by the current pantry catalog."
            let kind: PantryIntakeWarningKind = searchText.trimmed.isEmpty ? .missingItem : .unsupportedInput
            warnings.append(PantryIntakeWarning(kind: kind, severity: severity, message: message))
            return warnings
        }

        if storage == nil {
            warnings.append(PantryIntakeWarning(kind: .missingRequiredState, severity: .blocking, message: "Choose where this item will be stored."))
        }

        if quantityText.trimmed.isEmpty {
            warnings.append(PantryIntakeWarning(kind: .missingQuantity, severity: .blocking, message: "Enter a quantity before adding this item."))
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
        if searchText.trimmed.isEmpty && selectedItemID == nil {
            return .empty
        }
        if warnings.contains(where: { $0.severity == .blocking }) {
            return .invalid
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

    mutating func selectItem(_ item: PantryCatalogItemDefinition) {
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
    }

    mutating func updateSearchText(_ text: String) {
        searchText = text
        if selectedItemID != nil {
            clearSelection(keepingSearchText: true)
        }
    }

    mutating func clearSelection(keepingSearchText: Bool = false) {
        let currentSearchText = searchText
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

    func buildItem(existingID: UUID? = nil, existingDateAdded: Date? = nil, existingImageURL: String? = nil) -> PantryItem? {
        guard rowState == .valid, let selectedItem, let storage else { return nil }
        let notesValue = notes.trimmed.isEmpty ? nil : notes.trimmed
        return PantryItem(
            id: existingID ?? UUID(),
            name: selectedItem.displayName(for: selectedFacets),
            category: selectedItem.category,
            quantity: parsedQuantity,
            unit: parsedQuantity == nil ? nil : (unit ?? selectedItem.suggestedUnit(for: selectedFacets)),
            expiryDate: resolvedExpiryDate,
            dateAdded: existingDateAdded ?? Date(),
            notes: notesValue,
            imageURL: existingImageURL,
            catalogItemID: selectedItem.id,
            facets: selectedFacets,
            storage: storage,
            freshnessSource: expiryDateWasEdited ? .userProvided : .estimated
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

    private static func quantityString(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }
}