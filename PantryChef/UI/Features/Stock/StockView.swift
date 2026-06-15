import SwiftUI

/// Stores — the inventory as a printed ledger (spec §3, Field Notes). The kitchen
/// speaks first in a sentence; then PERISHING FIRST with day counts on dotted
/// leaders, STAPLES with honest presence tags (never a fake gauge, spec §7),
/// MADE BY YOU, and THE LIST. Rows are tappable → editor.
struct StockView: View {
    var store: KitchenStore

    @State private var editing: StockItem?
    @State private var shopping = false

    private var allPerishable: [StockItem] {
        store.stock
            .filter { if case .perishable = $0.measure { return true } else { return false } }
            .sorted { (days($0) ?? .max) < (days($1) ?? .max) }
    }
    /// Distinct sections, not one long sorted list: things to use NOW vs. the
    /// rest of the fridge.
    private var perishingFirst: [StockItem] {
        allPerishable.filter { (days($0) ?? .max) <= KitchenConfig.Stores.perishingSoonDays }
    }
    private var inStock: [StockItem] {
        allPerishable.filter { (days($0) ?? .max) > KitchenConfig.Stores.perishingSoonDays }
    }
    // Group by the item's *measure*, the single source of truth, so an item can
    // never disagree with itself and vanish (reactivity audit P1/P2). Perishables
    // split by urgency (days), staples and leftovers by kind.
    private var staples: [StockItem] {
        store.stock.filter { if case .staple = $0.measure { return true } else { return false } }
    }
    private var made: [StockItem] {
        store.stock.filter { if case .made = $0.measure { return true } else { return false } }
    }

    private func days(_ item: StockItem) -> Int? {
        if case .perishable(_, let d) = item.measure { return d }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stores").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                Text(summary)
                    .font(Theme.Typography.note(11.5)).foregroundStyle(Theme.Palette.warmGray)
                    .fixedSize(horizontal: false, vertical: true)
                DashedRule().padding(.top, 6)
            }
            .padding(.horizontal, 20).padding(.top, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !perishingFirst.isEmpty {
                        section("Perishing first", perishingFirst, tone: .urgent)
                    }
                    if !inStock.isEmpty {
                        section("In stock", inStock)
                    }
                    if !staples.isEmpty {
                        section("Staples", staples)
                    }
                    if !made.isEmpty {
                        section("Made by you", made)
                    }
                    if !store.shoppingList.isEmpty { listSection }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .background(KitchenBackground())
        .sheet(item: $editing) { item in
            StockItemEditor(
                item: item,
                adjustDaysOnStorageChange: store.autoAdjustDaysOnStorageChange,
                onSave: { store.updateStock($0); editing = nil },
                onRemove: { store.removeStock($0); editing = nil }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $shopping) {
            ShoppingChecklistView(store: store) { shopping = false }
        }
    }

    /// One labelled ledger block, divided from the next by a rule.
    @ViewBuilder private func section(_ title: String, _ items: [StockItem],
                                     tone: Eyebrow.Tone = .quiet) -> some View {
        Eyebrow(text: title, tone: tone).padding(.top, 14)
        ForEach(items) { item in row(item) }
        DashedRule().padding(.top, 11)
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
            checkTag("Still here") { withAnimation { store.reconfirm(item.id) } }
            checkTag("Low") { withAnimation { store.markLow(item.id) } }
            checkTag("Gone", urgent: true) { withAnimation { store.markGone(item.id) } }
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
        EmojiPlate.face(for: item.name, categories: item.plate.weights.map(\.category))
    }

    @ViewBuilder private func trailing(_ item: StockItem) -> some View {
        switch item.measure {
        case .perishable(let detail, let d):
            HStack(spacing: 8) {
                Text(detail.uppercased())
                    .font(.system(size: 10)).tracking(0.8)
                    .foregroundStyle(Theme.Palette.warmGraySoft)
                if let d {
                    Text(d == 1 ? "1 DAY" : "\(d) DAYS")
                        .font(Theme.Typography.dish(11, weight: .semibold))
                        .foregroundStyle(d <= 3 ? Theme.Palette.paprika : Theme.Palette.warmGray)
                }
            }
        case .staple(let level):
            switch level {
            case .inStock: OutlineTag(text: "In")
            case .runningLow: OutlineTag(text: "Low — listed", tone: .urgent)
            case .out: OutlineTag(text: "Out", tone: .urgent)
            }
        case .made(let detail):
            Text(detail.uppercased())
                .font(.system(size: 10)).tracking(0.8)
                .foregroundStyle(Theme.Palette.warmGray)
                .lineLimit(1)
        }
    }

    /// A read-only preview — managing the list (amounts, bought, removal) happens in
    /// the Shop run, so there's one place to keep it in sync. The whole section taps
    /// through to Shop.
    private var listSection: some View {
        Button { shopping = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow(text: "The list — \(store.shoppingList.count)", tone: .urgent)
                    Spacer()
                    Text("SHOP →").font(.system(size: 11, weight: .medium)).tracking(1.4)
                        .foregroundStyle(Theme.Palette.paprika)
                }
                .padding(.top, 14)
                ForEach(store.shoppingList) { entry in
                    HStack(spacing: 9) {
                        PlateView(name: entry.name, composition: store.plate(forName: entry.name), size: 26)
                        Text(entry.name).font(Theme.Typography.fact(13.5)).foregroundStyle(Theme.Palette.ink)
                        if let amount = entry.amount {
                            Text(amount).font(Theme.Typography.fact(11.5)).foregroundStyle(Theme.Palette.warmGraySoft)
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 5)
                    if entry.id != store.shoppingList.last?.id { DashedRule(opacity: 0.5) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Edit one stock item: amount/detail, days left or staple level, section, remove.
private struct StockItemEditor: View {
    @State var item: StockItem
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
                TextField("e.g. 300 g", text: Binding(
                    get: { detail },
                    set: { item.measure = .perishable(detail: $0, daysLeft: days) }))
            }
            field("Days left") {
                Stepper(days.map { "\($0) days" } ?? "not tracked",
                        value: Binding(get: { days ?? 7 },
                                       set: { item.measure = .perishable(detail: detail, daysLeft: $0) }),
                        in: 0...60)
            }
        case .staple(let level):
            field("Presence") {
                HStack(spacing: 8) {
                    stapleChip("In stock", .inStock, level)
                    stapleChip("Running low", .runningLow, level)
                    stapleChip("Out", .out, level)
                }
            }
        case .made(let detail):
            field("Portions") {
                TextField("e.g. 3 frozen portions", text: Binding(
                    get: { detail },
                    set: { item.measure = .made(detail: $0) }))
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
                    Button { item = item.moved(to: storage, now: Date(), adjustDaysLeft: adjustDaysOnStorageChange) } label: {
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
