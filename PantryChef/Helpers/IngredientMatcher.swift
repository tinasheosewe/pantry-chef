import Foundation

/// High-performance, offline ingredient matching engine.
/// Replaces naive substring matching with normalized names, synonym dictionary,
/// category-aware fallback, quantity checking, and substitution integration.
enum IngredientMatcher {

    private struct PantryIndex {
        let normalizedNames: [String]
        let normalizedSet: Set<String>
        let synonymUniverse: Set<String>
        let tokenizedNames: [(name: String, tokens: Set<String>)]
        let resolvedItemsByCatalogID: [String: [Set<PantryFacetSelection>]]
    }

    private static let pantryIndexCacheLock = NSLock()
    private static var cachedPantryIndexSignature: Int?
    private static var cachedPantryIndex: PantryIndex?

    // MARK: - Public API

    /// Full pantry match including substitution lookup.
    static func match(recipe: Recipe, pantry: [PantryItem]) -> PantryMatchResult {
        let required = recipe.ingredients.filter { !$0.isOptional }
        var matched: [Ingredient] = []
        var missing: [Ingredient] = []
        let pantryIndex = buildPantryIndex(pantry)

        for ingredient in required {
            if pantryContains(ingredient: ingredient, pantry: pantry, index: pantryIndex) {
                matched.append(ingredient)
            } else {
                missing.append(ingredient)
            }
        }

        let matchPct = required.isEmpty ? 0 : Double(matched.count) / Double(required.count) * 100

        // Look up substitutions for missing ingredients
        let subRepo = SubstitutionRepository.shared
        var substitutable: [(ingredient: Ingredient, substitutions: [SubstitutionEntry])] = []

        for ingredient in missing {
            let subs = subRepo.substitutions(for: ingredient, pantry: pantry)
            let availableSubs = subs.filter(\.inPantry)
            if !availableSubs.isEmpty {
                substitutable.append((ingredient: ingredient, substitutions: availableSubs))
            }
        }

        let subCount = substitutable.count
        let effectivePct = required.isEmpty ? 0 :
            Double(matched.count + subCount) / Double(required.count) * 100
        let canMakeWithSubs = missing.count == subCount && !missing.isEmpty

        return PantryMatchResult(
            recipe: recipe,
            matchedIngredients: matched,
            missingIngredients: missing,
            matchPercentage: matchPct,
            substitutableIngredients: substitutable,
            canMakeWithSubstitutions: canMakeWithSubs,
            effectiveMatchPercentage: effectivePct
        )
    }

    /// Quick check: does the pantry contain something matching this ingredient?
    static func pantryContains(ingredient: Ingredient, pantry: [PantryItem]) -> Bool {
        let index = buildPantryIndex(pantry)
        return pantryContains(ingredient: ingredient, pantry: pantry, index: index)
    }

    private static func pantryContains(ingredient: Ingredient, pantry: [PantryItem], index: PantryIndex) -> Bool {
        if let catalogItemID = ingredient.catalogItemID {
            guard let pantryFacetSets = index.resolvedItemsByCatalogID[catalogItemID] else {
                return false
            }

            let requiredFacets = Set(ingredient.facets)
            return pantryFacetSets.contains { pantryFacets in
                requiredFacets.isSubset(of: pantryFacets)
            }
        }

        return pantryContainsNormalized(normalize(ingredient.rawName), index: index)
    }

    private static func buildPantryIndex(_ pantry: [PantryItem]) -> PantryIndex {
        let signature = pantryIndexSignature(for: pantry)

        pantryIndexCacheLock.lock()
        if cachedPantryIndexSignature == signature, let cachedPantryIndex {
            pantryIndexCacheLock.unlock()
            return cachedPantryIndex
        }
        pantryIndexCacheLock.unlock()

        let normalizedNames = pantry.map { normalize($0.name) }
        let normalizedSet = Set(normalizedNames)

        var synonymUniverse: Set<String> = []
        synonymUniverse.reserveCapacity(normalizedNames.count * 2)
        for name in normalizedNames {
            synonymUniverse.insert(name)
            let group = synonymGroup(for: name)
            if !group.isEmpty {
                synonymUniverse.formUnion(group)
            }
        }

        let tokenizedNames = normalizedNames.map { name in
            (name: name, tokens: Set(IngredientLexicon.tokenize(name)))
        }

        var resolvedItemsByCatalogID: [String: [Set<PantryFacetSelection>]] = [:]
        resolvedItemsByCatalogID.reserveCapacity(pantry.count)
        for pantryItem in pantry {
            guard let catalogItemID = pantryItem.catalogItemID else { continue }
            resolvedItemsByCatalogID[catalogItemID, default: []].append(Set(pantryItem.facets))
        }

        let index = PantryIndex(
            normalizedNames: normalizedNames,
            normalizedSet: normalizedSet,
            synonymUniverse: synonymUniverse,
            tokenizedNames: tokenizedNames,
            resolvedItemsByCatalogID: resolvedItemsByCatalogID
        )

        pantryIndexCacheLock.lock()
        cachedPantryIndexSignature = signature
        cachedPantryIndex = index
        pantryIndexCacheLock.unlock()

        return index
    }

    private static func pantryIndexSignature(for pantry: [PantryItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(pantry.count)

        for pantryItem in pantry {
            hasher.combine(pantryItem.id)
            hasher.combine(pantryItem.name)
            hasher.combine(pantryItem.catalogItemID)
            hasher.combine(pantryItem.facets)
        }

        return hasher.finalize()
    }

    private static func pantryContainsNormalized(_ normalizedIngredient: String, index: PantryIndex) -> Bool {
        if index.normalizedSet.contains(normalizedIngredient) { return true }

        for pantryName in index.normalizedNames {
            if pantryName.contains(normalizedIngredient) || normalizedIngredient.contains(pantryName) {
                return true
            }
        }

        let group = synonymGroup(for: normalizedIngredient)
        if !group.isEmpty && !group.isDisjoint(with: index.synonymUniverse) {
            return true
        }

        let ingredientTokens = Set(normalizedIngredient.split(separator: " ").map(String.init))
        if !ingredientTokens.isEmpty {
            for (_, pantryTokens) in index.tokenizedNames {
                if IngredientLexicon.tokenSubsetMatch(ingredientTokens, pantryTokens) {
                    return true
                }
            }
        }

        return false
    }

    /// Normalized name comparison with synonym awareness.
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        let na = normalize(a)
        let nb = normalize(b)
        let lookupA = IngredientLexicon.lookupKey(a)
        let lookupB = IngredientLexicon.lookupKey(b)

        // Direct match
        if na == nb { return true }

        if lookupA == lookupB { return true }

        // Containment (handles "chicken breast" matching "chicken")
        if na.contains(nb) || nb.contains(na) { return true }

        // Synonym check
        let lookupSynsA = IngredientLexicon.synonymLookupGroup(for: a)
        let lookupSynsB = IngredientLexicon.synonymLookupGroup(for: b)
        if !lookupSynsA.isEmpty && lookupSynsA == lookupSynsB { return true }
        if lookupSynsA.contains(lookupB) || lookupSynsB.contains(lookupA) { return true }

        let synsA = synonymGroup(for: na)
        let synsB = synonymGroup(for: nb)
        if !synsA.isEmpty && synsA == synsB { return true }

        // Check if either normalized name matches any synonym of the other
        if synsA.contains(nb) || synsB.contains(na) { return true }

        // Token overlap for compound names: "bell pepper" vs "red bell pepper"
        let tokensA = Set(IngredientLexicon.tokenize(na))
        let tokensB = Set(IngredientLexicon.tokenize(nb))
        if IngredientLexicon.tokenSubsetMatch(tokensA, tokensB) { return true }

        return false
    }

    // MARK: - Normalization

    /// Strips adjectives, plurals, and normalizes whitespace.
    static func normalize(_ name: String) -> String {
        IngredientLexicon.normalizeIngredient(name)
    }

    // MARK: - Synonym Dictionary

    /// Returns the canonical synonym group for a normalized name, or empty set.
    static func synonymGroup(for normalizedName: String) -> Set<String> {
        IngredientLexicon.synonymGroup(forNormalizedIngredient: normalizedName)
    }

    // MARK: - Quantity Check

    /// Returns true if the pantry item has enough quantity for the ingredient.
    /// Returns true (optimistic) if quantities can't be compared.
    static func hasEnoughQuantity(pantryItem: PantryItem, ingredient: Ingredient) -> Bool {
        guard let pantryQty = pantryItem.quantity,
              let pantryUnit = pantryItem.unit,
              let ingredientUnit = ingredient.unit else {
            return true // Can't compare → assume yes
        }

        // Try to convert to common unit
        if let converted = UnitConverter.convert(pantryQty, from: pantryUnit, to: ingredientUnit) {
            return converted >= ingredient.quantity
        }

        // Same unit, direct compare
        if pantryUnit == ingredientUnit {
            return pantryQty >= ingredient.quantity
        }

        return true // Can't convert → assume yes
    }

}
