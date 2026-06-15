import XCTest
@testable import PantryChef

final class MultiCookSchedulerTests: XCTestCase {

    /// A dish whose steps are named `name1…nameN`, each with an optional timer so a
    /// test can mark a step active (short/none) or passive (a long walk-away timer).
    private func dish(_ name: String, _ timers: [Int?]) -> Dish {
        Dish(name: name, plate: .init(categories: [.produce], seed: 1), time: "10 min",
             ingredients: [],
             steps: timers.enumerated().map { CookStep("\(name)\($0.offset + 1)", timerSeconds: $0.element) })
    }

    private func names(_ schedule: [ScheduledStep]) -> [String] {
        schedule.map { $0.step.instruction }
    }

    // MARK: - Degenerate inputs

    func testEmptyIsEmpty() {
        XCTAssertTrue(MultiCookScheduler.schedule([]).isEmpty)
    }

    func testSingleDishIsItsOwnStepsInOrder() {
        let d = dish("A", [60, 1800, nil])
        XCTAssertEqual(names(MultiCookScheduler.schedule([d])), ["A1", "A2", "A3"])
    }

    // MARK: - Invariants

    /// Every step appears exactly once, and each dish's steps keep their order.
    func testEveryStepPlacedOncePreservingPerDishOrder() {
        let dishes = [dish("A", [nil, 1800, nil]), dish("B", [nil, nil]), dish("C", [600, nil, nil])]
        let schedule = MultiCookScheduler.schedule(dishes)

        XCTAssertEqual(schedule.count, 3 + 2 + 3)
        for d in dishes {
            let placed = schedule.filter { $0.dishName == d.name }.map { $0.step.instruction }
            XCTAssertEqual(placed, d.steps.map(\.instruction), "\(d.name) steps out of order or missing")
        }
    }

    // MARK: - The point of the rewrite

    /// A long passive step is started, then the *other* dish's hands-on work fills
    /// the idle window before we return to finish the first dish. The old
    /// round-robin could not express this.
    func testPassiveStepIsFrontLoadedAndItsWindowFilled() {
        // A: quick prep → long braise → quick finish.  B: two quick active steps.
        let a = dish("A", [nil, 1800, nil])
        let b = dish("B", [nil, nil])
        let schedule = names(MultiCookScheduler.schedule([a, b]))

        // The braise (A2) starts, then all of B happens, then A3 closes it out.
        XCTAssertEqual(schedule, ["A1", "A2", "B1", "B2", "A3"])
    }

    /// With two simmers available at once, the longer one goes on first.
    func testLongerPassiveStepStartsBeforeShorterOne() {
        let short = dish("S", [600])     // 10 min
        let long = dish("L", [3600])     // 60 min — should lead
        let schedule = names(MultiCookScheduler.schedule([short, long]))
        XCTAssertEqual(schedule, ["L1", "S1"])
    }
}
