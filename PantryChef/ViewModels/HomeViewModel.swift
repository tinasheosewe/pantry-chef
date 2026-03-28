import SwiftUI

@Observable
@MainActor
final class HomeViewModel {
    var greetingMessage: String = ""
    var dashboard = HomeDashboardSnapshot(todaysMeals: [], expiringItems: [], suggestedRecipe: nil, weeklyNutrition: nil)
    var isLoading = false

    let appState: AppState
    @ObservationIgnored private let inventoryGateway: InventoryGateway

    init(appState: AppState) {
        self.appState = appState
        self.inventoryGateway = appState.inventoryGateway
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

    var expiringPreparedDishes: [PreparedDish] {
        appState.expiringPreparedDishes
    }

    var suggestedRecipe: Recipe? {
        dashboard.suggestedRecipe
    }

    var weeklyNutrition: WeeklyNutritionSummary? {
        dashboard.weeklyNutrition
    }

    func addShoppingItems(_ items: [ShoppingItem]) async {
        await inventoryGateway.addShoppingItems(items)
    }
}

struct WeeklyNutritionSummary: Equatable {
    let totalCalories: Int
    let avgCaloriesPerMeal: Int
    let totalProtein: Double
    let totalCarbs: Double
    let totalFat: Double
    let mealsPlanned: Int

    var avgProteinPerMeal: Int {
        guard mealsPlanned > 0 else { return 0 }
        return Int(totalProtein / Double(mealsPlanned))
    }

    var avgCarbsPerMeal: Int {
        guard mealsPlanned > 0 else { return 0 }
        return Int(totalCarbs / Double(mealsPlanned))
    }

    var avgFatPerMeal: Int {
        guard mealsPlanned > 0 else { return 0 }
        return Int(totalFat / Double(mealsPlanned))
    }
}
