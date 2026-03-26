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

    @State private var pantryReviewItems: [PantryCookReviewItem] = []
    @State private var displayMode: CookDisplayMode = .step
    @State private var tabStepIndex: Int = 0
    @State private var showNoPantryMatchAlert = false

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
            // Cancel any lingering background notifications for this recipe
            // (handles re-entering from mini player / queue after backgrounding)
            NotificationService.shared.cancelAllNotifications(recipeId: recipe.id.uuidString)

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
                tabStepIndex = resumeAtStep
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
            // Refresh so mini player / queue see the persisted session
            appState.activeCooks.refresh()
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
        .onChange(of: viewModel?.currentStepIndex) { _, _ in
            appState.activeCooks.refresh()
        }
        .onChange(of: viewModel?.isConversationActive) { _, active in
            if active == true {
                // Session was just persisted in startConversation — pick it up
                appState.activeCooks.refresh()
            }
        }
        .confirmationDialog(
            "End Cooking Session?",
            isPresented: $showEndConfirm,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) {
                if let queueStageID {
                    Task { await appState.skipCookQueueStage(queueStageID) }
                }
                viewModel?.endCookingSession()
                appState.activeCooks.refresh()
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
        .alert("Nothing to Update", isPresented: $showNoPantryMatchAlert) {
            Button("OK") { }
        } message: {
            Text("None of this recipe's ingredients matched items in your pantry. Add ingredients to your pantry to track usage.")
        }
        .appNavigationSheet(isPresented: $showPantryReview) {
            if let viewModel {
                PantryCookReviewSheet(
                    recipeTitle: viewModel.recipe.title,
                    items: $pantryReviewItems,
                    onApply: { items in
                        await appState.applyPantryCookReview(items)
                    },
                    onCompletion: { }
                )
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
                        TabView(selection: $tabStepIndex) {
                            ForEach(Array(vm.steps.enumerated()), id: \.element.id) { index, step in
                                stepView(step)
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .onChange(of: tabStepIndex) { _, newIndex in
                            if newIndex != vm.currentStepIndex {
                                vm.goToStep(newIndex)
                            }
                        }
                        .onChange(of: vm.currentStepIndex) { _, newIndex in
                            if newIndex != tabStepIndex {
                                tabStepIndex = newIndex
                            }
                        }
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
        ZStack {
            // Center title
            Text(vm.recipe.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(PCColors.textPrimary)
                .lineLimit(1)

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
                        .foregroundStyle(PCColors.textPrimary)
                }

                Spacer()
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
        PCProgressBar(
            progress: vm.progress,
            label: "Step \(vm.currentStepIndex + 1) of \(vm.steps.count)"
        )
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
                        .foregroundStyle(vm.timerSeconds <= AppConfig.timerExpiryThresholdSeconds ? PCColors.expired : PCColors.accent)

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
        HStack(spacing: 12) {
            Button {
                vm.previousStep()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline)
                    Text("Back")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundStyle(vm.isFirstStep ? PCColors.textTertiary.opacity(0.3) : PCColors.textPrimary)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(PCColors.fillTertiary)
                .clipShape(Capsule())
            }
            .disabled(vm.isFirstStep)

            Button {
                vm.repeatCurrentStep()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.subheadline)
                    .foregroundStyle(PCColors.textSecondary)
                    .padding(12)
                    .background(PCColors.fillTertiary)
                    .clipShape(Circle())
            }

            Button {
                vm.nextStep()
            } label: {
                HStack(spacing: 4) {
                    Text(vm.isLastStep ? "Done" : "Next")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Image(systemName: vm.isLastStep ? "checkmark" : "chevron.right")
                        .font(.subheadline)
                }
                .foregroundStyle(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(vm.isLastStep ? PCColors.accent : PCColors.accent)
                .clipShape(Capsule())
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

                // Mute/unmute mic
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
                    Task {
                        // Save rating if set, then mark as cooked
                        if vm.selectedRating != nil {
                            await appState.updateRecipe(vm.ratedRecipe)
                        }
                        NotificationService.shared.cancelAllNotifications(recipeId: vm.recipe.id.uuidString)
                        if let queueStageID {
                            await appState.completeCookQueueStage(queueStageID)
                        } else {
                            await appState.stampCookedMealPlanEntriesByRecipe(vm.recipe.id)
                        }
                        await appState.addPreparedDishForRecipe(vm.recipe)
                        CookingSession.clear(recipeId: vm.recipe.id)
                        vm.endCookingSession()
                        appState.activeCooks.refresh()

                        let reviewItems = appState.pantryCookReviewItems(for: vm.recipe)
                        if reviewItems.isEmpty {
                            showNoPantryMatchAlert = true
                        } else {
                            pantryReviewItems = reviewItems
                            showPantryReview = true
                        }
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
                        NotificationService.shared.cancelAllNotifications(recipeId: vm.recipe.id.uuidString)
                        if let queueStageID {
                            await appState.completeCookQueueStage(queueStageID)
                        } else {
                            await appState.stampCookedMealPlanEntriesByRecipe(vm.recipe.id)
                        }
                        await appState.addPreparedDishForRecipe(vm.recipe)
                        CookingSession.clear(recipeId: vm.recipe.id)
                        vm.endCookingSession()
                        appState.activeCooks.refresh()
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