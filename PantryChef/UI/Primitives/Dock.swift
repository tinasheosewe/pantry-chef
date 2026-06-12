import SwiftUI

/// The three root spaces of the redesign (spec §3). Cook is an instrument entered
/// from the timeline, and "add" is the composer — neither is a space.
enum RootSpace: String, CaseIterable, Identifiable, Sendable {
    case timeline, library, stock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline: return "Today"
        case .library: return "Library"
        case .stock: return "Stock"
        }
    }

    var icon: String {
        switch self {
        case .timeline: return "calendar.day.timeline.left"
        case .library: return "book"
        case .stock: return "archivebox"
        }
    }
}

/// The floating glass dock: a glass pill of root spaces plus a separate add button
/// (the composer). Active space reads as an ink circle; the rest are quiet.
struct Dock: View {
    @Binding var selection: RootSpace
    var onAdd: () -> Void

    @State private var themeFlips = 0

    var body: some View {
        HStack(spacing: Theme.Metric.sm) {
            HStack(spacing: 6) {
                ForEach(RootSpace.allCases) { space in
                    spaceButton(space)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassCard(cornerRadius: Theme.Metric.chipCornerRadius)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Theme.Palette.paprika)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.pressable)
            .glassCard(cornerRadius: Theme.Metric.chipCornerRadius)
            .accessibilityLabel("Add")
            // Long-press flips the visual world (cream/glass ↔ green ink) for the
            // in-hand A/B trial; tap still opens the composer.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.45)) {
                        ThemeManager.shared.cycle()
                    }
                    themeFlips += 1
                }
            )
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.success, trigger: themeFlips)
    }

    private func spaceButton(_ space: RootSpace) -> some View {
        let isActive = selection == space
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = space }
        } label: {
            Image(systemName: space.icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(isActive ? Theme.Palette.cream : Theme.Palette.warmGraySoft)
                .frame(width: 46, height: 46)
                .background {
                    if isActive {
                        Circle().fill(Theme.Palette.ink)
                    }
                }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(space.title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

#Preview("Dock") {
    struct Harness: View {
        @State private var selection: RootSpace = .timeline
        var body: some View {
            ZStack(alignment: .bottom) {
                Theme.Palette.cream.ignoresSafeArea()
                Dock(selection: $selection, onAdd: {})
                    .padding(.bottom, 20)
            }
        }
    }
    return Harness()
}
