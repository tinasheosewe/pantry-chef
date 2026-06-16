import XCTest
@testable import PantryChef

/// The shipped seed dishes are the app's showroom — they must hold themselves to
/// the same rule the editor now enforces on the user: every ingredient maps to a
/// real catalog item, never a freeform line that resolves to nothing. We resolve
/// each line through the very pipeline the editor uses (`IntakePipeline`); a seed
/// ingredient that comes back `.custom` (no catalog home) fails the test.
@MainActor
final class SeedDishCatalogTests: XCTestCase {

    func testEverySeedIngredientResolvesToCatalog() {
        let store = KitchenStore()
        let seedDishes = store.library + store.fanOptions.compactMap(\.dish)
        let parser = IntakeParser()

        var violations: [String] = []
        for dish in seedDishes {
            for line in dish.ingredients {
                let (_, decision) = IntakePipeline.resolve(line.name) { parser.parse($0) }
                if case .custom = decision {
                    violations.append("\(dish.name): '\(line.name)' (key '\(line.key)') has no catalog match")
                }
            }
        }

        if !violations.isEmpty {
            XCTFail("Seed ingredient does not map to catalog:\n  " + violations.joined(separator: "\n  "))
        }
    }

    /// Catalog-by-id: every seed line must carry its resolved `catalogItemID`, so
    /// readiness matches by identity rather than re-running the name mapping.
    func testEverySeedLineCarriesCatalogID() {
        let store = KitchenStore()
        let seedDishes = store.library + store.fanOptions.compactMap(\.dish)

        var missing: [String] = []
        for dish in seedDishes {
            for line in dish.ingredients where line.catalogItemID == nil {
                missing.append("\(dish.name): '\(line.name)'")
            }
        }
        XCTAssertTrue(missing.isEmpty, "Seed line missing catalogItemID:\n  " + missing.joined(separator: "\n  "))
    }
}
