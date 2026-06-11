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

    var body: some View {
        HStack(spacing: Theme.Metric.sm) {
            HStack(spacing: Theme.Metric.xs) {
                ForEach(RootSpace.allCases) { space in
                    spaceButton(space)
                }
            }
            .padding(.horizontal, Theme.Metric.sm)
            .padding(.vertical, 6)
            .glassCard(cornerRadius: Theme.Metric.chipCornerRadius)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.Palette.paprika)
                    .frame(width: 45, height: 45)
            }
            .buttonStyle(.plain)
            .glassCard(cornerRadius: Theme.Metric.chipCornerRadius)
            .accessibilityLabel("Add")
        }
    }

    private func spaceButton(_ space: RootSpace) -> some View {
        let isActive = selection == space
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = space }
        } label: {
            Image(systemName: space.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? Theme.Palette.cream : Theme.Palette.warmGraySoft)
                .frame(width: 33, height: 33)
                .background {
                    if isActive {
                        Circle().fill(Theme.Palette.ink)
                    }
                }
        }
        .buttonStyle(.plain)
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
