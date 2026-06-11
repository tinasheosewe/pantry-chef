import XCTest
@testable import PantryChef

final class UnitConversionTests: XCTestCase {

    func testParseAmount() {
        XCTAssertEqual(UnitConversion.parseAmount("1 cup")?.0, 1)
        XCTAssertEqual(UnitConversion.parseAmount("1 cup")?.1, .cup)
        XCTAssertEqual(UnitConversion.parseAmount("2 tbsp")?.1, .tablespoon)
        XCTAssertEqual(UnitConversion.parseAmount("300 g")?.1, .gram)
        XCTAssertEqual(UnitConversion.parseAmount("half cup")?.0, 0.5)
    }

    func testParseAmountRejectsUnitlessAndJunk() {
        XCTAssertNil(UnitConversion.parseAmount("2"))         // a count, no unit
        XCTAssertNil(UnitConversion.parseAmount(""))
        XCTAssertNil(UnitConversion.parseAmount("a handful")) // "handful" isn't a known unit
    }

    func testGramsMathFromDensity() throws {
        // Use a real catalog item that carries a cup density.
        guard let flour = ["All-purpose flour", "Flour", "Plain flour"]
            .lazy.compactMap({ PantryCatalog.resolveExact(name: $0) }).first(where: { $0.gramsPerCup != nil }) else {
            throw XCTSkip("no flour with density in catalog")
        }
        let perCup = flour.gramsPerCup!
        XCTAssertEqual(UnitConversion.grams(qty: 2, unit: .cup, item: flour)!, perCup * 2, accuracy: 0.001)
        XCTAssertEqual(UnitConversion.grams(qty: 1, unit: .tablespoon, item: flour)!, perCup / 16, accuracy: 0.001)
        XCTAssertNil(UnitConversion.grams(qty: 1, unit: .gram, item: flour))  // already mass
    }
}
