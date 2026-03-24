import SwiftUI

@Observable
@MainActor
final class MealPlanViewModel: AsyncActionHandling {
    var weekStartDate: Date
    var showMealPicker = false
    var showMultiMealPicker = false
    var selectedSlot: MealSlot?
    var isLoading = false

    let appState: AppState
    @ObservationIgnored private let mealPlanActions: MealPlanActions

    struct MealSlot: Identifiable {
        let id = UUID()
        let date: Date
        let mealType: MealType
        let replaceExisting: Bool

        init(date: Date, mealType: MealType, replaceExisting: Bool = true) {
            self.date = date
            self.mealType = mealType
            self.replaceExisting = replaceExisting
        }
    }

    init(appState: AppState) {
        self.appState = appState
        self.mealPlanActions = MealPlanActions(appState: appState)
        let calendar = Calendar.current
        self.weekStartDate = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    var entries: [MealPlanEntry] {
        appState.plannedEntries(forWeekStarting: weekStartDate)
    }

    var weekDays: [Date] {
        (0..<7).compactMap { dayOffset in
            Calendar.current.date(byAdding: .day, value: dayOffset, to: weekStartDate)
        }
    }

    func entriesFor(date: Date, mealType: MealType) -> [MealPlanEntry] {
        entries.filter { entry in
            Calendar.current.isDate(entry.date, inSameDayAs: date) && entry.mealType == mealType
        }
    }

    func previousWeek() {
        weekStartDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekStartDate) ?? weekStartDate
    }

    func nextWeek() {
        weekStartDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: weekStartDate) ?? weekStartDate
    }

    func goToCurrentWeek() {
        weekStartDate = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    func assignRecipe(_ recipe: Recipe, to slot: MealSlot) {
        runTask { [self] in
            await self.mealPlanActions.assignRecipe(recipe, to: slot)
        }
    }

    func assignPreparedDish(_ dish: PreparedDish, to slot: MealSlot) {
        runTask { [self] in
            await self.mealPlanActions.assignPreparedDish(dish, to: slot)
        }
    }

    func assignSelections(_ selections: [MealSelectionItem], to slot: MealSlot) {
        runTask { [self] in
            await self.mealPlanActions.assignSelections(selections, to: slot)
        }
    }

    func removeEntry(_ entry: MealPlanEntry) {
        runTask { [self] in
            await self.mealPlanActions.removeEntry(entry)
        }
    }

    func removeEntries(_ entries: [MealPlanEntry]) {
        runTask { [self] in
            await self.mealPlanActions.removeEntries(entries)
        }
    }

    func updateEntry(_ entry: MealPlanEntry) {
        runTask { [self] in
            await self.mealPlanActions.updateEntry(entry)
        }
    }

    func logEntriesEaten(_ entries: [MealPlanEntry]) {
        runTask { [self] in
            await self.mealPlanActions.logEntriesEaten(entries)
        }
    }

    func selectSlot(date: Date, mealType: MealType, replaceExisting: Bool = true, allowsMultipleSelection: Bool = false) {
        selectedSlot = MealSlot(date: date, mealType: mealType, replaceExisting: replaceExisting)
        if allowsMultipleSelection {
            showMultiMealPicker = true
        } else {
            showMealPicker = true
        }
    }

    func generateShoppingList() {
        runTask { [self] in
            await self.mealPlanActions.generateShoppingList()
        }
    }

    func previewShoppingList() -> [ShoppingItem] {
        appState.previewShoppingListFromMealPlan()
    }

    func addShoppingItems(_ items: [ShoppingItem]) {
        runTask { [self] in
            await self.mealPlanActions.addShoppingItems(items)
        }
    }

    func addEntriesToCookQueue(_ entries: [MealPlanEntry], asParallelBatch: Bool) {
        runTask { [self] in
            await self.mealPlanActions.addEntriesToCookQueue(entries, asParallelBatch: asParallelBatch)
        }
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
