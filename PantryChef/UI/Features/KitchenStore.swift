import SwiftUI
import Observation

// MARK: - Stock view model

/// A stock row. Perishables show a day count; staples show honest presence, never
/// a fake fullness (spec §7).
struct StockItem: Identifiable, Equatable {
    enum Section: String { case made = "Made by you", useSoon = "Use soon", have = "In stock", staples = "Staples" }
    enum Measure: Equatable {
        case perishable(detail: String, daysLeft: Int?)
        case staple(StapleLevel)
        case made(detail: String)
    }
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

// MARK: - Store

/// The redesign's app state: holds the kitchen and derives every surface through
/// the pure engines (TimelineComposer, ReadinessService, IntakeParser). Seeded with
/// a sample kitchen; the single seam where real persistence wires in later.
@Observable
final class KitchenStore {
    var today = Date()
    var space: RootSpace = .timeline
    var nowState: NowState

    var journal: [JournalItem]
    var events: [DatedEvent]
    var whispers: [DatedWhisper]
    var stock: [StockItem]
    var library: [Dish]
    var profile = DietaryProfile()

    private let composer = TimelineComposer()
    private let parser = IntakeParser()

    var timelineEntries: [TimelineEntry] {
        composer.compose(KitchenSnapshot(today: today, horizonDays: 21,
                                         journal: journal, events: events, whispers: whispers))
    }

    /// Live readiness for a dish — the single ReadinessService over current stock.
    func readiness(for dish: Dish) -> Readiness {
        ReadinessService(presence: StockPresence(keys: stockKeys), swaps: NoSwaps())
            .evaluate(dish.requirements)
    }

    /// Which ingredient keys are on hand right now (for the gathering checklist).
    func onHand(_ key: String) -> Bool { stockKeys.contains(key) }

    private var stockKeys: Set<String> { Set(stock.map(\.key)) }

    func parse(_ phrase: String) -> ParsedIntake { parser.parse(phrase) }

    init() {
        let cal = Calendar.current
        let now = Date()
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: now)! }
        func plate(_ c: [FoodCategory], _ s: UInt64) -> PlateComposition { .init(categories: c, seed: s) }
        func line(_ key: String, _ amount: String?, _ name: String, staple: Bool = false) -> RecipeLine {
            RecipeLine(key: key, amount: amount, name: name, isStaple: staple)
        }
        today = now

        // Cookable dishes — ingredients + steps so Cook never sends you to the pantry.
        let orzo = Dish(
            name: "Spinach & feta orzo", plate: plate([.produce, .dairy, .pasta], 1), time: "25 min",
            isFavorite: true,
            ingredients: [
                line("baby spinach", "300 g", "Baby spinach"),
                line("feta", "200 g", "Feta"),
                line("orzo", "1 cup", "Orzo"),
                line("butter", "30 g", "Butter"),
                line("lemon", "1", "Lemon"),
                line("olive oil", nil, "Olive oil", staple: true)
            ],
            steps: [
                CookStep("Bring a pot of salted water to the boil and cook the orzo until al dente.", timerSeconds: 540),
                CookStep("Wilt the spinach into the brown butter until just collapsed — about two minutes.", timerSeconds: 120),
                CookStep("Fold the orzo and crumbled feta through; finish with lemon, season, and serve.")
            ])
        let shakshuka = Dish(
            name: "Shakshuka", plate: plate([.protein, .produce, .spices], 2), time: "30 min",
            ingredients: [line("eggs", "4", "Eggs"), line("tomato", "400 g", "Tomatoes"),
                          line("onion", "1", "Onion"), line("paprika", nil, "Paprika", staple: true)],
            steps: [CookStep("Soften the onion, add tomatoes and paprika, simmer to a sauce.", timerSeconds: 600),
                    CookStep("Make wells, crack in the eggs, cover and cook until just set.", timerSeconds: 480)])
        let stirfry = Dish(
            name: "Tuesday stir-fry", plate: plate([.produce, .protein], 14), time: "20 min", isYours: true,
            isFavorite: true,
            ingredients: [line("baby spinach", "200 g", "Spinach"), line("feta", "100 g", "Feta")],
            steps: [CookStep("Get the pan smoking hot, then go fast.")])
        let salmon = Dish(
            name: "Miso butter salmon", plate: plate([.protein, .oils], 5), time: "18 min",
            ingredients: [line("salmon", "2", "Salmon fillets"), line("miso", "2 tbsp", "Miso"),
                          line("butter", "20 g", "Butter")],
            steps: [CookStep("Whisk miso into soft butter; coat the salmon."),
                    CookStep("Roast until the centre just flakes.", timerSeconds: 600)])
        let ragu = Dish(
            name: "Lamb ragù", plate: plate([.protein, .pasta, .produce], 3), time: "2 h 10",
            ingredients: [line("lamb", "500 g", "Lamb mince"), line("orzo", "2 cups", "Orzo"),
                          line("onion", "1", "Onion"), line("tomato", "400 g", "Tomatoes")],
            steps: [CookStep("Brown the lamb hard, then build the sofrito.", timerSeconds: 600),
                    CookStep("Add tomatoes and braise low and slow.", timerSeconds: 5400)])
        let greens = Dish(
            name: "Lemon greens", plate: plate([.produce, .dairy], 7), time: "20 min",
            ingredients: [line("baby spinach", "200 g", "Spinach"), line("feta", "100 g", "Feta"),
                          line("lemon", "1", "Lemon")],
            steps: [CookStep("Blister the greens, dress with lemon, crumble over feta.")])
        let frittata = Dish(
            name: "Herb frittata", plate: plate([.dairy, .produce], 9), time: "15 min",
            ingredients: [line("eggs", "6", "Eggs"), line("feta", "100 g", "Feta"),
                          line("baby spinach", "100 g", "Spinach")],
            steps: [CookStep("Beat the eggs, fold in greens and feta, set under the grill.", timerSeconds: 480)])

        library = [orzo, shakshuka, stirfry, salmon, ragu, greens]

        nowState = .open(options: [
            FanOption(name: frittata.name, plate: frittata.plate, subtitle: "15 min · 5 of 5 on hand",
                      reason: "The fast pick — fifteen minutes, start to plate.", dish: frittata),
            FanOption(name: orzo.name, plate: orzo.plate, subtitle: "25 min · 6 of 6 on hand",
                      reason: "The rescue pick — spinach won't see Friday.", dish: orzo),
            FanOption(name: ragu.name, plate: ragu.plate, subtitle: "2 h 10 · 7 of 9 on hand",
                      reason: "The ambitious pick — and it freezes beautifully.",
                      readiness: .needs(items: ["wine", "celery"]), dish: ragu)
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
