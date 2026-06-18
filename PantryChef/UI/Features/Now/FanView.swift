import SwiftUI

/// TONIGHT (spec §5): a spread of ranked-but-not-dictated plates set directly on
/// the page. The centre plate carries the sommelier reason; swipe or tap a side
/// plate to re-centre — the carousel wraps infinitely. COOK commits; the bordered
/// companion names the alternates.
struct FanView: View {
    let options: [FanOption]
    @Binding var selected: Int
    var onCook: (FanOption) -> Void
    var onSeeAll: () -> Void

    @State private var dragX: CGFloat = 0

    private var count: Int { options.count }
    private var current: FanOption? { options.indices.contains(selected) ? options[selected] : nil }
    private var leftIndex: Int? { count > 1 ? (selected - 1 + count) % count : nil }
    private var rightIndex: Int? { count > 1 ? (selected + 1) % count : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            plates.padding(.top, 4)
            if let option = current {
                Text(option.name)
                    .font(Theme.Typography.dish(19)).foregroundStyle(Theme.Palette.ink)
                    .padding(.top, 10)
                Text("\u{201C}\(option.reason)\u{201D}")
                    .font(Theme.Typography.note(12.5)).foregroundStyle(Theme.Palette.warmGray)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
                    .id(option.id) // re-animate when the centre changes
                    .transition(.opacity)
                Text(option.subtitle.replacingOccurrences(of: "·", with: "—").uppercased())
                    .font(.system(size: 9)).tracking(1.8)
                    .foregroundStyle(Theme.Palette.ink.opacity(0.6))
                    .padding(.top, 5)
                actions(option).padding(.top, 10)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: selected)
    }

    private var plates: some View {
        ZStack {
            if let l = leftIndex { sidePlate(options[l], baseOffset: -82, angle: -8) { advance(-1) } }
            if let r = rightIndex { sidePlate(options[r], baseOffset: 82, angle: 8) { advance(1) } }
            if let centre = current {
                PlateView(name: centre.name, composition: centre.plate, size: Theme.Metric.plateHero)
                    .offset(x: dragX * 0.45)
                    .zIndex(2)
            }
        }
        .frame(height: Theme.Metric.plateHero + 8)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { dragX = $0.translation.width }
                .onEnded { value in
                    let threshold: CGFloat = 48
                    if value.translation.width <= -threshold { advance(1) }
                    else if value.translation.width >= threshold { advance(-1) }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { dragX = 0 }
                }
        )
    }

    private func sidePlate(_ option: FanOption, baseOffset: CGFloat, angle: Double,
                           tap: @escaping () -> Void) -> some View {
        PlateView(name: option.name, composition: option.plate, size: Theme.Metric.plateHero * 0.58)
            .rotationEffect(.degrees(angle))
            .offset(x: baseOffset + dragX * 0.45, y: 10)
            .opacity(0.8)
            .zIndex(1)
            .onTapGesture(perform: tap)
            .accessibilityLabel("See \(option.name)")
    }

    private func advance(_ direction: Int) {
        guard count > 1 else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            selected = (selected + direction + count) % count
        }
    }

    private func actions(_ option: FanOption) -> some View {
        HStack(spacing: 8) {
            BlockButton(title: option.level.verb) { onCook(option) }
            if count > 1 {
                OutlineButton(title: "⟨ \(alternateNames) ⟩") { advance(1) }
            }
            Spacer(minLength: 0)
            Button(action: onSeeAll) {
                Text("SEE ALL")
                    .font(.system(size: 9)).tracking(1.8)
                    .foregroundStyle(Theme.Palette.ink.opacity(0.55))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// "FRITTATA · RAGÙ" — the distinctive (last) word of each non-centred option.
    private var alternateNames: String {
        options.indices
            .filter { $0 != selected }
            .compactMap { options[$0].name.split(separator: " ").last?.uppercased() }
            .joined(separator: " · ")
    }
}
