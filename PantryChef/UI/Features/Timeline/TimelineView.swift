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
    var onReachStart: () -> Void = {}
    var onReachEnd: () -> Void = {}
    /// Live content for the `.now` row (the now-module). When nil, a placeholder
    /// is shown — keeps previews and standalone use simple.
    var nowContent: (() -> AnyView)?

    @State private var visibleID: String?
    @State private var unfolded: Set<String> = []
    @State private var extending = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        rows(for: entry)
                            .id(entry.id)
                            .onAppear { edgeCheck(entry) }
                    }
                }
                .scrollTargetLayout()
                .padding(.top, 8)
                .padding(.bottom, 90) // room for the floating dock
            }
            .scrollPosition(id: $visibleID, anchor: .top)
        }
        .background(background)
        .onAppear {
            if visibleID == nil {
                DispatchQueue.main.async { visibleID = TimelineEntry.now.id }
            }
        }
    }

    // MARK: - Pinned header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(headerMonth).font(Theme.Typography.dish(21)).foregroundStyle(Theme.Palette.ink)
                .animation(nil, value: headerMonth)
            Spacer()
            if isAwayFromNow {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        visibleID = TimelineEntry.now.id
                    }
                } label: {
                    Label("Today", systemImage: "smallcircle.filled.circle")
                        .font(Theme.Typography.fact(12, weight: .medium))
                        .foregroundStyle(Theme.Palette.paprika)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Theme.Palette.paprika.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Text(DayLabel.full(for: today)).font(Theme.Typography.fact(12))
                    .foregroundStyle(Theme.Palette.warmGraySoft)
            }
        }
        .padding(.leading, Theme.Metric.spineWidth)
        .padding(.trailing, Theme.Metric.lg)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var headerMonth: String {
        DayLabel.month(for: visibleID.flatMap(date(forEntryID:)) ?? today)
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

    // MARK: - Infinite extension

    private func edgeCheck(_ entry: TimelineEntry) {
        guard !extending else { return }
        if entry.id == entries.first?.id {
            extending = true
            onReachStart()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { extending = false }
        } else if entry.id == entries.last?.id {
            extending = true
            onReachEnd()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { extending = false }
        }
    }

    private var background: some View {
        ZStack {
            Theme.Palette.cream
            RadialGradient(
                colors: [Theme.Palette.creamRaised.opacity(0.9), Theme.Palette.creamRaised.opacity(0)],
                center: .init(x: 0.5, y: 0.18), startRadius: 0, endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

extension DayLabel {
    static func month(for date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM"; return f.string(from: date)
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
