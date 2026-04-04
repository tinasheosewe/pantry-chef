import Foundation

// MARK: - Weighted Field

/// Describes one searchable field on an item with a relevance weight.
/// Higher weight means matches in this field score more strongly.
struct WeightedField<Item> {
    let weight: Double
    let text: (Item) -> String
}

// MARK: - Ranked Text Search Engine

/// A generic ranked search engine that applies the same 4-strategy classification chain
/// as `CatalogSearchEngine` (exact → Levenshtein → Bitap → prefix) against a set of
/// weighted text fields on arbitrary item types.
///
/// Build the engine once for a given item set, then call `search(_:)` repeatedly.
/// Rebuild when the item set changes.
struct RankedTextSearchEngine<Item> {

    // MARK: - Private Types

    private struct ItemFieldKey: Hashable {
        let itemIdx: Int
        let fieldIdx: Int
    }

    // MARK: - Storage

    private let items: [Item]
    private let fields: [WeightedField<Item>]
    /// Inverted index: lowercased token → [(itemIdx, fieldIdx)].
    private let index: [String: [(itemIdx: Int, fieldIdx: Int)]]
    /// All indexed tokens sorted — used for fuzzy/prefix scanning.
    private let indexedTokens: [String]
    /// Index of the highest-weight field — used for the starts-with bonus.
    private let primaryFieldIdx: Int

    // MARK: - Init

    init(items: [Item], fields: [WeightedField<Item>]) {
        self.items = items
        self.fields = fields

        var idx: [String: [(Int, Int)]] = [:]
        for (fieldIdx, field) in fields.enumerated() {
            for (itemIdx, item) in items.enumerated() {
                for token in Self.tokenize(field.text(item)) {
                    idx[token, default: []].append((itemIdx, fieldIdx))
                }
            }
        }
        self.index = idx
        self.indexedTokens = Array(idx.keys).sorted()
        self.primaryFieldIdx = fields.indices.max(by: { fields[$0].weight < fields[$1].weight }) ?? 0
    }

    // MARK: - Search

    /// Returns items matching `query`, ranked by relevance score (highest first).
    /// Only items with score > 0 are returned. When `query` is empty, returns all
    /// items in original order with score 0.
    func search(_ query: String) -> [(item: Item, score: Double)] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items.map { ($0, 0.0) } }

        let queryTokens = Self.tokenize(trimmed)
        guard !queryTokens.isEmpty else { return items.map { ($0, 0.0) } }

        let totalFieldWeight = fields.reduce(0.0) { $0 + $1.weight }
        let maxRawScore = totalFieldWeight * Double(queryTokens.count)
        guard maxRawScore > 0 else { return [] }

        var scores = [Double](repeating: 0.0, count: items.count)

        for queryToken in queryTokens {
            let classified = classifyToken(queryToken)

            // Deduplicate contributions per (itemIdx, fieldIdx) — keep highest multiplier.
            // This prevents inflating scores when multiple indexed tokens match the same
            // query token for the same item (e.g. "chi" prefix-matching both "chicken" and
            // "chickpeas" in the title field).
            var bestContributions: [ItemFieldKey: Double] = [:]
            for (indexedToken, mult) in classified {
                if let hits = index[indexedToken] {
                    for (itemIdx, fieldIdx) in hits {
                        let key = ItemFieldKey(itemIdx: itemIdx, fieldIdx: fieldIdx)
                        bestContributions[key] = max(bestContributions[key] ?? 0.0, mult)
                    }
                }
            }

            for (key, mult) in bestContributions {
                scores[key.itemIdx] += fields[key.fieldIdx].weight * mult
            }
        }

        // Starts-with bonus: +15% of total field weight when the primary field's text
        // starts with the full query, rewarding tight matches like typing a title prefix.
        let queryLowered = trimmed.lowercased()
        for itemIdx in items.indices where scores[itemIdx] > 0 {
            let text = fields[primaryFieldIdx].text(items[itemIdx]).lowercased()
            if text.hasPrefix(queryLowered) {
                scores[itemIdx] += totalFieldWeight * 0.15
            }
        }

        return zip(items.indices, items)
            .compactMap { (idx, item) -> (Item, Double)? in
                guard scores[idx] > 0 else { return nil }
                return (item, min(scores[idx] / maxRawScore, 1.0))
            }
            .sorted { $0.1 > $1.1 }
    }

    // MARK: - Token Classification

    /// Classifies a query token using the same 4-strategy chain as `CatalogSearchEngine`:
    /// exact → Levenshtein (≥3 chars) → Bitap (≥3 chars) → prefix.
    ///
    /// Returns `[(indexedToken, contributionMultiplier)]` — one or more indexed tokens
    /// that should be credited for this query token, with their multipliers.
    private func classifyToken(_ token: String) -> [(String, Double)] {
        // 1. Exact match → full contribution (1.0×)
        if index[token] != nil {
            return [(token, 1.0)]
        }

        if token.count >= 3 {
            // 2. Levenshtein fuzzy (edit distance ≤ 2 — handles typos like "chiken" → "chicken").
            // Skipped for tokens < 3 chars because edit-distance on very short strings matches
            // almost anything, preventing the prefix strategy from running.
            var levBestToken: String?
            var levBestDist = 3 // threshold is 2; initialise above threshold
            for indexed in indexedTokens {
                let d = IngredientLexicon.levenshteinDistance(token, indexed)
                if d < levBestDist {
                    levBestDist = d
                    levBestToken = indexed
                }
            }
            if let matched = levBestToken {
                return [(matched, 0.5)]
            }

            // 3. Bitap approximate substring — catches typo-inside-longer-token,
            // e.g. "chese" matching inside "cheesecloth".
            if let pattern = BitapSearcher.createPattern(from: token) {
                var bitapBestToken: String?
                var bitapBestScore = 1.0
                for indexed in indexedTokens {
                    if let m = BitapSearcher.search(pattern, in: indexed, threshold: 0.4),
                       m.score < bitapBestScore {
                        bitapBestScore = m.score
                        bitapBestToken = indexed
                    }
                }
                if let matched = bitapBestToken {
                    return [(matched, 0.5)]
                }
            }
        }

        // 4. Prefix match (0.8×) — handles partial input like "app" → "apple", "apricot".
        let prefixMatches = indexedTokens.filter { $0.hasPrefix(token) && $0 != token }
        return prefixMatches.map { ($0, 0.8) }
    }

    // MARK: - Tokenization

    static func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
