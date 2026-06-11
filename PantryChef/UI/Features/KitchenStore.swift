import SwiftUI
import Observation

// MARK: - View models for Stock & Library

/// A stock row. Perishables show a day count; staples show a gauge level — the
/// trust layer never prints a fake gram count for a staple (spec §7).
struct StockItem: Identifiable, Equatable {
    enum Section: String { case made = "Made by you", useSoon = "Use soon", have = "In stock", staples = "Staples" }
    enum Measure: Equatable {
        case perishable(detail: String, daysLeft: Int?)   // "300 g", 2
        case staple(StapleLevel)                          // presence, not a fake fullness
        case made(detail: String)                         // "3 frozen portions"
    }

    /// Staples aren't measured by amount (we never know the bottle is "72% full") —
    /// only by presence, with a low/out flag the user sets at a natural moment.
    enum StapleLevel: Equatable {
        case inStock, runningLow, out
        var label: String {
            switch self {
            case .inStock: return "In stock"
            case .runningLow: return "Running low — on your list"
            case .out: return "Out"
            }
        }
    }
    let id: UUID
    let key: String
    let name: String
    let plate: PlateComposition
    let section: Section
    let measure: Measure

    init(id: UUID = UUID(), key: String, name: String, plate: PlateComposition,
         section: Section, measure: Measure) {
        self.id = id; self.key = key; self.name = name; self.plate = plate
        self.section = section; self.measure = measure
    }
}

/// A library cell — a dish with its readiness computed live by ReadinessService.
struct LibraryDish: Identifiable, Equatable {
    let id: UUID
    let name: String
    let plate: PlateComposition
    let time: String
    let isYours: Bool
    let requirements: [IngredientRequirement]

    init(id: UUID = UUID(), name: String, plate: PlateComposition, time: String,
         isYours: Bool = false, requirements: [IngredientRequirement]) {
        self.id = id; self.name = name; self.plate = plate
        self.time = time; self.isYours = isYours; self.requirements = requirements
    }
}

// MARK: - Store

/// The redesign's app state: holds the kitchen and derives every surface through
/// the pure engines (TimelineComposer, ReadinessService, IntakeParser). Seeded with
/// a sample kitchen so the app is alive on first launch; this is the single seam
/// where real persistence wires in later.
@Observable
final class KitchenStore {
    var today = Date()
    var space: RootSpace = .timeline
    var nowState: NowState

    var journal: [JournalItem]
    var events: [DatedEvent]
    var whispers: [DatedWhisper]
    var stock: [StockItem]
    var library: [LibraryDish]

    private let composer = TimelineComposer()
    private let parser = IntakeParser()

    var timelineEntries: [TimelineEntry] {
        composer.compose(KitchenSnapshot(today: today, horizonDays: 21,
                                         journal: journal, events: events, whispers: whispers))
    }

    /// Live readiness for a library dish — the single ReadinessService, fed by what
    /// the stock currently holds.
    func readiness(for dish: LibraryDish) -> Readiness {
        ReadinessService(presence: StockPresence(keys: stockKeys), swaps: NoSwaps())
            .evaluate(dish.requirements)
    }

    private var stockKeys: Set<String> { Set(stock.map(\.key)) }

    /// Parse a composer phrase and stage it (full add-to-stock wiring comes with
    /// persistence; here it returns the parse for the composer to show as a card).
    func parse(_ phrase: String) -> ParsedIntake { parser.parse(phrase) }

    init() {
        let cal = Calendar.current
        let now = Date()
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: now)! }
        func plate(_ c: [FoodCategory], _ s: UInt64) -> PlateComposition { .init(categories: c, seed: s) }

        today = now
        nowState = .open(options: [
            FanOption(name: "Herb frittata", plate: plate([.dairy, .produce], 9),
                      subtitle: "15 min · 5 of 5 on hand", reason: "The fast pick — fifteen minutes, start to plate."),
            FanOption(name: "Spinach & feta orzo", plate: plate([.produce, .dairy, .pasta], 1),
                      subtitle: "25 min · 6 of 6 on hand", reason: "The rescue pick — spinach won't see Friday."),
            FanOption(name: "Lamb ragù", plate: plate([.protein, .pasta, .produce], 3),
                      subtitle: "2 h 10 · 7 of 9 on hand", reason: "The ambitious pick — and it freezes beautifully.",
                      readiness: .needs(items: ["wine", "celery"]))
        ], selected: 1)

        journal = [
            JournalItem(date: day(-2), name: "Lamb ragù", plate: plate([.protein, .pasta], 3),
                        level: .cooked, note: "batch cooked, 3 servings"),
            JournalItem(date: day(-1), name: "Shakshuka", plate: plate([.protein, .produce, .spices], 2),
                        level: .cooked, note: "your sixth this spring")
        ]
        events = [
            DatedEvent(kind: .expiry(ExpiryMilestone(date: day(3), itemName: "spinach"))),
            DatedEvent(kind: .meal(PlannedMeal(date: day(8), name: "Miso salmon",
                                               plate: plate([.protein, .oils], 5), level: .cooked, missingCount: 2))),
            DatedEvent(kind: .proposal(Proposal(date: day(12), text: "Your list hit 5 items — milk runs out around Monday.")))
        ]
        whispers = [DatedWhisper(date: day(1), text: "ragù waiting · 3 portions")]

        stock = [
            StockItem(key: "lamb ragu", name: "Lamb ragù", plate: plate([.protein, .pasta], 3),
                      section: .made, measure: .made(detail: "3 frozen portions · good through July")),
            StockItem(key: "baby spinach", name: "Baby spinach", plate: plate([.produce], 1),
                      section: .useSoon, measure: .perishable(detail: "300 g", daysLeft: 2)),
            StockItem(key: "greek yogurt", name: "Greek yogurt", plate: plate([.dairy], 4),
                      section: .useSoon, measure: .perishable(detail: "500 g", daysLeft: 3)),
            StockItem(key: "feta", name: "Feta", plate: plate([.dairy], 7),
                      section: .have, measure: .perishable(detail: "200 g", daysLeft: 18)),
            StockItem(key: "orzo", name: "Orzo", plate: plate([.pasta], 6),
                      section: .staples, measure: .staple(.inStock)),
            StockItem(key: "flour", name: "Flour", plate: plate([.bakingSupplies], 11),
                      section: .staples, measure: .staple(.inStock)),
            StockItem(key: "olive oil", name: "Olive oil", plate: plate([.oils], 8),
                      section: .staples, measure: .staple(.runningLow))
        ]

        func req(_ key: String, _ name: String, staple: Bool = false) -> IngredientRequirement {
            .init(key: key, displayName: name, isStaple: staple)
        }
        library = [
            LibraryDish(name: "Spinach & feta orzo", plate: plate([.produce, .dairy, .pasta], 1), time: "25 min",
                        requirements: [req("baby spinach", "Spinach"), req("feta", "Feta"), req("orzo", "Orzo"),
                                       req("olive oil", "Olive oil", staple: true)]),
            LibraryDish(name: "Shakshuka", plate: plate([.protein, .produce, .spices], 2), time: "30 min",
                        requirements: [req("eggs", "Eggs"), req("tomato", "Tomato")]),
            LibraryDish(name: "Tuesday stir-fry", plate: plate([.produce, .protein], 14), time: "20 min", isYours: true,
                        requirements: [req("baby spinach", "Spinach"), req("feta", "Feta")]),
            LibraryDish(name: "Miso butter salmon", plate: plate([.protein, .oils], 5), time: "18 min",
                        requirements: [req("salmon", "Salmon"), req("miso", "Miso")]),
            LibraryDish(name: "Lamb ragù", plate: plate([.protein, .pasta, .produce], 3), time: "2 h 10",
                        requirements: [req("lamb", "Lamb"), req("orzo", "Orzo")]),
            LibraryDish(name: "Lemon greens", plate: plate([.produce, .dairy], 7), time: "20 min",
                        requirements: [req("baby spinach", "Spinach"), req("feta", "Feta")])
        ]
    }
}

/// PantryPresence backed by the store's current stock keys.
private struct StockPresence: PantryPresence {
    let keys: Set<String>
    func hasOnHand(_ key: String) -> Bool { keys.contains(key) }
    func isKnownOut(_ key: String) -> Bool { false }
}

private struct NoSwaps: SwapResolver {
    func swapTargets(for key: String) -> [(key: String, name: String)] { [] }
}
