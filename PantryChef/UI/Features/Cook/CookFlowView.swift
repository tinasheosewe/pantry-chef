import SwiftUI

/// Cook mode (spec §2, §5). Opens on **mise en place** — gather every ingredient,
/// checking each off (which doubles as pantry reconciliation) — then runs the
/// recipe's real steps. No more running to the pantry mid-step. Stays in the
/// app's warm light; the plate anchors, the timer is the hero numeral.
struct CookFlowView: View {
    let dish: Dish
    var isOnHand: (String) -> Bool = { _ in true }
    var onDone: () -> Void
    var onClose: () -> Void

    private enum Phase { case gathering, cooking }
    @State private var phase: Phase = .gathering
    @State private var gathered: Set<UUID> = []
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            switch phase {
            case .gathering: gathering
            case .cooking: cooking
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
    }

    private var header: some View {
        HStack(spacing: 10) {
            PlateView(composition: dish.plate, size: 30)
            Text(dish.name).font(Theme.Typography.dish(14)).foregroundStyle(Theme.Palette.warmGray)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.warmGray)
            }
        }
    }

    // MARK: - Gathering

    private var gathering: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Gather your ingredients").font(Theme.Typography.dish(22))
                .foregroundStyle(Theme.Palette.ink).padding(.top, 22)
            Text("Tap each as you set it out.").font(Theme.Typography.fact(12))
                .foregroundStyle(Theme.Palette.warmGraySoft).padding(.top, 3)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(dish.ingredients) { line in
                        gatherRow(line)
                        if line.id != dish.ingredients.last?.id { Divider().background(Theme.Palette.hairline) }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.top, 14)

            HStack {
                Text("\(gathered.count) of \(dish.ingredients.count) ready")
                    .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGraySoft)
                Spacer()
                PaprikaButton(title: "Start cooking") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = .cooking }
                }
            }
            .padding(.top, 8)
        }
    }

    private func gatherRow(_ line: RecipeLine) -> some View {
        let isGathered = gathered.contains(line.id)
        let onHand = isOnHand(line.key)
        return Button {
            if isGathered { gathered.remove(line.id) } else { gathered.insert(line.id) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(isGathered ? Theme.Palette.sage : Theme.Palette.warmGraySoft.opacity(0.5),
                                          lineWidth: 1.5).frame(width: 22, height: 22)
                    if isGathered {
                        Circle().fill(Theme.Palette.sage).frame(width: 22, height: 22)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.Palette.cream)
                    }
                }
                Text(line.display).font(Theme.Typography.fact(14))
                    .foregroundStyle(Theme.Palette.ink)
                    .strikethrough(isGathered, color: Theme.Palette.warmGraySoft)
                Spacer()
                if !onHand && !line.isStaple {
                    Text("not in stock").font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.ochre)
                }
            }
            .padding(.vertical, 11).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cooking

    private var cooking: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress.padding(.top, 16)
            Text(currentStep.instruction)
                .font(Theme.Typography.fact(22)).foregroundStyle(Theme.Palette.ink)
                .lineSpacing(5).padding(.top, 26)
            if let seconds = currentStep.timerSeconds {
                timer(seconds).padding(.top, 28)
            }
            Spacer()
            controls
        }
    }

    private var currentStep: CookStep { dish.steps[min(step, max(dish.steps.count - 1, 0))] }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(dish.steps.indices, id: \.self) { i in
                Capsule().fill(i <= step ? Theme.Palette.paprika : Theme.Palette.hairline).frame(height: 4)
            }
        }
    }

    private func timer(_ seconds: Int) -> some View {
        HStack(spacing: 14) {
            Text(format(seconds)).font(Theme.Typography.numeral(46)).foregroundStyle(Theme.Palette.ink)
            Text("Start").font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.paprika)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .overlay(Capsule().strokeBorder(Theme.Palette.paprika, lineWidth: 1.5))
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button(step > 0 ? "Back" : "Ingredients") {
                if step > 0 { step -= 1 } else { withAnimation { phase = .gathering } }
            }
            .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.warmGray)
            Spacer()
            Circle().fill(Theme.Palette.creamRaised)
                .overlay(Image(systemName: "microphone").foregroundStyle(Theme.Palette.paprika))
                .overlay(Circle().strokeBorder(Theme.Palette.paprika.opacity(0.4)))
                .frame(width: 44, height: 44)
            Spacer()
            PaprikaButton(title: step < dish.steps.count - 1 ? "Next" : "Done") {
                if step < dish.steps.count - 1 { step += 1 } else { onDone() }
            }
        }
        .buttonStyle(.plain)
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
