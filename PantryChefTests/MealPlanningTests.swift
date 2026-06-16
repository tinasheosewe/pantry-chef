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
}
