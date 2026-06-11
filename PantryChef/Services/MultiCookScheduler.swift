import Foundation

/// One step in a consolidated multi-dish cook, tagged with the dish it belongs to.
struct ScheduledStep: Identifiable, Equatable, Sendable {
    let id: UUID
    let dishName: String
    let plate: PlateComposition
    let step: CookStep

    init(id: UUID = UUID(), dishName: String, plate: PlateComposition, step: CookStep) {
        self.id = id; self.dishName = dishName; self.plate = plate; self.step = step
    }
}

/// Folds several dishes into one cook session (spec §5 — one Cook surface that
/// scales from a single recipe to many). Pure and deterministic.
///
/// The schedule interleaves by step index — every dish's first step, then every
/// second step, and so on — so you get all the pots going before tending each, the
/// way you actually cook in parallel. (The old AI batch scheduler can slot in here
/// behind the same `[ScheduledStep]` shape when wired.)
enum MultiCookScheduler {
    static func schedule(_ dishes: [Dish]) -> [ScheduledStep] {
        let maxSteps = dishes.map(\.steps.count).max() ?? 0
        var out: [ScheduledStep] = []
        for index in 0..<maxSteps {
            for dish in dishes where index < dish.steps.count {
                out.append(ScheduledStep(dishName: dish.name, plate: dish.plate, step: dish.steps[index]))
            }
        }
        return out
    }
}
