import Foundation

@MainActor
protocol CookQueueDomainState: AnyObject {
    var cookQueue: CookQueue? { get }
    var storageService: StorageServiceProtocol { get }

    func pushError(_ error: AppError)
    func setCookQueueValue(_ queue: CookQueue?)
    func stampCookedMealPlanEntries(_ entryIDs: [UUID]) async
}

@MainActor
protocol CookQueueDomainServicing {
    func addRecipesToCookQueue(_ recipes: [Recipe], asParallelBatch: Bool, sourceEntries: [MealPlanEntry], state: any CookQueueDomainState) async
    func moveCookQueueStage(_ stageID: UUID, by offset: Int, state: any CookQueueDomainState) async
    func bundleCookQueueStageWithNext(_ stageID: UUID, state: any CookQueueDomainState) async
    func splitCookQueueStage(_ stageID: UUID, state: any CookQueueDomainState) async
    func startCookQueueStage(_ stageID: UUID, state: any CookQueueDomainState) async
    func completeCookQueueStage(_ stageID: UUID, state: any CookQueueDomainState) async
    func skipCookQueueStage(_ stageID: UUID, state: any CookQueueDomainState) async
    func removeCookQueueStage(_ stageID: UUID, state: any CookQueueDomainState) async
    func clearCookQueue(state: any CookQueueDomainState) async
    func replaceCookQueueStages(_ stages: [CookQueueStage], name: String?, state: any CookQueueDomainState) async
    func appendCookQueueStages(_ stages: [CookQueueStage], name: String?, state: any CookQueueDomainState) async
    func persistCookQueue(state: any CookQueueDomainState) async
}

@MainActor
struct CookQueueDomainService: CookQueueDomainServicing {
    func addRecipesToCookQueue(_ recipes: [Recipe], asParallelBatch: Bool = false, sourceEntries: [MealPlanEntry] = [], state: any CookQueueDomainState) async {
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

        if var existingQueue = state.cookQueue {
            existingQueue.appendStages(newStages)
            state.setCookQueueValue(existingQueue)
        } else {
            state.setCookQueueValue(CookQueue(stages: newStages))
        }

        await persistCookQueue(state: state)
    }

    func moveCookQueueStage(_ stageID: UUID, by offset: Int, state: any CookQueueDomainState) async {
        guard var queue = state.cookQueue else { return }
        queue.moveStage(stageID, by: offset)
        state.setCookQueueValue(queue)
        await persistCookQueue(state: state)
    }

    func bundleCookQueueStageWithNext(_ stageID: UUID, state: any CookQueueDomainState) async {
        guard var queue = state.cookQueue else { return }
        queue.bundleStageWithNext(stageID)
        state.setCookQueueValue(queue)
        await persistCookQueue(state: state)
    }

    func splitCookQueueStage(_ stageID: UUID, state: any CookQueueDomainState) async {
        guard var queue = state.cookQueue else { return }
        queue.splitStage(stageID)
        state.setCookQueueValue(queue)
        await persistCookQueue(state: state)
    }

    func startCookQueueStage(_ stageID: UUID, state: any CookQueueDomainState) async {
        guard var queue = state.cookQueue else { return }
        queue.startStage(stageID)
        state.setCookQueueValue(queue)
        await persistCookQueue(state: state)
    }

    func completeCookQueueStage(_ stageID: UUID, state: any CookQueueDomainState) async {
        guard var queue = state.cookQueue else { return }

        if let stage = queue.stages.first(where: { $0.id == stageID }) {
            await state.stampCookedMealPlanEntries(stage.sourceMealPlanEntryIDs)
        }

        queue.completeStage(stageID)
        state.setCookQueueValue(queue.isEmpty ? nil : queue)
        await persistCookQueue(state: state)
    }

    func skipCookQueueStage(_ stageID: UUID, state: any CookQueueDomainState) async {
        guard var queue = state.cookQueue else { return }
        queue.skipStage(stageID)
        state.setCookQueueValue(queue.isEmpty ? nil : queue)
        await persistCookQueue(state: state)
    }

    func removeCookQueueStage(_ stageID: UUID, state: any CookQueueDomainState) async {
        guard var queue = state.cookQueue else { return }
        queue.removeStage(stageID)
        state.setCookQueueValue(queue.stages.isEmpty ? nil : queue)
        await persistCookQueue(state: state)
    }

    func clearCookQueue(state: any CookQueueDomainState) async {
        state.setCookQueueValue(nil)
        await persistCookQueue(state: state)
    }

    func replaceCookQueueStages(_ stages: [CookQueueStage], name: String? = nil, state: any CookQueueDomainState) async {
        let normalizedStages = stages.filter { !$0.recipeIDs.isEmpty }

        guard !normalizedStages.isEmpty else {
            state.setCookQueueValue(nil)
            await persistCookQueue(state: state)
            return
        }

        if var existingQueue = state.cookQueue {
            existingQueue.name = name ?? existingQueue.name
            existingQueue.replaceStages(normalizedStages)
            state.setCookQueueValue(existingQueue)
        } else {
            state.setCookQueueValue(CookQueue(name: name ?? "Cook Queue", stages: normalizedStages))
        }

        await persistCookQueue(state: state)
    }

    func appendCookQueueStages(_ stages: [CookQueueStage], name: String? = nil, state: any CookQueueDomainState) async {
        let normalizedStages = stages.filter { !$0.recipeIDs.isEmpty }
        guard !normalizedStages.isEmpty else { return }

        if var existingQueue = state.cookQueue {
            existingQueue.name = name ?? existingQueue.name
            existingQueue.appendStages(normalizedStages)
            state.setCookQueueValue(existingQueue)
        } else {
            state.setCookQueueValue(CookQueue(name: name ?? "Cook Queue", stages: normalizedStages))
        }

        await persistCookQueue(state: state)
    }

    func persistCookQueue(state: any CookQueueDomainState) async {
        do {
            try await state.storageService.saveCookQueue(state.cookQueue)
        } catch {
            state.pushError(.storage(error))
        }
    }
}

@MainActor
extension AppState: CookQueueDomainState {}