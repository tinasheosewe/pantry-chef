import SwiftUI
import AVFoundation
import Combine

@Observable
@MainActor
final class CookModeViewModel {
    var currentStepIndex = 0
    var timerSeconds: Int = 0
    var isTimerRunning = false
    var isPaused = false
    var showCompletionScreen = false
    var selectedRating: Int? = nil
    var voiceAuthorizationDenied = false

    /// Conversational voice mode (Realtime API) — always-on in cook mode
    var isConversationActive = false
    /// True while prepareAudio() is running (prevents sync timer from killing the session).
    /// Internal for testability.
    var isPreparing = false
    var conversationTranscript = ""   // what the AI is currently saying
    var isModelSpeaking = false
    var isUserSpeaking = false
    var conversationStatus = ""
    var conversationError: String?
    /// Whether the session is fully muted (mic + AI speaker)
    var isMuted = false

    /// Continue in Background state
    var isSchedulingBackground = false
    var didContinueInBackground = false
    /// Set when the user explicitly ends the session (vs. auto-backgrounding)
    var isEndingSession = false

    /// Tracks whether the WebRTC connection has ever succeeded in this session,
    /// so we can distinguish "not yet connected" from "connection dropped".
    private var wasEverConnected = false

    /// Cached notification permission result from startConversation() so
    /// auto-background can schedule synchronously without an async re-check.
    private var cachedNotificationPermission = false

    let recipe: Recipe
    let realtimeService: any RealtimeServiceProtocol
    let queueId: UUID?
    let queueStageId: UUID?

    /// Whether the next startConversation() should use resume greeting.
    private var isResuming: Bool

    /// Date-based timer tracking — survives backgrounding
    private var timerStartedAt: Date?
    private var timerDuration: TimeInterval = 0
    private var timerPausedRemaining: TimeInterval = 0
    private var timerCancellable: AnyCancellable?

    init(
        recipe: Recipe,
        realtimeService: any RealtimeServiceProtocol,
        initialStepIndex: Int = 0,
        isResuming: Bool = false,
        queueId: UUID? = nil,
        queueStageId: UUID? = nil
    ) {
        self.recipe = recipe
        self.realtimeService = realtimeService
        self.isResuming = isResuming
        self.currentStepIndex = initialStepIndex
        self.queueId = queueId
        self.queueStageId = queueStageId
        setupRealtimeCallbacks()
    }

    var steps: [RecipeStep] {
        recipe.steps.sorted { $0.stepNumber < $1.stepNumber }
    }

    var currentStep: RecipeStep? {
        guard currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }

    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(currentStepIndex + 1) / Double(steps.count)
    }

    var isFirstStep: Bool { currentStepIndex == 0 }
    var isLastStep: Bool { currentStepIndex >= steps.count - 1 }

    var timerDisplay: String {
        let minutes = timerSeconds / 60
        let seconds = timerSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Returns a rated copy of the recipe.
    var ratedRecipe: Recipe {
        var copy = recipe
        copy.rating = selectedRating
        return copy
    }

    // MARK: - Navigation

    func nextStep() {
        guard !isLastStep else {
            showCompletionScreen = true
            return
        }
        stopTimer()
        currentStepIndex += 1
        notifyStepChanged()
        autoStartTimerIfNeeded()
    }

    func previousStep() {
        guard !isFirstStep else { return }
        stopTimer()
        currentStepIndex -= 1
        notifyStepChanged()
    }

    func goToStep(_ index: Int) {
        guard index >= 0 && index < steps.count else { return }
        stopTimer()
        currentStepIndex = index
        notifyStepChanged()
    }

    /// Tell the Realtime API model about the new step so it reads it aloud.
    private func notifyStepChanged() {
        guard isConversationActive, let step = currentStep else { return }
        var msg = "The user moved to step \(step.stepNumber): \(step.instruction)."
        if let tip = step.tip { msg += " Tip: \(tip)." }
        msg += " Read this step aloud for them, briefly."
        realtimeService.sendUserMessage(msg)
    }

    /// Ask the model to re-read the current step.
    func repeatCurrentStep() {
        guard isConversationActive, let step = currentStep else { return }
        let msg = "Please repeat step \(step.stepNumber): \(step.instruction)"
        realtimeService.sendUserMessage(msg)
    }

    // MARK: - Mute (both mic and AI speaker)

    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            realtimeService.stopCapture()
            realtimeService.silenceAI()
        } else {
            realtimeService.startCapture()
        }
    }

    // MARK: - Conversational Voice (OpenAI Realtime API)

    func startConversation() {
        Task {
            let micAuthorized = await Self.requestMicrophoneAuthorization()
            guard micAuthorized else {
                voiceAuthorizationDenied = true
                return
            }

            // Pre-request notification permission so auto-background works
            cachedNotificationPermission = await NotificationService.shared.requestPermission()

            // If resuming from background, cancel pending notifications (we're live again)
            if isResuming {
                NotificationService.shared.cancelAllNotifications(recipeId: recipe.id.uuidString)
            }

            isConversationActive = true
            isPreparing = true
            voiceAuthorizationDenied = false
            conversationStatus = "Setting up audio…"

            // Prepare audio first — VPIO enable is slow (5-15s).
            // This awaits off the main thread so the UI stays responsive.
            AppLog.info("[CookMode] Preparing audio engine…")
            await realtimeService.prepareAudio()
            AppLog.info("[CookMode] Audio engine ready, isRunning=\(realtimeService.isAudioReady)")

            // Connect WebSocket (audio engine is ready for playback now)
            let instructions = buildConversationInstructions()
            let tools = buildConversationTools()
            realtimeService.connect(withInstructions: instructions, tools: tools)
            AppLog.info("[CookMode] WebSocket connected=\(realtimeService.isConnected)")

            // Now it's safe for the sync timer to check connection state
            isPreparing = false

            // Start mic capture (installs tap — engine is already running)
            realtimeService.startCapture()
            AppLog.info("[CookMode] Mic capture started")

            // Greet the user or resume at the right step
            let greeting: String
            if isResuming {
                greeting = "The user is resuming cooking \(recipe.title) from step \(currentStepIndex + 1). "
                    + "Welcome them back briefly and read step \(currentStepIndex + 1): "
                    + "\(currentStep?.instruction ?? ""). Keep it concise — no need to re-introduce the recipe."
            } else {
                greeting = "The user just started cooking \(recipe.title). "
                    + "Greet them warmly and briefly read step \(currentStepIndex + 1): "
                    + "\(currentStep?.instruction ?? ""). Keep it concise."
            }
            realtimeService.sendUserMessage(greeting)
            AppLog.info("[CookMode] Greeting sent (resume=\(isResuming), step=\(currentStepIndex + 1))")
        }
    }

    func stopConversation() {
        isConversationActive = false
        wasEverConnected = false
        realtimeService.disconnect()
        conversationTranscript = ""
        conversationStatus = ""
        conversationError = nil
        isModelSpeaking = false
        isUserSpeaking = false
        isMuted = false
    }

    // MARK: - Mic Permission

    static func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func setupRealtimeCallbacks() {
        realtimeService.onFunctionCall = { [weak self] name, args in
            Task { @MainActor in
                self?.handleRealtimeFunctionCall(name: name, args: args)
            }
        }
    }

    /// Syncs observable state from RealtimeService — called by the view's timer.
    func syncRealtimeState() {
        guard isConversationActive else { return }
        conversationTranscript = realtimeService.transcript
        isModelSpeaking = realtimeService.isModelSpeaking
        isUserSpeaking = realtimeService.isUserSpeaking
        conversationStatus = realtimeService.statusMessage
        conversationError = realtimeService.errorMessage

        if realtimeService.isConnected {
            wasEverConnected = true
        }

        // Only detect connection drops after we've been connected at least
        // once. Before that, the WebRTC handshake is still in progress and
        // isConnected would be transiently false.
        if !isPreparing && wasEverConnected && !realtimeService.isConnected && isConversationActive {
            // Connection dropped
            isConversationActive = false
        }
    }

    func handleRealtimeFunctionCall(name: String, args: [String: Any]) {
        // Model-initiated navigation: update UI directly WITHOUT calling
        // notifyStepChanged(), which would send a redundant message back
        // to the model (it already knows the step — it chose to call the
        // function). The dispatchFunctionCall sends createResponse() so
        // the model will naturally speak about the new step.
        switch name {
        case "next_step":
            guard !isLastStep else {
                showCompletionScreen = true
                return
            }
            stopTimer()
            currentStepIndex += 1
            autoStartTimerIfNeeded()
        case "previous_step":
            guard !isFirstStep else { return }
            stopTimer()
            currentStepIndex -= 1
        case "go_to_step":
            if let step = args["step_number"] as? Int {
                let index = step - 1
                guard index >= 0 && index < steps.count else { return }
                stopTimer()
                currentStepIndex = index
                autoStartTimerIfNeeded()
            }
        case "repeat_step":
            // No navigation needed — the model will re-read it
            break
        case "start_timer":
            if let minutes = args["minutes"] as? Int {
                startTimerWithMinutes(minutes)
            } else {
                startTimer()
            }
        case "pause_timer":
            pauseTimer()
        case "stop_timer":
            stopTimer()
        case "finish_cooking":
            endCookingSession()
            showCompletionScreen = true
        default:
            break
        }
    }

    func buildConversationInstructions() -> String {
        let stepsText = steps.map { step in
            var s = "Step \(step.stepNumber): \(step.instruction)"
            if let timer = step.timerMinutes { s += " [Timer: \(timer) min]" }
            if let tip = step.tip { s += " [Tip: \(tip)]" }
            return s
        }.joined(separator: "\n")

        let ingredientsList = recipe.ingredients.map { $0.displayText }.joined(separator: ", ")

        return """
        You are an interactive cooking assistant helping the user cook "\(recipe.title)" \
        (serves \(recipe.servings)). Be warm, encouraging, and concise.

        RECIPE STEPS:
        \(stepsText)

        INGREDIENTS: \(ingredientsList)

        The user is currently on step \(currentStepIndex + 1) of \(steps.count).

        BEHAVIOR:
        - Read steps aloud naturally, not robotically. Paraphrase slightly for a conversational feel.
        - When the user asks cooking questions (e.g. "what does dice mean?", "how do I know \
        when the onions are done?"), answer helpfully using your cooking knowledge.
        - Use the provided function tools for navigation: call next_step, previous_step, \
        go_to_step, start_timer, etc. when the user asks.
        - If the user asks for a specific numbered step, call go_to_step directly with that \
        step number. Do NOT chain next_step or previous_step multiple times to get there.
        - After calling a navigation function, briefly acknowledge it (e.g. "Moving to step 3…") \
        then read the new step.
        - Keep responses SHORT — 1-3 sentences normally. Only elaborate when the user asks \
        a specific question.
        - If the user says they're done or finished, call finish_cooking to end the cooking session.
        - You can be interrupted — that's fine, just respond to the new input.
        - IMPORTANT: If the user says "stop", "pause", "wait", "hold on", or "quiet" — even \
        if they interrupt you mid-sentence — you MUST stop talking immediately. Do NOT continue \
        with recipe instructions. Do NOT advance to the next step. Just say something very brief \
        like "OK" or "Sure, I'll wait" and then be completely silent until the user speaks again. \
        This takes absolute priority over everything else.
        - NEVER move to the next step unless the user explicitly says "next", "next step", \
        "move on", "continue", "I'm ready", or similar. Do NOT assume they are ready.
        - CRITICAL: You MUST call the next_step tool to advance steps. NEVER just verbally \
        describe the next step without calling the tool first. The UI tracks steps via tool calls.
        - NOISE REJECTION: Kitchen sounds (sizzling, fans, clanking) sometimes produce \
        garbage transcriptions — e.g. a single character, lone punctuation like "…", \
        random non-word fragments, or brief non-linguistic noise. If the input clearly \
        isn't an intentional utterance, stay completely silent. Real speech is \
        recognizable even when short ("ok", "next", "stop") or in another language.
        - Always speak in English.
        """
    }

    func buildConversationTools() -> [[String: Any]] {
        return [
            [
                "type": "function",
                "name": "next_step",
                "description": "Move to the next cooking step",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "type": "function",
                "name": "previous_step",
                "description": "Go back to the previous cooking step",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "type": "function",
                "name": "go_to_step",
                "description": "Jump to a specific step number",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "step_number": [
                            "type": "integer",
                            "description": "The step number to jump to (1-based)"
                        ]
                    ],
                    "required": ["step_number"]
                ]
            ],
            [
                "type": "function",
                "name": "repeat_step",
                "description": "Repeat the current step instructions",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "type": "function",
                "name": "start_timer",
                "description": "Start a timer for the specified number of minutes",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "minutes": [
                            "type": "integer",
                            "description": "Number of minutes for the timer"
                        ]
                    ],
                    "required": ["minutes"]
                ]
            ],
            [
                "type": "function",
                "name": "pause_timer",
                "description": "Pause or resume the current timer",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "type": "function",
                "name": "stop_timer",
                "description": "Stop and reset the current timer",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "type": "function",
                "name": "finish_cooking",
                "description": "End the cooking session and show the completion screen when the user says they are done.",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ]
        ]
    }

    // MARK: - Rating

    func setRating(_ stars: Int) {
        selectedRating = (selectedRating == stars) ? nil : stars // tap again to deselect
    }

    // MARK: - Timer (Date-based — survives backgrounding)

    func startTimer() {
        guard let step = currentStep, let minutes = step.timerMinutes else { return }
        startTimerWithMinutes(minutes)
    }

    private func startTimerWithMinutes(_ minutes: Int) {
        let duration = TimeInterval(minutes * 60)
        timerDuration = duration
        timerStartedAt = Date()
        timerPausedRemaining = 0
        timerSeconds = minutes * 60
        isTimerRunning = true
        isPaused = false
        startTimerTick()
    }

    private func startTimerTick() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.recalculateTimerSeconds()
                if self.timerSeconds <= 0 {
                    self.timerComplete()
                }
            }
    }

    /// Recalculates timerSeconds from the stored start date and duration.
    /// This ensures the timer "catches up" correctly after returning from background.
    private func recalculateTimerSeconds() {
        guard let startedAt = timerStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = max(0, timerDuration - elapsed)
        timerSeconds = Int(remaining.rounded(.up))
    }

    /// Called when the app returns to foreground — syncs Display from real time.
    func syncTimerOnForeground() {
        guard isTimerRunning, !isPaused else { return }
        recalculateTimerSeconds()
        if timerSeconds <= 0 {
            timerComplete()
        }
    }

    func stopTimer() {
        isTimerRunning = false
        isPaused = false
        timerStartedAt = nil
        timerDuration = 0
        timerPausedRemaining = 0
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func pauseTimer() {
        isPaused.toggle()
        if isPaused {
            // Snapshot remaining time
            recalculateTimerSeconds()
            timerPausedRemaining = TimeInterval(timerSeconds)
            timerCancellable?.cancel()
        } else {
            // Resume: reset startedAt to now, with remaining duration
            timerDuration = timerPausedRemaining
            timerStartedAt = Date()
            startTimerTick()
        }
    }

    private func timerComplete() {
        stopTimer()
        // Notify through the Realtime API so the AI announces it
        if isConversationActive {
            realtimeService.sendUserMessage(
                "The timer just finished! Let the user know and ask if they're ready for the next step."
            )
        }
    }

    private func autoStartTimerIfNeeded() {
        if let step = currentStep, step.timerMinutes != nil {
            startTimer()
        }
    }

    // MARK: - Continue in Background

    /// Schedules notifications deterministically using pre-computed step durations,
    /// then disconnects voice and saves the session.
    /// Safe to call multiple times — guards against double-scheduling.
    func continueInBackground() {
        guard isConversationActive, !didContinueInBackground, !isEndingSession, !showCompletionScreen else { return }
        isSchedulingBackground = true

        Task {
            // Use cached permission when available (fast path for auto-background).
            let authorized: Bool
            if cachedNotificationPermission {
                authorized = true
            } else {
                authorized = await NotificationService.shared.requestPermission()
            }

            if !authorized {
                AppLog.warn("[CookMode] ⚠️ Notification permission denied — background mode will not work")
                conversationError = "Please enable notifications in Settings to use background cook mode."
                isSchedulingBackground = false
                return
            }

            await scheduleBackgroundNotifications()
        }
    }

    /// Resume live voice session after returning from background.
    /// Cancels pending notifications and reconnects.
    func resumeFromBackground() {
        guard didContinueInBackground else { return }
        didContinueInBackground = false
        isSchedulingBackground = false
        isResuming = true

        NotificationService.shared.cancelAllNotifications(recipeId: recipe.id.uuidString)
        AppLog.info("[CookMode] Resuming from background — cancelled pending notifications")

        // Reconnect voice
        startConversation()
    }

    /// The actual scheduling logic, separated so it can run after permission is confirmed.
    private func scheduleBackgroundNotifications() async {
        let remaining = steps.enumerated().filter { $0.offset >= currentStepIndex }
        let recipeId = recipe.id.uuidString
        let notificationService = NotificationService.shared

        // Cancel any existing notifications for this recipe
        notificationService.cancelAllNotifications(recipeId: recipeId)

        var cumulativeDelay: Double = 0

        for (_, step) in remaining {
            let duration = Double(step.effectiveDurationSeconds)

            // Build a concise, self-contained notification message
            let message: String
            if let timer = step.timerMinutes {
                message = "Step \(step.stepNumber)/\(steps.count): \(step.instruction) ⏱ \(timer) min"
            } else {
                message = "Step \(step.stepNumber)/\(steps.count): \(step.instruction)"
            }

            let stepIndex = step.stepNumber - 1
            let nextPreview: String?
            if stepIndex + 1 < steps.count {
                nextPreview = steps[stepIndex + 1].instruction
            } else {
                nextPreview = nil
            }

            notificationService.scheduleStepNotification(
                recipeId: recipeId,
                stepIndex: stepIndex,
                totalSteps: steps.count,
                recipeName: recipe.title,
                message: message,
                nextStepPreview: nextPreview,
                delaySeconds: cumulativeDelay
            )

            cumulativeDelay += duration
        }

        // Schedule session expiry (2 hours after last notification)
        let expiryDelay = cumulativeDelay + 7200
        notificationService.scheduleSessionExpiry(
            recipeId: recipeId,
            recipeName: recipe.title,
            delaySeconds: expiryDelay
        )

        // Save session for potential deep-link return
        let session = CookingSession(
            recipeId: recipe.id,
            recipeName: recipe.title,
            totalSteps: steps.count,
            stepSummaries: steps.map {
                CookingSession.StepSummary(
                    stepNumber: $0.stepNumber,
                    instruction: $0.instruction,
                    timerMinutes: $0.timerMinutes
                )
            },
            currentStepIndex: currentStepIndex,
            startedAt: Date(),
            backgroundedAt: Date(),
            isActive: true,
            expiryTimeoutSeconds: expiryDelay,
            queueId: queueId,
            queueStageId: queueStageId
        )
        session.save()

        AppLog.info("[CookMode] ✅ Background notifications scheduled deterministically (\(remaining.count) steps, total \(Int(cumulativeDelay))s)")

        // Complete the background transition
        isSchedulingBackground = false
        didContinueInBackground = true

        // Disconnect voice — notifications take over
        stopConversation()
    }

    /// End the cooking session — clears notifications and persisted session.
    /// This is the ONLY way to fully stop background mode.
    func endCookingSession() {
        isEndingSession = true
        NotificationService.shared.cancelAllNotifications(recipeId: recipe.id.uuidString)
        CookingSession.clear(recipeId: recipe.id)
        didContinueInBackground = false
        cleanup()
    }

    // MARK: - Cleanup

    func cleanup() {
        stopTimer()
        stopConversation()
    }
}
