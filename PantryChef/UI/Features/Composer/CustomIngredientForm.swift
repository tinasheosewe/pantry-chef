import SwiftUI

/// Create a first-class custom ingredient when the catalog doesn't know one (spec
/// §7). Fields are filled manually, or with one tap of **Autofill** (AI proposes
/// category / storage / shelf life, which you can still edit). Saving registers a
/// validated user catalog item — complete, with a real freshness countdown — so
/// there is never a path to an incomplete ingredient.
struct CustomIngredientForm: View {
    @State private var draft: CustomIngredientDraft
    /// AI fill: name → proposed definition (nil if unavailable/declined).
    var autofill: (String) async -> AIIngredientDefinition?
    /// Receives the registered catalog item on save.
    var onSave: (PantryCatalogItemDefinition) -> Void
    var onCancel: () -> Void

    @State private var autofilling = false
    @State private var error: String?

    init(name: String,
         autofill: @escaping (String) async -> AIIngredientDefinition?,
         onSave: @escaping (PantryCatalogItemDefinition) -> Void,
         onCancel: @escaping () -> Void) {
        _draft = State(initialValue: CustomIngredientDraft(name: name))
        self.autofill = autofill
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            DashedRule().padding(.horizontal, 20).padding(.top, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    nameField
                    autofillRow
                    categoryField
                    storageField
                    shelfLifeField
                    if let warning = draft.nameCollisionWarning {
                        Text(warning).font(Theme.Typography.note(11.5)).foregroundStyle(Theme.Palette.paprika)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 24)
            }
            footer
        }
        .background(KitchenBackground())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New ingredient").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                Text("Not in the catalog — let's make it first-class.")
                    .font(Theme.Typography.note(11.5)).foregroundStyle(Theme.Palette.warmGray)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.warmGray).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 18)
    }

    private var nameField: some View {
        field("Name") {
            TextField("e.g. yuzu kosho", text: $draft.name)
                .font(Theme.Typography.fact(15)).foregroundStyle(Theme.Palette.ink)
        }
    }

    private var autofillRow: some View {
        Button {
            autofilling = true
            Task {
                if let def = await autofill(draft.name) { draft.applyAIDefinition(def) }
                autofilling = false
            }
        } label: {
            HStack(spacing: 8) {
                if autofilling { ProgressView().controlSize(.small) }
                else { Image(systemName: "wand.and.stars").font(.system(size: 13)) }
                Text(autofilling ? "Autofilling…" : "Autofill the details")
                    .font(.system(size: 12, weight: .medium)).tracking(0.4)
            }
            .foregroundStyle(Theme.Palette.sage)
            .padding(.horizontal, 12).frame(minHeight: 38)
            .overlay(Rectangle().strokeBorder(Theme.Palette.sage.opacity(0.7), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(autofilling || draft.name.trimmed.isEmpty)
    }

    private var categoryField: some View {
        field("Category") {
            Menu {
                ForEach(FoodCategory.allCases) { c in
                    Button(c.rawValue) { draft.category = c }
                }
            } label: {
                HStack {
                    Text(draft.category.rawValue).foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 11)).foregroundStyle(Theme.Palette.warmGraySoft)
                }
            }
        }
    }

    private var storageField: some View {
        field("Where it's kept") {
            HStack(spacing: 8) {
                ForEach([PantryStorage.pantry, .refrigerated, .frozen], id: \.self) { s in
                    let selected = draft.defaultStorage == s
                    Button { draft.defaultStorage = s } label: {
                        Text(storageLabel(s)).font(.system(size: 10, weight: .medium)).tracking(1.2)
                            .foregroundStyle(selected ? Theme.Palette.cream : Theme.Palette.ink.opacity(0.7))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(Rectangle().fill(selected ? Theme.Palette.ink : .clear))
                            .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(selected ? 0 : 0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var shelfLifeField: some View {
        field("Lasts about") {
            Stepper("\(draft.effectiveShelfLifeDays) days in \(storageLabel(draft.defaultStorage).lowercased())",
                    value: Binding(get: { draft.effectiveShelfLifeDays },
                                   set: { draft.shelfLifeDays = $0 }), in: 1...365)
                .font(Theme.Typography.fact(14))
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            SolidRule()
            HStack {
                if let error { Text(error).font(Theme.Typography.note(11)).foregroundStyle(Theme.Palette.paprika) }
                Spacer()
                BlockButton(title: "Save") { save() }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Theme.Palette.cream)
        .opacity(draft.validationError == nil ? 1 : 0.6)
    }

    private func save() {
        if let v = draft.validationError { error = v; return }
        let definition = draft.buildDefinition()
        switch PantryCatalog.registerUserItem(definition) {
        case .success: onSave(definition)
        case .failure(let e): error = e.errorDescription ?? "Couldn't save."
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: label)
            content()
                .font(Theme.Typography.fact(15)).foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Rectangle().fill(Theme.Palette.creamRaised))
                .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(0.25), lineWidth: 1))
        }
    }

    private func storageLabel(_ s: PantryStorage) -> String {
        switch s { case .refrigerated: return "Fridge"; case .frozen: return "Freezer"; case .pantry: return "Pantry" }
    }
}
