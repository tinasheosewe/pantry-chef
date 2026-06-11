import SwiftUI

/// Library — the plate gallery (spec §3/§6). Readiness is the first-class fact on
/// every cell, computed live by the one ReadinessService from current stock.
struct LibraryView: View {
    var store: KitchenStore
    var onCook: (LibraryDish) -> Void = { _ in }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Library").font(Theme.Typography.dish(26)).foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Text("\(store.library.count)").font(Theme.Typography.fact(12))
                        .foregroundStyle(Theme.Palette.warmGraySoft)
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(store.library) { dish in
                        LibraryCell(dish: dish, readiness: store.readiness(for: dish))
                            .onTapGesture { onCook(dish) }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 96)
        }
        .background(KitchenBackground())
    }
}

private struct LibraryCell: View {
    let dish: LibraryDish
    let readiness: Readiness

    var body: some View {
        VStack(spacing: 10) {
            PlateView(composition: dish.plate, size: 70)
            VStack(spacing: 3) {
                Text(dish.name).font(Theme.Typography.dish(14)).foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center).lineLimit(2)
                statusLine
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 8)
        .glassCard(cornerRadius: 20)
    }

    @ViewBuilder private var statusLine: some View {
        switch readiness {
        case .ready:
            Text("\(dish.time) · ready").font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage)
        case .readyWithSwaps(let swaps):
            Text("ready · \(swaps.first.map { "\($0.fromName) → \($0.toName)" } ?? "with a swap")")
                .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage)
                .lineLimit(1)
        case .needs(let items):
            Text(dish.isYours ? "your dish · \(dish.time)" : "needs \(items.count)")
                .font(Theme.Typography.fact(11))
                .foregroundStyle(dish.isYours ? Theme.Palette.paprika : Theme.Palette.ochre)
        }
    }
}
