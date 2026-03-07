import Foundation

// MARK: - Multi-Recipe Scheduler
//
// Deterministic interleaving scheduler for cooking multiple recipes simultaneously.
// Uses three rules:
//   1. Action-Class Grouping — batch same-class tasks together (e.g. all cutting)
//   2. Passive-Before-Active — start passive tasks, fill gaps with active work
//   3. Dependency Preservation — within-recipe step order is preserved
//
// Produces a flat timeline of ScheduledBlocks that a cook mode UI can step through.

struct MultiRecipeScheduler {

    // MARK: - Output Types

    /// A block in the scheduled timeline. May contain tasks from multiple recipes.
    struct ScheduledBlock: Identifiable, Hashable {
        let id: UUID
        let tasks: [StepTask]
        let type: TaskType
        let actionClass: ActionClass
        let totalDurationSeconds: Int

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

    /// A parallel activity that runs during a passive block.
    struct ParallelActivity: Identifiable {
        let id = UUID()
        let passiveBlock: ScheduledBlock
        let activeBlocks: [ScheduledBlock]
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

        // 2. Build dependency graph (within-recipe ordering)
        let dependencies = buildDependencies(tasks: allTasks, recipes: recipes)

        // 3. Merge prep tasks across recipes
        let (mergedTasks, mergeMap) = mergePrepTasks(allTasks)

        // 4. Schedule using priority-based list scheduling
        return listSchedule(tasks: mergedTasks, dependencies: dependencies, mergeMap: mergeMap)
    }

    // MARK: - Single Recipe (simple linear)

    private static func singleRecipeBlocks(_ recipe: Recipe) -> [ScheduledBlock] {
        recipe.steps.sorted { $0.stepNumber < $1.stepNumber }.map { step in
            let tasks = step.tasks.isEmpty
                ? [StepTask(action: .other(step.instruction), durationSeconds: step.effectiveDurationSeconds, type: .active, recipeId: recipe.id, recipeName: recipe.title, sourceStepNumber: step.stepNumber)]
                : step.tasks.map { var t = $0; t.recipeId = recipe.id; t.recipeName = recipe.title; t.sourceStepNumber = step.stepNumber; return t }

            let type = tasks.allSatisfy({ $0.type == .passive }) ? TaskType.passive : .active
            let actionClass = tasks.first?.action.actionClass ?? .activeCook
            let duration = tasks.map(\.durationSeconds).max() ?? step.effectiveDurationSeconds

            return ScheduledBlock(
                id: UUID(),
                tasks: tasks,
                type: type,
                actionClass: actionClass,
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
                    var task = StepTask(
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

    // MARK: - Dependency Graph

    /// Returns a dictionary: taskId -> [prerequisite taskIds].
    /// Within a recipe, each step's tasks depend on all tasks from the previous step.
    private static func buildDependencies(tasks: [StepTask], recipes: [Recipe]) -> [UUID: Set<UUID>] {
        var deps: [UUID: Set<UUID>] = [:]
        for task in tasks { deps[task.id] = [] }

        for recipe in recipes {
            let steps = recipe.steps.sorted { $0.stepNumber < $1.stepNumber }
            for i in 1..<steps.count {
                let prevStepTasks = tasks.filter { $0.recipeId == recipe.id && $0.sourceStepNumber == steps[i-1].stepNumber }
                let currStepTasks = tasks.filter { $0.recipeId == recipe.id && $0.sourceStepNumber == steps[i].stepNumber }
                let prevIds = Set(prevStepTasks.map(\.id))
                for task in currStepTasks {
                    deps[task.id, default: []].formUnion(prevIds)
                }
            }
        }
        return deps
    }

    // MARK: - Prep Task Merging

    /// Merge prep-class tasks across recipes into combined blocks.
    /// Returns (merged task list, mapping from merged ID to original IDs).
    private static func mergePrepTasks(_ tasks: [StepTask]) -> ([StepTask], [UUID: [UUID]]) {
        var mergeMap: [UUID: [UUID]] = [:]
        var result: [StepTask] = []
        var consumed = Set<UUID>()

        // Group by action class
        let byClass = Dictionary(grouping: tasks, by: { $0.action.actionClass })

        // Merge prepCut tasks that can be done together
        if let cutTasks = byClass[.prepCut], cutTasks.count > 1 {
            // Group by equipment (all cutting board tasks can merge)
            let merged = StepTask(
                action: .cut(.dice), // representative action
                ingredient: cutTasks.compactMap(\.ingredient).joined(separator: ", "),
                durationSeconds: cutTasks.map(\.durationSeconds).reduce(0, +),
                type: .active,
                requiresEquipment: "cutting board"
            )
            mergeMap[merged.id] = cutTasks.map(\.id)
            result.append(merged)
            consumed.formUnion(cutTasks.map(\.id))
        }

        // Merge heatSetup tasks (same equipment + temp)
        if let heatTasks = byClass[.heatSetup], heatTasks.count > 1 {
            // Group by equipment
            let byEquip = Dictionary(grouping: heatTasks, by: { $0.requiresEquipment ?? "unknown" })
            for (_, equipTasks) in byEquip {
                if equipTasks.count > 1 {
                    let merged = StepTask(
                        action: .heat,
                        ingredient: equipTasks.compactMap(\.ingredient).joined(separator: " & "),
                        durationSeconds: equipTasks.map(\.durationSeconds).max() ?? 60,
                        type: .active,
                        requiresEquipment: equipTasks.first?.requiresEquipment,
                        temperature: equipTasks.compactMap(\.temperature).max()
                    )
                    mergeMap[merged.id] = equipTasks.map(\.id)
                    result.append(merged)
                    consumed.formUnion(equipTasks.map(\.id))
                }
            }
        }

        // Add all non-merged tasks
        for task in tasks where !consumed.contains(task.id) {
            result.append(task)
            mergeMap[task.id] = [task.id]
        }

        return (result, mergeMap)
    }

    // MARK: - List Scheduling

    private static func listSchedule(tasks: [StepTask], dependencies: [UUID: Set<UUID>], mergeMap: [UUID: [UUID]]) -> [ScheduledBlock] {
        var timeline: [ScheduledBlock] = []
        var completed = Set<UUID>()
        var remaining = Set(tasks.map(\.id))
        let taskById = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        // Resolve original IDs for dependency checking
        func originalIds(for taskId: UUID) -> [UUID] {
            mergeMap[taskId] ?? [taskId]
        }

        func isReady(_ taskId: UUID) -> Bool {
            let originals = originalIds(for: taskId)
            for origId in originals {
                let prereqs = dependencies[origId] ?? []
                if !prereqs.isSubset(of: completed) { return false }
            }
            return true
        }

        var iterations = 0
        let maxIterations = tasks.count * 3 // safety

        while !remaining.isEmpty && iterations < maxIterations {
            iterations += 1

            // Find ready tasks
            let readyIds = remaining.filter { isReady($0) }
            guard !readyIds.isEmpty else { break }

            // Group ready tasks by action class
            let readyTasks = readyIds.compactMap { taskById[$0] }
            let byClass = Dictionary(grouping: readyTasks, by: { $0.action.actionClass })

            // Priority: prepCut > prepOther > heatSetup > passive (start early) > active > finish
            let classPriority: [ActionClass] = [.prepCut, .prepOther, .heatSetup, .passiveCook, .activeCook, .finish]

            // Pick highest-priority group
            var selected: [StepTask]?
            var selectedClass: ActionClass = .activeCook

            for cls in classPriority {
                if let group = byClass[cls], !group.isEmpty {
                    selected = group
                    selectedClass = cls
                    break
                }
            }

            guard let selectedTasks = selected else { break }

            // If passive, schedule it and look for active fillers
            if selectedClass == .passiveCook {
                // Schedule one passive task at a time
                let passiveTask = selectedTasks[0]
                let passiveBlock = ScheduledBlock(
                    id: UUID(),
                    tasks: [passiveTask],
                    type: .passive,
                    actionClass: .passiveCook,
                    totalDurationSeconds: passiveTask.durationSeconds
                )
                timeline.append(passiveBlock)

                // Mark as completed
                for origId in originalIds(for: passiveTask.id) {
                    completed.insert(origId)
                }
                remaining.remove(passiveTask.id)

                // Fill passive gap with active tasks
                var gap = passiveTask.durationSeconds
                let activeReady = remaining.filter { isReady($0) }
                    .compactMap { taskById[$0] }
                    .filter { $0.type == .active }
                    .sorted { $0.durationSeconds < $1.durationSeconds }

                for filler in activeReady {
                    guard gap > 0 && filler.durationSeconds <= gap else { continue }
                    let fillerBlock = ScheduledBlock(
                        id: UUID(),
                        tasks: [filler],
                        type: .active,
                        actionClass: filler.action.actionClass,
                        totalDurationSeconds: filler.durationSeconds
                    )
                    timeline.append(fillerBlock)
                    gap -= filler.durationSeconds
                    for origId in originalIds(for: filler.id) {
                        completed.insert(origId)
                    }
                    remaining.remove(filler.id)
                }
            } else if selectedClass == .prepCut || selectedClass == .prepOther {
                // Batch all prep tasks of this class into one block
                let block = ScheduledBlock(
                    id: UUID(),
                    tasks: selectedTasks,
                    type: .active,
                    actionClass: selectedClass,
                    totalDurationSeconds: selectedTasks.map(\.durationSeconds).reduce(0, +)
                )
                timeline.append(block)
                for task in selectedTasks {
                    for origId in originalIds(for: task.id) {
                        completed.insert(origId)
                    }
                    remaining.remove(task.id)
                }
            } else {
                // Active or finish — schedule one at a time
                let task = selectedTasks[0]
                let block = ScheduledBlock(
                    id: UUID(),
                    tasks: [task],
                    type: task.type,
                    actionClass: selectedClass,
                    totalDurationSeconds: task.durationSeconds
                )
                timeline.append(block)
                for origId in originalIds(for: task.id) {
                    completed.insert(origId)
                }
                remaining.remove(task.id)
            }
        }

        return timeline
    }

    // MARK: - Estimated Total Time

    /// Estimate total cooking time for the interleaved schedule.
    static func estimatedTotalTime(blocks: [ScheduledBlock]) -> Int {
        // Sum all active blocks + longest passive (they overlap)
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
