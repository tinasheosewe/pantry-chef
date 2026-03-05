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

    let recipe: Recipe
    let speechService: SpeechService

    private var timerCancellable: AnyCancellable?

    init(recipe: Recipe, speechService: SpeechService) {
        self.recipe = recipe
        self.speechService = speechService
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

    // MARK: - Voice Control

    func startVoiceControl() {
        Task {
            // Request both permissions before starting
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
        speechService.stop()
    }
}
