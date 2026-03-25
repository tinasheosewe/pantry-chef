import SwiftUI

struct ShoppingListView: View {
    @State private var viewModel: ShoppingViewModel
    @State private var showAddItem = false
    @State private var showPantryReview = false
    @State private var pantryReviewItems: [ShoppingItem] = []
    @State private var editingPantryPlanItem: ShoppingItem?

    private let isEmbedded: Bool

    init(appState: AppState, isEmbedded: Bool = false) {
        _viewModel = State(initialValue: ShoppingViewModel(appState: appState))
        self.isEmbedded = isEmbedded
    }

    var body: some View {
        AppScreen("shopping.screen", isEmbedded: isEmbedded) {
            VStack(spacing: 0) {
                if !viewModel.items.isEmpty {
                    progressHeader
                }

                if viewModel.items.isEmpty {
                    EmptyStateView(
                        icon: "cart",
                        title: "Shopping list is empty",
                        message: "Add items manually or generate a list from your meal plan.",
                        actionTitle: "Add Item"
                    ) {
                        showAddItem = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    shoppingList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Shopping List")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showAddItem = true
                        } label: {
                            Label("Add Item", systemImage: "plus")
                        }

                        Button {
                            presentPantryReview()
                        } label: {
                            Label("Checked → Pantry", systemImage: "arrow.right.circle")
                        }
                        .disabled(viewModel.checkedCount == 0)

                        Button(role: .destructive) {
                            viewModel.removeCheckedItems()
                        } label: {
                            Label("Clear Checked", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .appNavigationSheet(isPresented: $showAddItem) {
                ShoppingAddItemView { item in
                    viewModel.addItem(item)
                    showAddItem = false
                }
            }
        }
    }

    // MARK: - Progress Header
    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text(viewModel.progressText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(PCColors.textPrimary)
                Spacer()
                if viewModel.checkedCount > 0 {
                    Button("Add to Pantry") {
                        presentPantryReview()
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(PCColors.accent)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PCColors.fillTertiary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PCColors.accent)
                        .frame(width: viewModel.totalCount > 0 ?
                               geo.size.width * CGFloat(viewModel.checkedCount) / CGFloat(viewModel.totalCount) : 0)
                        .animation(.easeInOut, value: viewModel.checkedCount)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(PCColors.cardBackground)
    }

    // MARK: - Shopping List
    private var shoppingList: some View {
        AppList {
            ForEach(viewModel.groupedByCategory, id: \.0) { category, items in
                Section {
                    ForEach(items) { item in
                        ShoppingItemRow(item: item) {
                            viewModel.toggleItem(item)
                        } onAdjust: {
                            editingPantryPlanItem = item
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.removeItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                editingPantryPlanItem = item
                            } label: {
                                Label("Pantry Plan", systemImage: "slider.horizontal.3")
                            }
                            .tint(PCColors.info)
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        CategoryIcon(category: category, size: 20)
                        Text(category.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showPantryReview, onDismiss: {
            pantryReviewItems = []
        }) {
            ShoppingPantryReviewView(items: $pantryReviewItems) { reviewedItems in
                viewModel.completeCheckedToPantry(with: reviewedItems)
                showPantryReview = false
            }
        }
        .sheet(item: $editingPantryPlanItem) { item in
            ShoppingPantryPlanEditorView(item: item) { updatedItem in
                viewModel.updateItem(updatedItem)
            }
        }
    }

    private func presentPantryReview() {
        pantryReviewItems = viewModel.checkedItems
        showPantryReview = !pantryReviewItems.isEmpty
    }
}

private struct ShoppingAddItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ShoppingAddItemViewModel()

    let onAdd: (ShoppingItem) -> Void

    var body: some View {
        @Bindable var viewModel = viewModel

        AppForm {
            if viewModel.isCustomItem || viewModel.selectedItem == nil {
                Section {
                    TextField(
                        viewModel.isCustomItem ? "Custom item name" : "Search catalog",
                        text: viewModel.isCustomItem ? $viewModel.customItemName : $viewModel.searchText
                    )
                    .appTextEntry(autocapitalization: .words, autocorrectionDisabled: true)

                    if viewModel.isCustomItem {
                        Button("Back to Catalog Search") {
                            viewModel.setCatalogMode()
                        }
                    }
                } header: {
                    Text(viewModel.isCustomItem ? "Custom Item" : "Find Item")
                } footer: {
                    if !viewModel.isCustomItem {
                        Text("Pick a catalog match first so the item carries identity into the shopping list and pantry.")
                    }
                }
            }

            if !viewModel.isCustomItem {
                if let selectedItem = viewModel.selectedItem {
                    Section("Selected Item") {
                        HStack(spacing: 12) {
                            CategoryIcon(category: selectedItem.category, size: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedItem.name)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if let facetSummary = viewModel.selectedFacetSummary {
                                    Text(facetSummary)
                                        .font(.caption)
                                        .foregroundStyle(PCColors.textSecondary)
                                }
                                Text(selectedItem.category.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(PCColors.textSecondary)
                            }
                            Spacer()
                        }

                        Button("Choose Different Item") {
                            viewModel.selectedCatalogItemID = nil
                            viewModel.selectedFacets = []
                        }
                    }

                    Section("Details") {
                        ForEach(selectedItem.facets, id: \.key) { definition in
                            Picker(
                                definition.key.title,
                                selection: Binding(
                                    get: {
                                        viewModel.selectedFacets.first(where: { $0.key == definition.key })?.value
                                            ?? definition.options.first
                                            ?? ""
                                    },
                                    set: { newValue in
                                        viewModel.setFacetValue(newValue, for: definition.key)
                                    }
                                )
                            ) {
                                ForEach(definition.options, id: \.self) { option in
                                    Text(option.replacingOccurrences(of: "-", with: " ").capitalized).tag(option)
                                }
                            }
                        }
                        TextField(
                            "Quantity",
                            text: Binding(
                                get: { viewModel.quantityText },
                                set: { viewModel.setQuantityText($0) }
                            )
                        )
                        .keyboardType(.decimalPad)
                        .appTextEntry()

                        Picker(
                            "Unit",
                            selection: Binding(
                                get: { viewModel.selectedUnit },
                                set: { viewModel.setUnit($0) }
                            )
                        ) {
                            Text("None").tag(nil as MeasurementUnit?)
                            ForEach(MeasurementUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit as MeasurementUnit?)
                            }
                        }

                        HStack {
                            Text("Category")
                            Spacer()
                            Text(selectedItem.category.rawValue)
                                .foregroundStyle(PCColors.textSecondary)
                        }
                    }
                } else {
                    Section("Catalog Matches") {
                        ForEach(viewModel.searchResults) { suggestion in
                            Button {
                                viewModel.chooseSuggestion(suggestion)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    CategoryIcon(category: suggestion.category, size: 28)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(viewModel.suggestionBaseName(suggestion))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(PCColors.textPrimary)
                                        if let facetSummary = viewModel.suggestionFacetSummary(suggestion) {
                                            Text(facetSummary)
                                                .font(.caption)
                                                .foregroundStyle(PCColors.textSecondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            viewModel.setCustomItemMode()
                        } label: {
                            Label("Can’t find it? Add Custom Item", systemImage: "square.and.pencil")
                        }
                    }
                }

            } else {
                Section("Details") {
                    TextField(
                        "Quantity",
                        text: Binding(
                            get: { viewModel.quantityText },
                            set: { viewModel.setQuantityText($0) }
                        )
                    )
                    .keyboardType(.decimalPad)
                    .appTextEntry()

                    Picker(
                        "Unit",
                        selection: Binding(
                            get: { viewModel.selectedUnit },
                            set: { viewModel.setUnit($0) }
                        )
                    ) {
                        Text("None").tag(nil as MeasurementUnit?)
                        ForEach(MeasurementUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit as MeasurementUnit?)
                        }
                    }

                    Picker("Category", selection: $viewModel.customCategory) {
                        ForEach(FoodCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                }
            }
        }
        .navigationTitle("Add Shopping Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard let item = viewModel.buildItem() else { return }
                    onAdd(item)
                    dismiss()
                }
                .disabled(!viewModel.canAdd)
            }
        }
    }

}

// MARK: - Shopping Item Row
struct ShoppingItemRow: View {
    let item: ShoppingItem
    let onToggle: () -> Void
    let onAdjust: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? PCColors.accent : PCColors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.subheadline)
                        .foregroundStyle(item.isChecked ? PCColors.textSecondary : PCColors.textPrimary)
                        .strikethrough(item.isChecked)

                    if let facetSummary = item.facetSummary {
                        Text(facetSummary)
                            .font(.caption)
                            .foregroundStyle(PCColors.textSecondary)
                            .strikethrough(item.isChecked)
                    }

                    if let requirementText = item.recipeRequirementText {
                        Text("Need: \(requirementText)")
                            .font(.caption)
                            .foregroundStyle(PCColors.textSecondary)
                    }

                    if item.isPantryPlanCustomized || item.recipeRequirementText == nil {
                        Text("Pantry: \(item.pantryPlanText)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(PCColors.info)
                    }
                }

                Spacer()

                if let source = item.recipeSource {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(PCColors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PCColors.fillTertiary)
                        .clipShape(Capsule())
                }

                Button(action: onAdjust) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline)
                        .foregroundStyle(PCColors.info)
                        .padding(8)
                        .background(PCColors.info.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ShoppingPantryReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var items: [ShoppingItem]
    let onSave: ([ShoppingItem]) -> Void

    @State private var editingItem: ShoppingItem?

    private var customizedCount: Int {
        items.filter(\.isPantryPlanCustomized).count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if items.isEmpty {
                    EmptyStateView(
                        icon: "cart.badge.questionmark",
                        title: "Nothing checked yet",
                        message: "Check shopping items first, then review what should go into Pantry."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AppList {
                        Section {
                            Text("Review what should go into Pantry. Recipe amounts stay visible, but Pantry reflects what you actually bought.")
                                .font(.subheadline)
                                .foregroundStyle(PCColors.textSecondary)
                        }

                        Section {
                            ForEach(items.indices, id: \.self) { index in
                                reviewRow(for: items[index])
                            }
                        } header: {
                            SectionHeader(
                                title: "Checked Items",
                                subtitle: customizedCount == 0 ? "Using recipe amounts unless you adjust them." : "\(customizedCount) items have custom Pantry amounts."
                            )
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .navigationTitle("Review Pantry Intake")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(items)
                    } label: {
                        Text("Add to Pantry")
                    }
                    .disabled(items.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                summaryBar
            }
        }
        .sheet(item: $editingItem) { item in
            ShoppingPantryPlanEditorView(item: item) { updatedItem in
                if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
                    items[index] = updatedItem
                }
            }
        }
    }

    private func reviewRow(for item: ShoppingItem) -> some View {
        Button {
            editingItem = item
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    CategoryIcon(category: item.category, size: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(PCColors.textPrimary)
                        if let requirementText = item.recipeRequirementText {
                            Text("Recipe needs: \(requirementText)")
                                .font(.caption)
                                .foregroundStyle(PCColors.textSecondary)
                        }
                        Text("Pantry add: \(item.pantryPlanText)")
                            .font(.caption)
                            .foregroundStyle(item.isPantryPlanCustomized ? PCColors.info : PCColors.textSecondary)
                        if let source = item.recipeSource {
                            Text(source)
                                .font(.caption2)
                                .foregroundStyle(PCColors.textSecondary)
                        }
                    }

                    Spacer()

                    if item.isPantryPlanCustomized {
                        Text("Adjusted")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(PCColors.info)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PCColors.info.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var summaryBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(items.isEmpty ? "Nothing to add" : "Add \(items.count) item\(items.count == 1 ? "" : "s") to Pantry")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                    Text("Adjusted Pantry amounts will be used when these items move out of Shopping.")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }
}

private struct ShoppingPantryPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (ShoppingItem) -> Void

    @State private var draft: ShoppingPantryPlanDraft

    init(item: ShoppingItem, onSave: @escaping (ShoppingItem) -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: ShoppingPantryPlanDraft(item: item))
    }

    var body: some View {
        AppNavigationSheet {
            AppForm {
                Section {
                    Text(draft.item.displayName)
                        .font(.headline)
                        .foregroundStyle(PCColors.textPrimary)
                    if let requirementText = draft.item.recipeRequirementText {
                        Text("Recipe needs: \(requirementText)")
                            .font(.caption)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                }

                Section {
                    Picker("How to add this", selection: $draft.quantityMode) {
                        Text("Track exact amount").tag(PantryQuantityMode.exact)
                        Text("Just mark on hand").tag(PantryQuantityMode.presenceOnly)
                    }

                    if draft.quantityMode == .exact {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            TextField("Quantity", text: $draft.quantityText)
                                .keyboardType(.decimalPad)
                                .appTextEntry()

                            Picker("Unit", selection: $draft.selectedUnit) {
                                Text("None").tag(nil as MeasurementUnit?)
                                ForEach(MeasurementUnit.allCases) { unit in
                                    Text(unit.rawValue).tag(unit as MeasurementUnit?)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Pantry Plan")
                } footer: {
                    Text("Use this when the amount you buy differs from what the recipe needs, like buying a bottle of soy sauce instead of 2 tbsp.")
                }

                if let catalogItem = draft.catalogItem {
                    Section {
                        ForEach(catalogItem.facets, id: \.key) { definition in
                            Picker(
                                definition.key.title,
                                selection: Binding(
                                    get: { draft.selection(for: definition) },
                                    set: { draft.setFacetValue($0, for: definition.key) }
                                )
                            ) {
                                ForEach(definition.options, id: \.self) { option in
                                    Text(draft.humanizedFacetValue(option)).tag(option)
                                }
                            }
                        }
                    } header: {
                        Text("Facets")
                    } footer: {
                        Text("Catalog-backed recipe items already carry structured facet choices. Adjust them here when you bought a different cut, form, or variant.")
                    }
                }
            }
            .navigationTitle("Pantry Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft.buildItem())
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
    }
}

private struct ShoppingPantryPlanDraft {
    let item: ShoppingItem
    var quantityMode: PantryQuantityMode
    var quantityText: String
    var selectedUnit: MeasurementUnit?
    var selectedFacets: [PantryFacetSelection]

    init(item: ShoppingItem) {
        self.item = item
        self.quantityMode = item.pantryQuantityMode
        self.quantityText = item.pantryQuantity.map { quantity in
            quantity == quantity.rounded() ? "\(Int(quantity))" : String(format: "%.1f", quantity)
        } ?? ""
        self.selectedUnit = item.pantryUnit ?? item.unit
        self.selectedFacets = item.facets
    }

    var catalogItem: PantryCatalogItemDefinition? {
        item.resolvedCatalogItem
    }

    var quantityValue: Double? {
        let trimmed = quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    var isValid: Bool {
        switch quantityMode {
        case .exact:
            return quantityValue != nil
        case .presenceOnly:
            return true
        }
    }

    mutating func setFacetValue(_ value: String, for key: PantryFacetKey) {
        guard let catalogItem else { return }

        var facetsByKey = Dictionary(uniqueKeysWithValues: selectedFacets.map { ($0.key, $0) })
        if catalogItem.options(for: key).contains(value) {
            facetsByKey[key] = PantryFacetSelection(key: key, value: value)
        }

        selectedFacets = catalogItem.facets.compactMap { definition in
            facetsByKey[definition.key]
        }

        if quantityMode == .exact {
            selectedUnit = catalogItem.suggestedUnit(for: selectedFacets) ?? selectedUnit
        }
    }

    func selection(for definition: PantryFacetDefinition) -> String {
        selectedFacets.first(where: { $0.key == definition.key })?.value
            ?? definition.options.first
            ?? ""
    }

    func humanizedFacetValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    func buildItem() -> ShoppingItem {
        item.updatingPantryPlan(
            quantity: quantityValue,
            unit: selectedUnit,
            quantityMode: quantityMode,
            facets: selectedFacets
        )
    }
}
