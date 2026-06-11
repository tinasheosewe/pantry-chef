import Foundation

/// How confidently a typed phrase's ingredient was identified (spec §13 chip states).
enum NameConfidence: Equatable, Sendable {
    case resolved    // matched a catalog item exactly
    case guessed     // fuzzy-matched — offer a one-tap correction
    case unresolved  // unknown — saved anyway as a custom item, enriched later
}

/// The structured result of parsing one composer phrase.
struct ParsedIntake: Equatable, Sendable {
    var quantity: Double?
    var unit: MeasurementUnit?
    /// A token sitting in the unit slot that isn't a known unit ("1 jgirjgr of …").
    var unrecognizedUnit: String?
    /// The ingredient phrase as the user wrote it.
    var name: String
    /// A catalog display name to offer when the match was fuzzy.
    var suggestedName: String?
    var storage: PantryStorage?
    var resolvedItemID: String?
    var confidence: NameConfidence
}

/// Parses a single composer phrase ("300 g baby spinach, fridge") into structured
/// stock intent, on-device and **without regex** (spec §13). Tokens are scanned by
/// character class; each slot is filled from a closed, owned vocabulary — quantities
/// identify themselves, units come from the existing `MeasurementUnit` lexicon,
/// storage from a small word set, and whatever's left is the ingredient name, which
/// the injected catalog resolvers identify. Known tokens anchor their slots, so an
/// unknown token *inherits the slot left over* — that's how a gibberish unit is
/// recognised as a unit and questioned, while never blocking the entry.
///
/// Resolvers are injected so the slot logic is unit-testable with no catalog, and
/// reuses the real search engine in production (one matcher, never a second).
struct IntakeParser {
    var resolveExact: (String) -> (id: String, storage: PantryStorage)? = {
        guard let item = PantryCatalog.resolveExact(name: $0) else { return nil }
        return (item.id, item.defaultStorage)
    }
    var bestMatch: (String) -> (id: String, name: String, storage: PantryStorage, score: Double)? = {
        guard let hit = CatalogSearchEngine.search($0).first else { return nil }
        return (hit.item.id, hit.displayName, hit.item.defaultStorage, hit.score)
    }
    var guessThreshold = 0.5

    func parse(_ raw: String) -> ParsedIntake {
        let tokens = Self.tokenize(raw)
        var quantity: Double?
        var unit: MeasurementUnit?
        var unrecognizedUnit: String?
        var storage: PantryStorage?
        var nameTokens: [String] = []

        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            let lower = token.lowercased()

            if let s = Self.storageWords[lower] { storage = s; i += 1; continue }

            // Leading quantity (only before any name has started).
            if quantity == nil, nameTokens.isEmpty, let q = Self.quantity(lower) {
                quantity = q; i += 1; continue
            }

            if Self.fillers.contains(lower) { i += 1; continue }

            // Unit slot: directly after a quantity, before the name.
            if quantity != nil, unit == nil, unrecognizedUnit == nil, nameTokens.isEmpty {
                if let u = MeasurementUnit.parse(lower) ?? Self.containerUnits[lower] {
                    unit = u; i += 1; continue
                }
                // An unknown token here, followed by "of", can only be a unit.
                let nextIsOf = i + 1 < tokens.count && tokens[i + 1].lowercased() == "of"
                if nextIsOf { unrecognizedUnit = token; i += 1; continue }
            }

            nameTokens.append(token)
            i += 1
        }

        let name = nameTokens.joined(separator: " ")
        var resolvedID: String?
        var suggestedName: String?
        var confidence: NameConfidence = .unresolved

        if !name.isEmpty {
            if let exact = resolveExact(name) {
                resolvedID = exact.id
                confidence = .resolved
                storage = storage ?? exact.storage
            } else if let hit = bestMatch(name), hit.score >= guessThreshold {
                resolvedID = hit.id
                suggestedName = hit.name
                confidence = .guessed
                storage = storage ?? hit.storage
            }
        }

        return ParsedIntake(quantity: quantity, unit: unit, unrecognizedUnit: unrecognizedUnit,
                            name: name, suggestedName: suggestedName, storage: storage,
                            resolvedItemID: resolvedID, confidence: confidence)
    }

    // MARK: - Tokenizer (character-class, no regex)

    static func tokenize(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
            .map { $0.trimmingCharacters(in: Self.trimChars) }
            .filter { !$0.isEmpty }
    }

    private static let trimChars = CharacterSet(charactersIn: ".;:!?\u{2019}'\"")

    // MARK: - Vocabularies (closed, owned data)

    /// A quantity if the token reads as one: a number, a fraction, a number word,
    /// or an article ("a"/"an" → 1).
    static func quantity(_ token: String) -> Double? {
        if let d = Double(token) { return d }
        if token.contains("/") {
            let parts = token.split(separator: "/")
            if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 {
                return n / d
            }
        }
        if let word = numberWords[token] { return word }
        if token == "a" || token == "an" { return 1 }
        return nil
    }

    static let numberWords: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "dozen": 12, "couple": 2, "few": 3, "several": 4,
        "half": 0.5, "quarter": 0.25, "third": 1.0 / 3.0
    ]

    static let storageWords: [String: PantryStorage] = [
        "fridge": .refrigerated, "refrigerator": .refrigerated, "refrigerated": .refrigerated,
        "chilled": .refrigerated, "freezer": .frozen, "frozen": .frozen,
        "pantry": .pantry, "cupboard": .pantry, "shelf": .pantry, "counter": .pantry
    ]

    static let fillers: Set<String> = ["of", "a", "an", "the", "some"]

    /// Everyday container/count words the canonical `MeasurementUnit` lexicon lacks,
    /// mapped to the nearest canonical unit so common phrasing isn't flagged.
    static let containerUnits: [String: MeasurementUnit] = [
        "bag": .package, "bags": .package, "box": .package, "boxes": .package,
        "carton": .package, "tub": .package, "packet": .package, "pack": .package,
        "jar": .can, "jars": .can, "bottle": .can, "bottles": .can, "tin": .can, "tins": .can,
        "head": .whole, "heads": .whole, "stick": .piece, "sticks": .piece,
        "fillet": .piece, "fillets": .piece, "slices": .slice, "cloves": .clove,
        "bunches": .bunch, "cans": .can, "pieces": .piece, "loaves": .loaf
    ]
}
