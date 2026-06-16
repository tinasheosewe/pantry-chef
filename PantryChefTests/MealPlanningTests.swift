import XCTest
@testable import PantryChef

/// Day-granular planning with a light day-part: meals belong to a day, and an
/// optional morning/midday/evening tag tells lunch from dinner without a rigid slot
/// grid. The now-module's "you could…" voice follows the clock, not just dinner.
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
}
