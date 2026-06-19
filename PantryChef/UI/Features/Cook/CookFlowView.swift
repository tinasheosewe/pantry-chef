import SwiftUI

/// Cook mode (spec §2, §5) — one surface that scales from a single recipe to
/// several cooked together. Opens on **mise en place** (gather everything, tapping
/// each off = reconciliation), then runs the steps; for multiple dishes the
/// MultiCookScheduler interleaves them so all the pots get going. Warm light, the
/// plate anchors, the timer is the hero.
struct CookFlowView: View {
    let dishes: [Dish]
    var isOnHand: (RecipeLine) -> Bool = { _ in true }
    /// Reports live progress (step index, total) so the now-module can mirror it.
    var onStep: (Int, Int) -> Void = { _, _ in }
    /// Reports the most-urgent running timer's countdown (or nil) so the now-card
    /// can mirror it live.
    var onTimer: (String?) -> Void = { _ in }
    /// Finishing the cook — the made-portion count (single dish) the user confirmed,
    /// or nil to bank each dish at its default servings.
    var onDone: (Int?) -> Void = { _ in }
    var onClose: () -> Void

    private enum Phase { case gathering, cooking }
    @State private var phase: Phase = .gathering
    @State private var gathered: Set<UUID> = []
    @State private var step = 0
    /// Per-step countdowns, keyed by step index. Anchored to the wall clock (an end
    /// Date while running, a frozen remainder while paused) so they survive
    /// backgrounding and keep running while you move to other steps — a real kitchen
    /// has several pots going at once.
    @State private var timers: [Int: StepTimer] = [:]
    /// A monotonic "now" the running timers read from; bumped each tick and re-synced
    /// the instant we return to the foreground, so the displayed remainder is always
    /// the true wall-clock remainder.
    @State private var now = Date()
    @State private var startedAt: Date?
    @State private var doneSignal = 0
    @State private var firedTimers: Set<Int> = []
    @State private var swapsExpanded = false
    /// The finish-cook confirmation: how many portions actually came out of the pot.
    @State private var finishing = false
    @State private var madePortions = 0
    @Environment(\.scenePhase) private var scenePhase
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    /// One countdown anchored to the wall clock. While running it knows the `endsAt`
    /// instant; while paused it holds the frozen `pausedRemaining`. `total` is the full
    /// duration so "again" can restart it.
    struct StepTimer: Equatable {
        let total: Int
        var endsAt: Date?
        var pausedRemaining: Int?
    }

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
        // Moving between steps no longer nukes the timer — a step's countdown keeps
        // running so you can start a simmer and walk ahead to prep the next thing.
        .onChange(of: step) { onStep(step, schedule.count) }
        .onChange(of: phase) {
            if phase == .cooking {
                if startedAt == nil { startedAt = Date() }
                onStep(step, schedule.count)
            }
        }
        // Returning to the foreground: re-sync the clock so a timer that ran down
        // while we were backgrounded shows its true (possibly zero) remainder at once.
        .onChange(of: scenePhase) { if scenePhase == .active { now = Date(); reconcile() } }
        .onReceive(tick) { _ in now = Date(); reconcile() }
        .onChange(of: currentRemaining) { onTimer(runningTimerText) }
        .sensoryFeedback(.impact(weight: .light), trigger: gathered)
        .sensoryFeedback(.impact(weight: .medium), trigger: step)
        // The timer escalates in the last ten seconds, then lands a warm heartbeat
        // at zero — demanding but kind, not a jarring alarm.
        .sensoryFeedback(trigger: currentRemaining) { _, new in
            guard let new else { return nil }
            if new == 0 { return .impact(weight: .heavy) }
            if new <= 10 { return .selection }
            return nil
        }
        .sheet(isPresented: $finishing) { finishSheet }
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
        let onHand = isOnHand(line)
        let optional = !line.essential   // droppable garnish/finish — gather if you like
        return Button {
            if isGathered { gathered.remove(line.id) } else { gathered.insert(line.id) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 12) {
                    InkCheck(on: isGathered, size: 22)
                    Text(line.display).font(Theme.Typography.fact(14))
                        .foregroundStyle(optional ? Theme.Palette.warmGray : Theme.Palette.ink)
                        .strikethrough(isGathered, color: Theme.Palette.warmGraySoft)
                    Spacer()
                    if optional {
                        Text("OPTIONAL").font(.system(size: 9)).tracking(1.4).foregroundStyle(Theme.Palette.warmGraySoft)
                    } else if !onHand && !line.isStaple {
                        Text("NOT IN STOCK").font(.system(size: 9)).tracking(1.4).foregroundStyle(Theme.Palette.paprika)
                    }
                }
                // The substitution and its note (ratio / quantity guidance) ride through
                // from the recipe, so mid-cook you remember what to use and how much.
                if let note = line.swapNote {
                    Text("↻ \(note)")
                        .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage)
                        .padding(.leading, 34)
                        .fixedSize(horizontal: false, vertical: true)
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
            swapsStrip
            ticket.padding(.top, 14)
            if let next = nextStep {
                nextTicket(next).padding(.top, 8)
            }
            otherTimersStrip
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

    /// Accepted substitutions in this cook — kept glanceable through the steps, so
    /// mid-cook you still know what you swapped in (and the note: ratio / quantity).
    private var swappedLines: [RecipeLine] { allLines.filter { $0.swapNote != nil } }

    @ViewBuilder private var swapsStrip: some View {
        let swaps = swappedLines
        if !swaps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if swaps.count == 1 {
                    // One swap is never clutter — show it inline, no chrome.
                    swapLine(swaps[0])
                } else {
                    // Many swaps would dominate the step screen, so collapse to a
                    // count and let the cook expand into a height-capped scroll.
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { swapsExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("↻ \(swaps.count) substitutions")
                                .font(.system(size: 11, weight: .semibold)).tracking(0.4)
                            Image(systemName: swapsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Theme.Palette.sage)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if swapsExpanded {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(swaps) { swapLine($0) }
                            }
                        }
                        .frame(maxHeight: 108)   // bounded — even a dozen swaps stay tidy
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Rectangle().fill(Theme.Palette.sage.opacity(0.10)))
            .padding(.top, 10)
        }
    }

    private func swapLine(_ line: RecipeLine) -> some View {
        Text("↻ \(line.name)\(line.swapNote.map { " — \($0)" } ?? "")")
            .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func advance(_ direction: Int) {
        let target = step + direction
        if target < 0 {
            // Already at the first step → step back into gathering; never past it.
            if step == 0 { withAnimation(.paper) { phase = .gathering } }
            else { withAnimation(.paperQuick) { step = max(0, target) } }
        }
        else if target < schedule.count { withAnimation(.paperQuick) { step = target } }
        // Past the last step → confirm what came out of the pot before banking it.
        else { beginFinish() }
    }

    // MARK: - Timers (wall-clock anchored, concurrent across steps)

    /// Seconds left on the timer at `index`: the live wall-clock remainder while
    /// running, the frozen remainder while paused, or the full duration before it's
    /// ever started. nil = this step has no timer at all.
    private func remaining(at index: Int) -> Int? {
        guard schedule.indices.contains(index), let total = schedule[index].step.timerSeconds else { return nil }
        guard let t = timers[index] else { return total }
        if let end = t.endsAt { return max(0, Int(end.timeIntervalSince(now).rounded())) }
        return t.pausedRemaining ?? total
    }
    private func isRunning(_ index: Int) -> Bool { timers[index]?.endsAt != nil }
    private func isFinished(_ index: Int) -> Bool { timers[index] != nil && remaining(at: index) == 0 }

    /// Remaining on the current step's timer — the value the hero display and the
    /// escalating haptics read from.
    private var currentRemaining: Int? { timers[step] != nil ? remaining(at: step) : nil }

    /// The step's timer duration, if the index is in range and the step is timed.
    private func timerSeconds(at index: Int) -> Int? {
        schedule.indices.contains(index) ? schedule[index].step.timerSeconds : nil
    }

    /// Start the step's countdown fresh from its full duration.
    private func startTimer(_ index: Int) {
        guard let total = timerSeconds(at: index) else { return }
        timers[index] = StepTimer(total: total, endsAt: Date().addingTimeInterval(TimeInterval(total)), pausedRemaining: nil)
        firedTimers.remove(index)
        onTimer(runningTimerText)
    }

    /// Tap-through the step timer: start → pause → resume → (when finished) restart.
    private func toggleTimer(_ index: Int) {
        guard let total = timerSeconds(at: index) else { return }
        guard let t = timers[index] else { startTimer(index); return }
        if let end = t.endsAt {                                   // running → pause
            let rem = max(0, Int(end.timeIntervalSince(Date()).rounded()))
            timers[index] = StepTimer(total: t.total, endsAt: nil, pausedRemaining: rem)
        } else if let rem = t.pausedRemaining, rem > 0 {          // paused → resume
            timers[index] = StepTimer(total: t.total, endsAt: Date().addingTimeInterval(TimeInterval(rem)), pausedRemaining: nil)
        } else {                                                  // finished → again
            timers[index] = StepTimer(total: total, endsAt: Date().addingTimeInterval(TimeInterval(total)), pausedRemaining: nil)
            firedTimers.remove(index)
        }
        onTimer(runningTimerText)
    }

    /// Snap any running timer that has crossed zero to a stopped, finished state, and
    /// mark it fired once (so the heartbeat haptic lands a single time).
    private func reconcile() {
        for (index, t) in timers where t.endsAt != nil {
            if Int(t.endsAt!.timeIntervalSince(now).rounded()) <= 0, !firedTimers.contains(index) {
                firedTimers.insert(index)
            }
        }
        onTimer(runningTimerText)
    }

    /// Timers running on steps other than the one on screen — so a simmer you left
    /// behind stays visible while you work ahead.
    private var otherRunningTimers: [(index: Int, remaining: Int)] {
        timers.keys.compactMap { i -> (Int, Int)? in
            guard i != step, isRunning(i) || isFinished(i), let r = remaining(at: i) else { return nil }
            return (i, r)
        }
        .sorted { $0.1 < $1.1 }
    }

    /// The countdown the now-card mirrors: the running timer closest to firing.
    private var runningTimerText: String? {
        let live = timers.keys.filter { isRunning($0) }.compactMap { remaining(at: $0) }
        guard let soonest = live.min() else { return nil }
        return format(soonest)
    }

    /// The live step, torn open: bordered sheet with a dashed top edge.
    private var ticket: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let current = currentStep, isMulti || current.step.phase == .prep {
                Text(phaseLabel(for: current))
                    .font(.system(size: 9)).tracking(1.8)
                    .foregroundStyle(current.step.phase == .prep ? Theme.Palette.sage : Theme.Palette.paprika)
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

    /// Timers ticking on other steps — a tap jumps back to that step. So a sauce you
    /// set simmering stays in view (and a finished one nags) while you work ahead.
    @ViewBuilder private var otherTimersStrip: some View {
        let others = otherRunningTimers
        if !others.isEmpty {
            VStack(spacing: 6) {
                ForEach(others, id: \.index) { entry in
                    Button { withAnimation(.paperQuick) { step = entry.index } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isFinished(entry.index) ? "bell.fill" : "timer")
                                .font(.system(size: 11))
                                .foregroundStyle(isFinished(entry.index) ? Theme.Palette.sage : Theme.Palette.paprika)
                            Text("Step \(entry.index + 1)")
                                .font(Theme.Typography.fact(11, weight: .medium)).foregroundStyle(Theme.Palette.warmGray)
                            Text(schedule[entry.index].step.instruction)
                                .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(isFinished(entry.index) ? "DONE" : format(entry.remaining))
                                .font(Theme.Typography.numeral(12, weight: .medium))
                                .foregroundStyle(isFinished(entry.index) ? Theme.Palette.sage : Theme.Palette.paprika)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Rectangle().fill(Theme.Palette.ink.opacity(0.04)))
            .overlay(Rectangle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
            .padding(.top, 10)
        }
    }

    private func nextTicket(_ next: ScheduledStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("NEXT").font(.system(size: 9.5, weight: .medium)).tracking(1.6)
                .foregroundStyle(Theme.Palette.paprika)
            Text(next.step.instruction)
                .font(Theme.Typography.fact(12.5)).foregroundStyle(Theme.Palette.warmGray)
                .lineLimit(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Rectangle().fill(Theme.Palette.creamRaised))
        .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(0.18), lineWidth: 1))
    }

    /// "started 19:04 · eating by 19:30" — honest cook logistics. The "eating by"
    /// estimate appears ONLY when every remaining step has a real cook time; we never
    /// guess from a default (a wrong ETA is worse than none — seed recipes are fully
    /// timed, user-authored steps may not be).
    private var logistics: String? {
        guard let startedAt else { return nil }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let started = "started \(f.string(from: startedAt))"
        let remainingSteps = schedule[min(step, max(schedule.count - 1, 0))...]
        let times = remainingSteps.map(\.step.timerSeconds)
        guard !times.contains(where: { $0 == nil }) else { return started }
        let remaining = times.compactMap { $0 }.reduce(0, +)
        return "\(started) · eating by \(f.string(from: Date().addingTimeInterval(TimeInterval(remaining))))"
    }

    /// "PREP · DISH A" up front, then "DISH A" once the cooking starts — the unified
    /// prep stage reads as its own thing.
    private func phaseLabel(for s: ScheduledStep) -> String {
        let prefix = s.step.phase == .prep ? "PREP" : nil
        if isMulti { return [prefix, s.dishName.uppercased()].compactMap { $0 }.joined(separator: " · ") }
        return prefix ?? ""
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
        let shown = remaining(at: step) ?? seconds
        let running = isRunning(step)
        let started = timers[step] != nil
        let finished = isFinished(step)
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(format(shown)).font(Theme.Typography.dish(38))
                .foregroundStyle(finished ? Theme.Palette.sage : Theme.Palette.ink)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: shown)
                .overlay { if finished { Bloom(color: Theme.Palette.sage).id(firedTimers.contains(step)) } }
            Button { toggleTimer(step) } label: {
                Text(finished ? "AGAIN" : (running ? "PAUSE" : (started ? "RESUME" : "START")))
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

    // MARK: - Finish confirmation

    private func beginFinish() {
        // Default to the count we cooked toward; the cook nudges it to what actually
        // came out (a recipe for 4 sometimes yields 3 real portions).
        madePortions = max(1, dishes.reduce(0) { $0 + $1.servings })
        doneSignal += 1
        finishing = true
    }

    private var finishSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            Text("Nicely done").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                .padding(.top, 16)
            Text(isMulti
                 ? "Banking each dish into the fridge."
                 : "How many portions came out? We’ll keep them as leftovers.")
                .font(Theme.Typography.note(13)).foregroundStyle(Theme.Palette.warmGray)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)

            if !isMulti {
                HStack(spacing: 18) {
                    stepperButton("minus") { madePortions = max(0, madePortions - 1) }
                    Text("\(madePortions)").font(Theme.Typography.dish(40)).monospacedDigit()
                        .foregroundStyle(Theme.Palette.ink).frame(minWidth: 64)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: madePortions)
                    stepperButton("plus") { madePortions = min(24, madePortions + 1) }
                    Spacer()
                    Text(madePortions == 1 ? "portion" : "portions")
                        .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.warmGraySoft)
                }
                .padding(.vertical, 22)
                if madePortions == 0 {
                    Text("Nothing kept — just logs that you made it.")
                        .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
                }
            }
            Spacer(minLength: 0)
            PaprikaButton(title: madePortions == 0 && !isMulti ? "Log it" : "Bank it") {
                finishing = false
                onDone(isMulti ? nil : madePortions)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(22)
        .background(KitchenBackground())
        .presentationDetents([.height(isMulti ? 240 : 320)])
    }

    private func stepperButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Palette.paprika)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(Theme.Palette.paprika.opacity(0.5), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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
