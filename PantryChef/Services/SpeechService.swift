import AVFoundation
import Speech

@Observable
@MainActor
final class SpeechService: NSObject, SpeechServiceProtocol, AVSpeechSynthesizerDelegate {
    // MARK: - Heavy AV objects — created on first use, NOT at init time
    //
    // We can't use `lazy var` because @Observable synthesises property wrappers
    // that are incompatible with lazy storage.  Instead we use optional backing
    // stores with private computed accessors that initialise-on-first-access.

    @ObservationIgnored private var _synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var _speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored private var _audioEngine: AVAudioEngine?

    private var synthesizer: AVSpeechSynthesizer {
        if _synthesizer == nil {
            let synth = AVSpeechSynthesizer()
            synth.delegate = self
            _synthesizer = synth
        }
        return _synthesizer!
    }

    private var speechRecognizer: SFSpeechRecognizer? {
        if _speechRecognizer == nil {
            _speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }
        return _speechRecognizer
    }

    private var audioEngine: AVAudioEngine {
        if _audioEngine == nil { _audioEngine = AVAudioEngine() }
        return _audioEngine!
    }

    var isSpeaking = false
    var isListening = false
    var recognizedText = ""

    /// Whether the user wants voice control active (independent of session state).
    @ObservationIgnored var wantsListening = false
    /// Stored callback for auto-restart after TTS or session timeout.
    @ObservationIgnored private var _onResult: ((String) -> Void)?
    /// Debounce timer — waits for speech to settle before dispatching a command.
    @ObservationIgnored private var commandDebounceTask: Task<Void, Never>?
    /// The last command string already dispatched (prevents duplicate actions from partial results).
    @ObservationIgnored private var lastDispatchedCommand = ""

    // MARK: - Speech Recognition
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - TTS Methods

    func speak(_ text: String, rate: Float = 0.48) {
        // Pause recognition while speaking to avoid feedback loop
        let wasListening = isListening
        if wasListening { stopListeningSession() }

        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.preUtteranceDelay = 0.2
        utterance.postUtteranceDelay = 0.3

        configureAudioSession(forRecording: false)
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            // Auto-restart listening if voice control is still desired
            if self.wantsListening, let callback = self._onResult {
                try? await Task.sleep(for: .milliseconds(300))
                guard self.wantsListening, !self.isListening else { return }
                self.beginListeningSession(onResult: callback)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    // MARK: - Audio Session

    private func configureAudioSession(forRecording: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if forRecording {
                try session.setCategory(.playAndRecord, mode: .default,
                                        options: [.defaultToSpeaker, .allowBluetoothHFP])
            } else {
                try session.setCategory(.playback, mode: .default)
            }
            try session.setActive(true)
        } catch {
            print("Audio session config error: \(error)")
        }
    }

    // MARK: - Speech Recognition Methods

    func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startListening(onResult: @escaping (String) -> Void) {
        _onResult = onResult
        wantsListening = true
        lastDispatchedCommand = ""
        beginListeningSession(onResult: onResult)
    }

    /// Internal: starts a single recognition session. Can be called repeatedly for auto-restart.
    private func beginListeningSession(onResult: @escaping (String) -> Void) {
        // Clean up any prior session
        stopListeningSession()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        configureAudioSession(forRecording: true)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true
        // Use on-device recognition when available for lower latency
        if recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Guard against invalid format (0 Hz sample rate on Simulator)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            print("SpeechService: audio input format invalid (sampleRate=\(recordingFormat.sampleRate)), cannot start listening")
            stopListeningSession()
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    guard let self else { return }
                    self.recognizedText = text
                    // Debounce: wait for speech to settle before dispatching command
                    self.commandDebounceTask?.cancel()
                    self.commandDebounceTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(600))
                        guard !Task.isCancelled else { return }
                        // Only dispatch if this is a new command (not duplicate partial)
                        let parsed = VoiceCommand.parse(text)
                        if parsed != .unknown && text != self.lastDispatchedCommand {
                            self.lastDispatchedCommand = text
                            onResult(text)
                        }
                    }
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    guard let self else { return }
                    self.stopListeningSession()
                    // Auto-restart if user still wants voice control
                    if self.wantsListening, !self.isSpeaking {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard self.wantsListening, !self.isListening, !self.isSpeaking else { return }
                        self.beginListeningSession(onResult: onResult)
                    }
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("Audio engine start error: \(error)")
            stopListeningSession()
        }
    }

    /// Stops the current recognition session without clearing `wantsListening`.
    private func stopListeningSession() {
        commandDebounceTask?.cancel()
        commandDebounceTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    func stopListening() {
        wantsListening = false
        _onResult = nil
        lastDispatchedCommand = ""
        stopListeningSession()
    }

    // MARK: - Cook Mode Voice Commands

    enum VoiceCommand: Equatable {
        case next
        case previous
        case repeatStep
        case startTimer
        case pauseTimer
        case stopTimer
        case unknown

        static func parse(_ text: String) -> VoiceCommand {
            let lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
            let lastWord = lowered.split(separator: " ").last.map(String.init) ?? lowered

            switch lastWord {
            case "next", "forward", "continue", "done":
                return .next
            case "back", "previous", "before":
                return .previous
            case "repeat", "again", "what":
                return .repeatStep
            case "timer", "start", "go":
                return .startTimer
            case "pause":
                return .pauseTimer
            case "stop", "cancel":
                return .stopTimer
            default:
                if lowered.contains("next") { return .next }
                if lowered.contains("back") || lowered.contains("previous") { return .previous }
                if lowered.contains("repeat") || lowered.contains("again") { return .repeatStep }
                if lowered.contains("start timer") || lowered.contains("set timer") { return .startTimer }
                if lowered.contains("pause") { return .pauseTimer }
                if lowered.contains("stop") || lowered.contains("cancel") { return .stopTimer }
                return .unknown
            }
        }
    }
}
