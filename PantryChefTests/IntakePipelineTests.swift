import XCTest
@testable import PantryChef

/// The intake decision: confident matches auto-accept, uncertain ones surface
/// candidates + Custom, genuine unknowns go straight to Custom — never a silent
/// force-match.
final class IntakePipelineTests: XCTestCase {

    private func intake(_ name: String, _ confidence: NameConfidence) -> ParsedIntake {
        ParsedIntake(quantity: nil, unit: nil, unrecognizedUnit: nil, name: name,
                     suggestedName: nil, storage: nil, resolvedItemID: nil, confidence: confidence)
    }
    private func cand(_ name: String, _ score: Double) -> IntakeCandidate {
        IntakeCandidate(id: name, name: name, score: score)
    }

    func testExactResolvedIsConfident() {
        XCTAssertEqual(IntakePipeline.decide(intake("Feta", .resolved), candidates: []), .confident)
    }

    func testStrongLoneFuzzyMatchAutoAccepts() {
        // "chiken" → chicken: high score, no close rival → accept silently.
        let d = IntakePipeline.decide(intake("chiken", .guessed), candidates: [cand("Chicken", 0.9)])
        XCTAssertEqual(d, .confident)
    }

    func testCloseRivalsAreAmbiguous() {
        // Two strong, near-tied candidates → ask the user.
        let d = IntakePipeline.decide(intake("pepper", .guessed),
                                      candidates: [cand("Black pepper", 0.88), cand("Bell pepper", 0.86)])
        if case .ambiguous(let c) = d { XCTAssertEqual(c.count, 2) } else { XCTFail("expected ambiguous, got \(d)") }
    }

    func testMediumMatchIsAmbiguous() {
        let d = IntakePipeline.decide(intake("greens", .guessed), candidates: [cand("Mixed greens", 0.66)])
        if case .ambiguous(let c) = d { XCTAssertEqual(c.first?.name, "Mixed greens") } else { XCTFail() }
    }

    func testNoViableCandidatesGoesToCustom() {
        XCTAssertEqual(IntakePipeline.decide(intake("xyzzy", .unresolved), candidates: []), .custom)
        // weak noise below the floor is not offered
        XCTAssertEqual(IntakePipeline.decide(intake("xyzzy", .unresolved),
                                             candidates: [cand("Egg", 0.4)]), .custom)
    }

    func testAmbiguousCapsAtMaxCandidates() {
        let many = (0..<9).map { cand("c\($0)", 0.7) }
        if case .ambiguous(let c) = IntakePipeline.decide(intake("x", .guessed), candidates: many) {
            XCTAssertEqual(c.count, IntakePipeline.maxCandidates)
        } else { XCTFail() }
    }
}
