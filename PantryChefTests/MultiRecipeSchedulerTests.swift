import XCTest
@testable import PantryChef

final class MultiRecipeSchedulerTests: XCTestCase {

    // MARK: - Single Recipe (no LLM)

    func testSingleRecipeProducesLinearBlocks() async throws {
        let ai = MockAIService()
        let recipe = makeRecipe(
            title: "Simple Pasta",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Boil water", estimatedDurationSeconds: 300),
                RecipeStep(stepNumber: 2, instruction: "Cook pasta", estimatedDurationSeconds: 600),
                RecipeStep(stepNumber: 3, instruction: "Drain and serve", estimatedDurationSeconds: 60)
            ]
        )

        let blocks = try await MultiRecipeScheduler.schedule(recipes: [recipe], aiService: ai)

        XCTAssertEqual(blocks.count, 3, "Single recipe should produce one block per step")
        XCTAssertEqual(blocks[0].displayInstruction, "Boil water")
        XCTAssertEqual(blocks[1].displayInstruction, "Cook pasta")
        XCTAssertEqual(blocks[2].displayInstruction, "Drain and serve")
        // LLM should NOT be called for single recipe
        XCTAssertEqual(ai.generateBatchScheduleCallCount, 0)
    }

    func testSingleRecipePassiveBlockIsMarkedPassive() async throws {
        let passiveID = UUID()
        let activeID = UUID()
        let recipe = makeRecipe(
            title: "Bake Test",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Bake", estimatedDurationSeconds: 1800, timerMinutes: 30, tasks: [
                    StepTask(id: passiveID, action: .bake, ingredient: "casserole", durationSeconds: 1800, type: .passive)
                ]),
                RecipeStep(stepNumber: 2, instruction: "Chop herbs", estimatedDurationSeconds: 90, tasks: [
                    StepTask(id: activeID, action: .cut(.chop), ingredient: "herbs", durationSeconds: 90, type: .active)
                ])
            ]
        )

        let blocks = try await MultiRecipeScheduler.schedule(recipes: [recipe], aiService: MockAIService())

        XCTAssertEqual(blocks[0].type, .passive, "Block with only passive tasks should be passive")
        XCTAssertEqual(blocks[0].tasks.first?.id, passiveID)
        XCTAssertEqual(blocks[1].type, .active)
        XCTAssertEqual(blocks[1].tasks.first?.id, activeID)
    }

    // MARK: - Multi Recipe (LLM-powered)

    func testMultiRecipeCallsLLMAndMapsBlocks() async throws {
        let taskA = UUID()
        let taskB = UUID()
        let taskC = UUID()

        let recipe1 = makeRecipe(
            title: "Soup",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Chop onion", estimatedDurationSeconds: 120, tasks: [
                    StepTask(id: taskA, action: .cut(.dice), ingredient: "onion", durationSeconds: 120, type: .active)
                ]),
                RecipeStep(stepNumber: 2, instruction: "Simmer", estimatedDurationSeconds: 900, tasks: [
                    StepTask(id: taskB, action: .simmer, ingredient: "soup", durationSeconds: 900, type: .passive)
                ])
            ]
        )
        let recipe2 = makeRecipe(
            title: "Salad",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Toss salad", estimatedDurationSeconds: 60, tasks: [
                    StepTask(id: taskC, action: .toss, ingredient: "salad", durationSeconds: 60, type: .active)
                ])
            ]
        )

        let ai = MockAIService()
        ai.batchScheduleToReturn = LLMBatchSchedule(blocks: [
            .init(taskIDs: [taskA.uuidString, taskC.uuidString], instruction: "Dice the onion for the soup, then quickly toss the salad while it heats.", isPassive: false, durationSeconds: 180),
            .init(taskIDs: [taskB.uuidString], instruction: "Let the soup simmer for 15 minutes.", isPassive: true, durationSeconds: 900)
        ])

        let blocks = try await MultiRecipeScheduler.schedule(recipes: [recipe1, recipe2], aiService: ai)

        XCTAssertEqual(ai.generateBatchScheduleCallCount, 1)
        XCTAssertEqual(blocks.count, 2)

        // First block: merged active tasks
        XCTAssertEqual(blocks[0].tasks.count, 2)
        XCTAssertEqual(blocks[0].type, .active)
        XCTAssertEqual(blocks[0].displayInstruction, "Dice the onion for the soup, then quickly toss the salad while it heats.")
        XCTAssertTrue(blocks[0].recipeNames.contains("Soup"))
        XCTAssertTrue(blocks[0].recipeNames.contains("Salad"))

        // Second block: passive simmer
        XCTAssertEqual(blocks[1].tasks.count, 1)
        XCTAssertEqual(blocks[1].type, .passive)
        XCTAssertEqual(blocks[1].totalDurationSeconds, 900)
    }

    func testMultiRecipeThrowsOnLLMFailure() async {
        let recipe1 = makeRecipe(title: "R1")
        let recipe2 = makeRecipe(title: "R2")

        let ai = MockAIService()
        ai.batchScheduleError = BatchScheduleError.llmRequestFailed

        do {
            _ = try await MultiRecipeScheduler.schedule(recipes: [recipe1, recipe2], aiService: ai)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is BatchScheduleError)
        }
    }

    func testEmptyRecipesReturnsEmpty() async throws {
        let blocks = try await MultiRecipeScheduler.schedule(recipes: [], aiService: MockAIService())
        XCTAssertTrue(blocks.isEmpty)
    }

    // MARK: - Estimate Blocks (synchronous preview)

    func testEstimateBlocksProducesBlocksWithoutLLM() {
        let recipe1 = makeRecipe(
            title: "Pasta",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Boil", estimatedDurationSeconds: 300),
                RecipeStep(stepNumber: 2, instruction: "Sauce", estimatedDurationSeconds: 600)
            ]
        )
        let recipe2 = makeRecipe(
            title: "Salad",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Chop", estimatedDurationSeconds: 120)
            ]
        )

        let blocks = MultiRecipeScheduler.estimateBlocks(recipes: [recipe1, recipe2])

        XCTAssertFalse(blocks.isEmpty, "Estimate should produce blocks for preview")
        // Each block should have tasks
        for block in blocks {
            XCTAssertFalse(block.tasks.isEmpty)
        }
    }

    // MARK: - Task Extraction

    func testExtractTasksFillsRecipeMetadata() {
        let recipe = makeRecipe(
            title: "Test",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Mix stuff", estimatedDurationSeconds: 60)
            ]
        )

        let tasks = MultiRecipeScheduler.extractTasks(from: [recipe])

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].recipeName, "Test")
        XCTAssertEqual(tasks[0].sourceStepNumber, 1)
        XCTAssertEqual(tasks[0].recipeId, recipe.id)
    }

    // MARK: - Time Helpers

    func testInterleavedTimeIsLongestRecipe() {
        let recipe1 = makeRecipe(
            title: "Slow",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Braise", estimatedDurationSeconds: 3600)
            ]
        )
        let recipe2 = makeRecipe(
            title: "Fast",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Toss", estimatedDurationSeconds: 300)
            ]
        )

        let interleaved = MultiRecipeScheduler.estimatedInterleavedTime(recipes: [recipe1, recipe2])
        // Should equal the longest recipe, not the sum
        XCTAssertEqual(interleaved, 3600)
    }

    func testTimeSavedCalculation() {
        let recipe1 = makeRecipe(
            title: "Slow",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Braise", estimatedDurationSeconds: 3600)
            ]
        )
        let recipe2 = makeRecipe(
            title: "Fast",
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Toss", estimatedDurationSeconds: 300)
            ]
        )

        let saved = MultiRecipeScheduler.timeSaved(recipes: [recipe1, recipe2])
        // sequential (3900) - interleaved (3600) = 300
        XCTAssertEqual(saved, 300)
    }
}
