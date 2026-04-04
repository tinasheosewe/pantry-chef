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

    /// Resolves a single query token against this engine's index.
    /// Delegates to `matchToken` for the fuzzy+prefix strategies; exact is
    /// handled inline via the O(1) index dictionary.
    private func classifyToken(_ token: String) -> [(String, Double)] {
        if index[token] != nil { return [(token, 1.0)] }
        return matchToken(token, in: indexedTokens)
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

// MARK: - Shared Token-Matching Core

/// The single implementation of the 4-strategy token scan used by both
/// `RankedTextSearchEngine` (generic) and `TokenClassifier` (catalog search).
///
/// Strategies applied in priority order (exact must be done by the caller first):
///   1. Levenshtein fuzzy (edit distance ≤ `maxEditDistance`) — best hit, 0.5×
///   2. Bitap approximate substring — best hit, 0.5×
///   3. Prefix — all matching keys, 0.8× each
///
/// **To improve the matching algorithm, edit this function only.**
/// Both engines automatically benefit.
func matchToken(
    _ token: String,
    in keys: [String],
    maxEditDistance: Int = 2
) -> [(token: String, multiplier: Double)] {
    guard !keys.isEmpty else { return [] }

    if token.count >= 3 {
        // Levenshtein — tolerates typos like "chiken" → "chicken"
        var bestDist = maxEditDistance + 1
        var bestKey: String?
        for key in keys {
            let d = IngredientLexicon.levenshteinDistance(token, key)
            if d < bestDist { bestDist = d; bestKey = key }
        }
        if let key = bestKey { return [(key, 0.5)] }

        // Bitap approximate substring — catches typo inside a longer token,
        // e.g. "chese" matching "cheesecloth"
        if let pattern = BitapSearcher.createPattern(from: token) {
            var bestScore = 1.0
            var bitapKey: String?
            for key in keys {
                if let m = BitapSearcher.search(pattern, in: key, threshold: 0.4),
                   m.score < bestScore { bestScore = m.score; bitapKey = key }
            }
            if let key = bitapKey { return [(key, 0.5)] }
        }
    }

    // Prefix — handles partial input like "app" → "apple", "apricot"
    return keys.filter { $0.hasPrefix(token) && $0 != token }.map { ($0, 0.8) }
}
