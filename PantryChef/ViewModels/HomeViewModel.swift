import SwiftUI

@Observable
@MainActor
final class HomeViewModel {
    var greetingMessage: String = ""
    var todaysMeals: [MealPlanEntry] = []
    var expiringItems: [PantryItem] = []
    var suggestedRecipe: Recipe?
    var weeklyNutrition: WeeklyNutritionSummary?
    var isLoading = false

    let appState: AppState

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
        default: greetingMessage = "Good evening"
        }
    }

    private func loadTodaysMeals() {
        let today = Calendar.current.startOfDay(for: Date())
        todaysMeals = appState.mealPlan.filter {
            $0.isPlanned && Calendar.current.isDate($0.date, inSameDayAs: today)
        }
    }

    private func loadExpiringItems() {
        expiringItems = appState.expiringItems
    }

    private func loadSuggestedRecipe() {
        // Find the recipe with the best pantry match — pre-compute once, pick best
        let pantry = appState.pantryItems
        guard !pantry.isEmpty, !appState.recipes.isEmpty else {
            suggestedRecipe = nil
            return
        }
        var bestRecipe: Recipe?
        var bestPct: Double = -1
        for recipe in appState.recipes {
            let pct = recipe.pantryMatch(pantry: pantry).matchPercentage
            if pct > bestPct {
                bestPct = pct
                bestRecipe = recipe
            }
        }
        suggestedRecipe = bestRecipe
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
