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

/// One run of the cook instrument — a single dish, or several cooked together.
struct CookSession: Identifiable {
    let id = UUID()
    let dishes: [Dish]
}

/// A day the user tapped to plan.
private struct PlanTarget: Identifiable {
    let id = UUID()
    let date: Date
}

/// The redesign's root: the three spaces under a floating glass dock, with the
/// composer as a sheet and the cook instrument as a full-screen cover. Driven by a
/// single `KitchenStore`.
struct RedesignRootView: View {
    @State private var store = KitchenStore()
    @State private var showComposer = false
    @State private var detailDish: Dish?
    @State private var multiSession: CookSession?
    @State private var planTarget: PlanTarget?

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
        .sheet(item: $planTarget) { target in
            PlanDaySheet(store: store, date: target.date) { dish in
                store.planMeal(dish, on: target.date)
                planTarget = nil
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $detailDish) { dish in
            // Cook is presented from *inside* this cover (a second cover on the
            // same presenter never appears until the first dismisses).
            RecipeDetailScreen(store: store, dish: dish, onClose: { detailDish = nil })
        }
        .fullScreenCover(item: $multiSession) { session in
            CookFlowScreen(store: store, session: session, onClose: { multiSession = nil })
        }
    }

    @ViewBuilder private var space: some View {
        switch store.space {
        case .timeline:
            TimelineView(
                entries: store.timelineEntries,
                today: store.today,
                onTapDay: { planTarget = PlanTarget(date: $0) },
                onOpenMeal: { name in detailDish = store.dish(named: name) },
                onDismissProposal: { id in withAnimation { store.dismissProposal(id) } },
                onOpenStock: { store.space = .stock },
                onReachStart: { store.extendPast() },
                onReachEnd: { store.extendFuture() },
                nowContent: {
                    AnyView(NowModuleView(
                        state: Binding(get: { store.nowState }, set: { store.nowState = $0 }),
                        onCook: { option in detailDish = option.dish },
                        onSeeAll: {
                            store.libraryFilter = .ready
                            withAnimation { store.space = .library }
                        },
                        onChange: { store.resetNow() },
                        onResume: {
                            if case .cooking(let p) = store.nowState, let dish = p.dish {
                                multiSession = CookSession(dishes: [dish])
                            }
                        }
                    ))
                }
            )
        case .library:
            LibraryView(
                store: store,
                onCook: { dish in detailDish = dish },
                onCookTogether: { dishes in multiSession = CookSession(dishes: dishes) }
            )
        case .stock:
            StockView(store: store)
        }
    }
}

/// The recipe detail with its own nested cook presentation, so "Cook" works while
/// the detail is showing.
private struct RecipeDetailScreen: View {
    var store: KitchenStore
    let dish: Dish
    var onClose: () -> Void
    @State private var session: CookSession?

    var body: some View {
        RecipeDetailView(
            dish: dish,
            readiness: store.readiness(for: dish),
            isOnHand: { store.onHand($0) },
            onCook: { effective in session = CookSession(dishes: [effective]) },
            onClose: onClose
        )
        .fullScreenCover(item: $session) { s in
            CookFlowScreen(store: store, session: s, onClose: { session = nil }, onFinished: onClose)
        }
    }
}

/// CookFlowView wired to the store: live now-module progress, cooked state on
/// done, reset on abandon.
private struct CookFlowScreen: View {
    var store: KitchenStore
    let session: CookSession
    var onClose: () -> Void
    var onFinished: () -> Void = {}

    var body: some View {
        CookFlowView(
            dishes: session.dishes,
            isOnHand: { store.onHand($0) },
            onStep: { index, total in store.beginCooking(session.dishes, stepIndex: index, totalSteps: total) },
            onDone: {
                store.finishCooking(session.dishes)
                onClose()
                onFinished()
            },
            onClose: {
                store.resetNow()
                onClose()
            }
        )
    }
}

/// Pick a dish to plan onto a tapped day.
private struct PlanDaySheet: View {
    var store: KitchenStore
    let date: Date
    var onPlan: (Dish) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            Text("Plan \(DayLabel.full(for: date))").font(Theme.Typography.dish(20))
                .foregroundStyle(Theme.Palette.ink).padding(.top, 14)
            Text("Pick something — missing items go to your list.")
                .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGraySoft).padding(.top, 2)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.library) { dish in
                        Button { onPlan(dish) } label: {
                            HStack(spacing: 11) {
                                PlateView(composition: dish.plate, size: Theme.Metric.plateMini)
                                Text(dish.name).font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
                                Spacer()
                                readinessLabel(for: dish)
                            }
                            .padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if dish.id != store.library.last?.id { Divider().background(Theme.Palette.hairline) }
                    }
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .background(KitchenBackground())
    }

    @ViewBuilder private func readinessLabel(for dish: Dish) -> some View {
        switch store.readiness(for: dish) {
        case .ready: Text("ready").font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage)
        case .readyWithSwaps: Text("with a swap").font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage)
        case .needs(let items): Text("needs \(items.count)").font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.ochre)
        }
    }
}

#Preview { RedesignRootView() }
