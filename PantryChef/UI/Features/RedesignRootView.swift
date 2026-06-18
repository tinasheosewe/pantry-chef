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
    /// The Today feed's active intent lens (the chips). `.all` = the curated default.
    @State private var feedLens: FeedLens = .all
    /// Secondary "More filters" (cuisine/diet/meal type/time) layered on the lens.
    @State private var feedFilters = FeedFilters()
    @State private var showFilters = false
    /// Full dish library, opened from the feed's "browse all" / now-module "see all".
    @State private var showAllDishes = false
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
                    tailpiece: tailpiece,
                    badges: [.pantry: store.expiringSoon().count]
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
                let available = store.availablePortions(named: meal.name) ?? meal.servings
                ServingsOutcomeSheet(
                    name: meal.name, plate: meal.plate, available: available,
                    defaultKept: max(0, available - meal.servings),
                    onLog: { kept in withAnimation { store.logPlannedMeal(meal, kept: kept) }; loggingMeal = nil })
                .presentationDetents([.height(300)])
            }
            .fullScreenCover(item: $detailDish) { dish in
                // Cook is presented from *inside* this cover (a second cover on the
                // same presenter never appears until the first dismisses).
                RecipeDetailScreen(store: store, dish: dish, onClose: { detailDish = nil })
            }
            .fullScreenCover(item: $multiSession) { session in
                CookFlowScreen(store: store, session: session, onClose: { multiSession = nil })
            }
            .sheet(isPresented: $showAllDishes) {
                LibraryView(
                    store: store,
                    onCook: { dish in showAllDishes = false; DispatchQueue.main.async { detailDish = dish } },
                    onCookTogether: { dishes in showAllDishes = false; DispatchQueue.main.async { multiSession = CookSession(dishes: dishes) } }
                )
                .presentationDetents([.large])
            }
    }

    /// One true line per page (the mock's "№ 163 · sunset 21:43").
    private var tailpiece: String {
        switch store.space {
        case .today:
            let dayNumber = Calendar.current.ordinality(of: .day, in: .year, for: store.today) ?? 0
            guard store.readinessReady else { return "№ \(dayNumber)" }
            let ready = store.library.filter { store.readiness(for: $0).isMakeableNow }.count
            return "№ \(dayNumber) · \(ready) ready tonight"
        case .plan:
            return "\(store.todaysPlannedMeals.count) planned today · plan ahead"
        case .pantry:
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
        case .today:
            todayFeed
        case .plan:
            TimelineView(
                entries: store.timelineEntries,
                today: store.today,
                onTapDay: { planTarget = PlanTarget(date: $0) },
                onOpenMeal: { name in detailDish = store.dish(named: name) },
                onTapMeal: { editingMeal = $0 },
                onDismissProposal: { id in withAnimation { store.dismissProposal(id) } },
                onOpenStock: { store.space = .pantry },
                onPlanAhead: { showPlanAhead = true },
                onSettings: { showSettings = true },
                nowContent: {
                    // On the Plan feed the "now" anchor is just today's plan — the full
                    // now-module (cook CTA, options) lives on the Today hero, not here.
                    AnyView(TodayPlanView(
                        store: store,
                        onTapMeal: { editingMeal = $0 },
                        onAdd: { planTarget = PlanTarget(date: store.today) }))
                }
            )
        case .pantry:
            StockView(store: store)
        }
    }

    /// The Today feed (approachability redesign): a pinned "cook now" hero over an
    /// image-led recipe feed. Default lens ("For you") = named intent rails with one
    /// editorial feature woven in; a specific lens collapses to a filtered grid. This
    /// merged the old Today + Ideas tabs — the only unique content was the feed.
    private var todayFeed: some View {
        // The curated "For you" rails show only on the default lens with no extra
        // filters; any lens or filter turns the feed into a filtered grid.
        let curatedView = feedLens == .all && feedFilters.isEmpty
        return VStack(spacing: 0) {
            todayHeader
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if curatedView && showsHero {
                        nowModule
                            .padding(.horizontal, Theme.Metric.lg)
                            .padding(.top, 10)
                    }
                    IntentPills(selected: $feedLens, filterCount: feedFilters.activeCount,
                                onOpenFilters: { showFilters = true })
                        .padding(.top, curatedView ? 16 : 12)
                    if curatedView {
                        forYouFeed
                        browseAllFooter.padding(.top, 20)
                    } else {
                        filteredGrid
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .background(Theme.Palette.cream.ignoresSafeArea())
        .sheet(isPresented: $showFilters) {
            FeedFiltersSheet(
                filters: $feedFilters,
                cuisines: distinctTags { $0.cuisine },
                diets: distinctDiets,
                mealTypes: distinctTags { $0.mealType },
                resultCount: filteredDishes.count,
                onClose: { showFilters = false })
            .presentationDetents([.medium, .large])
        }
    }

    /// The curated default: a leftovers rail (when present), then intent rails with one
    /// magazine feature after the first.
    @ViewBuilder private var forYouFeed: some View {
        leftoversRail
        let rails = defaultRails
        ForEach(Array(rails.enumerated()), id: \.element.id) { idx, rail in
            RecipeRail(rail: rail, onOpen: { detailDish = $0 })
            if idx == 0, let feature = featureItem {
                FeatureCard(item: feature, eyebrow: featureEyebrow, subtitle: featureSubtitle,
                            onOpen: { detailDish = $0 })
                    .padding(.horizontal, Theme.Metric.lg).padding(.top, 18)
            }
        }
    }

    /// Heat-and-eat leftovers, leading the feed so you use them up first. Only shown
    /// when there are any (no empty rail). Tap → the "how much is left?" eat flow.
    @ViewBuilder private var leftoversRail: some View {
        let items = store.leftovers
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Eat first").font(Theme.Typography.dish(17)).foregroundStyle(Theme.Palette.ink)
                    Text("Heat-and-eat — use up what's already made")
                        .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGray)
                }
                .padding(.horizontal, Theme.Metric.lg)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items) { leftoverTile($0) }
                    }
                    .padding(.horizontal, Theme.Metric.lg)
                }
            }
            .padding(.top, 18)
        }
    }

    private func leftoverTile(_ item: StockItem) -> some View {
        Button {
            loggingMeal = PlannedMeal(date: store.today, name: item.name, plate: item.plate,
                                      level: .served, servings: 1)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Theme.Palette.creamRaised).frame(width: 142, height: 96)
                        .overlay(PlateView(name: item.name, composition: item.plate, size: 62))
                        .overlay(Rectangle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                    Text("LEFTOVER").font(.system(size: 8.5, weight: .bold)).tracking(1)
                        .foregroundStyle(Theme.Palette.sage)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Rectangle().fill(Theme.Palette.cream))
                        .overlay(Rectangle().strokeBorder(Theme.Palette.sage.opacity(0.6), lineWidth: 1))
                        .padding(6)
                }
                Text(item.name).font(Theme.Typography.dish(15)).foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1).frame(width: 142, alignment: .leading)
                Text(leftoverPortions(item)).font(Theme.Typography.fact(11))
                    .foregroundStyle(Theme.Palette.warmGray).frame(width: 142, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func leftoverPortions(_ item: StockItem) -> String {
        if case .made(let detail, let portions) = item.measure {
            if let p = portions { return "\(p) \(p == 1 ? "portion" : "portions")" }
            return detail
        }
        return ""
    }

    /// Lens + secondary filters → a two-column grid of every matching dish.
    @ViewBuilder private var filteredGrid: some View {
        let dishes = filteredDishes
        if dishes.isEmpty {
            Text("Nothing matches those filters.")
                .font(Theme.Typography.note(13)).foregroundStyle(Theme.Palette.warmGray)
                .frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      alignment: .leading, spacing: 16) {
                ForEach(dishes) { dish in
                    RecipeTile(item: feedItem(dish), onOpen: { detailDish = $0 })
                }
            }
            .padding(.horizontal, Theme.Metric.lg).padding(.top, 14)
        }
    }

    /// Dishes matching the active lens AND the secondary filters.
    private var filteredDishes: [Dish] {
        store.library.filter { matches($0, feedLens) && feedFilters.accepts($0) }
    }

    /// Distinct, sorted values of a string tag across the library (for the filter sheet).
    private func distinctTags(_ key: (Dish) -> String?) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for dish in store.library {
            guard let v = key(dish), !v.isEmpty else { continue }
            if seen.insert(v.lowercased()).inserted { out.append(v) }
        }
        return out.sorted()
    }
    private var distinctDiets: [String] {
        var seen = Set<String>(); var out: [String] = []
        for dish in store.library {
            for d in dish.diets where seen.insert(d.lowercased()).inserted { out.append(d) }
        }
        return out.sorted()
    }

    private var browseAllFooter: some View {
        Button { showAllDishes = true } label: {
            Text("BROWSE ALL DISHES →")
                .font(.system(size: 11, weight: .medium)).tracking(1.4)
                .foregroundStyle(Theme.Palette.paprika)
                .frame(maxWidth: .infinity).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed data (the categorizer)

    private func feedItem(_ dish: Dish) -> FeedItem {
        // Distinguish on-hand from cook-with-a-swap (the old "Cookable with a swap"
        // signal, kept alive in the feed). Skipped until readiness is warm.
        var stamp: String?
        if store.readinessReady {
            switch store.readiness(for: dish) {
            case .ready: stamp = "READY"
            case .readyWithSwaps: stamp = "SWAP"
            case .needs: stamp = nil
            }
        }
        return FeedItem(dish: dish, meta: dish.minutes.map { "\($0) min" } ?? dish.time, stamp: stamp)
    }

    /// Which lens a dish belongs to. Derived from the recipe itself + live pantry state.
    private func matches(_ dish: Dish, _ lens: FeedLens) -> Bool {
        switch lens {
        case .all: return true
        case .readyNow: return store.readiness(for: dish).isMakeableNow
        case .useItUp: return usesExpiring(dish)
        case .quick: return (dish.minutes ?? .max) <= 25
        case .highProtein: return dish.plate.weights.first?.category == .protein
        }
    }

    private func usesExpiring(_ dish: Dish) -> Bool {
        let expiring = store.expiringSoon().map { $0.name.lowercased() }
        guard !expiring.isEmpty else { return false }
        return dish.ingredients.contains { ing in
            let name = ing.name.lowercased()
            return expiring.contains { name.contains($0) || $0.contains(name) }
        }
    }

    /// Name of the dish the hero is already showing (planned meal, or the selected fan
    /// option), so the rails/feature don't echo it back at you a second time.
    private var heroDishName: String? {
        if isIdleNow, let plan = store.planForNow { return plan.name }
        return nil
    }

    /// Rails, de-duplicated: nothing repeats across rails, and nothing echoes the hero
    /// or the feature. Each dish earns exactly one slot in the For-you feed.
    private var defaultRails: [FeedRail] {
        let heroName = heroDishName?.lowercased()
        var used = Set<UUID>()
        if let f = featureDish { used.insert(f.id) }

        func rail(_ title: String, _ subtitle: String, from pool: [Dish]) -> FeedRail? {
            let picks = pool.filter { !used.contains($0.id) && $0.name.lowercased() != heroName }.prefix(10)
            guard !picks.isEmpty else { return nil }
            picks.forEach { used.insert($0.id) }
            return FeedRail(title: title, subtitle: subtitle, items: picks.map(feedItem))
        }

        return [
            // The pantry-aware rail only appears once readiness is warm (post-launch).
            store.readinessReady ? rail("Ready now", "Cook with what's on hand",
                 from: store.library.filter { store.readiness(for: $0).isMakeableNow }) : nil,
            rail("Fast tonight", "Under thirty minutes",
                 from: store.library.filter { ($0.minutes ?? .max) <= 25 }),
            rail("Feeds the table", "Serves four or more",
                 from: store.library.filter { $0.servings >= 4 }),
        ].compactMap { $0 }
    }

    /// The editorial feature — lead with a "use it up" dish when something's expiring,
    /// else the strongest ready-now pick. Never the dish the hero is already showing.
    private var featureDish: Dish? {
        let heroName = heroDishName?.lowercased()
        if let d = store.library.first(where: { usesExpiring($0) && $0.name.lowercased() != heroName }) { return d }
        guard store.readinessReady else { return nil }
        return store.library.first { store.readiness(for: $0).isMakeableNow && $0.name.lowercased() != heroName }
    }
    private var featureItem: FeedItem? { featureDish.map(feedItem) }
    private var featureEyebrow: String { (featureDish.map(usesExpiring) ?? false) ? "Use it up" : "Ready now" }
    private var featureSubtitle: String {
        if (featureDish.map(usesExpiring) ?? false), let soon = store.expiringSoon().first,
           let d = soon.daysLeft(now: store.today) {
            return "Your \(soon.name.lowercased()) won't keep — \(d <= 0 ? "use it today" : "\(d) day\(d == 1 ? "" : "s") left")."
        }
        return "Ready right now with what's on hand."
    }

    /// Date + settings, a single quiet line over the hero.
    private var todayHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(DayLabel.monthDayLong(for: store.today))
                    .font(Theme.Typography.dish(26)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text(DayLabel.eyebrow(for: store.today).uppercased())
                    .font(.system(size: 10)).tracking(Theme.Metric.eyebrowTracking)
                    .foregroundStyle(Theme.Palette.ink.opacity(0.55))
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.ink.opacity(0.5))
                        .padding(.vertical, 4).padding(.leading, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Settings")
            }
            .padding(.horizontal, Theme.Metric.lg).padding(.top, 6)
            DashedRule().padding(.horizontal, Theme.Metric.lg).padding(.top, 9).padding(.bottom, 2)
        }
    }

    /// "What's for now": a meal planned for the current part of day leads if there is
    /// one; otherwise the ready-options fan. Shared hero of the Today tab.
    /// The hero shows only when there's something decisive to say: a meal planned for
    /// now, or a cook in flight (committed/cooking/cooked). When idle with nothing
    /// planned there's no fan — the feed (leftovers + ready rails) is the exploration.
    private var showsHero: Bool {
        if isIdleNow { return store.planForNow != nil }
        return true
    }

    @ViewBuilder private var nowModule: some View {
        if isIdleNow, let plan = store.planForNow {
            PlannedNowView(
                meal: plan,
                onAct: { actOnPlan(plan) },
                onEdit: { editingMeal = plan })
        } else if isIdleNow {
            EmptyView()
        } else {
            NowModuleView(
                state: Binding(get: { store.nowState }, set: { store.nowState = $0 }),
                onCook: { option in
                    // A cookable dish opens the instrument; a ready-made pick is logged.
                    if option.level.usesInstrument, let dish = option.dish {
                        detailDish = dish
                    } else {
                        store.logEaten(option)
                    }
                },
                onSeeAll: {
                    store.libraryFilter = .all
                    showAllDishes = true
                },
                onChange: { store.resetNow() },
                onResume: {
                    if case .cooking(let p) = store.nowState, let dish = p.dish {
                        multiSession = CookSession(dishes: [dish])
                    }
                }
            )
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
            onLogCooked: { effective in store.logCooked(effective); onClose() },
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
            Button(action: onAct) {
                Text(meal.isCookable ? "COOK" : "LOG IT")
                    .font(.system(size: 11, weight: .medium)).tracking(1.6)
                    .foregroundStyle(Theme.Palette.cream)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Rectangle().fill(Theme.Palette.paprika))
            }
            .buttonStyle(.plain)
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
    let name: String
    let plate: PlateComposition
    let available: Int
    var onLog: (Int) -> Void
    @State private var kept: Int

    init(name: String, plate: PlateComposition, available: Int, defaultKept: Int,
         onLog: @escaping (Int) -> Void) {
        self.name = name; self.plate = plate; self.available = available; self.onLog = onLog
        _kept = State(initialValue: min(max(0, defaultKept), max(0, available)))
    }

    /// kept == 0 → ate everything; kept == all → ate none (e.g. batch-cooked for later).
    private var keptLabel: String {
        if kept <= 0 { return "ate it all" }
        if kept >= available { return "ate none" }
        return "\(kept) left"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                PlateView(name: name, composition: plate, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
                    Text("\(available) \(available == 1 ? "portion" : "portions")".uppercased())
                        .font(.system(size: 9)).tracking(Theme.Metric.eyebrowTracking)
                        .foregroundStyle(Theme.Palette.ink.opacity(0.5))
                }
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "How much is left?")
                HStack(spacing: 16) {
                    stepper("−") { if kept > 0 { kept -= 1 } }
                    Text(keptLabel)
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
