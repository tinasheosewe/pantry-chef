import XCTest
@testable import PantryChef

/// Property and example tests for the knowledge-certainty decay math. The engine
/// is pure, so every test injects an explicit `now` and asserts exact behaviour.
final class ConfidenceEngineTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func days(_ n: Double, after date: Date) -> Date {
        date.addingTimeInterval(n * 86_400)
    }

    // MARK: - Core decay properties

    func testFreshlyConfirmedIsFullConfidence() {
        let c = ConfidenceEngine.confidence(lastConfirmed: t0, now: t0,
                                            shelfLifeDays: 7, resolutionClass: .perishable)
        XCTAssertEqual(c, 1.0, accuracy: 1e-9)
        XCTAssertEqual(ConfidenceEngine.certainty(lastConfirmed: t0, now: t0,
                                                  shelfLifeDays: 7, resolutionClass: .perishable),
                       .confirmed)
    }

    func testConfidenceStrictlyDecreasesOverTime() {
        var previous = 1.0001
        for d in stride(from: 0.0, through: 30.0, by: 1.0) {
            let c = ConfidenceEngine.confidence(lastConfirmed: t0, now: days(d, after: t0),
                                                shelfLifeDays: 7, resolutionClass: .perishable)
            XCTAssertLessThan(c, previous, "confidence did not decrease at day \(d)")
            previous = c
        }
    }

    func testConfidenceHalvesEveryHalfLife() {
        // perishable factor is 1.0, so a 10-day shelf life → 10-day knowledge half-life.
        let half = ConfidenceEngine.confidence(lastConfirmed: t0, now: days(10, after: t0),
                                               shelfLifeDays: 10, resolutionClass: .perishable)
        XCTAssertEqual(half, 0.5, accuracy: 1e-9)
        let quarter = ConfidenceEngine.confidence(lastConfirmed: t0, now: days(20, after: t0),
                                                  shelfLifeDays: 10, resolutionClass: .perishable)
        XCTAssertEqual(quarter, 0.25, accuracy: 1e-9)
    }

    func testFutureClampedToNoElapsedTime() {
        // A `now` before lastConfirmed must not yield > 1.0.
        let c = ConfidenceEngine.confidence(lastConfirmed: t0, now: days(-5, after: t0),
                                            shelfLifeDays: 7, resolutionClass: .perishable)
        XCTAssertEqual(c, 1.0, accuracy: 1e-9)
    }

    // MARK: - Class modulation

    func testStaplesStayTrustedLongerThanPerishables() {
        let now = days(14, after: t0)
        let perishable = ConfidenceEngine.confidence(lastConfirmed: t0, now: now,
                                                     shelfLifeDays: 7, resolutionClass: .perishable)
        let staple = ConfidenceEngine.confidence(lastConfirmed: t0, now: now,
                                                 shelfLifeDays: 7, resolutionClass: .staple)
        XCTAssertGreaterThan(staple, perishable)
        // Concretely: two weeks on, the perishable's record is no longer trusted…
        XCTAssertLessThan(perishable, KitchenConfig.Confidence.probableAbove)
        // …while the staple's still is.
        XCTAssertGreaterThanOrEqual(staple, KitchenConfig.Confidence.probableAbove)
    }

    func testHalfLifeOrdersByClass() {
        let p = ConfidenceEngine.knowledgeHalfLifeDays(shelfLifeDays: 30, resolutionClass: .perishable)
        let s = ConfidenceEngine.knowledgeHalfLifeDays(shelfLifeDays: 30, resolutionClass: .semiCountable)
        let st = ConfidenceEngine.knowledgeHalfLifeDays(shelfLifeDays: 30, resolutionClass: .staple)
        XCTAssertLessThan(p, s)
        XCTAssertLessThan(s, st)
    }

    // MARK: - Degenerate inputs

    func testUnknownShelfLifeUsesFloorAndStaysFinite() {
        let c = ConfidenceEngine.confidence(lastConfirmed: t0, now: days(1, after: t0),
                                            shelfLifeDays: nil, resolutionClass: .perishable)
        XCTAssertTrue(c.isFinite)
        XCTAssertGreaterThan(c, 0)
        XCTAssertLessThanOrEqual(c, 1.0)
        // Floor is 2 days → one day elapsed → 0.5^(1/2) ≈ 0.707.
        XCTAssertEqual(c, pow(0.5, 0.5), accuracy: 1e-9)
    }

    func testZeroShelfLifeDoesNotDivideByZero() {
        let c = ConfidenceEngine.confidence(lastConfirmed: t0, now: days(3, after: t0),
                                            shelfLifeDays: 0, resolutionClass: .perishable)
        XCTAssertTrue(c.isFinite)
    }

    // MARK: - Buckets

    func testBucketBoundaries() {
        XCTAssertEqual(ConfidenceEngine.bucket(1.0), .confirmed)
        XCTAssertEqual(ConfidenceEngine.bucket(KitchenConfig.Confidence.confirmedAbove), .confirmed)
        XCTAssertEqual(ConfidenceEngine.bucket(KitchenConfig.Confidence.confirmedAbove - 0.01), .probable)
        XCTAssertEqual(ConfidenceEngine.bucket(KitchenConfig.Confidence.probableAbove), .probable)
        XCTAssertEqual(ConfidenceEngine.bucket(KitchenConfig.Confidence.probableAbove - 0.01), .uncertain)
        XCTAssertEqual(ConfidenceEngine.bucket(KitchenConfig.Confidence.uncertainAbove), .uncertain)
        XCTAssertEqual(ConfidenceEngine.bucket(KitchenConfig.Confidence.uncertainAbove - 0.01), .likelyGone)
        XCTAssertEqual(ConfidenceEngine.bucket(0.0), .likelyGone)
    }

    func testCertaintyIsOrdered() {
        XCTAssertLessThan(ItemCertainty.likelyGone, .uncertain)
        XCTAssertLessThan(ItemCertainty.uncertain, .probable)
        XCTAssertLessThan(ItemCertainty.probable, .confirmed)
    }

    // MARK: - Catalog-backed convenience (guarded)

    func testCatalogItemDegradesFromConfirmed() throws {
        guard let greens = ["Baby spinach", "Spinach", "Arugula"]
            .lazy.compactMap({ PantryCatalog.resolveExact(name: $0) }).first else {
            throw XCTSkip("No leafy-green item in catalog")
        }
        let storage = greens.defaultStorage
        let fresh = ConfidenceEngine.certainty(for: greens, storage: storage, lastConfirmed: t0, now: t0)
        XCTAssertEqual(fresh, .confirmed)
        let later = ConfidenceEngine.certainty(for: greens, storage: storage,
                                               lastConfirmed: t0, now: days(60, after: t0))
        XCTAssertLessThan(later, .confirmed, "a leafy green should not still read confirmed two months on")
    }
}
