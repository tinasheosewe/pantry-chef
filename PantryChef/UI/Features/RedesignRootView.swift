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
    @State private var cooking: FanOption?

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
        .fullScreenCover(item: $cooking) { option in
            CookInstrumentView(
                option: option,
                onDone: {
                    store.nowState = .cooked(CookedSummary(
                        name: option.name, plate: option.plate,
                        summary: "Cooked — 2 servings into the fridge. Good for 3 days."))
                    cooking = nil
                },
                onClose: { cooking = nil }
            )
        }
    }

    @ViewBuilder private var space: some View {
        switch store.space {
        case .timeline:
            TimelineView(
                entries: store.timelineEntries, today: store.today,
                nowContent: { AnyView(NowModuleView(state: nowBinding, onCook: { cooking = $0 })) }
            )
        case .library:
            LibraryView(store: store, onCook: { dish in
                cooking = FanOption(name: dish.name, plate: dish.plate, subtitle: dish.time, reason: "")
            })
        case .stock:
            StockView(store: store)
        }
    }

    private var nowBinding: Binding<NowState> {
        Binding(get: { store.nowState }, set: { store.nowState = $0 })
    }
}

#Preview { RedesignRootView() }
