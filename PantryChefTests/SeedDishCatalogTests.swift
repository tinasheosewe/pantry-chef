import XCTest
@testable import PantryChef

/// The shipped seed dishes are the app's showroom — they must hold themselves to
/// the same rule the editor now enforces on the user: every ingredient maps to a
/// real catalog item, never a freeform line that resolves to nothing. We resolve
/// each line through the very pipeline the editor uses (`IntakePipeline`); a seed
/// ingredient that comes back `.custom` (no catalog home) fails the test.
@MainActor
final class SeedDishCatalogTests: XCTestCase {

    func testEverySeedIngredientResolvesToCatalog() {
        let store = KitchenStore()
        let seedDishes = store.library + store.fanOptions.compactMap(\.dish)
        let parser = IntakeParser()

        var violations: [String] = []
        for dish in seedDishes {
            for line in dish.ingredients {
                let (_, decision) = IntakePipeline.resolve(line.name) { parser.parse($0) }
                if case .custom = decision {
                    violations.append("\(dish.name): '\(line.name)' (key '\(line.key)') has no catalog match")
                }
            }
        }

        if !violations.isEmpty {
            XCTFail("Seed ingredient does not map to catalog:\n  " + violations.joined(separator: "\n  "))
        }
    }

    /// Catalog-by-id: every seed line must carry its resolved `catalogItemID`, so
    /// readiness matches by identity rather than re-running the name mapping.
    /// Every seed recipe carries a total time AND every step a real cook time, so the
    /// cook flow can always show an honest ETA for seeds (only user recipes may lack one).
    func testEverySeedRecipeAndStepIsTimed() {
        var missing: [String] = []
        for dish in RecipeSeed.all {
            if (dish.minutes ?? 0) <= 0 { missing.append("\(dish.name): no recipe time") }
            for (i, step) in dish.steps.enumerated() where (step.timerSeconds ?? 0) <= 0 {
                missing.append("\(dish.name) step \(i + 1): no cook time")
            }
        }
        XCTAssertTrue(missing.isEmpty, "Untimed seed recipe/step:\n  " + missing.joined(separator: "\n  "))
    }

    /// A seed ingredient's resolved catalog item must share a content word with the
    /// ingredient name — the guard against wild mis-maps (e.g. "canned tomatoes" →
    /// "canned ripe jackfruit") that quietly satisfy readiness with the wrong item.
    func testSeedIngredientIdsAreNotWildlyMismatched() {
        let byID = Dictionary(PantryCatalog.allItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let mods: Set<String> = ["canned", "tinned", "cooked", "fresh", "frozen", "dried", "ground",
            "whole", "mixed", "chopped", "sliced", "minced", "diced", "crushed", "ripe", "baby", "raw",
            "boneless", "skinless", "extra", "virgin", "light", "low", "fat", "free", "reduced",
            "unsalted", "salted", "toasted", "roasted", "peeled", "plain", "fine", "coarse", "of",
            "the", "for", "with", "and", "jarred", "can", "tin", "long", "grain"]
        func content(_ s: String) -> Set<String> {
            Set(s.lowercased().folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US_POSIX"))
                .split { !$0.isLetter }
                .map { IngredientLexicon.depluralize(String($0)) }
                .filter { $0.count > 2 && !mods.contains($0) })
        }
        func fold(_ s: String) -> String {
            s.lowercased().folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US_POSIX"))
        }
        var bad: [String] = []
        for dish in RecipeSeed.all {
            for line in dish.ingredients {
                guard let id = line.catalogItemID, let item = byID[id] else { continue }
                let ic = content(line.name)
                guard !ic.isEmpty else { continue }
                var mc = content(item.name)
                for a in item.aliases { mc.formUnion(content(a)) }
                // A shared content word — exact, OR a ≥4-char content word contained in the
                // item's text (so "berry" matches "blueberry", but "tomato" still won't match
                // "jackfruit"). Wild mismatches share nothing either way.
                let hay = fold(([item.name] + item.aliases).joined(separator: " "))
                let matched = !ic.isDisjoint(with: mc)
                    || ic.contains { $0.count >= 4 && hay.contains($0) }
                if !matched {
                    bad.append("\(dish.name): '\(line.name)' → \(id) (\(item.name))")
                }
            }
        }
        XCTAssertTrue(bad.isEmpty, "Wildly mis-mapped seed ingredient id:\n  " + bad.joined(separator: "\n  "))
    }

    func testEverySeedLineCarriesCatalogID() {
        let store = KitchenStore()
        let seedDishes = store.library + store.fanOptions.compactMap(\.dish)

        var missing: [String] = []
        for dish in seedDishes {
            for line in dish.ingredients where line.catalogItemID == nil {
                missing.append("\(dish.name): '\(line.name)'")
            }
        }
        XCTAssertTrue(missing.isEmpty, "Seed line missing catalogItemID:\n  " + missing.joined(separator: "\n  "))
    }

    /// A dish's defining dried/ground spices must never be optional — you can't make
    /// tagine without cumin. (Fresh finishing herbs and salt/pepper are exempt: garnish
    /// herbs are a fair per-recipe call and salt/pepper are assumed-present staples.)
    func testDefiningSpicesAreNotOptional() {
        let byID = Dictionary(PantryCatalog.allItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let freshHerbs: Set<String> = [
            "cilantro", "parsley", "basil", "mint", "dill", "chives", "tarragon",
            "scallion", "green onion", "spring onion", "lemongrass", "watercress", "arugula",
            "herb", "herbs", "fresh herbs", "mixed herbs", "mixed fresh herbs"
        ]
        var offenders: [String] = []
        for dish in RecipeSeed.all {
            for line in dish.ingredients where !line.essential {
                guard let id = line.catalogItemID, let item = byID[id],
                      item.category == .spices else { continue }
                let n = item.name.lowercased(), ln = line.name.lowercased()
                if n.contains("salt") || n.contains("pepper") { continue }
                if freshHerbs.contains(n) || freshHerbs.contains(ln) { continue }
                offenders.append("\(dish.name): '\(line.name)' (\(id)) marked optional")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) defining dried spice(s) marked optional:\n  "
                        + offenders.prefix(20).joined(separator: "\n  "))
    }
}
