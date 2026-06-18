import SwiftUI

/// The three root spaces of the redesign. Today is the feed-first landing — a pinned
/// "cook now" hero over an image-led recipe feed (it absorbed the old Ideas tab, whose
/// only unique content was the feed). Plan is the day-by-day ruler; Pantry holds stock
/// + expiry warnings. Cook is an instrument, and "add" is the composer — not spaces.
enum RootSpace: String, CaseIterable, Identifiable, Sendable {
    case today, plan, pantry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .plan: return "Plan"
        case .pantry: return "Pantry"
        }
    }
}

/// The page floor (Field Notes): a solid rule, the inked nav band — TODAY ·
/// DISHES · STORES · ＋ — and the ❧ tailpiece carrying one true line. Printed
/// furniture, not a floating pill.
struct Dock: View {
    @Binding var selection: RootSpace
    var onAdd: () -> Void
    /// The page's one true closing line; varies by space.
    var tailpiece: String = ""
    /// Per-space warning counts (e.g. expiry on Pantry) — a small tomato block on the
    /// label, so a warning is visible from any space, not only when you're standing in it.
    var badges: [RootSpace: Int] = [:]

    var body: some View {
        VStack(spacing: 0) {
            SolidRule()
            HStack(spacing: 0) {
                ForEach(RootSpace.allCases) { space in
                    spaceButton(space)
                }
                Button(action: onAdd) {
                    Text("＋")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Palette.paprika)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Add")
            }
            if !tailpiece.isEmpty {
                Tailpiece(text: tailpiece).padding(.bottom, 6)
            }
        }
        .background(Theme.Palette.cream)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func spaceButton(_ space: RootSpace) -> some View {
        let isActive = selection == space
        let badge = badges[space] ?? 0
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = space }
        } label: {
            VStack(spacing: 3) {
                Text(space.title.uppercased())
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .tracking(Theme.Metric.eyebrowTracking)
                    .foregroundStyle(isActive ? Theme.Palette.ink : Theme.Palette.ink.opacity(0.5))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 { badgeBlock(badge).offset(x: 13, y: -6) }
                    }
                Rectangle()
                    .fill(isActive ? Theme.Palette.paprika : .clear)
                    .frame(width: 22, height: 2)
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(space.title)
        .accessibilityValue(badge > 0 ? "\(badge) expiring" : "")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// The squared tomato count block — printed furniture, not a round iOS pill.
    private func badgeBlock(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.Palette.cream)
            .frame(minWidth: 14, minHeight: 14)
            .padding(.horizontal, 2)
            .background(Rectangle().fill(Theme.Palette.paprika))
    }
}

#Preview("Dock") {
    struct Harness: View {
        @State private var selection: RootSpace = .today
        var body: some View {
            ZStack(alignment: .bottom) {
                Theme.Palette.cream.ignoresSafeArea()
                Dock(selection: $selection, onAdd: {}, tailpiece: "№ 163 · 3 ready tonight")
            }
        }
    }
    return Harness()
}
