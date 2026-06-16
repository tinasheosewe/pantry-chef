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
            let catalogID = IntakePipeline.bestCatalogID(for: ing.name,
                                                         resolvedItemID: PantryCatalog.resolveExact(name: key)?.id)
            let isStaple = catalogID.flatMap { PantryCatalog.itemsByID[$0] }?.resolutionClass == .staple
            return RecipeLine(key: key, amount: amount, name: ing.name,
                              isStaple: isStaple, catalogItemID: catalogID)
        }
        let cookSteps = steps.map { raw -> CookStep in
            let timer = raw.timerMinutes.map { max(1, $0) * 60 }
            // The AI tags each sub-task active/passive and prep/cook/finish. The
            // dominant (longest) task sets the step's attention; the step's phase is
            // the most-advanced phase present, so a step that also cooks isn't mistaken
            // for pure prep. Either falls back to text inference when the tags are absent.
            let lead = raw.tasks.max { $0.durationSeconds < $1.durationSeconds }
            let attention: StepAttention? = lead.map { $0.type == "passive" ? .passive : .active }
            let phase = raw.tasks.compactMap { $0.phase.flatMap(StepPhase.init(rawValue:)) }
                .max { $0.order < $1.order }
            let ingredient = raw.tasks.compactMap(\.ingredient).first
            return CookStep(raw.instruction, timerSeconds: timer, phase: phase,
                            attention: attention, ingredient: ingredient)
        }
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
