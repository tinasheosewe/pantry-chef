import Foundation

// MARK: - Multi-Recipe Scheduler
//
// LLM-powered scheduler for cooking multiple recipes simultaneously.
// At cook-start, the full task list is sent to the LLM which produces
// an optimal, naturally-worded block sequence. Single-recipe mode uses
// a simple linear conversion (no LLM needed).

struct MultiRecipeScheduler {

    // MARK: - Output Types

    /// A block in the scheduled timeline. May contain tasks from multiple recipes.
    struct ScheduledBlock: Identifiable, Hashable {
        let id: UUID
        let tasks: [StepTask]
        let type: TaskType
        let totalDurationSeconds: Int

        /// Natural-language instruction authored by the LLM.
        let llmInstruction: String

        /// Dominant action class (most common among tasks), used for display.
        var actionClass: ActionClass {
            let classes = tasks.map { $0.action.actionClass }
            let grouped = Dictionary(grouping: classes, by: { $0 })
            return grouped.max(by: { $0.value.count < $1.value.count })?.key ?? .activeCook
        }

        /// Human-readable instruction — returns the LLM-authored text.
        var displayInstruction: String {
            llmInstruction
        }

        /// Short label for the block.
        var label: String {
            actionClass.displayName
        }

        /// All recipe names involved in this block.
        var recipeNames: [String] {
            Array(Set(tasks.compactMap(\.recipeName))).sorted()
        }

        /// Source step info for the original instruction text.
        var sourceInfo: String {
            tasks.compactMap { task -> String? in
                guard let name = task.recipeName, let step = task.sourceStepNumber else { return nil }
                return "\(name) step \(step)"
            }.joined(separator: ", ")
        }
    }

    // MARK: - Schedule (LLM-powered)

    /// Build an interleaved timeline from multiple recipes using the LLM.
    static func schedule(recipes: [Recipe], aiService: AIServiceProtocol) async throws -> [ScheduledBlock] {
        guard !recipes.isEmpty else { return [] }

        // Single recipe: simple linear conversion, no LLM needed
        if recipes.count == 1 {
            return singleRecipeBlocks(recipes[0])
        }

        // Multi-recipe: call the LLM for an optimal schedule
        let allTasks = extractTasks(from: recipes)
        let taskByID = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id.uuidString, $0) })

        let llmSchedule = try await aiService.generateBatchSchedule(recipes: recipes)

        return llmSchedule.blocks.map { block in
            let blockTasks = block.taskIDs.compactMap { taskByID[$0] }
            let type: TaskType = block.isPassive ? .passive : .active
            return ScheduledBlock(
                id: UUID(),
                tasks: blockTasks,
                type: type,
                totalDurationSeconds: block.durationSeconds,
                llmInstruction: block.instruction
            )
        }
    }

    // MARK: - Single Recipe (simple linear)

    private static func singleRecipeBlocks(_ recipe: Recipe) -> [ScheduledBlock] {
        recipe.steps.sorted { $0.stepNumber < $1.stepNumber }.map { step in
            let tasks = step.tasks.isEmpty
                ? [StepTask(action: .other(step.instruction), durationSeconds: step.effectiveDurationSeconds, type: .active, recipeId: recipe.id, recipeName: recipe.title, sourceStepNumber: step.stepNumber)]
                : step.tasks.map { var t = $0; t.recipeId = recipe.id; t.recipeName = recipe.title; t.sourceStepNumber = step.stepNumber; return t }

            let type = tasks.allSatisfy({ $0.type == .passive }) ? TaskType.passive : .active
            let duration = tasks.map(\.durationSeconds).max() ?? step.effectiveDurationSeconds

            return ScheduledBlock(
                id: UUID(),
                tasks: tasks,
                type: type,
                totalDurationSeconds: duration,
                llmInstruction: step.instruction
            )
        }
    }

    // MARK: - Task Extraction

    static func extractTasks(from recipes: [Recipe]) -> [StepTask] {
        var result: [StepTask] = []
        for recipe in recipes {
            for step in recipe.steps.sorted(by: { $0.stepNumber < $1.stepNumber }) {
                if step.tasks.isEmpty {
                    let task = StepTask(
                        action: .other(step.instruction),
                        durationSeconds: step.effectiveDurationSeconds,
                        type: step.timerMinutes != nil ? .passive : .active,
                        recipeId: recipe.id,
                        recipeName: recipe.title,
                        sourceStepNumber: step.stepNumber
                    )
                    result.append(task)
                } else {
                    for var task in step.tasks {
                        task.recipeId = recipe.id
                        task.recipeName = recipe.title
                        task.sourceStepNumber = step.stepNumber
                        result.append(task)
                    }
                }
            }
        }
        return result
    }

    // MARK: - Quick Estimate (synchronous, no LLM)

    /// Produces a rough block estimate for preview UI — NOT used for cooking.
    /// Returns one block per recipe step to give a ballpark step count.
    static func estimateBlocks(recipes: [Recipe]) -> [ScheduledBlock] {
        guard recipes.count > 1 else {
            if let recipe = recipes.first { return singleRecipeBlocks(recipe) }
            return []
        }
        let tasks = extractTasks(from: recipes)
        let grouped = Dictionary(grouping: tasks, by: { $0.action.actionClass.phasePriority })
        return grouped.keys.sorted().compactMap { phase -> ScheduledBlock? in
            guard let phaseTasks = grouped[phase], !phaseTasks.isEmpty else { return nil }
            let isPassive = phaseTasks.allSatisfy { $0.type == .passive }
            let duration = phaseTasks.map(\.durationSeconds).max() ?? 0
            let instruction = phaseTasks.map { $0.displayText }.joined(separator: "; ")
            return ScheduledBlock(
                id: UUID(),
                tasks: phaseTasks,
                type: isPassive ? .passive : .active,
                totalDurationSeconds: duration,
                llmInstruction: instruction
            )
        }
    }

    // MARK: - Time Estimates

    /// Individual recipe time in seconds using step-level durations.
    private static func recipeTimeSeconds(_ recipe: Recipe) -> Int {
        if let total = recipe.totalTimeMinutes { return total * 60 }
        return recipe.steps.reduce(0) { $0 + $1.effectiveDurationSeconds }
    }

    /// Estimated interleaved time = longest recipe (assumes full parallelism).
    static func estimatedInterleavedTime(recipes: [Recipe]) -> Int {
        recipes.map { recipeTimeSeconds($0) }.max() ?? 0
    }

    /// Sequential baseline = sum of every recipe cooked back-to-back.
    static func sequentialTime(recipes: [Recipe]) -> Int {
        recipes.reduce(0) { $0 + recipeTimeSeconds($1) }
    }

    /// Time saved by interleaving.
    static func timeSaved(recipes: [Recipe]) -> Int {
        max(0, sequentialTime(recipes: recipes) - estimatedInterleavedTime(recipes: recipes))
    }
}

