import Foundation

/// The four ways a meal happens (spec §8). The primitive is *a meal*, not a cook —
/// an apple is as valid as a Sunday roast, and none is judged. Drives the action
/// verb and how the meal is logged.
enum MealPrepLevel: String, Codable, Sendable, CaseIterable {
    /// Followed a recipe through the cook instrument.
    case cooked
    /// Cooked without a recipe (the improviser's log).
    case improvised
    /// Reheated made stock (leftovers) — no instrument.
    case served
    /// Ate directly — an apple, a girl dinner.
    case justAte

    /// The action verb shown on cards for a meal at this level. Already-made food
    /// isn't cooked — you heat it and log that you ate it, so the verb says so.
    var verb: String {
        switch self {
        case .cooked: return "Cook"
        case .improvised: return "Cooked it"
        case .served: return "Log it"
        case .justAte: return "Log it"
        }
    }

    /// Whether this level runs through the full-screen cook instrument.
    var usesInstrument: Bool { self == .cooked }
}
