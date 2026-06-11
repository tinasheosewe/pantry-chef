import SwiftUI

/// The warm-light backdrop shared by every redesign surface.
struct KitchenBackground: View {
    var body: some View {
        ZStack {
            Theme.Palette.cream
            RadialGradient(
                colors: [Theme.Palette.creamRaised.opacity(0.9), Theme.Palette.creamRaised.opacity(0)],
                center: .init(x: 0.5, y: 0.18), startRadius: 0, endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

/// The redesign's root: the three spaces under a floating glass dock, with the
/// composer as a sheet and the cook instrument as a full-screen cover. Driven by a
/// single `KitchenStore`.
struct RedesignRootView: View {
    @State private var store = KitchenStore()
    @State private var showComposer = false
    @State private var detailDish: Dish?
    @State private var cookingDish: Dish?

    var body: some View {
        ZStack(alignment: .bottom) {
            space
            Dock(
                selection: Binding(get: { store.space }, set: { store.space = $0 }),
                onAdd: { showComposer = true }
            )
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showComposer) {
            ComposerView(store: store, onDismiss: { showComposer = false })
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $detailDish) { dish in
            RecipeDetailView(
                dish: dish,
                readiness: store.readiness(for: dish),
                isOnHand: { store.onHand($0) },
                onCook: { cookingDish = dish },
                onClose: { detailDish = nil }
            )
        }
        .fullScreenCover(item: $cookingDish) { dish in
            CookFlowView(
                dish: dish,
                isOnHand: { store.onHand($0) },
                onDone: {
                    store.nowState = .cooked(CookedSummary(
                        name: dish.name, plate: dish.plate,
                        summary: "Cooked — 2 servings into the fridge. Good for 3 days."))
                    cookingDish = nil
                    detailDish = nil
                },
                onClose: { cookingDish = nil }
            )
        }
    }

    @ViewBuilder private var space: some View {
        switch store.space {
        case .timeline:
            TimelineView(
                entries: store.timelineEntries, today: store.today,
                onOpenMeal: { name in detailDish = store.library.first { $0.name == name } },
                nowContent: { AnyView(NowModuleView(state: nowBinding, onCook: { detailDish = $0.dish })) }
            )
        case .library:
            LibraryView(store: store, onCook: { dish in detailDish = dish })
        case .stock:
            StockView(store: store)
        }
    }

    private var nowBinding: Binding<NowState> {
        Binding(get: { store.nowState }, set: { store.nowState = $0 })
    }
}

#Preview { RedesignRootView() }
