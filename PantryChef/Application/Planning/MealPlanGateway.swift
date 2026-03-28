import Foundation

@MainActor
protocol MealPlanGatewayProtocol {
    func planRecipe(_ recipe: Recipe, on date: Date, mealType: MealType, replaceExisting: Bool) async
    func planPreparedDish(_ dish: PreparedDish, on date: Date, mealType: MealType, replaceExisting: Bool) async
    func planSelections(_ selections: [MealSelectionItem], on date: Date, mealType: MealType, replaceExisting: Bool) async
    func removeEntries(_ entries: [MealPlanEntry]) async
    func updateEntry(_ entry: MealPlanEntry) async
    func logEntriesEaten(_ selections: [MealPlanEatenLoggingSelection]) async
    func addShoppingItems(_ items: [ShoppingItem]) async
    func addPreparedDishes(_ dishes: [PreparedDish]) async
    func addEntriesToCookQueue(_ entries: [MealPlanEntry], asParallelBatch: Bool) async
}

@MainActor
struct MealPlanGateway: MealPlanGatewayProtocol {
    private unowned let appState: AppState
    private let mealPlanDomainService: any MealPlanDomainServicing

    init(appState: AppState, mealPlanDomainService: any MealPlanDomainServicing) {
        self.appState = appState
        self.mealPlanDomainService = mealPlanDomainService
    }

    func planRecipe(_ recipe: Recipe, on date: Date, mealType: MealType, replaceExisting: Bool) async {
        let entry = MealPlanEntry(date: date, mealType: mealType, recipe: recipe)
        await mealPlanDomainService.addToMealPlan(entry, replaceExistingSlot: replaceExisting, state: appState)
    }

    func planPreparedDish(_ dish: PreparedDish, on date: Date, mealType: MealType, replaceExisting: Bool) async {
        let entry = MealPlanEntry(date: date, mealType: mealType, preparedDish: dish, plannedServings: 1)
        await mealPlanDomainService.addToMealPlan(entry, replaceExistingSlot: replaceExisting, state: appState)
    }

    func planSelections(_ selections: [MealSelectionItem], on date: Date, mealType: MealType, replaceExisting: Bool) async {
        let entries = selections.map { $0.makeEntry(date: date, mealType: mealType) }
        await mealPlanDomainService.addToMealPlan(entries, replaceExistingSlot: replaceExisting, state: appState)
    }

    func removeEntries(_ entries: [MealPlanEntry]) async {
        for entry in entries {
            await mealPlanDomainService.removeFromMealPlan(entry, state: appState)
        }
    }

    func updateEntry(_ entry: MealPlanEntry) async {
        await mealPlanDomainService.updateMealPlanEntry(entry, state: appState)
    }

    func logEntriesEaten(_ selections: [MealPlanEatenLoggingSelection]) async {
        await mealPlanDomainService.logMealPlanEntriesEaten(selections, state: appState)
    }

    func addShoppingItems(_ items: [ShoppingItem]) async {
        await appState.inventoryGateway.addShoppingItems(items)
    }

    func addPreparedDishes(_ dishes: [PreparedDish]) async {
        await appState.inventoryGateway.addPreparedDishes(dishes)
    }

    func addEntriesToCookQueue(_ entries: [MealPlanEntry], asParallelBatch: Bool) async {
        let recipes = entries.compactMap(\.scaledRecipeForPlanning)
        await appState.cookGateway.addRecipesToQueue(recipes, asParallelBatch: asParallelBatch, sourceEntries: entries)
    }
}

@MainActor
extension AppState {
    var mealPlanGateway: any MealPlanGatewayProtocol {
        MealPlanGateway(appState: self, mealPlanDomainService: mealPlanDomainService)
    }
}