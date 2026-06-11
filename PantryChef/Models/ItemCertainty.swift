import Foundation

/// How sure the app is that a tracked item is *still in the kitchen* — the
/// "knowledge" clock, distinct from the food's freshness clock (spec §7). Always
/// surfaced to the user as consequences and wording ("should be everything on
/// hand — check the feta"), never as these raw labels.
enum ItemCertainty: String, Codable, Sendable, Comparable, CaseIterable {
    /// Probably consumed or expired since we last had evidence of it.
    case likelyGone
    /// Could go either way — worth a one-tap question only if it changes a decision.
    case uncertain
    /// Likely still here.
    case probable
    /// Recently confirmed; trust the record.
    case confirmed

    private var rank: Int {
        switch self {
        case .likelyGone: return 0
        case .uncertain: return 1
        case .probable: return 2
        case .confirmed: return 3
        }
    }

    static func < (lhs: ItemCertainty, rhs: ItemCertainty) -> Bool {
        lhs.rank < rhs.rank
    }
}
