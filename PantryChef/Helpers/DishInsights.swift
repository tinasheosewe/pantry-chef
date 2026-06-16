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

    /// One catalog-recorded substitute for an ingredient — its catalog identity (so
    /// presence is checked by id), a readable name, and the cook's note.
    struct SwapSuggestion: Identifiable, Equatable {
        let key: String
        let name: String
        let catalogItemID: String?
        let notes: String?
        var id: String { catalogItemID ?? key }
    }

    /// Substitutions for a recipe line, resolved through its catalog identity — all
    /// three tiers (curated, sibling varieties, and the broad same-base family), in
    /// confidence order, so the cook can choose rather than take the first.
    static func swaps(for line: RecipeLine) -> [SwapSuggestion] {
        let item = line.catalogItemID.flatMap { PantryCatalog.itemsByID[$0] }
            ?? PantryCatalog.resolveExact(name: line.key)
        guard let item else { return [] }
        return CatalogSwaps.candidates(forItemID: item.id, includeFamily: true)
            .map { SwapSuggestion(key: $0.key, name: $0.name, catalogItemID: $0.id, notes: $0.notes) }
    }
}
