import Foundation

struct CatalogSearchResult: Identifiable, Hashable {
    let id: String
    let catalogItemID: String
    let facets: [PantryFacetSelection]
    let displayName: String
    let score: Double
    let item: PantryCatalogItemDefinition

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CatalogSearchResult, rhs: CatalogSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

enum CatalogSearchEngine {

    private static let maxResults = 20
    private static let maxFuzzyDistance = 2

    // MARK: - Prebuilt key sets for fuzzy correction

    /// All unique tokens from item names/aliases (keys of tokenIndex).
    private static let nameTokenKeys: [String] = {
        Array(PantryCatalog.tokenIndex.keys)
    }()

    /// All unique single-token facet option keys.
    private static let facetSingleTokenKeys: [String] = {
        // Only include single-token keys (multi-token facet options are handled separately)
        PantryCatalog.facetTokenToItems.keys.filter { !$0.contains(" ") }.map { $0 }
    }()

    /// All unique multi-token facet option keys.
    private static let facetMultiTokenKeys: [String] = {
        PantryCatalog.facetTokenToItems.keys.filter { $0.contains(" ") }.map { $0 }
    }()

    // MARK: - Public API

    static func search(_ query: String) -> [CatalogSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PantryCatalog.allItems
                .sorted { $0.name < $1.name }
                .prefix(maxResults)
                .map { defaultResult(for: $0) }
        }

        let lookupKey = IngredientLexicon.lookupKey(trimmed)
        guard !lookupKey.isEmpty else {
            return PantryCatalog.allItems
                .sorted { $0.name < $1.name }
                .prefix(maxResults)
                .map { defaultResult(for: $0) }
        }

        let queryTokens = IngredientLexicon.tokenize(lookupKey)

        // Step 1: Check for multi-token facet match first (e.g. "filet mignon")
        var consumedByMultiTokenFacet: Set<Int> = []
        var multiTokenFacetMatches: [(key: String, entries: [(itemID: String, key: PantryFacetKey, value: String)])] = []
        if queryTokens.count >= 2 {
            for facetKey in facetMultiTokenKeys {
                if lookupKey.contains(facetKey), let entries = PantryCatalog.facetTokenToItems[facetKey] {
                    multiTokenFacetMatches.append((key: facetKey, entries: entries))
                    let facetTokens = Set(IngredientLexicon.tokenize(facetKey))
                    for (i, token) in queryTokens.enumerated() {
                        if facetTokens.contains(token) {
                            consumedByMultiTokenFacet.insert(i)
                        }
                    }
                }
            }
        }

        // Step 2: Classify each remaining token
        var classifiedTokens: [ClassifiedToken] = []
        for (i, token) in queryTokens.enumerated() {
            if consumedByMultiTokenFacet.contains(i) { continue }
            classifiedTokens.append(classifyToken(token))
        }

        // Step 3: Collect candidate item IDs from all matched tokens
        var candidateScores: [String: CandidateAccumulator] = [:]

        // From multi-token facet matches
        for match in multiTokenFacetMatches {
            for entry in match.entries {
                candidateScores[entry.itemID, default: CandidateAccumulator()]
                    .addFacet(key: entry.key, value: entry.value, exact: true)
            }
        }

        // From classified single tokens
        for ct in classifiedTokens {
            switch ct.kind {
            case .nameToken(let itemIDs):
                for id in itemIDs {
                    candidateScores[id, default: CandidateAccumulator()]
                        .addNameToken(ct.original, exact: true)
                }
            case .facetToken(let entries):
                for entry in entries {
                    candidateScores[entry.itemID, default: CandidateAccumulator()]
                        .addFacet(key: entry.key, value: entry.value, exact: true)
                }
            case .fuzzyNameToken(let itemIDs, let corrected):
                for id in itemIDs {
                    candidateScores[id, default: CandidateAccumulator()]
                        .addNameToken(corrected, exact: false)
                }
            case .fuzzyFacetToken(let entries, _):
                for entry in entries {
                    candidateScores[entry.itemID, default: CandidateAccumulator()]
                        .addFacet(key: entry.key, value: entry.value, exact: false)
                }
            case .bothNameAndFacet(let nameIDs, let facetEntries):
                for id in nameIDs {
                    candidateScores[id, default: CandidateAccumulator()]
                        .addNameToken(ct.original, exact: true)
                }
                for entry in facetEntries {
                    candidateScores[entry.itemID, default: CandidateAccumulator()]
                        .addFacet(key: entry.key, value: entry.value, exact: true)
                }
            case .unmatched:
                break
            }
        }

        // Step 4: Also add items via full lookupKey exact alias match (handles "chicken breast" as a single alias)
        if let aliasItemID = PantryCatalog.resolveAlias(lookupKey),
           let item = PantryCatalog.item(id: aliasItemID) {
            var acc = candidateScores[aliasItemID] ?? CandidateAccumulator()
            acc.aliasMatch = true
            // Infer facets from the alias
            let facets = IngredientLexicon.inferredFacets(forLookupKey: lookupKey, item: item)
            for f in facets {
                acc.addFacet(key: f.key, value: f.value, exact: true)
            }
            for token in queryTokens where !consumedByMultiTokenFacet.contains(queryTokens.firstIndex(of: token) ?? -1) {
                acc.addNameToken(token, exact: true)
            }
            candidateScores[aliasItemID] = acc
        }

        // Step 5: Score and build results
        let totalQueryTokens = classifiedTokens.count + (multiTokenFacetMatches.isEmpty ? 0 : 1)
        guard totalQueryTokens > 0 else {
            return PantryCatalog.allItems
                .sorted { $0.name < $1.name }
                .prefix(maxResults)
                .map { defaultResult(for: $0) }
        }

        var results: [CatalogSearchResult] = []
        for (itemID, acc) in candidateScores {
            guard let item = PantryCatalog.item(id: itemID) else { continue }

            let matchedTokenCount = acc.matchedNameTokens.count + (acc.resolvedFacets.isEmpty ? 0 : acc.resolvedFacets.count)
            let coverage = Double(matchedTokenCount) / Double(totalQueryTokens)

            // Require at least some coverage
            guard coverage > 0.3 || acc.aliasMatch else { continue }

            let exactRatio = acc.exactCount > 0
                ? Double(acc.exactCount) / Double(acc.exactCount + acc.fuzzyCount)
                : 0.0

            // Check if name tokens actually belong to this item
            let itemNameTokens = Set(IngredientLexicon.tokenize(IngredientLexicon.lookupKey(item.name)))
            let nameTokenOverlap = acc.matchedNameTokens.intersection(itemNameTokens)
            let nameRelevance = itemNameTokens.isEmpty ? 0.0 : Double(nameTokenOverlap.count) / Double(itemNameTokens.count)

            var score = 0.0
            if acc.aliasMatch {
                score = 1.0
            } else {
                score = coverage * 0.5 + exactRatio * 0.2 + nameRelevance * 0.3
            }

            // Bonus for having both name and facet matches
            if !acc.matchedNameTokens.isEmpty && !acc.resolvedFacets.isEmpty {
                score += 0.05
            }

            // Resolve facet selections for this specific item
            let facets = resolveFacets(for: item, from: acc)
            let displayName = item.displayName(for: facets)

            let resultID = facets.isEmpty ? item.id : "\(item.id):\(facets.map(\.id).joined(separator: ","))"
            results.append(CatalogSearchResult(
                id: resultID,
                catalogItemID: item.id,
                facets: facets,
                displayName: displayName,
                score: min(1.0, score),
                item: item
            ))
        }

        results.sort { $0.score > $1.score }
        return Array(results.prefix(maxResults))
    }

    // MARK: - Token Classification

    private struct ClassifiedToken {
        let original: String
        let kind: Kind

        enum Kind {
            case nameToken(itemIDs: Set<String>)
            case facetToken(entries: [(itemID: String, key: PantryFacetKey, value: String)])
            case bothNameAndFacet(nameIDs: Set<String>, facetEntries: [(itemID: String, key: PantryFacetKey, value: String)])
            case fuzzyNameToken(itemIDs: Set<String>, corrected: String)
            case fuzzyFacetToken(entries: [(itemID: String, key: PantryFacetKey, value: String)], corrected: String)
            case unmatched
        }
    }

    private static func classifyToken(_ token: String) -> ClassifiedToken {
        let nameHit = PantryCatalog.tokenIndex[token]
        let facetHit = PantryCatalog.facetTokenToItems[token]

        if let nameIDs = nameHit, let facetEntries = facetHit {
            return ClassifiedToken(original: token, kind: .bothNameAndFacet(nameIDs: nameIDs, facetEntries: facetEntries))
        }
        if let nameIDs = nameHit {
            return ClassifiedToken(original: token, kind: .nameToken(itemIDs: nameIDs))
        }
        if let facetEntries = facetHit {
            return ClassifiedToken(original: token, kind: .facetToken(entries: facetEntries))
        }

        // Fuzzy fallback — find best match within edit distance 2
        return fuzzyCorrect(token)
    }

    private static func fuzzyCorrect(_ token: String) -> ClassifiedToken {
        var bestDistance = maxFuzzyDistance + 1
        var bestNameKey: String?
        var bestFacetKey: String?

        for key in nameTokenKeys {
            let dist = IngredientLexicon.levenshteinDistance(token, key)
            if dist < bestDistance {
                bestDistance = dist
                bestNameKey = key
                bestFacetKey = nil
            }
        }

        for key in facetSingleTokenKeys {
            let dist = IngredientLexicon.levenshteinDistance(token, key)
            if dist < bestDistance {
                bestDistance = dist
                bestNameKey = nil
                bestFacetKey = key
            }
        }

        if bestDistance <= maxFuzzyDistance {
            if let nameKey = bestNameKey, let ids = PantryCatalog.tokenIndex[nameKey] {
                return ClassifiedToken(original: token, kind: .fuzzyNameToken(itemIDs: ids, corrected: nameKey))
            }
            if let facetKey = bestFacetKey, let entries = PantryCatalog.facetTokenToItems[facetKey] {
                return ClassifiedToken(original: token, kind: .fuzzyFacetToken(entries: entries, corrected: facetKey))
            }
        }

        return ClassifiedToken(original: token, kind: .unmatched)
    }

    // MARK: - Accumulator

    private struct CandidateAccumulator {
        var matchedNameTokens: Set<String> = []
        var resolvedFacets: [PantryFacetKey: String] = [:]
        var exactCount = 0
        var fuzzyCount = 0
        var aliasMatch = false

        mutating func addNameToken(_ token: String, exact: Bool) {
            matchedNameTokens.insert(token)
            if exact { exactCount += 1 } else { fuzzyCount += 1 }
        }

        mutating func addFacet(key: PantryFacetKey, value: String, exact: Bool) {
            resolvedFacets[key] = value
            if exact { exactCount += 1 } else { fuzzyCount += 1 }
        }
    }

    // MARK: - Helpers

    private static func resolveFacets(
        for item: PantryCatalogItemDefinition,
        from acc: CandidateAccumulator
    ) -> [PantryFacetSelection] {
        item.facets.compactMap { definition in
            guard let value = acc.resolvedFacets[definition.key],
                  definition.options.contains(value) else { return nil }
            return PantryFacetSelection(key: definition.key, value: value)
        }
    }

    private static func defaultResult(for item: PantryCatalogItemDefinition) -> CatalogSearchResult {
        CatalogSearchResult(
            id: item.id,
            catalogItemID: item.id,
            facets: [],
            displayName: item.titleCasedName,
            score: 0,
            item: item
        )
    }
}
