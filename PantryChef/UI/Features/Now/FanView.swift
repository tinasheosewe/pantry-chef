import SwiftUI

/// The "Tonight you could…" fan (spec §5): a spread of ranked-but-not-dictated
/// plates. The centre plate carries the sommelier reason; tapping a side plate
/// re-centres it (and rewrites the reason). Choosing one commits it.
struct FanView: View {
    let options: [FanOption]
    @Binding var selected: Int
    var onCook: (FanOption) -> Void
    var onSeeAll: () -> Void

    private var current: FanOption? { options.indices.contains(selected) ? options[selected] : nil }
    private var leftIndex: Int? { selected > 0 ? selected - 1 : nil }
    private var rightIndex: Int? { selected < options.count - 1 ? selected + 1 : nil }

    var body: some View {
        VStack(spacing: 0) {
            plates
            dots.padding(.top, 10)
            if let option = current {
                Text(option.name).font(Theme.Typography.dish(19)).foregroundStyle(Theme.Palette.ink)
                    .padding(.top, 10)
                Text(option.subtitle).font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
                    .padding(.top, 3)
                Text("\u{201C}\(option.reason)\u{201D}")
                    .font(Theme.Typography.note(13)).foregroundStyle(Theme.Palette.warmGray)
                    .multilineTextAlignment(.center).padding(.top, 11).padding(.horizontal, 6)
                    .id(option.id) // re-animate when the centre changes
                    .transition(.opacity)
                footer(option).padding(.top, 13)
            }
        }
        .padding(16).frame(maxWidth: .infinity).glassCard()
    }

    private var plates: some View {
        ZStack {
            if let l = leftIndex { sidePlate(options[l], angle: -9, offset: -78, index: l) }
            if let r = rightIndex { sidePlate(options[r], angle: 9, offset: 78, index: r) }
            PlateView(composition: options[selected].plate, size: Theme.Metric.plateHero)
                .zIndex(2)
        }
        .frame(height: Theme.Metric.plateHero + 8)
    }

    private func sidePlate(_ option: FanOption, angle: Double, offset: CGFloat, index: Int) -> some View {
        PlateView(composition: option.plate, size: Theme.Metric.plateHero * 0.6)
            .rotationEffect(.degrees(angle))
            .offset(x: offset, y: 8)
            .opacity(0.85)
            .zIndex(1)
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { selected = index }
            }
            .accessibilityLabel("See \(option.name)")
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(options.indices, id: \.self) { i in
                Circle()
                    .fill(i == selected ? Theme.Palette.paprika : Theme.Palette.warmGraySoft.opacity(0.4))
                    .frame(width: i == selected ? 6 : 5, height: i == selected ? 6 : 5)
            }
        }
    }

    private func footer(_ option: FanOption) -> some View {
        HStack {
            Button(action: onSeeAll) {
                Text("\(options.count) ready · see all")
                    .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
            }
            .buttonStyle(.plain)
            Spacer()
            PaprikaButton(title: option.level.verb) { onCook(option) }
        }
        .overlay(Divider().background(Theme.Palette.hairline), alignment: .top)
        .padding(.top, 11)
    }
}
