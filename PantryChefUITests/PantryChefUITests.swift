import XCTest

final class PantryChefUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSeededLaunchCanNavigateCoreTabs() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(rootTabButton(in: app, id: "home").waitForExistence(timeout: 5))

        rootTabButton(in: app, id: "pantry").tap()
        XCTAssertTrue(element(in: app, id: "pantry.screen").waitForExistence(timeout: 5))

        rootTabButton(in: app, id: "recipes").tap()
        XCTAssertTrue(element(in: app, id: "recipes.screen").waitForExistence(timeout: 5))

        rootTabButton(in: app, id: "plan").tap()
        XCTAssertTrue(element(in: app, id: "mealplan.shoppingListButton").waitForExistence(timeout: 5))

        rootTabButton(in: app, id: "shop").tap()
        XCTAssertTrue(element(in: app, id: "shopping.screen").waitForExistence(timeout: 5))
    }

    func testPantrySearchShowsSeededItem() {
        let app = makeApp()
        app.launch()

        rootTabButton(in: app, id: "pantry").tap()
        let searchField = app.textFields["Search pantry..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Milk")

        XCTAssertTrue(app.staticTexts["Milk"].waitForExistence(timeout: 5))
    }

    func testEmptyPantryScenarioShowsEmptyState() {
        let app = makeApp(additionalArguments: ["UITEST_EMPTY_STATE"])
        app.launch()

        rootTabButton(in: app, id: "pantry").tap()
        XCTAssertTrue(app.staticTexts["Your pantry is empty"].waitForExistence(timeout: 2))
    }

    func testPantryItemCanBeEdited() {
        let app = makeApp()
        app.launch()

        rootTabButton(in: app, id: "pantry").tap()

        let milkRow = app.buttons.containing(.staticText, identifier: "Milk").firstMatch
        XCTAssertTrue(milkRow.waitForExistence(timeout: 5))
        milkRow.tap()

        let quantityField = app.textFields["pantry.form.quantityField"]
        XCTAssertTrue(quantityField.waitForExistence(timeout: 5))
        replaceText(in: quantityField, with: "2")

        let saveButton = app.buttons["pantry.form.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["2 L"].waitForExistence(timeout: 5))
    }

    func testRecipeDetailShowsDirectTopBarActions() {
        let app = makeApp(additionalArguments: ["UITEST_RECIPE_DETAIL"])
        app.launch()

        rootTabButton(in: app, id: "recipes").tap()

        XCTAssertTrue(element(in: app, id: "recipe.detail.editButton").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, id: "recipe.detail.favoriteButton").waitForExistence(timeout: 5))
    }

    func testRecipesScreenShowsDirectSortButton() {
        let app = makeApp()
        app.launch()

        rootTabButton(in: app, id: "recipes").tap()

        XCTAssertTrue(element(in: app, id: "recipes.toolbar.sortMenu").waitForExistence(timeout: 5))
    }

    private func makeApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_MODE"] + additionalArguments
        return app
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        element.tap()

        if let existingValue = element.value as? String {
            let deleteSequence = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingValue.count)
            element.typeText(deleteSequence)
        }

        element.typeText(text)
    }

    private func element(in app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func rootTabButton(in app: XCUIApplication, id: String) -> XCUIElement {
        app.buttons["root.tabButton.\(id)"]
    }
}
