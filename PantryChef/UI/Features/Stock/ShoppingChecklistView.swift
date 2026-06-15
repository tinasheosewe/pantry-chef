import SwiftUI

/// The shopping run (spec §3): a checklist you use in the aisle. Check things as
/// they go in the cart, adjust the amount you actually bought, add anything extra
/// you picked up — then "Done" moves everything checked into Stores, freshly
/// confirmed, and leaves the rest on the list. Printed-receipt furniture to match
/// the Field Notes world.
struct ShoppingChecklistView: View {
    var store: KitchenStore
    var onClose: () -> Void

    /// Local cart state — committed only on Done, so a mistaken tap costs nothing.
    /// `amounts` starts from each item's *desired* amount and is edited to what was
    /// actually bought.
    @State private var checked: Set<String> = []
    @State private var amounts: [String: String] = [:]
    @State private var extras: [ShoppingEntry] = []
    @State private var newItem = ""
    @State private var seeded = false
    @State private var resolving: Resolving?
    @FocusState private var addingFocused: Bool

    /// A typed item that needs disambiguation before it joins the cart.
    private enum Resolving: Identifiable {
        case pick(phrase: String, amount: String?, candidates: [IntakeCandidate])
        case custom(phrase: String, amount: String?)
        var id: String {
            switch self {
            case .pick(let p, _, _): return "pick:\(p)"
            case .custom(let p, _): return "custom:\(p)"
            }
        }
    }

    private var entries: [ShoppingEntry] { store.shoppingList + extras }
    private var boughtCount: Int { checked.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            DashedRule().padding(.horizontal, 20).padding(.top, 10)
            // A List so removal is the native swipe gesture (no ✕): swipe a row to
            // remove it. Marking bought is a tap on the check — distinct gesture, no
            // conflict. Separators tinted to ink to fit the printed look.
            List {
                ForEach(entries) { entry in
                    row(entry)
                        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.Palette.ink.opacity(0.18))
                        // A full swipe removes the row outright — the swipe performs
                        // the action, no button to then tap. Marking bought is the
                        // checkbox tap, so there's no redundant swipe-to-bought.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { remove(entry) } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
                addRow
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 5, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            footer
        }
        .background(KitchenBackground())
        .onAppear {
            guard !seeded else { return }
            for entry in store.shoppingList where amounts[entry.name] == nil {
                amounts[entry.name] = entry.amount ?? ""   // pre-fill bought amount with desired
            }
            seeded = true
        }
        .sheet(item: $resolving) { r in
            switch r {
            case .pick(let phrase, let amount, let candidates):
                IngredientPicker(
                    phrase: phrase, candidates: candidates,
                    onPick: { addGrabbed(name: $0.name, amount: amount); resolving = nil },
                    onCustom: { resolving = .custom(phrase: phrase, amount: amount) },
                    onCancel: { resolving = nil })
            case .custom(let phrase, let amount):
                CustomIngredientForm(
                    name: phrase,
                    autofill: { await store.ai.generateIngredientDefinition(name: $0) },
                    onSave: { def in addGrabbed(name: def.name, amount: amount); resolving = nil },
                    onCancel: { resolving = nil })
            }
        }
    }

    /// Remove a line: list items leave the store list, ad-hoc extras just drop.
    private func remove(_ entry: ShoppingEntry) {
        withAnimation {
            if extras.contains(where: { $0.id == entry.id }) {
                extras.removeAll { $0.id == entry.id }
            } else {
                store.removeFromList(entry.name)
            }
            checked.remove(entry.name)
            amounts[entry.name] = nil
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shopping").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                Text("Check things off as they go in the cart.")
                    .font(Theme.Typography.note(11.5)).foregroundStyle(Theme.Palette.warmGray)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.warmGray)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 18)
    }

    private func row(_ entry: ShoppingEntry) -> some View {
        let name = entry.name
        let isChecked = checked.contains(name)
        return HStack(spacing: 11) {
            Button { toggle(name) } label: {
                InkCheck(on: isChecked, size: 22)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            PlateView(name: name, composition: store.plate(forName: name), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Theme.Typography.fact(14.5)).foregroundStyle(Theme.Palette.ink)
                    .strikethrough(isChecked, color: Theme.Palette.warmGraySoft)
                // The desired amount, shown until it's in the cart (then you edit
                // it to what you actually bought, on the right).
                if let want = entry.amount, !isChecked {
                    Text("want \(want)").font(Theme.Typography.fact(11))
                        .foregroundStyle(Theme.Palette.warmGraySoft)
                }
            }
            Spacer(minLength: 6)
            // Count actually bought — pre-filled with the desired amount, editable.
            if isChecked {
                TextField("count", text: Binding(
                    get: { amounts[name] ?? "" }, set: { amounts[name] = $0 }))
                    .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 84)
                    .padding(.horizontal, 8).frame(minHeight: 34)
                    .overlay(Rectangle().strokeBorder(Theme.Palette.sage.opacity(0.7), lineWidth: 1))
            }
        }
        .padding(.vertical, 4)
        .animation(.spring(response: 0.3, dampingFraction: 1), value: isChecked)
    }

    private var addRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Palette.paprika).frame(width: 22)
            TextField("Add something you grabbed", text: $newItem)
                .font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
                .focused($addingFocused)
                .onSubmit(commitNewItem)
            if !newItem.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add", action: commitNewItem)
                    .font(Theme.Typography.fact(13, weight: .medium))
                    .foregroundStyle(Theme.Palette.paprika)
                    .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            SolidRule()
            HStack {
                Text("\(boughtCount) IN THE CART")
                    .font(.system(size: 10, weight: .medium)).tracking(1.4)
                    .foregroundStyle(Theme.Palette.warmGray)
                Spacer()
                BlockButton(title: boughtCount > 0 ? "Put \(boughtCount) away" : "Done") {
                    for name in checked { store.purchase(name: name, amount: amounts[name]) }
                    onClose()
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Theme.Palette.cream)
    }

    private func toggle(_ name: String) {
        if checked.contains(name) { checked.remove(name) } else { checked.insert(name) }
    }

    private func commitNewItem() {
        let phrase = newItem.trimmingCharacters(in: .whitespaces)
        guard !phrase.isEmpty else { return }
        newItem = ""
        // The one intake pipeline: confident matches join silently; uncertain ones
        // open the picker (+ Custom); genuine unknowns go straight to Custom. Never
        // a silent wrong guess.
        let (intake, decision) = IntakePipeline.resolve(phrase, using: store.parse)
        let amount = KitchenStore.amountText(intake)
        switch decision {
        case .confident:
            addGrabbed(name: intake.suggestedName ?? intake.name, amount: amount)
        case .ambiguous(let candidates):
            resolving = .pick(phrase: phrase, amount: amount, candidates: candidates)
        case .custom:
            resolving = .custom(phrase: phrase, amount: amount)
        }
    }

    /// Add a resolved ingredient to the cart (checked), seeding its bought amount.
    private func addGrabbed(name: String, amount: String?) {
        guard !name.isEmpty else { return }
        let display = name.prefix(1).capitalized + name.dropFirst()
        if !entries.contains(where: { $0.name.lowercased() == display.lowercased() }) {
            extras.append(ShoppingEntry(name: display, amount: amount))
        }
        amounts[display] = amount ?? ""
        checked.insert(display)
        addingFocused = true
    }
}
