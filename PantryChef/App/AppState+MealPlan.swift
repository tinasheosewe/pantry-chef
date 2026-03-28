import Foundation

// MARK: - Meal Plan Actions

extension AppState {
    func mealLoggingRequests(from selections: [MealPlanEatenLoggingSelection]) -> [MealPlanEatenLoggingRequest] {
        selections.compactMap { selection -> MealPlanEatenLoggingRequest? in
            guard let currentEntry = mealPlan.first(where: { $0.id == selection.entryID }) else { return nil }
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

    func validateMealLoggingRequests(_ requests: [MealPlanEatenLoggingRequest]) -> Bool {
        let requestedServingsByPreparedDishID = requests.reduce(into: [UUID: Int]()) { partialResult, request in
            guard request.additionalServings > 0 else { return }
            guard let preparedDishID = request.preparedDishID else { return }
            partialResult[preparedDishID, default: 0] += request.additionalServings
        }

        for request in requests where request.additionalServings > 0 {
            guard let preparedDishID = request.preparedDishID else {
                pushError(.validation("Choose which Prepared Food item was eaten before saving."))
                return false
            }

            let matchingDishIDs = Set(matchingPreparedDishes(for: request.entry).map(\.id))
            guard matchingDishIDs.contains(preparedDishID) else {
                pushError(.validation("The selected Prepared Food item no longer matches \(request.entry.displayName)."))
                return false
            }
        }

        for (preparedDishID, requestedServings) in requestedServingsByPreparedDishID {
            guard let preparedDish = preparedDishById(preparedDishID) else { continue }
            guard requestedServings <= preparedDish.servingsRemaining else {
                pushError(.validation("Not enough servings remain in \(preparedDish.name) to log those meals as eaten."))
                return false
            }
        }

        return true
    }

    func applyMealLoggingRequests(_ requests: [MealPlanEatenLoggingRequest]) async -> Bool {
        for request in requests {
            if request.additionalServings > 0, let preparedDishID = request.preparedDishID {
                if let currentPreparedDish = preparedDishById(preparedDishID) {
                    _ = await adjustPreparedDishServings(currentPreparedDish, delta: -request.additionalServings)
                }
            }

            do {
                let updatedEntry = request.entry.updatingEatenServings(request.targetEatenServings)
                let saved = try await storageService.updateMealPlanEntry(updatedEntry)
                if let index = mealPlan.firstIndex(where: { $0.id == saved.id }) {
                    mealPlan[index] = saved
                }
            } catch {
                pushError(.storage(error))
                return false
            }
        }

        return true
    }

    func addToMealPlan(_ entry: MealPlanEntry, replaceExistingSlot: Bool = false) async {
        await addToMealPlan([entry], replaceExistingSlot: replaceExistingSlot)
    }

    func addToMealPlan(_ entries: [MealPlanEntry], replaceExistingSlot: Bool = false) async {
        let plannedEntries = entries.filter(\.isPlanned)
        guard !plannedEntries.isEmpty else { return }

        do {
            if replaceExistingSlot, let slotSeed = plannedEntries.first {
                let conflictingEntries = mealPlan.filter { isSameMealSlot($0, slotSeed) }
                for conflict in conflictingEntries {
                    try await storageService.deleteMealPlanEntry(conflict)
                }
                mealPlan.removeAll { isSameMealSlot($0, slotSeed) }
            }

            for entry in plannedEntries {
                let saved = try await storageService.addMealPlanEntry(entry)
                mealPlan.append(saved)
            }

            setMealPlanEntries(sanitizeMealPlanEntries(mealPlan).visibleEntries)
        } catch {
            pushError(.storage(error))
        }
    }

    func removeFromMealPlan(_ entry: MealPlanEntry) async {
        do {
            try await storageService.deleteMealPlanEntry(entry)
            let originalCount = mealPlan.count
            mealPlan.removeAll { $0.id == entry.id }
            if mealPlan.count != originalCount {
                markMealPlanChanged()
            }
        } catch {
            pushError(.storage(error))
        }
    }

    func updateMealPlanEntry(_ entry: MealPlanEntry) async {
        do {
            let updated = try await storageService.updateMealPlanEntry(entry)
            if let index = mealPlan.firstIndex(where: { $0.id == entry.id }) {
                mealPlan[index] = updated
                setMealPlanEntries(sanitizeMealPlanEntries(mealPlan).visibleEntries)
            }
        } catch {
            pushError(.storage(error))
        }
    }

    func logMealPlanEntriesEaten(_ selections: [MealPlanEatenLoggingSelection]) async {
        let requests = mealLoggingRequests(from: selections)

        guard !requests.isEmpty else { return }

        guard validateMealLoggingRequests(requests) else { return }
        guard await applyMealLoggingRequests(requests) else { return }

        setMealPlanEntries(sanitizeMealPlanEntries(mealPlan).visibleEntries)
    }

    func logMealPlanEntriesEaten(_ entries: [MealPlanEntry]) async {
        let selections = entries.map { entry in
            MealPlanEatenLoggingSelection(
                entryID: entry.id,
                targetEatenServings: entry.effectiveEatenServings,
                preparedDishID: entry.preparedDish?.id
            )
        }
        await logMealPlanEntriesEaten(selections)
    }

    func stampCookedMealPlanEntriesByRecipe(_ recipeID: UUID) async {
        let entryIDs = mealPlan
            .filter { $0.recipe?.id == recipeID && $0.cookedAt == nil }
            .map(\.id)
        await stampCookedMealPlanEntries(entryIDs)
    }

    func stampCookedMealPlanEntries(_ entryIDs: [UUID]) async {
        guard !entryIDs.isEmpty else { return }
        let now = Date()
        for entryID in entryIDs {
            guard var entry = mealPlan.first(where: { $0.id == entryID }),
                  entry.cookedAt == nil else { continue }
            entry.cookedAt = now
            await updateMealPlanEntry(entry)
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

    func purgeMealPlanEntries(_ entries: [MealPlanEntry]) async {
        guard !entries.isEmpty else { return }

        for entry in entries {
            do {
                try await storageService.deleteMealPlanEntry(entry)
            } catch {
                AppLog.warn("[AppState] Failed to purge invalid meal plan entry \(entry.id.uuidString): \(error.localizedDescription)")
            }
        }
    }

    func isSameMealSlot(_ lhs: MealPlanEntry, _ rhs: MealPlanEntry) -> Bool {
        Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) && lhs.mealType == rhs.mealType
    }
}
