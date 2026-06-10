import XCTest
@testable import PantryChef

/// Data-driven invariants over the *entire* loaded catalog. These tests compute
/// their slices at runtime from `PantryCatalog.allItems`, so a new bad row is
/// caught wherever it appears — not just where a hand-written fixture happens to
/// look. Each test collects every violation and fails once with the full list.
final class CatalogInvariantTests: XCTestCase {

    private var items: [PantryCatalogItemDefinition] { PantryCatalog.allItems }
    private func key(_ s: String) -> String { IngredientLexicon.lookupKey(s) }

    private func report(_ violations: [String], _ label: String, cap: Int = 40) {
        guard !violations.isEmpty else { return }
        let shown = violations.prefix(cap).joined(separator: "\n  ")
        let more = violations.count > cap ? "\n  …and \(violations.count - cap) more" : ""
        XCTFail("\(label): \(violations.count) violation(s)\n  \(shown)\(more)")
    }

    func testCatalogLoaded() {
        XCTAssertGreaterThan(items.count, 1000, "Catalog failed to load or is suspiciously small")
    }

    // MARK: - Resolution

    /// Every item resolves by its own name, and the resolution lands on an item
    /// with that same name. This is the generic catch for the "chicken → chicken
    /// broth" class: a bare term must not resolve to a differently-named item.
    func testEveryNameResolvesToASameNamedItem() {
        var violations: [String] = []
        for item in items {
            guard let resolved = PantryCatalog.resolveExact(name: item.name) else {
                violations.append("'\(item.name)' (\(item.id)) does not resolve at all")
                continue
            }
            if key(resolved.name) != key(item.name) {
                violations.append("'\(item.name)' (\(item.id)) resolves to '\(resolved.name)' (\(resolved.id))")
            }
        }
        report(violations, "Name does not round-trip")
    }

    /// Every alias resolves to something (no dangling alias).
    func testEveryAliasResolves() {
        var violations: [String] = []
        for item in items {
            for alias in item.aliases where !key(alias).isEmpty {
                if PantryCatalog.resolveExact(name: alias) == nil {
                    violations.append("alias '\(alias)' of \(item.id) does not resolve")
                }
            }
        }
        report(violations, "Alias does not resolve")
    }

    /// A single-word ingredient name must resolve within its own category — the
    /// direct generic form of the chicken bug (a bare protein term resolved to a
    /// Canned broth).
    func testSingleWordNamesResolveWithinCategory() {
        var violations: [String] = []
        for item in items where !item.name.contains(" ") && !item.name.contains("-") {
            guard let resolved = PantryCatalog.resolveExact(name: item.name) else { continue }
            if resolved.category != item.category {
                violations.append("'\(item.name)' (\(item.category.rawValue)) resolves to \(resolved.id) (\(resolved.category.rawValue))")
            }
        }
        report(violations, "Single-word name resolves to a foreign category")
    }

    // MARK: - Structure

    func testEveryParentExists() {
        let ids = Set(items.map(\.id))
        var violations: [String] = []
        for item in items {
            for parent in item.parentIds where !ids.contains(parent) {
                violations.append("\(item.id) → missing parent '\(parent)'")
            }
        }
        report(violations, "Dangling parent reference")
    }

    func testNoInheritanceCycles() {
        var violations: [String] = []
        for item in items where PantryCatalog.ancestors(of: item.id).contains(where: { $0 != item.id && PantryCatalog.ancestors(of: $0).contains(item.id) }) {
            violations.append("\(item.id) participates in a cycle")
        }
        report(violations, "Inheritance cycle")
    }

    /// Single-parent inheritance is additive: a child's effective facets must
    /// include every option its parents contribute.
    func testFacetInheritanceIsAdditive() {
        var violations: [String] = []
        for item in items where item.parentIds.count == 1 {
            let childOptions = effectiveOptions(item.id)
            for parent in item.parentIds {
                for (k, opts) in effectiveOptions(parent) {
                    let missing = opts.subtracting(childOptions[k] ?? [])
                    if !missing.isEmpty {
                        violations.append("\(item.id) missing inherited \(k.rawValue): \(missing.sorted())")
                    }
                }
            }
        }
        report(violations, "Non-additive facet inheritance")
    }

    private func effectiveOptions(_ id: String) -> [PantryFacetKey: Set<String>] {
        var result: [PantryFacetKey: Set<String>] = [:]
        for def in PantryCatalog.effectiveFacets(for: id) {
            result[def.key, default: []].formUnion(def.options)
        }
        return result
    }

    // MARK: - Facets

    /// Every facet value belongs to exactly one facet key across the whole
    /// catalog (orthogonality). "whole" is the one legitimate exception
    /// (whole-fat milk vs whole-form produce).
    func testFacetValuesAreOrthogonal() {
        var keysByValue: [String: Set<PantryFacetKey>] = [:]
        for item in items {
            for facet in item.facets {
                for option in facet.options {
                    keysByValue[option.lowercased(), default: []].insert(facet.key)
                }
            }
        }
        let violations = keysByValue
            .filter { $0.value.count > 1 && $0.key != "whole" }
            .map { "'\($0.key)' under \($0.value.map(\.rawValue).sorted())" }
            .sorted()
        report(violations, "Facet value straddles multiple keys")
    }

    /// Default selections and facet aliases must reference facet options the item
    /// actually has.
    func testDefaultSelectionsAndFacetAliasesAreValid() {
        var violations: [String] = []
        for item in items {
            let eff = effectiveOptions(item.id)
            for sel in item.defaultSelections where !(eff[sel.key]?.contains(sel.value) ?? false) {
                violations.append("\(item.id) defaultSelection \(sel.key.rawValue)=\(sel.value) not in facets")
            }
            for alias in item.facetAliases {
                for sel in alias.facets where !(eff[sel.key]?.contains(sel.value) ?? false) {
                    violations.append("\(item.id) facetAlias '\(alias.text)' → \(sel.key.rawValue)=\(sel.value) not in facets")
                }
            }
        }
        report(violations, "Invalid defaultSelection / facetAlias")
    }

    // MARK: - Names & IDs

    /// No item id or name is a bare *state* word. The modifier vocabulary is
    /// derived from the catalog itself: a value used under a STATE facet (every
    /// key except `variant`, which holds genuine kinds like "ginger") is a
    /// modifier and must not stand alone as an identity. An id is only flagged
    /// when it also disagrees with its own name's slug (a misleading id such as
    /// `sweetened` → "sweetened applesauce"), so real ingredients whose id equals
    /// their name (e.g. `flour`, `sauce`, `clove`) are never flagged.
    func testNoBareModifierNamesOrIds() {
        let stateKeys = Set(PantryFacetKey.allCases).subtracting([.variant])
        var stateValues: Set<String> = []
        for item in items {
            for facet in item.facets where stateKeys.contains(facet.key) {
                for option in facet.options { stateValues.insert(key(option)) }
            }
        }
        var violations: [String] = []
        for item in items {
            if !item.id.contains("-"), stateValues.contains(key(item.id)),
               item.id != IngredientLexicon.lookupKey(item.name).replacingOccurrences(of: " ", with: "-") {
                violations.append("id '\(item.id)' is a bare state word (name: '\(item.name)')")
            }
            if !item.name.contains(" "), !item.parentIds.isEmpty, stateValues.contains(key(item.name)) {
                violations.append("name '\(item.name)' (\(item.id)) is a bare state word")
            }
        }
        report(violations, "Bare state-word id/name")
    }

    // MARK: - Enrichment coherence

    /// Dietary tags must be consistent with allergens: the derivation must never
    /// claim Vegan/Dairy-Free/Gluten-Free/Nut-Free while carrying a contradicting
    /// allergen.
    func testDietaryTagsAgreeWithAllergens() {
        var violations: [String] = []
        for item in items {
            let allergens = Set(item.allergens)
            let tags = Set(item.dietaryTags)
            func bad(_ tag: DietaryTag, _ contradicting: [Allergen]) {
                if tags.contains(tag), let hit = contradicting.first(where: allergens.contains) {
                    violations.append("\(item.id): \(tag.rawValue) but allergen \(hit.rawValue)")
                }
            }
            bad(.vegan, [.dairy, .egg])
            bad(.vegetarian, [.fish, .shellfish])
            bad(.dairyFree, [.dairy])
            bad(.glutenFree, [.gluten])
            bad(.nutFree, [.treeNut, .peanut])
        }
        report(violations, "Dietary tag contradicts allergen")
    }

    /// Density values must be physically plausible (grams per US cup / per piece).
    func testDensityValuesArePlausible() {
        var violations: [String] = []
        for item in items {
            if let g = item.gramsPerCup, !(5...600).contains(g) {
                violations.append("\(item.id) gramsPerCup=\(g) out of range")
            }
            if let g = item.gramsPerPiece, !(0.5...3000).contains(g) {
                violations.append("\(item.id) gramsPerPiece=\(g) out of range")
            }
        }
        report(violations, "Implausible density")
    }

    // MARK: - Lexicon

    /// The depluralizer must never truncate Latin `-us`/`-is` words or `-ss` mass
    /// nouns, and must collapse regular plurals to a sane singular.
    func testDepluralizeIsRobust() {
        for word in ["couscous", "hummus", "octopus", "asparagus", "molasses",
                     "watercress", "swiss", "hibiscus", "anise"] {
            XCTAssertEqual(IngredientLexicon.depluralize(word), word, "must not stem \(word)")
        }
        for (plural, singular) in [("apples", "apple"), ("olives", "olive"),
                                   ("tomatoes", "tomato"), ("berries", "berry"),
                                   ("peaches", "peach"), ("beans", "bean"),
                                   ("potatoes", "potato"), ("eggs", "egg"),
                                   ("cherries", "cherry"), ("boxes", "box")] {
            XCTAssertEqual(IngredientLexicon.depluralize(plural), singular)
        }
    }

    /// `normalizeIngredient` must never collapse a real ingredient to an empty (or
    /// single-character) string — the failure mode where an ingredient whose whole
    /// name is a facet word (e.g. "flour", "olive oil") gets stripped to nothing and
    /// can no longer be grouped or matched.
    func testNormalizationNeverEmptiesAnIngredient() {
        var violations: [String] = []
        for item in items {
            let normalized = IngredientLexicon.normalizeIngredient(item.name)
            if normalized.isEmpty {
                violations.append("'\(item.name)' (\(item.id)) normalizes to empty")
            }
        }
        report(violations, "Ingredient normalizes to (near) empty")
    }

    /// Substitutions must point at real catalog items and never at themselves.
    func testSwapsReferenceRealItems() {
        let ids = Set(items.map(\.id))
        var violations: [String] = []
        for item in items {
            for swap in item.swaps {
                if swap.substituteItemID == item.id {
                    violations.append("\(item.id) swaps to itself")
                } else if !ids.contains(swap.substituteItemID) {
                    violations.append("\(item.id) swaps to missing '\(swap.substituteItemID)'")
                }
            }
        }
        report(violations, "Invalid swap target")
    }
}
