import SwiftUI

/// Stock — have / need / made in one inventory (spec §3). Perishables show day
/// counts; staples show honest presence, never a fake fullness (spec §7). Rows are
/// tappable → editor; the shopping list lives here too.
struct StockView: View {
    var store: KitchenStore

    @State private var editing: StockItem?

    private let order: [StockItem.Section] = [.made, .useSoon, .have, .staples]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                // One continuous card: section labels inline, compact rows.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(order, id: \.rawValue) { section in
                        let items = store.stock.filter { $0.section == section }
                        if !items.isEmpty { sectionView(section, items) }
                    }
                    if !store.shoppingList.isEmpty { listSection }
                }
                .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 10)
                .glassCard(cornerRadius: 22)
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 96)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Stock").font(Theme.Typography.dish(26)).foregroundStyle(Theme.Palette.ink)
            Spacer()
            Text("\(store.stock.count) items").font(Theme.Typography.fact(12))
                .foregroundStyle(Theme.Palette.warmGraySoft)
        }
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
    }

    private func sectionView(_ section: StockItem.Section, _ items: [StockItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.rawValue.uppercased()).font(Theme.Typography.eyebrow)
                .tracking(Theme.Metric.eyebrowTracking)
                .foregroundStyle(section == .useSoon ? Theme.Palette.ochre : Theme.Palette.warmGraySoft)
                .padding(.top, 11).padding(.bottom, 2)
            ForEach(items) { item in
                Button { editing = item } label: {
                    StockRow(item: item).contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                if item.id != items.last?.id {
                    Divider().background(Theme.Palette.hairline)
                }
            }
        }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ON THE LIST").font(Theme.Typography.eyebrow).tracking(Theme.Metric.eyebrowTracking)
                .foregroundStyle(Theme.Palette.paprika)
                .padding(.top, 11).padding(.bottom, 2)
            ForEach(store.shoppingList, id: \.self) { entry in
                HStack(spacing: 9) {
                    Image(systemName: "cart").font(.system(size: 12)).foregroundStyle(Theme.Palette.warmGraySoft)
                    Text(entry).font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Button {
                        withAnimation { store.removeFromList(entry) }
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                            .foregroundStyle(Theme.Palette.warmGraySoft.opacity(0.6))
                            .frame(width: 32, height: 30)
                    }
                    .buttonStyle(.plain)
                }
                if entry != store.shoppingList.last {
                    Divider().background(Theme.Palette.hairline)
                }
            }
        }
    }
}

/// One compact line per item: plate · name · detail (truncating) · day count.
private struct StockRow: View {
    let item: StockItem

    var body: some View {
        HStack(spacing: 9) {
            PlateView(name: item.name, composition: item.plate, size: 27)
            Text(item.name).font(Theme.Typography.fact(13.5)).foregroundStyle(Theme.Palette.ink)
                .lineLimit(1).layoutPriority(1)
            Spacer(minLength: 8)
            detail
            trailing
            Image(systemName: "chevron.right").font(.system(size: 10))
                .foregroundStyle(Theme.Palette.warmGraySoft.opacity(0.5))
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var detail: some View {
        switch item.measure {
        case .made(let d):
            Label(d, systemImage: "snowflake").labelStyle(.titleAndIcon)
                .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
                .lineLimit(1)
        case .perishable(let d, _):
            Text(d).font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
                .lineLimit(1)
        case .staple(let level):
            Text(level.shortLabel).font(Theme.Typography.fact(11))
                .foregroundStyle(level == .inStock ? Theme.Palette.warmGraySoft : Theme.Palette.ochre)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var trailing: some View {
        if case .perishable(_, let days?) = item.measure {
            Text("\(days)d").font(Theme.Typography.numeral(12))
                .foregroundStyle(days <= 3 ? Theme.Palette.ochre : Theme.Palette.warmGraySoft)
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
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            HStack(spacing: 11) {
                PlateView(name: item.name, composition: item.plate, size: 38)
                Text(item.name).font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
            }
            measureEditor
            sectionPicker
            Spacer()
            HStack {
                Button {
                    onRemove(item.id)
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ochre)
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
            Text(title).font(Theme.Typography.fact(12))
                .foregroundStyle(selected ? Theme.Palette.cream : Theme.Palette.warmGray)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(selected ? Theme.Palette.ink : Color.clear))
                .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private var sectionPicker: some View {
        field("Where it lives") {
            HStack(spacing: 8) {
                ForEach([StockItem.Section.useSoon, .have, .staples, .made], id: \.rawValue) { section in
                    let selected = item.section == section
                    Button { item.section = section } label: {
                        Text(section.rawValue).font(Theme.Typography.fact(11))
                            .foregroundStyle(selected ? Theme.Palette.cream : Theme.Palette.warmGray)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(selected ? Theme.Palette.ink : Color.clear))
                            .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Theme.Typography.eyebrow).tracking(Theme.Metric.eyebrowTracking)
                .foregroundStyle(Theme.Palette.warmGraySoft)
            content()
                .font(Theme.Typography.fact(15)).foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.Palette.hairline))
        }
    }
}
