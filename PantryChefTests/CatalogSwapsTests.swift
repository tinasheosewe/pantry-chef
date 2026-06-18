import XCTest
@testable import PantryChef

/// Catalog-derived substitution tiers: curated swaps, sibling varieties (shared
/// immediate parent), and the broad same-base family — in confidence order, with
/// identity lineage excluded (a variant that *is* the ingredient isn't a "swap").
/// Uses real catalog ids: spinach's children (`flat-leaf-spinach`, `semi-savoy`),
/// `00-flour` (curated swaps), and the cross-subtree milk family.
final class CatalogSwapsTests: XCTestCase {

    private func ids(_ cs: [CatalogSwaps.Candidate]) -> [String] { cs.map(\.id) }

    func testCuratedSwapsComeFirst() {
        let cs = CatalogSwaps.candidates(forItemID: "00-flour", includeFamily: false)
        XCTAssertTrue(cs.contains { $0.id == "all-purpose" && $0.tier == .curated })
        XCTAssertEqual(cs.first?.tier, .curated)
    }

    func testSiblingsShareAParentButExcludeSelfAndLineage() {
        // Flour `00-flour` curates all-purpose/almond/bread; its other flour siblings
        // (cake flour, …) surface at the sibling tier. A curated item that's also a
        // sibling stays curated (the higher-confidence tier wins on dedup).
        let cs = CatalogSwaps.candidates(forItemID: "00-flour", includeFamily: false)
        XCTAssertTrue(cs.contains { $0.id == "cake-flour" && $0.tier == .sibling })
        XCTAssertTrue(cs.contains { $0.id == "all-purpose" && $0.tier == .curated })
        XCTAssertFalse(ids(cs).contains("00-flour")) // not itself
        XCTAssertFalse(ids(cs).contains("flour"))    // lineage (parent) = identity, not a swap
    }

    func testFamilyOnlyWhenRequested() {
        // chocolate-milk shares the base word "milk" but is not a child of almond
        // milk's parent — so it's a family candidate, present only with family on.
        let withFamily = CatalogSwaps.candidates(forItemID: "almond-non-dairy-milk", includeFamily: true)
        let confidentOnly = CatalogSwaps.candidates(forItemID: "almond-non-dairy-milk", includeFamily: false)
        XCTAssertTrue(withFamily.contains { $0.id == "chocolate-milk" && $0.tier == .family })
        XCTAssertFalse(ids(confidentOnly).contains("chocolate-milk"))
    }

    func testTiersAreInConfidenceOrder() {
        let cs = CatalogSwaps.candidates(forItemID: "almond-non-dairy-milk", includeFamily: true)
        let tiers = cs.map(\.tier.rawValue)
        XCTAssertEqual(tiers, tiers.sorted(), "candidates must be ordered curated → sibling → family")
    }

    func testOnePercentMilkIsAPlainMilkVarietyNotLactoseFree() {
        // `1` ("1% milk") was mis-nested under lactose-free-milk; it's ordinary dairy
        // 1% milk, so it now sits with the other plain-milk fat grades and is no longer
        // a confident (sibling) swap for the lactose-free line.
        let cs = CatalogSwaps.candidates(forItemID: "1", includeFamily: false)
        XCTAssertTrue(cs.contains { $0.id == "milk-2" && $0.tier == .sibling })
        XCTAssertTrue(cs.contains { $0.id == "whole-milk" && $0.tier == .sibling })
        XCTAssertFalse(ids(cs).contains("lactose-free-milk-2"))
        XCTAssertFalse(ids(cs).contains("lactose-free-milk-skim"))
    }
}
