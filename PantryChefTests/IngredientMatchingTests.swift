import XCTest
@testable import PantryChef

/// The one catalog-aware matcher: pantry items satisfy a requirement through
/// normalization (plurals, modifiers) and synonyms, not raw string equality
/// (consolidation audit §2). This is what makes "Baby spinach" on hand answer a
/// recipe that asks for "spinach".
final class IngredientMatchingTests: XCTestCase {

    func testExactNameMatches() {
        XCTAssertTrue(IngredientMatching.Index(names: ["Feta"]).contains(requirement: "feta"))
    }

    func testPluralOnHandSatisfiesSingularRequirement() {
        XCTAssertTrue(IngredientMatching.Index(names: ["Tomatoes"]).contains(requirement: "tomato"))
        XCTAssertTrue(IngredientMatching.Index(names: ["Eggs"]).contains(requirement: "egg"))
    }

    func testSingularOnHandSatisfiesPluralRequirement() {
        XCTAssertTrue(IngredientMatching.Index(names: ["Egg"]).contains(requirement: "eggs"))
    }

    func testUnrelatedItemDoesNotMatch() {
        XCTAssertFalse(IngredientMatching.Index(names: ["Chicken"]).contains(requirement: "beef"))
    }

    func testEmptyPantryMatchesNothing() {
        XCTAssertFalse(IngredientMatching.Index(names: []).contains(requirement: "egg"))
    }

    func testCaseAndWhitespaceInsensitive() {
        XCTAssertTrue(IngredientMatching.Index(names: ["  GREEK YOGURT "]).contains(requirement: "greek yogurt"))
    }
}
