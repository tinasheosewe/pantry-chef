import SwiftUI

@Observable
@MainActor
final class MealPlanViewModel {
    var weekStartDate: Date
    var entries: [MealPlanEntry] = []
    var showRecipePicker = false
    var selectedSlot: MealSlot?
    var isLoading = false

    let appState: AppState

    struct MealSlot: Identifiable {
        let id = UUID()
        let date: Date
        let mealType: MealType
    }

    init(appState: AppState) {
        self.appState = appState
        let calendar = Calendar.current
        self.weekStartDate = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        loadEntries()
    }

    var weekDays: [Date] {
        (0..<7).compactMap { dayOffset in
            Calendar.current.date(byAdding: .day, value: dayOffset, to: weekStartDate)
        }
    }

    func entriesFor(date: Date, mealType: MealType) -> MealPlanEntry? {
        entries.first { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: date) && entry.mealType == mealType
        }
    }

    func previousWeek() {
        weekStartDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekStartDate) ?? weekStartDate
        loadEntries()
    }

    func nextWeek() {
        weekStartDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: weekStartDate) ?? weekStartDate
        loadEntries()
    }

    func goToCurrentWeek() {
        weekStartDate = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        loadEntries()
    }

    private func loadEntries() {
        entries = appState.mealPlan.filter { entry in
            weekDays.contains { Calendar.current.isDate(entry.date, inSameDayAs: $0) }
        }
    }

    func assignRecipe(_ recipe: Recipe, to slot: MealSlot) async {
        let entry = MealPlanEntry(
            date: slot.date,
            mealType: slot.mealType,
            recipe: recipe
        )
        await appState.addToMealPlan(entry)
        entries.append(entry)
    }

    func removeEntry(_ entry: MealPlanEntry) async {
        await appState.removeFromMealPlan(entry)
        entries.removeAll { $0.id == entry.id }
    }

    func selectSlot(date: Date, mealType: MealType) {
        selectedSlot = MealSlot(date: date, mealType: mealType)
        showRecipePicker = true
    }

    func generateShoppingList() async {
        await appState.generateShoppingListFromMealPlan()
    }

    var totalPlannedMeals: Int {
        entries.filter { $0.isPlanned }.count
    }

    var weekDateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        guard let endDate = Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) else {
            return formatter.string(from: weekStartDate)
        }
        return "\(formatter.string(from: weekStartDate)) – \(formatter.string(from: endDate))"
    }
}
