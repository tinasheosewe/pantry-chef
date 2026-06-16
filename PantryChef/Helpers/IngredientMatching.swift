import Foundation

/// The single place the app decides whether the pantry satisfies an ingredient
/// requirement. An ingredient that carries a catalog id matches by *identity*, not
/// fuzzy strings: the same id, or one item being a variant of the other along the
/// catalog's parent lineage — so "spinach" is satisfied by "flat leaf spinach" (a
/// descendant) and vice-versa, while siblings ("flat leaf" vs "semi savoy") are not.
/// Synonyms (scallion/green onion) already collapse to one id via catalog aliases,
/// so identity covers them too. Name matching survives only as a degenerate path for
/// the rare line that has no catalog id at all. Readiness and the gathering checklist
/// both ask here, so they can never disagree (consolidation audit §2).
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
        /// Every on-hand catalog id plus all of its ancestors (each set includes the
        /// id itself), so "is this requirement a base of something I have?" is a
        /// single membership test.
        private let onHandLineage: Set<String>

        init(names: [String], catalogIDs: [String] = []) {
            normalizedKeys = Set(names.map { IngredientLexicon.normalizeIngredient($0) })
            lookupKeys = Set(names.map { IngredientLexicon.lookupKey($0) })
            let ids = Set(catalogIDs)
            self.catalogIDs = ids
            onHandLineage = ids.reduce(into: Set<String>()) { $0.formUnion(PantryCatalog.ancestors(of: $1)) }
        }

        /// True if some on-hand item *is* this catalog item, or sits on the same
        /// parent lineage (the requirement is a base of something on hand, or a
        /// variant of a base on hand). Siblings don't match — that's a swap, not
        /// the same ingredient.
        func contains(catalogItemID id: String) -> Bool {
            // The requirement is an on-hand item, or an ancestor (base) of one.
            if onHandLineage.contains(id) { return true }
            // Or an on-hand item is an ancestor (base) of the requirement variant.
            return !PantryCatalog.ancestors(of: id).isDisjoint(with: catalogIDs)
        }

        /// Name match — the degenerate path for a line with no catalog id.
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
