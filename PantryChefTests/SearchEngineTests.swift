import XCTest
@testable import PantryChef

// MARK: - RankedTextSearchEngineTests

/// Unit tests for `RankedTextSearchEngine<Item>` introduced in commit f642453.
///  - Ranking behaviour (exact > prefix > fuzzy)
///  - Token coverage scoring
///  - Multi-token queries
///  - Empty / whitespace queries
final class RankedTextSearchEngineTests: XCTestCase {

    // Minimal item type for test isolation
    private struct Tag {
        let name: String
    }

    private func makeEngine(items: [String]) -> RankedTextSearchEngine<Tag> {
        let tags = items.map { Tag(name: $0) }
        let fields = [WeightedField<Tag>(weight: 1.0, text: \.name)]
        return RankedTextSearchEngine(items: tags, fields: fields)
    }

    // MARK: - Empty input

    func testEmptyQueryReturnsAllItemsWithZeroScore() {
        let engine = makeEngine(items: ["apple", "banana", "cherry"])
        let results = engine.search("")
        XCTAssertEqual(results.count, 3, "All items should be returned for an empty query")
        XCTAssertTrue(results.allSatisfy { $0.score == 0.0 }, "Scores should all be zero for empty query")
    }

    func testWhitespaceOnlyQueryReturnsAllItemsWithZeroScore() {
        let engine = makeEngine(items: ["apple", "banana"])
        let results = engine.search("   ")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.score == 0.0 })
    }

    func testSearchAgainstEmptyItemSetReturnsNothing() {
        let engine = makeEngine(items: [])
        let results = engine.search("apple")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Exact match

    func testExactMatchScoresAboveTypoMatch() {
        // The engine applies fuzzy (Levenshtein) matching to QUERY tokens only when
        // there is no exact index entry for that token. Using a typo in the query lets
        // us compare exact-token score (1.0×) against fuzzy score (0.5×) for the same item.
        let engine = makeEngine(items: ["apple", "banana", "cherry"])

        let exactResults = engine.search("apple")
        let typoResults  = engine.search("aple")   // Levenshtein distance 1 from "apple"

        let exactScore = exactResults.first { $0.item.name == "apple" }?.score
        let fuzzyScore = typoResults.first  { $0.item.name == "apple" }?.score

        XCTAssertNotNil(exactScore, "Exact query 'apple' should find 'apple'")
        XCTAssertNotNil(fuzzyScore, "Typo query 'aple' should fuzzy-match 'apple'")

        if let exact = exactScore, let fuzzy = fuzzyScore {
            XCTAssertGreaterThan(exact, fuzzy,
                                 "Exact match score should be strictly higher than fuzzy typo match score")
        }
    }

    func testExactMatchIsCaseInsensitive() {
        let engine = makeEngine(items: ["Carrot", "carrot cake"])
        let results = engine.search("CARROT")
        XCTAssertFalse(results.isEmpty, "Case-insensitive exact match should return results")
        let exactResult = results.first { $0.item.name == "Carrot" }
        XCTAssertNotNil(exactResult)
    }

    // MARK: - Prefix scoring

    func testPrefixQueryReturnsMatchingItems() {
        let engine = makeEngine(items: ["blueberry", "blueberry muffin", "black bean"])
        let results = engine.search("blue")
        let names = results.map(\.item.name)
        XCTAssertTrue(names.contains("blueberry"), "Prefix 'blue' should match 'blueberry'")
        XCTAssertTrue(names.contains("blueberry muffin"), "Prefix 'blue' should match 'blueberry muffin'")
    }

    func testSingleCharQueryReturnsItems() {
        // Regression for 395116d: short queries must not be gated out.
        let engine = makeEngine(items: ["apple", "apricot", "banana"])
        let results = engine.search("a")
        let names = results.map(\.item.name)
        XCTAssertTrue(names.contains("apple"), "Single-char prefix 'a' should match 'apple'")
        XCTAssertTrue(names.contains("apricot"), "Single-char prefix 'a' should match 'apricot'")
        XCTAssertFalse(names.contains("banana"), "Single-char prefix 'a' should not match 'banana'")
    }

    func testTwoCharQueryReturnsItems() {
        let engine = makeEngine(items: ["peach", "pear", "plum", "grape"])
        let results = engine.search("pe")
        let names = results.map(\.item.name)
        XCTAssertTrue(names.contains("peach"), "'pe' should match 'peach'")
        XCTAssertTrue(names.contains("pear"), "'pe' should match 'pear'")
        XCTAssertFalse(names.contains("plum"), "'pe' should not match 'plum'")
        XCTAssertFalse(names.contains("grape"), "'pe' should not match 'grape'")
    }

    // MARK: - Scoring order

    func testResultsAreReturnedInDescendingScoreOrder() {
        let engine = makeEngine(items: ["tomato", "tomato sauce", "green tomato salad"])
        let results = engine.search("tomato")
        let scores = results.map(\.score)
        for i in 0..<(scores.count - 1) {
            XCTAssertGreaterThanOrEqual(scores[i], scores[i + 1], "Results must be sorted by descending score")
        }
    }

    func testFullExactTitleScoresHigherThanPartialMatch() {
        let engine = makeEngine(items: ["lemon", "lemon curd", "lemon verbena tea"])
        let results = engine.search("lemon")
        XCTAssertEqual(results.first?.item.name, "lemon", "Exact title 'lemon' should rank above 'lemon curd'")
    }

    // MARK: - Multi-token query

    func testMultiTokenQueryRequiresBothTokensToScore() {
        let engine = makeEngine(items: ["black bean", "black rice", "red bean"])
        let results = engine.search("black bean")
        XCTAssertFalse(results.isEmpty)
        let topResult = results.first
        XCTAssertEqual(topResult?.item.name, "black bean", "Full multi-token match should rank first")
    }

    func testMultiTokenQueryReturnsPartialMatchesWithLowerScore() {
        let engine = makeEngine(items: ["black bean", "black rice", "red bean", "spinach"])
        let results = engine.search("black bean")
        let blackBeanResult = results.first { $0.item.name == "black bean" }
        let blackRiceResult = results.first { $0.item.name == "black rice" }
        let spinachResult = results.first { $0.item.name == "spinach" }

        XCTAssertNotNil(blackBeanResult, "Full match should appear")
        XCTAssertNotNil(blackRiceResult, "Partial match (shares 'black') should appear")
        XCTAssertNil(spinachResult, "No-match 'spinach' should be excluded")

        if let full = blackBeanResult, let partial = blackRiceResult {
            XCTAssertGreaterThan(full.score, partial.score, "Full match should score above partial match")
        }
    }

    // MARK: - Field weight

    func testHigherWeightFieldScoresMoreStrongly() {
        struct Doc { let title: String; let subtitle: String }
        let items = [
            Doc(title: "Pasta", subtitle: "Italian meal"),
            Doc(title: "Italian grains", subtitle: "Pasta alternative")
        ]
        let fields = [
            WeightedField<Doc>(weight: 2.0, text: \.title),
            WeightedField<Doc>(weight: 1.0, text: \.subtitle)
        ]
        let engine = RankedTextSearchEngine(items: items, fields: fields)
        let results = engine.search("pasta")
        XCTAssertEqual(results.first?.item.title, "Pasta",
                       "Title match on heavily-weighted field should outrank subtitle match")
    }

    // MARK: - No match

    func testQueryWithNoMatchReturnsEmptyResults() {
        let engine = makeEngine(items: ["apple", "banana", "cherry"])
        let results = engine.search("zzz")
        XCTAssertTrue(results.isEmpty, "Unmatched query should return empty results")
    }
}

// MARK: - BitapSearcherTests

/// Unit tests for `BitapSearcher` introduced in commit a075702.
///  - Exact match fast path
///  - Fuzzy match within edit distance
///  - No match above threshold
///  - Edge cases (empty pattern, long pattern exceeding limit)
final class BitapSearcherTests: XCTestCase {

    // MARK: - Pattern creation

    func testCreatePatternSucceedsForNormalInput() {
        XCTAssertNotNil(BitapSearcher.createPattern(from: "apple"), "Should create pattern for normal input")
    }

    func testCreatePatternFailsForEmptyString() {
        XCTAssertNil(BitapSearcher.createPattern(from: ""), "Should return nil for empty pattern")
    }

    func testCreatePatternFailsForOverlongPattern() {
        let longPattern = String(repeating: "a", count: BitapSearcher.maxPatternLength + 1)
        XCTAssertNil(BitapSearcher.createPattern(from: longPattern),
                     "Should return nil for patterns exceeding maxPatternLength")
    }

    func testCreatePatternAtMaxLengthSucceeds() {
        let pattern = String(repeating: "x", count: BitapSearcher.maxPatternLength)
        XCTAssertNotNil(BitapSearcher.createPattern(from: pattern))
    }

    // MARK: - Exact match

    func testExactMatchReturnsZeroScore() {
        guard let pattern = BitapSearcher.createPattern(from: "apple") else {
            return XCTFail("Pattern creation failed")
        }
        let match = BitapSearcher.search(pattern, in: "apple")
        XCTAssertNotNil(match, "Exact match should be found")
        XCTAssertEqual(match?.score, 0.0, "Exact match should have score 0.0")
    }

    func testExactMatchIsCaseInsensitive() {
        guard let pattern = BitapSearcher.createPattern(from: "Apple") else {
            return XCTFail("Pattern creation failed")
        }
        let match = BitapSearcher.search(pattern, in: "apple")
        XCTAssertNotNil(match, "Case-insensitive exact match should succeed")
    }

    func testExactSubstringMatchSucceeds() {
        guard let pattern = BitapSearcher.createPattern(from: "butter") else {
            return XCTFail("Pattern creation failed")
        }
        let match = BitapSearcher.search(pattern, in: "peanut butter")
        XCTAssertNotNil(match, "'butter' should match substring in 'peanut butter'")
        XCTAssertNotNil(match?.score)
    }

    // MARK: - Fuzzy match

    func testOneCharTypoIsFoundWithDefaultThreshold() {
        guard let pattern = BitapSearcher.createPattern(from: "chiken") else {
            return XCTFail("Pattern creation failed")
        }
        // "chiken" vs "chicken" — one missing char inside the word
        let match = BitapSearcher.search(pattern, in: "chicken", threshold: 0.6)
        XCTAssertNotNil(match, "One-character typo 'chiken' should approximately match 'chicken'")
    }

    func testVeryDifferentStringDoesNotMatch() {
        guard let pattern = BitapSearcher.createPattern(from: "xyz") else {
            return XCTFail("Pattern creation failed")
        }
        let match = BitapSearcher.search(pattern, in: "apple", threshold: 0.3)
        XCTAssertNil(match, "'xyz' should not match 'apple' with a strict threshold")
    }

    func testExactMatchScoresBetterThanFuzzyMatch() {
        let text = "chicken"
        guard let exactPattern = BitapSearcher.createPattern(from: "chicken"),
              let fuzzyPattern = BitapSearcher.createPattern(from: "chiken") else {
            return XCTFail("Pattern creation failed")
        }
        let exactMatch = BitapSearcher.search(exactPattern, in: text)
        let fuzzyMatch = BitapSearcher.search(fuzzyPattern, in: text, threshold: 0.7)

        if let exact = exactMatch, let fuzzy = fuzzyMatch {
            XCTAssertLessThan(exact.score, fuzzy.score,
                              "Exact match score should be lower (better) than typo match score")
        } else {
            XCTAssertNotNil(exactMatch, "Exact pattern must match")
        }
    }

    // MARK: - Threshold gate

    func testMatchAboveThresholdIsExcluded() {
        guard let pattern = BitapSearcher.createPattern(from: "zzz") else {
            return XCTFail("Pattern creation failed")
        }
        // Use a very strict threshold that even a borderline match can't pass
        let match = BitapSearcher.search(pattern, in: "apple", threshold: 0.01)
        XCTAssertNil(match, "Should return nil when match score exceeds (is worse than) the threshold")
    }
}

// MARK: - CatalogSearchRegressionTests

/// Regression tests covering the search fixes in commits 395116d and a075702:
///  - Short queries (≤ 2 chars) return results via prefix expansion
///  - Result count is no longer capped at 20
///
/// These tests use the live PantryCatalog which ships with the app bundle.
final class CatalogSearchRegressionTests: XCTestCase {

    // MARK: - Short query prefix search

    func testOneCharQueryReturnsResults() {
        // Before 395116d, single-char queries used token matching only (no prefix),
        // so items whose catalog tokens are multi-char returned nothing.
        let results = CatalogSearchEngine.search("a")
        XCTAssertFalse(results.isEmpty, "Single-char query should return results via prefix expansion")
    }

    func testTwoCharQueryReturnsResults() {
        let results = CatalogSearchEngine.search("ap")
        XCTAssertFalse(results.isEmpty, "Two-char query should return results via prefix expansion")
        let names = results.map { $0.item.name.lowercased() }
        let hasAppleOrApricot = names.contains { $0.hasPrefix("ap") }
        XCTAssertTrue(hasAppleOrApricot, "Two-char prefix 'ap' should match items starting with 'ap'")
    }

    // MARK: - Result cap removal

    func testSearchForBroadTwoCharQueryExceedsTwentyResults() {
        // Before 395116d results were capped at 20; using "sa" reliably prefix-matches
        // many catalog items (salmon, salt, sage, saffron, salami, salsa, …).
        let results = CatalogSearchEngine.search("sa")
        XCTAssertGreaterThan(results.count, 20,
                             "Two-char prefix 'sa' should return more than 20 results after cap removal")
    }

    func testSearchForCommonWordExceedsTwentyResults() {
        // "c" matches a large number of catalog entries (carrot, chicken, cheese, etc.)
        let results = CatalogSearchEngine.search("c")
        XCTAssertGreaterThan(results.count, 20,
                             "Common single-char query should return more than 20 results")
    }

    // MARK: - Exact match quality

    func testExactIngredientNameAppearsInResults() {
        // Ensures the exact catalog item (not just items that share a token) appears
        // in the result set. Score-ordering is not asserted because items that contain
        // "garlic" as a token (e.g. "garlic bread") can tie on score.
        let results = CatalogSearchEngine.search("garlic")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.item.id == "garlic" },
                      "Exact catalog item 'garlic' must appear in results for query 'garlic'")
    }

    func testExactMatchRanksAbovePrefixMatches() {
        // "butter" is in the catalog; "buttermilk", "butternut squash" etc. are prefix matches.
        let results = CatalogSearchEngine.search("butter")
        guard let topResult = results.first else {
            return XCTFail("Search for 'butter' returned empty results")
        }
        XCTAssertEqual(topResult.item.id, "butter",
                       "Exact item 'butter' should rank first, above prefix matches like 'buttermilk'")
    }
}
