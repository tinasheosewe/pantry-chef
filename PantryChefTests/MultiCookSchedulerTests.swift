import XCTest
@testable import PantryChef

final class MultiCookSchedulerTests: XCTestCase {

    private func dish(_ name: String, steps: Int) -> Dish {
        Dish(name: name, plate: .init(categories: [.produce], seed: 1), time: "10 min",
             ingredients: [], steps: (1...steps).map { CookStep("\(name)\($0)") })
    }

    func testInterleavesByStepIndex() {
        let schedule = MultiCookScheduler.schedule([dish("A", steps: 2), dish("B", steps: 3)])
        // every dish's step 1, then step 2, then B's lone step 3.
        XCTAssertEqual(schedule.map { "\($0.dishName):\($0.step.instruction)" },
                       ["A:A1", "B:B1", "A:A2", "B:B2", "B:B3"])
    }

    func testSingleDishIsItsOwnSteps() {
        XCTAssertEqual(MultiCookScheduler.schedule([dish("A", steps: 3)]).count, 3)
    }

    func testEmptyIsEmpty() {
        XCTAssertTrue(MultiCookScheduler.schedule([]).isEmpty)
    }
}
