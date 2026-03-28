import Foundation

// MARK: - Cook Queue Actions

extension AppState {
    func addRecipesToCookQueue(_ recipes: [Recipe], asParallelBatch: Bool = false, sourceEntries: [MealPlanEntry] = []) async {
        await cookQueueDomainService.addRecipesToCookQueue(recipes, asParallelBatch: asParallelBatch, sourceEntries: sourceEntries, state: self)
    }

    func moveCookQueueStage(_ stageID: UUID, by offset: Int) async {
        await cookQueueDomainService.moveCookQueueStage(stageID, by: offset, state: self)
    }

    func bundleCookQueueStageWithNext(_ stageID: UUID) async {
        await cookQueueDomainService.bundleCookQueueStageWithNext(stageID, state: self)
    }

    func splitCookQueueStage(_ stageID: UUID) async {
        await cookQueueDomainService.splitCookQueueStage(stageID, state: self)
    }

    func startCookQueueStage(_ stageID: UUID) async {
        await cookQueueDomainService.startCookQueueStage(stageID, state: self)
    }

    func completeCookQueueStage(_ stageID: UUID) async {
        await cookQueueDomainService.completeCookQueueStage(stageID, state: self)
    }

    func skipCookQueueStage(_ stageID: UUID) async {
        await cookQueueDomainService.skipCookQueueStage(stageID, state: self)
    }

    func removeCookQueueStage(_ stageID: UUID) async {
        await cookQueueDomainService.removeCookQueueStage(stageID, state: self)
    }

    func clearCookQueue() async {
        await cookQueueDomainService.clearCookQueue(state: self)
    }

    func replaceCookQueueStages(_ stages: [CookQueueStage], name: String? = nil) async {
        await cookQueueDomainService.replaceCookQueueStages(stages, name: name, state: self)
    }

    func appendCookQueueStages(_ stages: [CookQueueStage], name: String? = nil) async {
        await cookQueueDomainService.appendCookQueueStages(stages, name: name, state: self)
    }

    func persistCookQueue() async {
        await cookQueueDomainService.persistCookQueue(state: self)
    }
}
