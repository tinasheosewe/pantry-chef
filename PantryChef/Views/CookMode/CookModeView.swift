import SwiftUI

struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState

    /// Created lazily on first appear — no heavy AV objects at app launch.
    @State private var realtimeService: RealtimeService?
    @State private var viewModel: CookModeViewModel?
    @State private var syncTask: Task<Void, Never>?
    @State private var showEndConfirm = false
    @State private var showPantryReview = false
    @State private var showPreparedDishEditor = false
    @State private var pantryReviewItems: [PantryCookReviewItem] = []
    @State private var displayMode: CookDisplayMode = .step

    private let recipe: Recipe
    private let resumeAtStep: Int
    private let isResuming: Bool
    private let queueID: UUID?
    private let queueStageID: UUID?

    init(recipe: Recipe, resumeAtStep: Int = 0, isResuming: Bool = false, queueID: UUID? = nil, queueStageID: UUID? = nil) {
        self.recipe = recipe
        self.resumeAtStep = resumeAtStep
        self.isResuming = isResuming
        self.queueID = queueID
        self.queueStageID = queueStageID
    }

    var body: some View {
        ZStack {
            PCColors.background.ignoresSafeArea()
            if let viewModel {
                cookContent(vm: viewModel)
            } else {
                ProgressView()
                    .tint(PCColors.accent)
            }
        }
        .onAppear {
            if viewModel == nil {
                let realtime = RealtimeService()
                realtimeService = realtime
                let vm = CookModeViewModel(
                    recipe: recipe,
                    realtimeService: realtime,
                    initialStepIndex: resumeAtStep,
                    isResuming: isResuming,
                    queueId: queueID,
                    queueStageId: queueStageID
                )
                viewModel = vm
                // Auto-start conversational cook mode
                vm.startConversation()
            }
            if syncTask == nil {
                // Poll realtime state at ~15 fps with lifecycle-aware cancellation.
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
            // Auto-background on any dismiss (unless explicitly ending)
            if let vm = viewModel, !vm.isEndingSession, !vm.didContinueInBackground {
                vm.continueInBackground()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                viewModel?.syncTimerOnForeground()
                // If we auto-backgrounded when the app went inactive, resume live voice
                if let vm = viewModel, vm.didContinueInBackground {
                    vm.resumeFromBackground()
                }
            case .background:
                // Auto-schedule notifications when app goes to background
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
        .confirmationDialog(
            "End Cooking Session?",
            isPresented: $showEndConfirm,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) {
                viewModel?.endCookingSession()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will stop all step notifications. You can minimize to keep cooking in the background.")
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
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please enable Speech Recognition and Microphone access in Settings to use voice commands.")
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
        .appNavigationSheet(isPresented: $showPantryReview) {
            if let viewModel {
                PantryCookReviewSheet(
                    recipeTitle: viewModel.recipe.title,
                    items: $pantryReviewItems,
                    onApply: { items in
                        await appState.applyPantryCookReview(items)
                    },
                    onCompletion: {
                        dismiss()
                    }
                )
            }
        }
        .sheet(isPresented: $showPreparedDishEditor) {
            if let viewModel {
                PreparedDishEditorView(appState: appState, seedRecipe: viewModel.recipe) { dish in
                    Task {
                        await appState.addPreparedDish(dish)
                    }
                }
            }
        }
    }

    // MARK: - Cook Content

    @ViewBuilder
    private func cookContent(vm: CookModeViewModel) -> some View {
        if vm.showCompletionScreen {
            completionView(vm: vm)
        } else {
            let isFullRecipeMode = displayMode == .fullRecipe

            VStack(spacing: 0) {
                topBar(vm: vm)
                progressBar(vm: vm)

                Picker("Display", selection: $displayMode) {
                    ForEach(CookDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 12)

                Group {
                    if displayMode == .step {
                        TabView(selection: Bindable(vm).currentStepIndex) {
                            ForEach(Array(vm.steps.enumerated()), id: \.element.id) { index, step in
                                stepView(step)
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    } else {
                        fullRecipeView(vm: vm)
                    }
                }

                if !isFullRecipeMode && (vm.currentStep?.timerMinutes != nil || vm.isTimerRunning) {
                    timerView(vm: vm)
                }

                if !isFullRecipeMode {
                    navigationControls(vm: vm)
                }

                if !isFullRecipeMode && vm.isConversationActive {
                    conversationIndicator(vm: vm)
                }
            }
        }
    }

    // MARK: - Top Bar

    private func topBar(vm: CookModeViewModel) -> some View {
        HStack {
            // Minimize — auto-backgrounds and dismisses
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .foregroundStyle(PCColors.textPrimary)
            }

            Spacer()

            Text(vm.recipe.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(PCColors.textPrimary)
                .lineLimit(1)

            Spacer()

            // End Session (explicit kill)
            Button {
                showEndConfirm = true
            } label: {
                Text("End")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PCColors.expired)
            }

            // Mute/unmute mic
            Button {
                vm.toggleMicMute()
            } label: {
                Image(systemName: vm.isMicMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.title3)
                    .foregroundStyle(vm.isMicMuted ? .gray : PCColors.accent)
            }
        }
        .padding()
        .overlay {
            if vm.isSchedulingBackground {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(PCColors.accent)
                    Text("Scheduling reminders…")
                        .font(.caption)
                        .foregroundStyle(PCColors.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Progress Bar

    private func progressBar(vm: CookModeViewModel) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(PCColors.accent.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(PCColors.accent)
                        .frame(width: geo.size.width * vm.progress)
                        .animation(.easeInOut(duration: 0.3), value: vm.progress)
                }
            }
            .frame(height: 4)

            Text("Step \(vm.currentStepIndex + 1) of \(vm.steps.count)")
                .font(.caption2)
                .foregroundStyle(PCColors.textSecondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Step View

    private func stepView(_ step: RecipeStep) -> some View {
        AppScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Text("STEP \(step.stepNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(2)
                    .foregroundStyle(PCColors.accent)

                Text(step.instruction)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(PCColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .lineSpacing(4)

                if let timer = step.timerMinutes {
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .foregroundStyle(PCColors.expiring)
                        Text("\(timer) minutes")
                            .fontWeight(.medium)
                            .foregroundStyle(PCColors.expiring)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(PCColors.expiring.opacity(0.15))
                    .clipShape(Capsule())
                }

                if let tip = step.tip {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(PCColors.expiring)
                            Text("Beginner Tip")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(PCColors.expiring)
                        }
                        Text(tip)
                            .font(.subheadline)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                    .padding()
                    .background(PCColors.expiring.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: 40)
            }
        }
    }

    private func fullRecipeView(vm: CookModeViewModel) -> some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ingredients")
                        .font(.headline)
                        .foregroundStyle(PCColors.textPrimary)

                    ForEach(vm.recipe.ingredients) { ingredient in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(PCColors.accent)
                                .padding(.top, 6)
                            Text(ingredient.displayText)
                                .font(.subheadline)
                                .foregroundStyle(PCColors.textPrimary)
                        }
                    }
                }
                .padding()
                .background(PCColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Steps")
                        .font(.headline)
                        .foregroundStyle(PCColors.textPrimary)

                    ForEach(Array(vm.steps.enumerated()), id: \.element.id) { index, step in
                        Button {
                            vm.goToStep(index)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Text("\(step.stepNumber)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundStyle(index == vm.currentStepIndex ? .white : PCColors.accent)
                                        .frame(width: 28, height: 28)
                                        .background(index == vm.currentStepIndex ? PCColors.accent : PCColors.accent.opacity(0.12))
                                        .clipShape(Circle())

                                    Text(step.instruction)
                                        .font(.subheadline)
                                        .fontWeight(index == vm.currentStepIndex ? .semibold : .regular)
                                        .foregroundStyle(PCColors.textPrimary)
                                        .multilineTextAlignment(.leading)

                                    Spacer()
                                }

                                if let timerMinutes = step.timerMinutes {
                                    Label("\(timerMinutes) min", systemImage: "timer")
                                        .font(.caption)
                                        .foregroundStyle(PCColors.expiring)
                                        .padding(.leading, 38)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(index == vm.currentStepIndex ? PCColors.accent.opacity(0.08) : PCColors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .padding(.bottom, 24)
        }
    }

    // MARK: - Timer View

    private func timerView(vm: CookModeViewModel) -> some View {
        VStack(spacing: 8) {
            if vm.isTimerRunning {
                HStack(spacing: 16) {
                    Text(vm.timerDisplay)
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundStyle(vm.timerSeconds <= 10 ? PCColors.expired : PCColors.accent)

                    VStack(spacing: 8) {
                        Button {
                            vm.pauseTimer()
                        } label: {
                            Image(systemName: vm.isPaused ? "play.fill" : "pause.fill")
                                .font(.title3)
                                .foregroundStyle(PCColors.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(PCColors.fillTertiary)
                                .clipShape(Circle())
                        }

                        Button {
                            vm.stopTimer()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(PCColors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(PCColors.fillTertiary)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding()
                .background(PCColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            } else if vm.currentStep?.timerMinutes != nil {
                Button {
                    vm.startTimer()
                } label: {
                    Label("Start Timer", systemImage: "timer")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(PCColors.expiring)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
    }

    // MARK: - Navigation Controls

    private func navigationControls(vm: CookModeViewModel) -> some View {
        HStack(spacing: 32) {
            Button {
                vm.previousStep()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(vm.isFirstStep ? PCColors.textTertiary.opacity(0.3) : PCColors.textPrimary)
                    Text("Back")
                        .font(.caption2)
                        .foregroundStyle(vm.isFirstStep ? PCColors.textTertiary.opacity(0.3) : PCColors.textSecondary)
                }
            }
            .disabled(vm.isFirstStep)

            Button {
                vm.repeatCurrentStep()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(PCColors.textSecondary)
                    Text("Repeat")
                        .font(.caption2)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }

            Button {
                vm.nextStep()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: vm.isLastStep ? "checkmark.circle.fill" : "chevron.right.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(vm.isLastStep ? PCColors.accent : PCColors.textPrimary)
                    Text(vm.isLastStep ? "Done" : "Next")
                        .font(.caption2)
                        .foregroundStyle(vm.isLastStep ? PCColors.accent : PCColors.textSecondary)
                }
            }
        }
        .padding()
        .padding(.bottom, 8)
    }

    // MARK: - Conversation Indicator (Realtime API)

    private func conversationIndicator(vm: CookModeViewModel) -> some View {
        VStack(spacing: 8) {
            // Status bar with animated waveform
            HStack(spacing: 10) {
                if vm.isUserSpeaking {
                    // User is speaking
                    Circle()
                        .fill(PCColors.info)
                        .frame(width: 10, height: 10)
                        .modifier(PulseAnimation())
                    Text("Listening to you…")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(PCColors.info)
                } else if vm.isModelSpeaking {
                    // AI is speaking — show waveform
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(PCColors.accent)
                                .frame(width: 3, height: CGFloat.random(in: 8...20))
                        }
                    }
                    .modifier(PulseAnimation())
                    Text("Speaking…")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(PCColors.accent)
                } else {
                    Circle()
                        .fill(PCColors.accent)
                        .frame(width: 8, height: 8)
                        .modifier(PulseAnimation())
                    Text(vm.conversationStatus.isEmpty ? "Ready — just talk!" : vm.conversationStatus)
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }

                Spacer()
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

    // MARK: - Completion View

    private func completionView(vm: CookModeViewModel) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(PCColors.accent)

            Text("Well Done!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(PCColors.textPrimary)

            Text("You've completed \(vm.recipe.title)")
                .font(.subheadline)
                .foregroundStyle(PCColors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Text("How was it?")
                    .font(.subheadline)
                    .foregroundStyle(PCColors.textSecondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            vm.setRating(star)
                        } label: {
                            Image(systemName: star <= (vm.selectedRating ?? 0) ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundStyle(star <= (vm.selectedRating ?? 0) ? PCColors.expiring : PCColors.textTertiary.opacity(0.3))
                        }
                    }
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showPreparedDishEditor = true
                } label: {
                    Text("Add to Prepared Food")
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(PCColors.accent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    Task {
                        // Save rating if set, then mark as cooked
                        if vm.selectedRating != nil {
                            await appState.updateRecipe(vm.ratedRecipe)
                        }
                        await appState.markRecipeAsCooked(vm.recipe)
                        if let queueStageID {
                            await appState.completeCookQueueStage(queueStageID)
                        }

                        let reviewItems = appState.pantryCookReviewItems(for: vm.recipe)
                        guard !reviewItems.isEmpty else {
                            dismiss()
                            return
                        }

                        pantryReviewItems = reviewItems
                        showPantryReview = true
                    }
                } label: {
                    Text(queueStageID == nil ? "Done — Update Pantry" : "Done — Update Pantry & Queue")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(PCColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    Task {
                        if vm.selectedRating != nil {
                            await appState.updateRecipe(vm.ratedRecipe)
                        }
                        await appState.markRecipeAsCooked(vm.recipe)
                        if let queueStageID {
                            await appState.completeCookQueueStage(queueStageID)
                        }
                        dismiss()
                    }
                } label: {
                    Text(queueStageID == nil ? "Close" : "Close & Continue Queue")
                        .foregroundStyle(PCColors.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

private enum CookDisplayMode: String, CaseIterable, Identifiable {
    case step
    case fullRecipe

    var id: Self { self }

    var title: String {
        switch self {
        case .step:
            return "Step"
        case .fullRecipe:
            return "Whole Recipe"
        }
    }
}

// MARK: - Pulse Animation

private struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}