import SwiftUI

@Observable
@MainActor
final class PreparedDishViewModel: AsyncActionHandling {
    struct FeedbackBanner: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    var searchText = ""
    private(set) var debouncedSearchText = ""
    var selectedMealType: MealType?
    var showAddDish = false
    var editingDish: PreparedDish?
    var selectedDish: PreparedDish?
    var feedbackBanner: FeedbackBanner?
    var isLoading = false

    @ObservationIgnored private let searchDebouncer = TaskDebouncer()
    @ObservationIgnored private let preparedDishActions: PreparedDishActions
    @ObservationIgnored private var feedbackDismissTask: Task<Void, Never>?

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

    /// Groups dishes by identity (name) so items with same name but different expiry dates are grouped together.
    var groupedByIdentity: [PreparedDishBatch] {
        let groupedDict = Dictionary(grouping: filteredDishes) { PreparedDishBatch.identityKey(for: $0) }
        return groupedDict.map { _, groupedDishes -> PreparedDishBatch in
            let sortedDishes = groupedDishes.sorted { left, right in
                // Sort by use-by date ascending (nil last)
                switch (left.useByDate, right.useByDate) {
                case let (l?, r?): return l < r
                case (nil, .some): return false
                case (.some, nil): return true
                case (nil, nil): return left.dateAdded > right.dateAdded
                }
            }
            return PreparedDishBatch(dishes: sortedDishes)
        }
        .sorted { left, right in
            // Sort batches by earliest use-by date
            switch (left.earliestUseBy, right.earliestUseBy) {
            case let (l?, r?): return l < r
            case (nil, .some): return false
            case (.some, nil): return true
            case (nil, nil): return left.representativeDish.name < right.representativeDish.name
            }
        }
    }

    var filteredHistoryItems: [PreparedDishHistoryItem] {
        var items = SearchQuerySupport.filtered(appState.preparedDishHistory, query: debouncedSearchText) { item in
            [item.name, item.mealTypesSummary].joined(separator: " ")
        }

        if let selectedMealType {
            items = items.filter { $0.mealTypes.contains(selectedMealType) }
        }

        return items.sorted { lhs, rhs in
            if lhs.recipeID != rhs.recipeID {
                return lhs.recipeID != nil
            }
            return lhs.lastUsedAt > rhs.lastUsedAt
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

    func addServing(_ dish: PreparedDish) {
        runTask { [self] in
            guard let currentDish = appState.preparedDishById(dish.id) else { return }

            _ = await preparedDishActions.adjustServings(currentDish, delta: 1)
            if let updatedDish = appState.preparedDishById(dish.id) {
                let remainingText = updatedDish.servingsRemaining == 1 ? "1 serving ready" : "\(updatedDish.servingsRemaining) servings ready"
                presentFeedback("Added 1 serving to \(updatedDish.name). \(remainingText).")
            }
        }
    }

    func consumeServing(_ dish: PreparedDish) {
        runTask { [self] in
            guard let currentDish = appState.preparedDishById(dish.id) else { return }

            let removed = await preparedDishActions.adjustServings(currentDish, delta: -1)
            if removed {
                presentFeedback("Finished \(currentDish.name). Removed from Prepared Dishes.")
            } else if let updatedDish = appState.preparedDishById(dish.id) {
                let remainingText = updatedDish.servingsRemaining == 1 ? "1 serving left" : "\(updatedDish.servingsRemaining) servings left"
                presentFeedback("Used 1 serving of \(updatedDish.name). \(remainingText).")
            }
        }
    }

    private func presentFeedback(_ message: String) {
        feedbackDismissTask?.cancel()
        feedbackBanner = FeedbackBanner(message: message)

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        feedbackDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            feedbackBanner = nil
        }
    }
}