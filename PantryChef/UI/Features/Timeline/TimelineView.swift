import SwiftUI

/// The timeline screen body: a scrolling ruler of composed rows over warm light.
/// A dumb renderer — it takes already-composed entries (the composer is upstream).
struct TimelineView: View {
    let entries: [TimelineEntry]
    var today: Date = Date()
    var onTapDay: (Date) -> Void = { _ in }
    /// Opens the recipe behind a tapped meal/journal node (by dish name).
    var onOpenMeal: (String) -> Void = { _ in }
    /// Live content for the `.now` row (the now-module). When nil, a placeholder
    /// is shown — keeps previews and standalone use simple.
    var nowContent: (() -> AnyView)?

    @State private var didInitialScroll = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(entries) { entry in
                        row(for: entry).id(entry.id)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 90) // room for the floating dock
            }
            .background(background)
            .onAppear {
                guard !didInitialScroll else { return }
                didInitialScroll = true
                // Open anchored at "now": the journal sits above (scroll up), the
                // future below (scroll down).
                DispatchQueue.main.async {
                    proxy.scrollTo(TimelineEntry.now.id, anchor: UnitPoint(x: 0.5, y: 0.12))
                }
            }
        }
    }

    @ViewBuilder private func row(for entry: TimelineEntry) -> some View {
        if case .now = entry, let nowContent {
            HStack(alignment: .top, spacing: 0) {
                SpineGutter(node: .now)
                nowContent().padding(.bottom, Theme.Metric.md)
                Spacer(minLength: 0)
            }
            .padding(.trailing, Theme.Metric.lg)
        } else {
            TimelineRow(entry: entry, onTapDay: onTapDay, onOpenMeal: onOpenMeal)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(DayLabel.month(for: today)).font(Theme.Typography.dish(21))
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Text(DayLabel.full(for: today)).font(Theme.Typography.fact(12))
                .foregroundStyle(Theme.Palette.warmGraySoft)
        }
        .padding(.leading, Theme.Metric.spineWidth)
        .padding(.trailing, Theme.Metric.lg)
        .padding(.bottom, Theme.Metric.lg)
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
        journal: [
            JournalItem(date: day(-2), name: "Lamb ragù", plate: plate([.protein, .pasta], 3),
                        level: .cooked, note: "batch cooked, 3 servings"),
            JournalItem(date: day(-1), name: "Shakshuka", plate: plate([.protein, .produce, .spices], 2),
                        level: .cooked, note: "your sixth this spring")
        ],
        events: [
            DatedEvent(kind: .expiry(ExpiryMilestone(date: day(3), itemName: "spinach"))),
            DatedEvent(kind: .meal(PlannedMeal(date: day(8), name: "Miso salmon",
                                               plate: plate([.protein, .oils], 5), level: .cooked, missingCount: 2))),
            DatedEvent(kind: .proposal(Proposal(date: day(12), text: "Your list hit 5 items — shop this weekend?")))
        ],
        whispers: [DatedWhisper(date: day(1), text: "ragù waiting · 3 portions")]
    )
    let entries = TimelineComposer(calendar: cal).compose(snapshot)
    return TimelineView(entries: entries, today: today)
}
