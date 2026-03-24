import Foundation

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

    private static let catalogPhrases = PantryCatalog.allItems.flatMap(IngredientLexicon.generatedCatalogPhrases(for:))
    private static let catalogPhraseIndex = CatalogPhraseIndex(phrases: catalogPhrases)

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
        let phraseIndex = Self.catalogPhraseIndex

        var candidatesByID: [String: ScoredCandidate] = [:]

        register(
            phrases: phraseIndex.exactPhrases(source: .name, lookupKey: query.lookupKey),
            stage: .exactName,
            score: 1,
            rationale: { phrase in "Exact catalog name match for \(phrase.text)." },
            into: &candidatesByID
        )

        register(
            phrases: phraseIndex.exactPhrases(source: .alias, lookupKey: query.lookupKey),
            stage: .exactAlias,
            score: 0.995,
            rationale: { phrase in "Exact alias match for \(phrase.text)." },
            into: &candidatesByID
        )

        register(
            phrases: phraseIndex.exactPhrases(source: .template, lookupKey: query.lookupKey),
            stage: .exactTemplate,
            score: 0.99,
            rationale: { phrase in "Exact facet template match for \(phrase.text)." },
            into: &candidatesByID
        )

        if !queryLookupTokenSet.isEmpty {
            register(
                phrases: phraseIndex.templatePhrases(matchingTokenSet: queryLookupTokenSet, excludingLookupKey: query.lookupKey),
                stage: .exactTemplate,
                score: 0.985,
                rationale: { phrase in "Exact facet template token match for \(phrase.text)." },
                into: &candidatesByID
            )
        }

        let synonymLookups = IngredientLexicon.synonymLookupGroup(for: ingredient.rawName)
            .subtracting([query.lookupKey])
        if !synonymLookups.isEmpty {
            register(
                phrases: phraseIndex.phrases(withLookupKeys: synonymLookups),
                stage: .exactSynonym,
                score: 0.96,
                rationale: { phrase in "Synonym expansion linked \(ingredient.rawName) to \(phrase.text)." },
                into: &candidatesByID
            )
        }

        if !query.tokens.isEmpty {
            let synonymTokens = synonymLookups.flatMap(IngredientLexicon.tokenize)
            let expandedQueryTokens = Array(Set(query.tokens + synonymTokens))

            for phrase in phraseIndex.lexicalCandidates(
                queryTokens: expandedQueryTokens,
                lookupKey: query.lookupKey,
                synonymLookups: synonymLookups
            ) {
                let tokenScore = IngredientLexicon.weightedTokenScore(
                    queryTokens: expandedQueryTokens,
                    candidateTokens: phrase.tokens
                )

                let containmentScore: Double
                if phrase.lookupKey.contains(query.lookupKey) || query.lookupKey.contains(phrase.lookupKey) {
                    containmentScore = 0.9
                } else {
                    containmentScore = 0
                }

                let combinedScore = max(tokenScore, containmentScore)
                guard combinedScore >= 0.48 else { continue }

                register(
                    phrase: phrase,
                    stage: .lexical,
                    score: min(0.94, combinedScore),
                    rationale: containmentScore > 0
                        ? "Strong lexical phrase overlap with \(phrase.text)."
                        : "Weighted token retrieval suggests \(phrase.text).",
                    into: &candidatesByID
                )
            }

            registerGenericFallbacks(
                query: query,
                candidatePhrases: phraseIndex.genericFallbackCandidates(for: expandedQueryTokens),
                into: &candidatesByID
            )
        }

        for phrase in phraseIndex.fuzzyCandidates(normalized: query.normalized, queryTokens: query.tokens) {
            let fuzzyScore = IngredientLexicon.fuzzySimilarity(query.normalized, phrase.normalized)
            guard fuzzyScore >= 0.78 else { continue }

            register(
                phrase: phrase,
                stage: .fuzzy,
                score: min(0.82, fuzzyScore),
                rationale: "Fuzzy retrieval kept \(phrase.text) in consideration.",
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
                    $0.value == "generic"
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
                      candidate.score >= 0.985 else {
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
                guard !candidate.facets.isEmpty, candidate.score >= 0.9 else {
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
                guard !candidate.facets.isEmpty, candidate.score >= 0.9 else {
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
        candidatePhrases: [IngredientLexicon.CatalogPhrase],
        into candidatesByID: inout [String: ScoredCandidate]
    ) {
        let queryTokenSet = Set(query.tokens)
        guard !queryTokenSet.isEmpty else { return }

        for phrase in candidatePhrases where phrase.source != .template {
            guard phrase.facets.first(where: { $0.key == .variant || $0.key == .base || $0.key == .form }) == nil else { continue }
            guard let item = PantryCatalog.item(id: phrase.itemID) else { continue }

            let genericFacetKey: PantryFacetKey?
            if item.options(for: .variant).contains("generic") {
                genericFacetKey = .variant
            } else if item.options(for: .base).contains("generic") {
                genericFacetKey = .base
            } else if item.options(for: .form).contains("generic") {
                genericFacetKey = .form
            } else {
                genericFacetKey = nil
            }
            guard let genericFacetKey else { continue }

            let phraseTokenSet = Set(phrase.tokens)
            guard !phraseTokenSet.isEmpty, phraseTokenSet.isSubset(of: queryTokenSet) else { continue }

            let meaningfulExtraTokens = query.tokens.filter {
                !phraseTokenSet.contains($0) && !Self.nonSpecificDescriptorTokens.contains($0)
            }
            guard !meaningfulExtraTokens.isEmpty else { continue }

            let tokenScore = IngredientLexicon.weightedTokenScore(
                queryTokens: query.tokens,
                candidateTokens: phrase.tokens
            )
            let containmentBoost = query.lookupKey.contains(phrase.lookupKey) ? 0.08 : 0
            let score = min(0.92, max(0.8, tokenScore + 0.08 + containmentBoost))

            register(
                item: item,
                facets: [PantryFacetSelection(key: genericFacetKey, value: "generic")],
                stage: .lexical,
                score: score,
                rationale: "Matched the base ingredient but kept subtype as generic for descriptors: \(meaningfulExtraTokens.joined(separator: ", ")).",
                into: &candidatesByID
            )
        }
    }

    private func register(
        phrases: [IngredientLexicon.CatalogPhrase],
        stage: RetrievalStage,
        score: Double,
        rationale: (IngredientLexicon.CatalogPhrase) -> String,
        into candidatesByID: inout [String: ScoredCandidate]
    ) {
        for phrase in phrases {
            register(phrase: phrase, stage: stage, score: score, rationale: rationale(phrase), into: &candidatesByID)
        }
    }

    private func register(
        phrase: IngredientLexicon.CatalogPhrase,
        stage: RetrievalStage,
        score: Double,
        rationale: String,
        into candidatesByID: inout [String: ScoredCandidate]
    ) {
        guard let item = PantryCatalog.item(id: phrase.itemID) else { return }

        let candidate = IngredientResolutionCandidate(
            id: candidateID(for: item.id, facets: phrase.facets),
            catalogItemID: item.id,
            facets: phrase.facets,
            displayName: item.displayName(for: phrase.facets),
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

private struct CatalogPhraseIndex {
    private let phrases: [IngredientLexicon.CatalogPhrase]
    private let exactPhraseIndices: [IngredientLexicon.CatalogPhraseSource: [String: [Int]]]
    private let lookupKeyIndices: [String: [Int]]
    private let templateTokenSetIndices: [String: [Int]]
    private let tokenToPhraseIndices: [String: Set<Int>]
    private let normalizedLengthIndices: [Int: Set<Int>]
    private let leadingCharacterIndices: [Character: Set<Int>]

    init(phrases: [IngredientLexicon.CatalogPhrase]) {
        self.phrases = phrases

        var exactPhraseIndices: [IngredientLexicon.CatalogPhraseSource: [String: [Int]]] = [:]
        var lookupKeyIndices: [String: [Int]] = [:]
        var templateTokenSetIndices: [String: [Int]] = [:]
        var tokenToPhraseIndices: [String: Set<Int>] = [:]
        var normalizedLengthIndices: [Int: Set<Int>] = [:]
        var leadingCharacterIndices: [Character: Set<Int>] = [:]

        for (index, phrase) in phrases.enumerated() {
            exactPhraseIndices[phrase.source, default: [:]][phrase.lookupKey, default: []].append(index)
            lookupKeyIndices[phrase.lookupKey, default: []].append(index)

            if phrase.source == .template {
                templateTokenSetIndices[Self.tokenSetKey(phrase.tokens), default: []].append(index)
            }

            for token in Set(phrase.tokens) {
                tokenToPhraseIndices[token, default: []].insert(index)
            }

            normalizedLengthIndices[phrase.normalized.count, default: []].insert(index)
            if let leadingCharacter = phrase.normalized.first {
                leadingCharacterIndices[leadingCharacter, default: []].insert(index)
            }
        }

        self.exactPhraseIndices = exactPhraseIndices
        self.lookupKeyIndices = lookupKeyIndices
        self.templateTokenSetIndices = templateTokenSetIndices
        self.tokenToPhraseIndices = tokenToPhraseIndices
        self.normalizedLengthIndices = normalizedLengthIndices
        self.leadingCharacterIndices = leadingCharacterIndices
    }

    func exactPhrases(source: IngredientLexicon.CatalogPhraseSource, lookupKey: String) -> [IngredientLexicon.CatalogPhrase] {
        phrases(at: exactPhraseIndices[source]?[lookupKey] ?? [])
    }

    func phrases(withLookupKeys lookupKeys: Set<String>) -> [IngredientLexicon.CatalogPhrase] {
        phrases(at: Set(lookupKeys.flatMap { lookupKeyIndices[$0] ?? [] }))
    }

    func templatePhrases(matchingTokenSet tokenSet: Set<String>, excludingLookupKey lookupKey: String) -> [IngredientLexicon.CatalogPhrase] {
        phrases(at: templateTokenSetIndices[Self.tokenSetKey(tokenSet)] ?? []).filter { $0.lookupKey != lookupKey }
    }

    func lexicalCandidates(
        queryTokens: [String],
        lookupKey: String,
        synonymLookups: Set<String>
    ) -> [IngredientLexicon.CatalogPhrase] {
        var indices = Set(lookupKeyIndices[lookupKey] ?? [])
        for synonymLookup in synonymLookups {
            indices.formUnion(lookupKeyIndices[synonymLookup] ?? [])
        }

        for token in Set(queryTokens) {
            indices.formUnion(tokenToPhraseIndices[token] ?? [])
        }

        return phrases(at: indices)
    }

    func genericFallbackCandidates(for queryTokens: [String]) -> [IngredientLexicon.CatalogPhrase] {
        phrases(at: candidateIndices(for: queryTokens))
    }

    func fuzzyCandidates(normalized: String, queryTokens: [String]) -> [IngredientLexicon.CatalogPhrase] {
        var indices = candidateIndices(for: queryTokens)

        if indices.isEmpty {
            let normalizedLength = normalized.count
            for length in max(0, normalizedLength - 2)...(normalizedLength + 2) {
                indices.formUnion(normalizedLengthIndices[length] ?? [])
            }
        }

        if let leadingCharacter = normalized.first,
           let leadingCandidates = leadingCharacterIndices[leadingCharacter],
           !indices.isEmpty {
            indices.formIntersection(leadingCandidates)
        }

        if indices.isEmpty {
            indices = candidateIndices(for: IngredientLexicon.tokenize(normalized))
        }

        return phrases(at: indices)
    }

    private func candidateIndices(for queryTokens: [String]) -> Set<Int> {
        var indices: Set<Int> = []
        for token in Set(queryTokens) {
            indices.formUnion(tokenToPhraseIndices[token] ?? [])
        }
        return indices
    }

    private func phrases(at indices: [Int]) -> [IngredientLexicon.CatalogPhrase] {
        indices.map { phrases[$0] }
    }

    private func phrases(at indices: Set<Int>) -> [IngredientLexicon.CatalogPhrase] {
        indices.sorted().map { phrases[$0] }
    }

    private static func tokenSetKey<S: Sequence>(_ tokens: S) -> String where S.Element == String {
        Array(tokens).sorted().joined(separator: "|")
    }
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
            $0.score >= 0.985 && $0.rationale.contains("Exact facet template")
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
           fallbackCandidate.score >= 0.985,
           fallbackCandidate.rationale.contains("Exact facet template") {
            return .resolved
        }

        if IngredientLexicon.tokenize(query.lookupKey).count > 1,
              let fallbackCandidate,
           !fallbackCandidate.facets.isEmpty,
              fallbackCandidate.score >= 0.8 {
            return .resolved
        }

        if candidates.count == 1 && bestCandidate.score >= 0.9 {
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