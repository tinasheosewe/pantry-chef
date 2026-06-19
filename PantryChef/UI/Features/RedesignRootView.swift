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
    /// Name search, shown in any grid view (every lens except the "For you" landing).
    @State private var feedSearch = ""
    @State private var feedSort: RecipeSort = .readiness
    @State private var feedSortAscending = true
    /// "Cook together" multi-select over the grid.
    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // A persistent paper floor behind everything, so swapping the loading screen
            // for the app — or one tab for another — never flashes a blank frame.
            Theme.Palette.cream.ignoresSafeArea()
            if store.readinessReady {
                main.transition(.opacity)
            } else {
                // Proactively load everything behind a loading screen — the UI only
                // appears once it's actually usable (no frozen half-built page).
                LoadingScreen(progress: store.loadProgress).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: store.readinessReady)
        .task { await store.warmUp() }
    }

    private var main: some View {
        // Tab switches are instant: no `.id(store.space)` (it forced a full teardown +
        // rebuild of each space, which flickered without the old page-turn to cover it)
        // and no transition. The persistent floor above keeps the swap clean.
        ZStack { space }
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
    }

    /// One true line per page.
    private var tailpiece: String {
        switch store.space {
        case .today:
            let ready = feedLibrary.filter { store.readiness(for: $0).isMakeableNow }.count
            return "\(ready) ready tonight"
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
            StockView(store: store, onSettings: { showSettings = true })
        }
    }

    /// The Today feed (approachability redesign): a pinned "cook now" hero over an
    /// image-led recipe feed. Default lens ("For you") = named intent rails with one
    /// editorial feature woven in; a specific lens collapses to a filtered grid. This
    /// merged the old Today + Ideas tabs — the only unique content was the feed.
    private var todayFeed: some View {
        // The curated "For you" rails show only on the default lens with no extra
        // filters; any lens or filter turns the feed into a filtered grid.
        // "For you" with no filters = the curated landing. Any other lens (incl. the "All"
        // grid) or a filter turns the feed into an in-page grid — the old bottom-sheet
        // library is gone, browsing lives right here.
        let curatedView = feedLens == .all && feedFilters.isEmpty
        return VStack(spacing: 0) {
            todayHeader
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if curatedView {
                        pantryHeadline
                        if showsHero {
                            nowModule
                                .padding(.horizontal, Theme.Metric.lg)
                                .padding(.top, 12)
                        }
                    }
                    IntentPills(selected: lensBinding, filterCount: feedFilters.activeCount,
                                onOpenFilters: { showFilters = true })
                        .padding(.top, curatedView ? 16 : 12)
                    if curatedView {
                        forYouFeed
                    } else {
                        gridControls.padding(.horizontal, Theme.Metric.lg).padding(.top, 12)
                        filteredGrid
                    }
                }
                .padding(.bottom, 28)
            }
            // Re-identify the scroll on lens change so it always starts at the top.
            // ("Browse all" / a rail's "see all" used to swap the tall curated feed for a
            // shorter grid while keeping a deep scroll offset → you landed on blank space.)
            .id(feedLens)
        }
        .background(Theme.Palette.cream.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if selecting && !selectedIDs.isEmpty { cookTogetherBar }
        }
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

    /// The loud pantry-intelligence headline — the app's whole reason to exist, stated
    /// up top: one honest number — how many recipes you can make tonight (as written or
    /// with a small substitution; both are "makeable"). The count of swaps is noise the
    /// cook doesn't act on, so it's not surfaced here. (Appears once readiness is warm.)
    @ViewBuilder private var pantryHeadline: some View {
        if store.readinessReady {
            let makeable = feedLibrary.filter { store.readiness(for: $0).isMakeableNow }.count
            (Text("\(makeable) ").font(Theme.Typography.dish(28, weight: .semibold))
                + Text(makeable == 1 ? "recipe you can make tonight" : "recipes you can make tonight")
                    .font(Theme.Typography.dish(19)))
                .foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Metric.lg).padding(.top, 12)
        }
    }

    /// The curated default, pantry-first: leftovers to use up, then the three readiness
    /// tiers (make now → one swap → a shop away), each tappable through to its full grid.
    @ViewBuilder private var forYouFeed: some View {
        leftoversRail
        if store.readinessReady {
            // Use-it-up leads when something's turning — a full rail now, not one card.
            tierRail("Use it up", "Cook before these ingredients turn", .useItUp)
            tierRail("Make it now", "Everything's already on hand", .makeNow, excludingName: featureDish?.name)
            if let feature = featureItem {
                FeatureCard(item: feature, eyebrow: featureEyebrow, subtitle: featureSubtitle,
                            onOpen: { detailDish = $0 })
                    .padding(.horizontal, Theme.Metric.lg).padding(.top, 18)
            }
            tierRail("With a swap", "Cook it with a small substitution", .oneSwap)
            tierRail("A quick shop", "You're an ingredient or two short", .shop, sortByMissing: true)
            browseAllFooter.padding(.top, 22)
        } else {
            Text("Reading your pantry…")
                .font(Theme.Typography.note(13)).foregroundStyle(Theme.Palette.warmGray)
                .frame(maxWidth: .infinity).padding(.top, 36)
        }
    }

    /// One pantry-tier rail — only shown if it has dishes; header taps through to the
    /// full grid for that lens.
    private func tierRail(_ title: String, _ subtitle: String, _ lens: FeedLens,
                          sortByMissing: Bool = false, excludingName: String? = nil) -> some View {
        var dishes = feedLibrary.filter { matches($0, lens) }
        if let ex = excludingName?.lowercased() { dishes.removeAll { $0.name.lowercased() == ex } }
        if sortByMissing {
            dishes.sort { store.readiness(for: $0).missingCount < store.readiness(for: $1).missingCount }
        }
        let total = dishes.count
        let items = dishes.prefix(12).map(feedItem)
        return Group {
            if !items.isEmpty {
                RecipeRail(
                    rail: FeedRail(title: title, subtitle: subtitle, items: Array(items)),
                    onOpen: { detailDish = $0 },
                    total: total,
                    onSeeAll: { withAnimation { feedLens = lens } })
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
                    Text("LEFTOVERS").font(.system(size: 8.5, weight: .bold)).tracking(1)
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
            Text("Nothing matches — clear a filter or your search.")
                .font(Theme.Typography.note(13)).foregroundStyle(Theme.Palette.warmGray)
                .frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      alignment: .leading, spacing: 16) {
                ForEach(dishes) { dish in gridTile(dish) }
            }
            .padding(.horizontal, Theme.Metric.lg).padding(.top, 14)
        }
    }

    /// One grid tile — opens the recipe, or toggles selection in "cook together" mode.
    @ViewBuilder private func gridTile(_ dish: Dish) -> some View {
        let isSel = selectedIDs.contains(dish.id)
        RecipeTile(item: feedItem(dish)) { tapped in
            if selecting {
                if isSel { selectedIDs.remove(dish.id) } else { selectedIDs.insert(dish.id) }
            } else { detailDish = tapped }
        }
        .overlay(alignment: .topTrailing) {
            if selecting {
                Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSel ? Theme.Palette.paprika : Theme.Palette.ink.opacity(0.35))
                    .padding(8)
            }
        }
        .opacity(selecting && !isSel ? 0.6 : 1)
    }

    /// Chips bind through here so picking a lens clears the search + any selection.
    private var lensBinding: Binding<FeedLens> {
        Binding(get: { feedLens },
                set: { feedLens = $0; selecting = false; selectedIDs = []; feedSearch = "" })
    }

    /// Search + "cook together" — sits just under the chips in every non-curated view.
    /// Search is the inline editorial style (magnifier + text, no boxed field); "cook
    /// together" rides the same line as a small-caps link.
    private var gridControls: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
                .foregroundStyle(Theme.Palette.ink.opacity(0.45))
            TextField("Search dishes", text: $feedSearch)
                .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
            if !feedSearch.isEmpty {
                Button { feedSearch = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(Theme.Palette.ink.opacity(0.45))
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            SortMenu(sort: $feedSort, ascending: $feedSortAscending)
            Button { withAnimation { selecting.toggle(); selectedIDs = [] } } label: {
                Text(selecting ? "CANCEL" : "COOK TOGETHER")
                    .font(.system(size: 9, weight: .medium)).tracking(1.4)
                    .foregroundStyle(Theme.Palette.paprika).fixedSize().contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The "cook N together" action bar, pinned while you're selecting.
    private var cookTogetherBar: some View {
        VStack(spacing: 0) {
            SolidRule()
            HStack {
                Text("\(selectedIDs.count) SELECTED")
                    .font(.system(size: 9)).tracking(1.8).foregroundStyle(Theme.Palette.ink.opacity(0.55))
                Spacer()
                BlockButton(title: "Cook \(selectedIDs.count) together") {
                    let chosen = store.library.filter { selectedIDs.contains($0.id) }
                    selecting = false; selectedIDs = []
                    multiSession = CookSession(dishes: chosen)
                }
            }
            .padding(.horizontal, Theme.Metric.lg).padding(.vertical, 10)
        }
        .background(Theme.Palette.cream)
    }

    /// Dishes matching the active lens AND the secondary filters AND the search.
    /// The library the feed + browse show: excludes dishes that clash with the user's
    /// dietary profile (avoided allergens) — we never surface something they can't eat.
    private var feedLibrary: [Dish] { store.feedLibrary }

    private var filteredDishes: [Dish] {
        let q = feedSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let matched = feedLibrary.filter {
            matches($0, feedLens) && feedFilters.accepts($0) && (q.isEmpty || $0.name.lowercased().contains(q))
        }
        return store.sorted(matched, by: feedSort, ascending: feedSortAscending)
    }

    /// Distinct, sorted values of a string tag across the library (for the filter sheet).
    private func distinctTags(_ key: (Dish) -> String?) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for dish in feedLibrary {
            guard let v = key(dish), !v.isEmpty else { continue }
            if seen.insert(v.lowercased()).inserted { out.append(v) }
        }
        return out.sorted()
    }
    private var distinctDiets: [String] {
        var seen = Set<String>(); var out: [String] = []
        for dish in feedLibrary {
            for d in dish.diets where seen.insert(d.lowercased()).inserted { out.append(d) }
        }
        return out.sorted()
    }

    private var browseAllFooter: some View {
        Button { withAnimation { feedLens = .everything } } label: {
            Text("BROWSE ALL DISHES →")
                .font(.system(size: 11, weight: .medium)).tracking(1.4)
                .foregroundStyle(Theme.Palette.paprika)
                .frame(maxWidth: .infinity).padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed data (the categorizer)

    // Tile + lens logic is shared with browse-all — it lives on the store (see
    // TodayFeed.swift). These thin aliases keep the feed's call sites tidy.
    private func feedItem(_ dish: Dish) -> FeedItem { store.feedItem(dish) }
    private func matches(_ dish: Dish, _ lens: FeedLens) -> Bool { store.matches(dish, lens: lens) }
    private func usesExpiring(_ dish: Dish) -> Bool { store.usesExpiring(dish) }

    /// Name of the dish the hero is already showing (planned meal, or the selected fan
    /// option), so the rails/feature don't echo it back at you a second time.
    private var heroDishName: String? {
        if isIdleNow, let plan = store.planForNow { return plan.name }
        return nil
    }

    /// The editorial feature — a ready-now spotlight (use-it-up now has its own rail).
    /// Never the dish the hero is already showing.
    private var featureDish: Dish? {
        guard store.readinessReady else { return nil }
        let heroName = heroDishName?.lowercased()
        return feedLibrary.first { store.readiness(for: $0).isMakeableNow && $0.name.lowercased() != heroName }
    }
    private var featureItem: FeedItem? { featureDish.map(feedItem) }
    private var featureEyebrow: String { "Tonight's pick" }
    private var featureSubtitle: String { "Ready right now with what's on hand." }

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
                onSeeAll: { withAnimation { feedLens = .everything } },
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
            onTimer: { text in store.updateCookingTimer(text) },
            onDone: { portions in
                store.finishCooking(session.dishes, madePortions: portions)
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
            // Header + leftovers are padded to match the browse grid below (which pads
            // itself), so chips, search and tiles all line up on one margin.
            VStack(alignment: .leading, spacing: 0) {
                Text("Plan \(DayLabel.full(for: date))").font(Theme.Typography.dish(20))
                    .foregroundStyle(Theme.Palette.ink).padding(.top, 22)
                Text("Pick something — missing items go to your list.")
                    .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGray).padding(.top, 3)
                partPicker.padding(.top, 12)
                DashedRule().padding(.top, 10)
                // Leftovers / ready-made first — heat-and-eat, no cooking.
                if !store.leftovers.isEmpty {
                    Eyebrow(text: "Leftovers — heat & eat")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12).padding(.bottom, 4)
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
                }
            }
            .padding(.horizontal, Theme.Metric.lg)
            // Then the same browse UI as Today (chips · search · filters · readiness-
            // sorted tiles) instead of the old flat, unsorted, unfilterable list.
            RecipeBrowse(store: store, library: browseLibrary) { onPlan($0, part) }
                .padding(.top, store.leftovers.isEmpty ? 4 : 10)
        }
        .background(KitchenBackground())
    }

    /// The dishes the picker browses — dietary-filtered, never surfacing something the
    /// user can't eat (mirrors the Today feed's `feedLibrary`).
    private var browseLibrary: [Dish] { store.feedLibrary }

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
}

/// Pick a day beyond the visible horizon to plan — the timeline's honest answer to
/// "what about later?" instead of an endless scroll.
private struct PlanAheadSheet: View {
    var onPick: (Date) -> Void
    var onClose: () -> Void
    // Start on today, not weeks out — simplest default; the picker opens on the
    // current month with today already selected.
    @State private var date = Date()

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
