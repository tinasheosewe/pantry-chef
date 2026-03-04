import AVFoundation
import Speech

@Observable
@MainActor
final class SpeechService: SpeechServiceProtocol {
    // MARK: - Heavy AV objects — created on first use, NOT at init time
    //
    // We can't use `lazy var` because @Observable synthesises property wrappers
    // that are incompatible with lazy storage.  Instead we use optional backing
    // stores with private computed accessors that initialise-on-first-access.

    @ObservationIgnored private var _synthesizer: AVSpeechSynthesizer?
    @ObservationIgnored private var _speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored private var _audioEngine: AVAudioEngine?

    private var synthesizer: AVSpeechSynthesizer {
        if _synthesizer == nil { _synthesizer = AVSpeechSynthesizer() }
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

    // MARK: - Speech Recognition
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - TTS Methods

    func speak(_ text: String, rate: Float = 0.48) {
        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.preUtteranceDelay = 0.2
        utterance.postUtteranceDelay = 0.3

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

    // MARK: - Speech Recognition Methods

    func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startListening(onResult: @escaping (String) -> Void) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self?.recognizedText = text
                    onResult(text)
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in
                    self?.stopListening()
                }
            }
        }

        audioEngine.prepare()
        try? audioEngine.start()
        isListening = true
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }

    // MARK: - Cook Mode Voice Commands

    enum VoiceCommand {
        case next
        case previous
        case repeatStep
        case startTimer
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
            case "stop", "cancel", "pause":
                return .stopTimer
            default:
                if lowered.contains("next") { return .next }
                if lowered.contains("back") || lowered.contains("previous") { return .previous }
                if lowered.contains("repeat") || lowered.contains("again") { return .repeatStep }
                if lowered.contains("start timer") || lowered.contains("set timer") { return .startTimer }
                if lowered.contains("stop") || lowered.contains("cancel") { return .stopTimer }
                return .unknown
            }
        }
    }
}
