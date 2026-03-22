import Foundation

final class IngredientCandidateParser: IngredientCandidateParserProtocol {
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

        let normalizedQuery = IngredientMatcher.normalize(ingredient.rawName)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryTokens = Self.tokenize(normalizedQuery)

        let scored = PantryCatalog.allItems.flatMap { item -> [(PantryCatalogItemDefinition, [PantryFacetSelection], Double, String)] in
            let forms = surfaceForms(for: item)
            var results: [(PantryCatalogItemDefinition, [PantryFacetSelection], Double, String)] = []
            var bestBaseScore = 0.0
            var bestBaseReason = ""

            for form in forms {
                let normalizedForm = IngredientMatcher.normalize(form)
                guard !normalizedForm.isEmpty else { continue }

                if normalizedForm == normalizedQuery {
                    bestBaseScore = 1.0
                    bestBaseReason = "Exact alias match for \(form)."
                    break
                }

                let formTokens = Self.tokenize(normalizedForm)
                let tokenScore = tokenOverlapScore(queryTokens: queryTokens, candidateTokens: formTokens)
                let fuzzyScore = fuzzySimilarity(normalizedQuery, normalizedForm)
                let containmentScore = containsScore(query: normalizedQuery, candidate: normalizedForm)
                let combined = max(tokenScore * 0.65 + fuzzyScore * 0.35, containmentScore)

                if combined > bestBaseScore {
                    bestBaseScore = combined
                    bestBaseReason = rationale(for: form, tokenScore: tokenScore, fuzzyScore: fuzzyScore, containmentScore: containmentScore)
                }
            }

            if bestBaseScore >= 0.42 {
                results.append((item, [], min(bestBaseScore, 0.99), bestBaseReason))
            }

            let facetHints = matchedFacetHints(for: item, queryTokens: queryTokens)
            for hint in facetHints {
                let score = min(max(bestBaseScore, 0.55) + 0.12, 0.99)
                results.append((
                    item,
                    [hint],
                    score,
                    "Facet hint \(hint.value) suggests \(item.displayName(for: [hint]))."
                ))
            }

            return results
        }

        return scored
            .sorted {
                if $0.2 == $1.2 {
                    if $0.1.count != $1.1.count {
                        return $0.1.count > $1.1.count
                    }
                    return $0.0.name < $1.0.name
                }
                return $0.2 > $1.2
            }
            .prefix(maxCandidates)
            .map { item, facets, score, reason in
                IngredientResolutionCandidate(
                    id: candidateID(for: item.id, facets: facets),
                    catalogItemID: item.id,
                    facets: facets,
                    displayName: item.displayName(for: facets),
                    score: score,
                    rationale: reason,
                    supportedFacets: item.facets
                )
            }
    }

    private func surfaceForms(for item: PantryCatalogItemDefinition) -> [String] {
        var forms = Set<String>()
        forms.insert(item.name)
        item.aliases.forEach { forms.insert($0) }

        for facet in item.facets {
            for option in facet.options {
                forms.insert("\(option) \(item.name)")
            }
        }

        return Array(forms)
    }

    private func matchedFacetHints(for item: PantryCatalogItemDefinition, queryTokens: Set<String>) -> [PantryFacetSelection] {
        item.facets.compactMap { definition in
            guard let matchedOption = definition.options.first(where: { queryTokens.contains(IngredientMatcher.normalize($0)) }) else {
                return nil
            }
            return PantryFacetSelection(key: definition.key, value: matchedOption)
        }
    }

    private func tokenOverlapScore(queryTokens: Set<String>, candidateTokens: Set<String>) -> Double {
        guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }
        let overlap = queryTokens.intersection(candidateTokens)
        let denominator = Double(max(queryTokens.count, candidateTokens.count))
        return Double(overlap.count) / denominator
    }

    private func containsScore(query: String, candidate: String) -> Double {
        if candidate.contains(query) || query.contains(candidate) {
            return 0.88
        }
        return 0
    }

    private func rationale(for form: String, tokenScore: Double, fuzzyScore: Double, containmentScore: Double) -> String {
        if containmentScore > 0 {
            return "Strong phrase overlap with \(form)."
        }
        if tokenScore >= fuzzyScore {
            return "Token overlap suggests \(form)."
        }
        return "Fuzzy match suggests \(form)."
    }

    private func fuzzySimilarity(_ lhs: String, _ rhs: String) -> Double {
        let distance = levenshteinDistance(lhs, rhs)
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else { return 1 }
        return 1 - Double(distance) / Double(maxLength)
    }

    private func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let lhsCount = lhsChars.count
        let rhsCount = rhsChars.count

        var distances = Array(0...rhsCount)
        for lhsIndex in 1...lhsCount {
            var previous = distances[0]
            distances[0] = lhsIndex

            for rhsIndex in 1...rhsCount {
                let current = distances[rhsIndex]
                if lhsChars[lhsIndex - 1] == rhsChars[rhsIndex - 1] {
                    distances[rhsIndex] = previous
                } else {
                    distances[rhsIndex] = min(previous, distances[rhsIndex - 1], current) + 1
                }
                previous = current
            }
        }
        return distances[rhsCount]
    }

    private static func tokenize(_ value: String) -> Set<String> {
        Set(value.split(separator: " ").map(String.init))
    }

    private func candidateID(for catalogItemID: String, facets: [PantryFacetSelection]) -> String {
        let facetKey = facets
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: "|")
        return facetKey.isEmpty ? catalogItemID : "\(catalogItemID)|\(facetKey)"
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