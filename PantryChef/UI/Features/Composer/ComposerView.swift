import SwiftUI
import UIKit

/// The composer (spec §13): one bar, living cards. Typed phrases parse live and
/// crystallize into cards above the bar; the parser never rejects input. Staged
/// cards are editable and removable; the batch goes to Stock, the list, or
/// tonight's meal log.
struct ComposerView: View {
    var store: KitchenStore
    var onDismiss: () -> Void = {}
    /// Open the blank recipe editor (the manual "write a recipe" front door). The root
    /// dismisses the composer and presents the editor.
    var onWriteRecipe: () -> Void = {}
    /// Open the "paste a recipe → format with AI" import sheet.
    var onPasteRecipe: () -> Void = {}
    /// Generate a recipe from what's in the pantry right now ("cook with what I have").
    var onCookWithWhatIHave: () -> Void = {}
    /// Read a recipe from a photo / screenshot (library only).
    var onPhotoRecipe: () -> Void = {}
    /// Scan product barcodes into the pantry (deterministic, free).
    var onScanBarcode: () -> Void = {}

    /// Where the staged batch lands on commit.
    enum Destination: String, CaseIterable {
        case stock = "Stock", list = "List", meal = "Tonight's meal"
    }

    @State private var text = ""
    @State private var staged: [ParsedIntake] = []
    @State private var editing: EditTarget?
    @State private var destination: Destination = .stock
    @State private var resolving: Resolving?
    @FocusState private var focused: Bool

    private struct EditTarget: Identifiable { let id: Int }

    /// A typed phrase that needs disambiguation before it's staged.
    private enum Resolving: Identifiable {
        case pick(phrase: String, intake: ParsedIntake, candidates: [IntakeCandidate])
        case custom(phrase: String, intake: ParsedIntake)
        var id: String {
            switch self {
            case .pick(let p, _, _): return "pick:\(p)"
            case .custom(let p, _): return "custom:\(p)"
            }
        }
    }

    private var preview: ParsedIntake? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : store.parse(text)
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            VStack(alignment: .leading, spacing: 8) {
                Text("Add anything").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                destinationChips
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(staged.enumerated()), id: \.offset) { index, item in
                        IntakeCard(item: item,
                                   onRemove: { remove(index) },
                                   onEdit: { editing = EditTarget(id: index) })
                    }
                    bar
                    if let preview { IntakeCard(item: preview, isPreview: true) }
                    if staged.isEmpty && preview == nil { doorways }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
            }
            if !staged.isEmpty { commitBar }
        }
        .background(KitchenBackground())
        .onAppear { focused = true }
        .sheet(item: $editing) { target in
            if staged.indices.contains(target.id) {
                ComposerItemEditor(item: bindingFor(target.id), onDone: { editing = nil })
                    .presentationDetents([.medium])
            }
        }
        .sheet(item: $resolving) { r in
            switch r {
            case .pick(let phrase, let intake, let candidates):
                IngredientPicker(
                    phrase: phrase, candidates: candidates,
                    onPick: { stageResolved(intake, itemID: $0.id, name: $0.name); resolving = nil },
                    onCustom: { resolving = .custom(phrase: phrase, intake: intake) },
                    onCancel: { resolving = nil })
            case .custom(let phrase, let intake):
                CustomIngredientForm(
                    name: phrase,
                    autofill: { await store.ai.generateIngredientDefinition(name: $0) },
                    onSave: { def in stageResolved(intake, itemID: def.id, name: def.name); resolving = nil },
                    onCancel: { resolving = nil })
            }
        }
    }

    private var destinationChips: some View {
        HStack(spacing: 8) {
            ForEach(Destination.allCases, id: \.rawValue) { dest in
                let selected = destination == dest
                Button { withAnimation(.easeOut(duration: 0.15)) { destination = dest } } label: {
                    Text(dest.rawValue).font(Theme.Typography.fact(12))
                        .foregroundStyle(selected ? Theme.Palette.cream : Theme.Palette.warmGray)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(selected ? Theme.Palette.ink : Color.clear))
                        .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: selected ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bindingFor(_ index: Int) -> Binding<ParsedIntake> {
        Binding(get: { staged[index] }, set: { staged[index] = $0 })
    }

    private func remove(_ index: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { _ = staged.remove(at: index) }
    }

    private var grabber: some View {
        Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4).padding(.top, 10)
    }

    private var bar: some View {
        HStack(spacing: 8) {
            TextField("300 g spinach, fridge", text: $text)
                .font(Theme.Typography.fact(14)).focused($focused)
                .submitLabel(.next).onSubmit(commitCurrent)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.hairline))
    }

    private var doorways: some View {
        VStack(spacing: 0) {
            doorway("Log tonight's meal", "fork.knife") {
                withAnimation { destination = .meal }
            }
            Divider().background(Theme.Palette.hairline)
            doorway("Add to the list", "cart") {
                withAnimation { destination = .list }
            }
            Divider().background(Theme.Palette.hairline)
            doorway("Scan a barcode", "barcode.viewfinder") {
                onScanBarcode()
            }
            Divider().background(Theme.Palette.hairline)
            doorway("Paste from the clipboard", "doc.on.clipboard") {
                if let pasted = UIPasteboard.general.string {
                    text = pasted
                }
            }
            Divider().background(Theme.Palette.hairline)
            doorway("Write a recipe", "square.and.pencil") {
                onWriteRecipe()
            }
            Divider().background(Theme.Palette.hairline)
            doorway("Paste a recipe · format with AI", "wand.and.stars") {
                onPasteRecipe()
            }
            Divider().background(Theme.Palette.hairline)
            doorway("Photo of a recipe · AI", "camera") {
                onPhotoRecipe()
            }
            Divider().background(Theme.Palette.hairline)
            doorway("Cook with what I have · AI", "sparkles") {
                onCookWithWhatIHave()
            }
        }
        .padding(.horizontal, 4)
    }

    private func doorway(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.Palette.warmGray).frame(width: 22)
                Text(title).font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
                Spacer()
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var commitBar: some View {
        HStack {
            Text(destinationHint).font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
            Spacer()
            PaprikaButton(title: commitTitle, action: commit)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var destinationHint: String {
        switch destination {
        case .stock: return "Everything goes to Stock"
        case .list: return "Everything joins your list"
        case .meal: return "Logged as what you ate tonight"
        }
    }

    private var commitTitle: String {
        switch destination {
        case .stock: return "Add \(staged.count) to Stock"
        case .list: return "Add \(staged.count) to the list"
        case .meal: return "Log tonight's meal"
        }
    }

    private func commit() {
        switch destination {
        case .stock: staged.forEach { store.addToStock($0) }
        case .list: staged.forEach { store.addToList($0) }
        case .meal: store.logMeal(staged)
        }
        onDismiss()
    }

    private func commitCurrent() {
        let phrase = text.trimmingCharacters(in: .whitespaces)
        guard !phrase.isEmpty else { return }
        text = ""
        // Same intake pipeline as shop-add: confident phrases stage immediately;
        // uncertain ones open the picker; unknowns open the custom form. No bare,
        // unresolved item is ever staged.
        let (intake, decision) = IntakePipeline.resolve(phrase, using: store.parse)
        switch decision {
        case .confident: stage(intake)
        case .ambiguous(let candidates): resolving = .pick(phrase: phrase, intake: intake, candidates: candidates)
        case .custom: resolving = .custom(phrase: phrase, intake: intake)
        }
    }

    private func stage(_ intake: ParsedIntake) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { staged.append(intake) }
    }

    /// Stage an intake resolved to a specific catalog item (a picked candidate or a
    /// freshly-created custom item).
    private func stageResolved(_ intake: ParsedIntake, itemID: String, name: String) {
        var resolved = intake
        resolved.resolvedItemID = itemID
        resolved.suggestedName = name
        resolved.name = name
        resolved.confidence = .resolved
        stage(resolved)
    }
}

/// One parsed item as a card. Staged cards (with `onRemove`/`onEdit`) are editable
/// and removable; the live preview card is read-only.
private struct IntakeCard: View {
    let item: ParsedIntake
    var isPreview = false
    var onRemove: (() -> Void)?
    var onEdit: (() -> Void)?

    var body: some View {
        Button { onEdit?() } label: { cardBody }
            .buttonStyle(.plain)
            .disabled(onEdit == nil)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                icon
                Text(title).font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                if let storage = item.storage {
                    Text(storageLabel(storage)).font(Theme.Typography.fact(11))
                        .foregroundStyle(Theme.Palette.warmGraySoft)
                }
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                            .foregroundStyle(Theme.Palette.warmGraySoft.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            if item.suggestedName != nil {
                hint("from \u{201C}\(item.name)\u{201D} — tap to fix")
            }
            if let unit = item.unrecognizedUnit {
                hint("\u{201C}\(unit)\u{201D} isn't a unit I know — tap to fix")
            }
            if item.confidence == .unresolved && item.suggestedName == nil {
                hint("new to me — saved as a custom item")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 3)
            .fill(Theme.Palette.creamRaised.opacity(isPreview ? 0.6 : 1)))
        .overlay(RoundedRectangle(cornerRadius: 3)
            .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 1, dash: item.confidence == .unresolved ? [4, 3] : [])))
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.ochre).padding(.leading, 25)
    }

    private var title: String {
        var parts: [String] = []
        if let q = item.quantity { parts.append(formatQty(q)) }
        if let u = item.unit { parts.append(u.rawValue) } else if let raw = item.unrecognizedUnit { parts.append(raw) }
        parts.append(item.suggestedName ?? (item.name.isEmpty ? "—" : item.name))
        return parts.joined(separator: " ")
    }

    @ViewBuilder private var icon: some View {
        switch item.confidence {
        case .resolved: Image(systemName: "checkmark").foregroundStyle(Theme.Palette.sage)
        case .guessed: Image(systemName: "pencil").foregroundStyle(Theme.Palette.ochre)
        case .unresolved: Image(systemName: "sparkles").foregroundStyle(Theme.Palette.warmGraySoft)
        }
    }

    private var borderColor: Color {
        switch item.confidence {
        case .resolved: return Theme.Palette.hairline
        case .guessed: return Theme.Palette.ochre.opacity(0.4)
        case .unresolved: return Theme.Palette.warmGraySoft.opacity(0.6)
        }
    }

    private func formatQty(_ q: Double) -> String { QuantityFormat.short(q) }
    private func storageLabel(_ s: PantryStorage) -> String {
        switch s { case .refrigerated: return "fridge"; case .frozen: return "freezer"; case .pantry: return "pantry" }
    }
}

/// Edit a staged item: amount, unit, storage, name. Resolves the "unrecognized
/// unit" and "custom ingredient" cases too.
private struct ComposerItemEditor: View {
    @Binding var item: ParsedIntake
    var onDone: () -> Void
    @State private var qtyText: String

    init(item: Binding<ParsedIntake>, onDone: @escaping () -> Void) {
        _item = item
        self.onDone = onDone
        let q = item.wrappedValue.quantity
        _qtyText = State(initialValue: q.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            Text("Edit item").font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)

            field("Name") {
                TextField("Name", text: Binding(get: { item.suggestedName ?? item.name },
                                                set: { item.name = $0; item.suggestedName = nil; item.confidence = .resolved }))
                    .textFieldStyle(.plain)
            }
            field("Amount") {
                HStack(spacing: 10) {
                    TextField("Qty", text: $qtyText)
                        .keyboardType(.decimalPad)
                        .onChange(of: qtyText) { item.quantity = Double(qtyText) }
                        .frame(width: 70)
                    unitMenu
                }
            }
            field("Storage") { storagePicker }

            Spacer()
            PaprikaButton(title: "Done", action: onDone).frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Theme.Typography.eyebrow).tracking(Theme.Metric.eyebrowTracking)
                .foregroundStyle(Theme.Palette.warmGraySoft)
            content()
                .font(Theme.Typography.fact(15)).foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.hairline))
        }
    }

    private var unitMenu: some View {
        Menu {
            Button("No unit") { item.unit = nil; item.unrecognizedUnit = nil }
            if let raw = item.unrecognizedUnit {
                Button("Keep \u{201C}\(raw)\u{201D}") { item.unit = nil }
            }
            ForEach(MeasurementUnit.allCases) { unit in
                Button(unit.rawValue) { item.unit = unit; item.unrecognizedUnit = nil }
            }
        } label: {
            HStack {
                Text(item.unit?.rawValue ?? item.unrecognizedUnit ?? "unit")
                    .foregroundStyle(item.unit != nil ? Theme.Palette.ink : Theme.Palette.warmGraySoft)
                Image(systemName: "chevron.down").font(.system(size: 11)).foregroundStyle(Theme.Palette.warmGraySoft)
            }
        }
    }

    private var storagePicker: some View {
        HStack(spacing: 8) {
            ForEach([PantryStorage.pantry, .refrigerated, .frozen], id: \.self) { storage in
                let selected = item.storage == storage
                Button { item.storage = selected ? nil : storage } label: {
                    Text(label(storage)).font(Theme.Typography.fact(12))
                        .foregroundStyle(selected ? Theme.Palette.cream : Theme.Palette.warmGray)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(selected ? Theme.Palette.ink : Color.clear))
                        .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: selected ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(_ s: PantryStorage) -> String {
        switch s { case .refrigerated: return "Fridge"; case .frozen: return "Freezer"; case .pantry: return "Pantry" }
    }
}
