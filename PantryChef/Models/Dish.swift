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
    /// The catalog item this line *is*, when known (seed + editor-resolved recipes).
    /// Readiness/swaps match on this directly — no fuzzy name mapping. Nil only for
    /// genuinely freeform lines, which fall back to name matching.
    let catalogItemID: String?

    init(id: UUID = UUID(), key: String, amount: String? = nil, name: String,
         isStaple: Bool = false, catalogItemID: String? = nil) {
        self.id = id; self.key = key; self.amount = amount; self.name = name
        self.isStaple = isStaple; self.catalogItemID = catalogItemID
    }

    var requirement: IngredientRequirement {
        IngredientRequirement(key: key, displayName: name, isStaple: isStaple, catalogItemID: catalogItemID)
    }

    /// "300 g · Baby spinach"
    var display: String { amount.map { "\($0) · \(name)" } ?? name }

    /// A copy with the amount recomposed from a structured quantity + unit (the
    /// recipe editor uses a fixed unit picker, never freeform unit text).
    func withAmount(qty: String, unit: MeasurementUnit?) -> RecipeLine {
        let q = qty.trimmingCharacters(in: .whitespaces)
        let amount: String? = q.isEmpty ? nil : (unit.map { "\(q) \($0.rawValue)" } ?? q)
        return RecipeLine(id: id, key: key, amount: amount, name: name,
                          isStaple: isStaple, catalogItemID: catalogItemID)
    }
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
    /// The dish's one sentence — the editorial line under its name (Field Notes:
    /// every dish gets its sentence). Optional; user dishes may not have one yet.
    var blurb: String?
    var ingredients: [RecipeLine]
    var steps: [CookStep]

    init(id: UUID = UUID(), name: String, plate: PlateComposition, time: String,
         isYours: Bool = false, isFavorite: Bool = false, servings: Int = 2,
         blurb: String? = nil,
         ingredients: [RecipeLine], steps: [CookStep] = []) {
        self.id = id; self.name = name; self.plate = plate; self.time = time
        self.isYours = isYours; self.isFavorite = isFavorite; self.servings = servings
        self.blurb = blurb
        self.ingredients = ingredients; self.steps = steps
    }

    var requirements: [IngredientRequirement] { ingredients.map(\.requirement) }

    /// A copy with a fresh identity — for "save as new" after a tweak/edit, so the
    /// original recipe is left untouched. Marked as the user's own, not favorited.
    func copyAsNew() -> Dish {
        Dish(name: name, plate: plate, time: time, isYours: true, isFavorite: false,
             servings: servings, blurb: blurb, ingredients: ingredients, steps: steps)
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
                              name: line.name, isStaple: line.isStaple,
                              catalogItemID: line.catalogItemID)
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
                      catalogItemID: String? = nil) -> Dish {
        var copy = self
        if let i = copy.ingredients.firstIndex(where: { $0.id == lineID }) {
            let old = copy.ingredients[i]
            // The swapped line takes on the substitute's catalog identity, so the
            // gathering checklist and readiness see what you're actually using.
            let resolved = catalogItemID ?? PantryCatalog.resolveExact(name: newName)?.id
            copy.ingredients[i] = RecipeLine(id: old.id, key: key, amount: old.amount,
                                             name: newName, isStaple: old.isStaple,
                                             catalogItemID: resolved)
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
