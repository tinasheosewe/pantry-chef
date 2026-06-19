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
        /// On-hand id → its FoodCategory, so lineage matches can be gated to the same
        /// kind of thing (a tomato is not ketchup, even though ketchup descends from it).
        private let onHandCategories: [String: FoodCategory]

        init(names: [String], catalogIDs: [String] = []) {
            normalizedKeys = Set(names.map { IngredientLexicon.normalizeIngredient($0) })
            lookupKeys = Set(names.map { IngredientLexicon.lookupKey($0) })
            let ids = Set(catalogIDs)
            self.catalogIDs = ids
            onHandCategories = Dictionary(uniqueKeysWithValues: ids.compactMap { id -> (String, FoodCategory)? in
                guard let cat = PantryCatalog.itemsByID[id]?.category else { return nil }
                return (id, cat)
            })
        }

        /// True if some on-hand item *is* this catalog item, or sits on the same parent
        /// lineage **within the same category**. The category gate is the honesty guard:
        /// the catalog tree mixes "variant-of" (cherry tomato → tomato) with "derived-
        /// from" (ketchup → tomato, apple → applesauce), and only the former is an
        /// interchangeable substitute. Without it, having a plain tomato would read as
        /// "make now" for a recipe that needs ketchup. Siblings still don't match — that's
        /// a swap, not the same ingredient. (Same-category base↔specific within a family,
        /// e.g. generic oil ↔ sesame oil, is a known remaining over-claim — see the typed-
        /// lineage-edge follow-up.)
        func contains(catalogItemID id: String) -> Bool {
            if catalogIDs.contains(id) { return true }          // exact item on hand
            let reqCategory = PantryCatalog.itemsByID[id]?.category
            let reqAncestors = PantryCatalog.ancestors(of: id)  // includes id itself
            for onHand in catalogIDs where onHandCategories[onHand] == reqCategory {
                // on-hand is a base (ancestor) of the requirement, OR a variant (descendant) of it
                if reqAncestors.contains(onHand) || PantryCatalog.ancestors(of: onHand).contains(id) {
                    return true
                }
            }
            return false
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
