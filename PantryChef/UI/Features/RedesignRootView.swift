import SwiftUI

/// The page itself: flat paper, no glow — Field Notes is printed, not lit.
struct KitchenBackground: View {
    var body: some View {
        Theme.Palette.cream.ignoresSafeArea()
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

/// The redesign's root: the three spaces over the printed page floor (rule + nav
/// band + tailpiece), with the composer as a sheet and the cook instrument as a
/// full-screen cover. Driven by a single `KitchenStore`.
struct RedesignRootView: View {
    @State private var store = KitchenStore()
    @State private var showComposer = false
    @State private var detailDish: Dish?
    @State private var multiSession: CookSession?
    @State private var planTarget: PlanTarget?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack { space }
            .id(store.space)
            .transition(reduceMotion ? .opacity : .pageTurn)
            .animation(.paper, value: store.space)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Dock(
                    selection: Binding(get: { store.space }, set: { store.space = $0 }),
                    onAdd: { showComposer = true },
                    tailpiece: tailpiece
                )
            }
            .background(KitchenBackground())
            // Support Dynamic Type, but bound the extreme sizes so the editorial
            // page composition still holds (accessibility pass).
            .dynamicTypeSize(.xSmall ... .accessibility2)
            .preferredColorScheme(ThemeManager.shared.spec.isDark ? .dark : .light)
            // Foregrounding re-checks the clock (the page may invert for evening)
            // and forgives failed plate renders — the network may be back.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    ThemeManager.shared.refresh()
                    PlateRenderLibrary.shared.sweep()
                }
            }
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

    /// One true line per page (the mock's "№ 163 · sunset 21:43").
    private var tailpiece: String {
        let ready = store.library.filter { store.readiness(for: $0).isMakeableNow }.count
        switch store.space {
        case .timeline:
            let dayNumber = Calendar.current.ordinality(of: .day, in: .year, for: store.today) ?? 0
            return "№ \(dayNumber) · \(ready) ready tonight"
        case .library:
            return "\(store.library.count) dishes · \(ready) ready"
        case .stock:
            return "\(store.stock.count) items · \(store.shoppingList.count) on the list"
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
                    AnyView(VStack(alignment: .leading, spacing: 0) {
                        NowModuleView(
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
                        )
                        OnTheClockSection(store: store) { withAnimation { store.space = .stock } }
                        KitchenLedger(
                            store: store,
                            onReady: { store.libraryFilter = .ready; withAnimation { store.space = .library } },
                            onStock: { withAnimation { store.space = .stock } }
                        )
                    })
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
            certaintyForKey: { store.certainty(forKey: $0) },
            onToggleFavorite: { store.toggleFavorite(dish.id) },
            onUpdateDish: { store.updateDish($0) },
            onAddMissingToList: { lines in lines.forEach { store.addToList(name: $0.name, amount: $0.amount) } },
            makeHealthier: { d in
                await store.ai.makeItHealthier(recipe: DishBridge.recipe(from: d))
            },
            tweak: { d, feedback in
                let result = await store.ai.modifyRecipe(
                    DishBridge.recipe(from: d), feedback: feedback,
                    pantryIngredients: store.stock.map(\.name))
                return result?.recipe.map { DishBridge.dish(from: $0, replacing: d) }
            },
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

/// ON THE CLOCK — the expiring ledger under the now-module: each perishable on a
/// dotted leader with its days, tomato when it's urgent. One tap from Stores.
private struct OnTheClockSection: View {
    var store: KitchenStore
    var onOpen: () -> Void

    private var items: [StockItem] {
        store.stock
            .compactMap { item -> (StockItem, Int)? in
                if case .perishable(_, let days?) = item.measure, days <= 5 { return (item, days) }
                return nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    var body: some View {
        if !items.isEmpty {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 7) {
                    DashedRule()
                    Eyebrow(text: "On the clock", tone: .urgent).padding(.top, 4)
                    ForEach(items.prefix(3)) { item in
                        if case .perishable(let detail, let days?) = item.measure {
                            LeaderRow {
                                Text("\(EmojiPlate.face(for: item.name, categories: item.plate.weights.map(\.category)))\u{2002}\(item.name) — \(detail)")
                                    .font(Theme.Typography.fact(12.5))
                                    .foregroundStyle(Theme.Palette.ink)
                                    .lineLimit(1)
                            } trailing: {
                                Text(days == 1 ? "1 day" : "\(days) days")
                                    .font(Theme.Typography.fact(12))
                                    .foregroundStyle(days <= 3 ? Theme.Palette.paprika : Theme.Palette.warmGray)
                            }
                        }
                    }
                }
                .padding(.top, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The kitchen at a glance, set as a two-column note above the page floor — each
/// column a door to its space.
private struct KitchenLedger: View {
    var store: KitchenStore
    var onReady: () -> Void
    var onStock: () -> Void

    var body: some View {
        let ready = store.library.filter { store.readiness(for: $0).isMakeableNow }.count
        VStack(alignment: .leading, spacing: 0) {
            DashedRule().padding(.top, 12)
            HStack(alignment: .top, spacing: 12) {
                Button(action: onReady) {
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "Ready tonight")
                        Text("\(ready) \(ready == 1 ? "dish" : "dishes") — no shopping")
                            .font(Theme.Typography.fact(11.5))
                            .foregroundStyle(Theme.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: onStock) {
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "The stores")
                        Text("\(store.stock.count) in · \(store.shoppingList.count) on the list")
                            .font(Theme.Typography.fact(11.5))
                            .foregroundStyle(Theme.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.clear)
                            .frame(width: 1)
                            .overlay(VerticalDashedRule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 9)
        }
    }
}

/// A vertical dashed hand-rule (column dividers).
struct VerticalDashedRule: View {
    var body: some View {
        VLine()
            .stroke(Theme.Palette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: 1)
    }

    private struct VLine: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: 0))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.height))
            return p
        }
    }
}

/// Pick a dish to plan onto a tapped day.
private struct PlanDaySheet: View {
    var store: KitchenStore
    let date: Date
    var onPlan: (Dish) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Plan \(DayLabel.full(for: date))").font(Theme.Typography.dish(20))
                .foregroundStyle(Theme.Palette.ink).padding(.top, 22)
            Text("Pick something — missing items go to your list.")
                .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGray).padding(.top, 3)
            DashedRule().padding(.top, 10)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.library) { dish in
                        Button { onPlan(dish) } label: {
                            LeaderRow {
                                HStack(spacing: 9) {
                                    PlateView(name: dish.name, composition: dish.plate, size: 26)
                                    Text(dish.name).font(Theme.Typography.dish(14)).foregroundStyle(Theme.Palette.ink)
                                }
                            } trailing: {
                                readinessLabel(for: dish)
                            }
                            .padding(.vertical, 9).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if dish.id != store.library.last?.id { DashedRule(opacity: 0.5) }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .background(KitchenBackground())
    }

    @ViewBuilder private func readinessLabel(for dish: Dish) -> some View {
        switch store.readiness(for: dish) {
        case .ready: Text("READY").font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.sage)
        case .readyWithSwaps: Text("WITH A SWAP").font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.sage)
        case .needs(let items): Text("NEEDS \(items.count)").font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.paprika)
        }
    }
}

#Preview { RedesignRootView() }
