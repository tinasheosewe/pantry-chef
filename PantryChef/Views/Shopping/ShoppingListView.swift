import SwiftUI

struct ShoppingListView: View {
    @State private var viewModel: ShoppingViewModel
    @State private var showAddItem = false

    init(appState: AppState) {
        _viewModel = State(initialValue: ShoppingViewModel(appState: appState))
    }

    var body: some View {
        NavigationStack {
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
            .accessibilityIdentifier("shopping.screen")
            .background(AppColors.background)
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
            .sheet(isPresented: $showAddItem) {
                NavigationStack {
                    ShoppingAddItemView { item in
                        viewModel.addItem(item)
                        showAddItem = false
                    }
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
        List {
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

        Form {
            Section {
                TextField(
                    viewModel.isCustomItem ? "Custom item name" : "Search catalog",
                    text: viewModel.isCustomItem ? $viewModel.customItemName : $viewModel.searchText
                )
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)

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

            if !viewModel.isCustomItem {
                if let selectedItem = viewModel.selectedItem {
                    Section("Selected Item") {
                        HStack(spacing: 12) {
                            CategoryIcon(category: selectedItem.category, size: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedItem.displayName(for: viewModel.selectedFacets))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(selectedItem.category.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.subtleText)
                            }
                            Spacer()
                        }

                        ForEach(selectedItem.facets, id: \.key) { definition in
                            Picker(
                                definition.key.title,
                                selection: Binding(
                                    get: {
                                        viewModel.selectedFacets.first(where: { $0.key == definition.key })?.value ?? ""
                                    },
                                    set: { newValue in
                                        viewModel.setFacetValue(newValue.isEmpty ? nil : newValue, for: definition.key)
                                    }
                                )
                            ) {
                                Text("Default").tag("")
                                ForEach(definition.options, id: \.self) { option in
                                    Text(option.capitalized).tag(option)
                                }
                            }
                        }
                    }
                }

                Section("Catalog Matches") {
                    ForEach(viewModel.searchResults) { suggestion in
                        Button {
                            viewModel.chooseSuggestion(suggestion)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                CategoryIcon(category: suggestion.category, size: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(AppColors.darkText)
                                    Text(suggestion.rationale)
                                        .font(.caption)
                                        .foregroundStyle(AppColors.subtleText)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                if viewModel.selectedCatalogItemID == suggestion.catalogItemID && viewModel.selectedFacets == suggestion.facets {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppColors.primaryGreen)
                                }
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

            Section("Details") {
                TextField(
                    "Quantity",
                    text: Binding(
                        get: { viewModel.quantityText },
                        set: { viewModel.setQuantityText($0) }
                    )
                )
                .keyboardType(.decimalPad)

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

                if viewModel.isCustomItem {
                    Picker("Category", selection: $viewModel.customCategory) {
                        ForEach(FoodCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                } else {
                    HStack {
                        Text("Category")
                        Spacer()
                        Text(viewModel.previewCategory.rawValue)
                            .foregroundStyle(AppColors.subtleText)
                    }
                }
            }

            if !viewModel.previewName.isEmpty {
                Section("Preview") {
                    HStack(spacing: 12) {
                        CategoryIcon(category: viewModel.previewCategory, size: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.previewName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if let quantity = viewModel.quantityValue {
                                Text(quantityDisplay(quantity, unit: viewModel.selectedUnit))
                                    .font(.caption)
                                    .foregroundStyle(AppColors.subtleText)
                            }
                        }
                        Spacer()
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

    private func quantityDisplay(_ quantity: Double, unit: MeasurementUnit?) -> String {
        let quantityText = quantity == quantity.rounded() ? String(Int(quantity)) : String(format: "%.1f", quantity)
        let unitText = unit?.rawValue ?? ""
        return "\(quantityText) \(unitText)".trimmingCharacters(in: .whitespaces)
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
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(item.isChecked ? AppColors.subtleText : AppColors.darkText)
                        .strikethrough(item.isChecked)

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
