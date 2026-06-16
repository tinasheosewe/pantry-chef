import Foundation

/// One ranked catalog candidate for an ambiguous ingredient.
struct IntakeCandidate: Identifiable, Equatable, Sendable {
    let id: String       // catalog item id
    let name: String     // display name
    let score: Double
}

/// What to do with a parsed ingredient phrase.
enum IntakeDecision: Equatable, Sendable {
    /// We're sure — accept the parse silently (no prompt).
    case confident
    /// Not sure — offer these ranked candidates plus a "Custom" option; the user picks.
    case ambiguous([IntakeCandidate])
    /// No real catalog match — go straight to custom creation (prefilled).
    case custom
}

/// The single entrypoint for turning typed/spoken ingredient text into a first-class
/// ingredient. It never silently force-matches a weak guess (the "nonsense → egg"
/// class of bug): a confident exact/near-exact match is accepted with zero friction,
/// anything uncertain surfaces candidates + Custom, and genuine unknowns become a
/// validated custom ingredient. Composer, shop-add, and recipe-import all resolve
/// through here so the behavior can't diverge (consolidation: one intake path).
enum IntakePipeline {
    /// A confident match needs this score and a clear lead over the runner-up.
    static let autoAcceptScore = 0.82
    static let leadGap = 0.12
    /// Below this, a candidate isn't even worth offering.
    static let ambiguousFloor = 0.55
    static let maxCandidates = 5

    /// Ranked candidates for an ingredient name — the one retrieval path.
    static func candidates(for name: String) -> [IntakeCandidate] {
        CatalogSearchEngine.search(name).prefix(8).map {
            IntakeCandidate(id: $0.catalogItemID, name: $0.displayName, score: $0.score)
        }
    }

    /// The single best catalog id for an ingredient name, so a line can carry its
    /// catalog identity. Cheap exact alias lookup first; the search engine's top
    /// hit only as a fallback (covers names the alias index misses, like "spinach").
    /// Returns nil only when nothing in the catalog matches at all.
    static func bestCatalogID(for name: String, resolvedItemID: String? = nil) -> String? {
        if let resolvedItemID { return resolvedItemID }
        if let exact = PantryCatalog.resolveExact(name: name)?.id { return exact }
        return candidates(for: name).first?.id
    }

    /// Classify a parsed intake against its candidates.
    static func decide(_ intake: ParsedIntake, candidates: [IntakeCandidate]) -> IntakeDecision {
        if intake.confidence == .resolved { return .confident }
        if let top = candidates.first, top.score >= autoAcceptScore,
           candidates.count < 2 || (top.score - candidates[1].score) >= leadGap {
            return .confident
        }
        let viable = candidates.filter { $0.score >= ambiguousFloor }
        if viable.isEmpty { return .custom }
        return .ambiguous(Array(viable.prefix(maxCandidates)))
    }

    /// Parse + decide in one call (production path).
    static func resolve(_ phrase: String, using parse: (String) -> ParsedIntake) -> (intake: ParsedIntake, decision: IntakeDecision) {
        let intake = parse(phrase)
        let name = intake.suggestedName ?? intake.name
        return (intake, decide(intake, candidates: candidates(for: name)))
    }
}
