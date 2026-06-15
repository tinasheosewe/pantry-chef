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
    @State private var startedAt: Date?
    @State private var doneSignal = 0
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
        // Greasy hands, no taps for minutes — the screen must not sleep mid-cook.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: step) {
            timerRemaining = nil
            timerRunning = false
            onStep(step, schedule.count)
        }
        .onChange(of: phase) {
            if phase == .cooking {
                if startedAt == nil { startedAt = Date() }
                onStep(step, schedule.count)
            }
        }
        .onReceive(tick) { _ in
            guard timerRunning, let r = timerRemaining else { return }
            if r > 1 { timerRemaining = r - 1 } else { timerRemaining = 0; timerRunning = false }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: gathered)
        .sensoryFeedback(.impact(weight: .medium), trigger: step)
        // The timer escalates in the last ten seconds, then lands a warm heartbeat
        // at zero — demanding but kind, not a jarring alarm.
        .sensoryFeedback(trigger: timerRemaining) { _, new in
            guard let new else { return nil }
            if new == 0 { return .impact(weight: .heavy) }
            if new <= 10 { return .selection }
            return nil
        }
        // The success buzz is reserved for finishing the cook — a real completion.
        .sensoryFeedback(.success, trigger: doneSignal)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(phase == .cooking ? "COOKING" : "GATHERING") — \(isMulti ? "\(dishes.count) DISHES" : (dishes.first?.name ?? ""))")
                .font(.system(size: 10)).tracking(1.8)
                .foregroundStyle(Theme.Palette.ink.opacity(0.6))
                .lineLimit(1)
            Spacer()
            if phase == .cooking {
                Text("STEP \(step + 1) OF \(schedule.count)")
                    .font(.system(size: 10)).tracking(1.8)
                    .foregroundStyle(Theme.Palette.paprika)
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink.opacity(0.6))
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Gathering

    private var gathering: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Gather your ingredients").font(Theme.Typography.dish(22))
                .foregroundStyle(Theme.Palette.ink).padding(.top, 22)
            Text("Tap each as you set it out.").font(Theme.Typography.note(12))
                .foregroundStyle(Theme.Palette.warmGray).padding(.top, 3)

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
                Text("\(gathered.count) OF \(allLines.count) READY")
                    .font(.system(size: 9)).tracking(1.8).foregroundStyle(Theme.Palette.ink.opacity(0.55))
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
                InkCheck(on: isGathered, size: 22)
                Text(line.display).font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
                    .strikethrough(isGathered, color: Theme.Palette.warmGraySoft)
                Spacer()
                if !onHand && !line.isStaple {
                    Text("NOT IN STOCK").font(.system(size: 9)).tracking(1.4).foregroundStyle(Theme.Palette.paprika)
                }
            }
            .padding(.vertical, 11).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cooking

    private var cooking: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress.padding(.top, 14)
            ticket.padding(.top, 14)
            if let next = nextStep {
                nextTicket(next).padding(.top, 8)
            }
            Spacer()
            controls
            if let line = logistics {
                Tailpiece(text: line).padding(.top, 10)
            }
        }
        // Lowest-precision gesture for messy hands: swipe to move between steps
        // (the BACK/NEXT buttons stay as the visible fallback).
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0 { advance(1) } else { advance(-1) }
                }
        )
    }

    private func advance(_ direction: Int) {
        let target = step + direction
        if target < 0 { withAnimation(.paper) { phase = .gathering } }
        else if target < schedule.count { withAnimation(.paperQuick) { step = target } }
        else { doneSignal += 1; onDone() }
    }

    /// The live step, torn open: bordered sheet with a dashed top edge.
    private var ticket: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isMulti, let current = currentStep {
                Text(current.dishName.uppercased())
                    .font(.system(size: 9)).tracking(1.8)
                    .foregroundStyle(Theme.Palette.paprika)
                    .padding(.bottom, 8)
            }
            Text(currentStep?.step.instruction ?? "")
                .font(Theme.Typography.fact(23)).foregroundStyle(Theme.Palette.ink)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            if let seconds = currentStep?.step.timerSeconds {
                timer(seconds).padding(.top, 14)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Rectangle().fill(Theme.Palette.creamRaised))
        .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(0.3), lineWidth: 1))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.clear)
                .frame(height: 2)
                .overlay(
                    Rectangle().stroke(Theme.Palette.ink.opacity(0.45),
                                       style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                )
                .clipped()
        }
    }

    private var nextStep: ScheduledStep? {
        schedule.indices.contains(step + 1) ? schedule[step + 1] : nil
    }

    private func nextTicket(_ next: ScheduledStep) -> some View {
        Text("NEXT — \(next.step.instruction)")
            .font(.system(size: 10)).tracking(1.2)
            .foregroundStyle(Theme.Palette.ink)
            .lineLimit(2)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(Theme.Palette.creamRaised))
            .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(0.18), lineWidth: 1))
            .opacity(0.6)
    }

    /// "started 19:04 · eating by 19:30" — honest cook logistics.
    private var logistics: String? {
        guard let startedAt else { return nil }
        let remaining = schedule[min(step, max(schedule.count - 1, 0))...].reduce(0) {
            $0 + ($1.step.timerSeconds ?? AppConfig.defaultStepDurationSeconds)
        }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "started \(f.string(from: startedAt)) · eating by \(f.string(from: Date().addingTimeInterval(TimeInterval(remaining))))"
    }

    private var currentStep: ScheduledStep? {
        schedule.indices.contains(step) ? schedule[step] : schedule.last
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(schedule.indices, id: \.self) { i in
                Rectangle()
                    .fill(i < step ? Theme.Palette.ink.opacity(0.9)
                          : i == step ? Theme.Palette.paprika
                          : Theme.Palette.ink.opacity(0.15))
                    .frame(height: 3)
            }
        }
    }

    private func timer(_ seconds: Int) -> some View {
        let shown = timerRemaining ?? seconds
        let finished = timerRemaining == 0
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(format(shown)).font(Theme.Typography.dish(38))
                .foregroundStyle(finished ? Theme.Palette.sage : Theme.Palette.ink)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: shown)
                .overlay { if finished { Bloom(color: Theme.Palette.sage).id(timerRemaining) } }
            Button {
                if finished { timerRemaining = seconds; timerRunning = true; return }
                if timerRemaining == nil { timerRemaining = seconds }
                timerRunning.toggle()
            } label: {
                Text(finished ? "AGAIN" : (timerRunning ? "PAUSE" : (timerRemaining == nil ? "START" : "RESUME")))
                    .font(.system(size: 13, weight: .medium)).tracking(2)
                    .foregroundStyle(Theme.Palette.paprika)
                    .padding(.horizontal, 20).frame(minHeight: 44)
                    .overlay(Rectangle().strokeBorder(Theme.Palette.paprika, lineWidth: 1.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            if finished {
                Text("DONE").font(.system(size: 11, weight: .medium)).tracking(2).foregroundStyle(Theme.Palette.sage)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button { advance(-1) } label: {
                Text(step > 0 ? "← BACK" : "← GATHER")
                    .font(.system(size: 11, weight: .medium)).tracking(1.8)
                    .foregroundStyle(Theme.Palette.warmGray)
                    .padding(.vertical, 12).padding(.trailing, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Circle().fill(Theme.Palette.creamRaised)
                .overlay(Image(systemName: "microphone").font(.system(size: 16)).foregroundStyle(Theme.Palette.paprika))
                .overlay(Circle().strokeBorder(Theme.Palette.paprika.opacity(0.5)))
                .frame(width: 46, height: 46)
            Spacer()
            BlockButton(title: step < schedule.count - 1 ? "Next →" : "Done") { advance(1) }
        }
    }

    private func format(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
