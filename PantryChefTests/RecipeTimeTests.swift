import XCTest
@testable import PantryChef

/// Recipe durations read as minutes under an hour and hours (+ minutes) at or above
/// one — never "480 min".
final class RecipeTimeTests: XCTestCase {

    func testUnderAnHourStaysMinutes() {
        XCTAssertEqual(RecipeTime.format(5), "5 min")
        XCTAssertEqual(RecipeTime.format(25), "25 min")
        XCTAssertEqual(RecipeTime.format(59), "59 min")
    }

    func testWholeHours() {
        XCTAssertEqual(RecipeTime.format(60), "1 h")
        XCTAssertEqual(RecipeTime.format(120), "2 h")
        XCTAssertEqual(RecipeTime.format(480), "8 h")
    }

    func testHoursAndMinutes() {
        XCTAssertEqual(RecipeTime.format(90), "1 h 30")
        XCTAssertEqual(RecipeTime.format(130), "2 h 10")
    }

    func testOptionalPassthrough() {
        XCTAssertNil(RecipeTime.format(nil))
        XCTAssertEqual(RecipeTime.format(45), "45 min")
    }

    /// A dish keeps its raw string when the time can't be parsed, else reformats.
    func testDishTimeText() {
        func dish(_ time: String) -> Dish {
            Dish(name: "x", plate: .init(categories: [], seed: 0), time: time, ingredients: [])
        }
        XCTAssertEqual(dish("8 h").timeText, "8 h")
        // "480 min" parses to 480 → reads as hours, not raw minutes.
        XCTAssertEqual(dish("480 min").timeText, "8 h")
    }
}
