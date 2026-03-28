import SwiftUI

struct PantryView: View {
    @State private var viewModel: PantryViewModel
    @State private var editingItem: PantryItem?

    private let isEmbedded: Bool

    init(appState: AppState, isEmbedded: Bool = false) {
        _viewModel = State(initialValue: PantryViewModel(appState: appState))
        self.isEmbedded = isEmbedded
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        AppScreen("pantry.screen", isEmbedded: isEmbedded) {
            VStack(spacing: 0) {
                searchAndSortBar

                if viewModel.appState.pantryItems.isEmpty {
                    EmptyStateView(
                        icon: "refrigerator",
                        title: "Your pantry is empty",
                        message: "Browse the catalog, set your preferences, then review everything before adding it.",
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
            .navigationTitle("Pantry")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.prepareBulkAdd()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddItem) {
                BulkAddPantryView(viewModel: viewModel)
            }
            .sheet(item: $editingItem) { item in
                AddPantryItemView(
                    item: item,
                    savedDefaultForItem: { viewModel.appState.pantryItemDefaultPreference(for: $0) },
                    saveDefault: { viewModel.appState.savePantryItemDefaultPreference($0) },
                    removeDefault: { viewModel.appState.removePantryItemDefaultPreference(for: $0) }
                ) { updatedItem in
                    viewModel.updateItem(updatedItem)
                }
            }
        }
    }

    // MARK: - Search & Sort
    private var searchAndSortBar: some View {
        @Bindable var viewModel = viewModel
        return PCSearchFilterBar(
            placeholder: "Search pantry...",
            searchText: $viewModel.searchText,
            accessibilityID: "pantry.searchField",
            onTextChange: { _ in viewModel.onSearchTextChanged() }
        ) {
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

    // MARK: - Pantry List
    private var pantryList: some View {
        AppList {
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
                                viewModel.deleteItem(item)
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
                    .foregroundStyle(PCColors.textPrimary)
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
                .background(isSelected ? PCColors.accent : PCColors.fillTertiary)
                .foregroundStyle(isSelected ? .white : PCColors.textSecondary)
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
                        .foregroundStyle(PCColors.textSecondary)
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
    @State private var savedDefault: PantryItemDefaultPreference?

    private let existingItem: PantryItem?
    private let savedDefaultForItem: (String) -> PantryItemDefaultPreference?
    private let saveDefault: (PantryIntakeRowDraft) -> Void
    private let removeDefault: (String) -> Void
    let onSave: (PantryItem) -> Void

    init(
        item: PantryItem? = nil,
        savedDefaultForItem: @escaping (String) -> PantryItemDefaultPreference? = { _ in nil },
        saveDefault: @escaping (PantryIntakeRowDraft) -> Void = { _ in },
        removeDefault: @escaping (String) -> Void = { _ in },
        onSave: @escaping (PantryItem) -> Void
    ) {
        self.existingItem = item
        self.savedDefaultForItem = savedDefaultForItem
        self.saveDefault = saveDefault
        self.removeDefault = removeDefault
        self.onSave = onSave
        _draft = State(initialValue: PantryIntakeRowDraft(item: item))
        _savedDefault = State(initialValue: item?.catalogItemID.flatMap(savedDefaultForItem))
    }

    private var isEditing: Bool {
        existingItem != nil
    }

    private var showsSavedDefault: Bool {
        savedDefault != nil
    }

    private var isCurrentDefault: Bool {
        draft.matchesDefaultPreference(savedDefault)
    }

    private var saveDefaultButtonTitle: String {
        if isCurrentDefault {
            return "Current Default"
        }
        return showsSavedDefault ? "Update Default" : "Set as Default"
    }

    private func handleSaveDefault() {
        saveDefault(draft)
        savedDefault = PantryItemDefaultPreference(draft: draft)
    }

    private func handleResetDefault() {
        guard let catalogItemID = draft.selectedItemID else { return }
        removeDefault(catalogItemID)
        savedDefault = nil
        draft.resetToCatalogDefaults()
    }

    var body: some View {
        NavigationStack {
            AppForm {
                PantryIntakeFormSections(
                    draft: $draft,
                    accessibilityPrefix: "pantry.form",
                    allowsIdentityEditing: !isEditing || !(existingItem?.isCatalogBacked ?? false),
                    hasSavedDefault: showsSavedDefault,
                    saveDefaultButtonTitle: saveDefaultButtonTitle,
                    isSaveDefaultDisabled: draft.rowState != .valid || isCurrentDefault,
                    onSaveDefault: handleSaveDefault,
                    onResetDefault: handleResetDefault
                )
            }
            .navigationTitle(isEditing ? "Edit Item" : "Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        if let item = draft.buildItem(existingID: existingItem?.id, existingDateAdded: existingItem?.dateAdded) {
                            onSave(item)
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("pantry.form.saveButton")
                    .disabled(draft.rowState != .valid)
                }
            }
        }
        .onChange(of: draft.selectedItemID) {
            savedDefault = draft.selectedItemID.flatMap(savedDefaultForItem)
        }
    }
}

struct BulkAddPantryView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: PantryViewModel
    @State private var editingDraft: PantryIntakeRowDraft?
    @State private var isSaving = false
    @State private var showingReview = false
    @FocusState private var isCatalogSearchFocused: Bool

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            addTab(viewModel: viewModel)
                .background(PCColors.background)
                .navigationTitle("Add To Pantry")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if viewModel.bulkAdd.hasStagedRows {
                            Button {
                                showingReview = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Review")
                                    Text("\(viewModel.bulkAdd.stagedRows.count)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(PCColors.accent)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if viewModel.bulkAdd.hasStagedRows {
                        searchSummaryBar(viewModel: viewModel)
                    }
                }
                .navigationDestination(isPresented: $showingReview) {
                    reviewDestination(viewModel: viewModel)
                }
        }
        .sheet(item: $editingDraft) { draft in
            PantryDraftEditorView(
                draft: draft,
                savedDefaultForItem: { viewModel.bulkAdd.savedDefault(for: $0) },
                saveDefault: { viewModel.bulkAdd.saveDefault(for: $0) },
                removeDefault: { viewModel.bulkAdd.removeDefault(for: $0) }
            ) { updatedDraft in
                viewModel.bulkAdd.updateStagedRow(updatedDraft)
            }
        }
    }

    private func addTab(viewModel: PantryViewModel) -> some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 16) {
                catalogSearchBar(viewModel: viewModel)

                if viewModel.bulkAdd.isShowingCategoryBrowser {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Browse Categories", subtitle: "Step into a pantry type instead of scrolling the whole ontology")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(viewModel.bulkAdd.categoryCounts, id: \.0) { category, count in
                                VStack(alignment: .leading, spacing: 8) {
                                    CategoryIcon(category: category, size: 34)
                                    Text(category.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(PCColors.textPrimary)
                                        .multilineTextAlignment(.leading)
                                    Text("\(count) items")
                                        .font(.caption)
                                        .foregroundStyle(PCColors.textSecondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                                .padding(14)
                                .background(PCColors.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
                                .contentShape(RoundedRectangle(cornerRadius: 18))
                                .onTapGesture {
                                    viewModel.bulkAdd.selectedCatalogCategory = category
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Common Staples", subtitle: "Fast picks for pantry setup")
                        VStack(spacing: 10) {
                            ForEach(viewModel.bulkAdd.commonItems) { item in
                                catalogItemRow(item: item, viewModel: viewModel)
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
                                    .foregroundStyle(PCColors.textPrimary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.rawValue)
                                    .font(.headline)
                                    .foregroundStyle(PCColors.textPrimary)
                                Text(viewModel.bulkAdd.debouncedCatalogSearchText.isEmpty ? "Browse this category" : "Search scoped to this category")
                                    .font(.caption)
                                    .foregroundStyle(PCColors.textSecondary)
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
                                .foregroundStyle(PCColors.textSecondary)
                        }
                        VStack(spacing: 10) {
                            ForEach(viewModel.bulkAdd.filteredCatalogItems) { item in
                                catalogItemRow(item: item, viewModel: viewModel)
                            }
                        }

                        if !viewModel.bulkAdd.catalogSearchText.trimmed.isEmpty {
                            Button {
                                viewModel.bulkAdd.stageCustomItem(named: viewModel.bulkAdd.catalogSearchText)
                                showingReview = true
                            } label: {
                                Label("Add \"\(viewModel.bulkAdd.catalogSearchText.trimmed)\" as a custom pantry item", systemImage: "square.and.pencil")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(PCColors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(PCColors.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { _ in
                    if isCatalogSearchFocused {
                        isCatalogSearchFocused = false
                        hideKeyboard()
                    }
                }
        )
    }

    private func catalogSearchBar(viewModel: PantryViewModel) -> some View {
        AppSearchField(
            "Search the ingredient catalog",
            text: Binding(
                get: { viewModel.bulkAdd.catalogSearchText },
                set: {
                    viewModel.bulkAdd.catalogSearchText = $0
                    viewModel.bulkAdd.onCatalogSearchTextChanged()
                }
            ),
            focus: $isCatalogSearchFocused,
            background: PCColors.cardBackground,
            cornerRadius: 14,
            padding: 12
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
    }

    private func catalogItemRow(item: PantryCatalogItemDefinition, viewModel: PantryViewModel) -> some View {
        let isSelected = viewModel.bulkAdd.isCatalogItemSelected(item)
        let previewDraft = viewModel.bulkAdd.draft(for: item)
        let savedDefault = viewModel.bulkAdd.savedDefault(for: item.id)

        return HStack(spacing: 12) {
            CategoryIcon(category: item.category, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PCColors.textPrimary)
                Text(item.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)

                if let defaultLabel = catalogDefaultLabel(for: previewDraft, savedDefault: savedDefault) {
                    Text(defaultLabel)
                        .font(.caption2)
                        .foregroundStyle(PCColors.info)
                        .lineLimit(1)
                }

                ForEach(catalogFacetOptions(for: item), id: \.self) { facetLine in
                    Text(facetLine)
                        .font(.caption2)
                        .foregroundStyle(PCColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.subheadline)
                Text(isSelected ? "Added" : "Add")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? PCColors.accent : PCColors.fillTertiary)
            .foregroundStyle(isSelected ? Color.white : PCColors.textPrimary)
            .clipShape(Capsule())
        }
        .padding(14)
        .background(isSelected ? PCColors.accent.opacity(0.12) : PCColors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? PCColors.accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture {
            viewModel.bulkAdd.toggleCatalogItemSelection(item)
        }
    }

    private func bulkStagingTab(viewModel: PantryViewModel) -> some View {
        Group {
            if viewModel.bulkAdd.stagedRows.isEmpty {
                EmptyStateView(
                    icon: "square.stack.3d.up.slash",
                    title: "Nothing selected yet",
                    message: "Select items from the catalog, then review and edit them here."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AppList {
                    Section {
                        ForEach(viewModel.bulkAdd.stagedRows) { draft in
                            stagedRowCard(draft: draft, viewModel: viewModel)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .listRowSeparator(.visible)
                        }
                    } header: {
                        SectionHeader(
                            title: "Review Items",
                            subtitle: "\(viewModel.bulkAdd.validRowCount) ready • \(viewModel.bulkAdd.invalidRowCount) need edits"
                        )
                        .padding(.top, 8)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(PCColors.background)
            }
        }
    }

    private func stagedRowCard(draft: PantryIntakeRowDraft, viewModel: PantryViewModel) -> some View {
        Button {
            editingDraft = draft
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    CategoryIcon(category: draft.selectedItem?.category ?? .other, size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.displayName.isEmpty ? "Unresolved item" : draft.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(PCColors.textPrimary)

                        Text(draft.selectedItem?.category.rawValue ?? (draft.isCustomItem ? draft.customCategory.rawValue : "Needs catalog match"))
                            .font(.caption)
                            .foregroundStyle(PCColors.textSecondary)

                        Text(reviewSummary(for: draft))
                            .font(.caption2)
                            .foregroundStyle(PCColors.textSecondary)

                        if let facetSummary = reviewFacetSummary(for: draft) {
                            Text(facetSummary)
                                .font(.caption2)
                                .foregroundStyle(PCColors.textSecondary)
                        }
                    }

                    Spacer()
                    PantryDraftStateBadge(state: draft.rowState)
                }

                if let warning = draft.warnings.first {
                    HStack(spacing: 8) {
                        Image(systemName: warning.severity == .blocking ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(warning.severity == .blocking ? PCColors.expired : PCColors.expiring)
                        Text(warning.message)
                            .font(.caption)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(PCColors.cardBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                viewModel.bulkAdd.removeStagedRow(draft)
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private func reviewDestination(viewModel: PantryViewModel) -> some View {
        bulkStagingTab(viewModel: viewModel)
            .background(PCColors.background)
            .navigationTitle("Review Items")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSaving = true
                            let validRows = viewModel.bulkAdd.stagedRows.filter { $0.rowState == .valid }
                            _ = await viewModel.addStagedItems(validRows)
                            viewModel.bulkAdd.stagedRows.removeAll { $0.rowState == .valid }
                            isSaving = false
                            if viewModel.bulkAdd.stagedRows.isEmpty {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Add to Pantry")
                        }
                    }
                    .disabled(isSaving || viewModel.bulkAdd.validRowCount == 0)
                }
            }
            .safeAreaInset(edge: .bottom) {
                reviewSummaryBar(viewModel: viewModel)
            }
    }

    private func searchSummaryBar(viewModel: PantryViewModel) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.bulkAdd.stagedRows.count) items selected")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                    Text("Review them before adding to your pantry")
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

    private func reviewSummaryBar(viewModel: PantryViewModel) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(viewModel.bulkAdd.stagedRows.count) items selected")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                    Text("\(viewModel.bulkAdd.validRowCount) ready to add now")
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

    private func catalogDefaultLabel(for draft: PantryIntakeRowDraft, savedDefault: PantryItemDefaultPreference?) -> String? {
        let prefix = savedDefault == nil ? "Catalog default" : "Your default"

        if let facetSummary = summaryText(for: draft.selectedFacets) {
            return "\(prefix): \(facetSummary)"
        }

        if savedDefault != nil {
            return "\(prefix): \(draft.displayName)"
        }

        return nil
    }

    private func catalogFacetOptions(for item: PantryCatalogItemDefinition) -> [String] {
        item.facets.map { definition in
            let options = Array(definition.options.prefix(AppConfig.facetOptionsMaxShown)).map(humanizedFacetValue)
            let hiddenCount = max(definition.options.count - options.count, 0)
            let suffix = hiddenCount > 0 ? ", +\(hiddenCount) more" : ""
            return "\(definition.key.title): \(options.joined(separator: ", "))\(suffix)"
        }
    }

    private func summaryText(for facets: [PantryFacetSelection]) -> String? {
        guard !facets.isEmpty else { return nil }
        return facets.map { humanizedFacetValue($0.value) }.joined(separator: " • ")
    }

    private func reviewSummary(for draft: PantryIntakeRowDraft) -> String {
        var parts: [String] = []

        if !draft.quantityText.trimmed.isEmpty {
            let unit = draft.unit ?? draft.selectedItem?.suggestedUnit(for: draft.selectedFacets) ?? .piece
            parts.append("\(draft.quantityText.trimmed) \(unit.rawValue)")
        } else {
            parts.append(PantryQuantityMode.presenceOnly.title)
        }

        if let storage = draft.storage {
            parts.append(storage.rawValue)
        }

        if let expiryDate = draft.resolvedExpiryDate {
            parts.append("Expires \(expiryDate.shortDisplay)")
        }

        if parts.isEmpty {
            return "Open item details to finish its assumptions."
        }

        return parts.joined(separator: " • ")
    }

    private func reviewFacetSummary(for draft: PantryIntakeRowDraft) -> String? {
        guard !draft.selectedFacets.isEmpty else { return nil }
        let values = draft.selectedFacets.map { "\($0.key.title): \(humanizedFacetValue($0.value))" }
        return values.joined(separator: " • ")
    }

    private func humanizedFacetValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
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
        case .valid: return PCColors.accent
        case .invalid: return PCColors.expired
        case .incomplete: return PCColors.expiring
        case .empty: return PCColors.textTertiary
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
                    .background(PCColors.cardBackground)
                    .foregroundStyle(PCColors.textPrimary)
                    .clipShape(Capsule())
            }
        }
    }
}

struct PantryDraftEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PantryIntakeRowDraft
    @State private var savedDefault: PantryItemDefaultPreference?
    private let savedDefaultForItem: (String) -> PantryItemDefaultPreference?
    private let saveDefault: (PantryIntakeRowDraft) -> Void
    private let removeDefault: (String) -> Void
    let onSave: (PantryIntakeRowDraft) -> Void

    init(
        draft: PantryIntakeRowDraft,
        savedDefaultForItem: @escaping (String) -> PantryItemDefaultPreference?,
        saveDefault: @escaping (PantryIntakeRowDraft) -> Void,
        removeDefault: @escaping (String) -> Void,
        onSave: @escaping (PantryIntakeRowDraft) -> Void
    ) {
        _draft = State(initialValue: draft)
        _savedDefault = State(initialValue: draft.selectedItemID.flatMap(savedDefaultForItem))
        self.savedDefaultForItem = savedDefaultForItem
        self.saveDefault = saveDefault
        self.removeDefault = removeDefault
        self.onSave = onSave
    }

    private var showsSavedDefault: Bool {
        savedDefault != nil
    }

    private var isCurrentDefault: Bool {
        draft.matchesDefaultPreference(savedDefault)
    }

    private var saveDefaultButtonTitle: String {
        if isCurrentDefault {
            return "Current Default"
        }
        return showsSavedDefault ? "Update Default" : "Set as Default"
    }

    private func handleSaveDefault() {
        saveDefault(draft)
        savedDefault = PantryItemDefaultPreference(draft: draft)
    }

    private func handleResetDefault() {
        guard let catalogItemID = draft.selectedItemID else { return }
        removeDefault(catalogItemID)
        savedDefault = nil
        draft.resetToCatalogDefaults()
    }

    var body: some View {
        NavigationStack {
            AppForm {
                PantryIntakeFormSections(
                    draft: $draft,
                    accessibilityPrefix: "pantry.bulk.form",
                    allowsIdentityEditing: draft.selectedItemID == nil,
                    hasSavedDefault: showsSavedDefault,
                    saveDefaultButtonTitle: saveDefaultButtonTitle,
                    isSaveDefaultDisabled: draft.rowState != .valid || isCurrentDefault,
                    onSaveDefault: handleSaveDefault,
                    onResetDefault: handleResetDefault
                )
            }
            .navigationTitle("Edit Selected Item")
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
        .onChange(of: draft.selectedItemID) {
            savedDefault = draft.selectedItemID.flatMap(savedDefaultForItem)
        }
    }
}

struct PantryIntakeFormSections: View {
    @Binding var draft: PantryIntakeRowDraft
    let accessibilityPrefix: String
    let allowsIdentityEditing: Bool
    let hasSavedDefault: Bool
    let saveDefaultButtonTitle: String
    let isSaveDefaultDisabled: Bool
    let onSaveDefault: (() -> Void)?
    let onResetDefault: (() -> Void)?

    init(
        draft: Binding<PantryIntakeRowDraft>,
        accessibilityPrefix: String,
        allowsIdentityEditing: Bool = true,
        hasSavedDefault: Bool = false,
        saveDefaultButtonTitle: String = "Set as Default",
        isSaveDefaultDisabled: Bool = false,
        onSaveDefault: (() -> Void)? = nil,
        onResetDefault: (() -> Void)? = nil
    ) {
        self._draft = draft
        self.accessibilityPrefix = accessibilityPrefix
        self.allowsIdentityEditing = allowsIdentityEditing
        self.hasSavedDefault = hasSavedDefault
        self.saveDefaultButtonTitle = saveDefaultButtonTitle
        self.isSaveDefaultDisabled = isSaveDefaultDisabled
        self.onSaveDefault = onSaveDefault
        self.onResetDefault = onResetDefault
    }

    var body: some View {
        Section(draft.isCustomItem ? "Custom Item" : "Catalog Item") {
            if let selectedItem = draft.selectedItem {
                lockedCatalogItemRow(selectedItem)
            } else if allowsIdentityEditing {
                TextField(draft.isCustomItem ? "Custom pantry item" : "Search pantry catalog", text: Binding(
                    get: { draft.searchText },
                    set: { draft.updateSearchText($0) }
                ))
                .appTextEntry(autocapitalization: .words)
                .accessibilityIdentifier("\(accessibilityPrefix).nameField")

                if draft.isCustomItem {
                    Picker("Category", selection: $draft.customCategory) {
                        ForEach(FoodCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }

                    Button("Back to Catalog Search") {
                        draft.disableCustomItemMode()
                    }

                    Text("Custom pantry items are stored without catalog identity and only satisfy identical unresolved recipe ingredients.")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                } else {
                    ForEach(Array(draft.matchingItems.prefix(AppConfig.matchingItemsDropdownMax))) { item in
                        Button {
                            draft.selectItem(item)
                        } label: {
                            HStack(spacing: 10) {
                                CategoryIcon(category: item.category, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .foregroundStyle(PCColors.textPrimary)
                                    Text(item.category.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(PCColors.textSecondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if !draft.searchText.trimmed.isEmpty {
                        Button {
                            draft.enableCustomItemMode()
                        } label: {
                            Label("Add as Custom Pantry Item", systemImage: "square.and.pencil")
                                .foregroundStyle(PCColors.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }

                    if draft.matchingItems.isEmpty && !draft.searchText.trimmed.isEmpty {
                        Text("No exact catalog items match this search. Add it as a custom pantry item if you still want to track it.")
                            .font(.caption)
                            .foregroundStyle(PCColors.textSecondary)
                    }
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
                        .foregroundStyle(PCColors.textSecondary)
                }
            }

            if let summary = draft.freshnessSummaryText() {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)
            }
            if let expiryDate = draft.estimatedExpiryDate {
                Text("Estimated expiry: \(expiryDate.shortDisplay)")
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)
            }
        }

        Section("Quantity (Optional)") {
            HStack {
                TextField("Amount", text: Binding(
                    get: { draft.quantityText },
                    set: { draft.setQuantityText($0) }
                ))
                .keyboardType(.decimalPad)
                .appTextEntry()
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
                    .foregroundStyle(PCColors.expired)
            } else {
                Text("Leave this blank to track the item by presence only. Enter an amount only when you want exact shortage detection.")
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)
            }
        }

        Section("Notes") {
            TextField("Optional notes", text: $draft.notes, axis: .vertical)
                .lineLimit(3)
                .appTextEntry()
                .accessibilityIdentifier("\(accessibilityPrefix).notesField")
        }

        if draft.selectedItem != nil && (onSaveDefault != nil || (hasSavedDefault && onResetDefault != nil)) {
            Section {
                if let onSaveDefault {
                    Button(saveDefaultButtonTitle) {
                        onSaveDefault()
                    }
                    .disabled(isSaveDefaultDisabled)
                }

                if hasSavedDefault, let onResetDefault {
                    Button("Reset to Catalog Default") {
                        onResetDefault()
                    }
                }
            } header: {
                Text("Defaults")
            } footer: {
                Text("These defaults will be reused the next time you add this catalog item.")
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)
            }
        }

        if !draft.warnings.isEmpty {
            Section("Review") {
                ForEach(draft.warnings) { warning in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: warningIcon(for: warning.severity))
                            .foregroundStyle(warningColor(for: warning.severity))
                        Text(warning.message)
                            .font(.caption)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lockedCatalogItemRow(_ selectedItem: PantryCatalogItemDefinition) -> some View {
        HStack(spacing: 12) {
            CategoryIcon(category: selectedItem.category, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedItem.displayName(for: draft.selectedFacets))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(selectedItem.category.rawValue)
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)
            }
            Spacer()
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
        case .blocking: return PCColors.expired
        case .warning: return PCColors.expiring
        case .informational: return PCColors.info
        }
    }
}
