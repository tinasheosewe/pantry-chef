import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var greetingMessage: String = ""
    @Published var todaysMeals: [MealPlanEntry] = []
    @Published var expiringItems: [PantryItem] = []
    @Published var suggestedRecipe: Recipe?
    @Published var weeklyNutrition: WeeklyNutritionSummary?
    @Published var isLoading = false

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        updateGreeting()
    }

    func refresh() {
        updateGreeting()
        loadTodaysMeals()
        loadExpiringItems()
        loadSuggestedRecipe()
        calculateWeeklyNutrition()
    }

    private func updateGreeting() {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: greetingMessage = "Good morning"
        case 12..<17: greetingMessage = "Good afternoon"
        case 17..<22: greetingMessage = "Good evening"
        default: greetingMessage = "Good night"
        }
    }

    private func loadTodaysMeals() {
        let today = Calendar.current.startOfDay(for: Date())
        todaysMeals = appState.mealPlan.filter {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }
    }

    private func loadExpiringItems() {
        expiringItems = appState.expiringItems
    }

    private func loadSuggestedRecipe() {
        // Find the recipe with the best pantry match
        let matches = appState.recipes.map { $0.pantryMatch(pantry: appState.pantryItems) }
        suggestedRecipe = matches.max(by: { $0.matchPercentage < $1.matchPercentage })?.recipe
    }

    private func calculateWeeklyNutrition() {
        let cookedRecipes = appState.mealPlan.compactMap { $0.recipe }
        guard !cookedRecipes.isEmpty else {
            weeklyNutrition = nil
            return
        }

        var totalCalories = 0
        var totalProtein = 0.0
        var totalCarbs = 0.0
        var totalFat = 0.0

        for recipe in cookedRecipes {
            if let nutrition = recipe.nutrition {
                totalCalories += nutrition.calories
                totalProtein += nutrition.protein
                totalCarbs += nutrition.carbohydrates
                totalFat += nutrition.fat
            }
        }

        weeklyNutrition = WeeklyNutritionSummary(
            totalCalories: totalCalories,
            avgCaloriesPerDay: totalCalories / 7,
            totalProtein: totalProtein,
            totalCarbs: totalCarbs,
            totalFat: totalFat,
            mealsPlanned: cookedRecipes.count
        )
    }
}

struct WeeklyNutritionSummary {
    let totalCalories: Int
    let avgCaloriesPerDay: Int
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
    let mealsPlanned: Int
}
