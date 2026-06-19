import Foundation

/// One ingredient line of a dish: an amount, a display name, and the lexicon key
/// used to check it against the pantry. The single source for both readiness
/// (via `requirement`) and the cook-mode gathering checklist.
struct RecipeLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let key: String
    let amount: String?     // "300 g", "2", nil for "to taste"
    let name: String
    let isStaple: Bool
    /// Whether this line is *load-bearing* — i.e. the dish genuinely needs it. A
    /// non-essential line (a garnish, a "to taste"/"to serve" finish, an optional
    /// extra) is droppable: missing it never makes the dish unmakeable, it's just
    /// surfaced as an optional add. Staples are a separate axis (assumed present);
    /// a line can be essential and non-staple (the common case), or optional.
    let essential: Bool
    /// The catalog item this line *is*, when known (seed + editor-resolved recipes).
    /// Readiness/swaps match on this directly — no fuzzy name mapping. Nil only for
    /// genuinely freeform lines, which fall back to name matching.
    let catalogItemID: String?
    /// When this line is being made via a substitution, the swap's note (ratio /
    /// quantity guidance, e.g. "¼ cup applesauce per egg") — carried through to the
    /// cook so the gathering screen shows what to use instead.
    let swapNote: String?

    init(id: UUID = UUID(), key: String, amount: String? = nil, name: String,
         isStaple: Bool = false, essential: Bool = true,
         catalogItemID: String? = nil, swapNote: String? = nil) {
        self.id = id; self.key = key; self.amount = amount; self.name = name
        self.isStaple = isStaple; self.essential = essential
        self.catalogItemID = catalogItemID; self.swapNote = swapNote
    }

    var requirement: IngredientRequirement {
        IngredientRequirement(key: key, displayName: name, isStaple: isStaple,
                              essential: essential, catalogItemID: catalogItemID)
    }

    /// Heuristic load-bearing classification for lines that don't carry an explicit
    /// flag (seed dataset, AI ingestion): a line is *optional* when its amount or name
    /// signals a garnish / finishing touch / to-taste extra. Conservative — only clear
    /// signals demote a line, so the default stays essential.
    static func isLikelyOptional(name: String, amount: String?) -> Bool {
        let hay = "\(name) \(amount ?? "")".lowercased()
        let signals = ["to taste", "to serve", "for serving", "to garnish", "for garnish",
                       "as garnish", "to finish", "for the garnish", "optional", "if desired",
                       "garnish", "to drizzle", "for dusting", "to dust"]
        return signals.contains(where: hay.contains)
    }

    /// "300 g · Baby spinach"
    var display: String { amount.map { "\($0) · \(name)" } ?? name }

    /// A copy with the amount recomposed from a structured quantity + unit (the
    /// recipe editor uses a fixed unit picker, never freeform unit text).
    func withAmount(qty: String, unit: MeasurementUnit?) -> RecipeLine {
        let q = qty.trimmingCharacters(in: .whitespaces)
        let amount: String? = q.isEmpty ? nil : (unit.map { "\(q) \($0.rawValue)" } ?? q)
        return RecipeLine(id: id, key: key, amount: amount, name: name,
                          isStaple: isStaple, essential: essential,
                          catalogItemID: catalogItemID, swapNote: swapNote)
    }
}

/// Where a step sits in the arc of cooking — prep is the knife work you can do up
/// front (mise en place), cook is the heat, finish is plating.
enum StepPhase: String, Equatable, Sendable {
    case prep, cook, finish
    /// Sequence rank — a step spanning several phases takes the most-advanced one,
    /// so a step that also cooks is never mistaken for pure prep.
    var order: Int { switch self { case .prep: 0; case .cook: 1; case .finish: 2 } }
    /// The next phase in the cycle, for a one-tap editor toggle.
    var next: StepPhase { switch self { case .prep: .cook; case .cook: .finish; case .finish: .prep } }
}

/// Whether a step holds the cook's hands (active) or runs on a timer they walk away
/// from (passive) — the axis that decides what can overlap.
enum StepAttention: String, Equatable, Sendable { case active, passive }

/// One cooking step, optionally timed, and structurally tagged so the multi-dish
/// scheduler can front-load prep and overlap passive waits. Tags are inferred from
/// the text + timer when not given (`StepClassifier`), so every step carries them.
struct CookStep: Identifiable, Equatable, Sendable {
    let id: UUID
    let instruction: String
    let timerSeconds: Int?
    /// The ingredient this step centres on, when known (AI ingestion supplies it) —
    /// for labelling and possible grouping in a unified prep list.
    let ingredient: String?
    private let rawPhase: StepPhase?
    private let rawAttention: StepAttention?

    /// Phase/attention are inferred from the text + timer when not given. Computed
    /// lazily (not at init) so loading a ~200-recipe library doesn't classify ~1,200
    /// steps up front — only the handful in the dish you actually cook get classified.
    var phase: StepPhase { rawPhase ?? StepClassifier.phase(of: instruction) }
    var attention: StepAttention { rawAttention ?? StepClassifier.attention(of: instruction, timerSeconds: timerSeconds) }

    init(id: UUID = UUID(), _ instruction: String, timerSeconds: Int? = nil,
         phase: StepPhase? = nil, attention: StepAttention? = nil, ingredient: String? = nil) {
        self.id = id; self.instruction = instruction; self.timerSeconds = timerSeconds
        self.rawPhase = phase; self.rawAttention = attention; self.ingredient = ingredient
    }
}

/// Infers a step's phase and attention from its wording (and timer) — the fallback
/// that keeps every CookStep structurally tagged even when the source (a seed, a
/// hand-typed editor step) doesn't say so explicitly.
enum StepClassifier {
    private static let finishVerbs = ["serve", "plate", "garnish", "drizzle over", "top with",
                                      "finish with", "sprinkle over", "scatter over", "to serve"]
    private static let prepVerbs = ["chop", "dice", "slice", "mince", "grate", "peel", "crush",
                                    "cut ", "measure", "whisk together", "beat the", "combine the",
                                    "mix together", "season the", "zest", "trim", "drain", "rinse",
                                    "pat dry", "halve", "quarter", "cube", "shred", "juice the"]
    private static let cookVerbs = ["cook", "fry", "sauté", "saute", "simmer", "boil", "bake",
                                    "roast", "grill", "braise", "heat", "sear", "steam", "poach",
                                    "toast", "melt", "caramel", "reduce", "stir-fry", "add", "fold in",
                                    "bring to", "deglaze", "blanch", "warm"]
    private static let passiveVerbs = ["simmer", "bake", "roast", "braise", "rest", "chill",
                                       "marinate", "proof", "refrigerate", "cool", "steep", "reduce",
                                       "slow cook", "let it", "leave to", "set aside", "infuse"]

    static func phase(of instruction: String) -> StepPhase {
        let s = instruction.lowercased()
        if finishVerbs.contains(where: s.contains) { return .finish }
        if cookVerbs.contains(where: s.contains) { return .cook }
        if prepVerbs.contains(where: s.contains) { return .prep }
        return .cook
    }

    static func attention(of instruction: String, timerSeconds: Int?) -> StepAttention {
        if let t = timerSeconds, t >= AppConfig.passiveStepThresholdSeconds { return .passive }
        return passiveVerbs.contains(where: instruction.lowercased().contains) ? .passive : .active
    }
}

/// A cookable recipe — the unit the Library shows, readiness is computed for, and
/// Cook mode runs. Carries everything Cook needs so it never sends you to the
/// pantry mid-step (spec §2 gathering).
struct Dish: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let plate: PlateComposition
    var time: String
    let isYours: Bool
    var isFavorite: Bool
    var servings: Int
    /// The dish's one sentence — the editorial line under its name (Field Notes:
    /// every dish gets its sentence). Optional; user dishes may not have one yet.
    var blurb: String?
    var ingredients: [RecipeLine]
    var steps: [CookStep]
    /// Browse/filter tags (from the seeded recipe dataset) — power the Today feed's
    /// lenses beyond the pantry-derived ones. Empty/nil for hand-built or user dishes.
    var cuisine: String?
    var mealType: String?
    var course: String?
    var diets: [String]
    var methods: [String]
    /// Explicit per-serving nutrition (hand-authored or AI-generated at build time).
    /// When nil the recipe page shows a labelled estimate from `NutritionEstimator`.
    var nutrition: NutritionFacts?

    init(id: UUID = UUID(), name: String, plate: PlateComposition, time: String,
         isYours: Bool = false, isFavorite: Bool = false, servings: Int = 2,
         blurb: String? = nil,
         ingredients: [RecipeLine], steps: [CookStep] = [],
         cuisine: String? = nil, mealType: String? = nil, course: String? = nil,
         diets: [String] = [], methods: [String] = [], nutrition: NutritionFacts? = nil) {
        self.id = id; self.name = name; self.plate = plate; self.time = time
        self.isYours = isYours; self.isFavorite = isFavorite; self.servings = servings
        self.blurb = blurb
        self.ingredients = ingredients; self.steps = steps
        self.cuisine = cuisine; self.mealType = mealType; self.course = course
        self.diets = diets; self.methods = methods; self.nutrition = nutrition
    }

    var requirements: [IngredientRequirement] { ingredients.map(\.requirement) }

    /// A copy with a fresh identity — for "save as new" after a tweak/edit, so the
    /// original recipe is left untouched. Marked as the user's own, not favorited.
    func copyAsNew() -> Dish {
        Dish(name: name, plate: plate, time: time, isYours: true, isFavorite: false,
             servings: servings, blurb: blurb, ingredients: ingredients, steps: steps,
             cuisine: cuisine, mealType: mealType, course: course, diets: diets, methods: methods)
    }

    /// A blank recipe to fill in — the manual "write a recipe" front door.
    static func draft() -> Dish {
        Dish(name: "", plate: PlateComposition(categories: [], seed: UInt64.random(in: 0..<100_000)),
             time: "", isYours: true, servings: 2, ingredients: [], steps: [])
    }

    /// A copy whose plate art is derived from the ingredients' catalog categories —
    /// used when saving a hand-built recipe that has no authored plate.
    func withDerivedPlate() -> Dish {
        var seen: [FoodCategory] = []
        for line in ingredients {
            guard let id = line.catalogItemID, let cat = PantryCatalog.itemsByID[id]?.category else { continue }
            if !seen.contains(cat) { seen.append(cat) }
        }
        let cats = seen.isEmpty ? [.other] : Array(seen.prefix(3))
        return Dish(id: id, name: name,
                    plate: PlateComposition(categories: cats, seed: UInt64(abs(name.hashValue) % 100_000)),
                    time: time, isYours: isYours, isFavorite: isFavorite, servings: servings,
                    blurb: blurb, ingredients: ingredients, steps: steps, cuisine: cuisine,
                    mealType: mealType, course: course, diets: diets, methods: methods, nutrition: nutrition)
    }

    /// This dish scaled to a different serving count: every ingredient amount with
    /// a leading number is multiplied; unitless lines ("to taste") pass through.
    func scaled(to newServings: Int) -> Dish {
        guard newServings > 0, newServings != servings, servings > 0 else { return self }
        let factor = Double(newServings) / Double(servings)
        var copy = self
        copy.servings = newServings
        copy.ingredients = ingredients.map { line in
            guard let amount = line.amount,
                  let scaled = Self.scaledAmount(amount, by: factor) else { return line }
            return RecipeLine(id: line.id, key: line.key, amount: scaled,
                              name: line.name, isStaple: line.isStaple, essential: line.essential,
                              catalogItemID: line.catalogItemID, swapNote: line.swapNote)
        }
        return copy
    }

    /// "300 g" ×1.5 → "450 g"; "1 cup" ×2 → "2 cups"… leaves non-numeric text alone.
    static func scaledAmount(_ amount: String, by factor: Double) -> String? {
        let parts = amount.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first, let qty = IntakeParser.quantity(first.lowercased()) else { return nil }
        let qtyText = QuantityFormat.short(qty * factor)
        return parts.count > 1 ? "\(qtyText) \(parts[1])" : qtyText
    }

    /// This dish with one ingredient line swapped for a substitute (the cook flow
    /// then gathers the substitute instead).
    func applyingSwap(to lineID: UUID, key: String, name newName: String,
                      catalogItemID: String? = nil, note: String? = nil) -> Dish {
        var copy = self
        if let i = copy.ingredients.firstIndex(where: { $0.id == lineID }) {
            let old = copy.ingredients[i]
            // The swapped line takes on the substitute's catalog identity, so the
            // gathering checklist and readiness see what you're actually using; the
            // note (ratio / quantity guidance) rides along to the cook.
            let resolved = catalogItemID ?? PantryCatalog.resolveExact(name: newName)?.id
            copy.ingredients[i] = RecipeLine(id: old.id, key: key, amount: old.amount,
                                             name: newName, isStaple: old.isStaple, essential: old.essential,
                                             catalogItemID: resolved, swapNote: note)
        }
        return copy
    }

    /// Total time in minutes, parsed from the display string ("25 min", "2 h 10").
    var minutes: Int? {
        let numbers = time.lowercased().split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if time.lowercased().contains("h") {
            guard let hours = numbers.first else { return nil }
            return hours * 60 + (numbers.count > 1 ? numbers[1] : 0)
        }
        return numbers.first
    }

    /// The duration formatted for display — under an hour stays in minutes, an hour or
    /// more reads as hours (+ minutes), never "480 min". Falls back to the raw `time`
    /// string when it can't be parsed.
    var timeText: String { RecipeTime.format(minutes) ?? time }
}

/// One place to phrase a recipe duration, so every surface agrees: "45 min", "1 h",
/// "2 h 10". Minutes under an hour stay minutes; an hour or more becomes hours (+ the
/// remaining minutes).
enum RecipeTime {
    static func format(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }
    static func format(_ minutes: Int?) -> String? { minutes.map(format) }
}
