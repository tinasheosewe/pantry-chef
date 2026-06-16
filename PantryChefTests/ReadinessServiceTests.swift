import XCTest
@testable import PantryChef

/// Unit tests for the single source of dish readiness. Pure inputs via small test
/// doubles → exact `Readiness` outputs.
final class ReadinessServiceTests: XCTestCase {

    private struct Pantry: PantryPresence {
        var onHand: Set<String>
        var onHandIDs: Set<String> = []
        var out: Set<String> = []
        func hasOnHand(key: String, catalogItemID: String?) -> Bool {
            if let id = catalogItemID, onHandIDs.contains(id) { return true }
            return onHand.contains(key)
        }
        func isKnownOut(key: String, catalogItemID: String?) -> Bool { out.contains(key) }
    }
    private struct Swaps: SwapResolver {
        var map: [String: [SwapTarget]] = [:]
        func swapTargets(for requirement: IngredientRequirement) -> [SwapTarget] { map[requirement.key] ?? [] }
    }

    private func req(_ key: String, _ name: String, staple: Bool = false) -> IngredientRequirement {
        .init(key: key, displayName: name, isStaple: staple)
    }
    private func swap(_ key: String, _ name: String) -> SwapTarget {
        SwapTarget(key: key, name: name, catalogItemID: nil)
    }
    private func service(onHand: Set<String>, out: Set<String> = [],
                         swaps: [String: [SwapTarget]] = [:]) -> ReadinessService {
        .init(presence: Pantry(onHand: onHand, out: out), swaps: Swaps(map: swaps))
    }

    func testEverythingOnHandIsReady() {
        let s = service(onHand: ["spinach", "feta", "orzo"])
        XCTAssertEqual(s.evaluate([req("spinach", "Spinach"), req("feta", "Feta"), req("orzo", "Orzo")]), .ready)
    }

    /// Catalog-by-id: a requirement matches by its catalog id even when the name key
    /// is nowhere on hand — identity wins over fuzzy name matching.
    func testMatchesByCatalogIDWhenNameKeyAbsent() {
        let s = ReadinessService(presence: Pantry(onHand: [], onHandIDs: ["feta-aged-001"]),
                                 swaps: Swaps())
        let line = IngredientRequirement(key: "some-other-key", displayName: "Feta",
                                         isStaple: false, catalogItemID: "feta-aged-001")
        XCTAssertEqual(s.evaluate([line]), .ready)
    }

    func testCatalogIDMissIsNeeds() {
        let s = ReadinessService(presence: Pantry(onHand: [], onHandIDs: ["cheddar-001"]),
                                 swaps: Swaps())
        let line = IngredientRequirement(key: "feta", displayName: "Feta",
                                         isStaple: false, catalogItemID: "feta-aged-001")
        XCTAssertEqual(s.evaluate([line]), .needs(items: ["Feta"]))
    }

    func testEmptyRequirementsIsReady() {
        XCTAssertEqual(service(onHand: []).evaluate([]), .ready)
    }

    func testMissingWithoutSwapIsNeeds() {
        let s = service(onHand: ["spinach"])
        XCTAssertEqual(s.evaluate([req("spinach", "Spinach"), req("salmon", "Salmon")]),
                       .needs(items: ["Salmon"]))
    }

    func testMissingWithSwapOnHandIsReadyWithSwaps() {
        let s = service(onHand: ["milk"], swaps: ["buttermilk": [swap("milk", "Milk")]])
        XCTAssertEqual(s.evaluate([req("buttermilk", "Buttermilk")]),
                       .readyWithSwaps([SwapOption(fromName: "Buttermilk", toName: "Milk")]))
    }

    func testSwapTargetNotOnHandFallsToNeeds() {
        let s = service(onHand: [], swaps: ["buttermilk": [swap("milk", "Milk")]])
        XCTAssertEqual(s.evaluate([req("buttermilk", "Buttermilk")]), .needs(items: ["Buttermilk"]))
    }

    /// The cap: a dish leaning on too many substitutes stops being "makeable" and
    /// surfaces the swapped ingredients as needs (≤ a third of non-staples allowed).
    func testTooManySwapsIsNeedsNotReady() {
        // 3 non-staple ingredients, all only satisfiable by a swap → cap is 1, so 3
        // swaps blows it: not makeable.
        let s = service(onHand: ["a2", "b2", "c2"],
                        swaps: ["a": [swap("a2", "A2")], "b": [swap("b2", "B2")], "c": [swap("c2", "C2")]])
        XCTAssertEqual(s.evaluate([req("a", "A"), req("b", "B"), req("c", "C")]),
                       .needs(items: ["A", "B", "C"]))
    }

    func testSwapsWithinCapStayReady() {
        // 3 non-staples, only one swapped (cap 1) → still makeable with a swap.
        let s = service(onHand: ["a2", "b", "c"], swaps: ["a": [swap("a2", "A2")]])
        XCTAssertEqual(s.evaluate([req("a", "A"), req("b", "B"), req("c", "C")]),
                       .readyWithSwaps([SwapOption(fromName: "A", toName: "A2")]))
    }

    func testStaplesAreAssumedPresent() {
        // Salt isn't tracked on-hand, but as a staple it never blocks a dish.
        let s = service(onHand: ["spinach"])
        XCTAssertEqual(s.evaluate([req("spinach", "Spinach"), req("salt", "Salt", staple: true)]), .ready)
    }

    func testStapleFlaggedOutCountsAsMissing() {
        let s = service(onHand: ["spinach"], out: ["oliveOil"])
        XCTAssertEqual(s.evaluate([req("spinach", "Spinach"), req("oliveOil", "Olive oil", staple: true)]),
                       .needs(items: ["Olive oil"]))
    }

    func testRealMissingDominatesOverAvailableSwaps() {
        // One ingredient swappable, one genuinely missing → not makeable.
        let s = service(onHand: ["milk"], swaps: ["buttermilk": [swap("milk", "Milk")]])
        let result = s.evaluate([req("buttermilk", "Buttermilk"), req("salmon", "Salmon")])
        XCTAssertEqual(result, .needs(items: ["Salmon"]))
        XCTAssertEqual(result.missingCount, 1)
    }

    func testReadinessFlags() {
        XCTAssertTrue(Readiness.ready.isMakeableNow)
        XCTAssertTrue(Readiness.readyWithSwaps([]).isMakeableNow)
        XCTAssertFalse(Readiness.needs(items: ["x"]).isMakeableNow)
    }
}
