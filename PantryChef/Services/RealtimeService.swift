import AVFoundation
import Foundation

// MARK: - Realtime API Service
//
// Connects to OpenAI's Realtime API via WebSocket for live voice-to-voice
// conversation during cook mode.  Streams microphone PCM16-24kHz audio to
// the API and plays back the model's audio responses through the speaker.
//
// The model is given full recipe context and function-calling tools for
// step navigation, timers, and finishing — so the user can say things like
// "what does dice mean?", "go to step 3", "start a 5 minute timer", etc.

@Observable
@MainActor
final class RealtimeService: NSObject {

    // MARK: - Public state (observed by SwiftUI)

    var isConnected = false
    var isModelSpeaking = false
    var isUserSpeaking = false
    var transcript = ""          // rolling text of what the model is saying
    var userTranscript = ""      // rolling text of what the user said
    var statusMessage = ""       // e.g. "Connecting…", "Listening…"
    var errorMessage: String?

    // MARK: - Callbacks (set by CookModeViewModel)

    var onFunctionCall: ((String, [String: Any]) -> Void)?

    // MARK: - Private

    private let apiKey: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var playerNode: AVAudioPlayerNode?
    @ObservationIgnored private var audioConverter: AVAudioConverter?
    @ObservationIgnored private var isCapturing = false

    // Audio format: PCM 16-bit signed integer, mono, 24 kHz  (Realtime API native format)
    @ObservationIgnored private let realtimeSampleRate: Double = 24_000
    @ObservationIgnored private let realtimeChannels: AVAudioChannelCount = 1

    /// Accumulates audio chunks so we can schedule larger buffers to avoid pops.
    @ObservationIgnored private var pendingAudioData = Data()
    @ObservationIgnored private var audioPlaybackTimer: Timer?

    /// Tracks ongoing response so we know when the model stops speaking.
    @ObservationIgnored private var activeResponseId: String?

    // MARK: - Init

    init(apiKey: String = AppConfig.openAIAPIKey) {
        self.apiKey = apiKey
        super.init()
    }

    // MARK: - Connect

    func connect(withInstructions instructions: String, tools: [[String: Any]]) {
        guard !isConnected else { return }
        statusMessage = "Connecting…"

        let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        urlSession = URLSession(configuration: config)
        webSocketTask = urlSession!.webSocketTask(with: request)
        webSocketTask?.resume()

        isConnected = true
        statusMessage = "Connected"

        // Start the receive loop
        receiveLoop()

        // Configure the session
        sendSessionUpdate(instructions: instructions, tools: tools)
    }

    // MARK: - Disconnect

    func disconnect() {
        stopCapture()
        stopPlayback()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        isModelSpeaking = false
        isUserSpeaking = false
        statusMessage = ""
        activeResponseId = nil
    }

    // MARK: - Session Configuration

    private func sendSessionUpdate(instructions: String, tools: [[String: Any]]) {
        let session: [String: Any] = [
            "modalities": ["text", "audio"],
            "instructions": instructions,
            "voice": "sage",
            "input_audio_format": "pcm16",
            "output_audio_format": "pcm16",
            "input_audio_transcription": [
                "model": "gpt-4o-mini-transcription"
            ],
            "turn_detection": [
                "type": "server_vad",
                "threshold": 0.5,
                "prefix_padding_ms": 300,
                "silence_duration_ms": 700
            ],
            "tools": tools,
            "tool_choice": "auto",
            "temperature": 0.7
        ]

        let event: [String: Any] = [
            "type": "session.update",
            "session": session
        ]

        sendJSON(event)
    }

    // MARK: - Audio Capture (Microphone → API)

    func startCapture() {
        guard !isCapturing else { return }

        configureAudioSession()

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Guard against Simulator with no mic
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            statusMessage = "No microphone available"
            return
        }

        // Target format: PCM16, mono, 24kHz
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: realtimeSampleRate,
            channels: realtimeChannels,
            interleaved: true
        ) else { return }

        // We'll need a converter if the mic format differs from our target
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        self.audioConverter = converter

        inputNode.installTap(onBus: 0, bufferSize: 2400, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in
                self.processAndSendAudio(buffer: buffer, converter: converter, targetFormat: targetFormat)
            }
        }

        engine.prepare()
        do {
            try engine.start()
            isCapturing = true
            statusMessage = "Listening…"
        } catch {
            print("RealtimeService: audio engine start error: \(error)")
            statusMessage = "Mic error"
        }
    }

    func stopCapture() {
        if audioEngine?.isRunning == true {
            audioEngine?.stop()
        }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        audioConverter = nil
        isCapturing = false
    }

    private func processAndSendAudio(buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, targetFormat: AVAudioFormat) {
        guard isConnected else { return }

        let pcmData: Data

        if let converter {
            // Convert from mic format to PCM16 24kHz mono
            let ratio = realtimeSampleRate / buffer.format.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

            var error: NSError?
            var consumedAll = false
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if consumedAll {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumedAll = true
                outStatus.pointee = .haveData
                return buffer
            }

            if error != nil { return }

            guard let int16Ptr = outputBuffer.int16ChannelData else { return }
            pcmData = Data(bytes: int16Ptr[0], count: Int(outputBuffer.frameLength) * 2)
        } else {
            // Already in the right format
            guard let int16Ptr = buffer.int16ChannelData else { return }
            pcmData = Data(bytes: int16Ptr[0], count: Int(buffer.frameLength) * 2)
        }

        guard !pcmData.isEmpty else { return }

        let base64 = pcmData.base64EncodedString()
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64
        ]
        sendJSON(event)
    }

    // MARK: - Audio Playback (API → Speaker)

    private func setupPlaybackIfNeeded() {
        guard playerNode == nil else { return }

        // Use a separate engine for playback (mic engine may be running)
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: realtimeSampleRate,
            channels: realtimeChannels,
            interleaved: true
        )!

        let node = AVAudioPlayerNode()
        self.playerNode = node

        // We reuse the capture engine if it exists, otherwise create one
        if audioEngine == nil {
            audioEngine = AVAudioEngine()
        }

        let engine = audioEngine!
        if !engine.attachedNodes.contains(node) {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: outputFormat)
        }

        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }

        node.play()
    }

    private func enqueueAudio(_ base64: String) {
        guard let data = Data(base64Encoded: base64) else { return }
        pendingAudioData.append(data)

        // Schedule playback chunks every ~100ms worth of audio
        let chunkThreshold = Int(realtimeSampleRate * 0.1) * 2  // 2 bytes per sample
        if pendingAudioData.count >= chunkThreshold {
            flushPendingAudio()
        }
    }

    private func flushPendingAudio() {
        guard !pendingAudioData.isEmpty else { return }

        let data = pendingAudioData
        pendingAudioData = Data()

        setupPlaybackIfNeeded()

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: realtimeSampleRate,
            channels: realtimeChannels,
            interleaved: true
        ) else { return }

        let frameCount = AVAudioFrameCount(data.count / 2)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        data.withUnsafeBytes { rawBuf in
            if let src = rawBuf.baseAddress {
                memcpy(pcmBuffer.int16ChannelData![0], src, data.count)
            }
        }

        playerNode?.scheduleBuffer(pcmBuffer, completionHandler: nil)
    }

    private func stopPlayback() {
        audioPlaybackTimer?.invalidate()
        audioPlaybackTimer = nil
        playerNode?.stop()
        playerNode = nil
        pendingAudioData = Data()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredSampleRate(realtimeSampleRate)
            try session.setActive(true)
        } catch {
            print("RealtimeService: audio session error: \(error)")
        }
    }

    // MARK: - WebSocket Send

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(str)) { error in
            if let error {
                print("RealtimeService send error: \(error)")
            }
        }
    }

    // MARK: - WebSocket Receive Loop

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleServerEvent(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleServerEvent(text)
                        }
                    @unknown default:
                        break
                    }
                    // Continue listening
                    self.receiveLoop()

                case .failure(let error):
                    print("RealtimeService receive error: \(error)")
                    self.isConnected = false
                    self.statusMessage = "Disconnected"
                    self.errorMessage = "Voice connection lost. Tap mic to reconnect."
                }
            }
        }
    }

    // MARK: - Server Event Handling

    private func handleServerEvent(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "session.created", "session.updated":
            statusMessage = "Ready — talk to me!"

        case "input_audio_buffer.speech_started":
            isUserSpeaking = true
            userTranscript = ""
            // Interrupt model if it's speaking
            if isModelSpeaking {
                cancelCurrentResponse()
            }

        case "input_audio_buffer.speech_stopped":
            isUserSpeaking = false

        case "conversation.item.input_audio_transcription.completed":
            if let transcriptText = json["transcript"] as? String {
                userTranscript = transcriptText
            }

        case "response.created":
            if let response = json["response"] as? [String: Any],
               let responseId = response["id"] as? String {
                activeResponseId = responseId
            }

        case "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                transcript += delta
                isModelSpeaking = true
            }

        case "response.audio.delta":
            if let delta = json["delta"] as? String {
                isModelSpeaking = true
                enqueueAudio(delta)
            }

        case "response.audio_transcript.done":
            // Full transcript complete
            break

        case "response.audio.done":
            // Flush any remaining audio
            flushPendingAudio()

        case "response.output_item.done":
            // Check if this is a function call
            if let item = json["item"] as? [String: Any],
               item["type"] as? String == "function_call",
               let name = item["name"] as? String,
               let argsString = item["arguments"] as? String,
               let callId = item["call_id"] as? String {
                handleFunctionCall(name: name, argumentsJSON: argsString, callId: callId)
            }

        case "response.done":
            isModelSpeaking = false
            transcript = ""
            activeResponseId = nil
            statusMessage = "Listening…"

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("RealtimeService API error: \(message)")
                errorMessage = message
            }

        default:
            break
        }
    }

    // MARK: - Function Calling

    private func handleFunctionCall(name: String, argumentsJSON: String, callId: String) {
        let args: [String: Any]
        if let data = argumentsJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            args = parsed
        } else {
            args = [:]
        }

        // Execute the function via callback
        onFunctionCall?(name, args)

        // Send function output back
        sendFunctionOutput(callId: callId, output: "{\"status\":\"done\"}")
    }

    func sendFunctionOutput(callId: String, output: String) {
        let item: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": output
            ]
        ]
        sendJSON(item)

        // Trigger a response after function output
        let response: [String: Any] = [
            "type": "response.create"
        ]
        sendJSON(response)
    }

    // MARK: - Interrupt Model

    private func cancelCurrentResponse() {
        // Truncate the model's response so it stops talking
        let cancel: [String: Any] = ["type": "response.cancel"]
        sendJSON(cancel)

        // Stop audio playback immediately
        playerNode?.stop()
        pendingAudioData = Data()
        isModelSpeaking = false
        transcript = ""
    }

    // MARK: - Send User Text (fallback / initial greeting)

    func sendUserMessage(_ text: String) {
        let event: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": text]
                ]
            ]
        ]
        sendJSON(event)

        let response: [String: Any] = ["type": "response.create"]
        sendJSON(response)
    }
}
