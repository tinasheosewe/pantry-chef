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
    var name: String
    let plate: PlateComposition
    var time: String
    let isYours: Bool
    var isFavorite: Bool
    var servings: Int
    var ingredients: [RecipeLine]
    var steps: [CookStep]

    init(id: UUID = UUID(), name: String, plate: PlateComposition, time: String,
         isYours: Bool = false, isFavorite: Bool = false, servings: Int = 2,
         ingredients: [RecipeLine], steps: [CookStep] = []) {
        self.id = id; self.name = name; self.plate = plate; self.time = time
        self.isYours = isYours; self.isFavorite = isFavorite; self.servings = servings
        self.ingredients = ingredients; self.steps = steps
    }

    var requirements: [IngredientRequirement] { ingredients.map(\.requirement) }

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
                              name: line.name, isStaple: line.isStaple)
        }
        return copy
    }

    /// "300 g" ×1.5 → "450 g"; "1 cup" ×2 → "2 cups"… leaves non-numeric text alone.
    static func scaledAmount(_ amount: String, by factor: Double) -> String? {
        let parts = amount.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = parts.first, let qty = IntakeParser.quantity(first.lowercased()) else { return nil }
        let scaled = qty * factor
        let qtyText: String
        if scaled == scaled.rounded() {
            qtyText = String(Int(scaled))
        } else {
            qtyText = String(format: "%.2g", scaled)
        }
        return parts.count > 1 ? "\(qtyText) \(parts[1])" : qtyText
    }

    /// This dish with one ingredient line swapped for a substitute (the cook flow
    /// then gathers the substitute instead).
    func applyingSwap(to lineID: UUID, key: String, name newName: String) -> Dish {
        var copy = self
        if let i = copy.ingredients.firstIndex(where: { $0.id == lineID }) {
            let old = copy.ingredients[i]
            copy.ingredients[i] = RecipeLine(id: old.id, key: key, amount: old.amount,
                                             name: newName, isStaple: old.isStaple)
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
}
