import Foundation

/// One plate offered in the "Tonight you could…" fan (spec §5). Ranked but not
/// dictated; each carries a *defensibly different* reason.
struct FanOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let plate: PlateComposition
    /// "25 min · 6 of 6 on hand"
    let subtitle: String
    /// The sommelier line — "The rescue pick — spinach won't see Friday."
    let reason: String
    let readiness: Readiness
    let level: MealPrepLevel
    /// The cookable recipe behind this option, when there is one (so Cook can run
    /// real ingredients + steps).
    let dish: Dish?

    init(id: UUID = UUID(), name: String, plate: PlateComposition, subtitle: String,
         reason: String, readiness: Readiness = .ready, level: MealPrepLevel = .cooked,
         dish: Dish? = nil) {
        self.id = id; self.name = name; self.plate = plate
        self.subtitle = subtitle; self.reason = reason
        self.readiness = readiness; self.level = level; self.dish = dish
    }
}

/// A meal committed for tonight — the staging state (logistics, not persuasion).
struct CommittedMeal: Equatable, Sendable {
    let name: String
    let plate: PlateComposition
    let level: MealPrepLevel
    /// "Start by 6:50 to eat at 7:15." — or a reheat note for served meals.
    let logistics: String
    /// The cookable recipe behind the commitment, when there is one.
    var dish: Dish?
}

/// A live cook in progress — the now-module as the cook bar.
struct CookingProgress: Equatable, Sendable {
    let name: String
    let plate: PlateComposition
    let stepIndex: Int
    let totalSteps: Int
    let timerText: String?
    /// The dish being cooked, so Resume can reopen the instrument.
    var dish: Dish?
    var fraction: Double {
        totalSteps > 0 ? Double(stepIndex) / Double(totalSteps) : 0
    }
}

/// The aftermath — what was eaten and what it left behind.
struct CookedSummary: Equatable, Sendable {
    let name: String
    let plate: PlateComposition
    /// "Cooked at 7:20 — 2 servings into the fridge. Good for 3 days."
    let summary: String
}

/// The now-module's four states (spec §5 state machine). "Could" language is only
/// valid in `.open`; once committed the voice turns to logistics.
enum NowState: Equatable, Sendable {
    case open(options: [FanOption], selected: Int)
    case committed(CommittedMeal)
    case cooking(CookingProgress)
    case cooked(CookedSummary)

    /// The eyebrow label for each state, keyed to the time of day so the "could…"
    /// invitation isn't dinner-only ("This morning you could…" / "For lunch you
    /// could…" / "Tonight you could…").
    func eyebrow(at part: DayPart) -> String {
        switch self {
        case .open: return part.youCould
        case .committed: return part.nowLabel
        case .cooking: return "On the stove"
        case .cooked: return "Done \(part.nowLabel.lowercased())"
        }
    }
}
