import XCTest

/// Smoke test for the Field Notes redesign: the app launches onto the timeline
/// and the page-floor nav band reaches every space.
final class PantryChefUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchAndNavigateSpaces() {
        let app = XCUIApplication()
        app.launch()

        // The nav band's three spaces and the composer door.
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add"].exists)

        app.buttons["Dishes"].tap()
        XCTAssertTrue(app.staticTexts["Dishes"].waitForExistence(timeout: 5))

        app.buttons["Stores"].tap()
        XCTAssertTrue(app.staticTexts["Stores"].waitForExistence(timeout: 5))

        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 5))
    }
}
