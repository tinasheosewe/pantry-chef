import SwiftUI

struct CustomIngredientDefinitionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomIngredientDraft
    @State private var editingAliases: [String]
    @State private var newAliasText = ""
    @State private var isAutoFilling = false
    @State private var isResolvingFold = false
    @State private var autoFillError: String?
    @State private var registrationError: String?
    @State private var newOptionText: [PantryFacetKey: String] = [:]
    @State private var editingOptions: [PantryFacetKey: [String]] = [:]
    @FocusState private var focusedField: EditableFieldFocus?
    @State private var activeAlert: ActiveAlert?
    @State private var foldReviewTarget: FoldReviewTarget?
    @State private var shouldDismissAfterFoldReview = false
    @State private var hasRejectedFoldSuggestion = false

    private enum EditableFieldFocus: Hashable {
        case facetOption(PantryFacetKey, Int)
        case addAlias
        case alias(Int)
    }

    private struct FoldCandidate {
        let baseItem: PantryCatalogItemDefinition
        let mergeResult: AIService.IngredientMergeResult
    }

    private enum FoldPromptOrigin: String {
        case autoFill
        case save
    }

    private enum ActiveAlert: Identifiable {
        case delete
        case reset
        case fold(FoldCandidate, FoldPromptOrigin)

        var id: String {
            switch self {
            case .delete:
                return "delete"
            case .reset:
                return "reset"
            case .fold(let candidate, let origin):
                return "fold-\(origin.rawValue)-\(candidate.baseItem.id)"
            }
        }
    }

    private struct FoldReviewTarget: Identifiable {
        let candidate: FoldCandidate

        var id: String {
            candidate.baseItem.id
        }
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
        _editingAliases = State(initialValue: [])
    }

    /// Edit an existing custom ingredient.
    init(
        itemID: String,
        appState: AppState,
        mergeResult: AIService.IngredientMergeResult? = nil,
        onSave: ((String) -> Void)? = nil
    ) {
        self.appState = appState
        self.existingItemID = itemID
        self.onSave = onSave
        if let item = PantryCatalog.item(id: itemID) {
            _draft = State(initialValue: Self.catalogDraft(item: item, mergeResult: mergeResult))
            _editingAliases = State(initialValue: Self.catalogAliases(item: item, mergeResult: mergeResult))
        } else {
            _draft = State(initialValue: CustomIngredientDraft(name: ""))
            _editingAliases = State(initialValue: [])
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

    private var isBusy: Bool {
        isAutoFilling || isResolvingFold
    }

    private var canSave: Bool {
        !draft.name.trimmed.isEmpty && !isBusy
    }

    private var currentCatalogItem: PantryCatalogItemDefinition? {
        guard isCatalogItem, let existingItemID else { return nil }
        return PantryCatalog.item(id: existingItemID)
    }

    private var baseCatalogItem: PantryCatalogItemDefinition? {
        guard isCatalogItem, let existingItemID else { return nil }
        return PantryCatalog.bundleItem(id: existingItemID)
    }

    private var hasCatalogModifications: Bool {
        guard let existingItemID else { return false }
        return PantryCatalog.hasUserModifications(catalogItemID: existingItemID)
    }

    private var hasLocalCatalogEdits: Bool {
        guard let currentItem = currentCatalogItem else { return false }

        if draft.defaultStorage != currentItem.defaultStorage {
            return true
        }

        if draft.defaultUnit != currentItem.defaultUnit {
            return true
        }

        let currentFacetKeys = Set(currentItem.facets.map(\.key))
        let localFacetKeys = Set((editingOptions.isEmpty ? draft.facets : editingOptions).keys)
        if localFacetKeys != currentFacetKeys {
            return true
        }

        for facet in currentItem.facets {
            if currentFacetOptions(for: facet.key) != facet.options.map(CustomIngredientDraft.titleCase) {
                return true
            }
        }

        let persistedAliases = (existingItemID.flatMap { PantryCatalog.aliasExtensions[$0] } ?? []).map(\.trimmed)
        let localAliases = editingAliases.map(\.trimmed)
        if localAliases != persistedAliases {
            return true
        }

        if !newAliasText.trimmed.isEmpty {
            return true
        }

        if newOptionText.values.contains(where: { !$0.trimmed.isEmpty }) {
            return true
        }

        return false
    }

    private var canResetCatalogItem: Bool {
        hasCatalogModifications || hasLocalCatalogEdits
    }

    private var baseAliases: [String] {
        guard isCatalogItem, let existingItemID else { return [] }
        return PantryCatalog.bundleItem(id: existingItemID)?.aliases ?? []
    }

    private var baseAliasLookupKeys: Set<String> {
        Set(baseAliases.map(PantryCatalog.normalizeLookupKey))
    }

    private var overlayTitle: String {
        isResolvingFold ? "Checking for an existing ingredient..." : "Generating definition..."
    }

    private var overlaySubtitle: String {
        isResolvingFold ? "This may take a few seconds" : "This may take a few seconds"
    }

    private var managementActions: [AppFormActionSection.Action] {
        if isUserDefinedItem {
            return [
                AppFormActionSection.Action(
                    title: "Delete Ingredient",
                    systemImage: "trash",
                    role: .destructive,
                    isCentered: true,
                    handler: { activeAlert = .delete }
                )
            ]
        }

        if isCatalogItem {
            return [
                AppFormActionSection.Action(
                    title: "Reset to Defaults",
                    systemImage: "arrow.counterclockwise",
                    foregroundColor: PCColors.expired,
                    isDisabled: !canResetCatalogItem,
                    isCentered: true,
                    handler: { activeAlert = .reset }
                )
            ]
        }

        return []
    }

    var body: some View {
        NavigationStack {
            AppForm {
                nameAndCategorySection
                autoFillSection
                facetsSections
                addFacetSection
                aliasesSection
                storageAndUnitSection

                if !managementActions.isEmpty {
                    AppFormActionSection(actions: managementActions)
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
            .disabled(isBusy)
            .overlay {
                if isBusy {
                    autoFillOverlay
                }
            }
            .alert(item: $activeAlert, content: alert)
            .sheet(item: $foldReviewTarget, onDismiss: handleFoldReviewDismissal) { target in
                CustomIngredientDefinitionView(
                    itemID: target.candidate.baseItem.id,
                    appState: appState,
                    mergeResult: target.candidate.mergeResult
                ) { savedItemID in
                    shouldDismissAfterFoldReview = true
                    onSave?(savedItemID)
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
                                .focused($focusedField, equals: .facetOption(key, idx))
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
                    .focused($focusedField, equals: .facetOption(key, -1))
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
        .onChange(of: focusedField) { oldFocus, _ in
            handleFocusDeparture(oldFocus)
        }
    }

    @ViewBuilder
    private var addFacetSection: some View {
        if !isCatalogItem && !draft.unusedFacetKeys.isEmpty {
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
    private var aliasesSection: some View {
        if isCatalogItem {
            Section {
                ForEach(baseAliases, id: \.self) { alias in
                    Text(CustomIngredientDraft.titleCase(alias))
                        .pcFormValueStyle(.readOnly)
                }

                ForEach(editingAliases.indices, id: \.self) { index in
                    HStack {
                        TextField("Alias", text: aliasBinding(index: index))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .pcFormValueStyle(.editable)
                            .focused($focusedField, equals: .alias(index))
                        Button {
                            removeEditingAlias(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(PCColors.textSecondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("Add alias...", text: $newAliasText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .pcFormValueStyle(.editable)
                    .focused($focusedField, equals: .addAlias)
            } header: {
                Text("Aliases")
            } footer: {
                Text("Alternate names help search surface this ingredient without changing its base display name.")
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)
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

            if !isCatalogItem {
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
    }

    private var autoFillOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(overlayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(PCColors.textPrimary)
                Text(overlaySubtitle)
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
        hasRejectedFoldSuggestion = false
        isAutoFilling = true
        Task { @MainActor in
            let trimmedName = draft.name.trimmed
            if let definition = await appState.generateIngredientDefinition(name: trimmedName) {
                draft.applyAIDefinition(definition)
                refreshEditingOptions()

                // Check for fold-into-existing candidate
                if !isEditing {
                    if let candidate = await resolveFoldCandidate(for: draft) {
                        activeAlert = .fold(candidate, .autoFill)
                    }
                }
            } else {
                autoFillError = "Could not generate definition. You can fill in the fields manually."
            }
            isAutoFilling = false
        }
    }

    private func resolveFoldCandidate(for draft: CustomIngredientDraft) async -> FoldCandidate? {
        let trimmedName = draft.name.trimmed
        guard !trimmedName.isEmpty else { return nil }

        let candidates = CatalogSearchEngine.collisionCandidates(
            name: trimmedName,
            category: draft.category,
            facets: draft.facets
        )

        for candidate in candidates where !candidate.item.isUserDefined {
            guard let mergeResult = await appState.verifyAndMergeIngredient(
                name: trimmedName,
                baseItem: candidate.item,
                generatedCategory: draft.category,
                generatedFacets: draft.facets
            ), mergeResult.shouldMerge else {
                continue
            }

            return FoldCandidate(baseItem: candidate.item, mergeResult: mergeResult)
        }

        return nil
    }

    private func save() {
        syncAllEditingOptionsToDraft()
        syncEditingAliases()
        registrationError = nil

        if !isEditing && !hasRejectedFoldSuggestion {
            guard !draft.name.trimmed.isEmpty else { return }

            isResolvingFold = true
            Task { @MainActor in
                let candidate = await resolveFoldCandidate(for: draft)
                isResolvingFold = false

                if let candidate {
                    activeAlert = .fold(candidate, .save)
                } else {
                    commitSave()
                }
            }
            return
        }

        commitSave()
    }

    private func commitSave() {
        registrationError = nil

        if isCatalogItem, let existingID = existingItemID {
            saveCatalogExtensions(existingID: existingID)
        } else if isEditing, let existingID = existingItemID {
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
        for facet in baseItem.facets {
            let key = facet.key
            let draftOptions = draft.facets[key] ?? []
            let baseOptions = Set(facet.options.map { $0.lowercased() })
            let extensionOptions = draftOptions.filter { !baseOptions.contains($0.lowercased()) }
            if !extensionOptions.isEmpty {
                extensions[key.rawValue] = extensionOptions
            }
        }

        PantryCatalog.setFacetExtensions(catalogItemID: existingID, extensions: extensions)
        PantryCatalog.setAliasExtensions(
            catalogItemID: existingID,
            aliases: editingAliases.filter { !baseAliasLookupKeys.contains(PantryCatalog.normalizeLookupKey($0)) }
        )

        // Compute default overrides against the base item
        var overrides: [String: String] = [:]
        if draft.defaultStorage != baseItem.defaultStorage {
            overrides["defaultStorage"] = draft.defaultStorage.rawValue
        }
        if draft.defaultUnit != baseItem.defaultUnit {
            overrides["defaultUnit"] = (draft.defaultUnit ?? .piece).rawValue
        }
        PantryCatalog.setDefaultOverrides(catalogItemID: existingID, overrides: overrides)

        onSave?(existingID)
        dismiss()
    }

    private func resetCatalogItem() {
        guard let existingID = existingItemID,
              let baseItem = baseCatalogItem else { return }
        PantryCatalog.resetExtensions(catalogItemID: existingID)
        restoreCatalogEditor(to: baseItem)
    }

    private func deleteIngredient() {
        guard let existingID = existingItemID else { return }
        Task { @MainActor in
            await appState.removePantryItems(catalogItemID: existingID)
            appState.removePantryItemDefaultPreference(for: existingID)
            PantryCatalog.removeUserItem(id: existingID)
            dismiss()
        }
    }

    private func beginFoldReview(_ candidate: FoldCandidate) {
        shouldDismissAfterFoldReview = false
        foldReviewTarget = FoldReviewTarget(candidate: candidate)
    }

    private func rejectFoldSuggestion(origin: FoldPromptOrigin) {
        hasRejectedFoldSuggestion = true
        if origin == .save {
            commitSave()
        }
    }

    private func handleFoldReviewDismissal() {
        if shouldDismissAfterFoldReview {
            dismiss()
        }
    }

    private func alert(for activeAlert: ActiveAlert) -> Alert {
        switch activeAlert {
        case .delete:
            return Alert(
                title: Text("Delete Ingredient"),
                message: Text("This will permanently remove \"\(draft.name)\" from your catalog and remove any matching items from your pantry."),
                primaryButton: .destructive(Text("Delete"), action: deleteIngredient),
                secondaryButton: .cancel()
            )
        case .reset:
            return Alert(
                title: Text("Reset to Defaults"),
                message: Text("This will discard any local edits and clear saved facet values, aliases, and storage or unit overrides for this ingredient."),
                primaryButton: .destructive(Text("Reset"), action: resetCatalogItem),
                secondaryButton: .cancel()
            )
        case .fold(let candidate, let origin):
            return Alert(
                title: Text("Existing Ingredient Found"),
                message: Text("\"\(draft.name)\" looks like it belongs under \"\(candidate.baseItem.titleCasedName)\". Review the merged item before saving it?"),
                primaryButton: .default(Text("Review Fold"), action: {
                    beginFoldReview(candidate)
                }),
                secondaryButton: .cancel(Text("Keep as New"), action: {
                    rejectFoldSuggestion(origin: origin)
                })
            )
        }
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

    private func handleFocusDeparture(_ previousFocus: EditableFieldFocus?) {
        guard let previousFocus else { return }

        switch previousFocus {
        case .facetOption(let key, let index):
            if index == -1 {
                let text = (newOptionText[key] ?? "").trimmed
                if !text.isEmpty {
                    withAnimation {
                        ensureEditingOptions(key)
                        editingOptions[key]?.append(text)
                        newOptionText[key] = ""
                    }
                }
                return
            }

            if let opts = editingOptions[key], index < opts.count {
                let isBase = isCatalogItem && baseOptionSet(for: key).contains(opts[index].lowercased())
                if opts[index].trimmed.isEmpty && !isBase {
                    withAnimation {
                        removeEditingOption(key: key, index: index)
                    }
                }
            }
        case .addAlias:
            if !newAliasText.trimmed.isEmpty {
                withAnimation {
                    addPendingAlias()
                }
            }
        case .alias(let index):
            if index < editingAliases.count, editingAliases[index].trimmed.isEmpty {
                withAnimation {
                    removeEditingAlias(at: index)
                }
            }
        }
    }

    private func aliasBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                guard index < editingAliases.count else { return "" }
                return editingAliases[index]
            },
            set: { newValue in
                guard index < editingAliases.count else { return }
                editingAliases[index] = newValue
            }
        )
    }

    private func removeEditingAlias(at index: Int) {
        guard index < editingAliases.count else { return }
        editingAliases.remove(at: index)
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

    private func currentFacetOptions(for key: PantryFacetKey) -> [String] {
        if let options = editingOptions[key] {
            return options
        }

        return (draft.facets[key] ?? []).map(CustomIngredientDraft.titleCase)
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

    private func addPendingAlias() {
        let trimmed = newAliasText.trimmed
        guard !trimmed.isEmpty else { return }

        let normalized = PantryCatalog.normalizeLookupKey(trimmed)
        guard !baseAliasLookupKeys.contains(normalized) else {
            newAliasText = ""
            return
        }

        let existing = Set(editingAliases.map(PantryCatalog.normalizeLookupKey))
        guard !existing.contains(normalized) else {
            newAliasText = ""
            return
        }

        editingAliases.append(trimmed)
        newAliasText = ""
    }

    private func syncEditingAliases() {
        addPendingAlias()

        var seen = baseAliasLookupKeys
        var cleaned: [String] = []

        for alias in editingAliases {
            let trimmed = alias.trimmed
            guard !trimmed.isEmpty else { continue }
            let normalized = PantryCatalog.normalizeLookupKey(trimmed)
            guard seen.insert(normalized).inserted else { continue }
            cleaned.append(trimmed)
        }

        editingAliases = cleaned
    }

    private func restoreCatalogEditor(to item: PantryCatalogItemDefinition) {
        draft = Self.catalogDraft(item: item)
        editingAliases = []
        newAliasText = ""
        newOptionText = [:]
        editingOptions = [:]
        registrationError = nil
        focusedField = nil
        refreshEditingOptions()
    }

    private static func catalogDraft(
        item: PantryCatalogItemDefinition,
        mergeResult: AIService.IngredientMergeResult? = nil
    ) -> CustomIngredientDraft {
        var draft = CustomIngredientDraft(name: item.name)
        draft.category = item.category
        draft.defaultStorage = item.defaultStorage
        draft.defaultUnit = item.defaultUnit

        for facet in item.facets {
            draft.facets[facet.key] = facet.options
        }

        for selection in item.defaultSelections {
            draft.defaultSelections[selection.key] = selection.value
        }

        if let mergeResult {
            for (key, options) in mergeResult.mergedFacets where item.supports(key) {
                for option in options {
                    draft.addFacetOption(key, value: option)
                }
            }
        }

        return draft
    }

    private static func catalogAliases(
        item: PantryCatalogItemDefinition,
        mergeResult: AIService.IngredientMergeResult? = nil
    ) -> [String] {
        let existingAliases = PantryCatalog.aliasExtensions[item.id] ?? []
        return mergedAliasExtensions(
            baseAliases: item.aliases,
            existingAliases: existingAliases,
            proposedAliases: mergeResult?.mergedAliases ?? []
        )
    }

    private static func mergedAliasExtensions(
        baseAliases: [String],
        existingAliases: [String],
        proposedAliases: [String]
    ) -> [String] {
        let baseAliasKeys = Set(baseAliases.map(PantryCatalog.normalizeLookupKey))
        var seen = baseAliasKeys
        var merged: [String] = []

        for alias in existingAliases + proposedAliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = PantryCatalog.normalizeLookupKey(trimmed)
            guard seen.insert(normalized).inserted else { continue }
            merged.append(trimmed)
        }

        return merged
    }
}
