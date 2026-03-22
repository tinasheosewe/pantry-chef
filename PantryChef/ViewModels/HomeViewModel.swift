import SwiftUI

@Observable
@MainActor
final class HomeViewModel {
    var greetingMessage: String = ""
    var dashboard = HomeDashboardSnapshot(todaysMeals: [], expiringItems: [], suggestedRecipe: nil, weeklyNutrition: nil)
    var isLoading = false

    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        updateGreeting()
    }

    func refresh() {
        updateGreeting()
        dashboard = appState.homeDashboardSnapshot()
    }

    private func updateGreeting() {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: greetingMessage = "Good morning"
        case 12..<17: greetingMessage = "Good afternoon"
        default: greetingMessage = "Good evening"
        }
    }

    var todaysMeals: [MealPlanEntry] {
        dashboard.todaysMeals
    }

    var expiringItems: [PantryItem] {
        dashboard.expiringItems
    }

    var suggestedRecipe: Recipe? {
        dashboard.suggestedRecipe
    }

    var weeklyNutrition: WeeklyNutritionSummary? {
        dashboard.weeklyNutrition
    }
}

struct WeeklyNutritionSummary: Equatable {
    let totalCalories: Int
    let avgCaloriesPerDay: Int
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
    let mealsPlanned: Int
}
