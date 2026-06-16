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
/// It schedules the way you actually cook in parallel, in two movements:
///
///  1. **Unified prep** — all the knife work up front, so you cut every onion and
///     tomato in one pass instead of returning to the board per dish. Each dish's
///     prep stays its own line ("dice 1 onion" for one, again for the other), in
///     dish-then-step order. It's the cook's natural mise en place.
///  2. **The cook phase** — a single cook simulated against a clock: get the long,
///     walk-away steps going first, then fill their idle windows with hands-on work
///     on the other dishes (not the old round-robin that treated a 90-minute braise
///     and a 10-second garnish as equals).
///
/// In the cook phase: each dish exposes its next step only after the previous one's
/// time has elapsed (precedence preserved within a dish); a *passive* step (set a
/// timer and leave) frees the cook after a brief setup, so its timer overlaps
/// everything after it; an *active* step occupies the cook for its whole duration;
/// and at each moment the cook starts the longest available passive step, otherwise
/// the shortest active one, breaking ties by the dishes' input order.
enum MultiCookScheduler {

    static func schedule(_ dishes: [Dish]) -> [ScheduledStep] {
        // 1) Unified prep — every dish's prep steps first, grouped, in order.
        var out: [ScheduledStep] = []
        for dish in dishes {
            for step in dish.steps where step.phase == .prep {
                out.append(ScheduledStep(dishName: dish.name, plate: dish.plate, step: step))
            }
        }
        // 2) The cook phase — clock-driven over each dish's remaining (non-prep) steps.
        out += cookPhase(dishes)
        return out
    }

    /// The passive-overlap greedy over the non-prep steps of every dish.
    private static func cookPhase(_ dishes: [Dish]) -> [ScheduledStep] {
        // A live queue of one dish's remaining cook/finish steps plus when its next
        // may start.
        struct Lane {
            let dishName: String
            let plate: PlateComposition
            let steps: [CookStep]
            var next: Int = 0
            var readyAt: Double = 0
            var hasSteps: Bool { next < steps.count }
            var step: CookStep { steps[next] }
        }

        var lanes = dishes.map {
            Lane(dishName: $0.name, plate: $0.plate, steps: $0.steps.filter { $0.phase != .prep })
        }
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
            out.append(ScheduledStep(dishName: lanes[pick].dishName,
                                     plate: lanes[pick].plate, step: step))
            // The dish can't move on until this step's full time elapses; the cook,
            // however, is freed after only the setup cost of a passive step.
            lanes[pick].readyAt = clock + duration(step)
            lanes[pick].next += 1
            clock += occupancy(step)
        }

        return out
    }

    /// A step you set going and walk away from — its timer overlaps everything after.
    private static func isPassive(_ step: CookStep) -> Bool { step.attention == .passive }

    /// How long the step's clock runs before the dish can proceed.
    private static func duration(_ step: CookStep) -> Double {
        Double(step.timerSeconds ?? AppConfig.defaultStepDurationSeconds)
    }

    /// How long the *cook* is occupied: a brief setup for a passive step (then they
    /// leave it), the full duration for a hands-on one.
    private static func occupancy(_ step: CookStep) -> Double {
        isPassive(step) ? Double(AppConfig.passiveStepSetupSeconds) : duration(step)
    }
}
