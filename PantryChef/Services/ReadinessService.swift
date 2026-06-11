import Foundation

/// One requirement of a dish — an ingredient it needs, already resolved to a
/// lexicon key so matching against the pantry is structural, not fuzzy.
struct IngredientRequirement: Equatable, Sendable {
    let key: String
    let displayName: String
    /// Staples (flour, oil, salt) are assumed present unless explicitly flagged out
    /// (spec §7 resolution classes) — they never make a dish "unmakeable".
    let isStaple: Bool
}

/// A concrete substitution that would let a dish be made tonight: swap the missing
/// `from` ingredient for the `to` ingredient already on hand.
struct SwapOption: Equatable, Sendable {
    let fromName: String
    let toName: String
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
    /// True when the item keyed `key` is on hand with enough confidence to rely on.
    func hasOnHand(_ key: String) -> Bool
    /// True when a staple has been explicitly flagged low/out, overriding the
    /// "assume staples present" rule.
    func isKnownOut(_ key: String) -> Bool
}

/// Resolves substitution targets for a missing ingredient, in priority order
/// (curated swaps + the catalog `swaps` enrichment). Pure lookup.
protocol SwapResolver {
    func swapTargets(for key: String) -> [(key: String, name: String)]
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
            if presence.hasOnHand(req.key) { continue }
            if req.isStaple && !presence.isKnownOut(req.key) { continue }

            if let target = swaps.swapTargets(for: req.key).first(where: { presence.hasOnHand($0.key) }) {
                usedSwaps.append(SwapOption(fromName: req.displayName, toName: target.name))
            } else {
                missing.append(req.displayName)
            }
        }

        if !missing.isEmpty { return .needs(items: missing) }
        if !usedSwaps.isEmpty { return .readyWithSwaps(usedSwaps) }
        return .ready
    }
}
