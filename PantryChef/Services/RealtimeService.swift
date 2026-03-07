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
final class RealtimeService: NSObject, RealtimeServiceProtocol {

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
    @ObservationIgnored private var isAudioEnginePrepared = false

    /// Tracks how many scheduled audio buffers haven't finished playing yet.
    /// Used to know when the speaker is truly silent (not just when the API
    /// response stream ended).
    @ObservationIgnored private var pendingBuffersCount = 0

    /// Set when response.done arrives but audio is still playing through speaker.
    /// The actual isModelSpeaking=false transition happens when the last buffer
    /// finishes, so interruption and echo suppression work correctly.
    @ObservationIgnored private var responseStreamDone = false

    /// Whether the audio engine is running and ready for playback/capture.
    var isAudioReady: Bool { isAudioEngineRunning }

    // Audio format: PCM 16-bit signed integer, mono, 24 kHz  (Realtime API native format)
    @ObservationIgnored private let realtimeSampleRate: Double = 24_000
    @ObservationIgnored private let realtimeChannels: AVAudioChannelCount = 1

    /// Accumulates audio chunks so we can schedule larger buffers to avoid pops.
    @ObservationIgnored private var pendingAudioData = Data()

    /// Tracks ongoing response so we know when the model stops speaking.
    @ObservationIgnored var activeResponseId: String?

    /// Set during intentional disconnect to suppress spurious receive errors.
    @ObservationIgnored private var isDisconnecting = false
    @ObservationIgnored private var interruptionObserver: Any?
    @ObservationIgnored private var routeChangeObserver: Any?

    // MARK: - Init

    init(apiKey: String = AppConfig.openAIAPIKey) {
        self.apiKey = apiKey
        super.init()
    }

    // MARK: - Connect

    func connect(withInstructions instructions: String, tools: [[String: Any]]) {
        guard !isConnected else { return }
        isDisconnecting = false
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
        print("[RealtimeService] WebSocket connected")

        // Start the receive loop
        receiveLoop()

        // Configure the session
        sendSessionUpdate(instructions: instructions, tools: tools)
    }

    // MARK: - Disconnect

    func disconnect() {
        isDisconnecting = true
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
        // Note: isDisconnecting stays true — the async receive callback
        // hasn't fired yet.  It resets on the next connect().
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
                "threshold": NSDecimalNumber(string: "0.6"),
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

    /// Prepares the audio engine asynchronously.  VPIO (Voice Processing IO)
    /// can take 5-15 seconds on first call — this yields the main thread so
    /// the UI stays responsive.  Call this BEFORE connect() so audio is ready
    /// when the first API response arrives.
    func prepareAudio() async {
        print("[RealtimeService] prepareAudio() start")
        configureAudioSession()
        await setupAudioEngine()
        print("[RealtimeService] prepareAudio() done, engineRunning=\(isAudioEngineRunning)")
    }

    /// Installs the mic tap, starts the audio engine, and begins streaming
    /// audio to the API.  The engine is started AFTER the tap is installed
    /// so that VPIO's audio graph is fully wired before any processing.
    /// Call prepareAudio() first to create the engine and enable VPIO.
    func startCapture() {
        guard !isCapturing, isAudioEnginePrepared, let engine = audioEngine else {
            print("[Audio][Mic] startCapture() guard failed: isCapturing=\(isCapturing), prepared=\(isAudioEnginePrepared), hasEngine=\(audioEngine != nil)")
            return
        }

        let inputNode = engine.inputNode
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

        guard let capConverter = AVAudioConverter(from: vpioFormat, to: captureTarget) else {
            print("[Audio][Mic] ❌ failed to create capture converter: vpioFormat=\(vpioFormat)")
            return
        }
        self.captureConverter = capConverter
        let apiRate = realtimeSampleRate
        print("[Audio][Mic] Installing tap BEFORE engine start: vpioFormat=\(vpioFormat.sampleRate)Hz/\(vpioFormat.channelCount)ch, target=\(apiRate)Hz")

        // ── CRITICAL: Convert audio synchronously in the tap callback ──
        // The tap's AVAudioPCMBuffer is only valid during the callback.
        // Dispatching the buffer to another thread causes use-after-recycle.
        // We convert to PCM16 Data here (audio thread), then dispatch the
        // safe Data value to @MainActor for WebSocket transmission.
        micChunksSent = 0
        micBytesSent = 0

        // Use a class wrapper so the closure can mutate the count from the audio thread
        final class TapCounter: @unchecked Sendable { var count = 0 }
        let tapCounter = TapCounter()

        // Pass nil for format – lets Core Audio choose the VPIO output format,
        // avoiding a potential format mismatch that silences the tap.
        inputNode.installTap(onBus: 0, bufferSize: 2400, format: nil) { [weak self] buffer, _ in
            guard self != nil else { return }
            tapCounter.count += 1
            let n = tapCounter.count
            if n <= 5 || n % 100 == 0 {
                print("[Audio][Mic] tap callback #\(n): \(buffer.frameLength) frames, format=\(buffer.format.sampleRate)Hz/\(buffer.format.channelCount)ch")
            }

            let pcmData: Data
            let ratio = apiRate / buffer.format.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: captureTarget, frameCapacity: outputFrameCount) else { return }

            var error: NSError?
            var consumedAll = false
            capConverter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if consumedAll {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumedAll = true
                outStatus.pointee = .haveData
                return buffer
            }

            if error != nil {
                if n <= 3 { print("[Audio][Mic] ❌ converter error: \(error!)" ) }
                return
            }
            guard let int16Ptr = outputBuffer.int16ChannelData else { return }
            pcmData = Data(bytes: int16Ptr[0], count: Int(outputBuffer.frameLength) * 2)
            guard !pcmData.isEmpty else { return }

            Task { @MainActor [weak self] in
                self?.sendCapturedPCM(pcmData)
            }
        }
        print("[Audio][Mic] Tap installed (format: nil / auto)")

        // ── Start the engine NOW — tap is wired, audio graph is complete ──
        do {
            try engine.start()
            playerNode?.play()
            isAudioEngineRunning = true
            isCapturing = true
            statusMessage = "Listening…"
            print("[Audio] Engine started AFTER tap: engine.isRunning=\(engine.isRunning), playerNode.isPlaying=\(playerNode?.isPlaying ?? false)")

            let route = AVAudioSession.sharedInstance().currentRoute
            let outputs = route.outputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ", ")
            print("[Audio] Final audio route: [\(outputs)]")
        } catch {
            print("[Audio] ❌ engine start (in startCapture) failed: \(error)")
            statusMessage = "Mic error"
        }
    }

    /// Removes the mic tap (engine keeps running for playback).
    func stopCapture() {
        guard isCapturing, let engine = audioEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        isCapturing = false
    }

    // MARK: - Audio Engine Setup

    /// One-time engine creation: enables VPIO (async because it's slow),
    /// attaches the player node, and starts the engine.  Mic tap is
    /// installed separately by startCapture().
    private func setupAudioEngine() async {
        guard audioEngine == nil else { return }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        // ── 1.  Enable Voice Processing IO for hardware AEC ──
        //        This call can block for 5-15 seconds.  Yield the main thread.
        let inputNode = engine.inputNode
        print("[Audio] VPIO: enabling (this may take 5-15s)...")
        let vpioStart = CFAbsoluteTimeGetCurrent()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try inputNode.setVoiceProcessingEnabled(true)
                    let elapsed = CFAbsoluteTimeGetCurrent() - vpioStart
                    print("[Audio] VPIO: enabled in \(String(format: "%.1f", elapsed))s")
                } catch {
                    print("[Audio] ❌ VPIO enable FAILED: \(error)")
                }
                cont.resume()
            }
        }
        print("[Audio] VPIO: isVoiceProcessingEnabled=\(inputNode.isVoiceProcessingEnabled)")

        // ── 2.  Re-apply audio session AFTER VPIO but BEFORE engine.start() ──
        // VPIO changes the audio unit graph and may reset the output route.
        // We must re-apply BEFORE starting the engine — doing it after
        // engine.start() causes the system to stop the engine.
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
            let postRoute = AVAudioSession.sharedInstance().currentRoute
            let postOutputs = postRoute.outputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ", ")
            print("[Audio] Post-VPIO session re-applied (before engine start). Route outputs: [\(postOutputs)]")
        } catch {
            print("[Audio] ❌ Post-VPIO session re-apply failed: \(error)")
        }

        // ── 3.  Attach player node at the mixer's native rate ──
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let mixerRate = mixerFormat.sampleRate > 0 ? mixerFormat.sampleRate : 48_000

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
        node.volume = 1.5
        self.playerNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: playerFormat)
        engine.mainMixerNode.outputVolume = 1.0
        print("[Audio] Player node attached: volume=\(node.volume), mixerOutputVol=\(engine.mainMixerNode.outputVolume), playerFormat=\(playerFormat)")

        // Build a converter: API Float32 24 kHz → player Float32 at mixer rate
        guard let apiFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: realtimeSampleRate,
            channels: realtimeChannels,
            interleaved: false
        ) else { return }

        if mixerRate != realtimeSampleRate {
            self.playbackConverter = AVAudioConverter(from: apiFormat, to: playerFormat)
        }

        // ── 4.  Prepare (but do NOT start) the engine ──
        // The engine must be started AFTER the mic tap is installed so
        // VPIO's audio graph is complete.  engine.start() happens in
        // startCapture().
        engine.prepare()
        isAudioEnginePrepared = true
        print("[Audio] Engine prepared (not started yet). mixerRate=\(mixerRate)")

        // ── 5.  Observe audio session interruptions / route changes ──
        observeAudioSession()
    }

    // MARK: - Tear Down

    private func tearDownAudioEngine() {
        print("[Audio] tearDownAudioEngine called")
        // Remove notification observers
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
            interruptionObserver = nil
        }
        if let obs = routeChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            routeChangeObserver = nil
        }

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
        isAudioEnginePrepared = false
    }

    // MARK: - Mic → API

    /// Sends pre-converted PCM16 audio data to the Realtime API.
    /// Called from the tap callback's Task after synchronous conversion.
    @ObservationIgnored private var micChunksSent = 0
    @ObservationIgnored private var micBytesSent = 0
    private func sendCapturedPCM(_ pcmData: Data) {
        guard isConnected else { return }
        micChunksSent += 1
        micBytesSent += pcmData.count
        if micChunksSent <= 3 || micChunksSent % 50 == 0 {
            print("[Audio][Mic→API] chunk #\(micChunksSent): \(pcmData.count) bytes, totalSent=\(micBytesSent) bytes")
        }
        let base64 = pcmData.base64EncodedString()
        sendJSON([
            "type": "input_audio_buffer.append",
            "audio": base64
        ])
    }

    // MARK: - API → Speaker

    @ObservationIgnored private var playbackChunksReceived = 0
    @ObservationIgnored private var playbackBytesReceived = 0
    @ObservationIgnored private var playbackBuffersScheduled = 0
    private func enqueueAudio(_ base64: String) {
        guard let data = AudioPipelineHelper.base64ToPCM16(base64) else {
            print("[Audio][API→Spk] ❌ base64 decode failed, len=\(base64.count) chars")
            return
        }
        playbackChunksReceived += 1
        playbackBytesReceived += data.count
        pendingAudioData.append(data)

        if playbackChunksReceived <= 3 {
            print("[Audio][API→Spk] chunk #\(playbackChunksReceived): \(data.count) bytes, pending=\(pendingAudioData.count), totalRecv=\(playbackBytesReceived)")
        }

        // Schedule playback chunks every ~100ms worth of audio
        let chunkThreshold = AudioPipelineHelper.chunkThreshold(sampleRate: realtimeSampleRate)
        if pendingAudioData.count >= chunkThreshold {
            flushPendingAudio()
        }
    }

    private func flushPendingAudio() {
        guard !pendingAudioData.isEmpty else { return }

        let data = pendingAudioData
        pendingAudioData = Data()

        guard let playerNode, isAudioEngineRunning else {
            print("[Audio][API→Spk] ❌ flush skipped — playerNode=\(self.playerNode != nil), engineRunning=\(isAudioEngineRunning), dataSize=\(data.count)")
            return
        }

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

        // Int16 → Float32 (uses the same math tested in AudioPipelineHelper)
        guard let floatData = apiBuffer.floatChannelData else { return }
        AudioPipelineHelper.pcm16ToFloatBuffer(from: data, into: floatData[0], frameCount: Int(apiFrameCount))

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
                playbackBuffersScheduled += 1
                pendingBuffersCount += 1
                if playbackBuffersScheduled <= 3 || playbackBuffersScheduled % 20 == 0 {
                    print("[Audio][API→Spk] scheduleBuffer #\(playbackBuffersScheduled): \(outBuffer.frameLength) frames at \(converter.outputFormat.sampleRate)Hz, isPlaying=\(playerNode.isPlaying), pending=\(pendingBuffersCount)")
                }
                playerNode.scheduleBuffer(outBuffer) { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.bufferDidFinishPlaying()
                    }
                }
            } else {
                print("[Audio][API→Spk] ❌ resample failed: error=\(String(describing: error)), outFrames=\(outBuffer.frameLength)")
            }
        } else {
            playbackBuffersScheduled += 1
            pendingBuffersCount += 1
            if playbackBuffersScheduled <= 3 || playbackBuffersScheduled % 20 == 0 {
                print("[Audio][API→Spk] scheduleBuffer #\(playbackBuffersScheduled): \(apiBuffer.frameLength) frames (no resample), isPlaying=\(playerNode.isPlaying), pending=\(pendingBuffersCount)")
            }
            playerNode.scheduleBuffer(apiBuffer) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.bufferDidFinishPlaying()
                }
            }
        }
    }

    // MARK: - Playback Completion

    /// Called on @MainActor when each scheduled buffer finishes playing.
    private func bufferDidFinishPlaying() {
        pendingBuffersCount = max(0, pendingBuffersCount - 1)
        if pendingBuffersCount == 0, responseStreamDone {
            print("[Audio] Last buffer finished playing — finalizing playback")
            finalizePlayback()
        }
    }

    /// Transitions from "model speaking" to "listening" once audio is truly done.
    private func finalizePlayback() {
        print("[Audio] finalizePlayback: isModelSpeaking=false, clearing activeResponseId")
        isModelSpeaking = false
        activeResponseId = nil
        responseStreamDone = false
        transcript = ""

        // Flush the API’s input audio buffer to discard any residual echo
        // that leaked through VPIO while the model was speaking.  Without
        // this, the API’s VAD triggers on the echo and the model hears itself.
        print("[Audio] Sending input_audio_buffer.clear to flush echo")
        sendJSON(["type": "input_audio_buffer.clear"])
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            try session.overrideOutputAudioPort(.speaker)
            let route = session.currentRoute
            let outputs = route.outputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ", ")
            let inputs = route.inputs.map { "\($0.portName)(\($0.portType.rawValue))" }.joined(separator: ", ")
            print("[Audio] Session configured: category=\(session.category.rawValue), mode=\(session.mode.rawValue)")
            print("[Audio] Route — outputs: [\(outputs)], inputs: [\(inputs)]")
            print("[Audio] Session sampleRate=\(session.sampleRate), ioBufferDuration=\(session.ioBufferDuration)")
        } catch {
            print("[Audio] ❌ Session config FAILED: \(error)")
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
                    // Intentional disconnect triggers a socket error — suppress it
                    guard !self.isDisconnecting, self.isConnected else { return }
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
            print("[WS] \(type)")
            statusMessage = "Ready — talk to me!"

        case "input_audio_buffer.speech_started":
            print("[WS] speech_started (modelSpeaking=\(isModelSpeaking), activeResp=\(activeResponseId ?? "nil"), pendingBuffers=\(pendingBuffersCount))")
            isUserSpeaking = true
            userTranscript = ""
            // Interrupt model if it's actively speaking OR audio is still playing
            if isModelSpeaking || pendingBuffersCount > 0, activeResponseId != nil {
                print("[WS] → interrupting model response \(activeResponseId!)")
                cancelCurrentResponse()
            }

        case "input_audio_buffer.speech_stopped":
            print("[WS] speech_stopped")
            isUserSpeaking = false

        case "conversation.item.input_audio_transcription.completed":
            if let transcriptText = json["transcript"] as? String {
                print("[WS] user transcription: \"\(transcriptText.prefix(80))\"")
                userTranscript = transcriptText
            }

        case "response.created":
            if let response = json["response"] as? [String: Any],
               let responseId = response["id"] as? String {
                print("[WS] response.created id=\(responseId)")
                activeResponseId = responseId
                // Reset playback counters for this response
                playbackChunksReceived = 0
                playbackBytesReceived = 0
                playbackBuffersScheduled = 0
            }

        case "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                transcript += delta
                isModelSpeaking = true
                if transcript.count <= 30 {
                    print("[WS] audio_transcript.delta: \"\(transcript)\"")
                }
            }

        case "response.audio.delta":
            if let delta = json["delta"] as? String {
                isModelSpeaking = true
                if playbackChunksReceived == 0 {
                    print("[WS] FIRST response.audio.delta received (\(delta.count) base64 chars)")
                }
                enqueueAudio(delta)
            }

        case "response.audio_transcript.done":
            // Full transcript complete
            break

        case "response.audio.done":
            // Flush any remaining audio
            print("[WS] response.audio.done — flushing remaining \(pendingAudioData.count) bytes, totalChunks=\(playbackChunksReceived), totalBytes=\(playbackBytesReceived), scheduled=\(playbackBuffersScheduled)")
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
            print("[WS] response.done — totalAudioChunks=\(playbackChunksReceived), totalAudioBytes=\(playbackBytesReceived), buffersScheduled=\(playbackBuffersScheduled), pendingBuffers=\(pendingBuffersCount)")
            // Don't clear transcript here — audio is still playing through
            // the speaker.  transcript is cleared in finalizePlayback().
            statusMessage = "Listening…"
            // Don't clear isModelSpeaking / activeResponseId here!
            // Audio is still physically playing through the speaker.
            // Mark the stream as done; the last buffer completion handler
            // will finalize the transition.
            responseStreamDone = true
            if pendingBuffersCount <= 0 {
                // All buffers already played (or none were scheduled)
                finalizePlayback()
            }

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("RealtimeService API error: \(message)")
                // Don't surface benign / transient errors to the user
                let benignPatterns = [
                    "no active response",
                    "cancellation failed",
                    "already has an active response"
                ]
                let isBenign = benignPatterns.contains { message.lowercased().contains($0) }
                if !isBenign {
                    errorMessage = message
                }
            }

        default:
            print("[WS] unhandled event: \(type)")
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
        print("[Audio] cancelCurrentResponse — clearing \(pendingAudioData.count) pending bytes, pendingBuffers=\(pendingBuffersCount), resp=\(activeResponseId ?? "nil")")
        // Tell the API to stop generating
        let cancel: [String: Any] = ["type": "response.cancel"]
        sendJSON(cancel)

        // Stop audio playback immediately and clear pending data
        pendingAudioData = Data()
        pendingBuffersCount = 0
        responseStreamDone = false
        if let oldNode = playerNode, let engine = audioEngine {
            oldNode.stop()
            engine.detach(oldNode)

            // Create a fresh player node — AVAudioPlayerNode can't reliably
            // schedule new buffers after .stop() in some iOS versions.
            let newNode = AVAudioPlayerNode()
            newNode.volume = 1.5
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
        // Cancel any in-flight response before requesting a new one
        if activeResponseId != nil {
            cancelCurrentResponse()
        }

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

    // MARK: - Audio Session Observation

    private func observeAudioSession() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                self.handleInterruption(notification)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                self.handleRouteChange(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            print("[Audio] ⚠️ Interruption BEGAN (e.g. phone call)")
            break
        case .ended:
            print("[Audio] Interruption ENDED — restarting engine")
            // Restart audio engine after interruption
            if let engine = audioEngine, !engine.isRunning {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    try engine.start()
                    playerNode?.play()
                    print("[Audio] Engine restarted after interruption, playerNode.isPlaying=\(playerNode?.isPlaying ?? false)")
                } catch {
                    print("[Audio] ❌ restart after interruption failed: \(error)")
                }
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable:
            print("[Audio] Route change: \(reason.rawValue) — re-overriding to speaker")
            // Headphones unplugged / Bluetooth changed — re-override to speaker
            try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        default:
            print("[Audio] Route change reason=\(reason.rawValue) (no action)")
            break
        }
    }
}
