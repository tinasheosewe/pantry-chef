import Foundation

// The value types the timeline is built from. Deliberately plain and Equatable so
// the composer can be golden-file tested and the views stay dumb renderers.

/// A meal that already happened — a record in the journal (spec §4, "past = record").
struct JournalItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let name: String
    let plate: PlateComposition
    let level: MealPrepLevel
    /// Optional one-line colour ("your sixth this spring", "2 servings left").
    var note: String?

    init(id: UUID = UUID(), date: Date, name: String, plate: PlateComposition,
         level: MealPrepLevel, note: String? = nil) {
        self.id = id; self.date = date; self.name = name
        self.plate = plate; self.level = level; self.note = note
    }
}

/// A meal committed to a future day (spec §4, "future = consequence", solid node).
struct PlannedMeal: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let name: String
    let plate: PlateComposition
    let level: MealPrepLevel
    /// Items this meal still needs, already routed to the list.
    var missingCount: Int

    init(id: UUID = UUID(), date: Date, name: String, plate: PlateComposition,
         level: MealPrepLevel, missingCount: Int = 0) {
        self.id = id; self.date = date; self.name = name
        self.plate = plate; self.level = level; self.missingCount = missingCount
    }
}

/// A deadline: an ingredient about to turn (spec §4, diamond marker).
struct ExpiryMilestone: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let itemName: String
    /// Whether a committed/likely meal already accounts for it.
    var rescued: Bool

    init(id: UUID = UUID(), date: Date, itemName: String, rescued: Bool = false) {
        self.id = id; self.date = date; self.itemName = itemName; self.rescued = rescued
    }
}

/// A dashed invitation the app floats into the future (meal, batch-cook, shop).
struct Proposal: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let text: String

    init(id: UUID = UUID(), date: Date, text: String) {
        self.id = id; self.date = date; self.text = text
    }
}

/// A one-line fact attached to an otherwise bare day so it earns its row instead
/// of folding (spec §4 density rules, "whispers").
struct DatedWhisper: Equatable, Sendable {
    let date: Date
    let text: String
}

/// One future thing with a date — the composer weaves these among the day ruler.
struct DatedEvent: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case meal(PlannedMeal)
        case expiry(ExpiryMilestone)
        case proposal(Proposal)
    }
    let kind: Kind
    var date: Date {
        switch kind {
        case .meal(let m): return m.date
        case .expiry(let e): return e.date
        case .proposal(let p): return p.date
        }
    }
    var id: UUID {
        switch kind {
        case .meal(let m): return m.id
        case .expiry(let e): return e.id
        case .proposal(let p): return p.id
        }
    }
}

/// Everything the timeline is composed from, at a moment in time. Built from the
/// real stores in later phases; constructed directly in tests and previews.
struct KitchenSnapshot: Equatable, Sendable {
    let today: Date
    var horizonDays: Int = 21
    /// How many days of past ruler to render. 0 = journal entries only (record),
    /// > 0 = a backward ruler so the timeline scrolls into the past too.
    var pastDays: Int = 0
    var journal: [JournalItem] = []
    var events: [DatedEvent] = []
    var whispers: [DatedWhisper] = []
}

/// One row of the rendered timeline. The composer emits an ordered list of these;
/// the view is a dumb renderer over them.
enum TimelineEntry: Identifiable, Equatable, Sendable {
    case journal(JournalItem)
    case now
    case meal(PlannedMeal)
    case expiry(ExpiryMilestone)
    case proposal(Proposal)
    /// A bare day on the ruler; `whisper` present means it earned a fact.
    case day(date: Date, whisper: String?)
    /// A compressed run of ≥2 silent days (spec §4 fold).
    case fold(start: Date, end: Date, dayCount: Int)
    /// A week boundary rollup ("Week of Jun 16 — 2 planned").
    case week(start: Date, plannedCount: Int)

    var id: String {
        switch self {
        case .journal(let j): return "journal-\(j.id)"
        case .now: return "now"
        case .meal(let m): return "meal-\(m.id)"
        case .expiry(let e): return "expiry-\(e.id)"
        case .proposal(let p): return "proposal-\(p.id)"
        case .day(let date, _): return "day-\(date.timeIntervalSince1970)"
        case .fold(let start, _, _): return "fold-\(start.timeIntervalSince1970)"
        case .week(let start, _): return "week-\(start.timeIntervalSince1970)"
        }
    }
}
