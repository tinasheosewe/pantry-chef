import SwiftUI

// MARK: - Multi-Cook Mode View
//
// Displays the interleaved timeline from MultiRecipeScheduler with voice AI.
// Each block shows the LLM-authored natural language instruction.
// Passive blocks start a background timer pill when the user advances past them.

struct MultiCookModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState

    let recipes: [Recipe]
    let blocks: [MultiRecipeScheduler.ScheduledBlock]
    let queueID: UUID?
    let queueStageID: UUID?
    let resumeSessionId: UUID?
    let resumeAtBlock: Int

    @State private var realtimeService: RealtimeService?
    @State private var viewModel: MultiCookModeViewModel?
    @State private var syncTask: Task<Void, Never>?
    @State private var showEndConfirm = false

    /// Distinct color per recipe.
    private let recipeColors: [Color] = [
        PCColors.info, PCColors.expiring, PCColors.teal,
        Color(red: 0.94, green: 0.53, blue: 0.68),   // rose
        PCColors.accent,
        Color(red: 0.48, green: 0.40, blue: 0.82)     // soft indigo
    ]

    init(
        recipes: [Recipe],
        blocks: [MultiRecipeScheduler.ScheduledBlock],
        queueID: UUID? = nil,
        queueStageID: UUID? = nil,
        resumeSessionId: UUID? = nil,
        resumeAtBlock: Int = 0
    ) {
        self.recipes = recipes
        self.blocks = blocks
        self.queueID = queueID
        self.queueStageID = queueStageID
        self.resumeSessionId = resumeSessionId
        self.resumeAtBlock = resumeAtBlock
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let viewModel {
                cookContent(vm: viewModel)
            } else {
                ProgressView()
                    .tint(PCColors.accent)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            if viewModel == nil {
                let realtime = RealtimeService()
                realtimeService = realtime
                let vm = MultiCookModeViewModel(
                    recipes: recipes,
                    blocks: blocks,
                    realtimeService: realtime,
                    preferenceStore: appState.cookModePreferenceStore,
                    queueID: queueID,
                    queueStageID: queueStageID,
                    sessionId: resumeSessionId ?? UUID(),
                    resumeAtBlock: resumeAtBlock
                )
                viewModel = vm
                vm.startConversation()
            }
            if syncTask == nil {
                syncTask = Task { @MainActor in
                    while !Task.isCancelled {
                        viewModel?.syncRealtimeState()
                        try? await Task.sleep(for: .milliseconds(66))
                    }
                }
            }
        }
        .onDisappear {
            syncTask?.cancel()
            syncTask = nil
            // Auto-continue in background on any dismiss (unless explicitly ending)
            if let vm = viewModel, !vm.isEndingSession, !vm.didContinueInBackground {
                vm.continueInBackground()
            }
            viewModel?.cleanup()
            appState.activeCooks.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // If we auto-backgrounded when the app went inactive, resume live voice
                if let vm = viewModel, vm.didContinueInBackground {
                    vm.resumeFromBackground()
                }
            case .background:
                // Auto-continue in background when app goes to background
                viewModel?.continueInBackground()
            default:
                break
            }
        }
        .onChange(of: viewModel?.isEndingSession ?? false) { _, isEnding in
            if isEnding {
                dismiss()
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
        .alert("Timer Done!", isPresented: Binding(
            get: { viewModel?.showTimerFinishedAlert ?? false },
            set: { viewModel?.showTimerFinishedAlert = $0 }
        )) {
            Button("OK") {}
        } message: {
            Text("\(viewModel?.finishedTimerName ?? "A passive task") is ready!")
        }
        .alert("Voice Control Unavailable",
               isPresented: Binding(
                get: { viewModel?.voiceAuthorizationDenied ?? false },
                set: { viewModel?.voiceAuthorizationDenied = $0 }
               )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable Microphone access in Settings to use voice commands.")
        }
        .alert("Voice Chat Error",
               isPresented: Binding(
                get: { viewModel?.conversationError != nil },
                set: { if !$0 { viewModel?.conversationError = nil } }
               )) {
            Button("Retry") {
                viewModel?.stopConversation()
                viewModel?.startConversation()
            }
            Button("Dismiss", role: .cancel) {
                viewModel?.stopConversation()
            }
        } message: {
            Text(viewModel?.conversationError ?? "Connection lost")
        }
    }

    // MARK: - Cook Content

    @ViewBuilder
    private func cookContent(vm: MultiCookModeViewModel) -> some View {
        if vm.showCompletionScreen {
            completionScreen(vm: vm)
        } else {
            VStack(spacing: 0) {
                topBar(vm: vm)
                progressBar(vm: vm)

                // Passive timer pills
                if !vm.runningTimers.isEmpty {
                    passiveTimerBanner(vm: vm)
                }

                if let block = vm.currentBlock {
                    blockContent(block, vm: vm)
                }
            }
        }
    }

    // MARK: - Top Bar

    private func topBar(vm: MultiCookModeViewModel) -> some View {
        ZStack {
            // Center title
            VStack(spacing: 2) {
                Text("Multi-Cook")
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)
                Text("\(recipes.count) Recipes")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PCColors.textPrimary)
            }

            HStack {
                // Close — offers background or end
                Menu {
                    Button {
                        dismiss()
                    } label: {
                        Label("Continue in Background", systemImage: "arrow.down.to.line")
                    }
                    Button(role: .destructive) {
                        showEndConfirm = true
                    } label: {
                        Label("End Session", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                        .padding(8)
                }

                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Progress Bar

    private func progressBar(vm: MultiCookModeViewModel) -> some View {
        PCProgressBar(
            progress: vm.progress,
            label: "Block \(min(vm.currentBlockIndex + 1, blocks.count)) of \(blocks.count)",
            trailingLabel: "~\(blocks.map(\.totalDurationSeconds).reduce(0, +) / 60) min total",
            height: 6
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Passive Timer Banner

    private func passiveTimerBanner(vm: MultiCookModeViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.runningTimers) { rt in
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

    // MARK: - Conversation Indicator

    private func conversationIndicator(vm: MultiCookModeViewModel) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if vm.isUserSpeaking {
                    Circle()
                        .fill(PCColors.info)
                        .frame(width: 10, height: 10)
                        .modifier(MultiCookPulseAnimation())
                    Text("Listening to you…")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(PCColors.info)
                } else if vm.isModelSpeaking {
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(PCColors.accent)
                                .frame(width: 3, height: CGFloat.random(in: 8...20))
                        }
                    }
                    .modifier(MultiCookPulseAnimation())
                    Text("Speaking…")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(PCColors.accent)
                } else {
                    Circle()
                        .fill(PCColors.accent)
                        .frame(width: 8, height: 8)
                        .modifier(MultiCookPulseAnimation())
                    Text(vm.conversationStatus.isEmpty ? "Ready — just talk!" : vm.conversationStatus)
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }

                Spacer()

                Button {
                    vm.toggleMute()
                } label: {
                    Image(systemName: vm.isMuted ? "speaker.slash.fill" : "mic.fill")
                        .font(.subheadline)
                        .foregroundStyle(vm.isMuted ? PCColors.textTertiary : PCColors.accent)
                        .frame(width: 32, height: 32)
                        .background(PCColors.fillTertiary)
                        .clipShape(Circle())
                }
            }

            if !vm.conversationTranscript.isEmpty {
                Text(vm.conversationTranscript)
                    .font(.caption)
                    .foregroundStyle(PCColors.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PCColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Block Content

    private func blockContent(_ block: MultiRecipeScheduler.ScheduledBlock, vm: MultiCookModeViewModel) -> some View {
        VStack(spacing: 0) {
            // Scrollable instruction area
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

                    // LLM-authored instruction — rendered as bullet list
                    instructionBullets(block.displayInstruction)
                        .padding(.horizontal)

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
                    .padding(.bottom, 16)
                }
            }

            Spacer(minLength: 0)

            // Fixed bottom area
            VStack(spacing: 8) {
                // Voice conversation indicator
                if vm.isConversationActive {
                    conversationIndicator(vm: vm)
                }

                // Navigation buttons
                HStack(spacing: 12) {
                    if !vm.isFirstBlock {
                        Button {
                            withAnimation { vm.previousBlock() }
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
                        withAnimation { vm.nextBlock() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(vm.isLastBlock
                                 ? "Finish"
                                 : (block.type == .passive ? "Start & Next" : "Next"))
                            Image(systemName: vm.isLastBlock
                                  ? "checkmark"
                                  : (block.type == .passive ? "timer" : "chevron.right"))
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
            .background(Color.black)
        }
    }

    // MARK: - Instruction Bullets

    /// Splits the LLM instruction into bullet lines for readability.
    /// Handles "• " prefixed lines, numbered lines, or falls back to sentence splitting.
    private func instructionBullets(_ text: String) -> some View {
        let lines = parseBulletLines(text)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(PCColors.accent)
                    Text(line)
                        .font(.title3)
                        .foregroundStyle(PCColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Parse instruction text into individual action lines.
    private func parseBulletLines(_ text: String) -> [String] {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // If the LLM already used bullet or numbered lines, split on newlines
        let newlineLines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if newlineLines.count > 1 {
            return newlineLines.map { line in
                // Strip leading bullet/number markers
                var cleaned = line
                if cleaned.hasPrefix("•") || cleaned.hasPrefix("-") || cleaned.hasPrefix("*") {
                    cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespaces)
                } else if let dotRange = cleaned.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                    cleaned = String(cleaned[dotRange.upperBound...])
                }
                return cleaned
            }
        }
        // Fallback: split a single paragraph on sentence boundaries
        let sentences = raw.components(separatedBy: ". ")
            .flatMap { $0.components(separatedBy: ".\n") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") ? $0 : $0 + "." }
        return sentences.count > 1 ? sentences : [raw]
    }

    // MARK: - Completion Screen

    private func completionScreen(vm: MultiCookModeViewModel) -> some View {
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
        // Tell the view model to end (sets isEndingSession flag, clears session)
        viewModel?.endSession()
        
        Task {
            if let queueStageID {
                if completed {
                    await appState.cookGateway.completeStage(queueStageID)
                } else {
                    await appState.cookGateway.skipStage(queueStageID)
                }
            }
        }
        for recipe in recipes {
            appState.cookingSessionStore.clear(recipeId: recipe.id)
        }
        appState.activeCooks.refresh()
        // Dismiss is handled by the onChange(of: viewModel?.isEndingSession) observer
    }
}

// MARK: - Pulse Animation

private struct MultiCookPulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
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
