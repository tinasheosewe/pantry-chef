import XCTest
import UniformTypeIdentifiers
@testable import PantryChef

/// The share-extension → app handoff contract: the inbox round-trips and drains, and the
/// extractor pulls the right recipe candidate out of synthetic shared items (no actual
/// share sheet needed — that's the point of factoring this out).
final class SharedRecipeInboxTests: XCTestCase {

    override func setUp() { super.setUp(); SharedRecipeInbox.clear() }
    override func tearDown() { SharedRecipeInbox.clear(); super.tearDown() }

    func testInboxRoundTripsAndDrains() {
        XCTAssertTrue(SharedRecipeInbox.all().isEmpty)
        SharedRecipeInbox.add(PendingRecipeImport(source: .url("https://example.com/banana-bread")))
        SharedRecipeInbox.add(PendingRecipeImport(source: .text("nonna's sauce: garlic, tomatoes, basil")))
        XCTAssertEqual(SharedRecipeInbox.all().count, 2)

        let drained = SharedRecipeInbox.drain()
        XCTAssertEqual(drained.count, 2)
        XCTAssertEqual(drained.first?.source, .url("https://example.com/banana-bread"))
        XCTAssertEqual(drained.last?.source, .text("nonna's sauce: garlic, tomatoes, basil"))
        XCTAssertTrue(SharedRecipeInbox.all().isEmpty, "drain clears the inbox")
    }

    func testExtractorPrefersAURL() async {
        let provider = NSItemProvider(object: URL(string: "https://simplyrecipes.com/banana-bread")! as NSURL)
        let item = NSExtensionItem(); item.attachments = [provider]
        let result = await ShareItemExtractor.extract(from: [item])
        XCTAssertEqual(result?.source, .url("https://simplyrecipes.com/banana-bread"))
    }

    func testExtractorTakesPlainText() async {
        let provider = NSItemProvider(object: "Garlic butter shrimp: 400g shrimp, 3 cloves garlic, butter, lemon" as NSString)
        let item = NSExtensionItem(); item.attachments = [provider]
        let result = await ShareItemExtractor.extract(from: [item])
        if case .text(let t)? = result?.source { XCTAssertTrue(t.contains("shrimp")) }
        else { XCTFail("expected a text import, got \(String(describing: result?.source))") }
    }

    func testALinkSharedAsTextBecomesAUrlImport() async {
        let provider = NSItemProvider(object: "https://www.bbcgoodfood.com/recipes/lasagne" as NSString)
        let item = NSExtensionItem(); item.attachments = [provider]
        let result = await ShareItemExtractor.extract(from: [item])
        XCTAssertEqual(result?.source, .url("https://www.bbcgoodfood.com/recipes/lasagne"))
    }

    func testSoleURLDetection() {
        XCTAssertEqual(ShareItemExtractor.soleURL(in: "  https://x.com/r  "), "https://x.com/r")
        XCTAssertNil(ShareItemExtractor.soleURL(in: "check out https://x.com/r it's great"))
        XCTAssertNil(ShareItemExtractor.soleURL(in: "just some recipe text"))
    }
}
