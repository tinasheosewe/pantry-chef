import SwiftUI

/// Renders the now-module in whichever of its four states it's in (spec §5). The
/// glass card the timeline shows at "now". A dumb renderer over `NowState`.
struct NowModuleView: View {
    @Binding var state: NowState
    var onCook: (FanOption) -> Void = { _ in }
    var onSeeAll: () -> Void = {}
    var onChange: () -> Void = {}
    var onResume: () -> Void = {}
    /// Log how much of a freshly cooked dish was eaten / kept (the "Done" card).
    var onLog: (Dish) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow
            content
        }
    }

    private var eyebrow: some View {
        Eyebrow(text: state.eyebrow(at: DayPart.current()), tone: isCooked ? .win : .urgent)
    }
    private var isCooked: Bool { if case .cooked = state { return true } else { return false } }

    @ViewBuilder private var content: some View {
        switch state {
        case .open(let options, let selected):
            FanView(
                options: options,
                selected: Binding(
                    get: { selected },
                    set: { state = .open(options: options, selected: $0) }
                ),
                onCook: onCook, onSeeAll: onSeeAll
            )
        case .committed(let meal):
            committedCard(meal)
        case .cooking(let p):
            cookingCard(p)
        case .cooked(let s):
            cookedCard(s)
        }
    }

    // MARK: - Committed / cooking / cooked

    private func committedCard(_ meal: CommittedMeal) -> some View {
        HStack(spacing: 11) {
            PlateView(name: meal.name, composition: meal.plate, size: Theme.Metric.plateRow)
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.name).font(Theme.Typography.dish(16)).foregroundStyle(Theme.Palette.ink)
                Text(meal.logistics).font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGray)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8).frame(maxWidth: .infinity)
        .overlay(alignment: .bottomTrailing) {
            actionRow(secondary: "Change", primary: "View",
                      secondaryAction: onChange,
                      primaryAction: {
                          onCook(FanOption(name: meal.name, plate: meal.plate, subtitle: "",
                                           reason: "", level: meal.level, dish: meal.dish))
                      })
                .padding(14)
        }
    }

    private func cookingCard(_ p: CookingProgress) -> some View {
        Button(action: onResume) {
            HStack(spacing: 11) {
                PlateView(name: p.name, composition: p.plate, size: Theme.Metric.plateRow)
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name).font(Theme.Typography.dish(15)).foregroundStyle(Theme.Palette.ink)
                    HStack(spacing: 6) {
                        Text("Step \(p.stepIndex + 1) of \(p.totalSteps)")
                            .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGray)
                        if let t = p.timerText {
                            Text(t).font(Theme.Typography.numeral(11)).foregroundStyle(Theme.Palette.paprika)
                        }
                    }
                    ProgressBar(fraction: p.fraction)
                }
                Spacer(minLength: 0)
                Text("Resume").font(Theme.Typography.fact(12, weight: .medium))
                    .foregroundStyle(Theme.Palette.cream)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.Palette.ink))
            }
            .padding(.vertical, 8).frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func cookedCard(_ s: CookedSummary) -> some View {
        // Actions sit on their own row beneath the summary (not overlaid) so the
        // primary button never overlaps the text or clips at the right edge.
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                PlateView(name: s.name, composition: s.plate, size: Theme.Metric.plateRow)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15)).foregroundStyle(Theme.Palette.sage)
                            .background(Circle().fill(Theme.Palette.cream).padding(1))
                            .offset(x: 3, y: 3)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.name).font(Theme.Typography.dish(15)).foregroundStyle(Theme.Palette.ink)
                    Text(s.summary).font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGray)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                // A fresh cook offers "Log" (how much eaten/kept); once logged (dish
                // nil), just a Dismiss back to the fan so the summary never dead-ends.
                Button("Dismiss", action: onChange)
                    .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGraySoft)
                    .buttonStyle(.plain)
                if let dish = s.dish {
                    PaprikaButton(title: "Log") { onLog(dish) }
                }
            }
        }
        .padding(.vertical, 8).frame(maxWidth: .infinity)
    }

    private func actionRow(secondary: String, primary: String,
                           secondaryAction: @escaping () -> Void,
                           primaryAction: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(secondary, action: secondaryAction)
                .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGraySoft)
                .buttonStyle(.plain)
            PaprikaButton(title: primary, action: primaryAction)
        }
    }
}

/// The thin paprika progress line used in the cooking state.
private struct ProgressBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.hairline)
                Capsule().fill(Theme.Palette.paprika).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

/// The one filled action button used across the redesign — the squared tomato
/// block of the printed page.
struct PaprikaButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        BlockButton(title: title, action: action)
    }
}

#Preview("Now — fan") {
    struct Harness: View {
        @State var state: NowState = .open(options: [
            FanOption(name: "Herb frittata", plate: .init(categories: [.dairy, .produce], seed: 9),
                      subtitle: "15 min · 5 of 5 on hand", reason: "The fast pick — fifteen minutes, start to plate."),
            FanOption(name: "Spinach & feta orzo", plate: .init(categories: [.produce, .dairy, .pasta], seed: 1),
                      subtitle: "25 min · 6 of 6 on hand", reason: "The rescue pick — spinach won't see Friday."),
            FanOption(name: "Lamb ragù", plate: .init(categories: [.protein, .pasta, .produce], seed: 3),
                      subtitle: "2 h 10 · 7 of 9 on hand", reason: "The ambitious pick — and it freezes beautifully.",
                      readiness: .needs(items: ["wine", "celery"]))
        ], selected: 1)
        var body: some View {
            ZStack { Theme.Palette.cream.ignoresSafeArea()
                NowModuleView(state: $state).padding(20)
            }
        }
    }
    return Harness()
}
