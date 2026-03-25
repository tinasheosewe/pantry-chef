import SwiftUI

// MARK: - Multi-Cook Mode View
//
// Displays the interleaved timeline from MultiRecipeScheduler.
// Each block is color-coded by source recipe.
// Passive blocks start a background timer pill when the user advances past them.

struct MultiCookModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let recipes: [Recipe]
    let queueID: UUID?
    let queueStageID: UUID?
    @State private var blocks: [MultiRecipeScheduler.ScheduledBlock]
    @State private var currentBlockIndex = 0
    @State private var showEndConfirm = false

    // MARK: - Passive Timer State
    @State private var runningTimers: [RunningPassiveTimer] = []
    @State private var tickTimer: Timer?
    @State private var finishedTimerName: String?
    @State private var showTimerFinishedAlert = false

    /// Distinct color per recipe.
    private let recipeColors: [Color] = [
        PCColors.info, PCColors.expiring, PCColors.teal,
        Color(red: 0.94, green: 0.53, blue: 0.68),   // rose
        PCColors.accent,
        Color(red: 0.48, green: 0.40, blue: 0.82)     // soft indigo
    ]

    init(recipes: [Recipe], blocks: [MultiRecipeScheduler.ScheduledBlock], queueID: UUID? = nil, queueStageID: UUID? = nil) {
        self.recipes = recipes
        self.queueID = queueID
        self.queueStageID = queueStageID
        _blocks = State(initialValue: blocks)
    }

    private var currentBlock: MultiRecipeScheduler.ScheduledBlock? {
        guard currentBlockIndex < blocks.count else { return nil }
        return blocks[currentBlockIndex]
    }

    private var progress: Double {
        guard !blocks.isEmpty else { return 0 }
        return Double(currentBlockIndex) / Double(blocks.count)
    }

    var body: some View {
        ZStack {
            PCColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                progressBar

                // Passive timer pills
                if !runningTimers.isEmpty {
                    passiveTimerBanner
                }

                if let block = currentBlock {
                    blockContent(block)
                } else {
                    completionScreen
                }
            }
        }
        .confirmationDialog("End Multi-Cook?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End All Sessions", role: .destructive) {
                endSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end all \(recipes.count) cooking sessions.")
        }
        .alert("Timer Done!", isPresented: $showTimerFinishedAlert) {
            Button("OK") {}
        } message: {
            Text("\(finishedTimerName ?? "A passive task") is ready!")
        }
        .onAppear { startTickTimer() }
        .onDisappear { tickTimer?.invalidate() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(PCColors.textPrimary)
                    .padding(8)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Multi-Cook")
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)
                Text("\(recipes.count) Recipes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PCColors.textPrimary)
            }

            Spacer()

            Button("End") {
                showEndConfirm = true
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(PCColors.expired)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(PCColors.expired.opacity(0.12))
            .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        PCProgressBar(
            progress: progress,
            label: "Step \(min(currentBlockIndex + 1, blocks.count)) of \(blocks.count)",
            trailingLabel: "~\(blocks.map(\.totalDurationSeconds).reduce(0, +) / 60) min total",
            height: 6
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Passive Timer Banner

    private var passiveTimerBanner: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(runningTimers) { rt in
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.caption2)
                        Text(rt.label)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(formatTimer(rt.remainingSeconds))
                            .font(.caption.monospaced())
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(rt.remainingSeconds <= 30 ? .red : .yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        (rt.remainingSeconds <= 30 ? Color.red : Color.yellow)
                            .opacity(0.12)
                    )
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 6)
    }

    // MARK: - Block Content

    private func blockContent(_ block: MultiRecipeScheduler.ScheduledBlock) -> some View {
        AppScrollView {
            VStack(spacing: 24) {
                // Action class badge
                HStack(spacing: 8) {
                    Image(systemName: block.actionClass.icon)
                        .font(.title3)
                    Text(block.label)
                        .font(.headline)
                }
                .foregroundStyle(colorForBlock(block))
                .padding(.top, 24)

                // Passive indicator
                if block.type == .passive {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "timer")
                                .font(.caption)
                            Text("Passive — \(block.totalDurationSeconds / 60) min wait")
                                .font(.caption)
                        }
                        .foregroundStyle(PCColors.expiring)

                        Text("Start this, then tap Next to continue with other tasks")
                            .font(.caption2)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(PCColors.expiring.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Tasks list
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(block.tasks) { task in
                        taskRow(task)
                    }
                }
                .padding(.horizontal)

                // Recipe source tags
                HStack(spacing: 8) {
                    ForEach(block.recipeNames, id: \.self) { name in
                        Text(name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(colorForRecipe(name).opacity(0.6))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                // Navigation buttons
                HStack(spacing: 12) {
                    if currentBlockIndex > 0 {
                        Button {
                            withAnimation {
                                currentBlockIndex -= 1
                                // Remove passive timers started from blocks after the new position
                                let validBlockIDs = Set(blocks.prefix(currentBlockIndex).map(\.id))
                                runningTimers.removeAll { !validBlockIDs.contains($0.blockId) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Previous")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(PCColors.textPrimary)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(PCColors.fillTertiary)
                            .clipShape(Capsule())
                        }
                    }

                    Button {
                        advanceBlock()
                    } label: {
                        HStack(spacing: 4) {
                            Text(currentBlockIndex < blocks.count - 1
                                 ? (block.type == .passive ? "Start & Next" : "Next")
                                 : "Finish")
                            Image(systemName: currentBlockIndex < blocks.count - 1
                                  ? (block.type == .passive ? "timer" : "chevron.right")
                                  : "checkmark")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(block.type == .passive ? PCColors.expiring : PCColors.accent)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Task Row

    private func taskRow(_ task: StepTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(colorForRecipe(task.recipeName ?? ""))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.displayText)
                    .font(.body)
                    .foregroundStyle(PCColors.textPrimary)

                HStack(spacing: 8) {
                    if let name = task.recipeName {
                        Text(name)
                            .font(.caption2)
                            .foregroundStyle(colorForRecipe(name))
                    }
                    if let step = task.sourceStepNumber {
                        Text("Step \(step)")
                            .font(.caption2)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                    if task.durationSeconds > 0 {
                        Text("\(task.durationSeconds / 60)m")
                            .font(.caption2)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(PCColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    // MARK: - Advance Block

    private func advanceBlock() {
        // If current block is passive, start a background timer for it
        if let block = currentBlock, block.type == .passive, block.totalDurationSeconds > 0 {
            let label = block.tasks.first.map { task -> String in
                let name = task.recipeName ?? "Timer"
                let verb = task.action.verb
                return "\(verb) (\(name))"
            } ?? "Passive"

            let rt = RunningPassiveTimer(
                blockId: block.id,
                label: label,
                totalSeconds: block.totalDurationSeconds,
                startedAt: Date()
            )
            runningTimers.append(rt)
        }

        withAnimation { currentBlockIndex += 1 }
    }

    // MARK: - Tick Timer (updates all passive countdowns)

    private func startTickTimer() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            tickPassiveTimers()
        }
        if let tickTimer {
            RunLoop.main.add(tickTimer, forMode: .common)
        }
    }

    private func tickPassiveTimers() {
        var finished: [RunningPassiveTimer] = []

        for i in runningTimers.indices {
            let elapsed = Date().timeIntervalSince(runningTimers[i].startedAt)
            let remaining = max(0, runningTimers[i].totalSeconds - Int(elapsed))
            runningTimers[i].remainingSeconds = remaining

            if remaining == 0 {
                finished.append(runningTimers[i])
            }
        }

        // Remove finished timers and alert
        if let first = finished.first {
            runningTimers.removeAll { $0.remainingSeconds == 0 }
            finishedTimerName = first.label

            // Haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            showTimerFinishedAlert = true
        }
    }

    // MARK: - Completion Screen

    private var completionScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(PCColors.accent)

            Text("All Done!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(PCColors.textPrimary)

            Text("You cooked \(recipes.count) recipes together!")
                .font(.title3)
                .foregroundStyle(PCColors.textSecondary)

            VStack(spacing: 8) {
                ForEach(recipes) { recipe in
                    HStack {
                        Circle()
                            .fill(colorForRecipe(recipe.title))
                            .frame(width: 8, height: 8)
                        Text(recipe.title)
                            .font(.subheadline)
                            .foregroundStyle(PCColors.textPrimary)
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundStyle(PCColors.accent)
                    }
                }
            }
            .padding()
            .background(PCColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            .padding(.horizontal)

            Spacer()

            Button {
                endSession(completed: true)
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PCColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Helpers

    private func formatTimer(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func colorForBlock(_ block: MultiRecipeScheduler.ScheduledBlock) -> Color {
        if block.recipeNames.count > 1 { return PCColors.textPrimary }
        return colorForRecipe(block.recipeNames.first ?? "")
    }

    private func colorForRecipe(_ name: String) -> Color {
        guard let idx = recipes.firstIndex(where: { $0.title == name }) else { return PCColors.textTertiary }
        return recipeColors[idx % recipeColors.count]
    }

    // MARK: - Session Management

    private func endSession(completed: Bool = false) {
        tickTimer?.invalidate()
        Task {
            if let queueStageID {
                if completed {
                    await appState.completeCookQueueStage(queueStageID)
                } else {
                    await appState.skipCookQueueStage(queueStageID)
                }
            }
        }
        for recipe in recipes {
            CookingSession.clear(recipeId: recipe.id)
        }
        appState.activeCooks.refresh()
        dismiss()
    }
}

// MARK: - Running Passive Timer Model

struct RunningPassiveTimer: Identifiable {
    let id = UUID()
    let blockId: UUID
    let label: String
    let totalSeconds: Int
    let startedAt: Date
    var remainingSeconds: Int

    init(blockId: UUID, label: String, totalSeconds: Int, startedAt: Date) {
        self.blockId = blockId
        self.label = label
        self.totalSeconds = totalSeconds
        self.startedAt = startedAt
        self.remainingSeconds = totalSeconds
    }
}
