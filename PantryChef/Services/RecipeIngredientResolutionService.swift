import Foundation

final class IngredientCandidateParser: IngredientCandidateParserProtocol {
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

    private let maxCandidates: Int

    init(maxCandidates: Int = 4) {
        self.maxCandidates = maxCandidates
    }

    func candidates(for ingredient: Ingredient) -> [IngredientResolutionCandidate] {
        if let item = ingredient.linkedItem {
            return [
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
        }

        let query = IngredientLexicon.parse(ingredient.rawName)
        guard !query.lookupKey.isEmpty else { return [] }

        var candidatesByID: [String: ScoredCandidate] = [:]

        register(
            phrases: Self.catalogPhrases.filter { $0.source == .name && $0.lookupKey == query.lookupKey },
            stage: .exactName,
            score: 1,
            rationale: { phrase in "Exact catalog name match for \(phrase.text)." },
            into: &candidatesByID
        )

        register(
            phrases: Self.catalogPhrases.filter { $0.source == .alias && $0.lookupKey == query.lookupKey },
            stage: .exactAlias,
            score: 0.995,
            rationale: { phrase in "Exact alias match for \(phrase.text)." },
            into: &candidatesByID
        )

        register(
            phrases: Self.catalogPhrases.filter { $0.source == .template && $0.lookupKey == query.lookupKey },
            stage: .exactTemplate,
            score: 0.99,
            rationale: { phrase in "Exact facet template match for \(phrase.text)." },
            into: &candidatesByID
        )

        let synonymLookups = IngredientLexicon.synonymLookupGroup(for: ingredient.rawName)
            .subtracting([query.lookupKey])
        if !synonymLookups.isEmpty {
            register(
                phrases: Self.catalogPhrases.filter { synonymLookups.contains($0.lookupKey) },
                stage: .exactSynonym,
                score: 0.96,
                rationale: { phrase in "Synonym expansion linked \(ingredient.rawName) to \(phrase.text)." },
                into: &candidatesByID
            )
        }

        if !query.tokens.isEmpty {
            let synonymTokens = synonymLookups.flatMap(IngredientLexicon.tokenize)
            let expandedQueryTokens = Array(Set(query.tokens + synonymTokens))

            for phrase in Self.catalogPhrases {
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

            registerGenericFallbacks(query: query, into: &candidatesByID)
        }

        for phrase in Self.catalogPhrases {
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

        preferGenericFallbacks(in: &candidatesByID)

        return candidatesByID.values
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

    private func registerGenericFallbacks(
        query: IngredientLexicon.ParsedText,
        into candidatesByID: inout [String: ScoredCandidate]
    ) {
        let queryTokenSet = Set(query.tokens)
        guard !queryTokenSet.isEmpty else { return }

        for phrase in Self.catalogPhrases where phrase.source != .template {
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
            let fallbackStatus: IngredientResolutionStatus = candidates.isEmpty ? .unknown : (candidates.count == 1 && candidates[0].score >= 0.9 ? .resolved : .ambiguous)
            let fallbackCandidateID = fallbackStatus == .resolved ? candidates.first?.id : nil

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