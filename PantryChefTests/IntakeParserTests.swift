import XCTest
@testable import PantryChef

/// Corpus tests for the no-regex anchored-slot parser. Resolvers are injected so
/// the slot logic is exercised purely; a couple of guarded cases use the real
/// catalog end-to-end.
final class IntakeParserTests: XCTestCase {

    private func parser(known: Set<String> = [], guesses: [String: String] = [:]) -> IntakeParser {
        var p = IntakeParser()
        p.resolveExact = { name in
            known.contains(name.lowercased()) ? (id: "id-" + name.lowercased(), storage: .pantry) : nil
        }
        p.bestMatch = { name in
            guesses[name.lowercased()].map { (id: "guess", name: $0, storage: .refrigerated, score: 0.8) }
        }
        return p
    }

    func testQuantityUnitNameStorage() {
        let r = parser(known: ["baby spinach"]).parse("300 g baby spinach, fridge")
        XCTAssertEqual(r.quantity, 300)
        XCTAssertEqual(r.unit, .gram)
        XCTAssertEqual(r.name, "baby spinach")
        XCTAssertEqual(r.storage, .refrigerated)
        XCTAssertEqual(r.confidence, .resolved)
        XCTAssertNil(r.unrecognizedUnit)
    }

    func testCupsAndFraction() {
        let r = parser(known: ["sugar"]).parse("1/2 cup sugar")
        XCTAssertEqual(r.quantity, 0.5)
        XCTAssertEqual(r.unit, .cup)
        XCTAssertEqual(r.name, "sugar")
    }

    func testBareStapleHasNoQuantity() {
        let r = parser(known: ["olive oil"]).parse("olive oil")
        XCTAssertNil(r.quantity)
        XCTAssertNil(r.unit)
        XCTAssertEqual(r.name, "olive oil")
        XCTAssertEqual(r.confidence, .resolved)
    }

    func testContainerWordIsAUnit() {
        let r = parser(known: ["spinach"]).parse("half a bag of spinach")
        XCTAssertEqual(r.quantity, 0.5)
        XCTAssertEqual(r.unit, .package)   // "bag" → package
        XCTAssertEqual(r.name, "spinach")
        XCTAssertNil(r.unrecognizedUnit)
    }

    func testUnrecognizedUnitIsFlaggedNotDropped() {
        let r = parser(known: ["salmon"]).parse("1 jgirjgr of salmon")
        XCTAssertEqual(r.quantity, 1)
        XCTAssertNil(r.unit)
        XCTAssertEqual(r.unrecognizedUnit, "jgirjgr")
        XCTAssertEqual(r.name, "salmon")
        XCTAssertEqual(r.confidence, .resolved)   // the item still resolves; only the unit is unknown
    }

    func testGlugOfOliveOil() {
        let r = parser(known: ["olive oil"]).parse("a glug of olive oil")
        XCTAssertEqual(r.quantity, 1)             // "a" → 1
        XCTAssertEqual(r.unrecognizedUnit, "glug")
        XCTAssertEqual(r.name, "olive oil")
    }

    func testGuessedNameOffersACorrection() {
        let r = parser(guesses: ["greek yog": "Greek yogurt"]).parse("greek yog")
        XCTAssertEqual(r.confidence, .guessed)
        XCTAssertEqual(r.suggestedName, "Greek yogurt")
        XCTAssertEqual(r.name, "greek yog")
    }

    func testUnknownNameBecomesUnresolvedCustomItem() {
        let r = parser().parse("grandma's chili crisp")
        XCTAssertEqual(r.confidence, .unresolved)
        XCTAssertEqual(r.name, "grandma's chili crisp")
        XCTAssertNil(r.resolvedItemID)
    }

    func testStorageWordAnywhereAndNumberWord() {
        let r = parser().parse("dozen eggs freezer")
        XCTAssertEqual(r.quantity, 12)
        XCTAssertEqual(r.name, "eggs")
        XCTAssertEqual(r.storage, .frozen)
    }

    func testEmptyInputIsHarmless() {
        let r = parser().parse("   ")
        XCTAssertNil(r.quantity)
        XCTAssertEqual(r.name, "")
        XCTAssertEqual(r.confidence, .unresolved)
    }

    // MARK: - Real catalog (guarded)

    func testRealCatalogResolvesACommonIngredient() throws {
        let r = IntakeParser().parse("spinach")
        guard r.confidence != .unresolved else { throw XCTSkip("catalog has no spinach") }
        XCTAssertNotNil(r.resolvedItemID)
    }
}
