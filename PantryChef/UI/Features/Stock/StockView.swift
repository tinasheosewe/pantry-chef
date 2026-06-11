import SwiftUI

/// Stock — have / need / made in one inventory (spec §3). Perishables show day
/// counts; staples show honest gauges, never a fake gram count (spec §7).
struct StockView: View {
    var store: KitchenStore

    private let order: [StockItem.Section] = [.made, .useSoon, .have, .staples]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metric.lg) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Stock").font(Theme.Typography.dish(26)).foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Text("\(store.stock.count) items").font(Theme.Typography.fact(12))
                        .foregroundStyle(Theme.Palette.warmGraySoft)
                }
                ForEach(order, id: \.rawValue) { section in
                    let items = store.stock.filter { $0.section == section }
                    if !items.isEmpty { sectionView(section, items) }
                }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 96)
        }
        .background(KitchenBackground())
    }

    private func sectionView(_ section: StockItem.Section, _ items: [StockItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.rawValue.uppercased()).font(Theme.Typography.eyebrow)
                .tracking(Theme.Metric.eyebrowTracking)
                .foregroundStyle(section == .useSoon ? Theme.Palette.ochre : Theme.Palette.warmGraySoft)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    StockRow(item: item)
                    if item.id != items.last?.id {
                        Divider().background(Theme.Palette.hairline)
                    }
                }
            }
            .padding(14).glassCard(cornerRadius: 22)
        }
    }
}

private struct StockRow: View {
    let item: StockItem

    var body: some View {
        HStack(spacing: 11) {
            PlateView(composition: item.plate, size: Theme.Metric.plateMini)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
                detail
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder private var detail: some View {
        switch item.measure {
        case .made(let d):
            Label(d, systemImage: "snowflake").labelStyle(.titleAndIcon)
                .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
        case .perishable(let d, _):
            Text(d).font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
        case .staple(let level):
            Text(level.label).font(Theme.Typography.fact(11))
                .foregroundStyle(level == .inStock ? Theme.Palette.warmGraySoft : Theme.Palette.ochre)
        }
    }

    @ViewBuilder private var trailing: some View {
        if case .perishable(_, let days?) = item.measure {
            Text("\(days)d").font(Theme.Typography.numeral(12))
                .foregroundStyle(days <= 3 ? Theme.Palette.ochre : Theme.Palette.warmGraySoft)
        }
    }
}

