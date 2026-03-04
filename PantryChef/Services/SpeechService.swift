import AVFoundation
import Speech

@Observable
@MainActor
final class SpeechService: SpeechServiceProtocol {
    // MARK: - Text-to-Speech
    private let synthesizer = AVSpeechSynthesizer()

    var isSpeaking = false
    var isListening = false
    var recognizedText = ""

    // MARK: - Speech Recognition
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

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
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
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
