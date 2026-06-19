import XCTest
@testable import PantryChef

/// Day-granular planning with a light day-part: meals belong to a day, and an
/// optional morning/midday/evening tag tells lunch from dinner without a rigid slot
/// grid. The now-module's "you could…" voice follows the clock, not just dinner.
@MainActor
final class MealPlanningTests: XCTestCase {

    private func at(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }

    func testCurrentDayPartFollowsTheClock() {
        XCTAssertEqual(DayPart.current(at(8)), .morning)
        XCTAssertEqual(DayPart.current(at(13)), .midday)
        XCTAssertEqual(DayPart.current(at(20)), .evening)
        XCTAssertEqual(DayPart.current(at(2)), .evening, "late night reads as evening")
    }

    func testYouCouldEyebrowIsNotDinnerOnly() {
        let open = NowState.open(options: [], selected: 0)
        XCTAssertEqual(open.eyebrow(at: .morning), "This morning you could…")
        XCTAssertEqual(open.eyebrow(at: .midday), "For lunch you could…")
        XCTAssertEqual(open.eyebrow(at: .evening), "Tonight you could…")
    }

    func testCommittedAndCookedEyebrowsMatchTheTimeOfDay() {
        let committed = NowState.committed(.init(name: "X", plate: .init(categories: [.produce], seed: 1),
                                                 level: .cooked, logistics: "", dish: nil))
        XCTAssertEqual(committed.eyebrow(at: .morning), "This morning")
        XCTAssertEqual(committed.eyebrow(at: .evening), "Tonight")
    }

    func testDayPartsOrderMorningBeforeEveningAndAnchorEarlier() {
        XCTAssertTrue(DayPart.morning < DayPart.midday)
        XCTAssertTrue(DayPart.midday < DayPart.evening)
        XCTAssertLessThan(DayPart.morning.anchorHour, DayPart.evening.anchorHour)
    }

    func testPlannedMealCarriesItsPart() {
        let m = PlannedMeal(date: Date(), name: "Shakshuka",
                            plate: .init(categories: [.produce], seed: 1),
                            level: .cooked, dayPart: .morning)
        XCTAssertEqual(m.dayPart, .morning)
        XCTAssertEqual(m.dayPart.tag, "morning")
    }

    // MARK: - Planning for today: add, reassign, remove (store-level)

    func testPlanningForTodayThenReassignThenRemove() {
        let store = KitchenStore()
        let before = store.todaysPlannedMeals.count
        let dish = store.library[0]

        store.planMeal(dish, on: store.today, part: .evening)        // plan dinner today
        XCTAssertEqual(store.todaysPlannedMeals.count, before + 1)
        let planned = store.todaysPlannedMeals.last { $0.name == dish.name }
        XCTAssertEqual(planned?.dayPart, .evening)

        store.setMealPart(planned!.id, to: .morning)                 // reallocate to morning
        XCTAssertEqual(store.plannedMeals(on: store.today).first { $0.id == planned!.id }?.dayPart, .morning)

        store.removeMeal(planned!.id)                                // drop it
        XCTAssertEqual(store.todaysPlannedMeals.count, before)
        XCTAssertNil(store.todaysPlannedMeals.first { $0.id == planned!.id })
    }

    func testTodaysPlannedMealsReadMorningToEvening() {
        let store = KitchenStore()
        let dish = store.library[0]
        store.planMeal(dish, on: store.today, part: .evening)
        store.planMeal(dish, on: store.today, part: .morning)
        let parts = store.todaysPlannedMeals.map(\.dayPart)
        XCTAssertEqual(parts, parts.sorted(), "today's meals must order morning → evening")
    }

    func testPlanMealTakesTheDishServingsAndCanBeChanged() {
        let store = KitchenStore()
        let dish = store.library[0]
        store.planMeal(dish, on: store.today, part: .evening)
        let m = store.todaysPlannedMeals.last!
        XCTAssertEqual(m.servings, dish.servings, "a plan starts at the recipe's serving count")
        XCTAssertTrue(m.isCookable)
        store.setMealServings(m.id, to: 6)
        XCTAssertEqual(store.todaysPlannedMeals.first { $0.id == m.id }?.servings, 6)
    }

    func testPlanLeftoverIsHeatAndEatAndLogsAway() {
        let store = KitchenStore()
        let leftover = StockItem(key: "ragu", name: "Lamb ragù",
                                 plate: .init(categories: [.protein], seed: 1),
                                 section: .made, measure: .made(detail: "3 portions"),
                                 category: .protein)
        store.planLeftover(leftover, on: store.today, part: .evening, servings: 2)
        let m = store.todaysPlannedMeals.last { $0.name == "Lamb ragù" }
        XCTAssertEqual(m?.level, .served)
        XCTAssertEqual(m?.isCookable, false, "a leftover is logged, not cooked")
        XCTAssertEqual(m?.servings, 2)
        store.logPlannedMeal(m!)
        XCTAssertNil(store.todaysPlannedMeals.first { $0.id == m!.id }, "logging clears it from the plan")
    }

    // A leftover with a name not used by the seed stock, to avoid fixture collisions.
    private func minestroneLeftover(portions: Int) -> StockItem {
        StockItem(key: "minestrone", name: "Minestrone", plate: .init(categories: [.produce], seed: 1),
                  section: .made, measure: .made(detail: "\(portions) portions", portions: portions),
                  category: .other)
    }

    func testLoggingALeftoverDrawsDownThePortionsKept() {
        let store = KitchenStore()
        store.stock.append(minestroneLeftover(portions: 2))
        store.planLeftover(store.stock.last!, on: store.today, part: .evening, servings: 1)
        let m = store.todaysPlannedMeals.last { $0.name == "Minestrone" }!
        XCTAssertEqual(store.availablePortions(named: "Minestrone"), 2)
        store.logPlannedMeal(m, kept: 1)               // ate one of two
        XCTAssertEqual(store.availablePortions(named: "Minestrone"), 1, "one portion remains")
        XCTAssertNil(store.todaysPlannedMeals.first { $0.id == m.id }, "the plan is cleared")
    }

    func testLoggingAteItAllRemovesTheLeftover() {
        let store = KitchenStore()
        store.stock.append(minestroneLeftover(portions: 2))
        store.planLeftover(store.stock.last!, on: store.today, part: .evening, servings: 2)
        let m = store.todaysPlannedMeals.last { $0.name == "Minestrone" }!
        store.logPlannedMeal(m, kept: 0)               // ate it all
        XCTAssertNil(store.availablePortions(named: "Minestrone"))
        XCTAssertFalse(store.stock.contains { $0.name == "Minestrone" }, "nothing left → gone")
    }

    private func minestroneDish(servings: Int) -> Dish {
        Dish(name: "Minestrone", plate: .init(categories: [.produce], seed: 1), time: "30 min",
             servings: servings, ingredients: [])
    }

    func testLoggingACookBanksTheServingsAndJournalsIt() {
        let store = KitchenStore()
        let before = store.journal.count
        store.logCooked(minestroneDish(servings: 3))
        XCTAssertEqual(store.availablePortions(named: "Minestrone"), 3, "the full yield is banked")
        XCTAssertEqual(store.journal.count, before + 1, "the cook is recorded in the journal")
        store.logCooked(minestroneDish(servings: 3))   // cooked again → adds
        XCTAssertEqual(store.availablePortions(named: "Minestrone"), 6, "cooking more adds to the leftover")
    }

    func testFinishingACookAutoBanksAndReturnsToTheFan() {
        let store = KitchenStore()
        store.finishCooking([minestroneDish(servings: 2)])
        XCTAssertEqual(store.availablePortions(named: "Minestrone"), 2, "auto-banked, no extra tap")
        if case .open = store.nowState {} else { XCTFail("cooking should return to the fan") }
        XCTAssertTrue(store.fanOptions.contains { $0.name == "Minestrone" },
                      "the cooked dish surfaces as a ready-made fan option")
    }

    func testFinishingASingleCookBanksTheConfirmedYield() {
        let store = KitchenStore()
        // Recipe was for 4, but only 3 real portions came out — confirm the truth.
        store.finishCooking([minestroneDish(servings: 4)], madePortions: 3)
        XCTAssertEqual(store.availablePortions(named: "Minestrone"), 3,
                       "the confirmed yield is banked, not the recipe's nominal servings")
    }

    func testFinishingACookWithZeroPortionsBanksNothingButStillJournals() {
        let store = KitchenStore()
        let before = store.journal.count
        store.finishCooking([minestroneDish(servings: 2)], madePortions: 0)
        XCTAssertNil(store.availablePortions(named: "Minestrone"), "ate it all → nothing kept")
        XCTAssertEqual(store.journal.count, before + 1, "still recorded that it was made")
    }

    func testPortionConfirmationOnlyAppliesToSingleDishCooks() {
        let store = KitchenStore()
        // A multi-dish finish ignores a single portion count and banks each at default.
        store.finishCooking([minestroneDish(servings: 2), minestroneDish(servings: 2)], madePortions: 1)
        XCTAssertEqual(store.availablePortions(named: "Minestrone"), 4,
                       "multi-dish banks each dish at its own servings, not one shared count")
    }

    func testFavoritesPersistThroughRecipeNotesAndSurfaceInTheLens() {
        let store = KitchenStore()
        let dish = store.library.first { !$0.isFavorite }!
        XCTAssertFalse(store.favorites().contains { $0.id == dish.id })
        store.toggleFavorite(dish.id)
        XCTAssertEqual(store.recipeNotes[KitchenStore.recipeSlug(dish.name)]?.favorite, true,
                       "favorite is recorded in the persisted per-recipe note")
        XCTAssertTrue(store.favorites().contains { $0.name == dish.name }, "and surfaces in the favorites lens")
        store.toggleFavorite(dish.id)
        XCTAssertNil(store.recipeNotes[KitchenStore.recipeSlug(dish.name)], "un-favoriting clears the empty note")
    }

    func testRatingAndNotesRoundTripAndClear() {
        let store = KitchenStore()
        let dish = store.library[0]
        store.setRating(4, for: dish)
        store.setNotes("  add chili oil  ", for: dish)
        XCTAssertEqual(store.rating(for: dish), 4)
        XCTAssertEqual(store.notes(for: dish), "add chili oil", "notes are trimmed")
        store.setRating(nil, for: dish)
        XCTAssertNil(store.rating(for: dish))
        store.setNotes("   ", for: dish)
        XCTAssertNil(store.notes(for: dish), "blank notes clear the entry")
        XCTAssertNil(store.recipeNotes[KitchenStore.recipeSlug(dish.name)], "an emptied note drops out entirely")
    }

    func testTimesCookedAndLastCookedDeriveFromTheJournalNotEating() {
        let store = KitchenStore()
        let dish = minestroneDish(servings: 2)
        XCTAssertEqual(store.timesCooked(dish), 0)
        store.logCooked(dish)
        store.logCooked(dish)
        XCTAssertEqual(store.timesCooked(dish), 2, "each cook counts")
        XCTAssertEqual(store.lastCooked(dish).map { Calendar.current.startOfDay(for: $0) },
                       Calendar.current.startOfDay(for: store.today))
        // Eating it (a leftover) is logged but must NOT inflate the cooked count.
        store.logEaten(FanOption(name: dish.name, plate: dish.plate, subtitle: "", reason: "",
                                 level: .served, dish: dish))
        XCTAssertEqual(store.timesCooked(dish), 2, "eating isn't cooking")
    }

    func testEveryEatPathLandsInTheUnifiedLog() {
        let store = KitchenStore()
        let before = store.journal.count
        store.logEaten(FanOption(name: "Apple", plate: .init(categories: [.produce], seed: 2),
                                 subtitle: "", reason: "", level: .justAte, dish: nil))
        store.logMeal([])   // empty → no-op, shouldn't add
        XCTAssertEqual(store.journal.count, before + 1, "a ready-made pick is recorded; an empty ad-hoc log is a no-op")
    }

    func testReconfirmByKeyResetsTheKnowledgeClock() {
        let store = KitchenStore()
        let stale = StockItem(key: "test-leek", name: "Leek",
                              plate: .init(categories: [.produce], seed: 3),
                              section: .have, measure: .perishable(detail: "2", daysLeft: 6),
                              lastConfirmed: store.today.addingTimeInterval(-40 * 86_400))
        store.stock.append(stale)
        XCTAssertLessThanOrEqual(store.certainty(forKey: "test-leek") ?? .confirmed, .uncertain,
                                 "40 days without evidence reads as a hedge")
        store.reconfirm(key: "test-leek")
        XCTAssertEqual(store.certainty(forKey: "test-leek"), .confirmed,
                       "confirming in the readiness moment resets the clock to certain")
    }

    func testSoonestExpiryDaysUsedLeadsWithTheMostUrgentRescue() {
        let store = KitchenStore()
        guard let top = store.expiringSoon().first, let d = top.daysLeft(now: store.today) else {
            return XCTFail("seed kitchen should have expiring items")
        }
        let dish = Dish(name: "Rescue dish", plate: .init(categories: [.produce], seed: 9),
                        time: "10 min", servings: 2,
                        ingredients: [RecipeLine(key: top.key, name: top.name, catalogItemID: top.catalogItemID)])
        XCTAssertEqual(store.soonestExpiryDaysUsed(by: dish), d,
                       "a dish using the most-urgent item ranks at its days-left")
        let unrelated = Dish(name: "Nothing urgent", plate: .init(categories: [.produce], seed: 8),
                             time: "10 min", servings: 2,
                             ingredients: [RecipeLine(key: "totally-unrelated-xyz", name: "Xyz", catalogItemID: nil)])
        XCTAssertNil(store.soonestExpiryDaysUsed(by: unrelated), "rescuing nothing turning → nil")
    }

    func testExpiryReminderPlansCoverWhatsTurningAndRespectTheSetting() {
        let store = KitchenStore()
        let plans = store.expiryReminderPlans()
        XCTAssertFalse(plans.isEmpty, "the seed kitchen has perishables turning soon")
        XCTAssertTrue(plans.allSatisfy { !$0.names.isEmpty }, "every reminder names something")
        XCTAssertTrue(plans.allSatisfy { $0.fireAt.timeIntervalSince(store.today) > 0 },
                      "reminders are scheduled in the future, never in the past")
        XCTAssertEqual(plans.map(\.fireAt), plans.map(\.fireAt).sorted(),
                       "plans come back soonest-first")
        store.expiryReminders = false
        XCTAssertTrue(store.expiryReminderPlans().isEmpty, "off means no reminders at all")
    }

    func testUpdateCookingTimerMirrorsOntoTheNowCard() {
        let store = KitchenStore()
        store.beginCooking([minestroneDish(servings: 2)], stepIndex: 1, totalSteps: 4)
        store.updateCookingTimer("04:20")
        if case .cooking(let p) = store.nowState {
            XCTAssertEqual(p.timerText, "04:20", "the running timer mirrors onto the cook card")
        } else { XCTFail("should still be in the cooking state") }
        store.updateCookingTimer(nil)
        if case .cooking(let p) = store.nowState {
            XCTAssertNil(p.timerText, "clearing the timer clears the card's countdown")
        } else { XCTFail("clearing the timer must not drop the cooking state") }
    }

    func testPlanForNowMatchesTheCurrentPartOfDay() {
        let store = KitchenStore()
        store.events.removeAll()   // ignore the sample seed's own today-plans
        store.today = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!  // morning
        let dish = store.library[0]
        store.planMeal(dish, on: store.today, part: .evening)
        XCTAssertNil(store.planForNow, "an evening plan isn't 'now' in the morning")
        store.planMeal(dish, on: store.today, part: .morning)
        XCTAssertEqual(store.planForNow?.dayPart, .morning)
    }
}
