import XCTest
@testable import PantryChef

/// Every shipped seed recipe must carry bundled plate art. The runtime painter only
/// fills in *new* user dishes, so a seed dish without its `<slug>.png` would silently
/// fall back to the emoji plate (or a live paint that needs a key) in production. This
/// guards against adding a recipe — or renaming one — and forgetting its art.
@MainActor
final class PlateArtCoverageTests: XCTestCase {

    func testEverySeedDishHasBundledPlateArt() {
        let dishes = RecipeSeed.all
        XCTAssertGreaterThan(dishes.count, 100, "Seed recipes failed to load — can't verify art coverage")

        let missing = dishes
            .filter { !PlateRenderLibrary.hasBundledArt(for: $0.name) }
            .map { "\($0.name)  →  \(PlateRenderLibrary.slug($0.name)).png" }

        XCTAssertTrue(missing.isEmpty,
                      "\(missing.count) seed dish(es) ship without bundled plate art:\n  "
                        + missing.joined(separator: "\n  "))
    }
}
