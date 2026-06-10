import Foundation

// MARK: - Resolution Scoring Thresholds

private enum ResolutionThresholds {
    /// Min score for exact facet template token matches.
    static let exactTemplateToken = 0.985
    /// Min containment score for lexical substring overlap.
    static let containment = 0.9
    /// Min combined (token + containment) score for lexical candidates.
    static let combinedLexical = 0.48
    /// Min fuzzy similarity score for fuzzy candidates.
    static let fuzzy = 0.78
    /// Min score for a facet-specific candidate to be considered strong.
    static let facetCandidate = 0.9
}

final class IngredientCandidateParser: IngredientCandidateParserProtocol {

    private struct CacheKey: Hashable {
        let rawName: String
        let catalogItemID: String?
        let linkedItemID: String?
        let facets: [PantryFacetSelection]
    }

    private enum RetrievalStage: Int {
        case exactName = 0
        case exactAlias = 1
        case exactTemplate = 2
        case exactSynonym = 3
        case lexical = 4
        case fuzzy = 5
    }

    private struct ScoredCandidate {
        let candidate: IngredientResolutionCandidate
        let stage: RetrievalStage
    }

    private let maxCandidates: Int
    private let cacheLock = NSLock()
    private var cachedCandidatesByKey: [CacheKey: [IngredientResolutionCandidate]] = [:]

    init(maxCandidates: Int = 4) {
        self.maxCandidates = maxCandidates
    }

    func candidates(for ingredient: Ingredient) -> [IngredientResolutionCandidate] {
        let cacheKey = CacheKey(
            rawName: ingredient.rawName,
            catalogItemID: ingredient.catalogItemID,
            linkedItemID: ingredient.linkedItem?.id,
            facets: ingredient.facets
        )

        cacheLock.lock()
        if let cachedCandidates = cachedCandidatesByKey[cacheKey] {
            cacheLock.unlock()
            return cachedCandidates
        }
        cacheLock.unlock()

        if let item = ingredient.linkedItem {
            let linkedCandidates = [
                IngredientResolutionCandidate(
                    id: candidateID(for: item.id, facets: ingredient.facets),
                    catalogItemID: item.id,
                    facets: ingredient.facets,
                    displayName: item.displayName(for: ingredient.facets),
                    score: 1,
                    rationale: "Already linked to this catalog item.",
                    supportedFacets: item.facets
                )
            ]
            cacheCandidates(linkedCandidates, for: cacheKey)
            return linkedCandidates
        }

        let query = IngredientLexicon.parse(ingredient.rawName)
        guard !query.lookupKey.isEmpty else {
            cacheCandidates([], for: cacheKey)
            return []
        }
        let queryLookupTokenSet = Set(IngredientLexicon.tokenize(query.lookupKey))
        let lookupTokens = IngredientLexicon.tokenize(query.lookupKey)

        var candidatesByID: [String: ScoredCandidate] = [:]

        // Stage 1 & 2: Exact name/alias via aliasIndex
        if let itemID = PantryCatalog.resolveAlias(query.lookupKey),
           let item = PantryCatalog.item(id: itemID) {
            let isName = PantryCatalog.nameKeySet.contains(query.lookupKey)
            let facets = IngredientLexicon.inferredFacets(forLookupKey: query.lookupKey, item: item)
            register(
                item: item, facets: facets,
                stage: isName ? .exactName : .exactAlias,
                score: isName ? 1.0 : 0.995,
                rationale: isName
                    ? "Exact catalog name match for \(item.name)."
                    : "Exact alias match for \(item.name).",
                into: &candidatesByID
            )
        }

        // Stage 3: Template matching — decompose query into item + facet options
        let tokenCandidateIDs = PantryCatalog.itemIDs(matchingAnyToken: queryLookupTokenSet)
        let facetCandidateIDs = PantryCatalog.itemIDs(matchingFacetTokens: queryLookupTokenSet)
        let templateCandidateIDs = tokenCandidateIDs.union(facetCandidateIDs)

        for itemID in templateCandidateIDs {
            guard let item = PantryCatalog.item(id: itemID) else { continue }

            // Check each single-facet template against query lookupKey
            for definition in item.facets {
                for option in definition.options {
                    let selection = PantryFacetSelection(key: definition.key, value: option)
                    let optionKey = IngredientLexicon.lookupKey(option)
                    let templateName = item.displayName(for: [selection])
                    let templateKey = IngredientLexicon.lookupKey(templateName)

                    if optionKey == query.lookupKey {
                        register(
                            item: item, facets: [selection],
                            stage: .exactTemplate, score: 0.99,
                            rationale: "Exact facet option match for \(option).",
                            into: &candidatesByID
                        )
                    }

                    if templateKey == query.lookupKey {
                        register(
                            item: item, facets: [selection],
                            stage: .exactTemplate, score: 0.99,
                            rationale: "Exact facet template match for \(templateName).",
                            into: &candidatesByID
                        )
                    }
                }
            }

            // Also check token-set matching for reordered tokens
            if queryLookupTokenSet.count > 1 {
                let nameTokens = Set(IngredientLexicon.tokenize(IngredientLexicon.lookupKey(item.name)))
                for definition in item.facets {
                    for option in definition.options {
                        let optionTokens = Set(IngredientLexicon.tokenize(IngredientLexicon.lookupKey(option)))
                        let templateTokenSet = nameTokens.union(optionTokens)
                        if templateTokenSet == queryLookupTokenSet && templateTokenSet != nameTokens {
                            let selection = PantryFacetSelection(key: definition.key, value: option)
                            let candidateKey = candidateID(for: item.id, facets: [selection])
                            if candidatesByID[candidateKey] == nil {
                                register(
                                    item: item, facets: [selection],
                                    stage: .exactTemplate,
                                    score: ResolutionThresholds.exactTemplateToken,
                                    rationale: "Exact facet template token match for \(option) \(item.name).",
                                    into: &candidatesByID
                                )
                            }
                        }
                    }
                }

                let inferredSelections = IngredientLexicon.inferredFacets(forLookupKey: query.lookupKey, item: item)
                if inferredSelections.count > 1 {
                    let matchesDefaultIdentity = Set(inferredSelections) == Set(item.defaultSelections)
                    let inferredTokenSet = Set(
                        inferredSelections.flatMap { selection in
                            IngredientLexicon.tokenize(IngredientLexicon.lookupKey(selection.value))
                        }
                    )
                    if matchesDefaultIdentity && (inferredTokenSet == queryLookupTokenSet || nameTokens.union(inferredTokenSet) == queryLookupTokenSet) {
                        let candidateKey = candidateID(for: item.id, facets: inferredSelections)
                        if candidatesByID[candidateKey] == nil {
                            register(
                                item: item,
                                facets: inferredSelections,
                                stage: .exactTemplate,
                                score: ResolutionThresholds.exactTemplateToken,
                                rationale: "Exact multi-facet template match for \(item.displayName(for: inferredSelections)).",
                                into: &candidatesByID
                            )
                        }
                    }
                }
            }
        }

        // Stage 4: Synonym expansion
        let synonymLookups = IngredientLexicon.synonymLookupGroup(for: ingredient.rawName)
            .subtracting([query.lookupKey])
        if !synonymLookups.isEmpty {
            for synonymKey in synonymLookups {
                if let itemID = PantryCatalog.resolveAlias(synonymKey),
                   let item = PantryCatalog.item(id: itemID) {
                    let facets = IngredientLexicon.inferredFacets(forLookupKey: synonymKey, item: item)
                    register(
                        item: item, facets: facets,
                        stage: .exactSynonym, score: 0.96,
                        rationale: "Synonym expansion linked \(ingredient.rawName) to \(item.name).",
                        into: &candidatesByID
                    )
                }
            }
        }

        // Stage 5: Lexical (token overlap scoring)
        if !query.tokens.isEmpty || !lookupTokens.isEmpty {
            let synonymTokens = synonymLookups.flatMap(IngredientLexicon.tokenize)
            let expandedQueryTokens = Array(Set(query.tokens + lookupTokens + synonymTokens))
            let lexicalCandidateIDs = PantryCatalog
                .itemIDs(matchingAnyToken: Set(expandedQueryTokens))
                .union(PantryCatalog.itemIDs(matchingFacetTokens: Set(expandedQueryTokens)))

            for itemID in lexicalCandidateIDs {
                guard let item = PantryCatalog.item(id: itemID) else { continue }
                scoreLexicalItem(item, query: query, expandedQueryTokens: expandedQueryTokens, into: &candidatesByID)

                // Also score aliases
                for alias in item.aliases {
                    let aliasNormalized = IngredientLexicon.normalizeIngredient(alias)
                    let aliasTokens = IngredientLexicon.tokenize(aliasNormalized)
                    let aliasLookup = IngredientLexicon.lookupKey(alias)
                    let tokenScore = IngredientLexicon.weightedTokenScore(queryTokens: expandedQueryTokens, candidateTokens: aliasTokens)
                    let containmentScore: Double = (aliasLookup.contains(query.lookupKey) || query.lookupKey.contains(aliasLookup))
                        ? ResolutionThresholds.containment : 0
                    let combinedScore = max(tokenScore, containmentScore)
                    guard combinedScore >= ResolutionThresholds.combinedLexical else { continue }

                    let facets = IngredientLexicon.inferredFacets(forLookupKey: query.lookupKey, item: item)
                    register(
                        item: item, facets: facets,
                        stage: .lexical, score: min(0.94, combinedScore),
                        rationale: containmentScore > 0
                            ? "Strong lexical phrase overlap with \(alias)."
                            : "Weighted token retrieval suggests \(alias).",
                        into: &candidatesByID
                    )
                }
            }

            // Generic fallbacks
            registerGenericFallbacks(
                query: query,
                lookupTokens: lookupTokens,
                candidateItemIDs: lexicalCandidateIDs,
                into: &candidatesByID
            )
        }

        // Stage 6: Fuzzy
        let normalizedTokens = IngredientLexicon.tokenize(query.normalized)
        var fuzzyCandidateIDs = PantryCatalog.itemIDs(matchingAnyToken: Set(normalizedTokens))
        if fuzzyCandidateIDs.isEmpty {
            // Broader fallback: all items (rare case, 780 items is still fast)
            fuzzyCandidateIDs = Set(PantryCatalog.allItems.map(\.id))
        }

        for itemID in fuzzyCandidateIDs {
            guard let item = PantryCatalog.item(id: itemID) else { continue }
            let itemNormalized = IngredientLexicon.normalizeIngredient(item.name)
            let fuzzyScore = IngredientLexicon.fuzzySimilarity(query.normalized, itemNormalized)
            guard fuzzyScore >= ResolutionThresholds.fuzzy else { continue }

            let facets = IngredientLexicon.inferredFacets(forLookupKey: query.lookupKey, item: item)
            register(
                item: item, facets: facets,
                stage: .fuzzy, score: min(0.82, fuzzyScore),
                rationale: "Fuzzy retrieval kept \(item.name) in consideration.",
                into: &candidatesByID
            )
        }

        preferFacetSpecificCandidates(for: query, in: &candidatesByID)
        preferFacetSpecificExactMatches(in: &candidatesByID)
        preferGenericFallbacks(in: &candidatesByID)

        let resolvedCandidates = candidatesByID.values
            .sorted {
                if $0.candidate.score == $1.candidate.score {
                    if $0.stage.rawValue == $1.stage.rawValue {
                        if $0.candidate.facets.count == $1.candidate.facets.count {
                            return $0.candidate.displayName < $1.candidate.displayName
                        }
                        return $0.candidate.facets.count > $1.candidate.facets.count
                    }
                    return $0.stage.rawValue < $1.stage.rawValue
                }
                return $0.candidate.score > $1.candidate.score
            }
            .prefix(maxCandidates)
            .map(\.candidate)

        cacheCandidates(resolvedCandidates, for: cacheKey)
        return resolvedCandidates
    }

    private func cacheCandidates(_ candidates: [IngredientResolutionCandidate], for key: CacheKey) {
        cacheLock.lock()
        cachedCandidatesByKey[key] = candidates
        cacheLock.unlock()
    }

    private func preferGenericFallbacks(in candidatesByID: inout [String: ScoredCandidate]) {
        let catalogItemIDsWithGenericFallback = Set(
            candidatesByID.values.compactMap { scoredCandidate -> String? in
                let candidate = scoredCandidate.candidate
                let hasGenericFacet = candidate.facets.contains {
                    $0.value == "none"
                }
                return hasGenericFacet ? candidate.catalogItemID : nil
            }
        )

        guard !catalogItemIDsWithGenericFallback.isEmpty else { return }

        candidatesByID = candidatesByID.filter { _, scoredCandidate in
            let candidate = scoredCandidate.candidate
            if !catalogItemIDsWithGenericFallback.contains(candidate.catalogItemID) {
                return true
            }

            return !candidate.facets.isEmpty
        }
    }

    private func preferFacetSpecificExactMatches(in candidatesByID: inout [String: ScoredCandidate]) {
        let exactFacetMatchedItemIDs = Set(
            candidatesByID.values.compactMap { scoredCandidate -> String? in
                let candidate = scoredCandidate.candidate
                guard scoredCandidate.stage == .exactTemplate,
                      !candidate.facets.isEmpty,
                      candidate.score >= ResolutionThresholds.exactTemplateToken else {
                    return nil
                }
                return candidate.catalogItemID
            }
        )

        guard !exactFacetMatchedItemIDs.isEmpty else { return }

        candidatesByID = candidatesByID.filter { _, scoredCandidate in
            let candidate = scoredCandidate.candidate
            guard exactFacetMatchedItemIDs.contains(candidate.catalogItemID) else {
                return true
            }

            return !candidate.facets.isEmpty
        }
    }

    private func preferFacetSpecificCandidates(
        for query: IngredientLexicon.ParsedText,
        in candidatesByID: inout [String: ScoredCandidate]
    ) {
        let lookupTokens = IngredientLexicon.tokenize(query.lookupKey)
        guard lookupTokens.count > 1 else { return }

        let queryLookup = query.lookupKey

        let explicitlyMatchedItemIDs = Set(
            candidatesByID.values.compactMap { scoredCandidate -> String? in
                let candidate = scoredCandidate.candidate
                guard !candidate.facets.isEmpty, candidate.score >= ResolutionThresholds.facetCandidate else {
                    return nil
                }

                let facetValues = candidate.facets.map(\.value)
                let allFacetValuesAppearInQuery = facetValues.allSatisfy { facetValue in
                    let normalizedFacetValue = IngredientLexicon.lookupKey(facetValue)
                    return !normalizedFacetValue.isEmpty && queryLookup.contains(normalizedFacetValue)
                }
                return allFacetValuesAppearInQuery ? candidate.catalogItemID : nil
            }
        )

        if !explicitlyMatchedItemIDs.isEmpty {
            candidatesByID = candidatesByID.filter { _, scoredCandidate in
                let candidate = scoredCandidate.candidate
                guard explicitlyMatchedItemIDs.contains(candidate.catalogItemID) else {
                    return true
                }

                guard !candidate.facets.isEmpty else { return false }
                return candidate.facets.allSatisfy { facet in
                    let normalizedFacetValue = IngredientLexicon.lookupKey(facet.value)
                    return !normalizedFacetValue.isEmpty && queryLookup.contains(normalizedFacetValue)
                }
            }
            return
        }

        let itemIDsWithFacetSpecificCandidates = Set(
            candidatesByID.values.compactMap { scoredCandidate -> String? in
                let candidate = scoredCandidate.candidate
                guard !candidate.facets.isEmpty, candidate.score >= ResolutionThresholds.facetCandidate else {
                    return nil
                }
                return candidate.catalogItemID
            }
        )

        guard !itemIDsWithFacetSpecificCandidates.isEmpty else { return }

        candidatesByID = candidatesByID.filter { _, scoredCandidate in
            let candidate = scoredCandidate.candidate
            guard itemIDsWithFacetSpecificCandidates.contains(candidate.catalogItemID) else {
                return true
            }

            return !candidate.facets.isEmpty
        }
    }

    private func registerGenericFallbacks(
        query: IngredientLexicon.ParsedText,
        lookupTokens: [String],
        candidateItemIDs: Set<String>,
        into candidatesByID: inout [String: ScoredCandidate]
    ) {
        let queryTokens = lookupTokens.isEmpty ? query.tokens : lookupTokens
        let queryTokenSet = Set(queryTokens)
        guard !queryTokenSet.isEmpty else { return }

        for itemID in candidateItemIDs {
            guard let item = PantryCatalog.item(id: itemID) else { continue }

            let genericFacetKey: PantryFacetKey?
            if item.supports(.variant) {
                genericFacetKey = .variant
            } else if item.supports(.grade) {
                genericFacetKey = .grade
            } else if item.supports(.form) {
                genericFacetKey = .form
            } else {
                genericFacetKey = nil
            }
            guard let genericFacetKey else { continue }

            let itemTokens = IngredientLexicon.tokenize(IngredientLexicon.lookupKey(item.name))
            let itemTokenSet = Set(itemTokens)
            guard !itemTokenSet.isEmpty, itemTokenSet.isSubset(of: queryTokenSet) else { continue }

            let meaningfulExtraTokens = queryTokens.filter {
                !itemTokenSet.contains($0) && !Self.nonSpecificDescriptorTokens.contains($0)
            }
            guard !meaningfulExtraTokens.isEmpty else { continue }

            let tokenScore = IngredientLexicon.weightedTokenScore(
                queryTokens: queryTokens,
                candidateTokens: itemTokens
            )
            let itemLookup = IngredientLexicon.lookupKey(item.name)
            let containmentBoost = query.lookupKey.contains(itemLookup) ? 0.08 : 0
            let score = min(0.92, max(0.8, tokenScore + 0.08 + containmentBoost))

            register(
                item: item,
                facets: [PantryFacetSelection(key: genericFacetKey, value: "none")],
                stage: .lexical,
                score: score,
                rationale: "Matched the base ingredient but kept subtype unspecified for descriptors: \(meaningfulExtraTokens.joined(separator: ", ")).",
                into: &candidatesByID
            )
        }
    }

    private func scoreLexicalItem(
        _ item: PantryCatalogItemDefinition,
        query: IngredientLexicon.ParsedText,
        expandedQueryTokens: [String],
        into candidatesByID: inout [String: ScoredCandidate]
    ) {
        let itemTokens = IngredientLexicon.tokenize(IngredientLexicon.lookupKey(item.name))
        let itemLookup = IngredientLexicon.lookupKey(item.name)

        let tokenScore = IngredientLexicon.weightedTokenScore(queryTokens: expandedQueryTokens, candidateTokens: itemTokens)
        let containmentScore: Double = (itemLookup.contains(query.lookupKey) || query.lookupKey.contains(itemLookup))
            ? ResolutionThresholds.containment : 0
        let combinedScore = max(tokenScore, containmentScore)
        guard combinedScore >= ResolutionThresholds.combinedLexical else { return }

        let facets = IngredientLexicon.inferredFacets(forLookupKey: query.lookupKey, item: item)
        register(
            item: item, facets: facets,
            stage: .lexical, score: min(0.94, combinedScore),
            rationale: containmentScore > 0
                ? "Strong lexical phrase overlap with \(item.name)."
                : "Weighted token retrieval suggests \(item.name).",
            into: &candidatesByID
        )
    }

    private func register(
        item: PantryCatalogItemDefinition,
        facets: [PantryFacetSelection],
        stage: RetrievalStage,
        score: Double,
        rationale: String,
        into candidatesByID: inout [String: ScoredCandidate]
    ) {
        let candidate = IngredientResolutionCandidate(
            id: candidateID(for: item.id, facets: facets),
            catalogItemID: item.id,
            facets: facets,
            displayName: item.displayName(for: facets),
            score: score,
            rationale: rationale,
            supportedFacets: item.facets
        )

        if let existing = candidatesByID[candidate.id] {
            if candidate.score > existing.candidate.score ||
                (candidate.score == existing.candidate.score && stage.rawValue < existing.stage.rawValue) {
                candidatesByID[candidate.id] = ScoredCandidate(candidate: candidate, stage: stage)
            }
            return
        }

        candidatesByID[candidate.id] = ScoredCandidate(candidate: candidate, stage: stage)
    }

    private func candidateID(for catalogItemID: String, facets: [PantryFacetSelection]) -> String {
        let facetKey = facets
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: "|")
        return facetKey.isEmpty ? catalogItemID : "\(catalogItemID)|\(facetKey)"
    }

    private static let nonSpecificDescriptorTokens: Set<String> = [
        "meat", "cut", "cuts", "piece", "pieces", "protein"
    ]
}

final class RecipeIngredientResolver: RecipeIngredientResolverProtocol {
    private let candidateParser: IngredientCandidateParserProtocol
    private let aiService: AIServiceProtocol

    init(candidateParser: IngredientCandidateParserProtocol, aiService: AIServiceProtocol) {
        self.candidateParser = candidateParser
        self.aiService = aiService
    }

    func resolve(recipe: Recipe) async -> RecipeResolutionDraft {
        let baseDrafts = recipe.ingredients.map { ingredient -> ResolvedIngredientDraft in
            if ingredient.isResolved {
                return ResolvedIngredientDraft(
                    ingredient: ingredient,
                    status: .resolved,
                    candidates: ingredient.linkedItem.map {
                        [IngredientResolutionCandidate(
                            id: candidateID(for: $0.id, facets: ingredient.facets),
                            catalogItemID: $0.id,
                            facets: ingredient.facets,
                            displayName: $0.displayName(for: ingredient.facets),
                            score: 1,
                            rationale: "Already linked to this catalog item.",
                            supportedFacets: $0.facets
                        )]
                    } ?? [],
                    selectedCandidateID: ingredient.catalogItemID.map { candidateID(for: $0, facets: ingredient.facets) },
                    confidence: 1,
                    rationale: "Already resolved."
                )
            }

            let candidates = candidateParser.candidates(for: ingredient)
            let query = IngredientLexicon.parse(ingredient.rawName)
            let fallbackCandidate = fallbackResolvedCandidate(for: candidates, query: query)
            let fallbackStatus = fallbackStatus(
                for: candidates,
                fallbackCandidate: fallbackCandidate,
                query: query
            )
            let fallbackCandidateID = fallbackStatus == .resolved ? fallbackCandidate?.id : nil

            return ResolvedIngredientDraft(
                ingredient: ingredient,
                status: fallbackStatus,
                candidates: candidates,
                selectedCandidateID: fallbackCandidateID,
                confidence: candidates.first?.score ?? 0,
                rationale: candidates.first?.rationale ?? "No credible catalog candidate was found."
            )
        }

        let requests = baseDrafts.compactMap { draft -> IngredientResolutionRequest? in
            guard !draft.ingredient.isResolved else { return nil }
            return IngredientResolutionRequest(
                ingredientID: draft.ingredient.id,
                rawName: draft.ingredient.rawName,
                quantity: draft.ingredient.quantity,
                unit: draft.ingredient.unit,
                category: draft.ingredient.category,
                notes: draft.ingredient.notes,
                candidates: draft.candidates
            )
        }

        let aiDecisions = await aiService.resolveIngredients(requests) ?? []
        let decisionsByIngredient: [UUID: IngredientResolutionDecision] = Dictionary(
            uniqueKeysWithValues: aiDecisions.map { ($0.ingredientID, $0) }
        )

        let resolvedDrafts = baseDrafts.map { draft in
            guard let decision = decisionsByIngredient[draft.ingredient.id] else {
                return draft
            }
            return validatedDraft(from: draft, decision: decision)
        }

        return RecipeResolutionDraft(recipe: recipe, ingredients: resolvedDrafts)
    }

    private func fallbackResolvedCandidate(
        for candidates: [IngredientResolutionCandidate],
        query: IngredientLexicon.ParsedText
    ) -> IngredientResolutionCandidate? {
        let queryMatchedFacetCandidates = candidates.filter { candidate in
            guard !candidate.facets.isEmpty else { return false }
            return candidate.facets.allSatisfy { facet in
                let normalizedFacetValue = IngredientLexicon.lookupKey(facet.value)
                return !normalizedFacetValue.isEmpty && query.lookupKey.contains(normalizedFacetValue)
            }
        }

        if let matchedFacetCandidate = queryMatchedFacetCandidates.max(by: { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.facets.count < rhs.facets.count
            }
            return lhs.score < rhs.score
        }) {
            return matchedFacetCandidate
        }

        if let exactTemplateCandidate = candidates.first(where: {
            $0.score >= ResolutionThresholds.exactTemplateToken && $0.rationale.contains("Exact facet template")
        }) {
            return exactTemplateCandidate
        }

        return candidates.first
    }

    private func fallbackStatus(
        for candidates: [IngredientResolutionCandidate],
        fallbackCandidate: IngredientResolutionCandidate?,
        query: IngredientLexicon.ParsedText
    ) -> IngredientResolutionStatus {
        guard let bestCandidate = candidates.first else {
            return .unknown
        }

        if let fallbackCandidate,
           fallbackCandidate.score >= ResolutionThresholds.exactTemplateToken,
           fallbackCandidate.rationale.contains("Exact facet template") {
            return .resolved
        }

        if IngredientLexicon.tokenize(query.lookupKey).count > 1,
              let fallbackCandidate,
           !fallbackCandidate.facets.isEmpty,
              fallbackCandidate.score >= 0.8 {
            return .resolved
        }

        if candidates.count == 1 && bestCandidate.score >= ResolutionThresholds.facetCandidate {
            return .resolved
        }

        if let secondCandidate = candidates.dropFirst().first,
           bestCandidate.score >= 0.98,
           bestCandidate.score - secondCandidate.score >= 0.04 {
            return .resolved
        }

        return .ambiguous
    }

    private func validatedDraft(from draft: ResolvedIngredientDraft, decision: IngredientResolutionDecision) -> ResolvedIngredientDraft {
        var validated = draft

        let candidateIDs = Set(draft.candidates.map(\.id))
        let validCandidateIDs = decision.candidateIDs.filter { candidateIDs.contains($0) }

        switch decision.status {
        case .resolved:
            guard let selectedCandidateID = decision.selectedCandidateID,
                  candidateIDs.contains(selectedCandidateID) else {
                return draft
            }

            validated.status = .resolved
            validated.selectedCandidateID = selectedCandidateID
            validated.confidence = decision.confidence
            validated.rationale = decision.rationale
        case .ambiguous:
            validated.status = .ambiguous
            validated.selectedCandidateID = nil
            validated.confidence = decision.confidence
            validated.rationale = decision.rationale
            if !validCandidateIDs.isEmpty {
                validated.candidates = draft.candidates.filter { validCandidateIDs.contains($0.id) }
            }
        case .unknown:
            validated.status = .unknown
            validated.selectedCandidateID = nil
            validated.confidence = decision.confidence
            validated.rationale = decision.rationale
        }

        return validated
    }

    private func candidateID(for catalogItemID: String, facets: [PantryFacetSelection]) -> String {
        let facetKey = facets
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: "|")
        return facetKey.isEmpty ? catalogItemID : "\(catalogItemID)|\(facetKey)"
    }
}