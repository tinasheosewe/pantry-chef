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
    @State private var cookSession: CookSession?

    /// One run of the cook instrument — a single dish, or several cooked together.
    struct CookSession: Identifiable { let id = UUID(); let dishes: [Dish] }

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
                onCook: { cookSession = CookSession(dishes: [dish]) },
                onClose: { detailDish = nil }
            )
        }
        .fullScreenCover(item: $cookSession) { session in
            CookFlowView(
                dishes: session.dishes,
                isOnHand: { store.onHand($0) },
                onDone: {
                    if let dish = session.dishes.first {
                        store.nowState = .cooked(CookedSummary(
                            name: session.dishes.count > 1 ? "Tonight's dishes" : dish.name,
                            plate: dish.plate,
                            summary: "Cooked — into the fridge. Good for a few days."))
                    }
                    cookSession = nil
                    detailDish = nil
                },
                onClose: { cookSession = nil }
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
            LibraryView(
                store: store,
                onCook: { dish in detailDish = dish },
                onCookTogether: { dishes in cookSession = CookSession(dishes: dishes) }
            )
        case .stock:
            StockView(store: store)
        }
    }

    private var nowBinding: Binding<NowState> {
        Binding(get: { store.nowState }, set: { store.nowState = $0 })
    }
}

#Preview { RedesignRootView() }
