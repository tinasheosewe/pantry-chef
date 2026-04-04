import Foundation

// MARK: - Result

struct CatalogSearchResult: Identifiable, Hashable {
    let id: String
    let catalogItemID: String
    let facets: [PantryFacetSelection]
    let displayName: String
    let score: Double
    let item: PantryCatalogItemDefinition

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

// MARK: - Token Classification

/// Classifies a single query token against the catalog's prebuilt indexes.
enum TokenClassifier {

    enum Match {
        /// Exact hit in the name/alias token index.
        case name(itemIDs: Set<String>)
        /// Exact hit in the facet option index.
        case facet(entries: [FacetEntry])
        /// Exact hit in both name and facet indexes.
        case nameAndFacet(nameIDs: Set<String>, facetEntries: [FacetEntry])
        /// Fuzzy match (Levenshtein ≤ maxDistance) to a name token.
        case fuzzyName(itemIDs: Set<String>, corrected: String)
        /// Fuzzy match (Levenshtein ≤ maxDistance) to a facet token.
        case fuzzyFacet(entries: [FacetEntry], corrected: String)
        /// Bitap approximate substring hit on a name token.
        case bitapName(itemIDs: Set<String>, target: String)
        /// Bitap approximate substring hit on a facet token.
        case bitapFacet(entries: [FacetEntry], target: String)
        /// Prefix of a name token (e.g. "a" → "apple").
        case prefixName(itemIDs: Set<String>)
        /// Prefix of a facet token.
        case prefixFacet(entries: [FacetEntry])
        /// No match at all.
        case unmatched
    }

    typealias FacetEntry = (itemID: String, key: PantryFacetKey, value: String)

    /// Classifies `token` by trying strategies in priority order:
    /// exact → fuzzy (Levenshtein) → bitap substring → prefix → unmatched.
    static func classify(
        _ token: String,
        nameKeys: [String],
        facetKeys: [String],
        maxEditDistance: Int
    ) -> Match {
        // 1. Exact lookup
        if let exact = exactMatch(token) { return exact }

        // 2. Levenshtein fuzzy (for short edits like typos)
        if let fuzzy = levenshteinMatch(token, nameKeys: nameKeys, facetKeys: facetKeys, maxDistance: maxEditDistance) {
            return fuzzy
        }

        // 3. Bitap fuzzy substring (catches typo + longer candidate, e.g. "chese" in "cheesecloth")
        if let bitap = bitapMatch(token, nameKeys: nameKeys, facetKeys: facetKeys) {
            return bitap
        }

        // 4. Prefix (short partial input, e.g. "a" → "apple")
        if let prefix = prefixMatch(token, nameKeys: nameKeys, facetKeys: facetKeys) {
            return prefix
        }

        return .unmatched
    }

    // MARK: - Strategies

    private static func exactMatch(_ token: String) -> Match? {
        let nameHit = PantryCatalog.tokenIndex[token]
        let facetHit = PantryCatalog.facetTokenToItems[token]

        switch (nameHit, facetHit) {
        case let (n?, f?): return .nameAndFacet(nameIDs: n, facetEntries: f)
        case let (n?, nil): return .name(itemIDs: n)
        case let (nil, f?): return .facet(entries: f)
        default: return nil
        }
    }

    private static func levenshteinMatch(
        _ token: String,
        nameKeys: [String],
        facetKeys: [String],
        maxDistance: Int
    ) -> Match? {
        var bestDistance = maxDistance + 1
        var bestNameKey: String?
        var bestFacetKey: String?

        for key in nameKeys {
            let dist = IngredientLexicon.levenshteinDistance(token, key)
            if dist < bestDistance {
                bestDistance = dist
                bestNameKey = key
                bestFacetKey = nil
            }
        }

        for key in facetKeys {
            let dist = IngredientLexicon.levenshteinDistance(token, key)
            if dist < bestDistance {
                bestDistance = dist
                bestNameKey = nil
                bestFacetKey = key
            }
        }

        guard bestDistance <= maxDistance else { return nil }

        if let key = bestNameKey, let ids = PantryCatalog.tokenIndex[key] {
            return .fuzzyName(itemIDs: ids, corrected: key)
        }
        if let key = bestFacetKey, let entries = PantryCatalog.facetTokenToItems[key] {
            return .fuzzyFacet(entries: entries, corrected: key)
        }
        return nil
    }

    private static func bitapMatch(
        _ token: String,
        nameKeys: [String],
        facetKeys: [String]
    ) -> Match? {
        guard let pattern = BitapSearcher.createPattern(from: token) else { return nil }
        // Only use bitap when the token is long enough that Levenshtein didn't help
        // but short enough for the bitap word-size limit.
        guard token.count >= 3 else { return nil }

        var bestScore = 1.0
        var bestNameKey: String?
        var bestFacetKey: String?

        for key in nameKeys {
            if let match = BitapSearcher.search(pattern, in: key, threshold: 0.4) {
                if match.score < bestScore {
                    bestScore = match.score
                    bestNameKey = key
                    bestFacetKey = nil
                }
            }
        }

        for key in facetKeys {
            if let match = BitapSearcher.search(pattern, in: key, threshold: 0.4) {
                if match.score < bestScore {
                    bestScore = match.score
                    bestNameKey = nil
                    bestFacetKey = key
                }
            }
        }

        if let key = bestNameKey, let ids = PantryCatalog.tokenIndex[key] {
            return .bitapName(itemIDs: ids, target: key)
        }
        if let key = bestFacetKey, let entries = PantryCatalog.facetTokenToItems[key] {
            return .bitapFacet(entries: entries, target: key)
        }
        return nil
    }

    private static func prefixMatch(
        _ token: String,
        nameKeys: [String],
        facetKeys: [String]
    ) -> Match? {
        var nameIDs: Set<String> = []
        var facetEntries: [FacetEntry] = []

        for key in nameKeys where key.hasPrefix(token) && key != token {
            if let ids = PantryCatalog.tokenIndex[key] {
                nameIDs.formUnion(ids)
            }
        }

        for key in facetKeys where key.hasPrefix(token) && key != token {
            if let entries = PantryCatalog.facetTokenToItems[key] {
                facetEntries.append(contentsOf: entries)
            }
        }

        if !nameIDs.isEmpty && !facetEntries.isEmpty {
            return .nameAndFacet(nameIDs: nameIDs, facetEntries: facetEntries)
        }
        if !nameIDs.isEmpty { return .prefixName(itemIDs: nameIDs) }
        if !facetEntries.isEmpty { return .prefixFacet(entries: facetEntries) }
        return nil
    }
}

// MARK: - Candidate Scoring

/// Accumulates match evidence for a single candidate item and computes a
/// relevance score.
struct CandidateAccumulator {
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

enum CandidateScorer {

    struct ScoredCandidate {
        let item: PantryCatalogItemDefinition
        let facets: [PantryFacetSelection]
        let score: Double
    }

    /// Scores a candidate item given its accumulated evidence.
    static func score(
        item: PantryCatalogItemDefinition,
        accumulator acc: CandidateAccumulator,
        totalQueryTokens: Int,
        lookupKey: String
    ) -> ScoredCandidate? {
        let matchedTokenCount = acc.matchedNameTokens.count
            + (acc.resolvedFacets.isEmpty ? 0 : acc.resolvedFacets.count)
        let coverage = Double(matchedTokenCount) / Double(max(totalQueryTokens, 1))

        guard coverage > 0.3 || acc.aliasMatch else { return nil }

        var score: Double
        if acc.aliasMatch {
            score = 1.0
        } else {
            let exactRatio = acc.exactCount > 0
                ? Double(acc.exactCount) / Double(acc.exactCount + acc.fuzzyCount)
                : 0.0

            let itemNameTokens = Set(IngredientLexicon.tokenize(IngredientLexicon.lookupKey(item.name)))
            let nameTokenOverlap = acc.matchedNameTokens.intersection(itemNameTokens)
            let nameRelevance = itemNameTokens.isEmpty
                ? 0.0
                : Double(nameTokenOverlap.count) / Double(itemNameTokens.count)

            score = coverage * 0.5 + exactRatio * 0.2 + nameRelevance * 0.3
        }

        // Bonus: combined name + facet evidence
        if !acc.matchedNameTokens.isEmpty && !acc.resolvedFacets.isEmpty {
            score += 0.05
        }

        // Bonus: item name starts with the full query
        if IngredientLexicon.lookupKey(item.name).hasPrefix(lookupKey) {
            score += 0.15
        }

        let facets = resolveFacets(for: item, from: acc)
        return ScoredCandidate(item: item, facets: facets, score: min(1.0, score))
    }

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
}

// MARK: - Search Engine (Orchestrator)

/// Orchestrates catalog search by composing token classification, candidate
/// accumulation, and scoring into a single pipeline.
enum CatalogSearchEngine {

    private static let maxResults = 20
    private static let maxFuzzyDistance = 2

    // MARK: - Cached Index Keys

    private static var nameTokenKeys: [String] = {
        Array(PantryCatalog.tokenIndex.keys)
    }()

    private static var facetSingleTokenKeys: [String] = {
        PantryCatalog.facetTokenToItems.keys.filter { !$0.contains(" ") }.map { $0 }
    }()

    private static var facetMultiTokenKeys: [String] = {
        PantryCatalog.facetTokenToItems.keys.filter { $0.contains(" ") }.map { $0 }
    }()

    static func invalidateCache() {
        nameTokenKeys = Array(PantryCatalog.tokenIndex.keys)
        facetSingleTokenKeys = PantryCatalog.facetTokenToItems.keys
            .filter { !$0.contains(" ") }.map { $0 }
        facetMultiTokenKeys = PantryCatalog.facetTokenToItems.keys
            .filter { $0.contains(" ") }.map { $0 }
    }

    // MARK: - Public API

    static func search(_ query: String) -> [CatalogSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allItemsFallback() }

        let lookupKey = IngredientLexicon.lookupKey(trimmed)
        guard !lookupKey.isEmpty else { return allItemsFallback() }

        let queryTokens = IngredientLexicon.tokenize(lookupKey)

        // Phase 1: Multi-token facet matches (e.g. "filet mignon")
        let (multiTokenFacetMatches, consumedIndices) = matchMultiTokenFacets(lookupKey: lookupKey, queryTokens: queryTokens)

        // Phase 2: Classify each unconsumed token
        let classifications = classifyUnconsumedTokens(queryTokens: queryTokens, consumedIndices: consumedIndices)

        // Phase 3: Accumulate candidates
        var candidates = accumulateCandidates(
            multiTokenMatches: multiTokenFacetMatches,
            classifications: classifications
        )

        // Phase 4: Alias resolution
        resolveAliases(into: &candidates, lookupKey: lookupKey, queryTokens: queryTokens, consumedIndices: consumedIndices)

        // Phase 5: Score and rank
        let totalQueryTokens = classifications.count + (multiTokenFacetMatches.isEmpty ? 0 : 1)
        guard totalQueryTokens > 0 else { return allItemsFallback() }

        return buildResults(from: candidates, totalQueryTokens: totalQueryTokens, lookupKey: lookupKey)
    }

    // MARK: - Collision Candidates

    static func collisionCandidates(
        name: String,
        category: FoodCategory? = nil,
        facets: [PantryFacetKey: [String]] = [:],
        limit: Int = 6
    ) -> [CatalogSearchResult] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return [] }

        let normalizedFacetValues = normalizedCollisionFacetValues(from: facets)
        let lookupQueries = collisionQueries(name: trimmedName, facetValues: normalizedFacetValues)
        var resultsByItemID: [String: CatalogSearchResult] = [:]
        var scoresByItemID: [String: Double] = [:]

        func record(_ result: CatalogSearchResult, bonus: Double) {
            guard !result.item.isUserDefined else { return }
            let itemID = result.item.id
            let candidateScore = result.score + bonus
            guard candidateScore > (scoresByItemID[itemID] ?? -1) else { return }
            scoresByItemID[itemID] = candidateScore
            resultsByItemID[itemID] = result
        }

        if let exactItem = PantryCatalog.resolveExact(name: trimmedName), !exactItem.isUserDefined {
            record(defaultResult(for: exactItem), bonus: 1.4)
        }

        for (index, query) in lookupQueries.enumerated() {
            let queryBonus = index == 0 ? 0.85 : 0.55
            for result in search(query) {
                record(result, bonus: queryBonus)
            }
        }

        let facetTokens = collisionFacetTokens(from: normalizedFacetValues)
        if !facetTokens.isEmpty {
            for itemID in PantryCatalog.itemIDs(matchingFacetTokens: facetTokens) {
                guard let item = PantryCatalog.item(id: itemID), !item.isUserDefined else { continue }
                let overlapBonus = collisionFacetOverlapBonus(item: item, normalizedFacetValues: normalizedFacetValues)
                guard overlapBonus > 0 else { continue }
                record(defaultResult(for: item), bonus: overlapBonus)
            }
        }

        if let category, category != .other {
            for itemID in resultsByItemID.keys {
                guard let item = PantryCatalog.item(id: itemID), item.category == category else { continue }
                scoresByItemID[itemID, default: 0] += 0.15
            }
        }

        return resultsByItemID.values
            .sorted {
                let lhs = scoresByItemID[$0.item.id] ?? 0
                let rhs = scoresByItemID[$1.item.id] ?? 0
                return lhs == rhs ? $0.item.name < $1.item.name : lhs > rhs
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Pipeline Phases

    private typealias FacetEntry = TokenClassifier.FacetEntry
    private typealias MultiTokenMatch = (key: String, entries: [FacetEntry])

    private static func matchMultiTokenFacets(
        lookupKey: String,
        queryTokens: [String]
    ) -> ([MultiTokenMatch], Set<Int>) {
        var consumed: Set<Int> = []
        var matches: [MultiTokenMatch] = []

        guard queryTokens.count >= 2 else { return (matches, consumed) }

        for facetKey in facetMultiTokenKeys {
            guard lookupKey.contains(facetKey),
                  let entries = PantryCatalog.facetTokenToItems[facetKey] else { continue }
            matches.append((key: facetKey, entries: entries))
            let facetTokens = Set(IngredientLexicon.tokenize(facetKey))
            for (i, token) in queryTokens.enumerated() where facetTokens.contains(token) {
                consumed.insert(i)
            }
        }

        return (matches, consumed)
    }

    private static func classifyUnconsumedTokens(
        queryTokens: [String],
        consumedIndices: Set<Int>
    ) -> [TokenClassifier.Match] {
        queryTokens.enumerated()
            .filter { !consumedIndices.contains($0.offset) }
            .map { TokenClassifier.classify(
                $0.element,
                nameKeys: nameTokenKeys,
                facetKeys: facetSingleTokenKeys,
                maxEditDistance: maxFuzzyDistance
            ) }
    }

    private static func accumulateCandidates(
        multiTokenMatches: [MultiTokenMatch],
        classifications: [TokenClassifier.Match]
    ) -> [String: CandidateAccumulator] {
        var candidates: [String: CandidateAccumulator] = [:]

        // Multi-token facet matches
        for match in multiTokenMatches {
            for entry in match.entries {
                candidates[entry.itemID, default: CandidateAccumulator()]
                    .addFacet(key: entry.key, value: entry.value, exact: true)
            }
        }

        // Classified single tokens
        for classification in classifications {
            applyClassification(classification, to: &candidates)
        }

        return candidates
    }

    private static func applyClassification(
        _ match: TokenClassifier.Match,
        to candidates: inout [String: CandidateAccumulator]
    ) {
        switch match {
        case .name(let ids):
            for id in ids { candidates[id, default: CandidateAccumulator()].addNameToken("", exact: true) }

        case .facet(let entries):
            for e in entries { candidates[e.itemID, default: CandidateAccumulator()].addFacet(key: e.key, value: e.value, exact: true) }

        case .nameAndFacet(let ids, let entries):
            for id in ids { candidates[id, default: CandidateAccumulator()].addNameToken("", exact: true) }
            for e in entries { candidates[e.itemID, default: CandidateAccumulator()].addFacet(key: e.key, value: e.value, exact: true) }

        case .fuzzyName(let ids, let corrected):
            for id in ids { candidates[id, default: CandidateAccumulator()].addNameToken(corrected, exact: false) }

        case .fuzzyFacet(let entries, _):
            for e in entries { candidates[e.itemID, default: CandidateAccumulator()].addFacet(key: e.key, value: e.value, exact: false) }

        case .bitapName(let ids, let target):
            for id in ids { candidates[id, default: CandidateAccumulator()].addNameToken(target, exact: false) }

        case .bitapFacet(let entries, _):
            for e in entries { candidates[e.itemID, default: CandidateAccumulator()].addFacet(key: e.key, value: e.value, exact: false) }

        case .prefixName(let ids):
            for id in ids { candidates[id, default: CandidateAccumulator()].addNameToken("", exact: false) }

        case .prefixFacet(let entries):
            for e in entries { candidates[e.itemID, default: CandidateAccumulator()].addFacet(key: e.key, value: e.value, exact: false) }

        case .unmatched:
            break
        }
    }

    private static func resolveAliases(
        into candidates: inout [String: CandidateAccumulator],
        lookupKey: String,
        queryTokens: [String],
        consumedIndices: Set<Int>
    ) {
        guard let aliasItemID = PantryCatalog.resolveAlias(lookupKey),
              let item = PantryCatalog.item(id: aliasItemID) else { return }

        var acc = candidates[aliasItemID] ?? CandidateAccumulator()
        acc.aliasMatch = true

        for f in IngredientLexicon.inferredFacets(forLookupKey: lookupKey, item: item) {
            acc.addFacet(key: f.key, value: f.value, exact: true)
        }
        for token in queryTokens where !consumedIndices.contains(queryTokens.firstIndex(of: token) ?? -1) {
            acc.addNameToken(token, exact: true)
        }

        candidates[aliasItemID] = acc
    }

    private static func buildResults(
        from candidates: [String: CandidateAccumulator],
        totalQueryTokens: Int,
        lookupKey: String
    ) -> [CatalogSearchResult] {
        var results: [CatalogSearchResult] = []

        for (itemID, acc) in candidates {
            guard let item = PantryCatalog.item(id: itemID) else { continue }
            guard let scored = CandidateScorer.score(
                item: item,
                accumulator: acc,
                totalQueryTokens: totalQueryTokens,
                lookupKey: lookupKey
            ) else { continue }

            let resultID = scored.facets.isEmpty
                ? item.id
                : "\(item.id):\(scored.facets.map(\.id).joined(separator: ","))"

            results.append(CatalogSearchResult(
                id: resultID,
                catalogItemID: item.id,
                facets: scored.facets,
                displayName: item.displayName(for: scored.facets),
                score: scored.score,
                item: item
            ))
        }

        results.sort { $0.score > $1.score }
        return Array(results.prefix(maxResults))
    }

    // MARK: - Fallback & Helpers

    private static func allItemsFallback() -> [CatalogSearchResult] {
        PantryCatalog.allItems
            .sorted { $0.name < $1.name }
            .prefix(maxResults)
            .map { defaultResult(for: $0) }
    }

    static func defaultResult(for item: PantryCatalogItemDefinition) -> CatalogSearchResult {
        CatalogSearchResult(
            id: item.id,
            catalogItemID: item.id,
            facets: [],
            displayName: item.titleCasedName,
            score: 0,
            item: item
        )
    }

    // MARK: - Collision Helpers

    private static func normalizedCollisionFacetValues(from facets: [PantryFacetKey: [String]]) -> [String] {
        var seen: Set<String> = []
        var values: [String] = []
        for facetValues in facets.values {
            for value in facetValues {
                let normalized = PantryCatalog.normalizeLookupKey(value)
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                values.append(normalized)
            }
        }
        return values
    }

    private static func collisionQueries(name: String, facetValues: [String]) -> [String] {
        var seen: Set<String> = []
        var queries: [String] = []

        func append(_ query: String) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let normalized = PantryCatalog.normalizeLookupKey(trimmed)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return }
            queries.append(trimmed)
        }

        append(name)
        let topFacetValues = Array(facetValues.prefix(3))
        for value in topFacetValues { append("\(name) \(value)") }
        if !topFacetValues.isEmpty {
            append(([name] + topFacetValues).joined(separator: " "))
        }

        return queries
    }

    private static func collisionFacetTokens(from normalizedFacetValues: [String]) -> Set<String> {
        var tokens = Set(normalizedFacetValues)
        for value in normalizedFacetValues {
            tokens.formUnion(IngredientLexicon.tokenize(value))
        }
        return tokens
    }

    private static func collisionFacetOverlapBonus(
        item: PantryCatalogItemDefinition,
        normalizedFacetValues: [String]
    ) -> Double {
        guard !normalizedFacetValues.isEmpty else { return 0 }
        let itemKeys = collisionComparisonKeys(for: item)
        let overlapCount = normalizedFacetValues.filter { itemKeys.contains($0) }.count
        guard overlapCount > 0 else { return 0 }
        return 0.45 + (Double(overlapCount - 1) * 0.12)
    }

    private static func collisionComparisonKeys(for item: PantryCatalogItemDefinition) -> Set<String> {
        var keys: Set<String> = [PantryCatalog.normalizeLookupKey(item.name)]
        for alias in item.aliases {
            let n = PantryCatalog.normalizeLookupKey(alias)
            if !n.isEmpty { keys.insert(n) }
        }
        for facet in item.facets {
            for option in facet.options {
                let n = PantryCatalog.normalizeLookupKey(option)
                if !n.isEmpty { keys.insert(n) }
            }
        }
        return keys
    }
}
