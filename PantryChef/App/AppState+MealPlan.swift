import Foundation

// MARK: - Meal Plan Actions

extension AppState {
    func mealLoggingRequests(from selections: [MealPlanEatenLoggingSelection]) -> [MealPlanEatenLoggingRequest] {
        mealPlanDomainService.mealLoggingRequests(from: selections, state: self)
    }

    func validateMealLoggingRequests(_ requests: [MealPlanEatenLoggingRequest]) -> Bool {
        mealPlanDomainService.validateMealLoggingRequests(requests, state: self)
    }

    func applyMealLoggingRequests(_ requests: [MealPlanEatenLoggingRequest]) async -> Bool {
        await mealPlanDomainService.applyMealLoggingRequests(requests, state: self)
    }

    func addToMealPlan(_ entry: MealPlanEntry, replaceExistingSlot: Bool = false) async {
        await mealPlanDomainService.addToMealPlan(entry, replaceExistingSlot: replaceExistingSlot, state: self)
    }

    func addToMealPlan(_ entries: [MealPlanEntry], replaceExistingSlot: Bool = false) async {
        await mealPlanDomainService.addToMealPlan(entries, replaceExistingSlot: replaceExistingSlot, state: self)
    }

    func removeFromMealPlan(_ entry: MealPlanEntry) async {
        await mealPlanDomainService.removeFromMealPlan(entry, state: self)
    }

    func updateMealPlanEntry(_ entry: MealPlanEntry) async {
        await mealPlanDomainService.updateMealPlanEntry(entry, state: self)
    }

    func logMealPlanEntriesEaten(_ selections: [MealPlanEatenLoggingSelection]) async {
        await mealPlanDomainService.logMealPlanEntriesEaten(selections, state: self)
    }

    func logMealPlanEntriesEaten(_ entries: [MealPlanEntry]) async {
        await mealPlanDomainService.logMealPlanEntriesEaten(entries, state: self)
    }

    func stampCookedMealPlanEntriesByRecipe(_ recipeID: UUID) async {
        await mealPlanDomainService.stampCookedMealPlanEntriesByRecipe(recipeID, state: self)
    }

    func stampCookedMealPlanEntries(_ entryIDs: [UUID]) async {
        await mealPlanDomainService.stampCookedMealPlanEntries(entryIDs, state: self)
    }

    func sanitizeMealPlanEntries(_ entries: [MealPlanEntry]) -> SanitizedMealPlan {
        mealPlanDomainService.sanitizeMealPlanEntries(entries)
    }

    func purgeMealPlanEntries(_ entries: [MealPlanEntry]) async {
        await mealPlanDomainService.purgeMealPlanEntries(entries, state: self)
    }

    func isSameMealSlot(_ lhs: MealPlanEntry, _ rhs: MealPlanEntry) -> Bool {
        mealPlanDomainService.isSameMealSlot(lhs, rhs)
    }
}
