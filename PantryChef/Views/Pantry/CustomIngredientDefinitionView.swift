import SwiftUI

struct CustomIngredientDefinitionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomIngredientDraft
    @State private var isAutoFilling = false
    @State private var autoFillError: String?
    @State private var registrationError: String?
    @State private var newOptionText: [PantryFacetKey: String] = [:]
    @State private var showingAddFacetPicker = false
    @State private var showDeleteConfirmation = false

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
            _draft = State(initialValue: d)
        } else {
            _draft = State(initialValue: CustomIngredientDraft(name: ""))
        }
    }

    private var isEditing: Bool { existingItemID != nil }

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

                if isEditing {
                    deleteSection
                }
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
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    @ViewBuilder
    private var nameAndCategorySection: some View {
        Section {
            TextField("Ingredient name", text: $draft.name)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)

            Picker("Category", selection: $draft.category) {
                ForEach(FoodCategory.allCases) { cat in
                    Text(cat.rawValue).tag(cat)
                }
            }
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
            Section {
                ForEach(draft.facets[key] ?? [], id: \.self) { option in
                    Text(option.capitalized)
                }
                .onDelete { offsets in
                    deleteFacetOptions(key: key, at: offsets)
                }

                HStack {
                    TextField("Add \(key.title.lowercased())...", text: bindingForNewOption(key))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .onSubmit { commitNewOption(key) }

                    Button {
                        commitNewOption(key)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(PCColors.accent)
                    }
                    .disabled((newOptionText[key] ?? "").trimmed.isEmpty)
                }
            } header: {
                HStack {
                    Text(key.title)
                    Spacer()
                    Button {
                        withAnimation { draft.removeFacet(key) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.7))
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

            Picker("Default Unit", selection: Binding(
                get: { draft.defaultUnit ?? .piece },
                set: { draft.defaultUnit = $0 }
            )) {
                ForEach(MeasurementUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
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
            if let definition = await appState.generateIngredientDefinition(name: draft.name.trimmed) {
                draft.applyAIDefinition(definition)
            } else {
                autoFillError = "Could not generate definition. You can fill in the fields manually."
            }
            isAutoFilling = false
        }
    }

    private func save() {
        registrationError = nil

        if isEditing, let existingID = existingItemID {
            // Remove old entry, register updated one
            PantryCatalog.removeUserItem(id: existingID)
            let definition = draft.buildDefinition()
            let result = PantryCatalog.registerUserItem(definition)
            switch result {
            case .success:
                onSave?(definition.id)
                dismiss()
            case .failure(let error):
                // Re-register old one on failure — but it was already removed.
                // The user will need to fix the issue.
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

    private func commitNewOption(_ key: PantryFacetKey) {
        let text = (newOptionText[key] ?? "").trimmed
        guard !text.isEmpty else { return }
        draft.addFacetOption(key, value: text)
        newOptionText[key] = ""
    }

    private func deleteFacetOptions(key: PantryFacetKey, at offsets: IndexSet) {
        guard var options = draft.facets[key] else { return }
        options.remove(atOffsets: offsets)
        if options.isEmpty {
            draft.facets.removeValue(forKey: key)
        } else {
            draft.facets[key] = options
        }
    }
}
