import XCTest
@testable import PantryChef

/// Catalog-identity matching reconciles variants along the parent lineage instead of
/// fuzzy strings: a base ingredient and its variants satisfy each other, but siblings
/// do not (that's a swap, not the same ingredient). Uses real catalog ids — `spinach`
/// with descendants `flat-leaf-spinach` and `semi-savoy`.
final class IngredientMatchingLineageTests: XCTestCase {

    private func index(onHand ids: String...) -> IngredientMatching.Index {
        IngredientMatching.Index(names: [], catalogIDs: ids)
    }

    func testExactIDMatches() {
        XCTAssertTrue(index(onHand: "spinach").contains(catalogItemID: "spinach"))
    }

    func testOnHandVariantSatisfiesBaseRequirement() {
        // You have flat-leaf spinach; a recipe asking for plain spinach is satisfied.
        XCTAssertTrue(index(onHand: "flat-leaf-spinach").contains(catalogItemID: "spinach"))
    }

    func testOnHandBaseSatisfiesVariantRequirement() {
        // You have generic spinach; a recipe asking for flat-leaf spinach is satisfied.
        XCTAssertTrue(index(onHand: "spinach").contains(catalogItemID: "flat-leaf-spinach"))
    }

    func testSiblingsDoNotMatch() {
        // Flat-leaf on hand does not satisfy a semi-savoy requirement — same parent,
        // but neither is the other's base.
        XCTAssertFalse(index(onHand: "flat-leaf-spinach").contains(catalogItemID: "semi-savoy"))
    }

    func testUnrelatedDoesNotMatch() {
        XCTAssertFalse(index(onHand: "spinach").contains(catalogItemID: "kale"))
    }

    /// The honesty guard: a derived product descends from its source in the catalog
    /// tree, but they're a DIFFERENT category and not interchangeable — having a tomato
    /// must never read as "you can make this" for a recipe needing ketchup.
    func testCrossCategoryLineageDoesNotMatch() {
        // tomato (Produce) is an ancestor of ketchup (Condiments) — different categories.
        XCTAssertFalse(index(onHand: "tomato").contains(catalogItemID: "ketchup"))
        XCTAssertFalse(index(onHand: "ketchup").contains(catalogItemID: "tomato"))
        XCTAssertFalse(index(onHand: "apple").contains(catalogItemID: "applesauce"))
    }
}
