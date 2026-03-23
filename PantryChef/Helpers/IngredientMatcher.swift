import Foundation

/// High-performance, offline ingredient matching engine.
/// Replaces naive substring matching with normalized names, synonym dictionary,
/// category-aware fallback, quantity checking, and substitution integration.
enum IngredientMatcher {

    private struct PantryCandidate {
        let facets: Set<PantryFacetSelection>
        let quantityMode: PantryQuantityMode
        let quantity: Double?
        let unit: MeasurementUnit?
    }

    private struct PantryIndex {
        let resolvedItemsByCatalogID: [String: [PantryCandidate]]
        let unresolvedItemsByMatchKey: [String: [PantryCandidate]]
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

    static func resolvedCatalogItem(
        for name: String,
        catalogItemID: String? = nil
    ) -> PantryCatalogItemDefinition? {
        if let catalogItemID,
           let item = PantryCatalog.item(id: catalogItemID) {
            return item
        }

        return PantryCatalog.resolveExact(name: name)
    }

    static func resolvedCatalogItemID(for name: String, catalogItemID: String? = nil) -> String? {
        resolvedCatalogItem(for: name, catalogItemID: catalogItemID)?.id ?? catalogItemID
    }

    static func pantryItemMatchesIngredient(_ pantryItem: PantryItem, ingredient: Ingredient) -> Bool {
        if let ingredientCatalogItemID = ingredient.catalogItemID,
           let pantryCatalogItemID = resolvedCatalogItemID(for: pantryItem.name, catalogItemID: pantryItem.catalogItemID),
           ingredientCatalogItemID == pantryCatalogItemID {
            let requiredFacets = Set(ingredient.facets)
            return pantryFacetsSatisfy(requiredFacets, pantryFacets: Set(pantryItem.facets))
        }

        guard pantryItem.catalogItemID == nil, ingredient.catalogItemID == nil else {
            return false
        }

        return unresolvedNamesExactlyMatch(pantryItem.name, ingredient.name)
    }

    private static func pantryContains(ingredient: Ingredient, pantry: [PantryItem], index: PantryIndex) -> Bool {
        if let catalogItemID = ingredient.catalogItemID {
            guard let pantryCandidates = index.resolvedItemsByCatalogID[catalogItemID] else {
                return false
            }

            let requiredFacets = Set(ingredient.facets)
            return pantryCandidates.contains { pantryCandidate in
                pantryFacetsSatisfy(requiredFacets, pantryFacets: pantryCandidate.facets)
                    && hasEnoughQuantity(candidate: pantryCandidate, ingredient: ingredient)
            }
        }

        let unresolvedKey = unresolvedMatchKey(for: ingredient.rawName)
        guard let pantryCandidates = index.unresolvedItemsByMatchKey[unresolvedKey] else {
            return false
        }

        return pantryCandidates.contains { hasEnoughQuantity(candidate: $0, ingredient: ingredient) }
    }

    private static func buildPantryIndex(_ pantry: [PantryItem]) -> PantryIndex {
        let signature = pantryIndexSignature(for: pantry)

        pantryIndexCacheLock.lock()
        if cachedPantryIndexSignature == signature, let cachedPantryIndex {
            pantryIndexCacheLock.unlock()
            return cachedPantryIndex
        }
        pantryIndexCacheLock.unlock()

        var resolvedItemsByCatalogID: [String: [PantryCandidate]] = [:]
        resolvedItemsByCatalogID.reserveCapacity(pantry.count)
        var unresolvedItemsByMatchKey: [String: [PantryCandidate]] = [:]
        for pantryItem in pantry {
            let candidate = PantryCandidate(
                facets: Set(pantryItem.facets),
                quantityMode: pantryItem.quantityMode,
                quantity: pantryItem.quantity,
                unit: pantryItem.unit
            )

            if let catalogItemID = pantryItem.catalogItemID {
                resolvedItemsByCatalogID[catalogItemID, default: []].append(candidate)
            } else {
                unresolvedItemsByMatchKey[unresolvedMatchKey(for: pantryItem.name), default: []].append(candidate)
            }
        }

        let index = PantryIndex(
            resolvedItemsByCatalogID: resolvedItemsByCatalogID,
            unresolvedItemsByMatchKey: unresolvedItemsByMatchKey
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
            hasher.combine(pantryItem.quantityMode)
            hasher.combine(pantryItem.quantity)
            hasher.combine(pantryItem.unit)
        }

        return hasher.finalize()
    }

    private static func pantryFacetsSatisfy(
        _ requiredFacets: Set<PantryFacetSelection>,
        pantryFacets: Set<PantryFacetSelection>
    ) -> Bool {
        guard !requiredFacets.isEmpty else { return true }

        let pantryFacetValues = Dictionary(uniqueKeysWithValues: pantryFacets.map { ($0.key, $0.value) })
        for requiredFacet in requiredFacets {
            if requiredFacet.value == "generic" {
                continue
            }

            guard pantryFacetValues[requiredFacet.key] == requiredFacet.value else {
                return false
            }
        }

        return true
    }

    private static func unresolvedNamesExactlyMatch(_ a: String, _ b: String) -> Bool {
        unresolvedMatchKey(for: a) == unresolvedMatchKey(for: b)
    }

    private static func unresolvedMatchKey(for name: String) -> String {
        let lookupKey = IngredientLexicon.lookupKey(name)
        return lookupKey.isEmpty ? normalize(name) : lookupKey
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
        hasEnoughQuantity(
            candidate: PantryCandidate(
                facets: Set(pantryItem.facets),
                quantityMode: pantryItem.quantityMode,
                quantity: pantryItem.quantity,
                unit: pantryItem.unit
            ),
            ingredient: ingredient
        )
    }

    private static func hasEnoughQuantity(candidate: PantryCandidate, ingredient: Ingredient) -> Bool {
        guard candidate.quantityMode == .exact else {
            return true
        }

        guard let pantryQuantity = candidate.quantity else {
            return true
        }

        guard let ingredientUnit = ingredient.unit else {
            return pantryQuantity >= ingredient.quantity
        }

        guard let pantryUnit = candidate.unit else {
            return true
        }

        if pantryUnit == ingredientUnit {
            return pantryQuantity >= ingredient.quantity
        }

        if let converted = UnitConverter.convert(pantryQuantity, from: pantryUnit, to: ingredientUnit) {
            return converted >= ingredient.quantity
        }

        return true
    }

}
