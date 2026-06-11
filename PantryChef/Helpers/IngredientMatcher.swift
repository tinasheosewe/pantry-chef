import Foundation

/// High-performance, offline ingredient matching engine.
/// Replaces naive substring matching with normalized names, synonym dictionary,
/// category-aware fallback, quantity checking, and substitution integration.
enum IngredientMatcher {

    static var substitutionRepository: any SubstitutionProviding = SubstitutionRepository.shared

    private struct PantryCandidate {
        let facets: Set<PantryFacetSelection>
        let quantityMode: PantryQuantityMode
        let quantity: Double?
        let unit: MeasurementUnit?
    }

    private struct PantryIndex {
        let resolvedItemsByRequirementCatalogID: [String: [PantryCandidate]]
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
        var substitutable: [(ingredient: Ingredient, substitutions: [SubstitutionEntry])] = []

        for ingredient in missing {
            let subs = substitutionRepository.substitutions(for: ingredient, pantry: pantry)
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
           let pantryCatalogItemID = pantryItem.catalogItemID {
            let requiredFacets = Set(ingredient.facets)
            let matchingCatalogIDs = PantryCatalog.matchingCatalogItemIDs(
                for: ingredientCatalogItemID,
                facets: ingredient.facets
            )

            if matchingCatalogIDs.contains(pantryCatalogItemID) {
                return pantryFacetsSatisfy(requiredFacets, pantryFacets: Set(pantryItem.facets))
            }
        }

        guard pantryItem.catalogItemID == nil, ingredient.catalogItemID == nil else {
            return false
        }

        return unresolvedNamesExactlyMatch(pantryItem.name, ingredient.name)
    }

    static func dependencyKeys(for ingredient: Ingredient) -> Set<String> {
        dependencyKeys(
            name: ingredient.rawName,
            catalogItemID: ingredient.catalogItemID,
            facets: ingredient.facets
        )
    }

    static func dependencyKeys(for pantryItem: PantryItem) -> Set<String> {
        dependencyKeys(
            name: pantryItem.name,
            catalogItemID: pantryItem.catalogItemID,
            facets: pantryItem.facets
        )
    }

    private static func pantryContains(ingredient: Ingredient, pantry: [PantryItem], index: PantryIndex) -> Bool {
        if let catalogItemID = ingredient.catalogItemID {
            let catalogIDs = PantryCatalog.matchingCatalogItemIDs(
                for: catalogItemID,
                facets: ingredient.facets
            )

            let requiredFacets = Set(ingredient.facets)
            for matchCatalogID in catalogIDs {
                guard let pantryCandidates = index.resolvedItemsByRequirementCatalogID[matchCatalogID] else {
                    continue
                }

                if pantryCandidates.contains(where: { pantryCandidate in
                    pantryFacetsSatisfy(requiredFacets, pantryFacets: pantryCandidate.facets)
                        && hasEnoughQuantity(candidate: pantryCandidate, ingredient: ingredient)
                }) {
                    return true
                }
            }
            return false
        }

        let unresolvedKey = unresolvedMatchKey(for: ingredient.rawName)
        if let pantryCandidates = index.unresolvedItemsByMatchKey[unresolvedKey],
           pantryCandidates.contains(where: { hasEnoughQuantity(candidate: $0, ingredient: ingredient) }) {
            return true
        }

        if let resolvedIngredientItem = resolvedCatalogItem(for: ingredient.rawName) {
            let requiredFacets = inferredFacets(for: ingredient.rawName, item: resolvedIngredientItem)
            let catalogIDs: Set<String> = PantryCatalog.matchingCatalogItemIDs(
                for: resolvedIngredientItem.id,
                facets: Array(requiredFacets)
            )

            for matchCatalogID in catalogIDs {
                if let pantryCandidates = index.resolvedItemsByRequirementCatalogID[matchCatalogID],
                   pantryCandidates.contains(where: {
                       pantryFacetsSatisfy(requiredFacets, pantryFacets: $0.facets)
                           && hasEnoughQuantity(candidate: $0, ingredient: ingredient)
                   }) {
                    return true
                }
            }

            return pantry.contains { pantryItem in
                if let pantryResolvedItem = resolvedCatalogItem(for: pantryItem.name, catalogItemID: pantryItem.catalogItemID),
                   pantryResolvedItem.id == resolvedIngredientItem.id {
                    let pantryFacets = pantryItem.catalogItemID == nil
                        ? inferredFacets(for: pantryItem.name, item: pantryResolvedItem)
                        : Set(pantryItem.facets)

                    return pantryFacetsSatisfy(requiredFacets, pantryFacets: pantryFacets)
                        && hasEnoughQuantity(pantryItem: pantryItem, ingredient: ingredient)
                }

                guard pantryItem.catalogItemID == nil else {
                    return false
                }

                return namesMatch(pantryItem.name, ingredient.rawName)
                    && hasEnoughQuantity(pantryItem: pantryItem, ingredient: ingredient)
            }
        }

        return pantry.contains { pantryItem in
            namesMatch(pantryItem.name, ingredient.rawName)
                && hasEnoughQuantity(pantryItem: pantryItem, ingredient: ingredient)
        }
    }

    private static func buildPantryIndex(_ pantry: [PantryItem]) -> PantryIndex {
        let signature = pantryIndexSignature(for: pantry)

        pantryIndexCacheLock.lock()
        if cachedPantryIndexSignature == signature, let cachedPantryIndex {
            pantryIndexCacheLock.unlock()
            return cachedPantryIndex
        }
        pantryIndexCacheLock.unlock()

        var resolvedItemsByRequirementCatalogID: [String: [PantryCandidate]] = [:]
        resolvedItemsByRequirementCatalogID.reserveCapacity(pantry.count)
        var unresolvedItemsByMatchKey: [String: [PantryCandidate]] = [:]
        for pantryItem in pantry {
            let candidate = PantryCandidate(
                facets: Set(pantryItem.facets),
                quantityMode: pantryItem.quantityMode,
                quantity: pantryItem.quantity,
                unit: pantryItem.unit
            )

            if let catalogItemID = resolvedCatalogItemID(for: pantryItem.name, catalogItemID: pantryItem.catalogItemID) {
                for ancestorID in PantryCatalog.ancestors(of: catalogItemID) {
                    resolvedItemsByRequirementCatalogID[ancestorID, default: []].append(candidate)
                }
            } else {
                unresolvedItemsByMatchKey[unresolvedMatchKey(for: pantryItem.name), default: []].append(candidate)
            }
        }

        let index = PantryIndex(
            resolvedItemsByRequirementCatalogID: resolvedItemsByRequirementCatalogID,
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
        guard !pantryFacets.isEmpty else {
            return requiredFacets.allSatisfy { $0.value == "none" }
        }

        let pantryFacetValues = Dictionary(uniqueKeysWithValues: pantryFacets.map { ($0.key, $0.value) })
        for requiredFacet in requiredFacets {
            if requiredFacet.value == "none" {
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

    private static func dependencyKeys(
        name: String,
        catalogItemID: String?,
        facets: [PantryFacetSelection]
    ) -> Set<String> {
        if let resolvedCatalogItemID = resolvedCatalogItemID(for: name, catalogItemID: catalogItemID) {
            var keys: Set<String> = ["catalog:\(resolvedCatalogItemID)"]
            for facet in facets where facet.value != "none" {
                keys.insert("catalog:\(resolvedCatalogItemID)|\(facet.key.rawValue)=\(facet.value)")
            }
            return keys
        }

        let unresolvedKey = unresolvedMatchKey(for: name)
        guard !unresolvedKey.isEmpty else { return [] }
        return ["raw:\(unresolvedKey)"]
    }

    private static func inferredFacets(
        for name: String,
        item: PantryCatalogItemDefinition
    ) -> Set<PantryFacetSelection> {
        let lookup = PantryCatalog.normalizeLookupKey(name)
        guard !lookup.isEmpty else { return [] }

        var inferred: [PantryFacetSelection] = []
        for definition in item.facets {
            let matches = definition.options.filter { option in
                let normalizedOption = PantryCatalog.normalizeLookupKey(option)
                guard !normalizedOption.isEmpty, normalizedOption != "none" else {
                    return false
                }

                return lookup.contains(normalizedOption)
            }

            if matches.count == 1 {
                inferred.append(PantryFacetSelection(key: definition.key, value: matches[0]))
            }
        }

        return Set(item.normalizedSelections(from: inferred))
    }

    /// Normalized name comparison with synonym awareness.
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        let na = normalize(a)
        let nb = normalize(b)
        let lookupA = IngredientLexicon.lookupKey(a)
        let lookupB = IngredientLexicon.lookupKey(b)

        if lookupA == lookupB { return true }

        // Containment (handles "chicken breast" matching "chicken")
        if !lookupA.isEmpty && !lookupB.isEmpty && (lookupA.contains(lookupB) || lookupB.contains(lookupA)) {
            return true
        }

        // Synonym check
        let lookupSynsA = IngredientLexicon.synonymLookupGroup(for: a)
        let lookupSynsB = IngredientLexicon.synonymLookupGroup(for: b)
        if !lookupSynsA.isEmpty && lookupSynsA == lookupSynsB { return true }
        if lookupSynsA.contains(lookupB) || lookupSynsB.contains(lookupA) { return true }

        let synsA = na.isEmpty ? Set<String>() : synonymGroup(for: na)
        let synsB = nb.isEmpty ? Set<String>() : synonymGroup(for: nb)
        if !synsA.isEmpty && synsA == synsB { return true }

        // Check if either normalized name matches any synonym of the other
        if (!nb.isEmpty && synsA.contains(nb)) || (!na.isEmpty && synsB.contains(na)) { return true }

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
