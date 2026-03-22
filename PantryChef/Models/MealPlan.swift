import Foundation

struct MealPlanEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var mealType: MealType
    var recipe: Recipe?
    var customMealName: String?
    var notes: String?

    init(
        id: UUID = UUID(),
        date: Date,
        mealType: MealType,
        recipe: Recipe? = nil,
        customMealName: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.mealType = mealType
        self.recipe = recipe
        self.customMealName = customMealName?.trimmed.nilIfEmpty
        self.notes = notes
    }

    var displayName: String {
        recipe?.title ?? normalizedCustomMealName ?? "Unplanned"
    }

    var normalizedCustomMealName: String? {
        customMealName?.trimmed.nilIfEmpty
    }

    var isPlanned: Bool {
        recipe != nil || normalizedCustomMealName != nil
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
