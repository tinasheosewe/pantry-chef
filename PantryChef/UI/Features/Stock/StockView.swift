import SwiftUI

/// Stores — the inventory as a printed ledger (spec §3, Field Notes). The kitchen
/// speaks first in a sentence; then PERISHING FIRST with day counts on dotted
/// leaders, STAPLES with honest presence tags (never a fake gauge, spec §7),
/// MADE BY YOU, and THE LIST. Rows are tappable → editor.
struct StockView: View {
    var store: KitchenStore

    @State private var editing: StockItem?
    @State private var shopping = false
    /// The category filter chip in effect — nil = "All" (everything, grouped under
    /// headers); a value narrows the list to that one category.
    @State private var selectedCategory: FoodCategory?
    /// The item whose "add to list" quantity we're asking for (we ask how much rather
    /// than guessing an amount).
    @State private var listing: ListPrompt?

    struct ListPrompt: Identifiable {
        let id = UUID()
        let name: String
        let plate: PlateComposition
        let suggested: String?
        let defaultUnit: MeasurementUnit?
    }

    private var allPerishable: [StockItem] {
        store.stock
            .filter { if case .perishable = $0.measure { return true } else { return false } }
            .sorted { (days($0) ?? .max) < (days($1) ?? .max) }
    }
    /// The expiry *warning* — perishables inside the tight "use it or lose it"
    /// window. Lifted out of the calm sort into a band at the top (and the tab badge).
    private var urgent: [StockItem] { store.expiringSoon() }
    private var urgentIDs: Set<UUID> { Set(urgent.map(\.id)) }
    /// For the header sentence only.
    private var staples: [StockItem] {
        store.stock.filter { if case .staple = $0.measure { return true } else { return false } }
    }

    /// The pantry grouped by category in display order (empty categories dropped),
    /// each sorted by urgency within.
    private var groups: [(FoodCategory, [StockItem])] {
        let byCat = Dictionary(grouping: store.stock, by: \.category)
        return FoodCategory.displayOrder.compactMap { cat in
            guard let items = byCat[cat], !items.isEmpty else { return nil }
            return (cat, items.sorted { (days($0) ?? .max) < (days($1) ?? .max) })
        }
    }

    /// Live days-left: the stored estimate counts down from its anchor, so the
    /// ledger (and its urgency sort) reflect today, not the day it was logged.
    private func days(_ item: StockItem) -> Int? {
        item.daysLeft(now: store.today)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Pantry").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    cartButton
                }
                Text(summary)
                    .font(Theme.Typography.note(11.5)).foregroundStyle(Theme.Palette.warmGray)
                    .fixedSize(horizontal: false, vertical: true)
                DashedRule().padding(.top, 6)
            }
            .padding(.horizontal, 20).padding(.top, 6)
            // The category chips stay pinned above the list, so switching category is
            // one tap from anywhere — no scrolling back up to a tile grid.
            CategoryFilterRail(categories: groups.map(\.0), selected: $selectedCategory,
                               flagged: Set(urgent.map(\.category)))
                .padding(.top, 10).padding(.bottom, 2)
            DashedRule().padding(.horizontal, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The expiry warning persists across category filters — scoped to
                    // the items in view (all of them on "All", just this category's
                    // otherwise) so it's always actionable, never hidden by a filter.
                    if !scopedUrgent.isEmpty { warningBand }
                    if let cat = selectedCategory {
                        let items = groups.first { $0.0 == cat }?.1 ?? []
                        sectionHeader(cat, items.count)
                        ForEach(items) { item in row(item) }
                    } else {
                        ForEach(groups, id: \.0) { cat, items in
                            sectionHeader(cat, items.count)
                            ForEach(items) { item in row(item) }
                            DashedRule().padding(.top, 11)
                        }
                    }
                    // Cooked/leftover dishes live in Dishes (and the now-module's
                    // ready-made fan), not here — Stores is ingredients & staples. The
                    // shopping list now opens from the header cart, not a buried footer.
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .background(KitchenBackground())
        .sheet(item: $editing) { item in
            StockItemEditor(
                item: item,
                today: store.today,
                adjustDaysOnStorageChange: store.autoAdjustDaysOnStorageChange,
                onSave: { store.updateStock($0); editing = nil },
                onRemove: { store.removeStock($0); editing = nil }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $shopping) {
            ShoppingChecklistView(store: store) { shopping = false }
        }
        .sheet(item: $listing) { prompt in
            AddToListSheet(prompt: prompt,
                           onAdd: { amount in store.addToList(name: prompt.name, amount: amount); listing = nil },
                           onCancel: { listing = nil })
                .presentationDetents([.height(260)])
        }
    }

    // MARK: - Section headers

    /// The expiry warnings in view: all of them on "All", just the selected category's
    /// otherwise — so the band persists across filters instead of vanishing.
    private var scopedUrgent: [StockItem] {
        guard let cat = selectedCategory else { return urgent }
        return urgent.filter { $0.category == cat }
    }

    /// A category's section header in the list — emoji, name, count, and a slim
    /// color spine, so "All" reads as labelled blocks rather than one long run.
    private func sectionHeader(_ cat: FoodCategory, _ count: Int) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(cat.color).frame(width: 3, height: 13)
            Text(EmojiPlate.categoryFace(cat)).font(.system(size: 13))
            Eyebrow(text: cat.rawValue)
            Text("\(count)").font(Theme.Typography.note(10.5)).foregroundStyle(Theme.Palette.warmGray)
            Spacer()
        }
        .padding(.top, 14).padding(.bottom, 2)
    }

    /// The expiry warning: a tomato-bordered band at the very top, so spoilage reads
    /// as "act on this", not a quietly-sorted row you scroll past. Tap a line to edit;
    /// the "+ list" sends the about-to-turn item straight to the shopping list.
    private var warningBand: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                Text("USE SOON — \(scopedUrgent.count)")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.4)
            }
            .foregroundStyle(Theme.Palette.paprika)
            ForEach(scopedUrgent) { item in
                Button { editing = item } label: {
                    LeaderRow {
                        Text("\(emoji(item))\u{2002}\(item.name)")
                            .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink).lineLimit(1)
                    } trailing: {
                        HStack(spacing: 8) {
                            if case .perishable(let detail, _) = item.measure, !detail.isEmpty {
                                Text(detail.uppercased()).font(.system(size: 10)).tracking(0.8)
                                    .foregroundStyle(Theme.Palette.warmGraySoft)
                            }
                            Text(daysLabel(item))
                                .font(Theme.Typography.dish(11, weight: .semibold))
                                .foregroundStyle(Theme.Palette.paprika)
                            listAffordance(item)
                        }
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Rectangle().fill(Theme.Palette.paprika.opacity(0.08)))
        .overlay(Rectangle().strokeBorder(Theme.Palette.paprika.opacity(0.55), lineWidth: 1))
        .padding(.top, 14)
    }

    /// "Send to shopping list" for an expiring or running-low item — always asks *how
    /// much* (a quantity prompt) rather than guessing. Already on the list? It stays
    /// tappable as "+ MORE" and the quantity adds to what's there (additive), so a
    /// second tap because something's low tops up the line instead of being blocked.
    private func listAffordance(_ item: StockItem) -> some View {
        let listed = store.isOnList(item.name)
        return Button { listing = ListPrompt(name: item.name, plate: item.plate, suggested: suggestedAmount(item),
                                             defaultUnit: PantryCatalog.itemsByID[item.catalogItemID ?? ""]?.defaultUnit) } label: {
            Text(listed ? "+ MORE" : "+ LIST").font(.system(size: 9, weight: .semibold)).tracking(0.8)
                .foregroundStyle(listed ? Theme.Palette.sage : Theme.Palette.paprika)
                .padding(.horizontal, 7).frame(minHeight: 30)
                .overlay(Rectangle().strokeBorder((listed ? Theme.Palette.sage : Theme.Palette.paprika).opacity(0.6), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// A starting amount for the prompt — the size you currently keep, when we know it
    /// (an editable suggestion, not an assumption).
    private func suggestedAmount(_ item: StockItem) -> String? {
        if case .perishable(let detail, _) = item.measure, !detail.isEmpty { return detail }
        return nil
    }

    /// "TODAY" for anything at or past its date, else "N DAY(S)".
    private func daysLabel(_ item: StockItem) -> String {
        guard let d = item.daysLeft(now: store.today) else { return "" }
        if d <= 0 { return "TODAY" }
        return d == 1 ? "1 DAY" : "\(d) DAYS"
    }

    /// "7 things in. The spinach wants using; staples are solid; 5 wait on the list."
    private var summary: String {
        var parts: [String] = ["\(store.stock.count) things in."]
        if let urgent = allPerishable.first, let d = days(urgent), d <= 3 {
            parts.append("The \(urgent.name.lowercased()) wants using;")
        }
        let anyLow = staples.contains { if case .staple(let l) = $0.measure { return l != .inStock } else { return false } }
        parts.append(anyLow ? "staples need a top-up;" : "staples are solid;")
        parts.append("\(store.shoppingList.count) wait on the list.")
        return parts.joined(separator: " ")
    }

    // MARK: - Ledger rows

    @ViewBuilder private func row(_ item: StockItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { editing = item } label: {
                LeaderRow {
                    Text("\(emoji(item))\u{2002}\(item.name)")
                        .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
                        .lineLimit(1)
                } trailing: {
                    trailing(item)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The trust loop: when the knowledge clock has gone stale, ask one
            // question — no typing, three taps. (Spec §7.)
            if item.needsCheck(now: store.today) {
                checkStrip(item)
            }
        }
    }

    /// "Haven't seen this lately — still around?" with one-tap answers.
    private func checkStrip(_ item: StockItem) -> some View {
        HStack(spacing: 7) {
            Text(hedge(item.certainty(now: store.today)))
                .font(Theme.Typography.note(10.5)).foregroundStyle(Theme.Palette.paprika)
            Spacer(minLength: 4)
            // Only "still here" or "finished" — a non-staple carries a real
            // quantity, so a discrete "low" reads as noise (that's a staple idea).
            checkTag("Still here") { withAnimation { store.reconfirm(item.id) } }
            checkTag("Finished", urgent: true) { withAnimation { store.markGone(item.id) } }
        }
        .padding(.leading, 18).padding(.bottom, 4)
    }

    private func checkTag(_ title: String, urgent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .medium)).tracking(1.0)
                .foregroundStyle(urgent ? Theme.Palette.paprika : Theme.Palette.ink)
                .padding(.horizontal, 11).frame(minHeight: 34)
                .overlay(Rectangle().strokeBorder(
                    (urgent ? Theme.Palette.paprika : Theme.Palette.ink).opacity(urgent ? 1 : 0.55), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// User-facing wording for low certainty — never the raw label (spec §7).
    private func hedge(_ certainty: ItemCertainty) -> String {
        switch certainty {
        case .likelyGone: return "probably used up —"
        case .uncertain: return "haven't seen this lately —"
        case .probable, .confirmed: return ""
        }
    }

    private func emoji(_ item: StockItem) -> String {
        // Specific ingredient emoji where one exists, else its category's face.
        EmojiPlate.icon(for: item.name, category: item.category)
    }

    @ViewBuilder private func trailing(_ item: StockItem) -> some View {
        switch item.measure {
        case .perishable(let detail, _):
            HStack(spacing: 8) {
                Text(detail.uppercased())
                    .font(.system(size: 10)).tracking(0.8)
                    .foregroundStyle(Theme.Palette.warmGraySoft)
                if let d = item.daysLeft(now: store.today) {
                    Text(d == 1 ? "1 DAY" : "\(d) DAYS")
                        .font(Theme.Typography.dish(11, weight: .semibold))
                        .foregroundStyle(d <= 3 ? Theme.Palette.paprika : Theme.Palette.warmGray)
                }
                // About to turn? Offer the list right where you see it.
                if urgentIDs.contains(item.id) { listAffordance(item) }
            }
        case .staple(let level):
            switch level {
            case .inStock: OutlineTag(text: "In")
            case .runningLow:
                HStack(spacing: 8) { OutlineTag(text: "Low", tone: .urgent); listAffordance(item) }
            case .out:
                HStack(spacing: 8) { OutlineTag(text: "Out", tone: .urgent); listAffordance(item) }
            }
        case .made(let detail, let portions):
            Text((portions.map { "\($0) \($0 == 1 ? "portion" : "portions")" } ?? detail).uppercased())
                .font(.system(size: 10)).tracking(0.8)
                .foregroundStyle(Theme.Palette.warmGray)
                .lineLimit(1)
        }
    }

    /// The shopping list lives one tap away in the header — a cart with the item count,
    /// always reachable without scrolling the inventory. Opens the Shop run.
    private var cartButton: some View {
        Button { shopping = true } label: {
            Image(systemName: "cart")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Palette.paprika)
                .overlay(alignment: .topTrailing) {
                    if !store.shoppingList.isEmpty {
                        Text("\(store.shoppingList.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Palette.cream)
                            .frame(minWidth: 14, minHeight: 14).padding(.horizontal, 1)
                            .background(Rectangle().fill(Theme.Palette.paprika))
                            .offset(x: 10, y: -7)
                    }
                }
                .frame(width: 44, height: 44, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shopping list")
        .accessibilityValue("\(store.shoppingList.count) items")
    }
}

/// Edit one stock item: amount/detail, days left or staple level, section, remove.
private struct StockItemEditor: View {
    @State var item: StockItem
    /// The app's clock (not wall-clock `Date()`), so edits re-anchor against the same
    /// `today` the rest of the app reads — they agree even when `today` is pinned.
    var today: Date = Date()
    /// Mirror of the Settings preference — gates whether changing storage re-projects
    /// the days-left or only relabels where the item is kept.
    var adjustDaysOnStorageChange = true
    var onSave: (StockItem) -> Void
    var onRemove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                PlateView(name: item.name, composition: item.plate, size: 38)
                Text(item.name).font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
            }
            .padding(.top, 24)
            measureEditor
            storagePicker
            Spacer()
            HStack {
                Button {
                    onRemove(item.id)
                } label: {
                    Text("REMOVE").font(.system(size: 10)).tracking(1.8)
                        .foregroundStyle(Theme.Palette.paprika)
                }
                .buttonStyle(.plain)
                Spacer()
                PaprikaButton(title: "Done") { onSave(item) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
    }

    @ViewBuilder private var measureEditor: some View {
        switch item.measure {
        case .perishable(let detail, let days):
            field("Amount") {
                // Structured number + approved-unit picker (no freeform "300 g" text),
                // pre-selecting the ingredient's default unit.
                AmountField(amount: Binding(
                    get: { detail.isEmpty ? nil : detail },
                    set: { item.measure = .perishable(detail: $0 ?? "", daysLeft: days) }),
                    defaultUnit: PantryCatalog.itemsByID[item.catalogItemID ?? ""]?.defaultUnit)
            }
            field("Days left") {
                HStack(spacing: 6) {
                    TextField("not tracked", text: Binding(
                        get: { item.daysLeft(now: today).map(String.init) ?? "" },
                        set: { raw in
                            let digits = raw.filter(\.isNumber)
                            // A typed estimate is "this many days from now", so re-anchor
                            // the freshness clock to today; empty clears tracking.
                            item.storageSince = today
                            item.consumedFraction = 0
                            item.measure = .perishable(detail: detail,
                                                       daysLeft: digits.isEmpty ? nil : Double(digits))
                        }))
                        .keyboardType(.numberPad)
                        .fixedSize()
                    if item.daysLeft(now: today) != nil { Text("days") }
                }
            }
        case .staple(let level):
            field("Presence") {
                HStack(spacing: 8) {
                    stapleChip("In stock", .inStock, level)
                    stapleChip("Running low", .runningLow, level)
                    stapleChip("Out", .out, level)
                }
            }
        case .made(let detail, let portions):
            field("Portions") {
                Stepper(portions.map { "\($0) \($0 == 1 ? "portion" : "portions")" } ?? "not counted",
                        value: Binding(get: { portions ?? 1 },
                                       set: { item.measure = .made(detail: detail, portions: $0) }),
                        in: 0...24)
            }
            field("Note") {
                TextField("e.g. frozen · good through July", text: Binding(
                    get: { detail },
                    set: { item.measure = .made(detail: $0, portions: portions) }))
            }
        }
    }

    private func stapleChip(_ title: String, _ value: StockItem.StapleLevel,
                            _ current: StockItem.StapleLevel) -> some View {
        let selected = value == current
        return Button { item.measure = .staple(value) } label: {
            Text(title.uppercased()).font(.system(size: 9)).tracking(1.4)
                .foregroundStyle(selected ? Theme.Palette.cream : Theme.Palette.ink.opacity(0.7))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Rectangle().fill(selected ? Theme.Palette.ink : .clear))
                .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(selected ? 0 : 0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Storage is first-class and editable anytime; changing it blends the
    /// freshness clock (proportional fraction-of-life) and re-projects days left.
    private var storagePicker: some View {
        field("Where it's kept") {
            HStack(spacing: 8) {
                ForEach([PantryStorage.pantry, .refrigerated, .frozen], id: \.self) { storage in
                    let selected = item.storage == storage
                    Button { item = item.moved(to: storage, now: today, adjustDaysLeft: adjustDaysOnStorageChange) } label: {
                        Text(storageLabel(storage)).font(.system(size: 9.5, weight: .medium)).tracking(1.2)
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

    private func storageLabel(_ s: PantryStorage) -> String {
        switch s { case .refrigerated: return "Fridge"; case .frozen: return "Freezer"; case .pantry: return "Pantry" }
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
}

/// "How much to buy?" — a tiny prompt shown when adding a low/expiring item to the
/// shopping list, so the amount is what the user wants, not a guessed default. The
/// current pack size is offered as an editable starting point.
private struct AddToListSheet: View {
    let prompt: StockView.ListPrompt
    var onAdd: (String?) -> Void
    var onCancel: () -> Void
    @State private var amount: String?

    init(prompt: StockView.ListPrompt, onAdd: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        self.prompt = prompt; self.onAdd = onAdd; self.onCancel = onCancel
        _amount = State(initialValue: prompt.suggested)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                PlateView(name: prompt.name, composition: prompt.plate, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Add to the list")
                    Text(prompt.name).font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
                }
            }
            .padding(.top, 22)
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "How much to buy?")
                AmountField(amount: $amount, defaultUnit: prompt.defaultUnit)
                    .font(Theme.Typography.fact(15)).foregroundStyle(Theme.Palette.ink)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Rectangle().fill(Theme.Palette.creamRaised))
                    .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(0.25), lineWidth: 1))
            }
            Spacer(minLength: 0)
            HStack {
                Button(action: onCancel) {
                    Text("CANCEL").font(.system(size: 10)).tracking(1.8).foregroundStyle(Theme.Palette.warmGray)
                }
                .buttonStyle(.plain)
                Spacer()
                PaprikaButton(title: "Add to list") { onAdd(amount) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
    }
}
