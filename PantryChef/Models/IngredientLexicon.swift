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

    enum CatalogPhraseSource: String, Hashable, Sendable {
        case name
        case alias
        case template
    }

    struct CatalogPhrase: Hashable, Sendable {
        let text: String
        let lookupKey: String
        let normalized: String
        let tokens: [String]
        let itemID: String
        let facets: [PantryFacetSelection]
        let source: CatalogPhraseSource
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
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func normalizeIngredient(_ name: String) -> String {
        var normalized = lookupKey(name)

        for regex in stripRegexes {
            normalized = regex.stringByReplacingMatches(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized),
                withTemplate: ""
            )
        }

        normalized = normalized
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if normalized.hasSuffix("ies") {
            normalized = String(normalized.dropLast(3)) + "y"
        } else if normalized.hasSuffix("oes") {
            normalized = String(normalized.dropLast(2))
        } else if normalized.hasSuffix("es") && !normalized.hasSuffix("ses") {
            normalized = String(normalized.dropLast(2))
        } else if normalized.hasSuffix("s") && !normalized.hasSuffix("ss") {
            normalized = String(normalized.dropLast())
        }

        return normalized
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

    static func generatedCatalogPhrases(for item: PantryCatalogItemDefinition) -> [CatalogPhrase] {
        var phrases: [CatalogPhrase] = []
        var seenKeys: Set<String> = []

        func register(_ text: String, source: CatalogPhraseSource, explicitFacets: [PantryFacetSelection]? = nil) {
            let lookup = lookupKey(text)
            guard !lookup.isEmpty else { return }

            let facets = explicitFacets ?? inferredFacets(forLookupKey: lookup, item: item)
            let facetKey = facets
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue)=\($0.value)" }
                .joined(separator: "|")
            let dedupeKey = [item.id, source.rawValue, facetKey, lookup].joined(separator: "::")
            guard seenKeys.insert(dedupeKey).inserted else { return }

            let normalized = normalizeIngredient(text)
            phrases.append(
                CatalogPhrase(
                    text: text,
                    lookupKey: lookup,
                    normalized: normalized,
                    tokens: tokenize(normalized),
                    itemID: item.id,
                    facets: facets,
                    source: source
                )
            )
        }

        register(item.name, source: .name)
        item.aliases.forEach { register($0, source: .alias) }

        if !item.defaultSelections.isEmpty {
            register(item.displayName(for: item.defaultSelections), source: .template, explicitFacets: item.defaultSelections)
        }

        for definition in item.facets {
            for option in definition.options {
                let selection = PantryFacetSelection(key: definition.key, value: option)
                register(item.displayName(for: [selection]), source: .template, explicitFacets: [selection])

                for alias in item.aliases where !lookupKey(alias).contains(lookupKey(option)) {
                    register("\(option) \(alias)", source: .template, explicitFacets: [selection])
                }
            }
        }

        return phrases
    }

    private static func inferredFacets(forLookupKey lookup: String, item: PantryCatalogItemDefinition) -> [PantryFacetSelection] {
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

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
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

    /// Strip words combining universal modifiers with catalog facet options.
    /// Universal modifiers are defined in PantryCatalog.universalModifiers.
    /// Facet options are derived from all catalog items.
    private static let stripWords: [String] = {
        var words = PantryCatalog.universalModifiers
        for item in PantryCatalog.allItems {
            for facet in item.facets {
                for option in facet.options {
                    words.insert(option.lowercased())
                }
            }
        }
        return Array(words)
    }()

    private static let stripRegexes: [NSRegularExpression] = {
        stripWords.compactMap { word in
            try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: lookupKey(word)))\\b",
                options: [.caseInsensitive]
            )
        }
    }()

    /// Synonym groups combining universal synonyms with catalog item aliases.
    /// Universal synonyms are defined in PantryCatalog.universalSynonyms.
    /// Item aliases create additional synonym groups per catalog item.
    private static let rawSynonymGroups: [[String]] = {
        var groups = PantryCatalog.universalSynonyms
        for item in PantryCatalog.allItems {
            guard !item.aliases.isEmpty else { continue }
            groups.append([item.name] + item.aliases)
        }
        return groups
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