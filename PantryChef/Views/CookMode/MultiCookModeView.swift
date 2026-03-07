import SwiftUI

// MARK: - Multi-Cook Mode View
//
// Displays the interleaved timeline from MultiRecipeScheduler.
// Each block is color-coded by source recipe.
// Supports stepping through blocks with voice guidance.

struct MultiCookModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let recipes: [Recipe]
    @State private var blocks: [MultiRecipeScheduler.ScheduledBlock]
    @State private var currentBlockIndex = 0
    @State private var showEndConfirm = false
    @State private var timerSeconds = 0
    @State private var isTimerRunning = false
    @State private var timerStartedAt: Date?
    @State private var timerDuration: TimeInterval = 0
    @State private var timer: Timer?

    /// Distinct color per recipe.
    private let recipeColors: [Color] = [
        .blue, .orange, .purple, .pink, .teal, .mint
    ]

    init(recipes: [Recipe], blocks: [MultiRecipeScheduler.ScheduledBlock]) {
        self.recipes = recipes
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
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                progressBar

                if let block = currentBlock {
                    blockContent(block)
                } else {
                    completionScreen
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("End Multi-Cook?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End All Sessions", role: .destructive) {
                endSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end all \(recipes.count) cooking sessions.")
        }
        .onDisappear {
            timer?.invalidate()
        }
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
                    .foregroundStyle(.white)
                    .padding(8)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Multi-Cook")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Text("\(recipes.count) Recipes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            Spacer()

            Button("End") {
                showEndConfirm = true
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.red.opacity(0.15))
            .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.primaryGreen)
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)

            HStack {
                Text("Block \(min(currentBlockIndex + 1, blocks.count)) of \(blocks.count)")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                Spacer()
                let totalSeconds = blocks.map(\.totalDurationSeconds).reduce(0, +)
                Text("~\(totalSeconds / 60) min total")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Block Content

    private func blockContent(_ block: MultiRecipeScheduler.ScheduledBlock) -> some View {
        ScrollView {
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

                // Type indicator
                if block.type == .passive {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.caption)
                        Text("Passive — do other tasks while waiting")
                            .font(.caption)
                    }
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.yellow.opacity(0.1))
                    .clipShape(Capsule())
                }

                // Tasks list
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(block.tasks) { task in
                        taskRow(task)
                    }
                }
                .padding(.horizontal)

                // Timer (for passive blocks or blocks with duration)
                if block.totalDurationSeconds > 0 {
                    timerView(duration: block.totalDurationSeconds)
                }

                // Recipe source tags
                HStack(spacing: 8) {
                    ForEach(block.recipeNames, id: \.self) { name in
                        Text(name)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(colorForRecipe(name).opacity(0.6))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                // Navigation buttons
                HStack(spacing: 20) {
                    if currentBlockIndex > 0 {
                        Button {
                            withAnimation { currentBlockIndex -= 1 }
                            resetTimer()
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Previous")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 24)
                            .background(.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    Button {
                        withAnimation { currentBlockIndex += 1 }
                        resetTimer()
                    } label: {
                        HStack {
                            Text(currentBlockIndex < blocks.count - 1 ? "Next" : "Finish")
                            Image(systemName: currentBlockIndex < blocks.count - 1 ? "chevron.right" : "checkmark")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.primaryGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    if let name = task.recipeName {
                        Text(name)
                            .font(.caption2)
                            .foregroundStyle(colorForRecipe(name))
                    }
                    if let step = task.sourceStepNumber {
                        Text("Step \(step)")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                    if task.durationSeconds > 0 {
                        Text("\(task.durationSeconds / 60)m")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Timer

    private func timerView(duration: Int) -> some View {
        VStack(spacing: 8) {
            Text(formatTimer(timerSeconds))
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                Button {
                    if isTimerRunning {
                        pauseTimer()
                    } else {
                        startTimer(duration: duration)
                    }
                } label: {
                    Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }

                Button {
                    resetTimer()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
            }
        }
        .padding()
    }

    // MARK: - Completion Screen

    private var completionScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(AppColors.primaryGreen)

            Text("All Done!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("You cooked \(recipes.count) recipes together!")
                .font(.title3)
                .foregroundStyle(.gray)

            VStack(spacing: 8) {
                ForEach(recipes) { recipe in
                    HStack {
                        Circle()
                            .fill(colorForRecipe(recipe.title))
                            .frame(width: 8, height: 8)
                        Text(recipe.title)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppColors.primaryGreen)
                    }
                }
            }
            .padding()
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Spacer()

            Button {
                endSession()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.primaryGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Timer Helpers

    private func startTimer(duration: Int) {
        timerSeconds = duration
        timerDuration = TimeInterval(duration)
        timerStartedAt = Date()
        isTimerRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                guard let start = timerStartedAt else { return }
                let elapsed = Date().timeIntervalSince(start)
                let remaining = max(0, Int(timerDuration - elapsed))
                timerSeconds = remaining
                if remaining == 0 {
                    isTimerRunning = false
                    timer?.invalidate()
                }
            }
        }
    }

    private func pauseTimer() {
        isTimerRunning = false
        timer?.invalidate()
        timerDuration = TimeInterval(timerSeconds)
        timerStartedAt = nil
    }

    private func resetTimer() {
        isTimerRunning = false
        timer?.invalidate()
        timerSeconds = 0
        timerStartedAt = nil
    }

    private func formatTimer(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Colors

    private func colorForBlock(_ block: MultiRecipeScheduler.ScheduledBlock) -> Color {
        if block.recipeNames.count > 1 { return .white }
        return colorForRecipe(block.recipeNames.first ?? "")
    }

    private func colorForRecipe(_ name: String) -> Color {
        guard let idx = recipes.firstIndex(where: { $0.title == name }) else { return .gray }
        return recipeColors[idx % recipeColors.count]
    }

    // MARK: - Session Management

    private func endSession() {
        for recipe in recipes {
            CookingSession.clear(recipeId: recipe.id)
        }
        appState.activeCooks.refresh()
        dismiss()
    }
}
