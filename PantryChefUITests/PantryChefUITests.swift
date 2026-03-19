import XCTest

final class PantryChefUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSeededLaunchCanNavigateCoreTabs() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(element(in: app, id: "pantry.screen").waitForExistence(timeout: 5))

        app.tabBars.buttons["Recipes"].tap()
        XCTAssertTrue(element(in: app, id: "recipes.screen").waitForExistence(timeout: 5))

        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(element(in: app, id: "mealplan.shoppingListButton").waitForExistence(timeout: 5))

        app.tabBars.buttons["Shop"].tap()
        XCTAssertTrue(element(in: app, id: "shopping.screen").waitForExistence(timeout: 5))
    }

    func testPantrySearchShowsSeededItem() {
        let app = makeApp()
        app.launch()

        app.tabBars.buttons["Pantry"].tap()
        let searchField = app.textFields["Search pantry..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Milk")

        XCTAssertTrue(app.staticTexts["Milk"].waitForExistence(timeout: 5))
    }

    func testEmptyPantryScenarioShowsEmptyState() {
        let app = makeApp(additionalArguments: ["UITEST_EMPTY_STATE"])
        app.launch()

        app.tabBars.buttons["Pantry"].tap()
        XCTAssertTrue(app.staticTexts["Your pantry is empty"].waitForExistence(timeout: 2))
    }

    private func makeApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MODE"] + additionalArguments
        return app
    }

    private func element(in app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }
}
