import Foundation

// MARK: - Prepared Dish Actions

extension AppState {
    func addPreparedDish(_ dish: PreparedDish) async {
        await preparedDishDomainService.addPreparedDish(dish, state: self)
    }

    func updatePreparedDish(_ dish: PreparedDish) async {
        await preparedDishDomainService.updatePreparedDish(dish, state: self)
    }

    func removePreparedDish(_ dish: PreparedDish) async {
        await preparedDishDomainService.removePreparedDish(dish, state: self)
    }

    @discardableResult
    func adjustPreparedDishServings(_ dish: PreparedDish, delta: Int) async -> Bool {
        await preparedDishDomainService.adjustPreparedDishServings(dish, delta: delta, state: self)
    }

    func preparedDishById(_ id: UUID) -> PreparedDish? {
        preparedDishDomainService.preparedDishById(id, state: self)
    }

    func preparedDishHistoryItem(by id: UUID) -> PreparedDishHistoryItem? {
        preparedDishDomainService.preparedDishHistoryItem(by: id, state: self)
    }

    func addPreparedDishForRecipe(_ recipe: Recipe) async {
        await preparedDishDomainService.addPreparedDishForRecipe(recipe, state: self)
    }

    func refreshPreparedDishHistory(with dish: PreparedDish) {
        preparedDishDomainService.refreshPreparedDishHistory(with: dish, state: self)
    }

    func persistPreparedDishHistory() async {
        await preparedDishDomainService.persistPreparedDishHistory(state: self)
    }
}
