import Foundation

final class SubstitutionRepository: @unchecked Sendable {

    static let shared = SubstitutionRepository()

    private init() {}

    func substitutions(for ingredientName: String) -> [SubstitutionEntry] {
        guard let item = PantryCatalog.resolveExact(name: ingredientName) else {
            return []
        }

        return item.substitutions.compactMap { definition in
            guard let substituteItem = PantryCatalog.item(id: definition.substituteItemID) else {
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
        var results = substitutions(for: ingredientName)

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
}
