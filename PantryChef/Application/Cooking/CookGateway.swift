import Foundation

@MainActor
protocol CookGatewayProtocol {
    // Queue management
    func addRecipesToQueue(_ recipes: [Recipe], asParallelBatch: Bool, sourceEntries: [MealPlanEntry]) async
    func removeStage(_ stageID: UUID) async
    func clearQueue() async
    func skipStage(_ stageID: UUID) async
    func moveStage(_ stageID: UUID, by offset: Int) async
    func bundleStageWithNext(_ stageID: UUID) async
    func splitStage(_ stageID: UUID) async
    func startStage(_ stageID: UUID) async
    func completeStage(_ stageID: UUID) async

    // Cook completion
    func stampCookedMealPlanEntries(recipeID: UUID) async
    func addPreparedDishForRecipe(_ recipe: Recipe) async
}

@MainActor
struct CookGateway: CookGatewayProtocol {
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Queue Management

    func addRecipesToQueue(_ recipes: [Recipe], asParallelBatch: Bool = false, sourceEntries: [MealPlanEntry] = []) async {
        await appState.addRecipesToCookQueue(recipes, asParallelBatch: asParallelBatch, sourceEntries: sourceEntries)
    }

    func removeStage(_ stageID: UUID) async {
        await appState.removeCookQueueStage(stageID)
    }

    func clearQueue() async {
        await appState.clearCookQueue()
    }

    func skipStage(_ stageID: UUID) async {
        await appState.skipCookQueueStage(stageID)
    }

    func moveStage(_ stageID: UUID, by offset: Int) async {
        await appState.moveCookQueueStage(stageID, by: offset)
    }

    func bundleStageWithNext(_ stageID: UUID) async {
        await appState.bundleCookQueueStageWithNext(stageID)
    }

    func splitStage(_ stageID: UUID) async {
        await appState.splitCookQueueStage(stageID)
    }

    func startStage(_ stageID: UUID) async {
        await appState.startCookQueueStage(stageID)
    }

    func completeStage(_ stageID: UUID) async {
        await appState.completeCookQueueStage(stageID)
    }

    // MARK: - Cook Completion

    func stampCookedMealPlanEntries(recipeID: UUID) async {
        await appState.stampCookedMealPlanEntriesByRecipe(recipeID)
    }

    func addPreparedDishForRecipe(_ recipe: Recipe) async {
        await appState.addPreparedDishForRecipe(recipe)
    }
}

@MainActor
extension AppState {
    var cookGateway: any CookGatewayProtocol {
        CookGateway(appState: self)
    }
}
