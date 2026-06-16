import Foundation

/// One requirement of a dish — an ingredient it needs, already resolved to a
/// lexicon key so matching against the pantry is structural, not fuzzy.
struct IngredientRequirement: Equatable, Sendable {
    let key: String
    let displayName: String
    /// Staples (flour, oil, salt) are assumed present unless explicitly flagged out
    /// (spec §7 resolution classes) — they never make a dish "unmakeable".
    let isStaple: Bool
    /// The catalog item this requirement *is*, when known — matched directly, no
    /// fuzzy name mapping. Nil falls back to name matching.
    let catalogItemID: String?

    init(key: String, displayName: String, isStaple: Bool, catalogItemID: String? = nil) {
        self.key = key; self.displayName = displayName
        self.isStaple = isStaple; self.catalogItemID = catalogItemID
    }
}

/// A concrete substitution that would let a dish be made tonight: swap the missing
/// `from` ingredient for the `to` ingredient already on hand.
struct SwapOption: Equatable, Sendable {
    let fromName: String
    let toName: String
}

/// One place to phrase a swap count, so every surface speaks the same way.
enum SwapPhrase {
    static func count(_ n: Int) -> String { n == 1 ? "1 swap" : "\(n) swaps" }
}

/// Whether a dish can be made from what's on hand (spec §6 readiness vocabulary).
/// The single shape every surface speaks — Library, Explore, the fan, conflicts.
enum Readiness: Equatable, Sendable {
    /// Everything needed is on hand.
    case ready
    /// Makeable tonight, but one or more ingredients via a substitution.
    case readyWithSwaps([SwapOption])
    /// Not yet — these (display names) are missing with no swap.
    case needs(items: [String])

    var missingCount: Int {
        if case .needs(let items) = self { return items.count }
        return 0
    }
    var isMakeableNow: Bool {
        switch self {
        case .ready, .readyWithSwaps: return true
        case .needs: return false
        }
    }
}

/// What the pantry currently holds, abstracted so the readiness logic stays pure
/// and testable. Real implementations read the stock + confidence layer; tests and
/// previews supply doubles.
protocol PantryPresence {
    /// True when the ingredient is on hand with enough confidence to rely on —
    /// matched by catalog id when one is given, else by name key.
    func hasOnHand(key: String, catalogItemID: String?) -> Bool
    /// True when a staple has been explicitly flagged low/out, overriding the
    /// "assume staples present" rule.
    func isKnownOut(key: String, catalogItemID: String?) -> Bool
}

/// A candidate substitute for a missing ingredient — carries the catalog identity
/// so presence is checked by id, not name.
struct SwapTarget: Equatable, Sendable {
    let key: String
    let name: String
    let catalogItemID: String?
}

/// Resolves substitution targets for a missing ingredient, in priority order
/// (the catalog `swaps` enrichment). Pure lookup.
protocol SwapResolver {
    func swapTargets(for requirement: IngredientRequirement) -> [SwapTarget]
}

/// The sole computer of dish readiness. Pure: it never reaches for global state, so
/// the same inputs always give the same answer and it is trivially unit-tested.
/// Every surface that shows "ready / ready-with-swap / needs N" asks this — none
/// re-derive it (spec §15, one source of truth).
struct ReadinessService {
    let presence: PantryPresence
    let swaps: SwapResolver

    func evaluate(_ requirements: [IngredientRequirement]) -> Readiness {
        var missing: [String] = []
        var usedSwaps: [SwapOption] = []

        for req in requirements {
            if presence.hasOnHand(key: req.key, catalogItemID: req.catalogItemID) { continue }
            if req.isStaple && !presence.isKnownOut(key: req.key, catalogItemID: req.catalogItemID) { continue }

            if let target = swaps.swapTargets(for: req)
                .first(where: { presence.hasOnHand(key: $0.key, catalogItemID: $0.catalogItemID) }) {
                usedSwaps.append(SwapOption(fromName: req.displayName, toName: target.name))
            } else {
                missing.append(req.displayName)
            }
        }

        if !missing.isEmpty { return .needs(items: missing) }
        // A dish that leans on too many substitutes isn't really that dish. Past the
        // cap (~a third of its non-staple ingredients), stop calling it makeable and
        // surface the swapped-out ingredients as what it needs.
        if usedSwaps.count > Self.swapCap(forNonStaple: requirements.lazy.filter { !$0.isStaple }.count) {
            return .needs(items: usedSwaps.map(\.fromName))
        }
        if !usedSwaps.isEmpty { return .readyWithSwaps(usedSwaps) }
        return .ready
    }

    /// At most ~a third of a dish's non-staple ingredients may be substituted before
    /// it stops counting as makeable (always allowing at least one).
    static func swapCap(forNonStaple count: Int) -> Int { max(1, count / 3) }
}
