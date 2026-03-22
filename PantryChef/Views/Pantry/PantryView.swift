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
                        message: "Browse the catalog, search within it, stage defaults, then add everything at once.",
                        actionTitle: "Start Adding"
                    ) {
                        viewModel.prepareBulkAdd()
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
                BulkAddPantryView(viewModel: viewModel)
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
                    viewModel.prepareBulkAdd()
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
        .frame(width: 86, height: 56)
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
                PantryIntakeFormSections(draft: $draft, accessibilityPrefix: "pantry.form")
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
}

struct BulkAddPantryView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: PantryViewModel
    @State private var editingDraft: PantryIntakeRowDraft?
    @State private var isSaving = false

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $viewModel.bulkAdd.selectedTab) {
                    ForEach(PantryBulkAddViewModel.Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Group {
                    switch viewModel.bulkAdd.selectedTab {
                    case .add:
                        addTab(viewModel: viewModel)
                    case .staging:
                        bulkStagingTab(viewModel: viewModel)
                    }
                }
            }
            .background(AppColors.background)
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.bulkAdd.hasStagedRows {
                        Button("Review") {
                            viewModel.bulkAdd.selectedTab = .staging
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bulkSummaryBar(viewModel: viewModel)
            }
        }
        .sheet(item: $editingDraft) { draft in
            PantryDraftEditorView(draft: draft) { updatedDraft in
                viewModel.bulkAdd.updateStagedRow(updatedDraft)
            }
        }
    }

    private func addTab(viewModel: PantryViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                catalogSearchBar(viewModel: viewModel)

                if viewModel.bulkAdd.isShowingCategoryBrowser {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Browse Categories", subtitle: "Step into a pantry type instead of scrolling the whole ontology")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(viewModel.bulkAdd.categoryCounts, id: \.0) { category, count in
                                Button {
                                    viewModel.bulkAdd.selectedCatalogCategory = category
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        CategoryIcon(category: category, size: 34)
                                        Text(category.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(AppColors.darkText)
                                            .multilineTextAlignment(.leading)
                                        Text("\(count) items")
                                            .font(.caption)
                                            .foregroundStyle(AppColors.subtleText)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                                    .padding(14)
                                    .background(AppColors.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Common Staples", subtitle: "Fast picks for pantry setup")
                        VStack(spacing: 10) {
                            ForEach(viewModel.bulkAdd.commonItems) { item in
                                catalogItemRow(item: item) {
                                    viewModel.bulkAdd.stageCatalogItem(item)
                                }
                            }
                        }
                    }
                } else {
                    if let category = viewModel.bulkAdd.selectedCatalogCategory {
                        HStack(spacing: 10) {
                            Button {
                                viewModel.bulkAdd.selectedCatalogCategory = nil
                                viewModel.bulkAdd.catalogSearchText = ""
                                viewModel.bulkAdd.applyCatalogSearchImmediately()
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppColors.darkText)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.rawValue)
                                    .font(.headline)
                                    .foregroundStyle(AppColors.darkText)
                                Text(viewModel.bulkAdd.debouncedCatalogSearchText.isEmpty ? "Browse this category" : "Search scoped to this category")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.subtleText)
                            }

                            Spacer()
                        }
                    } else if !viewModel.bulkAdd.debouncedCatalogSearchText.isEmpty {
                        SectionHeader(title: "Search Results", subtitle: "Cross-category matches")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if viewModel.bulkAdd.filteredCatalogItems.isEmpty {
                            Text("No catalog items matched that filter.")
                                .font(.caption)
                                .foregroundStyle(AppColors.subtleText)
                        }
                        VStack(spacing: 10) {
                            ForEach(viewModel.bulkAdd.filteredCatalogItems) { item in
                                catalogItemRow(item: item) {
                                    viewModel.bulkAdd.stageCatalogItem(item)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
    }

    private func catalogSearchBar(viewModel: PantryViewModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.mediumGray)
            TextField("Search the ingredient catalog", text: Binding(
                get: { viewModel.bulkAdd.catalogSearchText },
                set: {
                    viewModel.bulkAdd.catalogSearchText = $0
                    viewModel.bulkAdd.onCatalogSearchTextChanged()
                }
            ))
            .textInputAutocapitalization(.words)

            if !viewModel.bulkAdd.catalogSearchText.isEmpty {
                Button {
                    viewModel.bulkAdd.catalogSearchText = ""
                    viewModel.bulkAdd.applyCatalogSearchImmediately()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.mediumGray)
                }
            }
        }
        .padding(12)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    private func catalogItemRow(item: PantryCatalogItemDefinition, addAction: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(category: item.category, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.darkText)
                Text(item.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
                if !item.aliases.isEmpty {
                    Text(item.aliases.prefix(3).joined(separator: " • "))
                        .font(.caption2)
                        .foregroundStyle(AppColors.subtleText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Stage", action: addAction)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.primaryGreen)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .padding(14)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private func bulkStagingTab(viewModel: PantryViewModel) -> some View {
        Group {
            if viewModel.bulkAdd.stagedRows.isEmpty {
                EmptyStateView(
                    icon: "square.stack.3d.up.slash",
                    title: "Nothing staged yet",
                    message: "Stage items from Catalog or Search, then review and edit defaults here."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "Staging Area",
                            subtitle: "\(viewModel.bulkAdd.validRowCount) ready • \(viewModel.bulkAdd.invalidRowCount) need edits"
                        )

                        ForEach(viewModel.bulkAdd.stagedRows) { draft in
                            stagedRowCard(draft: draft, viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    private func stagedRowCard(draft: PantryIntakeRowDraft, viewModel: PantryViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CategoryIcon(category: draft.selectedItem?.category ?? .other, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.displayName.isEmpty ? "Unresolved item" : draft.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.darkText)

                    Text(draft.selectedItem?.category.rawValue ?? "Needs catalog match")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)

                    HStack(spacing: 8) {
                        Text(draft.quantityText.trimmed.isEmpty ? "No quantity" : "\(draft.quantityText.trimmed) \((draft.unit ?? draft.selectedItem?.suggestedUnit(for: draft.selectedFacets) ?? .piece).rawValue)")
                        if let storage = draft.storage {
                            Label(storage.rawValue, systemImage: storage.icon)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
                }

                Spacer()
                PantryDraftStateBadge(state: draft.rowState)
            }

            if let warning = draft.warnings.first {
                HStack(spacing: 8) {
                    Image(systemName: warning.severity == .blocking ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(warning.severity == .blocking ? AppColors.softRed : AppColors.warmOrange)
                    Text(warning.message)
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }
            }

            HStack(spacing: 10) {
                Button {
                    editingDraft = draft
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.lightGray)
                        .foregroundStyle(AppColors.darkText)
                        .clipShape(Capsule())
                }

                Button(role: .destructive) {
                    viewModel.bulkAdd.removeStagedRow(draft)
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.softRed.opacity(0.12))
                        .foregroundStyle(AppColors.softRed)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(AppColors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(borderColor(for: draft.rowState), lineWidth: 1.25)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private func bulkSummaryBar(viewModel: PantryViewModel) -> some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.bulkAdd.hasStagedRows ? "\(viewModel.bulkAdd.stagedRows.count) items staged" : "Stage items to build your batch")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.darkText)
                        Text(viewModel.bulkAdd.hasStagedRows ? "\(viewModel.bulkAdd.validRowCount) ready to add now" : "Browse categories or search the catalog, then stage defaults")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                Spacer()

                Button {
                    Task {
                        isSaving = true
                        let validRows = viewModel.bulkAdd.stagedRows.filter { $0.rowState == .valid }
                        _ = await viewModel.addStagedItems(validRows)
                        viewModel.bulkAdd.stagedRows.removeAll { $0.rowState == .valid }
                        isSaving = false

                        if viewModel.bulkAdd.stagedRows.isEmpty {
                            dismiss()
                        } else {
                            viewModel.bulkAdd.selectedTab = .staging
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(viewModel.bulkAdd.validRowCount > 0 ? "Add Valid Items" : "Review Staging")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(viewModel.bulkAdd.validRowCount > 0 ? AppColors.primaryGreen : AppColors.mediumGray)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(isSaving || (!viewModel.bulkAdd.hasStagedRows && viewModel.bulkAdd.validRowCount == 0))
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func borderColor(for state: PantryIntakeRowState) -> Color {
        switch state {
        case .valid:
            return AppColors.primaryGreen.opacity(0.6)
        case .invalid:
            return AppColors.softRed.opacity(0.55)
        case .incomplete:
            return AppColors.warmOrange.opacity(0.55)
        case .empty:
            return Color.clear
        }
    }
}

struct PantryDraftStateBadge: View {
    let state: PantryIntakeRowState

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch state {
        case .valid: return "Ready"
        case .invalid: return "Fix"
        case .incomplete: return "Review"
        case .empty: return "Empty"
        }
    }

    private var color: Color {
        switch state {
        case .valid: return AppColors.primaryGreen
        case .invalid: return AppColors.softRed
        case .incomplete: return AppColors.warmOrange
        case .empty: return AppColors.mediumGray
        }
    }
}

struct FlexibleTokenWrap: View {
    let tokens: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tokens, id: \.self) { token in
                Text(token)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColors.cardBackground)
                    .foregroundStyle(AppColors.darkText)
                    .clipShape(Capsule())
            }
        }
    }
}

struct PantryDraftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PantryIntakeRowDraft
    let onSave: (PantryIntakeRowDraft) -> Void

    init(draft: PantryIntakeRowDraft, onSave: @escaping (PantryIntakeRowDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                PantryIntakeFormSections(draft: $draft, accessibilityPrefix: "pantry.bulk.form")
            }
            .navigationTitle("Edit Staged Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PantryIntakeFormSections: View {
    @Binding var draft: PantryIntakeRowDraft
    let accessibilityPrefix: String

    var body: some View {
        Section("Catalog Item") {
            TextField("Search pantry catalog", text: Binding(
                get: { draft.searchText },
                set: { draft.updateSearchText($0) }
            ))
            .textInputAutocapitalization(.words)
            .accessibilityIdentifier("\(accessibilityPrefix).nameField")

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
                .accessibilityIdentifier("\(accessibilityPrefix).quantityField")

                Picker("Unit", selection: Binding(
                    get: { draft.unit ?? draft.selectedItem?.suggestedUnit(for: draft.selectedFacets) ?? .piece },
                    set: { draft.setUnit($0) }
                )) {
                    ForEach(MeasurementUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
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
                .accessibilityIdentifier("\(accessibilityPrefix).notesField")
        }

        if !draft.warnings.isEmpty {
            Section("Review") {
                ForEach(draft.warnings) { warning in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: warningIcon(for: warning.severity))
                            .foregroundStyle(warningColor(for: warning.severity))
                        Text(warning.message)
                            .font(.caption)
                            .foregroundStyle(AppColors.subtleText)
                    }
                }
            }
        }
    }

    private func warningIcon(for severity: PantryIntakeWarningSeverity) -> String {
        switch severity {
        case .blocking: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .informational: return "info.circle.fill"
        }
    }

    private func warningColor(for severity: PantryIntakeWarningSeverity) -> Color {
        switch severity {
        case .blocking: return AppColors.softRed
        case .warning: return AppColors.warmOrange
        case .informational: return AppColors.accentBlue
        }
    }
}
