import XCTest
@testable import PantryChef

final class MultiRecipeSchedulerTests: XCTestCase {
    func testSchedulerPrefersCriticalPathTaskWhenBudgetIsTight() {
        let longTaskID = UUID()
        let longFollowupID = UUID()
        let shortTaskOneID = UUID()
        let shortTaskTwoID = UUID()
        let shortTaskThreeID = UUID()

        let longRecipe = makeRecipe(
            title: "Long Path",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Start sauce", estimatedDurationSeconds: 60, tasks: [
                    StepTask(id: longTaskID, action: .saute, ingredient: "sauce", durationSeconds: 60, type: .active, effort: .hard)
                ]),
                RecipeStep(stepNumber: 2, instruction: "Finish sauce", estimatedDurationSeconds: 900, tasks: [
                    StepTask(id: longFollowupID, action: .simmer, ingredient: "sauce", durationSeconds: 900, type: .active, effort: .easy, dependsOn: [longTaskID])
                ])
            ]
        )

        let shortRecipes = [shortTaskOneID, shortTaskTwoID, shortTaskThreeID].enumerated().map { index, taskID in
            makeRecipe(
                title: "Short \(index)",
                steps: [
                    RecipeStep(stepNumber: 1, instruction: "Quick prep", estimatedDurationSeconds: 120, tasks: [
                        StepTask(id: taskID, action: .saute, ingredient: "item \(index)", durationSeconds: 120, type: .active, effort: .easy)
                    ])
                ]
            )
        }

        let blocks = MultiRecipeScheduler.schedule(recipes: [longRecipe] + shortRecipes)

        XCTAssertEqual(blocks.first?.tasks.map(\.id), [longTaskID])
    }

    func testSchedulerStillEmitsPassiveTasksImmediately() {
        let passiveID = UUID()
        let activeID = UUID()
        let recipe = makeRecipe(
            title: "Passive First",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Bake", estimatedDurationSeconds: 1800, tasks: [
                    StepTask(id: passiveID, action: .bake, ingredient: "casserole", durationSeconds: 1800, type: .passive)
                ]),
                RecipeStep(stepNumber: 2, instruction: "Chop herbs", estimatedDurationSeconds: 90, tasks: [
                    StepTask(id: activeID, action: .cut(.chop), ingredient: "herbs", durationSeconds: 90, type: .active, effort: .easy)
                ])
            ]
        )

        let blocks = MultiRecipeScheduler.schedule(recipes: [recipe])

        XCTAssertEqual(blocks.first?.tasks.first?.id, passiveID)
        XCTAssertEqual(blocks.dropFirst().first?.tasks.first?.id, activeID)
    }
}