import XCTest
@testable import PantryChef

final class PantryChefTests: XCTestCase {
    func testSampleDataExists() {
        XCTAssertFalse(PantryItem.sampleItems.isEmpty)
        XCTAssertFalse(Recipe.sampleRecipes.isEmpty)
    }
}
