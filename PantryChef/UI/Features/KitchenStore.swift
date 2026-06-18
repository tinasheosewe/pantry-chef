import SwiftUI
import Observation

// MARK: - Stock view model

/// A stock row. Perishables show a day count; staples show honest presence, never
/// a fake fullness (spec §7).
struct StockItem: Identifiable, Equatable {
    enum Section: String { case made = "Made by you", useSoon = "Use soon", have = "In stock", staples = "Staples" }
    enum Measure: Equatable {
        // daysLeft is the FULL-PRECISION remaining lifetime (a Double): storage moves
        // re-project it without losing a partial day each time. It's truncated to a whole
        // number only at the consumer boundary (`daysLeft(now:)`), never in storage.
        case perishable(detail: String, daysLeft: Double?)
        case staple(StapleLevel)
        /// Leftover / batch-cooked food. `portions` is the structured count drawn down
        /// as it's eaten (nil when we only have the free-text `detail`).
        case made(detail: String, portions: Int? = nil)
    }
    enum StapleLevel: Equatable {
        case inStock, runningLow, out
        var label: String {
            switch self {
            case .inStock: return "In stock"
            case .runningLow: return "Running low — on your list"
            case .out: return "Out"
            }
        }
        /// Compact form for single-line rows.
        var shortLabel: String {
            switch self {
            case .inStock: return "in stock"
            case .runningLow: return "low · listed"
            case .out: return "out"
            }
        }
    }
    let id: UUID
    let key: String
    var name: String
    let plate: PlateComposition
    var section: Section
    var measure: Measure
    /// When we last had evidence this item is in the kitchen — the anchor for the
    /// knowledge clock (spec §7). The whole "you don't have to log perfectly" bet
    /// lives here: certainty decays from this date, so a stale record degrades
    /// honestly instead of asserting a confident lie.
    var lastConfirmed: Date

    // First-class ingredient identity (data is the differentiator — every item
    // carries its catalog link, category, and physical storage; no path may
    // create one without them).
    var catalogItemID: String?
    var category: FoodCategory
    /// Where it physically lives — drives the freshness clock and is editable anytime.
    var storage: PantryStorage
    /// When it entered its *current* storage (anchor for blended expiry).
    var storageSince: Date
    /// Fraction of total shelf life used up in *earlier* storage locations, before
    /// the current stint (blended fraction-of-life model — see ExpiryEngine).
    var consumedFraction: Double

    init(id: UUID = UUID(), key: String, name: String, plate: PlateComposition,
         section: Section, measure: Measure, lastConfirmed: Date = Date(),
         catalogItemID: String? = nil, category: FoodCategory = .other,
         storage: PantryStorage = .pantry, storageSince: Date = Date(),
         consumedFraction: Double = 0) {
        self.id = id; self.key = key; self.name = name; self.plate = plate
        self.section = section; self.measure = measure; self.lastConfirmed = lastConfirmed
        self.catalogItemID = catalogItemID; self.category = category
        self.storage = storage; self.storageSince = storageSince
        self.consumedFraction = consumedFraction
    }

    /// Move to a new storage location, re-projecting the freshness clock: the share
    /// of shelf life already used carries over, and the days-left is recomputed from
    /// the new location's shelf life (spec §7). Pure.
    ///
    /// The "used so far" is read from the days-left we're *currently showing*, not a
    /// separately tracked fraction — a seed value or a manual Stepper edit changes
    /// what's on screen without touching `consumedFraction`, and projecting from the
    /// stale fraction discarded that. Reading the shown estimate makes a sequence of
    /// moves consistent and exactly reversible: fridge → freezer → fridge lands back
    /// on the original days-left.
    ///
    /// `adjustDaysLeft` is the user's Settings preference: when off, only the storage
    /// label changes — the freshness clock and the displayed days-left are left
    /// exactly as they were (you moved it, but you're keeping your own estimate).
    func moved(to newStorage: PantryStorage, now: Date, adjustDaysLeft: Bool = true) -> StockItem {
        guard newStorage != storage else { return self }
        guard adjustDaysLeft else {
            var copy = self
            copy.storage = newStorage
            return copy
        }
        var copy = self
        let consumed = currentConsumedFraction(now: now)
        copy.consumedFraction = consumed
        copy.storage = newStorage
        copy.storageSince = now
        if case .perishable(let detail, _) = measure {
            copy.measure = .perishable(
                detail: detail,
                daysLeft: ExpiryEngine.freshDaysLeft(catalogItemID: catalogItemID,
                                                     storage: newStorage,
                                                     consumedFraction: consumed))
        }
        return copy
    }

    /// Days left *right now*. The stored count is the estimate as of `storageSince`,
    /// and it counts down with the calendar — so something logged today with 10 days
    /// reads 1 day nine days on, and 0 once it's past (never negative). Storage moves
    /// and manual edits re-anchor it (each sets a fresh estimate as of the change).
    /// nil unless it's a tracked perishable.
    func daysLeft(now: Date = Date()) -> Int? {
        guard case .perishable(_, let stored?) = measure else { return nil }
        // Truncate the full-precision remaining lifetime to a whole number here, at the
        // consumer boundary — the stored value stays a Double so moves don't lose a day.
        return max(0, Int(stored - ExpiryEngine.daysBetween(storageSince, now)))
    }

    /// A leftover / batch-cooked item.
    var isMade: Bool { if case .made = measure { return true } else { return false } }
    /// Portions remaining for a leftover (nil unless tracked by count).
    var madePortions: Int? { if case .made(_, let p) = measure { return p } else { return nil } }

    /// Fraction of shelf life used up right now, inferred from the days-left we're
    /// showing — the *live* remaining (the stored estimate already ticked down for
    /// time spent in the current location) against that location's safe lifetime.
    /// Falls back to the tracked fraction plus the current stint when there's no
    /// displayed estimate to read (untracked item) or no catalog life to read against.
    private func currentConsumedFraction(now: Date) -> Double {
        if case .perishable(_, let stored?) = measure,
           let safe = ExpiryEngine.safeDays(catalogItemID: catalogItemID, storage: storage), safe > 0 {
            let remaining = stored - ExpiryEngine.daysBetween(storageSince, now)
            return min(1, max(0, 1 - remaining / Double(safe)))
        }
        return ExpiryEngine.consumedAfterStint(
            priorFraction: consumedFraction, daysInStint: ExpiryEngine.daysBetween(storageSince, now),
            storage: storage, catalogItemID: catalogItemID)
    }

    /// Tracking class for the knowledge clock. Staples almost never need
    /// re-confirming; leftovers sit between perishables and staples.
    var resolutionClass: ResolutionClass {
        switch measure {
        case .perishable: return .perishable
        case .made: return .semiCountable
        case .staple: return .staple
        }
    }

    /// Shelf life feeding the knowledge half-life (NOT the food clock). Perishables
    /// reuse their day-count; leftovers get a freezer-ish span; staples get a long
    /// life so the class factor keeps them effectively always-confirmed.
    private var knowledgeShelfLifeDays: Int? {
        switch measure {
        case .perishable(_, let days): return days.map { Int($0) }
        case .made: return 30
        case .staple: return KitchenConfig.Resolution.stapleMinShelfLifeDays
        }
    }

    /// How sure we are this is still here, right now.
    func certainty(now: Date = Date()) -> ItemCertainty {
        ConfidenceEngine.certainty(lastConfirmed: lastConfirmed, now: now,
                                   shelfLifeDays: knowledgeShelfLifeDays,
                                   resolutionClass: resolutionClass)
    }

    /// True once stale enough to be worth a one-tap question (and not a staple,
    /// which we assume present).
    func needsCheck(now: Date = Date()) -> Bool {
        resolutionClass != .staple && certainty(now: now) <= .uncertain
    }
}

/// One line on the shopping list — a name and the *desired* amount to buy. The
/// amount you actually purchase is recorded when you mark it bought (it may differ).
struct ShoppingEntry: Identifiable, Equatable {
    let id: UUID
    var name: String
    var amount: String?

    init(id: UUID = UUID(), name: String, amount: String? = nil) {
        self.id = id; self.name = name; self.amount = amount
    }
}

// MARK: - Store

/// The redesign's app state: holds the kitchen and derives every surface through
/// the pure engines (TimelineComposer, ReadinessService, IntakeParser). Seeded with
/// a sample kitchen; the single seam where real persistence wires in later.
@Observable
final class KitchenStore {
    var today = Date()
    var space: RootSpace = .today
    var nowState: NowState = .open(options: [], selected: 0)

    var journal: [JournalItem]
    var events: [DatedEvent]
    var whispers: [DatedWhisper]
    var stock: [StockItem]
    var library: [Dish]
    var profile = DietaryProfile()
    /// Settings: when on, moving an item between pantry/fridge/freezer re-projects
    /// its days-left from the new location's shelf life; when off, only the label
    /// changes and your own estimate stands. See `StockItem.moved(to:now:adjustDaysLeft:)`.
    var autoAdjustDaysOnStorageChange = true
    var shoppingList: [ShoppingEntry] = [
        ShoppingEntry(name: "Olive oil"),
        ShoppingEntry(name: "Salmon", amount: "2 fillets"),
        ShoppingEntry(name: "Miso", amount: "1 tub"),
        ShoppingEntry(name: "Milk", amount: "2 L"),
        ShoppingEntry(name: "Eggs", amount: "12")
    ]
    /// The fan's current options — the now-module's Open state rebuilds from these.
    var fanOptions: [FanOption] = []

    private let composer = TimelineComposer()
    private let parser = IntakeParser()
    private let cal = Calendar.current
    /// The surviving AI engine — used only for explicit, user-triggered actions
    /// (make healthier, tweak); never in the ambient loop. No-ops gracefully when
    /// no API key is configured.
    let ai = AIService()

    /// The timeline window — a bounded, honest horizon rather than a pretend-
    /// infinite scroll: a couple of weeks ahead to plan against, a short tail of
    /// recent record behind. Planning further is an explicit act (the horizon cap).
    let horizonDays = 16
    /// The plan starts at today — no history tail. (The cooking record lives in the
    /// journal; the forward plan isn't where you relive last week.)
    let pastDays = 0

    var timelineEntries: [TimelineEntry] {
        // Expiry diamonds and leftover whispers are derived from LIVE stock (not seeded),
        // so the Plan timeline always agrees with Pantry/Feed — eat a leftover or use up
        // a perishable and the timeline updates with everything else.
        let cal = Calendar.current
        let liveExpiry = expiringSoon(within: 7).compactMap { item -> DatedEvent? in
            guard let d = item.daysLeft(now: today),
                  let date = cal.date(byAdding: .day, value: max(0, d), to: today) else { return nil }
            // Stable id (the stock item's) so the timeline row doesn't churn each render,
            // and so two items turning on the same day stay distinct diamonds.
            return DatedEvent(kind: .expiry(ExpiryMilestone(id: item.id, date: date, itemName: item.name)))
        }
        let liveWhispers = leftovers.compactMap { item -> DatedWhisper? in
            guard let p = item.madePortions, p > 0 else { return nil }
            return DatedWhisper(date: today, text: "\(item.name.lowercased()) waiting · \(p) \(p == 1 ? "portion" : "portions")")
        }
        return composer.compose(KitchenSnapshot(today: today, horizonDays: horizonDays, pastDays: pastDays,
                                                journal: journal, events: events + liveExpiry,
                                                whispers: whispers + liveWhispers))
    }

    // MARK: - Actions

    /// Forgiving dish lookup for timeline nodes (exact, then contains either way).
    func dish(named name: String) -> Dish? {
        let q = name.lowercased()
        return library.first { $0.name.lowercased() == q }
            ?? library.first { $0.name.lowercased().contains(q) || q.contains($0.name.lowercased()) }
    }

    func toggleFavorite(_ id: UUID) {
        if let i = library.firstIndex(where: { $0.id == id }) { library[i].isFavorite.toggle() }
    }

    /// Add a brand-new dish to the library (e.g. "save as new" from a tweak/edit).
    func addDish(_ dish: Dish) {
        library.insert(dish, at: 0)
    }

    /// Replace a dish (edits, AI tweaks) wherever it lives — library and the fan.
    func updateDish(_ dish: Dish) {
        if let i = library.firstIndex(where: { $0.id == dish.id }) { library[i] = dish }
        fanOptions = fanOptions.map { option in
            guard option.dish?.id == dish.id else { return option }
            return FanOption(id: option.id, name: dish.name, plate: option.plate,
                             subtitle: option.subtitle, reason: option.reason,
                             readiness: option.readiness, level: option.level, dish: dish)
        }
        if case .open(_, let selected) = nowState {
            nowState = .open(options: fanOptions, selected: selected)
        }
    }

    func planMeal(_ dish: Dish, on date: Date, part: DayPart = .evening, servings: Int? = nil) {
        // Anchor the hour to the part so a day's meals sort morning → evening.
        let when = cal.date(bySettingHour: part.anchorHour, minute: 0, second: 0, of: date) ?? date
        events.append(DatedEvent(kind: .meal(PlannedMeal(
            date: when, name: dish.name, plate: dish.plate, level: .cooked,
            dayPart: part, servings: servings ?? dish.servings,
            missingCount: readiness(for: dish).missingCount))))
    }

    /// Plan a leftover / ready-made dish — heat-and-eat, logged not cooked.
    /// `servings` is the portions you intend to eat.
    func planLeftover(_ item: StockItem, on date: Date, part: DayPart = .evening, servings: Int = 1) {
        let when = cal.date(bySettingHour: part.anchorHour, minute: 0, second: 0, of: date) ?? date
        events.append(DatedEvent(kind: .meal(PlannedMeal(
            date: when, name: item.name, plate: item.plate, level: .served,
            dayPart: part, servings: servings, missingCount: 0))))
    }

    /// Made / leftover stock you can plan to simply reheat (the "cooked dish" case).
    var leftovers: [StockItem] {
        stock.filter { if case .made = $0.measure { return true } else { return false } }
    }

    /// Planned meals on a given calendar day, ordered morning → evening.
    func plannedMeals(on date: Date) -> [PlannedMeal] {
        events.compactMap { event -> PlannedMeal? in
            guard case .meal(let m) = event.kind, cal.isDate(m.date, inSameDayAs: date) else { return nil }
            return m
        }.sorted { ($0.dayPart, $0.date) < ($1.dayPart, $1.date) }
    }

    /// Today's committed meals — surfaced at the now-module (the future ruler starts
    /// at tomorrow, so today's plan would otherwise have nowhere to show).
    var todaysPlannedMeals: [PlannedMeal] { plannedMeals(on: today) }

    /// The plan to foreground in the now-module: today's meal for the current part of
    /// day, if any — so a plan leads instead of the generic "you could…" fan.
    var planForNow: PlannedMeal? {
        let part = DayPart.current(today)
        return todaysPlannedMeals.first { $0.dayPart == part }
    }

    /// Drop a meal from the plan.
    func removeMeal(_ id: UUID) {
        events.removeAll { if case .meal(let m) = $0.kind { return m.id == id } else { return false } }
    }

    /// Portions on hand for a named leftover/made item (nil if not tracked by count).
    func availablePortions(named name: String) -> Int? {
        stock.first { $0.name == name }?.madePortions
    }

    /// Log a planned heat-and-eat meal as eaten, truthful about what's left: `kept`
    /// portions remain as made stock (0 = finished). Clears the plan, mirrors logEaten.
    func logPlannedMeal(_ meal: PlannedMeal, kept: Int = 0) {
        removeMeal(meal.id)
        drawDownLeftover(name: meal.name, plate: meal.plate, to: kept)
        nowState = .cooked(CookedSummary(
            name: meal.name, plate: meal.plate,
            summary: kept > 0
                ? "Logged — \(kept) \(kept == 1 ? "portion" : "portions") left."
                : "Logged — all eaten."))
    }

    /// Set a named leftover to `kept` portions: update it, remove it (0), or create it.
    private func drawDownLeftover(name: String, plate: PlateComposition, to kept: Int) {
        if let i = stock.firstIndex(where: { $0.name == name && $0.isMade }) {
            if kept <= 0 { stock.remove(at: i) }
            else { stock[i].measure = .made(detail: leftoverDetail(kept), portions: kept) }
        } else if kept > 0 {
            stock.append(StockItem(key: name.lowercased(), name: name, plate: plate,
                                   section: .made, measure: .made(detail: leftoverDetail(kept), portions: kept),
                                   category: .other))
        }
    }

    private func leftoverDetail(_ n: Int) -> String { "\(n) \(n == 1 ? "portion" : "portions")" }

    /// Reassign a planned meal to a different part of its day, re-anchoring the hour
    /// so it keeps sorting morning → evening.
    func setMealPart(_ id: UUID, to part: DayPart) {
        updateMeal(id) { m in
            guard m.dayPart != part else { return m }
            let when = cal.date(bySettingHour: part.anchorHour, minute: 0, second: 0, of: m.date) ?? m.date
            return PlannedMeal(id: m.id, date: when, name: m.name, plate: m.plate, level: m.level,
                               dayPart: part, servings: m.servings, missingCount: m.missingCount)
        }
    }

    /// Change how many servings a planned meal is for (carried into the cook instrument).
    func setMealServings(_ id: UUID, to servings: Int) {
        guard servings > 0 else { return }
        updateMeal(id) { m in
            PlannedMeal(id: m.id, date: m.date, name: m.name, plate: m.plate, level: m.level,
                        dayPart: m.dayPart, servings: servings, missingCount: m.missingCount)
        }
    }

    private func updateMeal(_ id: UUID, _ transform: (PlannedMeal) -> PlannedMeal) {
        guard let i = events.firstIndex(where: {
            if case .meal(let m) = $0.kind { return m.id == id } else { return false }
        }), case .meal(let m) = events[i].kind else { return }
        events[i] = DatedEvent(kind: .meal(transform(m)))
    }

    func dismissProposal(_ id: UUID) {
        events.removeAll { if case .proposal(let p) = $0.kind { return p.id == id } else { return false } }
    }

    func resetNow() {
        fanOptions = composeFan()
        nowState = .open(options: fanOptions, selected: 0)
    }

    func beginCooking(_ dishes: [Dish], stepIndex: Int, totalSteps: Int) {
        guard let first = dishes.first else { return }
        let name = dishes.count > 1 ? "\(dishes.count) dishes together" : first.name
        nowState = .cooking(CookingProgress(name: name, plate: first.plate,
                                            stepIndex: stepIndex, totalSteps: totalSteps,
                                            timerText: nil, dish: first))
    }

    func finishCooking(_ dishes: [Dish]) {
        // Cooking is *production*: auto-log each dish (bank its servings + journal it)
        // — no extra tap, you already walked the steps — and return to the fan, where
        // the dish now shows as ready-made. Eating is logged separately, when you eat.
        for dish in dishes { logCooked(dish) }
        resetNow()
    }

    /// Record a cooked dish: bank its (scaled) servings as leftovers and journal it.
    /// This is the single "I made this" operation — reached from finishing the cook
    /// instrument or "Mark as made" on the recipe. No eat-time prompt; eating draws
    /// the leftover down separately.
    func logCooked(_ dish: Dish) {
        bankLeftover(name: dish.name, plate: dish.plate, add: dish.servings)
        journal.append(JournalItem(
            date: today, name: dish.name, plate: dish.plate, level: .cooked,
            note: "\(dish.servings) \(dish.servings == 1 ? "serving" : "servings")"))
    }

    /// Add `count` portions to a named leftover (cooking *produces* food), creating it
    /// if absent. Distinct from drawDownLeftover, which *sets* the remaining count.
    private func bankLeftover(name: String, plate: PlateComposition, add count: Int) {
        guard count > 0 else { return }
        if let i = stock.firstIndex(where: { $0.name == name && $0.isMade }) {
            let total = (stock[i].madePortions ?? 0) + count
            stock[i].measure = .made(detail: leftoverDetail(total), portions: total)
        } else {
            stock.append(StockItem(key: name.lowercased(), name: name, plate: plate,
                                   section: .made, measure: .made(detail: leftoverDetail(count), portions: count),
                                   category: .other))
        }
    }

    // MARK: - Stock & list mutations

    func updateStock(_ item: StockItem) {
        if let i = stock.firstIndex(where: { $0.id == item.id }) { stock[i] = item }
    }

    func removeStock(_ id: UUID) { stock.removeAll { $0.id == id } }

    func removeFromList(_ name: String) {
        let key = name.lowercased()
        shoppingList.removeAll { $0.name.lowercased() == key }
    }

    /// Commit a parsed composer phrase into the pantry — keeps the storage the user
    /// chose (no longer dropped) and seeds days-left from it via `makeStockItem`.
    func addToStock(_ intake: ParsedIntake) {
        let name = intake.suggestedName ?? intake.name
        guard !name.isEmpty else { return }
        let catalogItem = intake.resolvedItemID.flatMap { PantryCatalog.itemsByID[$0] }
        stock.append(makeStockItem(name: name, amount: Self.amountText(intake),
                                   storage: intake.storage, catalogItem: catalogItem,
                                   lastConfirmed: today))
    }

    func addToList(_ intake: ParsedIntake) {
        addToList(name: intake.suggestedName ?? intake.name, amount: Self.amountText(intake))
    }

    /// Add to the list, carrying a *desired* amount ("2 L", "12") when we know it.
    /// Adding something already listed updates its desired amount rather than
    /// duplicating.
    func addToList(name: String, amount: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let display = trimmed.prefix(1).capitalized + trimmed.dropFirst()
        let cleanAmount = amount?.trimmingCharacters(in: .whitespaces)
        if let i = shoppingList.firstIndex(where: { $0.name.lowercased() == display.lowercased() }) {
            if let cleanAmount, !cleanAmount.isEmpty { shoppingList[i].amount = cleanAmount }
            return
        }
        shoppingList.append(ShoppingEntry(name: display,
                                          amount: (cleanAmount?.isEmpty == false) ? cleanAmount : nil))
    }

    /// Free-text amount from a parsed phrase ("500 g", "2"), or nil.
    static func amountText(_ intake: ParsedIntake) -> String? {
        let text = [intake.quantity.map { QuantityFormat.short($0) },
                    intake.unit?.rawValue ?? intake.unrecognizedUnit]
            .compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// A plate face for a bare name (shopping-list rows, ad-hoc purchases) — resolve
    /// the catalog category (through aliases) if we know the item, else a neutral
    /// plate; EmojiPlate still picks a sensible face from the name.
    func plate(forName name: String) -> PlateComposition {
        let category = PantryCatalog.resolveExact(name: name)?.category ?? .other
        let seed = UInt64(name.lowercased().utf8.reduce(0) { $0 &+ UInt64($1) } &+ 23)
        return PlateComposition(categories: [category], seed: seed)
    }

    /// The single factory for a stocked item — the one place completeness is
    /// guaranteed: it resolves catalog identity, category, and storage (chosen ??
    /// catalog default ?? pantry), and seeds days-left from the chosen storage's
    /// shelf life via ExpiryEngine. Every intake path goes through here so no path
    /// can mint an incomplete ingredient.
    func makeStockItem(name: String, amount: String?, storage: PantryStorage?,
                       catalogItem: PantryCatalogItemDefinition?, lastConfirmed: Date) -> StockItem {
        let item = catalogItem ?? PantryCatalog.resolveExact(name: name)
        let category = item?.category ?? .other
        let store = storage ?? item?.defaultStorage ?? .pantry
        let seed = UInt64(name.lowercased().utf8.reduce(0) { $0 &+ UInt64($1) } &+ 23)
        let plate = PlateComposition(categories: [category], seed: seed)
        let cleaned = amount?.trimmingCharacters(in: .whitespaces)
        let detail = (cleaned?.isEmpty == false) ? cleaned! : "—"
        let display = name.isEmpty ? name : name.prefix(1).capitalized + name.dropFirst()
        let measure: StockItem.Measure
        let section: StockItem.Section
        if let item, item.resolutionClass == .staple {
            measure = .staple(.inStock); section = .staples
        } else {
            let days = ExpiryEngine.freshDaysLeft(catalogItemID: item?.id, storage: store, consumedFraction: 0)
            measure = .perishable(detail: detail, daysLeft: days); section = .have
        }
        return StockItem(key: name.lowercased(), name: display, plate: plate, section: section,
                         measure: measure, lastConfirmed: lastConfirmed,
                         catalogItemID: item?.id, category: category,
                         storage: store, storageSince: lastConfirmed, consumedFraction: 0)
    }

    /// Bought it: the item leaves the list and enters stock, freshly confirmed,
    /// with days-left seeded from its catalog default storage. Re-confirms instead
    /// of duplicating if it's already on hand (spec §3).
    func purchase(name: String, amount: String? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        removeFromList(trimmed)
        let key = trimmed.lowercased()
        let detail = amount?.trimmingCharacters(in: .whitespaces)
        if let i = stock.firstIndex(where: { $0.key == key }) {
            stock[i].lastConfirmed = today
            if let detail, !detail.isEmpty, case .perishable(_, let d) = stock[i].measure {
                stock[i].measure = .perishable(detail: detail, daysLeft: d)
            }
            return
        }
        stock.append(makeStockItem(name: trimmed, amount: amount, storage: nil,
                                   catalogItem: nil, lastConfirmed: today))
    }

    /// Log a recipe-less meal from composer items (the "just ate" path).
    func logMeal(_ intakes: [ParsedIntake]) {
        let names = intakes.map { $0.suggestedName ?? $0.name }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        let categories = intakes.compactMap { $0.resolvedItemID.flatMap { PantryCatalog.itemsByID[$0] }?.category }
        let plate = PlateComposition(categories: categories.isEmpty ? [.other] : categories,
                                     seed: UInt64(names.joined().utf8.reduce(0) { $0 &+ UInt64($1) } &+ 5))
        nowState = .cooked(CookedSummary(
            name: "Tonight: \(names.prefix(3).joined(separator: ", "))",
            plate: plate, summary: "Logged — \(names.count) item\(names.count == 1 ? "" : "s") from your kitchen."))
    }

    /// Perishables turning within the warning window — surfaced on Pantry as a
    /// warning band and counted on the Pantry tab badge, so spoilage is a warning
    /// the user sees from anywhere, not buried decoration.
    func expiringSoon(within days: Int = KitchenConfig.Stores.expiryWarningDays) -> [StockItem] {
        stock
            .compactMap { item -> (StockItem, Int)? in
                guard case .perishable = item.measure,
                      let d = item.daysLeft(now: today), d <= days else { return nil }
                return (item, d)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Live readiness for a dish — the single ReadinessService over current stock,
    /// matched through the one catalog-aware IngredientMatching path.
    ///
    /// Cached per dish: readiness is read many times per render (the feed's "Ready now"
    /// rail, the READY stamps, the tailpiece count, the fan) across a 200-dish library,
    /// and each evaluation walks the catalog for swaps — so recomputing every call made
    /// the feed crawl. The cache clears whenever anything readiness depends on changes,
    /// captured by a cheap fingerprint of present stock + the day.
    func readiness(for dish: Dish) -> Readiness {
        let key = readinessFingerprint
        if key != readinessCacheKey { readinessCache.removeAll(); readinessCacheKey = key }
        if let cached = readinessCache[dish.id] { return cached }
        let r = ReadinessService(presence: StockPresence(index: presenceIndex), swaps: CatalogSwapResolver())
            .evaluate(dish.requirements)
        readinessCache[dish.id] = r
        return r
    }

    /// Flips true once the post-launch warmup has filled the readiness cache. The feed
    /// gates its readiness-dependent bits (the "Ready now" rail, READY stamps, the
    /// ready count) on this so first paint isn't blocked computing readiness over 200
    /// dishes — they appear a beat later instead of behind a blank screen.
    var readinessReady = false

    @ObservationIgnored private var readinessCache: [UUID: Readiness] = [:]
    @ObservationIgnored private var readinessCacheKey = ""

    /// Post-launch warmup (runs after first paint): fill the readiness cache for the
    /// whole library, compose the opening fan from it, and reveal the ready bits.
    func warmReadinessAndFan() {
        for dish in library { _ = readiness(for: dish) }
        if case .open(let opts, _) = nowState, opts.isEmpty {
            fanOptions = composeFan()
            nowState = .open(options: fanOptions, selected: 0)
        }
        readinessReady = true
    }

    /// Everything readiness depends on, as a cheap string: the present (trusted) stock
    /// identities and the current day. Stock is small, so this is microseconds.
    private var readinessFingerprint: String {
        let day = Int(today.timeIntervalSince1970 / 86_400)
        return "\(day)|\(presentStockCatalogIDs.sorted().joined(separator: ","))|\(presentStockNames.sorted().joined(separator: ","))"
    }

    /// The "tonight you could" fan, built from what's actually here (spec §5):
    /// ready-made leftovers first — you'd heat and eat, not cook — then the dishes
    /// you can make right now (ready before swap-ready), skipping anything that
    /// clashes with the dietary profile. If little is fully ready, it's padded with
    /// the closest dishes so the fan is never empty.
    func composeFan() -> [FanOption] {
        var out: [FanOption] = []

        // 1) Ready-made: made/leftover stock you can eat tonight without cooking.
        for item in stock where item.section == .made && item.certainty(now: today) > .likelyGone {
            let detail: String
            if case .made(let d, _) = item.measure { detail = d } else { detail = "" }
            out.append(FanOption(
                name: item.name, plate: item.plate,
                subtitle: detail.isEmpty ? "ready-made" : detail,
                reason: "Already made — heat and eat.",
                readiness: .ready, level: .served, dish: nil))
        }

        // 2) Cookable now: dietary-safe library dishes, ready before swap-ready.
        let safe = library.filter { DishInsights.conflicts($0, with: profile).isEmpty }
            .map { (dish: $0, readiness: readiness(for: $0)) }
        for entry in safe.filter({ $0.readiness.isMakeableNow })
            .sorted(by: { Self.fanRank($0.readiness) < Self.fanRank($1.readiness) })
            .prefix(4) {
            out.append(fanOption(entry.dish, entry.readiness))
        }

        // 3) Never empty: if little is ready, offer the closest dishes (fewest missing).
        if out.count < 2 {
            for entry in safe.filter({ !$0.readiness.isMakeableNow })
                .sorted(by: { $0.readiness.missingCount < $1.readiness.missingCount })
                .prefix(3 - out.count) {
                out.append(fanOption(entry.dish, entry.readiness))
            }
        }
        return Array(out.prefix(5))
    }

    private func fanOption(_ dish: Dish, _ r: Readiness) -> FanOption {
        let detail: String
        switch r {
        case .ready: detail = "\(dish.time) · all on hand"
        case .readyWithSwaps(let s): detail = "\(dish.time) · \(SwapPhrase.count(s.count))"
        case .needs(let items): detail = "\(dish.time) · needs \(items.count)"
        }
        return FanOption(name: dish.name, plate: dish.plate, subtitle: detail,
                         reason: dish.blurb ?? "Ready from what you have.",
                         readiness: r, level: .cooked, dish: dish)
    }

    private static func fanRank(_ r: Readiness) -> Int {
        switch r { case .ready: return 0; case .readyWithSwaps: return 1; case .needs: return 2 }
    }

    /// Log a ready-made pick as eaten tonight — no cook instrument, just the record.
    func logEaten(_ option: FanOption) {
        nowState = .cooked(CookedSummary(
            name: option.name, plate: option.plate, summary: "Logged — eaten tonight."))
    }

    /// Whether a recipe line is on hand right now (for the gathering checklist) —
    /// same matcher as readiness, so the two can never disagree: catalog identity +
    /// lineage for an id-bearing line, name only for a line with no catalog id.
    func onHand(_ line: RecipeLine) -> Bool {
        if let id = line.catalogItemID { return presenceIndex.contains(catalogItemID: id) }
        return presenceIndex.contains(requirement: line.key)
    }

    /// The names we'll trust for readiness: everything except items the knowledge
    /// clock says are *probably gone*. This is the honesty rule — we stop asserting
    /// "on hand" for things we've almost certainly used up, so the fan and recipe
    /// readiness can't quietly lie. Uncertain items still count (we don't punish a
    /// casual logger) but get surfaced for a one-tap check in Stores.
    private var presentStockNames: [String] {
        let now = today
        return stock.filter { $0.certainty(now: now) > .likelyGone }.map(\.name)
    }

    /// The catalog identities we'll trust for readiness — same honesty rule as
    /// `presentStockNames`, but exact, so an ID-bearing recipe line matches without
    /// any name normalization.
    private var presentStockCatalogIDs: [String] {
        let now = today
        return stock.filter { $0.certainty(now: now) > .likelyGone }.compactMap(\.catalogItemID)
    }

    /// The single on-hand index, catalog/synonym-aware (see IngredientMatching).
    private var presenceIndex: IngredientMatching.Index {
        .init(names: presentStockNames, catalogIDs: presentStockCatalogIDs)
    }

    /// The certainty of a stocked key, for surfaces that want to hedge their wording.
    func certainty(forKey key: String) -> ItemCertainty? {
        stock.first { $0.key == key }?.certainty(now: today)
    }

    /// Items stale enough to be worth a one-tap "still here?" — drives the Stores
    /// re-confirmation nudge.
    var itemsNeedingCheck: [StockItem] {
        stock.filter { $0.needsCheck(now: today) }
    }

    // MARK: - Re-confirmation (the trust loop)

    /// "Still here." Reset the knowledge clock — confidence jumps back to certain.
    func reconfirm(_ id: UUID) {
        if let i = stock.firstIndex(where: { $0.id == id }) { stock[i].lastConfirmed = today }
    }

    /// "Finished." Drop it from stock and offer it back on the list.
    func markGone(_ id: UUID) {
        guard let i = stock.firstIndex(where: { $0.id == id }) else { return }
        let name = stock[i].name
        stock.remove(at: i)
        addToList(name: name)
    }

    func parse(_ phrase: String) -> ParsedIntake { parser.parse(phrase) }

    /// Pre-resolved catalog ids for the hand-built seed (curated dishes + demo stock),
    /// so `init` does ZERO catalog lookups — the 2,277-item catalog index then builds
    /// off the main thread (see the detached warm below) instead of blocking first paint.
    /// Regenerate via SeedDishCatalogTests if the seed's ingredient names change.
    private static let seedCatalogIDs: [String: String] = [
        "Applesauce": "applesauce", "Baby spinach": "baby-spinach-mix", "Butter": "butter",
        "Eggs": "egg", "Feta": "feta", "Flour": "flour", "Greek yogurt": "greek-yogurt",
        "Lamb mince": "lamb", "Lemon": "lemon", "Miso": "miso", "Olive oil": "olive-oil",
        "Onion": "onion", "Orzo": "pasta", "Paprika": "paprika", "Peas": "pea",
        "Salmon fillets": "salmon-oily-fish", "spinach": "spinach", "Spinach": "spinach",
        "Tomatoes": "tomato",
    ]

    init() {
        let cal = Calendar.current
        let now = Date()
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: now)! }
        func plate(_ c: [FoodCategory], _ s: UInt64) -> PlateComposition { .init(categories: c, seed: s) }
        func line(_ key: String, _ amount: String?, _ name: String, staple: Bool = false) -> RecipeLine {
            // Catalog identity is resolved once, here — so every seed line carries its
            // catalog id and readiness matches by id, never by fuzzy name.
            // (SeedDishCatalogTests guarantees they all resolve.)
            RecipeLine(key: key, amount: amount, name: name, isStaple: staple,
                       catalogItemID: Self.seedCatalogIDs[name] ?? IntakePipeline.bestCatalogID(for: name))
        }
        today = now

        // Cookable dishes — ingredients + steps so Cook never sends you to the pantry.
        let orzo = Dish(
            name: "Spinach & feta orzo", plate: plate([.produce, .dairy, .pasta], 1), time: "25 min",
            isFavorite: true,
            blurb: "Sweet greens through hot orzo — briny feta to finish.",
            ingredients: [
                line("baby spinach", "300 g", "Baby spinach"),
                line("feta", "200 g", "Feta"),
                line("orzo", "1 cup", "Orzo"),
                line("butter", "30 g", "Butter"),
                line("lemon", "1", "Lemon"),
                line("olive oil", nil, "Olive oil", staple: true)
            ],
            steps: [
                CookStep("Bring a pot of salted water to the boil and cook the orzo until al dente.", timerSeconds: 540, phase: .cook, attention: .passive),
                CookStep("Wilt the spinach into the brown butter until just collapsed — about two minutes.", timerSeconds: 120, phase: .cook, attention: .active),
                CookStep("Fold the orzo and crumbled feta through; finish with lemon, season, and serve.", phase: .finish, attention: .active)
            ],
            cuisine: "Mediterranean", mealType: "dinner", course: "main",
            diets: ["vegetarian"], methods: ["stovetop", "one-pan"])
        let shakshuka = Dish(
            name: "Shakshuka", plate: plate([.protein, .produce, .spices], 2), time: "30 min",
            blurb: "Eggs poached in a paprika tomato sauce.",
            ingredients: [line("eggs", "4", "Eggs"), line("tomato", "400 g", "Tomatoes"),
                          line("onion", "1", "Onion"), line("paprika", nil, "Paprika", staple: true)],
            steps: [CookStep("Soften the onion, add tomatoes and paprika, simmer to a sauce.", timerSeconds: 600, phase: .cook, attention: .passive),
                    CookStep("Make wells, crack in the eggs, cover and cook until just set.", timerSeconds: 480, phase: .cook, attention: .passive)],
            cuisine: "Middle Eastern", mealType: "breakfast", course: "main",
            diets: ["vegetarian", "gluten-free"], methods: ["one-pan", "stovetop"])
        let stirfry = Dish(
            name: "Tuesday stir-fry", plate: plate([.produce, .protein], 14), time: "20 min", isYours: true,
            isFavorite: true,
            blurb: "Hot pan, whatever's crisp, twenty minutes.",
            ingredients: [line("baby spinach", "200 g", "Spinach"), line("feta", "100 g", "Feta")],
            steps: [CookStep("Get the pan smoking hot, then go fast.", phase: .cook, attention: .active)],
            cuisine: "Asian", mealType: "dinner", course: "main",
            diets: ["vegetarian"], methods: ["stovetop", "one-pan"])
        let salmon = Dish(
            name: "Miso butter salmon", plate: plate([.protein, .oils], 5), time: "18 min",
            blurb: "Miso butter does the work; the oven the rest.",
            ingredients: [line("salmon", "2", "Salmon fillets"), line("miso", "2 tbsp", "Miso"),
                          line("butter", "20 g", "Butter")],
            steps: [CookStep("Whisk miso into soft butter; coat the salmon.", phase: .prep, attention: .active, ingredient: "salmon"),
                    CookStep("Roast until the centre just flakes.", timerSeconds: 600, phase: .cook, attention: .passive, ingredient: "salmon")],
            cuisine: "Japanese", mealType: "dinner", course: "main",
            diets: ["pescatarian", "gluten-free", "high-protein"], methods: ["bake"])
        let ragu = Dish(
            name: "Lamb ragù", plate: plate([.protein, .pasta, .produce], 3), time: "2 h 10",
            blurb: "Brown hard, braise low — and it freezes beautifully.",
            ingredients: [line("lamb", "500 g", "Lamb mince"), line("orzo", "2 cups", "Orzo"),
                          line("onion", "1", "Onion"), line("tomato", "400 g", "Tomatoes")],
            steps: [CookStep("Brown the lamb hard, then build the sofrito.", timerSeconds: 600, phase: .cook, attention: .active, ingredient: "lamb"),
                    CookStep("Add tomatoes and braise low and slow.", timerSeconds: 5400, phase: .cook, attention: .passive, ingredient: "tomato")],
            cuisine: "Italian", mealType: "dinner", course: "main",
            diets: ["high-protein"], methods: ["stovetop", "slow-cook"])
        let greens = Dish(
            name: "Lemon greens", plate: plate([.produce, .dairy], 7), time: "20 min",
            blurb: "Blistered greens, cold cheese, sharp lemon.",
            ingredients: [line("baby spinach", "200 g", "Spinach"), line("feta", "100 g", "Feta"),
                          line("lemon", "1", "Lemon")],
            steps: [CookStep("Blister the greens, dress with lemon, crumble over feta.", phase: .cook, attention: .active)],
            cuisine: "Mediterranean", mealType: "lunch", course: "side",
            diets: ["vegetarian", "gluten-free"], methods: ["stovetop"])
        let frittata = Dish(
            name: "Herb frittata", plate: plate([.dairy, .produce], 9), time: "15 min",
            blurb: "Beaten eggs, folded greens, five minutes under the grill.",
            ingredients: [line("eggs", "6", "Eggs"), line("feta", "100 g", "Feta"),
                          line("baby spinach", "100 g", "Spinach")],
            steps: [CookStep("Beat the eggs, fold in greens and feta, set under the grill.", timerSeconds: 480, phase: .cook, attention: .passive)],
            cuisine: "Italian", mealType: "breakfast", course: "main",
            diets: ["vegetarian", "gluten-free", "high-protein"], methods: ["one-pan", "stovetop"])

        // The seven hand-tuned showroom dishes lead (their steps + the demo stock make
        // them "ready now"); the generated dataset adds breadth so the feed's filters
        // have real variety. Dedupe by name, curated first.
        let curated = [frittata, orzo, shakshuka, stirfry, salmon, ragu, greens]
        var seenNames = Set(curated.map { $0.name.lowercased() })
        let seeded = RecipeSeed.all.filter { seenNames.insert($0.name.lowercased()).inserted }
        library = curated + seeded

        journal = [
            JournalItem(date: day(-4), name: "Spinach & feta orzo", plate: orzo.plate,
                        level: .cooked, note: "quick weeknight"),
            JournalItem(date: day(-2), name: "Lamb ragù", plate: plate([.protein, .pasta], 3),
                        level: .cooked, note: "batch cooked, 3 servings"),
            JournalItem(date: day(-1), name: "Shakshuka", plate: plate([.protein, .produce, .spices], 2),
                        level: .cooked, note: "your sixth this spring")
        ]
        // A planned meal anchored to its day-part's hour (mirrors planMeal), carrying
        // the dish's servings so the plan → cook hand-off scales correctly.
        func plannedMeal(_ d: Dish, inDays n: Int, _ part: DayPart, missing: Int = 0) -> DatedEvent {
            let when = cal.date(bySettingHour: part.anchorHour, minute: 0, second: 0, of: day(n)) ?? day(n)
            return DatedEvent(kind: .meal(PlannedMeal(
                date: when, name: d.name, plate: d.plate, level: .cooked,
                dayPart: part, servings: d.servings, missingCount: missing)))
        }
        let nowPart = DayPart.current(now)
        events = [
            // Today is planned: the current part's meal leads the now-module, the rest
            // show in "Today's plan".
            plannedMeal(stirfry, inDays: 0, nowPart),
            plannedMeal(salmon, inDays: 0, nowPart == .evening ? .midday : .evening, missing: 2),
            // A future day with two meals — shows the day-grouped card in the timeline.
            plannedMeal(shakshuka, inDays: 2, .morning, missing: 3),
            plannedMeal(orzo, inDays: 2, .evening, missing: 2),
            // A single far-out plan (week marker + fold around it) and an invite. Expiry
            // diamonds + the leftover whisper are NOT seeded here — they're derived live
            // from stock in `timelineEntries`, so the Plan tab can't contradict Pantry/Feed.
            plannedMeal(greens, inDays: 8, .evening, missing: 1),
            DatedEvent(kind: .proposal(Proposal(date: day(12), text: "Your list hit 5 items — milk runs out around Monday.")))
        ]
        whispers = []
        shoppingList = [
            ShoppingEntry(name: "Eggs", amount: "1 dozen"),
            ShoppingEntry(name: "Lemon", amount: "3"),
            ShoppingEntry(name: "Onion"),
            ShoppingEntry(name: "Miso", amount: "1 tub")
        ]

        func catalogID(_ name: String) -> String? { Self.seedCatalogIDs[name] ?? IntakePipeline.bestCatalogID(for: name) }
        // A realistic, moderately-stocked household kitchen: a leftover, a few things to
        // use soon, a full fridge/freezer, and the pantry backbone. catalogItemIDs are set
        // literally (the ids the seed recipes use) so readiness matches by identity and the
        // init does zero catalog lookups (launch stays fast).
        func perish(_ key: String, _ name: String, _ id: String, _ cat: FoodCategory, _ store: PantryStorage,
                    _ detail: String, daysLeft: Double, confirmed: Int, since: Int, _ seed: UInt64,
                    _ section: StockItem.Section = .have) -> StockItem {
            StockItem(key: key, name: name, plate: plate([cat], seed), section: section,
                      measure: .perishable(detail: detail, daysLeft: daysLeft),
                      lastConfirmed: day(confirmed), catalogItemID: id, category: cat,
                      storage: store, storageSince: day(since))
        }
        func staple(_ key: String, _ name: String, _ id: String, _ cat: FoodCategory,
                    _ level: StockItem.StapleLevel, _ seed: UInt64) -> StockItem {
            StockItem(key: key, name: name, plate: plate([cat], seed), section: .staples,
                      measure: .staple(level), catalogItemID: id, category: cat, storage: .pantry)
        }
        stock = [
            // Leftover from a batch-cook — the "eat first" whisper + a heat-and-eat plan.
            StockItem(key: "lamb ragu", name: "Lamb ragù", plate: plate([.protein, .pasta], 3),
                      section: .made, measure: .made(detail: "frozen · good through July", portions: 3),
                      lastConfirmed: day(-3), category: .protein, storage: .frozen, storageSince: day(-3)),

            // Use soon — the warning band.
            perish("baby spinach", "Baby spinach", "spinach", .produce, .refrigerated, "300 g", daysLeft: 2, confirmed: 0, since: 0, 1, .useSoon),
            perish("chicken thighs", "Chicken thighs", "chicken-thigh", .protein, .refrigerated, "6 thighs", daysLeft: 3, confirmed: -1, since: -1, 21, .useSoon),
            perish("milk", "Milk", "milk", .dairy, .refrigerated, "2 L", daysLeft: 5, confirmed: -2, since: -2, 9, .useSoon),

            // Fridge — on hand.
            StockItem(key: "eggs", name: "Eggs", plate: plate([.dairy], 5), section: .have,
                      measure: .perishable(detail: "10 left", daysLeft: 16), lastConfirmed: day(-3),
                      catalogItemID: "egg", category: .dairy, storage: .refrigerated, storageSince: day(-3)),
            perish("greek yogurt", "Greek yogurt", "greek-yogurt", .dairy, .refrigerated, "500 g", daysLeft: 9, confirmed: -2, since: -2, 4),
            perish("butter", "Butter", "butter", .dairy, .refrigerated, "250 g", daysLeft: 40, confirmed: -6, since: -6, 12),
            perish("cheddar", "Cheddar", "cheddar", .dairy, .refrigerated, "block", daysLeft: 30, confirmed: -6, since: -6, 14),
            perish("parmesan", "Parmesan", "parmesan", .dairy, .refrigerated, "wedge", daysLeft: 60, confirmed: -8, since: -8, 17),
            // Stale knowledge clock — plenty of shelf life, but logged 3 weeks ago, so it
            // reads "check?" (certainty decays even when the food clock is fine).
            perish("feta", "Feta", "feta", .dairy, .refrigerated, "200 g", daysLeft: 18, confirmed: -22, since: -2, 7),
            perish("carrots", "Carrots", "carrot", .produce, .refrigerated, "1 bag", daysLeft: 18, confirmed: -5, since: -5, 19),
            perish("broccoli", "Broccoli", "broccoli", .produce, .refrigerated, "1 head", daysLeft: 6, confirmed: -2, since: -2, 23),
            perish("tomatoes", "Tomatoes", "tomato", .produce, .refrigerated, "5", daysLeft: 8, confirmed: -3, since: -3, 25),
            perish("lemon", "Lemons", "lemon", .produce, .refrigerated, "3", daysLeft: 20, confirmed: -5, since: -5, 31),

            // Freezer.
            perish("ground beef", "Ground beef", "beef-ground", .protein, .frozen, "500 g", daysLeft: 120, confirmed: -14, since: -14, 27),
            perish("salmon", "Salmon fillets", "salmon-oily-fish", .protein, .frozen, "2 fillets", daysLeft: 120, confirmed: -14, since: -14, 33),
            perish("peas", "Frozen peas", "pea", .frozenFoods, .frozen, "1 bag", daysLeft: 120, confirmed: -10, since: -10, 13),

            // Pantry — on hand.
            StockItem(key: "onion", name: "Onions", plate: plate([.produce], 35), section: .have,
                      measure: .staple(.inStock), catalogItemID: "onion", category: .produce, storage: .pantry),
            StockItem(key: "garlic", name: "Garlic", plate: plate([.produce], 37), section: .have,
                      measure: .staple(.inStock), catalogItemID: "garlic", category: .produce, storage: .pantry),
            StockItem(key: "ginger", name: "Ginger", plate: plate([.produce], 39), section: .have,
                      measure: .staple(.inStock), catalogItemID: "ginger", category: .produce, storage: .pantry),
            StockItem(key: "canned tomatoes", name: "Canned tomatoes", plate: plate([.canned], 41), section: .have,
                      measure: .staple(.inStock), catalogItemID: "canned-ripe", category: .canned, storage: .pantry),
            StockItem(key: "black beans", name: "Black beans", plate: plate([.legumes], 43), section: .have,
                      measure: .staple(.inStock), catalogItemID: "black-beans", category: .legumes, storage: .pantry),
            StockItem(key: "chickpeas", name: "Chickpeas", plate: plate([.legumes], 45), section: .have,
                      measure: .staple(.inStock), catalogItemID: "chickpea", category: .legumes, storage: .pantry),
            StockItem(key: "tortillas", name: "Corn tortillas", plate: plate([.breads], 47), section: .have,
                      measure: .perishable(detail: "1 pack", daysLeft: 14), lastConfirmed: day(-4),
                      catalogItemID: "corn", category: .breads, storage: .pantry, storageSince: day(-4)),

            // Pantry backbone — staples.
            staple("rice", "Rice", "rice", .grains, .inStock, 49),
            staple("orzo", "Orzo", "pasta", .pasta, .inStock, 6),
            staple("flour", "Flour", "flour", .bakingSupplies, .inStock, 11),
            staple("oats", "Rolled oats", "oats", .grains, .inStock, 51),
            staple("soy sauce", "Soy sauce", "soy-sauce", .condiments, .inStock, 53),
            staple("olive oil", "Olive oil", "olive-oil", .oils, .runningLow, 8)
        ]

        // The cold-launch cost is the 2,277-item catalog index build (triggered the
        // first time anything resolves a name). Init no longer touches the catalog (seed
        // ids are pre-baked above), so force that build on a BACKGROUND thread, then warm
        // readiness + the fan on the main actor. First paint isn't blocked by either.
        nowState = .open(options: [], selected: 0)
        Task.detached(priority: .userInitiated) { [weak self] in
            _ = IntakePipeline.bestCatalogID(for: "salt")   // builds the catalog indices off-main
            await MainActor.run { self?.warmReadinessAndFan() }
        }

        // Screenshot/CI hook: open straight to a given space.
        if let forced = ProcessInfo.processInfo.environment["PC_SPACE"],
           let initial = RootSpace(rawValue: forced) {
            space = initial
        }

        // Render policy: anything that is a *dish* somewhere (library, fan,
        // journal) earns a painted plate; raw stock items stay emoji.
        Task { @MainActor [weak self] in
            guard let self else { return }
            PlateRenderLibrary.shared.eligibility = { [weak self] name in
                guard let self else { return false }
                let key = PlateRenderLibrary.slug(name)
                return self.library.contains { PlateRenderLibrary.slug($0.name) == key }
                    || self.fanOptions.contains { PlateRenderLibrary.slug($0.name) == key }
                    || self.journal.contains { PlateRenderLibrary.slug($0.name) == key }
            }
        }
    }
}

/// PantryPresence backed by the one catalog-aware matcher.
private struct StockPresence: PantryPresence {
    let index: IngredientMatching.Index
    func hasOnHand(key: String, catalogItemID: String?) -> Bool {
        // An id-bearing ingredient matches by catalog identity + lineage only — no
        // fuzzy name reconciliation. Name matching is the fallback solely for a line
        // that carries no catalog id at all.
        if let id = catalogItemID { return index.contains(catalogItemID: id) }
        return index.contains(requirement: key)
    }
    func isKnownOut(key: String, catalogItemID: String?) -> Bool { false }
}

/// The live swap resolver for *readiness* — the confident tiers only (curated swaps +
/// tight sibling varieties), so "ready · N swaps" never leans on a loose family guess.
/// The recipe chooser asks `DishInsights.swaps(for:)` for the broader family tier too.
struct CatalogSwapResolver: SwapResolver {
    func swapTargets(for requirement: IngredientRequirement) -> [SwapTarget] {
        let item = requirement.catalogItemID.flatMap { PantryCatalog.itemsByID[$0] }
            ?? PantryCatalog.resolveExact(name: requirement.key)
        guard let item else { return [] }
        return CatalogSwaps.candidates(forItemID: item.id, includeFamily: false)
            .map { SwapTarget(key: $0.key, name: $0.name, catalogItemID: $0.id) }
    }
}
