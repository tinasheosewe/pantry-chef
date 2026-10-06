import XCTest

/// Smoke test for the Field Notes redesign: the app launches onto Today and the
/// page-floor nav band reaches every space (Today · Plan · Pantry · ＋).
final class PantryChefUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchAndNavigateSpaces() {
        let app = XCUIApplication()
        app.launch()
        clearLaunchInterruptions(app)

        // The nav band's three spaces and the composer door.
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add"].exists)

        // Every space is reachable and the dock survives each hop.
        for tab in ["Plan", "Pantry", "Today"] {
            app.buttons[tab].tap()
            XCTAssertTrue(app.buttons[tab].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Add"].exists)
        }
    }

    /// Two things can sit over the dock after launch. A first launch (clean simulator)
    /// presents onboarding: wait for whichever comes up first — the dock or onboarding —
    /// and leave onboarding through its sample-kitchen exit. Later launches offer to
    /// import a link if one is on the clipboard: decline it.
    private func clearLaunchInterruptions(_ app: XCUIApplication) {
        let sample = app.buttons["Explore a sample kitchen first"]
        let today = app.buttons["Today"]
        let deadline = Date().addingTimeInterval(30)
        while !today.exists && !sample.exists && Date() < deadline {
            _ = sample.waitForExistence(timeout: 0.5)
        }
        // Both are presented a beat after the dock first appears, so give them a
        // moment before deciding they are not coming.
        if sample.waitForExistence(timeout: 3) { sample.tap() }
        let decline = app.alerts.buttons["Not now"]
        if decline.exists { decline.tap() }
    }
}
