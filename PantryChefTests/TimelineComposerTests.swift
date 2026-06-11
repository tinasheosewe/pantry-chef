import XCTest
@testable import PantryChef

/// Golden tests for the timeline feed composer. Each test builds a snapshot and
/// asserts the exact row sequence via a compact token encoding, so a failure reads
/// like the timeline it describes.
final class TimelineComposerTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }()
    private lazy var composer = TimelineComposer(calendar: cal)
    /// Monday, 1 Jan 2024, 09:00 UTC — so offsets 1...6 stay inside the week.
    private lazy var today = cal.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 9))!
    private var todayStart: Date { cal.startOfDay(for: today) }

    /// Noon of (today + n days), so it lands cleanly inside that day.
    private func day(_ n: Int) -> Date {
        cal.date(byAdding: .day, value: n, to: todayStart)!.addingTimeInterval(12 * 3600)
    }

    private func offset(_ date: Date) -> Int {
        cal.dateComponents([.day], from: todayStart, to: cal.startOfDay(for: date)).day ?? 0
    }

    /// Compact, readable encoding of each row.
    private func tokens(_ entries: [TimelineEntry]) -> [String] {
        entries.map { entry in
            switch entry {
            case .now: return "NOW"
            case .journal(let j): return "J(\(j.name))"
            case .meal(let m): return "MEAL(\(m.name)@\(offset(m.date)))"
            case .expiry(let e): return "EXP(\(e.itemName)@\(offset(e.date)))"
            case .proposal: return "PROP"
            case .day(let d, let w): return w == nil ? "DAY(\(offset(d)))" : "WHISPER(\(offset(d)))"
            case .fold(let s, _, let c): return "FOLD(\(c)@\(offset(s)))"
            case .week(_, let c): return "WEEK(\(c))"
            }
        }
    }

    private func snapshot(horizon: Int = 6, journal: [JournalItem] = [],
                          events: [DatedEvent] = [], whispers: [DatedWhisper] = []) -> KitchenSnapshot {
        KitchenSnapshot(today: today, horizonDays: horizon, journal: journal,
                        events: events, whispers: whispers)
    }

    private func plannedMeal(_ n: Int, _ name: String) -> DatedEvent {
        .init(kind: .meal(PlannedMeal(date: day(n), name: name,
                                      plate: .init(categories: [.produce], seed: 1), level: .cooked)))
    }
    private func expiry(_ n: Int, _ item: String) -> DatedEvent {
        .init(kind: .expiry(ExpiryMilestone(date: day(n), itemName: item)))
    }

    // MARK: - Always anchored at now

    func testStartsWithNow() {
        XCTAssertEqual(tokens(composer.compose(snapshot(horizon: 0))), ["NOW"])
    }

    // MARK: - Fold policy

    func testSingleSilentDayStaysBare() {
        XCTAssertEqual(tokens(composer.compose(snapshot(horizon: 1))), ["NOW", "DAY(1)"])
    }

    func testTwoOrMoreSilentDaysFold() {
        XCTAssertEqual(tokens(composer.compose(snapshot(horizon: 3))), ["NOW", "FOLD(3@1)"])
    }

    func testEventFlushesTheSilentRun() {
        // days 1,2 silent → fold(2); meal on 3; day 4 silent alone → bare.
        let entries = composer.compose(snapshot(horizon: 4, events: [plannedMeal(3, "Orzo")]))
        XCTAssertEqual(tokens(entries), ["NOW", "FOLD(2@1)", "MEAL(Orzo@3)", "DAY(4)"])
    }

    func testWhisperedDayDoesNotFold() {
        let entries = composer.compose(snapshot(
            horizon: 3, whispers: [DatedWhisper(date: day(2), text: "ragù waiting")]))
        XCTAssertEqual(tokens(entries), ["NOW", "DAY(1)", "WHISPER(2)", "DAY(3)"])
    }

    func testNeverTwoAdjacentBareDays() {
        // A long, sparsely-populated horizon must never stack empty rows.
        let entries = composer.compose(snapshot(
            horizon: 21, events: [plannedMeal(4, "A"), expiry(10, "spinach"), plannedMeal(17, "B")]))
        for (a, b) in zip(entries, entries.dropFirst()) {
            if case .day(_, nil) = a, case .day(_, nil) = b {
                XCTFail("two adjacent bare days: \(tokens([a, b]))")
            }
        }
    }

    // MARK: - Within-day ordering & today exclusion

    func testMealLeadsExpiryOnSameDay() {
        let entries = composer.compose(snapshot(
            horizon: 2, events: [expiry(1, "spinach"), plannedMeal(1, "Orzo")]))
        XCTAssertEqual(tokens(entries), ["NOW", "MEAL(Orzo@1)", "EXP(spinach@1)", "DAY(2)"])
    }

    func testTodaysEventsAreNotInTheFutureRuler() {
        // An event dated today belongs to the now-module, not the future ruler.
        let entries = composer.compose(snapshot(horizon: 2, events: [plannedMeal(0, "Tonight")]))
        XCTAssertEqual(tokens(entries), ["NOW", "FOLD(2@1)"])
    }

    // MARK: - Past journal

    func testJournalIsPastOrderedOldestFirstBeforeNow() {
        let j1 = JournalItem(date: day(-3), name: "Ragù", plate: .init(categories: [.protein], seed: 1), level: .cooked)
        let j2 = JournalItem(date: day(-1), name: "Shakshuka", plate: .init(categories: [.protein], seed: 2), level: .cooked)
        let entries = composer.compose(snapshot(horizon: 0, journal: [j2, j1]))
        XCTAssertEqual(tokens(entries), ["J(Ragù)", "J(Shakshuka)", "NOW"])
    }

    // MARK: - Week markers

    func testWeekMarkerAtBoundaryCarriesPlannedCount() {
        // horizon 8 crosses into the week of Jan 8; a meal on day 8 → plannedCount 1.
        let entries = composer.compose(snapshot(horizon: 8, events: [plannedMeal(8, "Salmon")]))
        let weeks = entries.filter { if case .week = $0 { return true } else { return false } }
        XCTAssertEqual(weeks.count, 1)
        if case .week(_, let count)? = weeks.first {
            XCTAssertEqual(count, 1)
        } else {
            XCTFail("expected a week marker")
        }
    }
}
