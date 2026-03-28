import Foundation

// MARK: - Prepared Dish Actions

extension AppState {
    func addPreparedDish(_ dish: PreparedDish) async {
        do {
            let saved = try await storageService.addPreparedDish(dish)
            preparedDishes.append(saved)
            markPreparedDishesChanged()
            refreshPreparedDishHistory(with: saved)
            await persistPreparedDishHistory()
        } catch {
            pushError(.storage(error))
        }
    }

    func updatePreparedDish(_ dish: PreparedDish) async {
        do {
            let previousDish = preparedDishes.first(where: { $0.id == dish.id })
            let updated = try await storageService.updatePreparedDish(dish)
            if let index = preparedDishes.firstIndex(where: { $0.id == dish.id }) {
                preparedDishes[index] = updated
                markPreparedDishesChanged()
            }
            if let previousDish {
                let shouldRefreshHistory = previousDish.historyTemplateSignature != updated.historyTemplateSignature
                    || updated.servingsRemaining > previousDish.servingsRemaining
                if shouldRefreshHistory {
                    refreshPreparedDishHistory(with: updated)
                    await persistPreparedDishHistory()
                }
            }
        } catch {
            pushError(.storage(error))
        }
    }

    func removePreparedDish(_ dish: PreparedDish) async {
        do {
            try await storageService.deletePreparedDish(dish)
            let originalDishCount = preparedDishes.count
            preparedDishes.removeAll { $0.id == dish.id }
            if preparedDishes.count != originalDishCount {
                markPreparedDishesChanged()
            }
        } catch {
            pushError(.storage(error))
        }
    }

    @discardableResult
    func adjustPreparedDishServings(_ dish: PreparedDish, delta: Int) async -> Bool {
        guard delta != 0 else { return false }
        guard let currentDish = preparedDishById(dish.id) else { return false }

        let updatedServings = currentDish.servingsRemaining + delta
        if updatedServings <= 0 {
            await removePreparedDish(currentDish)
            return true
        }

        var updatedDish = currentDish
        updatedDish.servingsRemaining = updatedServings
        await updatePreparedDish(updatedDish)
        return false
    }

    func preparedDishById(_ id: UUID) -> PreparedDish? {
        preparedDishes.first { $0.id == id }
    }

    func preparedDishHistoryItem(by id: UUID) -> PreparedDishHistoryItem? {
        preparedDishHistory.first { $0.id == id }
    }

    func addPreparedDishForRecipe(_ recipe: Recipe) async {
        let dish = PreparedDish(
            name: recipe.title,
            mealTypes: [recipe.mealType].compactMap { $0 },
            servingsRemaining: recipe.servings,
            storage: .refrigerated,
            useByDate: PreparedDishFreshnessPolicy.estimatedUseByDate(for: .refrigerated),
            recipeID: recipe.id,
            nutrition: recipe.nutrition
        )
        await addPreparedDish(dish)
    }

    func refreshPreparedDishHistory(with dish: PreparedDish) {
        let existingIndex = preparedDishHistory.firstIndex(where: { historyItem in
            historyItem.matches(dish)
        })

        if let existingIndex {
            preparedDishHistory[existingIndex] = PreparedDishHistoryItem(
                dish: dish,
                previousItem: preparedDishHistory[existingIndex]
            )
        } else {
            preparedDishHistory.append(PreparedDishHistoryItem(dish: dish))
        }

        setPreparedDishHistoryItems(preparedDishHistory)
    }

    func persistPreparedDishHistory() async {
        do {
            try await storageService.savePreparedDishHistory(preparedDishHistory)
        } catch {
            pushError(.storage(error))
        }
    }
}
