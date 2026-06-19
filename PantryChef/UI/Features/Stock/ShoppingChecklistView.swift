import SwiftUI

/// The shopping run (spec §3): a checklist you use in the aisle. Check things as
/// they go in the cart, adjust the amount you actually bought, add anything extra
/// you picked up — then "Done" moves everything checked into Stores, freshly
/// confirmed, and leaves the rest on the list. Printed-receipt furniture to match
/// the Field Notes world.
struct ShoppingChecklistView: View {
    var store: KitchenStore
    var onClose: () -> Void

    /// Checked state lives on the store entries (persists across open/close); `amounts`
    /// is the bought amount, seeded from each item's desired amount and edited in place.
    @State private var amounts: [String: String] = [:]
    @State private var extras: [ShoppingEntry] = []
    @State private var newItem = ""
    @State private var seeded = false
    @State private var resolving: Resolving?
    /// Category filter chip in effect — nil = "All" (every aisle), like the Pantry.
    @State private var selectedCategory: FoodCategory?
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
    private var boughtCount: Int { entries.filter(\.checked).count }

    /// Aisle groups shown — every category on "All", just the selected one otherwise.
    private var displayedGroups: [(FoodCategory, [ShoppingEntry])] {
        let all = store.shoppingByCategory(entries)
        guard let cat = selectedCategory else { return all }
        return all.filter { $0.0 == cat }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // Pinned category chips, like the Pantry — filter the aisles you shop.
            CategoryFilterRail(categories: store.shoppingByCategory(entries).map(\.0),
                               selected: $selectedCategory)
                .padding(.top, 10)
            DashedRule().padding(.horizontal, 20).padding(.top, 8)
            // A List so removal is the native swipe gesture (no ✕): swipe a row to
            // remove it. Marking bought is a tap on the check — distinct gesture, no
            // conflict. Separators tinted to ink to fit the printed look.
            // Grouped by category (aisle order), the same grouping the Pantry uses, so
            // you shop section by section.
            List {
                if entries.isEmpty {
                    QuietEmpty(eyebrow: "Nothing on the list",
                               line: "Add what you’re short on, or send a recipe’s missing bits here.")
                        .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(displayedGroups, id: \.0) { cat, items in
                    Section {
                        ForEach(items) { entry in
                            row(entry)
                                .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(Theme.Palette.ink.opacity(0.18))
                                // Swipe right (leading) to mark bought, swipe left
                                // (trailing) to remove — full-swipe performs the action.
                                // Tapping the check still toggles bought too.
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { toggle(entry.name) } label: {
                                        Label(entry.checked ? "Un-cart" : "Bought",
                                              systemImage: entry.checked ? "arrow.uturn.left" : "checkmark")
                                    }
                                    .tint(Theme.Palette.sage)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { remove(entry) } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        sectionHeader(cat)
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

    /// A category band between aisles — emoji + name + a slim color spine, matching the
    /// Pantry's section headers.
    private func sectionHeader(_ cat: FoodCategory) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(cat.color).frame(width: 3, height: 12)
            Text(EmojiPlate.categoryFace(cat)).font(.system(size: 12))
            Text(cat.rawValue).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Theme.Palette.ink.opacity(0.6))
        }
        .textCase(nil)
        .padding(.leading, 20)
    }

    private func row(_ entry: ShoppingEntry) -> some View {
        let name = entry.name
        let isChecked = entry.checked
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
            // Amount actually bought — same structured number + unit-from-list as a
            // recipe ingredient (no freeform text). Pre-filled with the desired amount.
            if isChecked {
                AmountField(amount: Binding(
                    get: { (amounts[name]?.isEmpty ?? true) ? nil : amounts[name] },
                    set: { amounts[name] = $0 ?? "" }),
                    defaultUnit: store.defaultUnit(forName: name),
                    qtyWidth: 40, unitWidth: 46)
                    .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
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
                    // Completion is the one place checks clear automatically — each bought
                    // item moves to stock and leaves the list.
                    for entry in entries where entry.checked {
                        store.purchase(name: entry.name, amount: amounts[entry.name] ?? entry.amount)
                    }
                    onClose()
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Theme.Palette.cream)
    }

    /// Toggle the checked flag on the matching entry — a store line (persists) or a
    /// local ad-hoc extra. Only ever called from a user tap/swipe.
    private func toggle(_ name: String) {
        if let i = store.shoppingList.firstIndex(where: { $0.name == name }) {
            store.shoppingList[i].checked.toggle()
        } else if let i = extras.firstIndex(where: { $0.name == name }) {
            extras[i].checked.toggle()
        }
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
    /// Its category is resolved (catalog or just-registered custom item) so an ad-hoc
    /// grab still lands in an aisle, never outside the grouping.
    private func addGrabbed(name: String, amount: String?) {
        guard !name.isEmpty else { return }
        let display = name.prefix(1).capitalized + name.dropFirst()
        let category = store.listCategory(forName: display)
        // You grabbed it → it's in the cart (checked). Mark the existing line if it was
        // already on the list/extras, else add a new ad-hoc extra already checked.
        if let i = store.shoppingList.firstIndex(where: { $0.name.lowercased() == display.lowercased() }) {
            store.shoppingList[i].checked = true
        } else if let i = extras.firstIndex(where: { $0.name.lowercased() == display.lowercased() }) {
            extras[i].checked = true
        } else {
            extras.append(ShoppingEntry(name: display, amount: amount, category: category, checked: true))
        }
        amounts[display] = amount ?? ""
        // If a category filter is on and the new item belongs to a different aisle, it
        // would be added but hidden — drop to "All" so it's never added out of sight.
        if let sel = selectedCategory, sel != category { selectedCategory = nil }
        addingFocused = true
    }
}
