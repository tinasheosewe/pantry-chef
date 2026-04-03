import SwiftUI

struct CustomIngredientDefinitionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomIngredientDraft
    @State private var isAutoFilling = false
    @State private var autoFillError: String?
    @State private var registrationError: String?
    @State private var newOptionText: [PantryFacetKey: String] = [:]
    @State private var editingOptions: [PantryFacetKey: [String]] = [:]
    @FocusState private var focusedOption: FacetOptionFocus?
    @State private var showingAddFacetPicker = false
    @State private var showDeleteConfirmation = false
    @State private var showResetConfirmation = false
    @State private var foldCandidate: FoldCandidate?
    @State private var showFoldAlert = false

    private struct FacetOptionFocus: Hashable {
        let key: PantryFacetKey
        let index: Int // -1 = the trailing "add" row
    }

    private struct FoldCandidate {
        let baseItem: PantryCatalogItemDefinition
        let mergeResult: AIService.IngredientMergeResult
    }

    private let appState: AppState
    private let existingItemID: String?
    private let onSave: ((String) -> Void)?

    /// Create a new custom ingredient.
    init(name: String, appState: AppState, onSave: ((String) -> Void)? = nil) {
        self.appState = appState
        self.existingItemID = nil
        self.onSave = onSave
        _draft = State(initialValue: CustomIngredientDraft(name: name))
    }

    /// Edit an existing custom ingredient.
    init(itemID: String, appState: AppState, onSave: ((String) -> Void)? = nil) {
        self.appState = appState
        self.existingItemID = itemID
        self.onSave = onSave
        if let item = PantryCatalog.item(id: itemID) {
            var d = CustomIngredientDraft(name: item.name)
            d.category = item.category
            d.defaultStorage = item.defaultStorage
            d.defaultUnit = item.defaultUnit
            for facet in item.facets {
                d.facets[facet.key] = facet.options
            }
            for selection in item.defaultSelections {
                d.defaultSelections[selection.key] = selection.value
            }
            _draft = State(initialValue: d)
        } else {
            _draft = State(initialValue: CustomIngredientDraft(name: ""))
        }
    }

    private var isEditing: Bool { existingItemID != nil }

    private var isUserDefinedItem: Bool {
        guard let id = existingItemID else { return false }
        return PantryCatalog.item(id: id)?.isUserDefined == true
    }

    private var isCatalogItem: Bool {
        isEditing && !isUserDefinedItem
    }

    private var canSave: Bool {
        !draft.name.trimmed.isEmpty && !isAutoFilling
    }

    var body: some View {
        NavigationStack {
            AppForm {
                nameAndCategorySection
                autoFillSection
                facetsSections
                addFacetSection
                storageAndUnitSection

                if isEditing && isUserDefinedItem {
                    deleteSection
                } else if isCatalogItem {
                    resetSection
                }
            }
            .onAppear {
                guard editingOptions.isEmpty else { return }
                refreshEditingOptions()
            }
            .navigationTitle(isEditing ? "Edit Ingredient" : "New Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .disabled(isAutoFilling)
            .overlay {
                if isAutoFilling {
                    autoFillOverlay
                }
            }
            .confirmationDialog(
                "Delete Ingredient",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteIngredient() }
            } message: {
                Text("This will permanently remove \"\(draft.name)\" from your catalog. Existing pantry items using this ingredient will become unresolved.")
            }
            .confirmationDialog(
                "Reset to Defaults",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) { resetCatalogItem() }
            } message: {
                Text("This will remove all custom facet values and aliases added to this ingredient, restoring the original catalog definition.")
            }
            .alert(
                "Existing Ingredient Found",
                isPresented: $showFoldAlert
            ) {
                Button("Fold In") { applyFold() }
                Button("Keep as New", role: .cancel) { foldCandidate = nil }
            } message: {
                if let candidate = foldCandidate {
                    Text("\"\(draft.name)\" looks like it belongs under \"\(candidate.baseItem.titleCasedName)\". Fold it in to enrich the existing item?")
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    @ViewBuilder
    private var nameAndCategorySection: some View {
        Section {
            if isCatalogItem {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(draft.titleCasedName)
                        .pcFormValueStyle(.readOnly)
                }
            } else {
                TextField("Ingredient name", text: $draft.name)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .pcFormValueStyle(.editable)
            }

            Picker("Category", selection: $draft.category) {
                ForEach(FoodCategory.allCases) { cat in
                    Text(cat.rawValue).tag(cat)
                }
            }
            .pcFormValueStyle(isEditable: !isCatalogItem)
            .disabled(isCatalogItem)
        } header: {
            Text("Ingredient")
        } footer: {
            if let warning = draft.nameCollisionWarning, !isEditing {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(PCColors.expiring)
            }
            if let error = registrationError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(PCColors.expired)
            }
        }
    }

    @ViewBuilder
    private var autoFillSection: some View {
        if !isEditing {
            Section {
                Button {
                    autoFill()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Auto-fill with AI")
                        Spacer()
                        if isAutoFilling {
                            ProgressView()
                        }
                    }
                }
                .disabled(draft.name.trimmed.isEmpty || isAutoFilling)
            } footer: {
                if let error = autoFillError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(PCColors.expired)
                } else {
                    Text("Generates category, storage, unit, and facet definitions based on the ingredient name.")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var facetsSections: some View {
        ForEach(draft.sortedFacetKeys) { key in
            let options = editingOptions[key] ?? []
            let baseOpts = baseOptionSet(for: key)
            Section {
                ForEach(options.indices, id: \.self) { idx in
                    let isBase = isCatalogItem && baseOpts.contains(options[idx].lowercased())
                    HStack {
                        if isBase {
                            Text(options[idx])
                                .pcFormValueStyle(.readOnly)
                        } else {
                            TextField(key.title.lowercased(), text: facetOptionBinding(key: key, index: idx))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.words)
                                .pcFormValueStyle(.editable)
                                .focused($focusedOption, equals: FacetOptionFocus(key: key, index: idx))
                            Button {
                                withAnimation {
                                    removeEditingOption(key: key, index: idx)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(PCColors.textSecondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Trailing "add" row
                TextField("Add \(key.title.lowercased())...", text: bindingForNewOption(key))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .pcFormValueStyle(.editable)
                    .focused($focusedOption, equals: FacetOptionFocus(key: key, index: -1))
            } header: {
                HStack {
                    Text(key.title)
                    Spacer()
                    if !isCatalogItem || !isBaseFacetKey(key) {
                        Button {
                            withAnimation {
                                draft.removeFacet(key)
                                editingOptions.removeValue(forKey: key)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.7))
                        }
                    }
                }
            }
        }
        .onChange(of: focusedOption) { oldFocus, _ in
            guard let old = oldFocus else { return }
            // Commit trailing add-row text into the options list
            if old.index == -1 {
                let text = (newOptionText[old.key] ?? "").trimmed
                if !text.isEmpty {
                    ensureEditingOptions(old.key)
                    editingOptions[old.key]?.append(text)
                    newOptionText[old.key] = ""
                }
            } else {
                // Remove row if user cleared it and moved away (skip base options)
                if let opts = editingOptions[old.key], old.index < opts.count {
                    let isBase = isCatalogItem && baseOptionSet(for: old.key).contains(opts[old.index].lowercased())
                    if opts[old.index].trimmed.isEmpty && !isBase {
                        withAnimation {
                            removeEditingOption(key: old.key, index: old.index)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var addFacetSection: some View {
        if !draft.unusedFacetKeys.isEmpty {
            Section {
                DisclosureGroup("Add Facet") {
                    ForEach(draft.unusedFacetKeys) { key in
                        Button {
                            withAnimation {
                                draft.facets[key] = []
                            }
                        } label: {
                            Label(key.title, systemImage: "plus.circle")
                                .foregroundStyle(PCColors.textPrimary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var storageAndUnitSection: some View {
        Section("Defaults") {
            Picker("Default Storage", selection: $draft.defaultStorage) {
                ForEach(PantryStorage.allCases) { storage in
                    Label(storage.rawValue, systemImage: storage.icon).tag(storage)
                }
            }
            .pcFormValueStyle(.editable)

            Picker("Default Unit", selection: Binding(
                get: { draft.defaultUnit ?? .piece },
                set: { draft.defaultUnit = $0 }
            )) {
                ForEach(MeasurementUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pcFormValueStyle(.editable)

            ForEach(draft.sortedFacetKeys) { key in
                let options = editingOptions[key] ?? []
                if !options.isEmpty {
                    Picker("Default \(key.title)", selection: facetDefaultBinding(key)) {
                        Text("None").tag("" as String)
                        ForEach(options, id: \.self) { option in
                            Text(CustomIngredientDraft.titleCase(option)).tag(option.lowercased())
                        }
                    }
                    .pcFormValueStyle(.editable)
                }
            }
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label("Delete Ingredient", systemImage: "trash")
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        if let itemID = existingItemID,
           PantryCatalog.facetExtensions[itemID] != nil || PantryCatalog.aliasExtensions[itemID] != nil || PantryCatalog.defaultOverrides[itemID] != nil {
            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        Spacer()
                    }
                }
            }
        }
    }

    private var autoFillOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Generating definition...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(PCColors.textPrimary)
                Text("This may take a few seconds")
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Actions

    private func autoFill() {
        autoFillError = nil
        isAutoFilling = true
        Task {
            let trimmedName = draft.name.trimmed
            if let definition = await appState.generateIngredientDefinition(name: trimmedName) {
                draft.applyAIDefinition(definition)
                refreshEditingOptions()

                // Check for fold-into-existing candidate
                if !isEditing {
                    await checkFoldCandidate(name: trimmedName)
                }
            } else {
                autoFillError = "Could not generate definition. You can fill in the fields manually."
            }
            isAutoFilling = false
        }
    }

    private func checkFoldCandidate(name: String) async {
        // Local match: check top search result
        let results = CatalogSearchEngine.search(name)
        guard let topResult = results.first,
              topResult.score >= 0.5,
              !topResult.item.isUserDefined else { return }

        let baseItem = topResult.item

        // LLM verify + merge
        guard let mergeResult = await appState.verifyAndMergeIngredient(
            name: name,
            baseItem: baseItem
        ), mergeResult.shouldMerge else { return }

        foldCandidate = FoldCandidate(baseItem: baseItem, mergeResult: mergeResult)
        showFoldAlert = true
    }

    private func applyFold() {
        guard let candidate = foldCandidate else { return }
        PantryCatalog.applyMerge(
            catalogItemID: candidate.baseItem.id,
            mergedFacets: candidate.mergeResult.mergedFacets,
            mergedAliases: candidate.mergeResult.mergedAliases
        )
        dismiss()
    }

    private func save() {
        syncAllEditingOptionsToDraft()
        registrationError = nil

        if isCatalogItem, let existingID = existingItemID {
            // Catalog item: compute diff and apply as extensions
            saveCatalogExtensions(existingID: existingID)
        } else if isEditing, let existingID = existingItemID {
            // User-defined item: remove old, register updated
            PantryCatalog.removeUserItem(id: existingID)
            let definition = draft.buildDefinition()
            let result = PantryCatalog.registerUserItem(definition)
            switch result {
            case .success:
                onSave?(definition.id)
                dismiss()
            case .failure(let error):
                registrationError = error.localizedDescription
            }
        } else {
            // New item
            let definition = draft.buildDefinition()
            let result = PantryCatalog.registerUserItem(definition)
            switch result {
            case .success:
                onSave?(definition.id)
                dismiss()
            case .failure(let error):
                registrationError = error.localizedDescription
            }
        }
    }

    private func saveCatalogExtensions(existingID: String) {
        guard let baseItem = PantryCatalog.bundleItem(id: existingID) else { return }

        // Compute facet diff against the unextended base item
        var extensions: [String: [String]] = [:]
        for (key, draftOptions) in draft.facets {
            let baseOptions = Set(baseItem.options(for: key).map { $0.lowercased() })
            let extensionOptions = draftOptions.filter { !baseOptions.contains($0.lowercased()) }
            if !extensionOptions.isEmpty {
                extensions[key.rawValue] = extensionOptions
            }
        }

        PantryCatalog.setFacetExtensions(catalogItemID: existingID, extensions: extensions)

        // Compute default overrides against the base item
        var overrides: [String: String] = [:]
        if draft.defaultStorage != baseItem.defaultStorage {
            overrides["defaultStorage"] = draft.defaultStorage.rawValue
        }
        if draft.defaultUnit != baseItem.defaultUnit {
            overrides["defaultUnit"] = (draft.defaultUnit ?? .piece).rawValue
        }
        // Facet default selections
        let baseDefaults = Dictionary(baseItem.defaultSelections.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        for (key, value) in draft.defaultSelections {
            if baseDefaults[key] != value {
                overrides["facet.\(key.rawValue)"] = value
            }
        }
        // If a base default was removed (set to "None"), store empty string to indicate removal
        for (key, _) in baseDefaults {
            if draft.defaultSelections[key] == nil {
                overrides["facet.\(key.rawValue)"] = ""
            }
        }
        PantryCatalog.setDefaultOverrides(catalogItemID: existingID, overrides: overrides)

        onSave?(existingID)
        dismiss()
    }

    private func resetCatalogItem() {
        guard let existingID = existingItemID else { return }
        PantryCatalog.resetExtensions(catalogItemID: existingID)
        dismiss()
    }

    private func deleteIngredient() {
        guard let existingID = existingItemID else { return }
        PantryCatalog.removeUserItem(id: existingID)
        dismiss()
    }

    private func bindingForNewOption(_ key: PantryFacetKey) -> Binding<String> {
        Binding(
            get: { newOptionText[key] ?? "" },
            set: { newOptionText[key] = $0 }
        )
    }

    private func facetDefaultBinding(_ key: PantryFacetKey) -> Binding<String> {
        Binding(
            get: { draft.defaultSelections[key] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    draft.defaultSelections.removeValue(forKey: key)
                } else {
                    draft.defaultSelections[key] = newValue
                }
            }
        )
    }

    /// Single source of truth: copies draft.facets → editingOptions with titlecasing.
    private func refreshEditingOptions() {
        for (key, values) in draft.facets {
            editingOptions[key] = values.map { CustomIngredientDraft.titleCase($0) }
        }
    }

    private func ensureEditingOptions(_ key: PantryFacetKey) {
        if editingOptions[key] == nil {
            editingOptions[key] = (draft.facets[key] ?? []).map { CustomIngredientDraft.titleCase($0) }
        }
    }

    /// Returns the set of base (bundle) facet options for a key, lowercased.
    private func baseOptionSet(for key: PantryFacetKey) -> Set<String> {
        guard isCatalogItem, let itemID = existingItemID,
              let baseItem = PantryCatalog.bundleItem(id: itemID) else { return [] }
        return Set(baseItem.options(for: key).map { $0.lowercased() })
    }

    /// Whether this facet key exists in the original bundle item.
    private func isBaseFacetKey(_ key: PantryFacetKey) -> Bool {
        guard isCatalogItem, let itemID = existingItemID,
              let baseItem = PantryCatalog.bundleItem(id: itemID) else { return false }
        return baseItem.facets.contains { $0.key == key }
    }

    private func facetOptionBinding(key: PantryFacetKey, index: Int) -> Binding<String> {
        Binding(
            get: {
                ensureEditingOptions(key)
                let opts = editingOptions[key] ?? []
                guard index < opts.count else { return "" }
                return opts[index]
            },
            set: { newValue in
                ensureEditingOptions(key)
                guard index < (editingOptions[key]?.count ?? 0) else { return }
                editingOptions[key]?[index] = newValue
            }
        )
    }

    private func removeEditingOption(key: PantryFacetKey, index: Int) {
        ensureEditingOptions(key)
        guard index < (editingOptions[key]?.count ?? 0) else { return }
        editingOptions[key]?.remove(at: index)
        syncEditingOptionsToDraft(key: key)
    }

    private func syncEditingOptionsToDraft(key: PantryFacetKey) {
        let current = editingOptions[key] ?? []
        // Rebuild: remove all then re-add (store lowercase)
        draft.facets[key] = nil
        for opt in current where !opt.trimmed.isEmpty {
            draft.addFacetOption(key, value: opt.trimmed.lowercased())
        }
    }

    private func syncAllEditingOptionsToDraft() {
        for key in editingOptions.keys {
            syncEditingOptionsToDraft(key: key)
        }
        // Also commit any trailing add-row text
        for (key, text) in newOptionText {
            let trimmed = text.trimmed
            if !trimmed.isEmpty {
                draft.addFacetOption(key, value: trimmed.lowercased())
                newOptionText[key] = ""
            }
        }
    }
}
