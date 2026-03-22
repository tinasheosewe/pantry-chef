import Foundation

final class SubstitutionRepository: @unchecked Sendable {

    static let shared = SubstitutionRepository()

    private init() {}

    func substitutions(for ingredientName: String) -> [SubstitutionEntry] {
        guard let item = IngredientMatcher.resolvedCatalogItem(for: ingredientName) else {
            return []
        }

        return substitutions(forItem: item)
    }

    func substitutions(for ingredient: Ingredient) -> [SubstitutionEntry] {
        if containsGenericFacet(ingredient.facets) {
            return []
        }

        if let catalogItemID = ingredient.catalogItemID,
           let item = PantryCatalog.item(id: catalogItemID) {
            return substitutions(forItem: item)
        }

        guard let item = IngredientMatcher.resolvedCatalogItem(for: ingredient.rawName) else {
            return []
        }

        return substitutions(forItem: item)
    }

    func substitutions(for ingredient: Ingredient, pantry: [PantryItem]) -> [SubstitutionEntry] {
        var results = substitutions(for: ingredient)

        for index in results.indices {
            results[index].inPantry = pantry.contains {
                pantryItemMatches($0, substituteItemID: results[index].substituteItemID, requiredFacets: results[index].substituteFacets)
            }
        }

        results.sort { lhs, rhs in
            if lhs.inPantry != rhs.inPantry {
                return lhs.inPantry && !rhs.inPantry
            }
            return lhs.substituteName < rhs.substituteName
        }
        return results
    }

    private func substitutions(forItem item: PantryCatalogItemDefinition) -> [SubstitutionEntry] {
        item.substitutions.compactMap { definition in
            guard let substituteItem = PantryCatalog.item(id: definition.substituteItemID) else {
                return nil
            }

            if containsGenericFacet(definition.substituteFacets) {
                return nil
            }

            if definition.substituteFacets.isEmpty && containsGenericFacet(substituteItem.defaultSelections) {
                return nil
            }

            let displayFacets = definition.substituteFacets.isEmpty ? substituteItem.defaultSelections : definition.substituteFacets

            return SubstitutionEntry(
                originalItemID: item.id,
                substituteItemID: substituteItem.id,
                substituteName: substituteItem.displayName(for: displayFacets),
                substituteFacets: definition.substituteFacets,
                ratio: definition.ratio,
                tasteImpact: definition.tasteImpact,
                textureImpact: definition.textureImpact,
                cookingImpact: definition.cookingImpact,
                nutritionImpact: definition.nutritionImpact,
                notes: definition.notes,
                dietary: definition.dietary
            )
        }
    }

    func substitutions(for ingredientName: String, pantry: [PantryItem]) -> [SubstitutionEntry] {
        substitutions(for: Ingredient(name: ingredientName), pantry: pantry)
    }

    func hasSubstitutions(for ingredientName: String) -> Bool {
        !substitutions(for: ingredientName).isEmpty
    }

    var allIngredients: [String] {
        PantryCatalog.allItems
            .filter { !$0.substitutions.isEmpty }
            .map(\.name)
            .sorted()
    }

    private func pantryItemMatches(
        _ pantryItem: PantryItem,
        substituteItemID: String,
        requiredFacets: [PantryFacetSelection]
    ) -> Bool {
        guard pantryItem.catalogItemID == substituteItemID else {
            return false
        }

        let pantryFacets = Set(pantryItem.facets)
        return requiredFacets.allSatisfy { pantryFacets.contains($0) }
    }

    private func containsGenericFacet(_ facets: [PantryFacetSelection]) -> Bool {
        facets.contains { $0.value == "generic" }
    }
}
