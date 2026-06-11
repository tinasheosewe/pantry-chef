import XCTest
@testable import PantryChef

/// Unit tests for the single source of dish readiness. Pure inputs via small test
/// doubles → exact `Readiness` outputs.
final class ReadinessServiceTests: XCTestCase {

    private struct Pantry: PantryPresence {
        var onHand: Set<String>
        var out: Set<String> = []
        func hasOnHand(_ key: String) -> Bool { onHand.contains(key) }
        func isKnownOut(_ key: String) -> Bool { out.contains(key) }
    }
    private struct Swaps: SwapResolver {
        var map: [String: [(key: String, name: String)]] = [:]
        func swapTargets(for key: String) -> [(key: String, name: String)] { map[key] ?? [] }
    }

    private func req(_ key: String, _ name: String, staple: Bool = false) -> IngredientRequirement {
        .init(key: key, displayName: name, isStaple: staple)
    }
    private func service(onHand: Set<String>, out: Set<String> = [],
                         swaps: [String: [(key: String, name: String)]] = [:]) -> ReadinessService {
        .init(presence: Pantry(onHand: onHand, out: out), swaps: Swaps(map: swaps))
    }

    func testEverythingOnHandIsReady() {
        let s = service(onHand: ["spinach", "feta", "orzo"])
        XCTAssertEqual(s.evaluate([req("spinach", "Spinach"), req("feta", "Feta"), req("orzo", "Orzo")]), .ready)
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
        let s = service(onHand: ["milk"], swaps: ["buttermilk": [(key: "milk", name: "Milk")]])
        XCTAssertEqual(s.evaluate([req("buttermilk", "Buttermilk")]),
                       .readyWithSwaps([SwapOption(fromName: "Buttermilk", toName: "Milk")]))
    }

    func testSwapTargetNotOnHandFallsToNeeds() {
        let s = service(onHand: [], swaps: ["buttermilk": [(key: "milk", name: "Milk")]])
        XCTAssertEqual(s.evaluate([req("buttermilk", "Buttermilk")]), .needs(items: ["Buttermilk"]))
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
        let s = service(onHand: ["milk"], swaps: ["buttermilk": [(key: "milk", name: "Milk")]])
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
