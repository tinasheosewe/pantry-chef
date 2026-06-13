import SwiftUI

/// Renders one composed `TimelineEntry`: its spine marker plus content. A dumb
/// renderer — all policy lives upstream in `TimelineComposer`.
struct TimelineRow: View {
    let entry: TimelineEntry
    var onTapDay: (Date) -> Void = { _ in }
    var onOpenMeal: (String) -> Void = { _ in }
    var onDismissProposal: (UUID) -> Void = { _ in }
    var onOpenStock: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SpineGutter(node: node)
            content.padding(.bottom, Theme.Metric.md)
            Spacer(minLength: 0)
        }
        .padding(.trailing, Theme.Metric.lg)
    }

    private var node: SpineNode {
        switch entry {
        case .now: return .now
        case .journal: return .journal
        case .meal: return .meal
        case .expiry: return .expiry
        case .proposal: return .proposal
        case .day: return .day
        case .fold: return .fold
        case .week: return .week
        }
    }

    @ViewBuilder private var content: some View {
        switch entry {
        case .now: nowSlot
        case .journal(let j): journalRow(j).contentShape(Rectangle()).onTapGesture { onOpenMeal(j.name) }
        case .meal(let m): mealCard(m).onTapGesture { onOpenMeal(m.name) }
        case .expiry(let e): expiryRow(e).contentShape(Rectangle()).onTapGesture { onOpenStock() }
        case .proposal(let p):
            proposalCard(p).onTapGesture { onDismissProposal(p.id) }
        case .day(let date, let whisper): dayRow(date, whisper)
        case .fold(_, _, let count): foldRow(count)
        case .week(let start, let count): weekRow(start, count)
        }
    }

    // MARK: - Content

    private var nowSlot: some View {
        VStack(alignment: .leading, spacing: 6) {
            eyebrow("Tonight", color: Theme.Palette.paprika)
            Text("What you could make appears here.")
                .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.warmGray)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func journalRow(_ j: JournalItem) -> some View {
        HStack(spacing: 10) {
            PlateView(name: j.name, composition: j.plate, size: Theme.Metric.plateMini)
            VStack(alignment: .leading, spacing: 1) {
                Text(j.name).font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
                if let note = j.note {
                    Text(note).font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
                }
            }
        }
        .opacity(0.62)
    }

    private func mealCard(_ m: PlannedMeal) -> some View {
        HStack(spacing: 11) {
            PlateView(name: m.name, composition: m.plate, size: Theme.Metric.plateRow)
            VStack(alignment: .leading, spacing: 2) {
                Text(DayLabel.eyebrow(for: m.date).uppercased())
                    .font(.system(size: 9)).tracking(Theme.Metric.eyebrowTracking)
                    .foregroundStyle(Theme.Palette.ink.opacity(0.55))
                Text(m.name).font(Theme.Typography.dish(16)).foregroundStyle(Theme.Palette.ink)
                if m.missingCount > 0 {
                    Text("NEEDS \(m.missingCount) → LIST")
                        .font(.system(size: 9)).tracking(1.6)
                        .foregroundStyle(Theme.Palette.paprika)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private func expiryRow(_ e: ExpiryMilestone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(DayLabel.eyebrow(for: e.date)) — \(e.itemName) turns")
                .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.ink)
            if e.rescued {
                Label("rescued", systemImage: "checkmark")
                    .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.top, 2)
    }

    private func proposalCard(_ p: Proposal) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(p.text)
                .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink.opacity(0.85))
            Spacer(minLength: 0)
            Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Palette.warmGraySoft.opacity(0.7))
                .padding(.top, 3)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Rectangle()
                .strokeBorder(Theme.Palette.ink.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .contentShape(Rectangle())
    }

    private func dayRow(_ date: Date, _ whisper: String?) -> some View {
        Button { onTapDay(date) } label: {
            HStack {
                Text(DayLabel.full(for: date)).font(Theme.Typography.fact(12))
                    .foregroundStyle(Theme.Palette.warmGraySoft)
                Spacer()
                if let whisper {
                    Text(whisper).font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
                }
            }
            .padding(.top, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func foldRow(_ count: Int) -> some View {
        Text("\(count) quiet days — nothing needs you")
            .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGraySoft.opacity(0.9))
            .padding(.top, 3)
    }

    private func weekRow(_ start: Date, _ count: Int) -> some View {
        Text("Week of \(DayLabel.monthDay(for: start)) — \(count == 0 ? "nothing yet" : "\(count) planned")")
            .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
            .tracking(0.6)
            .padding(.top, 4)
    }

    private func eyebrow(_ text: String, color: Color) -> some View {
        Text(text.uppercased()).font(Theme.Typography.eyebrow).tracking(Theme.Metric.eyebrowTracking)
            .foregroundStyle(color)
    }
}

/// Date labels for timeline rows, formatted once and reused.
enum DayLabel {
    private static let weekdayDay: DateFormatter = formatter("EEEE d")
    private static let eyebrowFmt: DateFormatter = formatter("EEEE")
    private static let monthDayFmt: DateFormatter = formatter("MMM d")

    static func full(for date: Date) -> String { weekdayDay.string(from: date) }
    static func eyebrow(for date: Date) -> String { eyebrowFmt.string(from: date) }
    static func monthDay(for date: Date) -> String { monthDayFmt.string(from: date) }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        return f
    }
}
