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

    /// Single audio engine for both capture and playback.
    /// VPIO (Voice Processing IO) on the input node enables hardware acoustic
    /// echo cancellation — the engine knows what's playing through the speaker
    /// and subtracts it from the mic signal.  This lets the user interrupt the
    /// model naturally while preventing the model from hearing its own output.
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var playerNode: AVAudioPlayerNode?
    @ObservationIgnored private var captureConverter: AVAudioConverter?
    @ObservationIgnored private var playbackConverter: AVAudioConverter?
    @ObservationIgnored private var isCapturing = false
    @ObservationIgnored private var isAudioEngineRunning = false

    // Audio format: PCM 16-bit signed integer, mono, 24 kHz  (Realtime API native format)
    @ObservationIgnored private let realtimeSampleRate: Double = 24_000
    @ObservationIgnored private let realtimeChannels: AVAudioChannelCount = 1

    /// Accumulates audio chunks so we can schedule larger buffers to avoid pops.
    @ObservationIgnored private var pendingAudioData = Data()

    /// Tracks ongoing response so we know when the model stops speaking.
    @ObservationIgnored var activeResponseId: String?

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
        tearDownAudioEngine()
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
                "model": "gpt-4o-mini-transcribe"
            ],
            "turn_detection": [
                "type": "server_vad",
                "threshold": 0.6,
                "prefix_padding_ms": 300,
                "silence_duration_ms": 800,
                "create_response": true
            ],
            "tools": tools,
            "tool_choice": "auto",
            "temperature": 0.75
        ]

        let event: [String: Any] = [
            "type": "session.update",
            "session": session
        ]

        sendJSON(event)
    }

    // MARK: - Unified Audio Engine (capture + playback + AEC)
    //
    // A single AVAudioEngine hosts both the mic input tap and the player node.
    // Enabling Voice Processing IO on the input node gives us Apple's hardware
    // Acoustic Echo Cancellation (AEC) — the engine subtracts what it's playing
    // from what the mic hears, so the model can't hear itself.  The user can
    // still interrupt normally because AEC passes through real human speech.
    //
    // The player node is connected at the mixer's native sample rate (typically
    // 48 kHz) to avoid CoreAudio format conflicts.  We resample:
    //   • Mic  → 24 kHz PCM16  (for the Realtime API)
    //   • API  → mixer rate Float32  (for the speaker)

    func startCapture() {
        guard !isCapturing else { return }

        configureAudioSession()
        setupAudioEngine()

        guard isAudioEngineRunning else { return }
        isCapturing = true
        statusMessage = "Listening…"
    }

    func stopCapture() {
        guard let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        isCapturing = false
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        guard audioEngine == nil else { return }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        // ── 1.  Enable Voice Processing IO for hardware AEC ──
        let inputNode = engine.inputNode
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            print("RealtimeService: VPIO enable failed: \(error)")
            // Fall back — AEC won't work but at least we can still talk
        }

        // ── 2.  Attach player node at the mixer's native rate ──
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let mixerRate = mixerFormat.sampleRate > 0 ? mixerFormat.sampleRate : 48_000

        // Player format: Float32, mono, at the mixer's native rate
        guard let playerFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: mixerRate,
            channels: realtimeChannels,
            interleaved: false
        ) else {
            statusMessage = "Audio format error"
            return
        }

        let node = AVAudioPlayerNode()
        self.playerNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: playerFormat)

        // Build a converter: API PCM16 24 kHz → player Float32 at mixer rate
        guard let apiFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: realtimeSampleRate,
            channels: realtimeChannels,
            interleaved: false
        ) else { return }

        if mixerRate != realtimeSampleRate {
            self.playbackConverter = AVAudioConverter(from: apiFormat, to: playerFormat)
        }

        // ── 3.  Install mic tap (post-VPIO = echo-cancelled audio) ──
        //        The VPIO input node's output format is whatever the hardware gives us
        //        (usually 48 kHz Float32 mono when VPIO is on).  We convert to 24 kHz PCM16.
        let vpioFormat = inputNode.outputFormat(forBus: 0)
        guard vpioFormat.sampleRate > 0, vpioFormat.channelCount > 0 else {
            statusMessage = "No microphone available"
            return
        }

        guard let captureTarget = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: realtimeSampleRate,
            channels: realtimeChannels,
            interleaved: true
        ) else { return }

        let capConverter = AVAudioConverter(from: vpioFormat, to: captureTarget)
        self.captureConverter = capConverter

        inputNode.installTap(onBus: 0, bufferSize: 2400, format: vpioFormat) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in
                self.processAndSendAudio(buffer: buffer, converter: capConverter, targetFormat: captureTarget)
            }
        }

        // ── 4.  Start the unified engine ──
        engine.prepare()
        do {
            try engine.start()
            isAudioEngineRunning = true
            node.play()
        } catch {
            print("RealtimeService: audio engine start error: \(error)")
            statusMessage = "Mic error"
        }
    }

    // MARK: - Tear Down

    private func tearDownAudioEngine() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            playerNode?.stop()
            if engine.isRunning {
                engine.stop()
            }
        }
        playerNode = nil
        audioEngine = nil
        captureConverter = nil
        playbackConverter = nil
        pendingAudioData = Data()
        isCapturing = false
        isAudioEngineRunning = false
    }

    // MARK: - Mic → API

    private func processAndSendAudio(buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, targetFormat: AVAudioFormat) {
        guard isConnected else { return }

        let pcmData: Data

        if let converter {
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

    // MARK: - API → Speaker

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

        // Ensure engine is set up (lazy setup for initial greeting before startCapture)
        setupAudioEngine()
        guard let playerNode, isAudioEngineRunning else { return }

        // Convert PCM16 24 kHz → Float32 at API rate first
        let apiFrameCount = AVAudioFrameCount(data.count / 2)
        guard apiFrameCount > 0 else { return }

        guard let apiFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: realtimeSampleRate,
            channels: realtimeChannels,
            interleaved: false
        ) else { return }

        guard let apiBuffer = AVAudioPCMBuffer(pcmFormat: apiFormat, frameCapacity: apiFrameCount) else { return }
        apiBuffer.frameLength = apiFrameCount

        // Int16 → Float32
        guard let floatData = apiBuffer.floatChannelData else { return }
        data.withUnsafeBytes { rawBuf in
            let int16Ptr = rawBuf.bindMemory(to: Int16.self)
            for i in 0..<Int(apiFrameCount) {
                floatData[0][i] = Float(int16Ptr[i]) / 32768.0
            }
        }

        // If mixer rate differs from 24 kHz, resample up to mixer rate
        if let converter = playbackConverter {
            let ratio = converter.outputFormat.sampleRate / realtimeSampleRate
            let outFrames = AVAudioFrameCount(Double(apiFrameCount) * ratio)
            guard let outBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat,
                frameCapacity: outFrames
            ) else { return }

            var error: NSError?
            var consumedAll = false
            converter.convert(to: outBuffer, error: &error) { _, outStatus in
                if consumedAll {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumedAll = true
                outStatus.pointee = .haveData
                return apiBuffer
            }

            if error == nil, outBuffer.frameLength > 0 {
                playerNode.scheduleBuffer(outBuffer, completionHandler: nil)
            }
        } else {
            // Already at mixer rate
            playerNode.scheduleBuffer(apiBuffer, completionHandler: nil)
        }
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .voiceChat mode enables system-level echo cancellation as well.
            // .defaultToSpeaker routes to the loudspeaker for hands-free cooking.
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth])
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

    func handleServerEvent(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "session.created", "session.updated":
            statusMessage = "Ready — talk to me!"

        case "input_audio_buffer.speech_started":
            isUserSpeaking = true
            userTranscript = ""
            // Interrupt model if it's actively speaking AND there's a response to cancel
            if isModelSpeaking, activeResponseId != nil {
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
                // Don't surface benign cancellation errors to the user
                let benignPatterns = ["no active response", "cancellation failed"]
                let isBenign = benignPatterns.contains { message.lowercased().contains($0) }
                if !isBenign {
                    errorMessage = message
                }
            }

        default:
            break
        }
    }

    // MARK: - Function Calling

    func handleFunctionCall(name: String, argumentsJSON: String, callId: String) {
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
        // Tell the API to stop generating
        let cancel: [String: Any] = ["type": "response.cancel"]
        sendJSON(cancel)

        // Stop audio playback immediately and clear pending data
        pendingAudioData = Data()
        if let oldNode = playerNode, let engine = audioEngine {
            oldNode.stop()
            engine.detach(oldNode)

            // Create a fresh player node — AVAudioPlayerNode can't reliably
            // schedule new buffers after .stop() in some iOS versions.
            let newNode = AVAudioPlayerNode()
            self.playerNode = newNode
            let mixerRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
            let rate = mixerRate > 0 ? mixerRate : 48_000
            if let fmt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: rate,
                channels: realtimeChannels,
                interleaved: false
            ) {
                engine.attach(newNode)
                engine.connect(newNode, to: engine.mainMixerNode, format: fmt)
                newNode.play()
            }
        }

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
