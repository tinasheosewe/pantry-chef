import SwiftUI

/// The timeline screen: a pinned header (month tracks the scroll; "Today" returns
/// to now) over an effectively infinite ruler — scrolling near either edge asks the
/// store to extend the window. Folds unfurl in place when tapped.
struct TimelineView: View {
    let entries: [TimelineEntry]
    var today: Date = Date()
    var onTapDay: (Date) -> Void = { _ in }
    /// Opens the recipe behind a tapped meal/journal node (by dish name).
    var onOpenMeal: (String) -> Void = { _ in }
    var onDismissProposal: (UUID) -> Void = { _ in }
    var onOpenStock: () -> Void = {}
    /// Opens the date picker to plan a day beyond the visible horizon.
    var onPlanAhead: () -> Void = {}
    /// Opens the app's Settings surface (preferences + dietary profile).
    var onSettings: () -> Void = {}
    /// Live content for the `.now` row (the now-module). When nil, a placeholder
    /// is shown — keeps previews and standalone use simple.
    var nowContent: (() -> AnyView)?

    @State private var visibleID: String?
    @State private var unfolded: Set<String> = []
    /// Flipped on for a single runloop tick to kill in-flight scroll momentum so
    /// "return to today" lands even when tapped mid-deceleration.
    @State private var scrollLocked = false

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header(proxy)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        recordCap
                        ForEach(entries) { entry in
                            rows(for: entry)
                                .id(entry.id)
                        }
                        horizonCap
                    }
                    .scrollTargetLayout()
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollPosition(id: $visibleID, anchor: .top)
                .scrollDisabled(scrollLocked)
            }
            .background(background)
            .onAppear {
                if visibleID == nil {
                    DispatchQueue.main.async { visibleID = TimelineEntry.now.id }
                }
            }
        }
    }

    // MARK: - Pinned header

    /// Always-available "return to today". A tap landed mid-deceleration is
    /// otherwise swallowed — SwiftUI ignores both `scrollTo` and `scrollPosition`
    /// while the scroll view still carries momentum. Disabling scrolling for one
    /// runloop tick halts that momentum; the next tick then jumps us home.
    private func returnToToday(_ proxy: ScrollViewProxy) {
        scrollLocked = true
        DispatchQueue.main.async {
            scrollLocked = false
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                proxy.scrollTo(TimelineEntry.now.id, anchor: .top)
                visibleID = TimelineEntry.now.id
            }
        }
    }

    private func header(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(headerTitle).font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                    .animation(nil, value: headerTitle)
                Spacer()
                if isAwayFromNow {
                    Button { returnToToday(proxy) } label: {
                        Text("TODAY")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(Theme.Metric.eyebrowTracking)
                            .foregroundStyle(Theme.Palette.paprika)
                            .padding(.vertical, 4).padding(.leading, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                } else {
                    Text(headerMeta)
                        .font(.system(size: 10))
                        .tracking(Theme.Metric.eyebrowTracking)
                        .foregroundStyle(Theme.Palette.ink.opacity(0.55))
                }
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Palette.ink.opacity(0.5))
                        .padding(.vertical, 4).padding(.leading, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            .padding(.leading, Theme.Metric.spineWidth)
            .padding(.trailing, Theme.Metric.lg)
            .padding(.top, 6)
            DashedRule()
                .padding(.leading, Theme.Metric.spineWidth)
                .padding(.trailing, Theme.Metric.lg)
                .padding(.top, 9)
                .padding(.bottom, 2)
        }
    }

    /// "June 12" while at now; the visible month while travelling.
    private var headerTitle: String {
        let visible = visibleID.flatMap(date(forEntryID:)) ?? today
        return isAwayFromNow ? DayLabel.month(for: visible) : DayLabel.monthDayLong(for: today)
    }

    /// "FRIDAY — DAY 163"
    private var headerMeta: String {
        let dayNumber = Calendar.current.ordinality(of: .day, in: .year, for: today) ?? 0
        return "\(DayLabel.eyebrow(for: today).uppercased()) — DAY \(dayNumber)"
    }

    private var isAwayFromNow: Bool {
        guard let id = visibleID, id != TimelineEntry.now.id else { return false }
        // Near-now ids (the entries right around the anchor) don't count as "away".
        guard let d = date(forEntryID: id) else { return false }
        return abs(d.timeIntervalSince(today)) > 3 * 86_400
    }

    private func date(forEntryID id: String) -> Date? {
        guard let entry = entries.first(where: { $0.id == id }) else { return nil }
        switch entry {
        case .now: return today
        case .journal(let j): return j.date
        case .meal(let m): return m.date
        case .expiry(let e): return e.date
        case .proposal(let p): return p.date
        case .day(let d, _): return d
        case .fold(let s, _, _): return s
        case .week(let s, _): return s
        }
    }

    // MARK: - Rows

    @ViewBuilder private func rows(for entry: TimelineEntry) -> some View {
        if case .now = entry, let nowContent {
            HStack(alignment: .top, spacing: 0) {
                SpineGutter(node: .now)
                nowContent().padding(.bottom, Theme.Metric.md)
                Spacer(minLength: 0)
            }
            .padding(.trailing, Theme.Metric.lg)
        } else if case .fold(let start, let end, _) = entry {
            if unfolded.contains(entry.id) {
                ForEach(daysBetween(start, end), id: \.timeIntervalSince1970) { day in
                    TimelineRow(entry: .day(date: day, whisper: nil), onTapDay: onTapDay)
                }
            } else {
                TimelineRow(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            _ = unfolded.insert(entry.id)
                        }
                    }
            }
        } else {
            TimelineRow(entry: entry, onTapDay: onTapDay, onOpenMeal: onOpenMeal,
                        onDismissProposal: onDismissProposal, onOpenStock: onOpenStock)
        }
    }

    private func daysBetween(_ start: Date, _ end: Date) -> [Date] {
        var days: [Date] = []
        var cursor = start
        let cal = Calendar.current
        while cursor <= end {
            days.append(cursor)
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    // MARK: - Bounds

    /// The page has honest ends rather than a pretend-infinite scroll: a quiet mark
    /// where your record begins, and a planning horizon you extend on purpose.
    private var recordCap: some View {
        Text("— start of your record —")
            .font(Theme.Typography.note(10.5)).tracking(1.2)
            .foregroundStyle(Theme.Palette.ink.opacity(0.32))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2).padding(.bottom, 10)
    }

    private var horizonCap: some View {
        VStack(spacing: 11) {
            DashedRule()
                .padding(.leading, Theme.Metric.spineWidth).padding(.trailing, Theme.Metric.lg)
            Button(action: onPlanAhead) {
                Text("PLAN A DAY AHEAD →")
                    .font(.system(size: 10, weight: .medium)).tracking(Theme.Metric.eyebrowTracking)
                    .foregroundStyle(Theme.Palette.paprika)
                    .padding(.vertical, 6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 16)
    }

    private var background: some View {
        Theme.Palette.cream.ignoresSafeArea()
    }
}

extension DayLabel {
    static func month(for date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM"; return f.string(from: date)
    }
    /// "June 12"
    static func monthDayLong(for date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM d"; return f.string(from: date)
    }
}

#Preview("Timeline — improviser") {
    let cal = Calendar.current
    let today = Date()
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }
    func plate(_ cats: [FoodCategory], _ seed: UInt64) -> PlateComposition { .init(categories: cats, seed: seed) }

    let snapshot = KitchenSnapshot(
        today: today,
        horizonDays: 21,
        pastDays: 14,
        journal: [
            JournalItem(date: day(-2), name: "Lamb ragù", plate: plate([.protein, .pasta], 3),
                        level: .cooked, note: "batch cooked, 3 servings"),
            JournalItem(date: day(-1), name: "Shakshuka", plate: plate([.protein, .produce, .spices], 2),
                        level: .cooked, note: "your sixth this spring")
        ],
        events: [
            DatedEvent(kind: .expiry(ExpiryMilestone(date: day(3), itemName: "spinach"))),
            DatedEvent(kind: .meal(PlannedMeal(date: day(8), name: "Miso butter salmon",
                                               plate: plate([.protein, .oils], 5), level: .cooked, missingCount: 2))),
            DatedEvent(kind: .proposal(Proposal(date: day(12), text: "Your list hit 5 items — milk runs out around Monday.")))
        ],
        whispers: [DatedWhisper(date: day(1), text: "ragù waiting · 3 portions")]
    )
    let entries = TimelineComposer(calendar: cal).compose(snapshot)
    return TimelineView(entries: entries, today: today)
}
