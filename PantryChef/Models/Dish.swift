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

    init(id: UUID = UUID(), key: String, amount: String? = nil, name: String, isStaple: Bool = false) {
        self.id = id; self.key = key; self.amount = amount; self.name = name; self.isStaple = isStaple
    }

    var requirement: IngredientRequirement {
        IngredientRequirement(key: key, displayName: name, isStaple: isStaple)
    }

    /// "300 g · Baby spinach"
    var display: String { amount.map { "\($0) · \(name)" } ?? name }
}

/// One cooking step, optionally timed.
struct CookStep: Identifiable, Equatable, Sendable {
    let id: UUID
    let instruction: String
    let timerSeconds: Int?

    init(id: UUID = UUID(), _ instruction: String, timerSeconds: Int? = nil) {
        self.id = id; self.instruction = instruction; self.timerSeconds = timerSeconds
    }
}

/// A cookable recipe — the unit the Library shows, readiness is computed for, and
/// Cook mode runs. Carries everything Cook needs so it never sends you to the
/// pantry mid-step (spec §2 gathering).
struct Dish: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let plate: PlateComposition
    let time: String
    let isYours: Bool
    let ingredients: [RecipeLine]
    let steps: [CookStep]

    init(id: UUID = UUID(), name: String, plate: PlateComposition, time: String,
         isYours: Bool = false, ingredients: [RecipeLine], steps: [CookStep] = []) {
        self.id = id; self.name = name; self.plate = plate; self.time = time
        self.isYours = isYours; self.ingredients = ingredients; self.steps = steps
    }

    var requirements: [IngredientRequirement] { ingredients.map(\.requirement) }
}
