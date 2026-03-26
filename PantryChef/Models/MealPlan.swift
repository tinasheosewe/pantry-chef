import Foundation

struct MealPlanEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var mealType: MealType
    var recipe: Recipe?
    var preparedDish: PreparedDish?
    var preparedFoodNameSnapshot: String?
    var preparedFoodRecipeID: UUID?
    var preparedFoodIdentityID: UUID?
    var customMealName: String?
    var plannedServings: Int?
    var eatenServings: Int?
    var notes: String?
    var cookedAt: Date?

    init(
        id: UUID = UUID(),
        date: Date,
        mealType: MealType,
        recipe: Recipe? = nil,
        preparedDish: PreparedDish? = nil,
        preparedFoodNameSnapshot: String? = nil,
        preparedFoodRecipeID: UUID? = nil,
        preparedFoodIdentityID: UUID? = nil,
        customMealName: String? = nil,
        plannedServings: Int? = nil,
        eatenServings: Int? = nil,
        notes: String? = nil,
        cookedAt: Date? = nil
    ) {
        let normalizedCustomMealName = customMealName?.trimmed.nilIfEmpty
        let normalizedPlannedServings = plannedServings.flatMap { $0 > 0 ? $0 : nil }
        let normalizedPreparedFoodNameSnapshot = preparedFoodNameSnapshot?.trimmed.nilIfEmpty ?? preparedDish?.name.trimmed.nilIfEmpty
        let normalizedPreparedFoodRecipeID = preparedFoodRecipeID ?? preparedDish?.recipeID
        let normalizedPreparedFoodIdentityID: UUID?
        if normalizedPreparedFoodRecipeID != nil {
            normalizedPreparedFoodIdentityID = nil
        } else {
            normalizedPreparedFoodIdentityID = preparedFoodIdentityID ?? preparedDish?.foodIdentityID
        }

        self.id = id
        self.date = date
        self.mealType = mealType
        self.recipe = recipe
        self.preparedDish = preparedDish
        self.preparedFoodNameSnapshot = normalizedPreparedFoodNameSnapshot
        self.preparedFoodRecipeID = normalizedPreparedFoodRecipeID
        self.preparedFoodIdentityID = normalizedPreparedFoodIdentityID
        self.customMealName = normalizedCustomMealName
        self.plannedServings = normalizedPlannedServings
        self.eatenServings = Self.normalizedEatenServings(
            eatenServings,
            recipe: recipe,
            preparedFoodNameSnapshot: normalizedPreparedFoodNameSnapshot,
            preparedFoodRecipeID: normalizedPreparedFoodRecipeID,
            preparedFoodIdentityID: normalizedPreparedFoodIdentityID,
            customMealName: normalizedCustomMealName,
            plannedServings: normalizedPlannedServings
        )
        self.notes = notes
        self.cookedAt = cookedAt
    }

    var displayName: String {
        recipe?.title ?? preparedFoodNameSnapshot ?? preparedDish?.name ?? normalizedCustomMealName ?? "Unplanned"
    }

    var normalizedCustomMealName: String? {
        customMealName?.trimmed.nilIfEmpty
    }

    var isPlanned: Bool {
        recipe != nil || preparedFoodNameSnapshot != nil || preparedDish != nil || normalizedCustomMealName != nil
    }

    var preparedFoodMatchKey: PreparedFoodMatchKey? {
        if let recipeID = recipe?.id ?? preparedFoodRecipeID {
            return .recipe(recipeID)
        }
        if let preparedFoodIdentityID {
            return .preparedFoodIdentity(preparedFoodIdentityID)
        }
        return nil
    }

    var isPreparedFoodPlan: Bool {
        preparedFoodNameSnapshot != nil
    }

    var defaultPlannedServings: Int? {
        if let recipe {
            return recipe.servings
        }
        if preparedFoodMatchKey != nil || preparedDish != nil {
            return 1
        }
        return nil
    }

    var maximumPlannedServings: Int? {
        nil
    }

    var effectivePlannedServings: Int? {
        guard let plannedServings, plannedServings > 0 else {
            return defaultPlannedServings
        }
        return plannedServings
    }

    var supportsPlannedServings: Bool {
        defaultPlannedServings != nil
    }

    var trackingPlannedServings: Int? {
        effectivePlannedServings ?? (normalizedCustomMealName != nil ? 1 : nil)
    }

    var effectiveEatenServings: Int {
        let normalizedEatenServings = Swift.max(0, eatenServings ?? 0)
        if let trackingPlannedServings {
            return Swift.min(normalizedEatenServings, trackingPlannedServings)
        }
        return normalizedEatenServings
    }

    var remainingTrackedServings: Int? {
        trackingPlannedServings.map { Swift.max(0, $0 - effectiveEatenServings) }
    }

    var supportsEatenTracking: Bool {
        trackingPlannedServings != nil
    }

    var eatenServingsRange: ClosedRange<Int> {
        let upperBound = Swift.max(trackingPlannedServings ?? effectiveEatenServings, effectiveEatenServings)
        return 0...upperBound
    }

    var eatenProgressLabel: String? {
        guard let trackingPlannedServings else { return nil }
        guard effectiveEatenServings > 0 else { return nil }
        if effectiveEatenServings >= trackingPlannedServings {
            return "Finished"
        }
        return "\(effectiveEatenServings) of \(trackingPlannedServings) eaten"
    }

    var mealLoggingSummary: String? {
        guard preparedFoodMatchKey != nil else { return nil }
        guard let trackingPlannedServings else { return nil }
        if let eatenProgressLabel {
            return "\(eatenProgressLabel) • \(trackingPlannedServings) planned"
        }
        return trackingPlannedServings == 1 ? "1 planned" : "\(trackingPlannedServings) planned"
    }

    var isFullyEaten: Bool {
        guard let trackingPlannedServings else { return false }
        return effectiveEatenServings >= trackingPlannedServings
    }

    var supportsMealLogging: Bool {
        preparedFoodMatchKey != nil && trackingPlannedServings != nil
    }

    var editablePlannedServingsRange: ClosedRange<Int> {
        if let maximumPlannedServings {
            return 1...Swift.max(1, maximumPlannedServings)
        }

        return 1...Swift.max(defaultPlannedServings ?? 1, 24)
    }

    var plannedServingsLabel: String? {
        guard let effectivePlannedServings else { return nil }
        return effectivePlannedServings == 1 ? "1 serving planned" : "\(effectivePlannedServings) servings planned"
    }

    var planningSubtitle: String? {
        if let recipe {
            if let plannedServingsLabel {
                return "\(plannedServingsLabel) • \(recipe.totalTimeDisplay)"
            }
            return recipe.totalTimeDisplay
        }

        if preparedFoodMatchKey != nil {
            return plannedServingsLabel
        }

        return plannedServingsLabel
    }

    var scaledRecipeForPlanning: Recipe? {
        guard let recipe else { return nil }
        guard let effectivePlannedServings, effectivePlannedServings != recipe.servings else {
            return recipe
        }
        return recipe.scaled(to: effectivePlannedServings)
    }

    func updatingPlannedServings(_ plannedServings: Int?) -> MealPlanEntry {
        var updated = self
        updated.plannedServings = plannedServings.flatMap { $0 > 0 ? $0 : nil }
        updated.eatenServings = Self.normalizedEatenServings(
            updated.eatenServings,
            recipe: updated.recipe,
            preparedFoodNameSnapshot: updated.preparedFoodNameSnapshot,
            preparedFoodRecipeID: updated.preparedFoodRecipeID,
            preparedFoodIdentityID: updated.preparedFoodIdentityID,
            customMealName: updated.customMealName,
            plannedServings: updated.plannedServings
        )
        return updated
    }

    func updatingEatenServings(_ eatenServings: Int?) -> MealPlanEntry {
        var updated = self
        updated.eatenServings = Self.normalizedEatenServings(
            eatenServings,
            recipe: updated.recipe,
            preparedFoodNameSnapshot: updated.preparedFoodNameSnapshot,
            preparedFoodRecipeID: updated.preparedFoodRecipeID,
            preparedFoodIdentityID: updated.preparedFoodIdentityID,
            customMealName: updated.customMealName,
            plannedServings: updated.plannedServings
        )
        return updated
    }

    func makePreparedDishDraft() -> PreparedDishDraft {
        if let recipe {
            var draft = PreparedDishDraft(id: id)
            draft.recipeID = recipe.id
            draft.syncLinkedRecipe(recipe)
            if let effectivePlannedServings {
                draft.servingsRemaining = effectivePlannedServings
            }
            if draft.mealTypes.isEmpty {
                draft.mealTypes = [mealType]
            }
            return draft
        }

        if let preparedDish {
            var draft = PreparedDishDraft(id: id, dish: preparedDish)
            if let effectivePlannedServings {
                draft.servingsRemaining = effectivePlannedServings
            }
            return draft
        }

        if preparedFoodMatchKey != nil {
            var draft = PreparedDishDraft(id: id)
            draft.foodIdentityID = preparedFoodIdentityID ?? UUID()
            draft.name = preparedFoodNameSnapshot ?? displayName
            draft.mealTypes = [mealType]
            draft.servingsRemaining = effectivePlannedServings ?? 1
            draft.recipeID = recipe?.id ?? preparedFoodRecipeID
            return draft
        }

        var draft = PreparedDishDraft(id: id)
        draft.name = displayName == "Unplanned" ? "" : displayName
        draft.mealTypes = [mealType]
        draft.servingsRemaining = effectivePlannedServings ?? 1
        return draft
    }

    static func emptyWeek(from startDate: Date = Date()) -> [MealPlanEntry] {
        var entries: [MealPlanEntry] = []
        let mealTypes: [MealType] = [.breakfast, .lunch, .dinner]
        for dayOffset in 0..<7 {
            guard let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }
            for mealType in mealTypes {
                entries.append(MealPlanEntry(date: date, mealType: mealType))
            }
        }
        return entries
    }

    static let samples: [MealPlanEntry] = {
        let today = Date()
        return [
            MealPlanEntry(date: today, mealType: .breakfast, recipe: Recipe.samples[1]),
            MealPlanEntry(date: today, mealType: .lunch, customMealName: "Leftover stir fry"),
            MealPlanEntry(date: today, mealType: .dinner, recipe: Recipe.samples[0]),
        ]
    }()

    private static func normalizedEatenServings(
        _ eatenServings: Int?,
        recipe: Recipe?,
        preparedFoodNameSnapshot: String?,
        preparedFoodRecipeID: UUID?,
        preparedFoodIdentityID: UUID?,
        customMealName: String?,
        plannedServings: Int?
    ) -> Int? {
        guard let eatenServings else { return nil }

        let normalizedPlannedServings = plannedServings.flatMap { $0 > 0 ? $0 : nil }
        let trackingPlannedServings = normalizedPlannedServings
            ?? recipe?.servings
            ?? ((preparedFoodNameSnapshot != nil || preparedFoodRecipeID != nil || preparedFoodIdentityID != nil) ? 1 : nil)
            ?? (customMealName != nil ? 1 : nil)

        let clamped = trackingPlannedServings.map { Swift.min(Swift.max(0, eatenServings), $0) } ?? Swift.max(0, eatenServings)
        return clamped > 0 ? clamped : nil
    }
}

enum MealSelectionItem: Identifiable, Hashable {
    case recipe(Recipe)
    case preparedDish(PreparedDish)

    var id: String {
        switch self {
        case .recipe(let recipe):
            return "recipe:\(recipe.id.uuidString)"
        case .preparedDish(let dish):
            return "prepared:\(dish.id.uuidString)"
        }
    }

    var displayName: String {
        switch self {
        case .recipe(let recipe):
            return recipe.title
        case .preparedDish(let dish):
            return dish.name
        }
    }

    func makeEntry(date: Date, mealType: MealType) -> MealPlanEntry {
        switch self {
        case .recipe(let recipe):
            return MealPlanEntry(date: date, mealType: mealType, recipe: recipe, plannedServings: recipe.servings)
        case .preparedDish(let dish):
            return MealPlanEntry(date: date, mealType: mealType, preparedDish: dish, plannedServings: 1)
        }
    }
}
