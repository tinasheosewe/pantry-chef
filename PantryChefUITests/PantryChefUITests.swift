import XCTest

/// Smoke test for the Field Notes redesign: the app launches onto Today and the
/// page-floor nav band reaches every space (Today · Ideas · Plan · Pantry · ＋).
final class PantryChefUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchAndNavigateSpaces() {
        let app = XCUIApplication()
        app.launch()

        // The nav band's four spaces and the composer door.
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add"].exists)

        // Every space is reachable and the dock survives each hop.
        for tab in ["Ideas", "Plan", "Pantry", "Today"] {
            app.buttons[tab].tap()
            XCTAssertTrue(app.buttons[tab].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Add"].exists)
        }
    }
}
