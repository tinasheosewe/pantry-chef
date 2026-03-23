import Foundation

// MARK: - Multi-Recipe Scheduler
//
// Generic DAG-based scheduler for cooking multiple recipes simultaneously.
// The LLM builds the dependency graph and assigns effort levels at recipe
// creation time. The scheduler is a dumb executor — it packs ready tasks
// into time slots under an attention budget, using action-class phase
// priority only as a tiebreaker.
//
// Key concepts:
//   1. DAG — task.dependsOn defines hard ordering (built by the LLM).
//   2. Effort budget — up to 3 "effort points" of active work per block.
//      easy=1, medium=2, hard=3, passive=0. Tasks of any class can share a block.
//   3. Phase preference — when multiple tasks are ready and could fill the budget,
//      prefer prep → cook → finish. This gives the natural "chop everything first" feel.
//   4. Passive tasks — emitted as background timer blocks (0 effort cost)
//      and do not block the active work pipeline.

struct MultiRecipeScheduler {

    /// Maximum attention points the cook can handle simultaneously.
    static let effortBudget = 3

    // MARK: - Output Types

    /// A block in the scheduled timeline. May contain tasks from multiple recipes
    /// running in parallel (within the effort budget).
    struct ScheduledBlock: Identifiable, Hashable {
        let id: UUID
        let tasks: [StepTask]
        let type: TaskType
        let totalDurationSeconds: Int

        /// Total effort points consumed by this block.
        var totalEffort: Int {
            tasks.reduce(0) { $0 + $1.effortPoints }
        }

        /// Dominant action class (most common among tasks), used for display.
        var actionClass: ActionClass {
            let classes = tasks.map { $0.action.actionClass }
            let grouped = Dictionary(grouping: classes, by: { $0 })
            return grouped.max(by: { $0.value.count < $1.value.count })?.key ?? .activeCook
        }

        /// Human-readable instruction combining all tasks.
        var displayInstruction: String {
            if tasks.count == 1, let task = tasks.first {
                var text = task.displayText
                if let name = task.recipeName {
                    text += " (\(name))"
                }
                return text
            }
            // Multi-task block
            let grouped = Dictionary(grouping: tasks, by: { $0.recipeName ?? "Unknown" })
            var lines: [String] = []
            for (recipe, recipeTasks) in grouped.sorted(by: { $0.key < $1.key }) {
                let descs = recipeTasks.map { $0.displayText }.joined(separator: ", ")
                lines.append("\(descs) (\(recipe))")
            }
            return lines.joined(separator: "\n")
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

    // MARK: - Schedule

    /// Build an interleaved timeline from multiple recipes.
    static func schedule(recipes: [Recipe]) -> [ScheduledBlock] {
        guard !recipes.isEmpty else { return [] }

        // If single recipe, just convert steps to blocks linearly
        if recipes.count == 1 {
            return singleRecipeBlocks(recipes[0])
        }

        // 1. Extract all tasks with recipe context
        let allTasks = extractTasks(from: recipes)

        // 2. Build dependency graph from task.dependsOn
        let dependencies = buildDependencies(tasks: allTasks)

        // 3. Schedule using effort-budget packing
        return effortPackSchedule(tasks: allTasks, dependencies: dependencies)
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
                totalDurationSeconds: duration
            )
        }
    }

    // MARK: - Task Extraction

    private static func extractTasks(from recipes: [Recipe]) -> [StepTask] {
        var result: [StepTask] = []
        for recipe in recipes {
            for step in recipe.steps.sorted(by: { $0.stepNumber < $1.stepNumber }) {
                if step.tasks.isEmpty {
                    // Wrap the step instruction as a single generic task
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

    // MARK: - Dependency Graph (explicit DAG from recipe data)

    private static func buildDependencies(tasks: [StepTask]) -> [UUID: Set<UUID>] {
        let validIds = Set(tasks.map(\.id))
        var deps: [UUID: Set<UUID>] = [:]
        for task in tasks {
            deps[task.id] = Set(task.dependsOn.filter { validIds.contains($0) })
        }
        return deps
    }

    // MARK: - Effort-Budget Packing Scheduler
    //
    // Algorithm:
    //   1. Find all ready tasks (deps satisfied).
    //   2. Separate passive (background timers, 0 effort) from active.
    //   3. Emit each passive task as its own timer block.
    //   4. Sort active ready tasks by phase priority (tiebreaker), then by effort ascending.
    //   5. Greedily pack active tasks into one block up to `effortBudget` points.
    //   6. Mark completed, repeat.

    private static func effortPackSchedule(tasks: [StepTask], dependencies: [UUID: Set<UUID>]) -> [ScheduledBlock] {
        var timeline: [ScheduledBlock] = []
        var completed = Set<UUID>()
        var remaining = Set(tasks.map(\.id))
        let taskById = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let dependents = buildDependents(dependencies: dependencies)
        let criticalPathLengths = computeCriticalPathLengths(tasks: taskById, dependents: dependents)

        func isReady(_ taskId: UUID) -> Bool {
            (dependencies[taskId] ?? []).isSubset(of: completed)
        }

        var iterations = 0
        let maxIterations = tasks.count * 3

        while !remaining.isEmpty && iterations < maxIterations {
            iterations += 1

            let readyIds = remaining.filter { isReady($0) }
            guard !readyIds.isEmpty else { break }

            let readyTasks = readyIds.compactMap { taskById[$0] }

            // --- Passive tasks: emit as background timer blocks ---
            let passiveTasks = readyTasks.filter { $0.type == .passive }
            for task in passiveTasks {
                timeline.append(ScheduledBlock(
                    id: UUID(),
                    tasks: [task],
                    type: .passive,
                    totalDurationSeconds: task.durationSeconds
                ))
                completed.insert(task.id)
                remaining.remove(task.id)
            }

            // --- Active tasks: effort-budget packing ---
            // Re-check readiness after passive completions may have unlocked new tasks
            let activeReadyIds = remaining.filter { isReady($0) }
            let activeReady = activeReadyIds.compactMap { taskById[$0] }
                .filter { $0.type == .active }
                .sorted {
                    let c0 = criticalPathLengths[$0.id] ?? $0.durationSeconds
                    let c1 = criticalPathLengths[$1.id] ?? $1.durationSeconds
                    if c0 != c1 { return c0 > c1 }

                    // Secondary: phase priority (prep first)
                    let p0 = $0.action.actionClass.phasePriority
                    let p1 = $1.action.actionClass.phasePriority
                    if p0 != p1 { return p0 < p1 }

                    // Tertiary: prioritize higher effort if critical path is tied.
                    if $0.effortPoints != $1.effortPoints {
                        return $0.effortPoints > $1.effortPoints
                    }

                    return $0.durationSeconds > $1.durationSeconds
                }

            guard !activeReady.isEmpty else {
                // Only passive tasks were ready this iteration
                if passiveTasks.isEmpty { break }
                continue
            }

            // Greedily fill one block up to the budget
            var blockTasks: [StepTask] = []
            var budgetUsed = 0

            for task in activeReady {
                if budgetUsed + task.effortPoints <= effortBudget {
                    blockTasks.append(task)
                    budgetUsed += task.effortPoints
                }
                if budgetUsed >= effortBudget { break }
            }

            if !blockTasks.isEmpty {
                let duration = blockTasks.map(\.durationSeconds).max() ?? 60
                timeline.append(ScheduledBlock(
                    id: UUID(),
                    tasks: blockTasks,
                    type: .active,
                    totalDurationSeconds: duration
                ))
                for task in blockTasks {
                    completed.insert(task.id)
                    remaining.remove(task.id)
                }
            }
        }

        return timeline
    }

    private static func buildDependents(dependencies: [UUID: Set<UUID>]) -> [UUID: Set<UUID>] {
        var dependents: [UUID: Set<UUID>] = [:]
        for (taskID, prerequisites) in dependencies {
            dependents[taskID, default: []] = dependents[taskID] ?? []
            for prerequisite in prerequisites {
                dependents[prerequisite, default: []].insert(taskID)
            }
        }
        return dependents
    }

    private static func computeCriticalPathLengths(
        tasks: [UUID: StepTask],
        dependents: [UUID: Set<UUID>]
    ) -> [UUID: Int] {
        var memo: [UUID: Int] = [:]

        func criticalPath(for taskID: UUID) -> Int {
            if let cached = memo[taskID] {
                return cached
            }

            let duration = tasks[taskID]?.durationSeconds ?? 0
            let downstream = (dependents[taskID] ?? []).map { criticalPath(for: $0) }.max() ?? 0
            let total = duration + downstream
            memo[taskID] = total
            return total
        }

        for taskID in tasks.keys {
            memo[taskID] = criticalPath(for: taskID)
        }

        return memo
    }

    // MARK: - Estimated Total Time

    /// Estimate total cooking time for the interleaved schedule.
    static func estimatedTotalTime(blocks: [ScheduledBlock]) -> Int {
        var activeTime = 0
        var maxPassive = 0

        for block in blocks {
            if block.type == .passive {
                maxPassive = max(maxPassive, block.totalDurationSeconds)
            } else {
                activeTime += block.totalDurationSeconds
            }
        }

        return activeTime + maxPassive
    }

    /// Compare with sequential cooking time.
    static func sequentialTime(recipes: [Recipe]) -> Int {
        recipes.reduce(0) { total, recipe in
            total + recipe.steps.reduce(0) { $0 + $1.effectiveDurationSeconds }
        }
    }

    /// Time saved by interleaving.
    static func timeSaved(recipes: [Recipe], blocks: [ScheduledBlock]) -> Int {
        let sequential = sequentialTime(recipes: recipes)
        let interleaved = estimatedTotalTime(blocks: blocks)
        return max(0, sequential - interleaved)
    }
}
