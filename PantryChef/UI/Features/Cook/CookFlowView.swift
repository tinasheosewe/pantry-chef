import SwiftUI

/// Cook mode (spec §2, §5) — one surface that scales from a single recipe to
/// several cooked together. Opens on **mise en place** (gather everything, tapping
/// each off = reconciliation), then runs the steps; for multiple dishes the
/// MultiCookScheduler interleaves them so all the pots get going. Warm light, the
/// plate anchors, the timer is the hero.
struct CookFlowView: View {
    let dishes: [Dish]
    var isOnHand: (String) -> Bool = { _ in true }
    /// Reports live progress (step index, total) so the now-module can mirror it.
    var onStep: (Int, Int) -> Void = { _, _ in }
    var onDone: () -> Void
    var onClose: () -> Void

    private enum Phase { case gathering, cooking }
    @State private var phase: Phase = .gathering
    @State private var gathered: Set<UUID> = []
    @State private var step = 0
    @State private var timerRemaining: Int?
    @State private var timerRunning = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isMulti: Bool { dishes.count > 1 }
    private var allLines: [RecipeLine] { dishes.flatMap(\.ingredients) }
    private var schedule: [ScheduledStep] {
        isMulti
            ? MultiCookScheduler.schedule(dishes)
            : (dishes.first.map { d in d.steps.map { ScheduledStep(dishName: d.name, plate: d.plate, step: $0) } } ?? [])
    }

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
        .onChange(of: step) {
            timerRemaining = nil
            timerRunning = false
            onStep(step, schedule.count)
        }
        .onChange(of: phase) { if phase == .cooking { onStep(step, schedule.count) } }
        .onReceive(tick) { _ in
            guard timerRunning, let r = timerRemaining else { return }
            if r > 1 { timerRemaining = r - 1 } else { timerRemaining = 0; timerRunning = false }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let plate = dishes.first?.plate { PlateView(composition: plate, size: 30) }
            Text(isMulti ? "\(dishes.count) dishes together" : (dishes.first?.name ?? ""))
                .font(Theme.Typography.dish(14)).foregroundStyle(Theme.Palette.warmGray)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.Palette.warmGray)
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(dishes) { dish in
                        if isMulti {
                            Text(dish.name.uppercased()).font(Theme.Typography.eyebrow)
                                .tracking(Theme.Metric.eyebrowTracking).foregroundStyle(Theme.Palette.warmGraySoft)
                                .padding(.top, 14).padding(.bottom, 2)
                        }
                        ForEach(dish.ingredients) { line in
                            gatherRow(line)
                            if line.id != dish.ingredients.last?.id { Divider().background(Theme.Palette.hairline) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.top, 14)

            HStack {
                Text("\(gathered.count) of \(allLines.count) ready")
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
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.Palette.cream)
                    }
                }
                Text(line.display).font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
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
            if isMulti, let current = currentStep {
                HStack(spacing: 8) {
                    PlateView(composition: current.plate, size: 22)
                    Text(current.dishName).font(Theme.Typography.fact(12, weight: .medium)).foregroundStyle(Theme.Palette.paprika)
                }
                .padding(.top, 18)
            }
            Text(currentStep?.step.instruction ?? "")
                .font(Theme.Typography.fact(22)).foregroundStyle(Theme.Palette.ink)
                .lineSpacing(5).padding(.top, isMulti ? 12 : 26)
            if let seconds = currentStep?.step.timerSeconds {
                timer(seconds).padding(.top, 26)
            }
            Spacer()
            controls
        }
    }

    private var currentStep: ScheduledStep? {
        schedule.indices.contains(step) ? schedule[step] : schedule.last
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(schedule.indices, id: \.self) { i in
                Capsule().fill(i <= step ? Theme.Palette.paprika : Theme.Palette.hairline).frame(height: 4)
            }
        }
    }

    private func timer(_ seconds: Int) -> some View {
        let shown = timerRemaining ?? seconds
        let finished = timerRemaining == 0
        return HStack(spacing: 14) {
            Text(format(shown)).font(Theme.Typography.numeral(46))
                .foregroundStyle(finished ? Theme.Palette.sage : Theme.Palette.ink)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: shown)
            Button {
                if finished { timerRemaining = seconds; timerRunning = true; return }
                if timerRemaining == nil { timerRemaining = seconds }
                timerRunning.toggle()
            } label: {
                Text(finished ? "Again" : (timerRunning ? "Pause" : (timerRemaining == nil ? "Start" : "Resume")))
                    .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.paprika)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .overlay(Capsule().strokeBorder(Theme.Palette.paprika, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            if finished {
                Text("done!").font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.sage)
            }
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
            PaprikaButton(title: step < schedule.count - 1 ? "Next" : "Done") {
                if step < schedule.count - 1 { step += 1 } else { onDone() }
            }
        }
        .buttonStyle(.plain)
    }

    private func format(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
