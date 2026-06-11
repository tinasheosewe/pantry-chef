import Foundation

/// Resolves a dish's ingredients against the catalog to surface its enrichment —
/// allergens and substitutions (spec §4/§"what to add"). Pure lookups over the
/// catalog; the first real consumer of the `allergens`/`swaps` enrichment.
enum DishInsights {

    /// Allergens the dish carries, aggregated from its ingredients' catalog entries.
    static func allergens(for dish: Dish) -> [Allergen] {
        var found = Set<Allergen>()
        for line in dish.ingredients {
            if let item = PantryCatalog.resolveExact(name: line.key) {
                found.formUnion(item.allergens)
            }
        }
        return found.sorted { $0.title < $1.title }
    }

    /// The avoided allergens this dish would expose the household to.
    static func conflicts(_ dish: Dish, with profile: DietaryProfile) -> [Allergen] {
        allergens(for: dish).filter { profile.avoided.contains($0) }
    }

    /// Substitutions for an ingredient, resolved to a pantry key + readable name +
    /// notes — the key is what readiness/gathering match against.
    static func swaps(forKey key: String) -> [(key: String, name: String, notes: String?)] {
        guard let item = PantryCatalog.resolveExact(name: key) else { return [] }
        return item.swaps.compactMap { swap in
            guard let target = PantryCatalog.itemsByID[swap.substituteItemID] else { return nil }
            return (IngredientLexicon.lookupKey(target.name), target.name, swap.notes)
        }
    }
}
