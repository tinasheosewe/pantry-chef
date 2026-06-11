import Foundation

/// Bridges the redesign's `Dish` to the legacy `Recipe` model the surviving AI
/// engines speak (AIService.makeItHealthier / modifyRecipe), and back. Lossy in
/// both directions but faithful where it matters: names, amounts, steps.
enum DishBridge {

    static func recipe(from dish: Dish) -> Recipe {
        let ingredients = dish.ingredients.map { line -> Ingredient in
            let parsed = line.amount.flatMap { UnitConversion.parseAmount($0) }
            let bareQty = line.amount.flatMap { Double($0) }
            return Ingredient(
                name: line.name,
                quantity: parsed?.0 ?? bareQty ?? 1,
                unit: parsed?.1,
                category: PantryCatalog.resolveExact(name: line.key)?.category ?? .other
            )
        }
        let steps = dish.steps.enumerated().map { index, step in
            RecipeStep(stepNumber: index + 1, instruction: step.instruction,
                       timerMinutes: step.timerSeconds.map { max(1, $0 / 60) })
        }
        return Recipe(title: dish.name, ingredients: ingredients, steps: steps,
                      servings: dish.servings, prepTimeMinutes: nil,
                      cookTimeMinutes: dish.minutes, difficulty: .easy,
                      dietaryTags: [], source: .aiGenerated)
    }

    /// A returned recipe as a Dish, keeping the original's identity (id, plate,
    /// favorite state) so it replaces in place.
    static func dish(from recipe: Recipe, replacing original: Dish) -> Dish {
        let lines = recipe.ingredients.map { ing -> RecipeLine in
            let key = IngredientLexicon.lookupKey(ing.rawName)
            let amount = formatAmount(ing.quantity, ing.unit)
            let isStaple = PantryCatalog.resolveExact(name: key)?.resolutionClass == .staple
            return RecipeLine(key: key, amount: amount, name: ing.rawName, isStaple: isStaple)
        }
        let steps = recipe.steps.map { CookStep($0.instruction, timerSeconds: $0.timerMinutes.map { $0 * 60 }) }
        return Dish(id: original.id, name: recipe.title, plate: original.plate,
                    time: recipe.totalTimeMinutes.map { "\($0) min" } ?? original.time,
                    isYours: true, isFavorite: original.isFavorite,
                    servings: recipe.servings, ingredients: lines, steps: steps)
    }

    private static func formatAmount(_ qty: Double, _ unit: MeasurementUnit?) -> String? {
        guard qty > 0 else { return nil }
        let qtyText = qty == qty.rounded() ? String(Int(qty)) : String(format: "%.2g", qty)
        return unit.map { "\(qtyText) \($0.rawValue)" } ?? qtyText
    }
}
