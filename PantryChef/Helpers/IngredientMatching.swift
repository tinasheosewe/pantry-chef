import Foundation

/// The single place the app decides whether the pantry satisfies an ingredient
/// requirement. Catalog/lexicon-aware: it normalizes both sides through
/// `IngredientLexicon` (modifiers stripped, plurals folded) and honors synonym
/// groups, so "Baby spinach" or "tomatoes" on hand satisfy a recipe that asks for
/// "spinach" / "tomato". Readiness *and* the gathering checklist both ask here,
/// superseding the old raw lowercased-string equality that made creation and
/// readiness disagree (consolidation audit §2 — the #1 divergence).
enum IngredientMatching {

    /// The canonical match key for an ingredient name/phrase.
    static func key(_ value: String) -> String {
        IngredientLexicon.normalizeIngredient(value)
    }

    /// A precomputed view of what's on hand, for repeated requirement checks.
    struct Index {
        private let normalizedKeys: Set<String>
        private let lookupKeys: Set<String>
        private let catalogIDs: Set<String>

        init(names: [String], catalogIDs: [String] = []) {
            normalizedKeys = Set(names.map { IngredientLexicon.normalizeIngredient($0) })
            lookupKeys = Set(names.map { IngredientLexicon.lookupKey($0) })
            self.catalogIDs = Set(catalogIDs)
        }

        /// True if some on-hand item is exactly this catalog item.
        func contains(catalogItemID: String) -> Bool { catalogIDs.contains(catalogItemID) }

        /// True if some on-hand item satisfies `requirement` (by name).
        func contains(requirement: String) -> Bool {
            if normalizedKeys.contains(IngredientLexicon.normalizeIngredient(requirement)) { return true }
            if lookupKeys.contains(IngredientLexicon.lookupKey(requirement)) { return true }
            let synonyms = IngredientLexicon.synonymLookupGroup(for: requirement)
            return !synonyms.isEmpty && !synonyms.isDisjoint(with: lookupKeys)
        }
    }

    /// One-off check (small callers); for repeated checks build an `Index` once.
    static func isOnHand(requirement: String, inNames names: [String]) -> Bool {
        Index(names: names).contains(requirement: requirement)
    }
}
