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
    private let cookQueueDomainService: any CookQueueDomainServicing
    private let mealPlanDomainService: any MealPlanDomainServicing
    private let preparedDishDomainService: any PreparedDishDomainServicing

    init(
        appState: AppState,
        cookQueueDomainService: any CookQueueDomainServicing,
        mealPlanDomainService: any MealPlanDomainServicing,
        preparedDishDomainService: any PreparedDishDomainServicing
    ) {
        self.appState = appState
        self.cookQueueDomainService = cookQueueDomainService
        self.mealPlanDomainService = mealPlanDomainService
        self.preparedDishDomainService = preparedDishDomainService
    }

    // MARK: - Queue Management

    func addRecipesToQueue(_ recipes: [Recipe], asParallelBatch: Bool = false, sourceEntries: [MealPlanEntry] = []) async {
        await cookQueueDomainService.addRecipesToCookQueue(recipes, asParallelBatch: asParallelBatch, sourceEntries: sourceEntries, state: appState)
    }

    func removeStage(_ stageID: UUID) async {
        await cookQueueDomainService.removeCookQueueStage(stageID, state: appState)
    }

    func clearQueue() async {
        await cookQueueDomainService.clearCookQueue(state: appState)
    }

    func skipStage(_ stageID: UUID) async {
        await cookQueueDomainService.skipCookQueueStage(stageID, state: appState)
    }

    func moveStage(_ stageID: UUID, by offset: Int) async {
        await cookQueueDomainService.moveCookQueueStage(stageID, by: offset, state: appState)
    }

    func bundleStageWithNext(_ stageID: UUID) async {
        await cookQueueDomainService.bundleCookQueueStageWithNext(stageID, state: appState)
    }

    func splitStage(_ stageID: UUID) async {
        await cookQueueDomainService.splitCookQueueStage(stageID, state: appState)
    }

    func startStage(_ stageID: UUID) async {
        await cookQueueDomainService.startCookQueueStage(stageID, state: appState)
    }

    func completeStage(_ stageID: UUID) async {
        await cookQueueDomainService.completeCookQueueStage(stageID, state: appState)
    }

    // MARK: - Cook Completion

    func stampCookedMealPlanEntries(recipeID: UUID) async {
        await mealPlanDomainService.stampCookedMealPlanEntriesByRecipe(recipeID, state: appState)
    }

    func addPreparedDishForRecipe(_ recipe: Recipe) async {
        await preparedDishDomainService.addPreparedDishForRecipe(recipe, state: appState)
    }
}

@MainActor
extension AppState {
    var cookGateway: any CookGatewayProtocol {
        CookGateway(
            appState: self,
            cookQueueDomainService: cookQueueDomainService,
            mealPlanDomainService: mealPlanDomainService,
            preparedDishDomainService: preparedDishDomainService
        )
    }
}
