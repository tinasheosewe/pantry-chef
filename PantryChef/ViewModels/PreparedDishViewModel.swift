import SwiftUI

@Observable
@MainActor
final class PreparedDishViewModel: AsyncActionHandling {
    var searchText = ""
    private(set) var debouncedSearchText = ""
    var selectedMealType: MealType?
    var showAddDish = false
    var editingDish: PreparedDish?
    var selectedDish: PreparedDish?
    var isLoading = false

    @ObservationIgnored private let searchDebouncer = TaskDebouncer()
    @ObservationIgnored private let preparedDishActions: PreparedDishActions

    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        self.preparedDishActions = PreparedDishActions(appState: appState)
    }

    var filteredDishes: [PreparedDish] {
        var dishes = SearchQuerySupport.filtered(appState.preparedDishes, query: debouncedSearchText) { $0.name }

        if let selectedMealType {
            dishes = dishes.filter { $0.mealTypes.contains(selectedMealType) }
        }

        return dishes.sorted { lhs, rhs in
            switch (lhs.useByDate, rhs.useByDate) {
            case let (left?, right?):
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.dateAdded > rhs.dateAdded
            }
        }
    }

    var mealTypeCounts: [MealType: Int] {
        var counts: [MealType: Int] = [:]
        for dish in appState.preparedDishes {
            for mealType in dish.mealTypes {
                counts[mealType, default: 0] += 1
            }
        }
        return counts
    }

    func onSearchTextChanged() {
        SearchQuerySupport.schedule(text: searchText, debouncer: searchDebouncer) {
            self.debouncedSearchText = $0
        }
    }

    func addDish(_ dish: PreparedDish) {
        runTask { [self] in
            await self.preparedDishActions.addDish(dish)
        }
    }

    func updateDish(_ dish: PreparedDish) {
        runTask { [self] in
            await self.preparedDishActions.updateDish(dish)
        }
    }

    func deleteDish(_ dish: PreparedDish) {
        runTask { [self] in
            await self.preparedDishActions.deleteDish(dish)
        }
    }
}