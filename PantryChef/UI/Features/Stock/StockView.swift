import SwiftUI

/// Stores — the inventory as a printed ledger (spec §3, Field Notes). The kitchen
/// speaks first in a sentence; then PERISHING FIRST with day counts on dotted
/// leaders, STAPLES with honest presence tags (never a fake gauge, spec §7),
/// MADE BY YOU, and THE LIST. Rows are tappable → editor.
struct StockView: View {
    var store: KitchenStore

    @State private var editing: StockItem?

    private var perishables: [StockItem] {
        store.stock
            .filter { if case .perishable = $0.measure { return true } else { return false } }
            .sorted { days($0) ?? .max < days($1) ?? .max }
    }
    private var staples: [StockItem] { store.stock.filter { $0.section == .staples } }
    private var made: [StockItem] { store.stock.filter { $0.section == .made } }

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
                    if !perishables.isEmpty {
                        Eyebrow(text: "Perishing first", tone: .urgent).padding(.top, 12)
                        ForEach(perishables) { item in row(item) }
                        DashedRule().padding(.top, 10)
                    }
                    if !staples.isEmpty {
                        Eyebrow(text: "Staples").padding(.top, 12)
                        ForEach(staples) { item in row(item) }
                        DashedRule().padding(.top, 10)
                    }
                    if !made.isEmpty {
                        Eyebrow(text: "Made by you").padding(.top, 12)
                        ForEach(made) { item in row(item) }
                        DashedRule().padding(.top, 10)
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
                onSave: { store.updateStock($0); editing = nil },
                onRemove: { store.removeStock($0); editing = nil }
            )
            .presentationDetents([.medium])
        }
    }

    /// "7 things in. The spinach wants using; staples are solid; 5 wait on the list."
    private var summary: String {
        var parts: [String] = ["\(store.stock.count) things in."]
        if let urgent = perishables.first, let d = days(urgent), d <= 3 {
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

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "The list — \(store.shoppingList.count)", tone: .urgent).padding(.top, 12)
            FlowLayoutRow(items: store.shoppingList) { entry in
                Button {
                    withAnimation { store.removeFromList(entry) }
                } label: {
                    HStack(spacing: 4) {
                        Text(entry).font(Theme.Typography.fact(12.5)).foregroundStyle(Theme.Palette.ink)
                        Image(systemName: "xmark").font(.system(size: 7))
                            .foregroundStyle(Theme.Palette.ink.opacity(0.4))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A wrapping run of items separated like a printed line.
private struct FlowLayoutRow<Content: View>: View {
    let items: [String]
    @ViewBuilder let content: (String) -> Content

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 84), spacing: 10)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

/// Edit one stock item: amount/detail, days left or staple level, section, remove.
private struct StockItemEditor: View {
    @State var item: StockItem
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
            sectionPicker
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

    private var sectionPicker: some View {
        field("Where it lives") {
            HStack(spacing: 8) {
                ForEach([StockItem.Section.useSoon, .have, .staples, .made], id: \.rawValue) { section in
                    let selected = item.section == section
                    Button { item.section = section } label: {
                        Text(section.rawValue.uppercased()).font(.system(size: 8.5)).tracking(1.2)
                            .foregroundStyle(selected ? Theme.Palette.cream : Theme.Palette.ink.opacity(0.7))
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Rectangle().fill(selected ? Theme.Palette.ink : .clear))
                            .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(selected ? 0 : 0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
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
}
