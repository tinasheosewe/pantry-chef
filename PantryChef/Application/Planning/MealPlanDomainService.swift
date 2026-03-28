import Foundation

@MainActor
protocol MealPlanDomainState: AnyObject {
    var mealPlan: [MealPlanEntry] { get set }
    var storageService: StorageServiceProtocol { get }

    func pushError(_ error: AppError)
    func preparedDishById(_ id: UUID) -> PreparedDish?
    func matchingPreparedDishes(for entry: MealPlanEntry) -> [PreparedDish]
    func adjustPreparedDishServings(_ dish: PreparedDish, delta: Int) async -> Bool
    func setMealPlanEntries(_ entries: [MealPlanEntry])
    func markMealPlanChanged()
}

@MainActor
protocol MealPlanDomainServicing {
    func mealLoggingRequests(from selections: [MealPlanEatenLoggingSelection], state: any MealPlanDomainState) -> [MealPlanEatenLoggingRequest]
    func validateMealLoggingRequests(_ requests: [MealPlanEatenLoggingRequest], state: any MealPlanDomainState) -> Bool
    func applyMealLoggingRequests(_ requests: [MealPlanEatenLoggingRequest], state: any MealPlanDomainState) async -> Bool
    func addToMealPlan(_ entry: MealPlanEntry, replaceExistingSlot: Bool, state: any MealPlanDomainState) async
    func addToMealPlan(_ entries: [MealPlanEntry], replaceExistingSlot: Bool, state: any MealPlanDomainState) async
    func removeFromMealPlan(_ entry: MealPlanEntry, state: any MealPlanDomainState) async
    func updateMealPlanEntry(_ entry: MealPlanEntry, state: any MealPlanDomainState) async
    func logMealPlanEntriesEaten(_ selections: [MealPlanEatenLoggingSelection], state: any MealPlanDomainState) async
    func logMealPlanEntriesEaten(_ entries: [MealPlanEntry], state: any MealPlanDomainState) async
    func stampCookedMealPlanEntriesByRecipe(_ recipeID: UUID, state: any MealPlanDomainState) async
    func stampCookedMealPlanEntries(_ entryIDs: [UUID], state: any MealPlanDomainState) async
    func sanitizeMealPlanEntries(_ entries: [MealPlanEntry]) -> SanitizedMealPlan
    func purgeMealPlanEntries(_ entries: [MealPlanEntry], state: any MealPlanDomainState) async
    func isSameMealSlot(_ lhs: MealPlanEntry, _ rhs: MealPlanEntry) -> Bool
}

@MainActor
struct MealPlanDomainService: MealPlanDomainServicing {
    func mealLoggingRequests(
        from selections: [MealPlanEatenLoggingSelection],
        state: any MealPlanDomainState
    ) -> [MealPlanEatenLoggingRequest] {
        selections.compactMap { selection -> MealPlanEatenLoggingRequest? in
            guard let currentEntry = state.mealPlan.first(where: { $0.id == selection.entryID }) else { return nil }
            guard currentEntry.supportsMealLogging else { return nil }

            let currentEatenServings = currentEntry.effectiveEatenServings
            let targetEatenServings = Swift.max(currentEatenServings, selection.targetEatenServings)
            guard targetEatenServings > currentEatenServings else { return nil }

            return MealPlanEatenLoggingRequest(
                entry: currentEntry,
                targetEatenServings: targetEatenServings,
                preparedDishID: selection.preparedDishID
            )
        }
    }

    func validateMealLoggingRequests(_ requests: [MealPlanEatenLoggingRequest], state: any MealPlanDomainState) -> Bool {
        let requestedServingsByPreparedDishID = requests.reduce(into: [UUID: Int]()) { partialResult, request in
            guard request.additionalServings > 0 else { return }
            guard let preparedDishID = request.preparedDishID else { return }
            partialResult[preparedDishID, default: 0] += request.additionalServings
        }

        for request in requests where request.additionalServings > 0 {
            guard let preparedDishID = request.preparedDishID else {
                state.pushError(.validation("Choose which Prepared Food item was eaten before saving."))
                return false
            }

            let matchingDishIDs = Set(state.matchingPreparedDishes(for: request.entry).map(\.id))
            guard matchingDishIDs.contains(preparedDishID) else {
                state.pushError(.validation("The selected Prepared Food item no longer matches \(request.entry.displayName)."))
                return false
            }
        }

        for (preparedDishID, requestedServings) in requestedServingsByPreparedDishID {
            guard let preparedDish = state.preparedDishById(preparedDishID) else { continue }
            guard requestedServings <= preparedDish.servingsRemaining else {
                state.pushError(.validation("Not enough servings remain in \(preparedDish.name) to log those meals as eaten."))
                return false
            }
        }

        return true
    }

    func applyMealLoggingRequests(_ requests: [MealPlanEatenLoggingRequest], state: any MealPlanDomainState) async -> Bool {
        for request in requests {
            if request.additionalServings > 0, let preparedDishID = request.preparedDishID {
                if let currentPreparedDish = state.preparedDishById(preparedDishID) {
                    _ = await state.adjustPreparedDishServings(currentPreparedDish, delta: -request.additionalServings)
                }
            }

            do {
                let updatedEntry = request.entry.updatingEatenServings(request.targetEatenServings)
                let saved = try await state.storageService.updateMealPlanEntry(updatedEntry)
                if let index = state.mealPlan.firstIndex(where: { $0.id == saved.id }) {
                    state.mealPlan[index] = saved
                }
            } catch {
                state.pushError(.storage(error))
                return false
            }
        }

        return true
    }

    func addToMealPlan(_ entry: MealPlanEntry, replaceExistingSlot: Bool, state: any MealPlanDomainState) async {
        await addToMealPlan([entry], replaceExistingSlot: replaceExistingSlot, state: state)
    }

    func addToMealPlan(_ entries: [MealPlanEntry], replaceExistingSlot: Bool, state: any MealPlanDomainState) async {
        let plannedEntries = entries.filter(\.isPlanned)
        guard !plannedEntries.isEmpty else { return }

        do {
            if replaceExistingSlot, let slotSeed = plannedEntries.first {
                let conflictingEntries = state.mealPlan.filter { isSameMealSlot($0, slotSeed) }
                for conflict in conflictingEntries {
                    try await state.storageService.deleteMealPlanEntry(conflict)
                }
                state.mealPlan.removeAll { isSameMealSlot($0, slotSeed) }
            }

            for entry in plannedEntries {
                let saved = try await state.storageService.addMealPlanEntry(entry)
                state.mealPlan.append(saved)
            }

            state.setMealPlanEntries(sanitizeMealPlanEntries(state.mealPlan).visibleEntries)
        } catch {
            state.pushError(.storage(error))
        }
    }

    func removeFromMealPlan(_ entry: MealPlanEntry, state: any MealPlanDomainState) async {
        do {
            try await state.storageService.deleteMealPlanEntry(entry)
            let originalCount = state.mealPlan.count
            state.mealPlan.removeAll { $0.id == entry.id }
            if state.mealPlan.count != originalCount {
                state.markMealPlanChanged()
            }
        } catch {
            state.pushError(.storage(error))
        }
    }

    func updateMealPlanEntry(_ entry: MealPlanEntry, state: any MealPlanDomainState) async {
        do {
            let updated = try await state.storageService.updateMealPlanEntry(entry)
            if let index = state.mealPlan.firstIndex(where: { $0.id == entry.id }) {
                state.mealPlan[index] = updated
                state.setMealPlanEntries(sanitizeMealPlanEntries(state.mealPlan).visibleEntries)
            }
        } catch {
            state.pushError(.storage(error))
        }
    }

    func logMealPlanEntriesEaten(_ selections: [MealPlanEatenLoggingSelection], state: any MealPlanDomainState) async {
        let requests = mealLoggingRequests(from: selections, state: state)

        guard !requests.isEmpty else { return }

        guard validateMealLoggingRequests(requests, state: state) else { return }
        guard await applyMealLoggingRequests(requests, state: state) else { return }

        state.setMealPlanEntries(sanitizeMealPlanEntries(state.mealPlan).visibleEntries)
    }

    func logMealPlanEntriesEaten(_ entries: [MealPlanEntry], state: any MealPlanDomainState) async {
        let selections = entries.map { entry in
            MealPlanEatenLoggingSelection(
                entryID: entry.id,
                targetEatenServings: entry.effectiveEatenServings,
                preparedDishID: entry.preparedDish?.id
            )
        }
        await logMealPlanEntriesEaten(selections, state: state)
    }

    func stampCookedMealPlanEntriesByRecipe(_ recipeID: UUID, state: any MealPlanDomainState) async {
        let entryIDs = state.mealPlan
            .filter { $0.recipe?.id == recipeID && $0.cookedAt == nil }
            .map(\.id)
        await stampCookedMealPlanEntries(entryIDs, state: state)
    }

    func stampCookedMealPlanEntries(_ entryIDs: [UUID], state: any MealPlanDomainState) async {
        guard !entryIDs.isEmpty else { return }
        let now = Date()
        for entryID in entryIDs {
            guard var entry = state.mealPlan.first(where: { $0.id == entryID }),
                  entry.cookedAt == nil else { continue }
            entry.cookedAt = now
            await updateMealPlanEntry(entry, state: state)
        }
    }

    func sanitizeMealPlanEntries(_ entries: [MealPlanEntry]) -> SanitizedMealPlan {
        var removedEntries: [MealPlanEntry] = []
        var visibleEntries: [MealPlanEntry] = []

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard entry.isPlanned else {
                removedEntries.append(entry)
                continue
            }
            visibleEntries.append(entry)
        }

        visibleEntries.sort { lhs, rhs in
            if Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) {
                if lhs.mealType == rhs.mealType {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.mealType.rawValue < rhs.mealType.rawValue
            }
            return lhs.date < rhs.date
        }

        return SanitizedMealPlan(visibleEntries: visibleEntries, removedEntries: removedEntries)
    }

    func purgeMealPlanEntries(_ entries: [MealPlanEntry], state: any MealPlanDomainState) async {
        guard !entries.isEmpty else { return }

        for entry in entries {
            do {
                try await state.storageService.deleteMealPlanEntry(entry)
            } catch {
                AppLog.warn("[MealPlanDomainService] Failed to purge invalid meal plan entry \(entry.id.uuidString): \(error.localizedDescription)")
            }
        }
    }

    func isSameMealSlot(_ lhs: MealPlanEntry, _ rhs: MealPlanEntry) -> Bool {
        Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) && lhs.mealType == rhs.mealType
    }
}

@MainActor
extension AppState: MealPlanDomainState {}