import Foundation

/// Maps a parsed AI recipe straight to the live `Dish` model — the AI boundary
/// speaks the live model directly, with no detour through the legacy `Recipe`
/// (which is being retired). The JSON→`RawFullRecipe` decode is unchanged; only
/// this post-decode mapping is new, so it's deterministic and unit-tested.
extension RawFullRecipe {
    /// The modified recipe as a Dish, preserving the original's identity (id, plate,
    /// favorite) so an in-place tweak replaces cleanly.
    func toDish(preserving original: Dish) -> Dish {
        let lines = ingredients.map { ing -> RecipeLine in
            let key = IngredientLexicon.lookupKey(ing.name)
            let unit = MeasurementUnit(rawValue: ing.unit)
            let amount: String? = ing.quantity > 0
                ? (unit.map { "\(QuantityFormat.short(ing.quantity)) \($0.rawValue)" }
                    ?? QuantityFormat.short(ing.quantity))
                : nil
            let isStaple = PantryCatalog.resolveExact(name: key)?.resolutionClass == .staple
            return RecipeLine(key: key, amount: amount, name: ing.name, isStaple: isStaple)
        }
        let cookSteps = steps.map { CookStep($0.instruction, timerSeconds: $0.timerMinutes.map { max(1, $0) * 60 }) }
        let totalMinutes = [prepTimeMinutes, cookTimeMinutes].compactMap { $0 }.reduce(0, +)
        return Dish(
            id: original.id, name: title, plate: original.plate,
            time: totalMinutes > 0 ? "\(totalMinutes) min" : original.time,
            isYours: true, isFavorite: original.isFavorite,
            servings: servings ?? original.servings,
            blurb: description ?? original.blurb,
            ingredients: lines, steps: cookSteps)
    }
}
