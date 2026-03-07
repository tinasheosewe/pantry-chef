import Foundation

// MARK: - Step Task
//
// Atomic unit of work within a recipe step. One step may contain multiple tasks.
// Tasks enable cross-recipe merging, scheduling, and interleaving.

struct StepTask: Identifiable, Codable, Hashable {
    var id: UUID
    let action: CookingAction
    let ingredient: String?           // normalized name ("onion", not "1 large yellow onion")
    let quantity: Double?
    let unit: String?
    let durationSeconds: Int
    let type: TaskType
    let requiresEquipment: String?    // "oven", "stovetop", "cutting board"
    let temperature: Int?             // °F — for merging "preheat oven" steps

    /// Explicit dependency graph: IDs of tasks that must complete before this one.
    /// Built by the LLM at recipe-creation time so the scheduler uses an exact DAG
    /// instead of fuzzy ingredient-name matching.
    var dependsOn: [UUID]

    /// Which recipe this task belongs to (set during scheduling).
    var recipeId: UUID?
    var recipeName: String?

    /// Original step number within the source recipe.
    var sourceStepNumber: Int?

    init(
        id: UUID = UUID(),
        action: CookingAction,
        ingredient: String? = nil,
        quantity: Double? = nil,
        unit: String? = nil,
        durationSeconds: Int = 60,
        type: TaskType = .active,
        requiresEquipment: String? = nil,
        temperature: Int? = nil,
        dependsOn: [UUID] = [],
        recipeId: UUID? = nil,
        recipeName: String? = nil,
        sourceStepNumber: Int? = nil
    ) {
        self.id = id
        self.action = action
        self.ingredient = ingredient
        self.quantity = quantity
        self.unit = unit
        self.durationSeconds = durationSeconds
        self.type = type
        self.requiresEquipment = requiresEquipment
        self.temperature = temperature
        self.dependsOn = dependsOn
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.sourceStepNumber = sourceStepNumber
    }

    /// Human-readable description for display.
    var displayText: String {
        var parts: [String] = []
        parts.append(action.verb)
        if let q = quantity, let u = unit, let ing = ingredient {
            if q == q.rounded() {
                parts.append("\(Int(q)) \(u) \(ing)")
            } else {
                parts.append(String(format: "%.1f %@ %@", q, u, ing))
            }
        } else if let ing = ingredient {
            parts.append(ing)
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Task Type

enum TaskType: String, Codable, Hashable {
    case active    // needs hands (chopping, stirring, flipping)
    case passive   // waiting (baking, boiling, marinating, resting)
}

// MARK: - Cooking Action

enum CookingAction: Codable, Hashable {
    // Prep
    case cut(CutStyle)
    case peel
    case measure
    case mix
    case marinate
    case season

    // Cook
    case heat
    case saute
    case boil
    case simmer
    case fry(FryStyle)
    case bake
    case roast
    case grill
    case steam
    case scramble

    // Finish
    case plate
    case garnish
    case rest
    case serve
    case toss

    // Generic fallback
    case other(String)

    enum CutStyle: String, Codable, Hashable {
        case dice, mince, julienne, slice, chop, rough, halve
    }

    enum FryStyle: String, Codable, Hashable {
        case pan, deep, stir
    }

    /// The action class for grouping/merging.
    var actionClass: ActionClass {
        switch self {
        case .cut: return .prepCut
        case .peel, .measure, .mix, .season: return .prepOther
        case .marinate: return .passiveCook
        case .heat: return .heatSetup
        case .saute, .fry, .scramble, .toss: return .activeCook
        case .boil, .simmer, .bake, .roast, .grill, .steam: return .passiveCook
        case .rest: return .passiveCook
        case .plate, .garnish, .serve: return .finish
        case .other: return .activeCook
        }
    }

    /// Human-readable verb for display.
    var verb: String {
        switch self {
        case .cut(let style): return style.rawValue.capitalized
        case .peel: return "Peel"
        case .measure: return "Measure"
        case .mix: return "Mix"
        case .marinate: return "Marinate"
        case .season: return "Season"
        case .heat: return "Heat"
        case .saute: return "Sauté"
        case .boil: return "Boil"
        case .simmer: return "Simmer"
        case .fry(let style): return "\(style.rawValue.capitalized)-fry"
        case .bake: return "Bake"
        case .roast: return "Roast"
        case .grill: return "Grill"
        case .steam: return "Steam"
        case .scramble: return "Scramble"
        case .plate: return "Plate"
        case .garnish: return "Garnish"
        case .rest: return "Rest"
        case .serve: return "Serve"
        case .toss: return "Toss"
        case .other(let name): return name.capitalized
        }
    }
}

// MARK: - Action Class (coarse grouping for merging)

enum ActionClass: String, Codable, Hashable, CaseIterable {
    case prepCut      // dice, mince, slice, julienne, chop — same workspace
    case prepOther    // peel, measure, mix, whisk — same phase
    case heatSetup    // preheat oven, boil water, heat oil — mergeable if same equipment+temp
    case activeCook   // sauté, fry, stir, flip — needs attention, one at a time
    case passiveCook  // bake, simmer, marinate, rest — schedulable as gaps
    case finish       // plate, garnish, serve — end phase

    var displayName: String {
        switch self {
        case .prepCut: return "Prep (Cutting)"
        case .prepOther: return "Prep"
        case .heatSetup: return "Heat Setup"
        case .activeCook: return "Active Cooking"
        case .passiveCook: return "Waiting"
        case .finish: return "Plating & Serving"
        }
    }

    var icon: String {
        switch self {
        case .prepCut: return "knife"
        case .prepOther: return "takeoutbag.and.cup.and.straw"
        case .heatSetup: return "flame"
        case .activeCook: return "frying.pan"
        case .passiveCook: return "timer"
        case .finish: return "fork.knife"
        }
    }

    /// Prep-phase tasks (no implicit ordering constraints).
    var isPrep: Bool { self == .prepCut || self == .prepOther }

    /// Tasks that share a pan/vessel sequentially within a recipe.
    var isActiveChain: Bool { self == .activeCook || self == .heatSetup }
}
