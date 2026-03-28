import Foundation

@MainActor
protocol PreparedDishDomainState: AnyObject {
    var preparedDishes: [PreparedDish] { get }
    var preparedDishHistory: [PreparedDishHistoryItem] { get }
    var storageService: StorageServiceProtocol { get }

    func pushError(_ error: AppError)
    func setPreparedDishes(_ items: [PreparedDish])
    func setPreparedDishHistoryItems(_ items: [PreparedDishHistoryItem])
}

@MainActor
protocol PreparedDishDomainServicing {
    func addPreparedDish(_ dish: PreparedDish, state: any PreparedDishDomainState) async
    func updatePreparedDish(_ dish: PreparedDish, state: any PreparedDishDomainState) async
    func removePreparedDish(_ dish: PreparedDish, state: any PreparedDishDomainState) async
    func adjustPreparedDishServings(_ dish: PreparedDish, delta: Int, state: any PreparedDishDomainState) async -> Bool
    func preparedDishById(_ id: UUID, state: any PreparedDishDomainState) -> PreparedDish?
    func preparedDishHistoryItem(by id: UUID, state: any PreparedDishDomainState) -> PreparedDishHistoryItem?
    func addPreparedDishForRecipe(_ recipe: Recipe, state: any PreparedDishDomainState) async
    func refreshPreparedDishHistory(with dish: PreparedDish, state: any PreparedDishDomainState)
    func persistPreparedDishHistory(state: any PreparedDishDomainState) async
    func syncPreparedDishesLinked(to recipe: Recipe, state: any PreparedDishDomainState) async
}

@MainActor
struct PreparedDishDomainService: PreparedDishDomainServicing {
    func addPreparedDish(_ dish: PreparedDish, state: any PreparedDishDomainState) async {
        do {
            let saved = try await state.storageService.addPreparedDish(dish)
            state.setPreparedDishes(state.preparedDishes + [saved])
            refreshPreparedDishHistory(with: saved, state: state)
            await persistPreparedDishHistory(state: state)
        } catch {
            state.pushError(.storage(error))
        }
    }

    func updatePreparedDish(_ dish: PreparedDish, state: any PreparedDishDomainState) async {
        do {
            let previousDish = state.preparedDishes.first(where: { $0.id == dish.id })
            let updated = try await state.storageService.updatePreparedDish(dish)
            guard let index = state.preparedDishes.firstIndex(where: { $0.id == dish.id }) else { return }

            var dishes = state.preparedDishes
            dishes[index] = updated
            state.setPreparedDishes(dishes)

            if let previousDish {
                let shouldRefreshHistory = previousDish.historyTemplateSignature != updated.historyTemplateSignature
                    || updated.servingsRemaining > previousDish.servingsRemaining
                if shouldRefreshHistory {
                    refreshPreparedDishHistory(with: updated, state: state)
                    await persistPreparedDishHistory(state: state)
                }
            }
        } catch {
            state.pushError(.storage(error))
        }
    }

    func removePreparedDish(_ dish: PreparedDish, state: any PreparedDishDomainState) async {
        do {
            try await state.storageService.deletePreparedDish(dish)
            let updatedDishes = state.preparedDishes.filter { $0.id != dish.id }
            guard updatedDishes.count != state.preparedDishes.count else { return }
            state.setPreparedDishes(updatedDishes)
        } catch {
            state.pushError(.storage(error))
        }
    }

    func adjustPreparedDishServings(_ dish: PreparedDish, delta: Int, state: any PreparedDishDomainState) async -> Bool {
        guard delta != 0 else { return false }
        guard let currentDish = preparedDishById(dish.id, state: state) else { return false }

        let updatedServings = currentDish.servingsRemaining + delta
        if updatedServings <= 0 {
            await removePreparedDish(currentDish, state: state)
            return true
        }

        var updatedDish = currentDish
        updatedDish.servingsRemaining = updatedServings
        await updatePreparedDish(updatedDish, state: state)
        return false
    }

    func preparedDishById(_ id: UUID, state: any PreparedDishDomainState) -> PreparedDish? {
        state.preparedDishes.first { $0.id == id }
    }

    func preparedDishHistoryItem(by id: UUID, state: any PreparedDishDomainState) -> PreparedDishHistoryItem? {
        state.preparedDishHistory.first { $0.id == id }
    }

    func addPreparedDishForRecipe(_ recipe: Recipe, state: any PreparedDishDomainState) async {
        let dish = PreparedDish(
            name: recipe.title,
            mealTypes: [recipe.mealType].compactMap { $0 },
            servingsRemaining: recipe.servings,
            storage: .refrigerated,
            useByDate: PreparedDishFreshnessPolicy.estimatedUseByDate(for: .refrigerated),
            recipeID: recipe.id,
            nutrition: recipe.nutrition
        )
        await addPreparedDish(dish, state: state)
    }

    func refreshPreparedDishHistory(with dish: PreparedDish, state: any PreparedDishDomainState) {
        var items = state.preparedDishHistory
        let existingIndex = items.firstIndex(where: { historyItem in
            historyItem.matches(dish)
        })

        if let existingIndex {
            items[existingIndex] = PreparedDishHistoryItem(
                dish: dish,
                previousItem: items[existingIndex]
            )
        } else {
            items.append(PreparedDishHistoryItem(dish: dish))
        }

        state.setPreparedDishHistoryItems(items)
    }

    func persistPreparedDishHistory(state: any PreparedDishDomainState) async {
        do {
            try await state.storageService.savePreparedDishHistory(state.preparedDishHistory)
        } catch {
            state.pushError(.storage(error))
        }
    }

    func syncPreparedDishesLinked(to recipe: Recipe, state: any PreparedDishDomainState) async {
        let linkedDishes = state.preparedDishes.filter { $0.recipeID == recipe.id }
        guard !linkedDishes.isEmpty else { return }

        var dishes = state.preparedDishes
        var didChange = false

        for dish in linkedDishes {
            var draft = PreparedDishDraft(dish: dish)
            draft.syncLinkedRecipe(recipe)

            guard let syncedDish = draft.buildDish(using: recipe) else { continue }

            do {
                let updatedDish = try await state.storageService.updatePreparedDish(syncedDish)
                if let index = dishes.firstIndex(where: { $0.id == updatedDish.id }) {
                    dishes[index] = updatedDish
                    didChange = true
                }
            } catch {
                state.pushError(.storage(error))
                return
            }
        }

        if didChange {
            state.setPreparedDishes(dishes)
        }
    }
}

@MainActor
extension AppState: PreparedDishDomainState {}