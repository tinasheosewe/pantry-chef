import SwiftUI

/// The three root spaces of the redesign (spec §3). Cook is an instrument entered
/// from the timeline, and "add" is the composer — neither is a space.
enum RootSpace: String, CaseIterable, Identifiable, Sendable {
    case timeline, library, stock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline: return "Today"
        case .library: return "Dishes"
        case .stock: return "Stores"
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
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = space }
        } label: {
            VStack(spacing: 3) {
                Text(space.title.uppercased())
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .tracking(Theme.Metric.eyebrowTracking)
                    .foregroundStyle(isActive ? Theme.Palette.ink : Theme.Palette.ink.opacity(0.5))
                Rectangle()
                    .fill(isActive ? Theme.Palette.paprika : .clear)
                    .frame(width: 22, height: 2)
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .contentShape(Rectangle())
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
                Dock(selection: $selection, onAdd: {}, tailpiece: "№ 163 · 3 ready tonight")
            }
        }
    }
    return Harness()
}
