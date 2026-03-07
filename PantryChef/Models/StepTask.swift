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

    /// Attention cost for the effort-budget scheduler.
    /// Set by the LLM at recipe creation time. Passive tasks always cost 0.
    let effort: EffortLevel

    /// Explicit dependency graph: IDs of tasks that must complete before this one.
    /// Built by the LLM at recipe-creation time so the scheduler uses an exact DAG
    /// instead of fuzzy ingredient-name matching.
    var dependsOn: [UUID]

    /// Which recipe this task belongs to (set during scheduling).
    var recipeId: UUID?
    var recipeName: String?

    /// Original step number within the source recipe.
    var sourceStepNumber: Int?

    /// Effort points consumed when this task is active (passive tasks cost 0).
    var effortPoints: Int {
        type == .passive ? 0 : effort.points
    }

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
        effort: EffortLevel = .easy,
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
        self.effort = effort
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

// MARK: - Effort Level

/// How much active attention a task demands. Used by the scheduler to
/// decide how many tasks a cook can handle simultaneously.
///   • Budget per block: 3 points
///   • Passive tasks always cost 0 (background timers).
enum EffortLevel: Int, Codable, Hashable, CaseIterable {
    case easy   = 1   // occasional checking — boiling, toasting, simmering
    case medium = 2   // periodic attention  — sautéing, pan-frying, flipping
    case hard   = 3   // constant hands-on   — stir-frying, tempering, roux

    var points: Int { rawValue }

    var displayName: String {
        switch self {
        case .easy:   return "Easy"
        case .medium: return "Medium"
        case .hard:   return "Hard"
        }
    }

    init(from string: String) {
        switch string.lowercased() {
        case "easy", "1":   self = .easy
        case "medium", "2": self = .medium
        case "hard", "3":   self = .hard
        default:            self = .medium
        }
    }
}

// MARK: - Action Class (phase preference for scheduling tiebreaks)

enum ActionClass: String, Codable, Hashable, CaseIterable {
    case prepCut      // dice, mince, slice, julienne, chop
    case prepOther    // peel, measure, mix, whisk
    case heatSetup    // preheat oven, boil water, heat oil
    case activeCook   // sauté, fry, stir, flip
    case passiveCook  // bake, simmer, marinate, rest
    case finish       // plate, garnish, serve

    /// Phase priority for the scheduler: lower = earlier.
    /// Used only as a tiebreaker when picking from the ready set.
    var phasePriority: Int {
        switch self {
        case .prepCut:    return 0
        case .prepOther:  return 1
        case .heatSetup:  return 2
        case .passiveCook: return 2   // start passive early too
        case .activeCook: return 3
        case .finish:     return 4
        }
    }

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
}
