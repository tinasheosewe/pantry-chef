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

    func testPlanForNowMatchesTheCurrentPartOfDay() {
        let store = KitchenStore()
        store.today = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!  // morning
        let dish = store.library[0]
        store.planMeal(dish, on: store.today, part: .evening)
        XCTAssertNil(store.planForNow, "an evening plan isn't 'now' in the morning")
        store.planMeal(dish, on: store.today, part: .morning)
        XCTAssertEqual(store.planForNow?.dayPart, .morning)
    }
}
