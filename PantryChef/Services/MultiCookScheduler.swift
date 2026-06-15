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
/// It schedules the way you actually cook in parallel: get the long, walk-away
/// steps going first, then fill their idle windows with hands-on work on the other
/// dishes — instead of the old round-robin that treated a 90-minute braise and a
/// 10-second garnish as equals. It simulates a single cook against a clock:
///
///  - each dish exposes its next step only after the previous one's time has
///    elapsed (precedence is preserved within a dish);
///  - a *passive* step (a long timer you set and leave) costs only a brief setup
///    before the cook is free again, so its timer overlaps everything after it;
///  - an *active* step occupies the cook for its whole duration;
///  - at each moment the cook starts the longest available passive step first
///    (get the slow things going), otherwise the shortest active one (clear quick
///    tasks), breaking ties by the dishes' input order for determinism.
enum MultiCookScheduler {

    static func schedule(_ dishes: [Dish]) -> [ScheduledStep] {
        // A live queue of one dish's remaining steps plus when its next may start.
        struct Lane {
            let dish: Dish
            var next: Int = 0          // index of the next unplaced step
            var readyAt: Double = 0    // clock time the next step may begin
            var hasSteps: Bool { next < dish.steps.count }
            var step: CookStep { dish.steps[next] }
        }

        var lanes = dishes.map { Lane(dish: $0) }
        var clock: Double = 0
        var out: [ScheduledStep] = []

        while true {
            let active = lanes.indices.filter { lanes[$0].hasSteps }
            guard !active.isEmpty else { break }

            // Lanes whose next step can begin now; if none, jump the clock forward.
            let ready = active.filter { lanes[$0].readyAt <= clock + 0.0001 }
            guard !ready.isEmpty else {
                clock = active.map { lanes[$0].readyAt }.min() ?? clock
                continue
            }

            // Start the longest passive step first; otherwise the shortest active
            // one. `input order` (the lane index) is the stable final tiebreak.
            let pick = ready.min { a, b in
                let sa = lanes[a].step, sb = lanes[b].step
                let key = { (s: CookStep) -> (Int, Double) in
                    isPassive(s) ? (0, -duration(s)) : (1, duration(s))
                }
                let (ka, kb) = (key(sa), key(sb))
                if ka != kb { return ka < kb }
                return a < b
            }!

            let step = lanes[pick].step
            out.append(ScheduledStep(dishName: lanes[pick].dish.name,
                                     plate: lanes[pick].dish.plate, step: step))
            // The dish can't move on until this step's full time elapses; the cook,
            // however, is freed after only the setup cost of a passive step.
            lanes[pick].readyAt = clock + duration(step)
            lanes[pick].next += 1
            clock += attention(step)
        }

        return out
    }

    /// A step you set going and walk away from — a timer at or above the passive
    /// threshold. These are what make parallel cooking worth scheduling.
    private static func isPassive(_ step: CookStep) -> Bool {
        guard let t = step.timerSeconds else { return false }
        return t >= AppConfig.passiveStepThresholdSeconds
    }

    /// How long the step's clock runs before the dish can proceed.
    private static func duration(_ step: CookStep) -> Double {
        Double(step.timerSeconds ?? AppConfig.defaultStepDurationSeconds)
    }

    /// How long the *cook* is occupied: a brief setup for a passive step (then they
    /// leave it), the full duration for a hands-on one.
    private static func attention(_ step: CookStep) -> Double {
        isPassive(step) ? Double(AppConfig.passiveStepSetupSeconds) : duration(step)
    }
}
