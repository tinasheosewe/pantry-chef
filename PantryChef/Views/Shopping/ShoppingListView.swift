import SwiftUI

struct ShoppingListView: View {
    @State private var viewModel: ShoppingViewModel
    @State private var showAddItem = false

    init(appState: AppState) {
        _viewModel = State(initialValue: ShoppingViewModel(appState: appState))
    }

    var body: some View {
        AppScreen("shopping.screen") {
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
                            Task { await viewModel.addCheckedToPantry() }
                        } label: {
                            Label("Checked → Pantry", systemImage: "arrow.right.circle")
                        }

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
                    .foregroundStyle(AppColors.darkText)
                Spacer()
                if viewModel.checkedCount > 0 {
                    Button("Add to Pantry") {
                        Task { await viewModel.addCheckedToPantry() }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.primaryGreen)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.lightGray)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.primaryGreen)
                        .frame(width: viewModel.totalCount > 0 ?
                               geo.size.width * CGFloat(viewModel.checkedCount) / CGFloat(viewModel.totalCount) : 0)
                        .animation(.easeInOut, value: viewModel.checkedCount)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(AppColors.cardBackground)
    }

    // MARK: - Shopping List
    private var shoppingList: some View {
        AppList {
            ForEach(viewModel.groupedByCategory, id: \.0) { category, items in
                Section {
                    ForEach(items) { item in
                        ShoppingItemRow(item: item) {
                            viewModel.toggleItem(item)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.removeItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
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
                                        .foregroundStyle(AppColors.subtleText)
                                }
                                Text(selectedItem.category.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.subtleText)
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
                                .foregroundStyle(AppColors.subtleText)
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
                                            .foregroundStyle(AppColors.darkText)
                                        if let facetSummary = viewModel.suggestionFacetSummary(suggestion) {
                                            Text(facetSummary)
                                                .font(.caption)
                                                .foregroundStyle(AppColors.subtleText)
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

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? AppColors.primaryGreen : AppColors.mediumGray)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.subheadline)
                        .foregroundStyle(item.isChecked ? AppColors.subtleText : AppColors.darkText)
                        .strikethrough(item.isChecked)

                    if let facetSummary = item.facetSummary {
                        Text(facetSummary)
                            .font(.caption)
                            .foregroundStyle(AppColors.subtleText)
                            .strikethrough(item.isChecked)
                    }

                    if let qty = item.quantity {
                        Text("\(qty == qty.rounded() ? "\(Int(qty))" : String(format: "%.1f", qty)) \(item.unit?.rawValue ?? "")")
                            .font(.caption)
                            .foregroundStyle(AppColors.subtleText)
                    }
                }

                Spacer()

                if let source = item.recipeSource {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(AppColors.subtleText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.lightGray)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}
