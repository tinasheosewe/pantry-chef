import Foundation

struct MealPlanEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var mealType: MealType
    var recipe: Recipe?
    var preparedDish: PreparedDish?
    var customMealName: String?
    var plannedServings: Int?
    var notes: String?

    init(
        id: UUID = UUID(),
        date: Date,
        mealType: MealType,
        recipe: Recipe? = nil,
        preparedDish: PreparedDish? = nil,
        customMealName: String? = nil,
        plannedServings: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.mealType = mealType
        self.recipe = recipe
        self.preparedDish = preparedDish
        self.customMealName = customMealName?.trimmed.nilIfEmpty
        self.plannedServings = plannedServings.flatMap { $0 > 0 ? $0 : nil }
        self.notes = notes
    }

    var displayName: String {
        recipe?.title ?? preparedDish?.name ?? normalizedCustomMealName ?? "Unplanned"
    }

    var normalizedCustomMealName: String? {
        customMealName?.trimmed.nilIfEmpty
    }

    var isPlanned: Bool {
        recipe != nil || preparedDish != nil || normalizedCustomMealName != nil
    }

    var defaultPlannedServings: Int? {
        recipe?.servings ?? preparedDish?.servingsRemaining
    }

    var maximumPlannedServings: Int? {
        preparedDish?.servingsRemaining
    }

    var effectivePlannedServings: Int? {
        guard let plannedServings, plannedServings > 0 else {
            return defaultPlannedServings
        }

        if let maximumPlannedServings {
            return Swift.min(plannedServings, maximumPlannedServings)
        }

        return plannedServings
    }

    var supportsPlannedServings: Bool {
        defaultPlannedServings != nil
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

        if preparedDish != nil {
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
            return MealPlanEntry(date: date, mealType: mealType, preparedDish: dish, plannedServings: dish.servingsRemaining)
        }
    }
}
