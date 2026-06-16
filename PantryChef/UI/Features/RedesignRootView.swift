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
    @State private var showSettings = false
    @State private var showPlanAhead = false
    @State private var detailDish: Dish?
    @State private var multiSession: CookSession?
    @State private var planTarget: PlanTarget?
    @State private var editingMeal: PlannedMeal?
    /// A heat-and-eat meal being logged — drives the "how much is left?" prompt.
    @State private var loggingMeal: PlannedMeal?
    /// When a meal is planned for now, the now-module leads with it; this reveals the
    /// generic "you could…" suggestions instead, on demand.
    @State private var showSuggestions = false
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
                    store.today = Date()          // un-freeze the knowledge clock
                    showSuggestions = false       // let the plan lead again
                    ThemeManager.shared.refresh()
                    PlateRenderLibrary.shared.sweep()
                }
            }
            .sheet(isPresented: $showComposer) {
                ComposerView(store: store, onDismiss: { showComposer = false })
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(store: store, onClose: { showSettings = false })
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showPlanAhead) {
                PlanAheadSheet(
                    onPick: { date in
                        showPlanAhead = false
                        // Hand off to the day planner on the next tick — presenting a
                        // sheet while another dismisses in the same runloop no-ops it.
                        DispatchQueue.main.async { planTarget = PlanTarget(date: date) }
                    },
                    onClose: { showPlanAhead = false })
                    .presentationDetents([.medium])
            }
            .sheet(item: $planTarget) { target in
                PlanDaySheet(
                    store: store, date: target.date,
                    onPlan: { dish, part in store.planMeal(dish, on: target.date, part: part); planTarget = nil },
                    onPlanLeftover: { item, part in store.planLeftover(item, on: target.date, part: part); planTarget = nil })
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $editingMeal) { meal in
                PlannedMealSheet(
                    meal: meal,
                    onSetPart: { store.setMealPart(meal.id, to: $0) },
                    onSetServings: { store.setMealServings(meal.id, to: $0) },
                    onAct: { servings in
                        store.setMealServings(meal.id, to: servings)
                        editingMeal = nil
                        var acted = meal; acted.servings = servings
                        // Defer so this sheet finishes dismissing before the next one
                        // (cook cover / leftover prompt) presents.
                        DispatchQueue.main.async { actOnPlan(acted) }
                    },
                    onRemove: { store.removeMeal(meal.id); editingMeal = nil })
                .presentationDetents([.medium])
            }
            .sheet(item: $loggingMeal) { meal in
                ServingsOutcomeSheet(
                    meal: meal,
                    available: store.availablePortions(named: meal.name) ?? meal.servings,
                    onLog: { kept in withAnimation { store.logPlannedMeal(meal, kept: kept) }; loggingMeal = nil })
                .presentationDetents([.height(280)])
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

    /// The now-module is idle (no cook/commit in flight), so a plan may lead it.
    private var isIdleNow: Bool { if case .open = store.nowState { return true } else { return false } }

    /// Act on a planned meal: cook a recipe (instrument, scaled to its servings) or
    /// log a heat-and-eat one as eaten.
    private func actOnPlan(_ meal: PlannedMeal) {
        if meal.isCookable {
            detailDish = store.dish(named: meal.name)?.scaled(to: meal.servings)
        } else {
            // Heat-and-eat: ask what's left only when there's more than one portion in
            // play (the moment you actually know — not a guess made ahead of time).
            let available = store.availablePortions(named: meal.name) ?? meal.servings
            if available > 1 { loggingMeal = meal }
            else { withAnimation { store.logPlannedMeal(meal, kept: 0) } }
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
                onTapMeal: { editingMeal = $0 },
                onDismissProposal: { id in withAnimation { store.dismissProposal(id) } },
                onOpenStock: { store.space = .stock },
                onPlanAhead: { showPlanAhead = true },
                onSettings: { showSettings = true },
                nowContent: {
                    AnyView(VStack(alignment: .leading, spacing: 0) {
                        if isIdleNow, let plan = store.planForNow, !showSuggestions {
                            // A meal is planned for now — it leads, with the generic
                            // "you could…" suggestions one tap away.
                            PlannedNowView(
                                meal: plan,
                                onAct: { actOnPlan(plan) },
                                onEdit: { editingMeal = plan },
                                onSeeOptions: { withAnimation { showSuggestions = true } })
                        } else {
                            NowModuleView(
                                state: Binding(get: { store.nowState }, set: { store.nowState = $0 }),
                                onCook: { option in
                                    // A cookable dish opens the instrument; a ready-made
                                    // pick is just logged as eaten.
                                    if option.level.usesInstrument, let dish = option.dish {
                                        detailDish = dish
                                    } else {
                                        store.logEaten(option)
                                    }
                                },
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
                        }
                        TodayPlanView(
                            store: store,
                            excluding: (isIdleNow && !showSuggestions) ? store.planForNow?.id : nil,
                            onTapMeal: { editingMeal = $0 },
                            onAdd: { planTarget = PlanTarget(date: store.today) })
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
            onSaveAsNew: { store.addDish($0) },
            onAddMissingToList: { lines in lines.forEach { store.addToList(name: $0.name, amount: $0.amount) } },
            makeHealthier: { d in
                await store.ai.makeItHealthier(dish: d)
            },
            tweak: { d, feedback in
                await store.ai.modifyRecipe(d, feedback: feedback,
                                            pantryIngredients: store.stock.map(\.name),
                                            avoid: store.profile.avoided.map(\.title))
            },
            autofill: { await store.ai.generateIngredientDefinition(name: $0) },
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
/// Today's committed meals, shown at the now-module — the future ruler starts at
/// tomorrow, so this is where a plan made *for today* lives. Also the entry point to
/// plan something for today (plan dinner in the morning, etc.).
private struct TodayPlanView: View {
    var store: KitchenStore
    /// The meal the now-module is already foregrounding, so we don't list it twice.
    var excluding: UUID? = nil
    var onTapMeal: (PlannedMeal) -> Void
    var onAdd: () -> Void

    var body: some View {
        let all = store.todaysPlannedMeals
        let meals = all.filter { $0.id != excluding }
        VStack(alignment: .leading, spacing: 8) {
            if meals.isEmpty {
                addLine(all.isEmpty ? "+ PLAN SOMETHING FOR TODAY" : "+ ADD TO TODAY")
            } else {
                HStack {
                    Eyebrow(text: "Today’s plan")
                    Spacer()
                    addLine("+ ADD")
                }
                ForEach(meals) { m in
                    Button { onTapMeal(m) } label: { row(m) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func addLine(_ title: String) -> some View {
        Button(action: onAdd) {
            Text(title).font(.system(size: 10, weight: .medium)).tracking(1.4)
                .foregroundStyle(Theme.Palette.paprika).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ m: PlannedMeal) -> some View {
        HStack(spacing: 11) {
            PlateView(name: m.name, composition: m.plate, size: Theme.Metric.plateMini)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(m.dayPart.tag) · serves \(m.servings)".uppercased())
                    .font(.system(size: 8.5)).tracking(Theme.Metric.eyebrowTracking)
                    .foregroundStyle(Theme.Palette.ink.opacity(0.4))
                Text(m.name).font(Theme.Typography.dish(15)).foregroundStyle(Theme.Palette.ink)
                if m.missingCount > 0 {
                    Text("NEEDS \(m.missingCount) → LIST")
                        .font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.paprika)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// The now-module leading with a meal planned for the current part of day: the thing
/// to do now (Cook a recipe / Log a leftover, at its servings), with the generic
/// "you could…" suggestions one tap away.
private struct PlannedNowView: View {
    let meal: PlannedMeal
    var onAct: () -> Void
    var onEdit: () -> Void
    var onSeeOptions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "\(meal.dayPart.nowLabel) · planned", tone: .urgent)
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    PlateView(name: meal.name, composition: meal.plate, size: Theme.Metric.plateRow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meal.name).font(Theme.Typography.dish(18)).foregroundStyle(Theme.Palette.ink)
                        Text("serves \(meal.servings)" + (meal.missingCount > 0 ? " · needs \(meal.missingCount)" : ""))
                            .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGray)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 14) {
                Button(action: onAct) {
                    Text(meal.isCookable ? "COOK" : "LOG IT")
                        .font(.system(size: 11, weight: .medium)).tracking(1.6)
                        .foregroundStyle(Theme.Palette.cream)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Rectangle().fill(Theme.Palette.paprika))
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onSeeOptions) {
                    Text("see other options →").font(Theme.Typography.fact(12))
                        .foregroundStyle(Theme.Palette.warmGray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 12)
    }
}

/// Actions on a planned meal: adjust its servings (carried into the cook instrument),
/// move it to a different part of the day, cook it (recipe) or log it (leftover), or
/// drop it from the plan.
private struct PlannedMealSheet: View {
    let meal: PlannedMeal
    var onSetPart: (DayPart) -> Void
    var onSetServings: (Int) -> Void
    /// Cook (recipe) or log (leftover) at the chosen servings.
    var onAct: (Int) -> Void
    var onRemove: () -> Void

    @State private var servings: Int
    @State private var part: DayPart

    init(meal: PlannedMeal, onSetPart: @escaping (DayPart) -> Void,
         onSetServings: @escaping (Int) -> Void, onAct: @escaping (Int) -> Void,
         onRemove: @escaping () -> Void) {
        self.meal = meal; self.onSetPart = onSetPart
        self.onSetServings = onSetServings; self.onAct = onAct; self.onRemove = onRemove
        _servings = State(initialValue: meal.servings)
        _part = State(initialValue: meal.dayPart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                PlateView(name: meal.name, composition: meal.plate, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name).font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
                    Text("\(DayLabel.full(for: meal.date)) · \(part.tag)".uppercased())
                        .font(.system(size: 9)).tracking(Theme.Metric.eyebrowTracking)
                        .foregroundStyle(Theme.Palette.ink.opacity(0.5))
                }
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Servings")
                HStack(spacing: 16) {
                    stepper("−") { if servings > 1 { servings -= 1; onSetServings(servings) } }
                    Text("\(servings)").font(Theme.Typography.dish(17)).foregroundStyle(Theme.Palette.ink)
                    stepper("＋") { if servings < 24 { servings += 1; onSetServings(servings) } }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Move to")
                HStack(spacing: 8) {
                    ForEach(DayPart.allCases, id: \.self) { p in
                        let selected = p == part
                        Button { part = p; onSetPart(p) } label: {
                            Text(p.tag.uppercased()).font(.system(size: 9.5, weight: .medium)).tracking(1.2)
                                .foregroundStyle(selected ? Theme.Palette.cream : Theme.Palette.ink.opacity(0.7))
                                .padding(.horizontal, 11).padding(.vertical, 7)
                                .background(Rectangle().fill(selected ? Theme.Palette.ink : .clear))
                                .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(selected ? 0 : 0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button { onAct(servings) } label: {
                Text(meal.isCookable ? "COOK →" : "LOG IT EATEN")
                    .font(.system(size: 11, weight: .medium)).tracking(1.6)
                    .foregroundStyle(Theme.Palette.cream)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Rectangle().fill(Theme.Palette.paprika))
            }
            .buttonStyle(.plain)

            Spacer()
            Button(action: onRemove) {
                Text("REMOVE FROM PLAN").font(.system(size: 10)).tracking(1.8)
                    .foregroundStyle(Theme.Palette.paprika)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
    }

    private func stepper(_ glyph: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(.system(size: 16, weight: .light)).foregroundStyle(Theme.Palette.ink)
                .frame(width: 40, height: 36)
                .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// "How much is left?" — the truth captured at the moment of eating (one tap, only
/// when more than one portion is in play), not a guess made ahead of time. `kept`
/// portions remain as leftovers; 0 means it's finished.
private struct ServingsOutcomeSheet: View {
    let meal: PlannedMeal
    let available: Int
    var onLog: (Int) -> Void
    @State private var kept: Int

    init(meal: PlannedMeal, available: Int, onLog: @escaping (Int) -> Void) {
        self.meal = meal; self.available = available; self.onLog = onLog
        _kept = State(initialValue: max(0, available - meal.servings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                PlateView(name: meal.name, composition: meal.plate, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name).font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
                    Text("\(available) portions on hand".uppercased())
                        .font(.system(size: 9)).tracking(Theme.Metric.eyebrowTracking)
                        .foregroundStyle(Theme.Palette.ink.opacity(0.5))
                }
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "How much is left?")
                HStack(spacing: 16) {
                    stepper("−") { if kept > 0 { kept -= 1 } }
                    Text(kept == 0 ? "ate it all" : "\(kept) left")
                        .font(Theme.Typography.dish(16)).foregroundStyle(Theme.Palette.ink)
                        .frame(minWidth: 96)
                    stepper("＋") { if kept < available { kept += 1 } }
                }
            }

            Spacer()
            Button { onLog(kept) } label: {
                Text("LOG IT").font(.system(size: 11, weight: .medium)).tracking(1.6)
                    .foregroundStyle(Theme.Palette.cream)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Rectangle().fill(Theme.Palette.paprika))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
    }

    private func stepper(_ glyph: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(.system(size: 16, weight: .light)).foregroundStyle(Theme.Palette.ink)
                .frame(width: 40, height: 36)
                .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct PlanDaySheet: View {
    var store: KitchenStore
    let date: Date
    var onPlan: (Dish, DayPart) -> Void
    var onPlanLeftover: (StockItem, DayPart) -> Void = { _, _ in }
    @State private var part: DayPart = .evening

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Plan \(DayLabel.full(for: date))").font(Theme.Typography.dish(20))
                .foregroundStyle(Theme.Palette.ink).padding(.top, 22)
            Text("Pick something — missing items go to your list.")
                .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGray).padding(.top, 3)
            partPicker.padding(.top, 12)
            DashedRule().padding(.top, 10)
            ScrollView {
                VStack(spacing: 0) {
                    // Leftovers / ready-made first — heat-and-eat, no cooking.
                    if !store.leftovers.isEmpty {
                        Eyebrow(text: "Leftovers — heat & eat")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10).padding(.bottom, 2)
                        ForEach(store.leftovers) { item in
                            Button { onPlanLeftover(item, part) } label: {
                                LeaderRow {
                                    HStack(spacing: 9) {
                                        PlateView(name: item.name, composition: item.plate, size: 26)
                                        Text(item.name).font(Theme.Typography.dish(14)).foregroundStyle(Theme.Palette.ink)
                                    }
                                } trailing: {
                                    Text("READY").font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.sage)
                                }
                                .padding(.vertical, 9).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            DashedRule(opacity: 0.5)
                        }
                        Eyebrow(text: "Cook something")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12).padding(.bottom, 2)
                    }
                    ForEach(store.library) { dish in
                        Button { onPlan(dish, part) } label: {
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

    /// Optional, low-friction sense of which meal — defaults to evening, the common
    /// plan. The day still holds the meals; this just tells lunch from dinner.
    private var partPicker: some View {
        HStack(spacing: 8) {
            ForEach(DayPart.allCases, id: \.self) { p in
                let selected = part == p
                Button { part = p } label: {
                    Text(p.tag.uppercased()).font(.system(size: 9.5, weight: .medium)).tracking(1.2)
                        .foregroundStyle(selected ? Theme.Palette.cream : Theme.Palette.ink.opacity(0.7))
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Rectangle().fill(selected ? Theme.Palette.ink : .clear))
                        .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(selected ? 0 : 0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func readinessLabel(for dish: Dish) -> some View {
        switch store.readiness(for: dish) {
        case .ready: Text("READY").font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.sage)
        case .readyWithSwaps(let swaps): Text("WITH \(SwapPhrase.count(swaps.count).uppercased())").font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.sage)
        case .needs(let items): Text("NEEDS \(items.count)").font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.paprika)
        }
    }
}

/// Pick a day beyond the visible horizon to plan — the timeline's honest answer to
/// "what about later?" instead of an endless scroll.
private struct PlanAheadSheet: View {
    var onPick: (Date) -> Void
    var onClose: () -> Void
    @State private var date = Calendar.current.date(byAdding: .day, value: 21, to: Date()) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Plan a day").font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Button("Done", action: onClose)
                    .font(Theme.Typography.fact(14, weight: .medium)).foregroundStyle(Theme.Palette.paprika)
                    .buttonStyle(.plain)
            }
            .padding(.top, 22)
            DashedRule().padding(.top, 10)
            DatePicker("", selection: $date, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Theme.Palette.paprika)
                .labelsHidden()
                .padding(.top, 6)
            Button { onPick(date) } label: {
                Text("PLAN \(DayLabel.full(for: date).uppercased()) →")
                    .font(.system(size: 11, weight: .medium)).tracking(1.4)
                    .foregroundStyle(Theme.Palette.cream)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Rectangle().fill(Theme.Palette.ink))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
    }
}

#Preview { RedesignRootView() }
