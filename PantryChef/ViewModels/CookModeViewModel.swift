import SwiftUI
import Combine

@Observable
@MainActor
final class CookModeViewModel {
    var currentStepIndex = 0
    var isAudioEnabled = true
    var isVoiceControlEnabled = false
    var timerSeconds: Int = 0
    var isTimerRunning = false
    var isPaused = false
    var showCompletionScreen = false
    var selectedRating: Int? = nil
    var voiceAuthorizationDenied = false

    /// Conversational voice mode (Realtime API)
    var isConversationMode = false
    var conversationTranscript = ""   // what the AI is currently saying
    var userTranscript = ""           // what the user said
    var isModelSpeaking = false
    var isUserSpeaking = false
    var conversationStatus = ""
    var conversationError: String?

    let recipe: Recipe
    let speechService: SpeechService
    let realtimeService: RealtimeService

    private var timerCancellable: AnyCancellable?

    init(recipe: Recipe, speechService: SpeechService, realtimeService: RealtimeService) {
        self.recipe = recipe
        self.speechService = speechService
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
        speakCurrentStep()
        autoStartTimerIfNeeded()
    }

    func previousStep() {
        guard !isFirstStep else { return }
        stopTimer()
        currentStepIndex -= 1
        speakCurrentStep()
    }

    func goToStep(_ index: Int) {
        guard index >= 0 && index < steps.count else { return }
        stopTimer()
        currentStepIndex = index
        speakCurrentStep()
        autoStartTimerIfNeeded()
    }

    // MARK: - Audio

    func speakCurrentStep() {
        guard isAudioEnabled, let step = currentStep else { return }
        let stepText = "Step \(step.stepNumber). \(step.instruction)"
        if let tip = step.tip {
            speechService.speak(stepText + ". Tip: \(tip)")
        } else {
            speechService.speak(stepText)
        }
    }

    func toggleAudio() {
        isAudioEnabled.toggle()
        if !isAudioEnabled {
            speechService.stop()
        }
    }

    // MARK: - Voice Control (legacy keyword-based — kept as fallback)

    func startVoiceControl() {
        Task {
            let speechAuthorized = await speechService.requestSpeechAuthorization()
            let micAuthorized = await speechService.requestMicrophoneAuthorization()

            guard speechAuthorized && micAuthorized else {
                voiceAuthorizationDenied = true
                return
            }

            isVoiceControlEnabled = true
            voiceAuthorizationDenied = false
            speechService.startListening { [weak self] text in
                Task { @MainActor in
                    self?.handleVoiceCommand(text)
                }
            }
        }
    }

    func stopVoiceControl() {
        isVoiceControlEnabled = false
        speechService.stopListening()
    }

    private func handleVoiceCommand(_ text: String) {
        let command = SpeechService.VoiceCommand.parse(text)
        switch command {
        case .next: nextStep()
        case .previous: previousStep()
        case .repeatStep: speakCurrentStep()
        case .startTimer: startTimer()
        case .pauseTimer: pauseTimer()
        case .stopTimer: stopTimer()
        case .unknown: break
        }
    }

    // MARK: - Conversational Voice Mode (OpenAI Realtime API)

    func startConversation() {
        Task {
            let micAuthorized = await speechService.requestMicrophoneAuthorization()
            guard micAuthorized else {
                voiceAuthorizationDenied = true
                return
            }

            // Stop any legacy voice / TTS
            stopVoiceControl()
            speechService.stop()

            isConversationMode = true
            voiceAuthorizationDenied = false

            let instructions = buildConversationInstructions()
            let tools = buildConversationTools()

            realtimeService.connect(withInstructions: instructions, tools: tools)
            realtimeService.startCapture()

            // Greet the user by triggering a response with the current step context
            let greeting = "The user just started cooking \(recipe.title). "
                + "Greet them warmly and briefly read step \(currentStepIndex + 1): "
                + "\(currentStep?.instruction ?? ""). Keep it concise."
            realtimeService.sendUserMessage(greeting)
        }
    }

    func stopConversation() {
        isConversationMode = false
        realtimeService.disconnect()
        conversationTranscript = ""
        userTranscript = ""
        conversationStatus = ""
        conversationError = nil
        isModelSpeaking = false
        isUserSpeaking = false
    }

    private func setupRealtimeCallbacks() {
        realtimeService.onFunctionCall = { [weak self] name, args in
            Task { @MainActor in
                self?.handleRealtimeFunctionCall(name: name, args: args)
            }
        }
    }

    /// Syncs observable state from RealtimeService — called by the view's onChange or timer.
    func syncRealtimeState() {
        guard isConversationMode else { return }
        conversationTranscript = realtimeService.transcript
        userTranscript = realtimeService.userTranscript
        isModelSpeaking = realtimeService.isModelSpeaking
        isUserSpeaking = realtimeService.isUserSpeaking
        conversationStatus = realtimeService.statusMessage
        conversationError = realtimeService.errorMessage

        if !realtimeService.isConnected && isConversationMode {
            // Connection dropped
            isConversationMode = false
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
        if isAudioEnabled {
            speechService.speak("Timer is done! Ready for the next step.")
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
        stopVoiceControl()
        stopConversation()
        speechService.stop()
    }
}
