import Foundation

final class SubstitutionRepository: SubstitutionProviding, @unchecked Sendable {

    static let shared = SubstitutionRepository()

    private init() {}

    func substitutions(for ingredientName: String) -> [SubstitutionEntry] {
        substitutions(for: Ingredient(name: ingredientName))
    }

    func substitutions(for ingredient: Ingredient) -> [SubstitutionEntry] {
        if containsGenericFacet(ingredient.facets) {
            return []
        }

        if let catalogItemID = ingredient.catalogItemID,
           let item = PantryCatalog.item(id: catalogItemID) {
            let substitutions = substitutions(forItem: item)
            return substitutions.isEmpty ? builtinSubstitutions(for: ingredient, resolvedItem: item) : substitutions
        }

        if let item = IngredientMatcher.resolvedCatalogItem(for: ingredient.rawName) {
            let substitutions = substitutions(forItem: item)
            return substitutions.isEmpty ? builtinSubstitutions(for: ingredient, resolvedItem: item) : substitutions
        }

        return builtinSubstitutions(for: ingredient, resolvedItem: nil)
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
        guard let pantryCatalogItemID = pantryItem.catalogItemID else {
            return false
        }
        let acceptableIDs = PantryCatalog.descendants(of: substituteItemID)
        guard acceptableIDs.contains(pantryCatalogItemID) else { return false }

        let pantryFacets = Set(pantryItem.facets)
        return requiredFacets.allSatisfy { pantryFacets.contains($0) }
    }

    private func containsGenericFacet(_ facets: [PantryFacetSelection]) -> Bool {
        facets.contains { $0.value == "none" }
    }

    private func builtinSubstitutions(
        for ingredient: Ingredient,
        resolvedItem: PantryCatalogItemDefinition?
    ) -> [SubstitutionEntry] {
        let lookup = IngredientLexicon.lookupKey(ingredient.rawName)
        let itemID = resolvedItem?.id ?? ingredient.catalogItemID
        let facets = ingredient.facets

        if matches(
            ingredientLookup: lookup,
            itemID: itemID,
            facets: facets,
            expectedItemID: "chicken",
            expectedFacet: PantryFacetSelection(key: .variant, value: "breast")
        ) || lookup == "chicken breast" {
            return [
                builtInSubstitution(
                    originalItemID: "chicken",
                    substituteItemID: "tofu",
                    substituteFacets: [.init(key: .variant, value: "extra firm")],
                    ratio: "1:1 by weight",
                    tasteImpact: .moderate,
                    textureImpact: .moderate,
                    cookingImpact: .moderateAdjustment,
                    nutritionImpact: "Lower saturated fat, slightly lower protein",
                    notes: "Best in stir-fries, curries, and saucy dishes."
                ),
                builtInSubstitution(
                    originalItemID: "chicken",
                    substituteItemID: "tempeh",
                    substituteFacets: [],
                    ratio: "1:1 by weight",
                    tasteImpact: .slight,
                    textureImpact: .slight,
                    cookingImpact: .slightAdjustment,
                    nutritionImpact: "Higher fiber, similar protein",
                    notes: "Works best when sliced thin and browned before saucing."
                )
            ]
        }

        if matches(
            ingredientLookup: lookup,
            itemID: itemID,
            facets: facets,
            expectedItemID: "chicken",
            expectedFacet: PantryFacetSelection(key: .variant, value: "thigh")
        ) || lookup == "chicken thigh" {
            return [
                builtInSubstitution(
                    originalItemID: "chicken",
                    substituteItemID: "tofu",
                    substituteFacets: [.init(key: .variant, value: "extra firm")],
                    ratio: "1:1 by weight",
                    tasteImpact: .moderate,
                    textureImpact: .moderate,
                    cookingImpact: .moderateAdjustment,
                    nutritionImpact: "Lower saturated fat, slightly lower protein",
                    notes: "Best in braises, curries, and other saucy dishes."
                )
            ]
        }

        if matches(
            ingredientLookup: lookup,
            itemID: itemID,
            facets: facets,
            expectedItemID: "broth",
            expectedFacet: PantryFacetSelection(key: .variant, value: "beef")
        ) || lookup == "beef broth" {
            return [
                builtInSubstitution(
                    originalItemID: "broth",
                    substituteItemID: "broth",
                    substituteFacets: [],
                    ratio: "1:1 by volume",
                    tasteImpact: .slight,
                    textureImpact: .none,
                    cookingImpact: .none,
                    nutritionImpact: "Slightly lighter savory flavor",
                    notes: "Add a splash of soy sauce or mushrooms to deepen the flavor if needed."
                )
            ]
        }

        if itemID == "soy-sauce" || lookup == "soy sauce" {
            return [
                builtInSubstitution(
                    originalItemID: "soy-sauce",
                    substituteItemID: "coconut-aminos",
                    substituteFacets: [],
                    ratio: "1:1 by volume",
                    tasteImpact: .slight,
                    textureImpact: .none,
                    cookingImpact: .none,
                    nutritionImpact: "Typically lower sodium and a touch sweeter",
                    notes: "Reduce added sweeteners slightly if the dish already leans sweet."
                )
            ]
        }

        return []
    }

    private func builtInSubstitution(
        originalItemID: String,
        substituteItemID: String,
        substituteFacets: [PantryFacetSelection],
        ratio: String,
        tasteImpact: SubstitutionImpact,
        textureImpact: SubstitutionImpact,
        cookingImpact: CookingImpact,
        nutritionImpact: String,
        notes: String
    ) -> SubstitutionEntry {
        let substituteItem = PantryCatalog.item(id: substituteItemID)
        let displayFacets = substituteFacets.isEmpty ? (substituteItem?.defaultSelections ?? []) : substituteFacets
        return SubstitutionEntry(
            originalItemID: originalItemID,
            substituteItemID: substituteItemID,
            substituteName: substituteItem?.displayName(for: displayFacets) ?? substituteItemID,
            substituteFacets: substituteFacets,
            ratio: ratio,
            tasteImpact: tasteImpact,
            textureImpact: textureImpact,
            cookingImpact: cookingImpact,
            nutritionImpact: nutritionImpact,
            notes: notes,
            dietary: nil
        )
    }

    private func matches(
        ingredientLookup: String,
        itemID: String?,
        facets: [PantryFacetSelection],
        expectedItemID: String,
        expectedFacet: PantryFacetSelection
    ) -> Bool {
        guard itemID == expectedItemID else { return false }
        return facets.contains(expectedFacet)
    }
}
