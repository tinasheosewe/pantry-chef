import Foundation

enum IngredientLexicon {
    struct ParsedText: Hashable, Sendable {
        let raw: String
        let lookupKey: String
        let normalized: String
        let tokens: [String]

        var tokenSet: Set<String> {
            Set(tokens)
        }
    }

    static func parse(_ value: String) -> ParsedText {
        let lookup = lookupKey(value)
        let normalized = normalizeIngredient(value)
        return ParsedText(
            raw: value,
            lookupKey: lookup,
            normalized: normalized,
            tokens: tokenize(normalized)
        )
    }

    static func lookupKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func normalizeIngredient(_ name: String) -> String {
        let base = lookupKey(name)
        var stripped = base

        // Remove multi-word strip phrases first (few entries)
        for phrase in stripMultiWordPhrases {
            stripped = stripped.replacingOccurrences(of: phrase, with: " ")
        }

        // Singularize each token *before* stripping so plural and singular modifier
        // forms are removed consistently ("flours" and "flour" both → "flour").
        let kept = stripped
            .split(separator: " ")
            .map { depluralize(String($0)) }
            .filter { !stripWordSet.contains($0) }
        if !kept.isEmpty {
            return kept.joined(separator: " ")
        }

        // Everything was a modifier/facet word (e.g. the ingredient is literally
        // "flour" or "olive oil"). Never collapse a real ingredient to empty — fall
        // back to its singularized full name.
        return base.split(separator: " ").map { depluralize(String($0)) }.joined(separator: " ")
    }

    /// Best-effort English singular form. Guards the endings that are *not* plural
    /// markers — Latin `-us`/`-is` (couscous, hummus, octopus, asparagus) and `-ss`
    /// mass nouns (molasses, watercress) — so they are never truncated, and drops
    /// only a trailing `s` for regular plurals so `apples`→`apple`, `olives`→`olive`
    /// rather than `appl`/`oliv`.
    static func depluralize(_ word: String) -> String {
        guard word.count > 2 else { return word }
        if word.hasSuffix("us") || word.hasSuffix("is")
            || word.hasSuffix("ss") || word.hasSuffix("sses") {
            return word
        }
        if word.hasSuffix("ies"), word.count > 4 {
            return String(word.dropLast(3)) + "y"          // berries -> berry
        }
        if word.hasSuffix("ches") || word.hasSuffix("shes")
            || word.hasSuffix("xes") || word.hasSuffix("zes") || word.hasSuffix("oes") {
            return String(word.dropLast(2))                // peaches->peach, boxes->box, tomatoes->tomato
        }
        if word.hasSuffix("s") {
            return String(word.dropLast())                 // apples->apple, beans->bean
        }
        return word
    }

    static func tokenize(_ value: String) -> [String] {
        value.split(separator: " ").map(String.init)
    }

    static func synonymLookupGroup(for value: String) -> Set<String> {
        lookupSynonymIndex[lookupKey(value)] ?? []
    }

    static func synonymGroup(forNormalizedIngredient normalized: String) -> Set<String> {
        normalizedSynonymIndex[normalized] ?? []
    }

    static func tokenSubsetMatch(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        let overlap = lhs.intersection(rhs)
        let shorter = lhs.count <= rhs.count ? lhs : rhs
        return !shorter.isEmpty && overlap == shorter
    }

    static func weightedTokenScore(queryTokens: [String], candidateTokens: [String]) -> Double {
        guard !queryTokens.isEmpty, !candidateTokens.isEmpty else { return 0 }

        let candidateTokenSet = Set(candidateTokens)
        var matchedWeight = 0.0
        var totalWeight = 0.0

        for (index, token) in queryTokens.enumerated() {
            let isHeadToken = index == queryTokens.count - 1
            let weight = isHeadToken ? 1.35 : 1.0
            totalWeight += weight
            if candidateTokenSet.contains(token) {
                matchedWeight += weight
            }
        }

        let queryCoverage = matchedWeight / max(totalWeight, 0.0001)
        let overlapCount = Set(queryTokens).intersection(candidateTokenSet).count
        let candidateCoverage = Double(overlapCount) / Double(max(candidateTokenSet.count, 1))
        let headBoost = candidateTokenSet.contains(queryTokens.last ?? "") ? 0.08 : 0

        return min(1, queryCoverage * 0.72 + candidateCoverage * 0.28 + headBoost)
    }

    static func fuzzySimilarity(_ lhs: String, _ rhs: String) -> Double {
        let distance = levenshteinDistance(lhs, rhs)
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else { return 1 }
        return 1 - Double(distance) / Double(maxLength)
    }

    static func inferredFacets(forLookupKey lookup: String, item: PantryCatalogItemDefinition) -> [PantryFacetSelection] {
        item.facets.compactMap { definition in
            guard let option = definition.options.first(where: { option in
                let optionKey = lookupKey(option)
                return !optionKey.isEmpty && lookup.contains(optionKey)
            }) else {
                return nil
            }

            return PantryFacetSelection(key: definition.key, value: option)
        }
    }

    static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let lhsCount = lhsChars.count
        let rhsCount = rhsChars.count

        if lhsCount == 0 { return rhsCount }
        if rhsCount == 0 { return lhsCount }

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

    // MARK: - Catalog-Derived Data

    /// Strip vocabulary derived entirely from the catalog's facet option values: a
    /// word is a "modifier" to be removed during normalization iff the catalog uses
    /// it as a facet value somewhere. No hardcoded list — it grows with the data.
    private static let allStripKeys: [String] = {
        var words: Set<String> = []
        for item in PantryCatalog.allItems {
            for facet in item.facets {
                for option in facet.options {
                    words.insert(option.lowercased())
                }
            }
        }
        return words.map(lookupKey)
    }()

    private static let stripWordSet: Set<String> = {
        Set(allStripKeys.filter { !$0.contains(" ") })
    }()

    private static let stripMultiWordPhrases: [String] = {
        // Sort longest first so longer phrases are removed before shorter subphrases
        allStripKeys.filter { $0.contains(" ") }.sorted { $0.count > $1.count }
    }()

    /// Synonym groups, derived entirely from catalog data: each item's name plus its
    /// aliases form one group. Cross-regional synonyms are migrated into those aliases
    /// by the catalog pipeline, so there is no hardcoded synonym list to drift.
    private static let rawSynonymGroups: [[String]] = {
        PantryCatalog.allItems
            .filter { !$0.aliases.isEmpty }
            .map { [$0.name] + $0.aliases }
    }()

    private static let lookupSynonymIndex: [String: Set<String>] = {
        var index: [String: Set<String>] = [:]

        for group in rawSynonymGroups {
            let normalizedGroup = Set(group.map(lookupKey))
            for name in normalizedGroup {
                index[name] = normalizedGroup
            }
        }

        return index
    }()

    private static let normalizedSynonymIndex: [String: Set<String>] = {
        var index: [String: Set<String>] = [:]

        for group in rawSynonymGroups {
            let normalizedGroup = Set(group.map(normalizeIngredient))
            for name in normalizedGroup {
                index[name] = normalizedGroup
            }
        }

        return index
    }()
}