import XCTest
@testable import PantryChef

/// The procedural plate renderer is pure and deterministic, so it is tested
/// directly on its `PlateSpec` output — no rendering, no snapshots.
final class ProceduralPlateRendererTests: XCTestCase {

    private func comp(_ categories: [FoodCategory], seed: UInt64 = 1) -> PlateComposition {
        .init(categories: categories, seed: seed)
    }

    func testRenderIsDeterministic() {
        let c = comp([.produce, .dairy, .pasta], seed: 42)
        XCTAssertEqual(ProceduralPlateRenderer.render(c), ProceduralPlateRenderer.render(c))
    }

    func testSingleCategoryFoodMatchesItsTone() {
        XCTAssertEqual(ProceduralPlateRenderer.render(comp([.produce])).food,
                       PlatePalette.tone(for: .produce))
        XCTAssertEqual(ProceduralPlateRenderer.render(comp([.protein])).food,
                       PlatePalette.tone(for: .protein))
    }

    func testWeightShiftsTheBlendTowardTheHeavierCategory() {
        let produceHeavy = ProceduralPlateRenderer.render(.init(
            weights: [.init(category: .produce, weight: 9), .init(category: .protein, weight: 1)], seed: 1)).food
        let proteinHeavy = ProceduralPlateRenderer.render(.init(
            weights: [.init(category: .produce, weight: 1), .init(category: .protein, weight: 9)], seed: 1)).food
        // Produce is greener and less red than protein, so the blends order accordingly.
        XCTAssertGreaterThan(produceHeavy.g, proteinHeavy.g)
        XCTAssertLessThan(produceHeavy.r, proteinHeavy.r)
    }

    func testEmptyCompositionRendersANeutralPlateNotABareOne() {
        let spec = ProceduralPlateRenderer.render(comp([]))
        XCTAssertEqual(spec.food, RGBA(r: 0.80, g: 0.74, b: 0.62))   // documented neutral
        XCTAssertGreaterThanOrEqual(spec.flecks.count, 5)            // never empty
        XCTAssertEqual(spec.ceramic, PlatePalette.ceramic)
    }

    func testFleckCountStaysWithinBounds() {
        let few = ProceduralPlateRenderer.render(comp([.produce])).flecks.count
        let many = ProceduralPlateRenderer.render(comp(
            [.produce, .protein, .dairy, .grains, .spices, .oils, .nuts, .legumes, .pasta, .condiments])).flecks.count
        for count in [few, many] {
            XCTAssertGreaterThanOrEqual(count, 5)
            XCTAssertLessThanOrEqual(count, 16)
        }
    }

    func testAllFlecksLieWithinTheFoodDisc() {
        let spec = ProceduralPlateRenderer.render(comp([.produce, .protein, .grains], seed: 7))
        for fleck in spec.flecks {
            let radial = (fleck.x * fleck.x + fleck.y * fleck.y).squareRoot()
            XCTAssertLessThanOrEqual(radial, 0.62 + 1e-9, "fleck escaped the food disc")
        }
    }

    func testDifferentSeedsProduceDifferentPlates() {
        let a = ProceduralPlateRenderer.render(comp([.produce, .protein], seed: 1))
        let b = ProceduralPlateRenderer.render(comp([.produce, .protein], seed: 2))
        XCTAssertNotEqual(a.flecks, b.flecks, "different dishes should not share a fleck layout")
        XCTAssertEqual(a.food, b.food, "but the same categories keep the same base tone")
    }
}
