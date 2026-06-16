import Foundation

/// Turns a `KitchenSnapshot` into the ordered rows of the timeline (spec §4). Pure
/// and deterministic — the make-or-break component, so it owns the whole policy in
/// one place and is golden-file tested:
///
///   • past = the journal, oldest→newest, real entries only (never invented);
///   • now  = a single anchor slot the now-module fills;
///   • future = a day ruler from tomorrow to the horizon, where dated events and
///     whispered days punctuate bare days, runs of ≥2 silent days fold into a tick
///     cluster, and week boundaries get a marker.
///
/// The result is never blank and never a wall of empty rows: silence compresses.
struct TimelineComposer {
    var calendar: Calendar = .current

    func compose(_ snapshot: KitchenSnapshot) -> [TimelineEntry] {
        let todayStart = calendar.startOfDay(for: snapshot.today)
        var out: [TimelineEntry] = []

        // Past — a backward ruler when a window is set, else just the journal record.
        if snapshot.pastDays > 0 {
            out += composePast(snapshot, todayStart: todayStart)
        } else {
            out += snapshot.journal
                .filter { calendar.startOfDay(for: $0.date) < todayStart }
                .sorted { $0.date < $1.date }
                .map(TimelineEntry.journal)
        }

        // Now — the anchor; its content is the now-module's job.
        out.append(.now)

        // Future — the woven ruler.
        out += composeFuture(snapshot, todayStart: todayStart)
        return out
    }

    /// The backward ruler: journal entries on their days, quiet runs folded, oldest
    /// first. No week markers (a "nothing planned" marker reads wrong in the past).
    private func composePast(_ snapshot: KitchenSnapshot, todayStart: Date) -> [TimelineEntry] {
        let journalByDay = Dictionary(grouping: snapshot.journal.filter {
            calendar.startOfDay(for: $0.date) < todayStart
        }) { calendar.startOfDay(for: $0.date) }

        var out: [TimelineEntry] = []
        var silentRun: [Date] = []
        func flush() {
            switch silentRun.count {
            case 0: break
            case 1: out.append(.day(date: silentRun[0], whisper: nil))
            default: out.append(.fold(start: silentRun.first!, end: silentRun.last!, dayCount: silentRun.count))
            }
            silentRun.removeAll(keepingCapacity: true)
        }

        for offset in stride(from: -snapshot.pastDays, through: -1, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            let items = (journalByDay[dayStart] ?? []).sorted { $0.date < $1.date }
            if !items.isEmpty {
                flush()
                out += items.map(TimelineEntry.journal)
            } else {
                silentRun.append(dayStart)
            }
        }
        flush()
        return out
    }

    // MARK: - Future weaving

    private func composeFuture(_ snapshot: KitchenSnapshot, todayStart: Date) -> [TimelineEntry] {
        guard snapshot.horizonDays > 0 else { return [] }

        let eventsByDay = Dictionary(grouping: snapshot.events) { calendar.startOfDay(for: $0.date) }
        let whisperByDay = Dictionary(grouping: snapshot.whispers) { calendar.startOfDay(for: $0.date) }

        var out: [TimelineEntry] = []
        var silentRun: [Date] = []

        func flushSilentRun() {
            switch silentRun.count {
            case 0: break
            case 1: out.append(.day(date: silentRun[0], whisper: nil))
            default: out.append(.fold(start: silentRun.first!, end: silentRun.last!, dayCount: silentRun.count))
            }
            silentRun.removeAll(keepingCapacity: true)
        }

        var lastWeekStart = weekStart(of: todayStart) // current week — no marker for it
        for offset in 1...snapshot.horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let dayStart = calendar.startOfDay(for: day)

            let week = weekStart(of: dayStart)
            if week != lastWeekStart {
                flushSilentRun()
                out.append(.week(start: week, plannedCount: plannedMealCount(inWeekOf: week, events: snapshot.events)))
                lastWeekStart = week
            }

            let dayEvents = eventsByDay[dayStart] ?? []
            if !dayEvents.isEmpty {
                flushSilentRun()
                out += dayEntries(dayStart: dayStart, events: dayEvents)
            } else if let whisper = whisperByDay[dayStart]?.first?.text {
                flushSilentRun()
                out.append(.day(date: dayStart, whisper: whisper))
            } else {
                silentRun.append(dayStart)
            }
        }
        flushSilentRun()
        return out
    }

    // MARK: - Helpers

    private func entry(for event: DatedEvent) -> TimelineEntry {
        switch event.kind {
        case .meal(let m): return .meal(m)
        case .expiry(let e): return .expiry(e)
        case .proposal(let p): return .proposal(p)
        }
    }

    /// One day's rows: the meals lead (a single one as its own card, 2+ gathered into
    /// a `.mealDay` under one header, always ordered morning → evening), then the
    /// deadline they address, then any invitation.
    private func dayEntries(dayStart: Date, events: [DatedEvent]) -> [TimelineEntry] {
        var meals: [PlannedMeal] = []
        var rest: [DatedEvent] = []
        for event in events {
            if case .meal(let m) = event.kind { meals.append(m) } else { rest.append(event) }
        }
        meals.sort { ($0.dayPart, $0.date) < ($1.dayPart, $1.date) }
        rest.sort { (order($0), $0.date) < (order($1), $1.date) }

        var out: [TimelineEntry] = []
        if meals.count >= 2 {
            out.append(.mealDay(date: dayStart, meals: meals))
        } else {
            out += meals.map(TimelineEntry.meal)
        }
        out += rest.map(entry(for:))
        return out
    }

    /// Stable within-day ordering for non-meal events: the deadline before any
    /// invitation (meals are pulled out and lead, in `dayEntries`).
    private func order(_ event: DatedEvent) -> Int {
        switch event.kind {
        case .meal: return 0
        case .expiry: return 1
        case .proposal: return 2
        }
    }

    private func weekStart(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func plannedMealCount(inWeekOf weekStart: Date, events: [DatedEvent]) -> Int {
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return 0 }
        return events.filter { event in
            guard case .meal = event.kind else { return false }
            return event.date >= weekStart && event.date < weekEnd
        }.count
    }
}
