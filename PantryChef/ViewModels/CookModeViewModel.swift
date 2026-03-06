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
    var userTranscript = ""           // what the user said
    var isModelSpeaking = false
    var isUserSpeaking = false
    var conversationStatus = ""
    var conversationError: String?
    /// Whether the mic is muted (user can still hear the AI)
    var isMicMuted = false

    let recipe: Recipe
    let realtimeService: any RealtimeServiceProtocol

    private var timerCancellable: AnyCancellable?

    init(recipe: Recipe, realtimeService: any RealtimeServiceProtocol) {
        self.recipe = recipe
        self.realtimeService = realtimeService
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
        autoStartTimerIfNeeded()
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

    // MARK: - Mic Mute

    func toggleMicMute() {
        isMicMuted.toggle()
        if isMicMuted {
            realtimeService.stopCapture()
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

            isConversationActive = true
            isPreparing = true
            voiceAuthorizationDenied = false
            conversationStatus = "Setting up audio…"

            // Prepare audio first — VPIO enable is slow (5-15s).
            // This awaits off the main thread so the UI stays responsive.
            print("[CookMode] Preparing audio engine…")
            await realtimeService.prepareAudio()
            print("[CookMode] Audio engine ready, isRunning=\(realtimeService.isAudioReady)")

            // Connect WebSocket (audio engine is ready for playback now)
            let instructions = buildConversationInstructions()
            let tools = buildConversationTools()
            realtimeService.connect(withInstructions: instructions, tools: tools)
            print("[CookMode] WebSocket connected=\(realtimeService.isConnected)")

            // Now it's safe for the sync timer to check connection state
            isPreparing = false

            // Start mic capture (installs tap — engine is already running)
            realtimeService.startCapture()
            print("[CookMode] Mic capture started")

            // Greet the user by triggering a response with the current step context
            let greeting = "The user just started cooking \(recipe.title). "
                + "Greet them warmly and briefly read step \(currentStepIndex + 1): "
                + "\(currentStep?.instruction ?? ""). Keep it concise."
            realtimeService.sendUserMessage(greeting)
            print("[CookMode] Greeting sent")
        }
    }

    func stopConversation() {
        isConversationActive = false
        realtimeService.disconnect()
        conversationTranscript = ""
        userTranscript = ""
        conversationStatus = ""
        conversationError = nil
        isModelSpeaking = false
        isUserSpeaking = false
        isMicMuted = false
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
        userTranscript = realtimeService.userTranscript
        isModelSpeaking = realtimeService.isModelSpeaking
        isUserSpeaking = realtimeService.isUserSpeaking
        conversationStatus = realtimeService.statusMessage
        conversationError = realtimeService.errorMessage

        // Don't check connection state while still preparing audio
        if !isPreparing && !realtimeService.isConnected && isConversationActive {
            // Connection dropped
            isConversationActive = false
        }
    }

    func handleRealtimeFunctionCall(name: String, args: [String: Any]) {
        switch name {
        case "next_step":
            nextStep()
        case "previous_step":
            previousStep()
        case "go_to_step":
            if let step = args["step_number"] as? Int {
                goToStep(step - 1) // API uses 1-based, we use 0-based
            }
        case "repeat_step":
            // No navigation needed — the model will re-read it
            break
        case "start_timer":
            if let minutes = args["minutes"] as? Int {
                timerSeconds = minutes * 60
                isTimerRunning = true
                isPaused = false
                startTimerTick()
            } else {
                startTimer()
            }
        case "pause_timer":
            pauseTimer()
        case "stop_timer":
            stopTimer()
        case "finish_cooking":
            showCompletionScreen = true
        default:
            break
        }
    }

    private func buildConversationInstructions() -> String {
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
        - After calling a navigation function, briefly acknowledge it (e.g. "Moving to step 3…") \
        then read the new step.
        - Keep responses SHORT — 1-3 sentences normally. Only elaborate when the user asks \
        a specific question.
        - If the user says they're done or finished, call finish_cooking.
        - You can be interrupted — that's fine, just respond to the new input.
        """
    }

    private func buildConversationTools() -> [[String: Any]] {
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
                "description": "The user has finished cooking. Show the completion screen.",
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

    // MARK: - Timer

    func startTimer() {
        guard let step = currentStep, let minutes = step.timerMinutes else { return }
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
                if self.timerSeconds > 0 {
                    self.timerSeconds -= 1
                } else {
                    self.timerComplete()
                }
            }
    }

    func stopTimer() {
        isTimerRunning = false
        isPaused = false
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func pauseTimer() {
        isPaused.toggle()
        if isPaused {
            timerCancellable?.cancel()
        } else {
            timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    if self.timerSeconds > 0 {
                        self.timerSeconds -= 1
                    } else {
                        self.timerComplete()
                    }
                }
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

    // MARK: - Cleanup

    func cleanup() {
        stopTimer()
        stopConversation()
    }
}
