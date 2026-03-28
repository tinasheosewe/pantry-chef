import Foundation

// MARK: - Cook Queue Actions

extension AppState {
    func addRecipesToCookQueue(_ recipes: [Recipe], asParallelBatch: Bool = false, sourceEntries: [MealPlanEntry] = []) async {
        guard !recipes.isEmpty else { return }

        let sourceEntryIDs = sourceEntries.map(\.id)
        let newStages: [CookQueueStage]
        if asParallelBatch {
            newStages = [CookQueueStage(recipes: recipes, sourceMealPlanEntryIDs: sourceEntryIDs)]
        } else {
            newStages = recipes.map { recipe in
                let matchingEntryIDs = sourceEntries
                    .filter { $0.recipe?.id == recipe.id }
                    .map(\.id)
                return CookQueueStage(recipes: [recipe], sourceMealPlanEntryIDs: matchingEntryIDs)
            }
        }

        if var existingQueue = cookQueue {
            existingQueue.appendStages(newStages)
            setCookQueueValue(existingQueue)
        } else {
            setCookQueueValue(CookQueue(stages: newStages))
        }

        await persistCookQueue()
    }

    func moveCookQueueStage(_ stageID: UUID, by offset: Int) async {
        guard var queue = cookQueue else { return }
        queue.moveStage(stageID, by: offset)
        setCookQueueValue(queue)
        await persistCookQueue()
    }

    func bundleCookQueueStageWithNext(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }
        queue.bundleStageWithNext(stageID)
        setCookQueueValue(queue)
        await persistCookQueue()
    }

    func splitCookQueueStage(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }
        queue.splitStage(stageID)
        setCookQueueValue(queue)
        await persistCookQueue()
    }

    func startCookQueueStage(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }
        queue.startStage(stageID)
        setCookQueueValue(queue)
        await persistCookQueue()
    }

    func completeCookQueueStage(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }

        // Stamp cookedAt on linked meal plan entries and auto-create prepared dishes
        if let stage = queue.stages.first(where: { $0.id == stageID }) {
            await stampCookedMealPlanEntries(stage.sourceMealPlanEntryIDs)
        }

        queue.completeStage(stageID)
        setCookQueueValue(queue.isEmpty ? nil : queue)
        await persistCookQueue()
    }

    func skipCookQueueStage(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }
        queue.skipStage(stageID)
        setCookQueueValue(queue.isEmpty ? nil : queue)
        await persistCookQueue()
    }

    func removeCookQueueStage(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }
        queue.removeStage(stageID)
        setCookQueueValue(queue.stages.isEmpty ? nil : queue)
        await persistCookQueue()
    }

    func clearCookQueue() async {
        setCookQueueValue(nil)
        await persistCookQueue()
    }

    func replaceCookQueueStages(_ stages: [CookQueueStage], name: String? = nil) async {
        let normalizedStages = stages.filter { !$0.recipeIDs.isEmpty }

        guard !normalizedStages.isEmpty else {
            setCookQueueValue(nil)
            await persistCookQueue()
            return
        }

        if var existingQueue = cookQueue {
            existingQueue.name = name ?? existingQueue.name
            existingQueue.replaceStages(normalizedStages)
            setCookQueueValue(existingQueue)
        } else {
            setCookQueueValue(CookQueue(name: name ?? "Cook Queue", stages: normalizedStages))
        }

        await persistCookQueue()
    }

    func appendCookQueueStages(_ stages: [CookQueueStage], name: String? = nil) async {
        let normalizedStages = stages.filter { !$0.recipeIDs.isEmpty }
        guard !normalizedStages.isEmpty else { return }

        if var existingQueue = cookQueue {
            existingQueue.name = name ?? existingQueue.name
            existingQueue.appendStages(normalizedStages)
            setCookQueueValue(existingQueue)
        } else {
            setCookQueueValue(CookQueue(name: name ?? "Cook Queue", stages: normalizedStages))
        }

        await persistCookQueue()
    }

    func persistCookQueue() async {
        do {
            try await storageService.saveCookQueue(cookQueue)
        } catch {
            pushError(.storage(error))
        }
    }
}
