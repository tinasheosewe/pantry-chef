import SwiftUI

struct PantryView: View {
    @State private var viewModel: PantryViewModel
    @State private var editingItem: PantryItem?

    init(appState: AppState) {
        _viewModel = State(initialValue: PantryViewModel(appState: appState))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            VStack(spacing: 0) {
                inputMethodsBar
                searchAndSortBar

                if viewModel.appState.pantryItems.isEmpty {
                    EmptyStateView(
                        icon: "refrigerator",
                        title: "Your pantry is empty",
                        message: "Add items manually while the structured pantry intake flow is being built.",
                        actionTitle: "Add First Item"
                    ) {
                        viewModel.showAddItem = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    pantryList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityIdentifier("pantry.screen")
            .background(AppColors.background)
            .navigationTitle("Pantry")
            .sheet(isPresented: $viewModel.showAddItem) {
                AddPantryItemView { item in
                    Task { await viewModel.addItem(item) }
                }
            }
            .sheet(item: $editingItem) { item in
                AddPantryItemView(item: item) { updatedItem in
                    Task { await viewModel.updateItem(updatedItem) }
                }
            }
        }
    }

    // MARK: - Input Methods Bar
    private var inputMethodsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                InputMethodButton(icon: "plus.circle.fill", title: "Add", color: AppColors.primaryGreen) {
                    viewModel.showAddItem = true
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(AppColors.cardBackground)
    }

    // MARK: - Search & Sort
    private var searchAndSortBar: some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.mediumGray)
                TextField("Search pantry...", text: $viewModel.searchText)
                    .font(.subheadline)
                    .accessibilityIdentifier("pantry.searchField")
                    .onChange(of: viewModel.searchText) {
                        viewModel.onSearchTextChanged()
                    }

                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.mediumGray)
                    }
                }
            }
            .padding(10)
            .background(AppColors.lightGray)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryPill(title: "All", isSelected: viewModel.selectedCategory == nil) {
                        viewModel.selectedCategory = nil
                    }
                    ForEach(FoodCategory.allCases) { category in
                        if let count = viewModel.activeCategoryCount[category], count > 0 {
                            CategoryPill(
                                title: "\(category.rawValue) (\(count))",
                                isSelected: viewModel.selectedCategory == category
                            ) {
                                viewModel.selectedCategory = viewModel.selectedCategory == category ? nil : category
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Pantry List
    private var pantryList: some View {
        List {
            ForEach(viewModel.groupedByCategory, id: \.0) { category, items in
                Section {
                    ForEach(items) { item in
                        Button {
                            editingItem = item
                        } label: {
                            PantryItemRow(item: item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pantry.item.\(item.id.uuidString)")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteItem(item) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        CategoryIcon(category: category, size: 24)
                        Text(category.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .accessibilityIdentifier("pantry.list")
        .listStyle(.insetGrouped)
    }
}

// MARK: - Input Method Button
struct InputMethodButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(AppColors.darkText)
            }
            .frame(width: 70, height: 56)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Category Pill
struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AppColors.primaryGreen : AppColors.lightGray)
                .foregroundStyle(isSelected ? .white : AppColors.subtleText)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Pantry Item Row
struct PantryItemRow: View {
    let item: PantryItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    if !item.displayQuantity.isEmpty {
                        Text(item.displayQuantity)
                    }

                    Label(item.storage.rawValue, systemImage: item.storage.icon)
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }
            }

            Spacer()

            if item.expiryDate != nil {
                ExpiryBadge(status: item.expiryStatus, daysLeft: item.daysUntilExpiry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - Add Pantry Item View
struct AddPantryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PantryIntakeRowDraft

    private let existingItem: PantryItem?
    let onSave: (PantryItem) -> Void

    init(item: PantryItem? = nil, onSave: @escaping (PantryItem) -> Void) {
        self.existingItem = item
        self.onSave = onSave
        _draft = State(initialValue: PantryIntakeRowDraft(item: item))
    }

    private var isEditing: Bool {
        existingItem != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Catalog Item") {
                    TextField("Search pantry catalog", text: Binding(
                        get: { draft.searchText },
                        set: { draft.updateSearchText($0) }
                    ))
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("pantry.form.nameField")

                    if let selectedItem = draft.selectedItem {
                        HStack(spacing: 12) {
                            CategoryIcon(category: selectedItem.category, size: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedItem.displayName(for: draft.selectedFacets))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(selectedItem.category.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.subtleText)
                            }
                            Spacer()
                            Button("Clear") {
                                draft.clearSelection(keepingSearchText: true)
                            }
                            .font(.caption)
                        }
                    }

                    if draft.selectedItem == nil {
                        ForEach(Array(draft.matchingItems.prefix(8))) { item in
                            Button {
                                draft.selectItem(item)
                            } label: {
                                HStack(spacing: 10) {
                                    CategoryIcon(category: item.category, size: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .foregroundStyle(AppColors.darkText)
                                        Text(item.category.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(AppColors.subtleText)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if draft.matchingItems.isEmpty && !draft.searchText.trimmed.isEmpty {
                            Text("No exact catalog items match this search. Pick from the supported ontology only.")
                                .font(.caption)
                                .foregroundStyle(AppColors.softRed)
                        }
                    }
                }

                if !draft.facetDefinitions.isEmpty {
                    Section("Facets") {
                        ForEach(draft.facetDefinitions, id: \.key) { definition in
                            Picker(definition.key.title, selection: Binding(
                                get: { draft.selectedFacetValues[definition.key] ?? "" },
                                set: { newValue in
                                    draft.setFacet(definition.key, value: newValue.isEmpty ? nil : newValue)
                                }
                            )) {
                                Text("None").tag("")
                                ForEach(definition.options, id: \.self) { option in
                                    Text(option.capitalized).tag(option)
                                }
                            }
                        }
                    }
                }

                Section("Storage & Freshness") {
                    Picker("Storage", selection: Binding(
                        get: { draft.storage },
                        set: { newValue in
                            if let newValue {
                                draft.setStorage(newValue)
                            } else {
                                draft.clearStorage()
                            }
                        }
                    )) {
                        Text("Select storage").tag(Optional<PantryStorage>.none)
                        ForEach(PantryStorage.allCases) { storage in
                            Label(storage.rawValue, systemImage: storage.icon)
                                .tag(Optional(storage))
                        }
                    }

                    if let expiryDate = draft.manualExpiryDate {
                        DatePicker("Expires on", selection: Binding(
                            get: { expiryDate },
                            set: { draft.setExpiryDate($0) }
                        ), displayedComponents: .date)
                    } else {
                        LabeledContent("Expires on") {
                            Text(" ")
                                .foregroundStyle(AppColors.subtleText)
                        }
                    }

                    if let summary = draft.freshnessSummaryText() {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(AppColors.subtleText)
                    }
                    if let expiryDate = draft.estimatedExpiryDate {
                        Text("Estimated expiry: \(expiryDate.shortDisplay)")
                            .font(.caption)
                            .foregroundStyle(AppColors.subtleText)
                    }
                }

                Section("Quantity") {
                    HStack {
                        TextField("Amount", text: Binding(
                            get: { draft.quantityText },
                            set: { draft.setQuantityText($0) }
                        ))
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("pantry.form.quantityField")
                        Picker("Unit", selection: Binding(
                            get: { draft.unit ?? draft.selectedItem?.suggestedUnit(for: draft.selectedFacets) ?? .piece },
                            set: { draft.setUnit($0) }
                        )) {
                            ForEach(MeasurementUnit.allCases) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                    }
                    if draft.quantityIsInvalid {
                        Text("Enter a valid number for quantity")
                            .font(.caption)
                            .foregroundStyle(AppColors.softRed)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3)
                        .accessibilityIdentifier("pantry.form.notesField")
                }

                if !draft.warnings.isEmpty {
                    Section("Review") {
                        ForEach(draft.warnings) { warning in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: icon(for: warning.severity))
                                    .foregroundStyle(color(for: warning.severity))
                                Text(warning.message)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.subtleText)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        if let item = draft.buildItem(existingID: existingItem?.id, existingDateAdded: existingItem?.dateAdded, existingImageURL: existingItem?.imageURL) {
                            onSave(item)
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("pantry.form.saveButton")
                    .disabled(draft.rowState != .valid)
                }
            }
        }
    }

    private func icon(for severity: PantryIntakeWarningSeverity) -> String {
        switch severity {
        case .blocking: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .informational: return "info.circle.fill"
        }
    }

    private func color(for severity: PantryIntakeWarningSeverity) -> Color {
        switch severity {
        case .blocking: return AppColors.softRed
        case .warning: return AppColors.warmOrange
        case .informational: return AppColors.accentBlue
        }
    }
}
