import XCTest
@testable import PantryChef

/// The fuzzy matcher must tolerate real typos but not let short catalog words
/// (egg, oil, ham) swallow gibberish two edits away — the "nonsense → egg" bug.
final class FuzzyMatchFloorTests: XCTestCase {

    func testRealTypoOnALongWordStillCorrects() {
        let result = matchToken("chiken", in: ["chicken", "egg", "oil"])
        XCTAssertEqual(result.first?.token, "chicken")
    }

    func testGibberishDoesNotLandOnAShortWord() {
        // "xqzj" is many edits from any real word — must not resolve to egg/oil/ham.
        let result = matchToken("xqzj", in: ["egg", "oil", "ham", "chicken"])
        XCTAssertFalse(result.contains { $0.token == "egg" || $0.token == "oil" || $0.token == "ham" })
    }

    func testTwoEditGibberishNoLongerMatchesAThreeLetterWord() {
        // "ozz" → "egg" is 2 edits; with the length-scaled floor a 3-char word
        // only tolerates 1, so this must NOT match egg.
        let result = matchToken("ozz", in: ["egg", "oil", "chicken"])
        XCTAssertFalse(result.contains { $0.token == "egg" })
    }
}
