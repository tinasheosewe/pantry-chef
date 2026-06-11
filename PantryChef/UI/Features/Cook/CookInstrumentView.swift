import SwiftUI

/// The cook instrument (spec §5) — entered when a plate is chosen. Stays in the
/// app's warm light (no dark mode switch); big type at arm's length, the plate as
/// anchor, the timer as the hero numeral. A focused v1: step text, timer, controls.
struct CookInstrumentView: View {
    let option: FanOption
    var onDone: () -> Void
    var onClose: () -> Void

    @State private var step = 0
    private let steps = [
        "Bring a pot of salted water to the boil and start the orzo.",
        "Wilt the spinach into the brown butter until just collapsed — about two minutes.",
        "Fold in the feta and a little pasta water; season and serve."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            progress.padding(.top, 14)
            Text(steps[min(step, steps.count - 1)])
                .font(Theme.Typography.fact(22)).foregroundStyle(Theme.Palette.ink)
                .lineSpacing(5).padding(.top, 28)
            timer.padding(.top, 30)
            Spacer()
            controls
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
    }

    private var header: some View {
        HStack(spacing: 10) {
            PlateView(composition: option.plate, size: 30)
            Text(option.name).font(Theme.Typography.dish(14)).foregroundStyle(Theme.Palette.warmGray)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.warmGray)
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<steps.count, id: \.self) { i in
                Capsule().fill(i <= step ? Theme.Palette.paprika : Theme.Palette.hairline)
                    .frame(height: 4)
            }
        }
    }

    private var timer: some View {
        HStack(spacing: 14) {
            Text("02:00").font(Theme.Typography.numeral(46)).foregroundStyle(Theme.Palette.ink)
            Text("Start").font(Theme.Typography.fact(12))
                .foregroundStyle(Theme.Palette.paprika)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .overlay(Capsule().strokeBorder(Theme.Palette.paprika, lineWidth: 1.5))
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button("Back") { if step > 0 { step -= 1 } }
                .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.warmGray)
            Spacer()
            Circle().fill(Theme.Palette.creamRaised)
                .overlay(Image(systemName: "microphone").foregroundStyle(Theme.Palette.paprika))
                .overlay(Circle().strokeBorder(Theme.Palette.paprika.opacity(0.4)))
                .frame(width: 44, height: 44)
            Spacer()
            PaprikaButton(title: step < steps.count - 1 ? "Next" : "Done") {
                if step < steps.count - 1 { step += 1 } else { onDone() }
            }
        }
        .buttonStyle(.plain)
    }
}
