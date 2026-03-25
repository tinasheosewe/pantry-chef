import AVFoundation
import Foundation
import RealtimeAPI

// MARK: - Realtime API Service (SDK-backed)
//
// Wraps the swift-realtime-openai SDK's Conversation class to provide
// voice-to-voice conversation with OpenAI's Realtime API during cook mode.
//
// The SDK handles all audio pipeline concerns internally via WebRTC:
//   • Microphone capture with hardware echo cancellation
//   • Audio playback through the speaker
//   • Interruption handling (user can speak over the model)
//   • PCM encoding/decoding and streaming
//
// This service is a thin adapter between the SDK and our
// RealtimeServiceProtocol, which CookModeViewModel depends on.

@Observable
@MainActor
final class RealtimeService: RealtimeServiceProtocol {

    private enum AudioTuning {
        static let inputNoiseReduction: Session.Audio.Input.NoiseReduction = .farField
        static let vadSilenceDurationMs = 1000
        static let vadThreshold = 0.88
    }

    // MARK: - Public state (observed by CookModeViewModel)

    var isConnected = false
    var isModelSpeaking = false
    var isUserSpeaking = false
    var transcript = ""          // rolling text of what the model is saying
    var statusMessage = ""       // e.g. "Connecting…", "Listening…"
    var errorMessage: String?

    // MARK: - Callbacks (set by CookModeViewModel)

    var onFunctionCall: ((String, [String: Any]) -> Void)?

    // MARK: - Computed

    /// Audio is ready once the SDK's WebRTC connection is established.
    var isAudioReady: Bool { conversation?.status == .connected }

    // MARK: - Private

    private let apiKey: String
    private let urlSession: URLSession
    private var conversation: Conversation?

    /// Ephemeral key fetched from OpenAI REST API for WebRTC auth.
    @ObservationIgnored private var ephemeralKey: String?

    /// Message queued before connection is ready — sent once connected.
    @ObservationIgnored private var pendingMessage: String?

    /// Tracks function call IDs already dispatched to avoid double-firing.
    @ObservationIgnored private var processedFunctionCallIds = Set<String>()

    /// Tracks user message item IDs already checked for garbage transcription.
    @ObservationIgnored private var processedUserTranscriptIds = Set<String>()

    /// Background tasks for state sync and error listening.
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var errorTask: Task<Void, Never>?
    @ObservationIgnored private var currentAssistantMessageId: String?
    @ObservationIgnored private var previousSDKUserSpeaking = false
    @ObservationIgnored private var userMessageCountAtSpeechStart = 0
    @ObservationIgnored private var lastLoggedStateSignature = ""

    // MARK: - Init

    init(apiKey: String = AppConfig.openAIAPIKey, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    // MARK: - Prepare Audio

    /// Fetches an ephemeral key from OpenAI for WebRTC connection.
    /// Also pre-configures the audio session so WebRTC can create audio tracks.
    func prepareAudio() async {
        statusMessage = "Setting up…"

        // Configure the audio session for WebRTC BEFORE the SDK tries to
        // create a peer connection. Without this, the SDP offer won't
        // contain an audio media section and the server returns 400.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothA2DP]
            )
            try session.setActive(true)
            AppLog.debug("Audio session configured for WebRTC")
        } catch {
            AppLog.warn("Audio session setup warning: \(error.localizedDescription)")
        }

        do {
            ephemeralKey = try await fetchEphemeralKey()
            statusMessage = "Ready"
            AppLog.info("Ephemeral key obtained")
        } catch {
            errorMessage = "Audio setup failed: \(error.localizedDescription)"
            AppLog.error("Ephemeral key fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Connect

    func connect(withInstructions instructions: String, tools: [[String: Any]]) {
        guard let key = ephemeralKey else {
            errorMessage = "Audio not ready — no ephemeral key"
            return
        }

        // Tear down any previous session
        cleanUpConversation()

        let sdkTools = convertTools(tools)
        statusMessage = "Connecting…"

        // Create the SDK Conversation with session configuration.
        // The configuring callback fires when the server sends session.created,
        // so session preferences are applied at the right time.
        conversation = Conversation(debug: true) { session in
            session.instructions = instructions
            session.audio.output.voice = .sage
            session.audio.input.transcription = .init(model: .gpt4oMini)
            session.audio.input.noiseReduction = AudioTuning.inputNoiseReduction
            session.audio.input.turnDetection = .serverVad(
                createResponse: true,
                prefixPaddingMs: 500,
                silenceDurationMs: AudioTuning.vadSilenceDurationMs,
                threshold: AudioTuning.vadThreshold
            )
            session.tools = sdkTools
            session.toolChoice = .auto
            // Note: temperature and modalities are not supported by the GA API
            // session.update and will cause the entire update to be rejected.
        }

        // Connect asynchronously via WebRTC
        let realtimeModel = "gpt-4o-realtime-preview"
        Task { [weak self] in
            guard let self, let conv = self.conversation else { return }
            do {
                try await conv.connect(ephemeralKey: key, model: .custom(realtimeModel))
                AppLog.info("Connected via WebRTC")
                self.isConnected = true
                self.statusMessage = "Connected"

                // Wait for the session.update round-trip to complete before
                // sending any messages. The SDK fires `session.update` when it
                // receives `session.created`, but connect() returns as soon as
                // the WebRTC handshake is done — before that event arrives.
                // Without this wait, the greeting races ahead and the API
                // uses the default session config (wrong voice, Spanish, etc.).
                //
                // We detect completion by checking that the voice has changed
                // from the default (alloy) to our requested voice (sage).
                var waited = 0
                while conv.session?.audio.output.voice != .sage,
                      waited < 50 {  // up to 5 seconds
                    try await Task.sleep(for: .milliseconds(100))
                    waited += 1
                }
                if waited >= 50 {
                    AppLog.warn("Session update timed out, sending greeting anyway")
                } else {
                    AppLog.debug("Session updated after \(waited * 100)ms")
                }

                // Send any message that was queued before connection completed
                if let msg = self.pendingMessage {
                    self.pendingMessage = nil
                    try conv.send(from: .user, text: msg)
                    AppLog.debug("Sent queued message")
                }

                self.startSyncLoop()
                self.startErrorListener()
            } catch {
                self.errorMessage = "Connection failed: \(error.localizedDescription)"
                self.statusMessage = "Disconnected"
                AppLog.error("WebRTC connect failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        AppLog.debug("disconnect()")

        // Mute mic and stop audio session BEFORE tearing down the
        // conversation. The SDK's Conversation has an internal retain
        // cycle (Task.detached + guard let self) that prevents deinit,
        // so setting conversation = nil alone won't close WebRTC.
        // Deactivating the audio session kills playback immediately.
        conversation?.muted = true
        cleanUpConversation()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            AppLog.debug("Audio session deactivated")
        } catch {
            AppLog.warn("Audio session deactivation warning: \(error.localizedDescription)")
        }

        isConnected = false
        isModelSpeaking = false
        isUserSpeaking = false
        transcript = ""
        statusMessage = ""
        pendingMessage = nil
    }

    // MARK: - Audio Capture (Mic Mute / Unmute)

    /// Unmutes the microphone. The SDK handles mic capture automatically
    /// after connection — this just toggles the mute state.
    func startCapture() {
        conversation?.muted = false
        if isConnected {
            statusMessage = "Listening…"
        }
        AppLog.debug("startCapture (unmuted)")
    }

    /// Mutes the microphone (SDK keeps running, just silences input).
    func stopCapture() {
        conversation?.muted = true
        AppLog.debug("stopCapture (muted)")
    }

    /// Cancel any in-progress AI response and clear the output audio buffer
    /// so the speaker goes silent immediately.
    func silenceAI() {
        guard let conv = conversation else { return }
        do {
            try conv.send(event: .cancelResponse(eventId: nil, responseId: nil))
            try conv.send(event: .outputAudioBufferClear(eventId: nil))
            AppLog.debug("silenceAI: cancelled response + cleared audio buffer")
        } catch {
            AppLog.warn("silenceAI failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Send User Message

    func sendUserMessage(_ text: String) {
        guard let conv = conversation, conv.status == .connected else {
            // Connection not ready yet — queue for delivery after connect
            pendingMessage = text
            AppLog.debug("Queued message (not connected yet)")
            return
        }
        do {
            try conv.send(from: .user, text: text)
            AppLog.debug("Sent user message")
        } catch {
            AppLog.error("sendUserMessage failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Ephemeral Key

    /// Calls OpenAI's GA Realtime API to create a short-lived client secret
    /// for WebRTC authentication.
    private func fetchEphemeralKey() async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !AppConfig.isMissing(apiKey) else {
            throw NSError(
                domain: "RealtimeService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing OpenAI API key"]
            )
        }

        guard let url = URL(string: "https://api.openai.com/v1/realtime/client_secrets") else {
            throw NSError(
                domain: "RealtimeService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid client secrets endpoint URL"]
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // GA endpoint takes no model param — model is set on the connect URL
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            AppLog.error("Ephemeral key request failed (\(code)): \(bodyStr)")
            throw NSError(
                domain: "RealtimeService", code: code,
                userInfo: [NSLocalizedDescriptionKey:
                    "Ephemeral key request failed (\(code)): \(bodyStr)"]
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "RealtimeService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid ephemeral key response (not JSON)"]
            )
        }

        AppLog.debug("Client secret response parsed")

        // GA endpoint returns { "value": "ek_...", "expires_at": ..., "session": {...} }
        if let key = json["value"] as? String { return key }

        // Beta endpoint fallback: { "client_secret": { "value": "ek_..." } }
        if let clientSecret = json["client_secret"] as? [String: Any],
           let key = clientSecret["value"] as? String {
            return key
        }

        let bodyStr = String(data: data, encoding: .utf8) ?? ""
        AppLog.error("Could not parse key from response: \(bodyStr)")
        throw NSError(
            domain: "RealtimeService", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid ephemeral key response"]
        )
    }

    // MARK: - State Sync Loop

    /// Polls the SDK's Conversation state and copies it into our protocol-
    /// conforming properties so CookModeViewModel can read them.
    private func startSyncLoop() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.syncState()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func syncState() {
        guard let conv = conversation else { return }

        let sdkModelSpeaking = conv.isModelSpeaking
        let sdkUserSpeaking = conv.isUserSpeaking
        let latestConversationMessage = Self.latestMessage(in: conv.entries)
        let latestAssistantMessage = Self.latestMessage(in: conv.entries, role: .assistant)
        let userMessageCount = conv.entries.reduce(into: 0) { count, entry in
            guard case let .message(message) = entry, message.role == .user else { return }
            count += 1
        }

        if sdkUserSpeaking && !previousSDKUserSpeaking {
            userMessageCountAtSpeechStart = userMessageCount
            transcript = ""
        }
        previousSDKUserSpeaking = sdkUserSpeaking

        let userTurnCommitted = userMessageCount > userMessageCountAtSpeechStart
        isUserSpeaking = sdkUserSpeaking && !userTurnCommitted

        // Connection monitoring
        if isConnected && conv.status != .connected {
            isConnected = false
            statusMessage = "Disconnected"
            errorMessage = "Voice connection lost. Tap mic to reconnect."
        }

        // ── Transcript: latest assistant message ──
          if sdkUserSpeaking {
                transcript = ""
          }

          if let latestAssistantMessage,
              latestAssistantMessage.status == .inProgress,
              latestAssistantMessage.id != currentAssistantMessageId {
            transcript = ""
            currentAssistantMessageId = latestAssistantMessage.id
        }
          if !sdkUserSpeaking,
              let latestAssistantMessage,
              latestConversationMessage?.role == .assistant {
            let text = Self.assistantDisplayTranscript(from: latestAssistantMessage)
            if !text.isEmpty,
               Self.shouldDisplayAssistantTranscript(
                from: latestAssistantMessage,
                isAudioPlaying: sdkModelSpeaking
               ) {
                transcript = text
            }
        }

        isModelSpeaking = !isUserSpeaking && sdkModelSpeaking

        // ── Function calls ──
        // Scan entries for completed function calls not yet dispatched.
        for entry in conv.entries {
            if case let .functionCall(fc) = entry,
               fc.status == .completed,
               !processedFunctionCallIds.contains(fc.callId) {
                processedFunctionCallIds.insert(fc.callId)
                dispatchFunctionCall(fc, via: conv)
            }
        }

        // ── Garbage transcription rejection ──
        // Check new user messages for noise transcriptions and cancel
        // the AI response if detected.
        for entry in conv.entries {
            if case let .message(msg) = entry,
               msg.role == .user,
               !processedUserTranscriptIds.contains(msg.id) {
                // Extract transcript from inputAudio content
                for content in msg.content {
                    if case let .inputAudio(audio) = content,
                       let transcript = audio.transcript {
                        processedUserTranscriptIds.insert(msg.id)
                        if Self.isGarbageTranscription(transcript) {
                            AppLog.debug("Garbage transcription detected; cancelling response")
                            do {
                                try conv.send(event: .cancelResponse(eventId: nil, responseId: nil))
                                try conv.send(event: .outputAudioBufferClear(eventId: nil))
                                try conv.send(event: .deleteConversationItem(eventId: nil, itemId: msg.id))
                                AppLog.debug("Cancelled response and removed noise item")
                            } catch {
                                AppLog.warn("Failed to cancel garbage response: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }

        // ── Status message ──
        if conv.status == .connected {
            if isUserSpeaking {
                statusMessage = "Listening…"
            } else if isModelSpeaking {
                statusMessage = "Speaking…"
            } else {
                statusMessage = "Ready"
            }
        }

        logStateTransitionIfNeeded(
            conv: conv,
            sdkUserSpeaking: sdkUserSpeaking,
            sdkModelSpeaking: sdkModelSpeaking,
            userTurnCommitted: userTurnCommitted,
            latestAssistantMessage: latestAssistantMessage
        )
    }

    // MARK: - Helpers

    static func assistantDisplayTranscript(from message: Item.Message) -> String {
        let audioTranscript = message.content.compactMap { content -> String? in
            guard case let .audio(audio) = content else { return nil }
            return audio.transcript
        }.joined()

        if !audioTranscript.isEmpty {
            return audioTranscript
        }

        return message.content.compactMap { content -> String? in
            guard case let .text(text) = content else { return nil }
            return text
        }.joined()
    }
    static func shouldDisplayAssistantTranscript(
        from message: Item.Message,
        isAudioPlaying: Bool
    ) -> Bool {
        isAudioPlaying || message.status != .inProgress
    }

    private static func latestMessage(in entries: [Item], role: Item.Message.Role) -> Item.Message? {
        entries.reversed().compactMap { entry -> Item.Message? in
            guard case let .message(message) = entry, message.role == role else { return nil }
            return message
        }.first
    }

    private static func latestMessage(in entries: [Item]) -> Item.Message? {
        entries.reversed().compactMap { entry -> Item.Message? in
            guard case let .message(message) = entry else { return nil }
            return message
        }.first
    }

    private func logStateTransitionIfNeeded(
        conv: Conversation,
        sdkUserSpeaking: Bool,
        sdkModelSpeaking: Bool,
        userTurnCommitted: Bool,
        latestAssistantMessage: Item.Message?
    ) {
        let signature = [
            "conn=\(conv.status.rawValue)",
            "sdkUser=\(sdkUserSpeaking)",
            "sdkModel=\(sdkModelSpeaking)",
            "user=\(isUserSpeaking)",
            "model=\(isModelSpeaking)",
            "ui=\(statusMessage)",
            "muted=\(conv.muted)",
            "assistantMsgs=\(describe(message: latestAssistantMessage, transcriptSource: transcript))",
            "speechStartCount=\(userMessageCountAtSpeechStart)",
            "userTurnCommitted=\(userTurnCommitted)",
        ].joined(separator: " | ")

        guard signature != lastLoggedStateSignature else { return }
        lastLoggedStateSignature = signature
        AppLog.info("[RealtimeState] \(signature)")
    }

    private func describe(message: Item.Message?, transcriptSource: String) -> String {
        guard let message else { return "none" }
        return "\(shortID(message.id)):\(message.status.rawValue):chars=\(transcriptSource.count)"
    }

    private func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }

    /// Sends the function result back to the API, notifies the view model,
    /// then triggers a follow-up response.
    private func dispatchFunctionCall(_ fc: Item.FunctionCall, via conv: Conversation) {
        // Parse JSON arguments
        let args: [String: Any]
        if let data = fc.arguments.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            args = parsed
        } else {
            args = [:]
        }

        AppLog.debug("Function call: \(fc.name)")

        // 1. Send function output FIRST so the API knows the call succeeded
        do {
            // OpenAI requires item.id ≤ 32 chars; UUID has 36 (with hyphens)
            let shortId = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(32)
            try conv.send(result: Item.FunctionCallOutput(
                id: String(shortId),
                callId: fc.callId,
                output: "{\"status\":\"done\"}"
            ))
        } catch {
            AppLog.error("Function output send failed: \(error.localizedDescription)")
        }

        // 2. Notify the view model (this may update currentStepIndex etc.)
        onFunctionCall?(fc.name, args)

        // 3. Trigger a follow-up response so the model speaks after the tool call
        do {
            try conv.send(event: .createResponse())
        } catch {
            AppLog.error("createResponse failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Listener

    private func startErrorListener() {
        guard let conv = conversation else { return }
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            for await error in conv.errors {
                guard let self else { break }
                AppLog.error("API error: \(error.message)")
                let benign = [
                    "no active response",
                    "cancellation failed",
                    "already has an active response"
                ]
                let isBenign = benign.contains { error.message.lowercased().contains($0) }
                if !isBenign {
                    self.errorMessage = error.message
                }
            }
        }
    }

    // MARK: - Cleanup

    private func cleanUpConversation() {
        syncTask?.cancel()
        syncTask = nil
        errorTask?.cancel()
        errorTask = nil
        conversation = nil  // triggers SDK disconnect on deinit
        processedFunctionCallIds.removeAll()
        processedUserTranscriptIds.removeAll()
        currentAssistantMessageId = nil
        previousSDKUserSpeaking = false
        userMessageCountAtSpeechStart = 0
        lastLoggedStateSignature = ""
    }

    // MARK: - Tool Conversion

    /// Converts the dictionary-based tool definitions from CookModeViewModel
    /// into the SDK's typed Tool values.
    private func convertTools(_ tools: [[String: Any]]) -> [Tool] {
        tools.compactMap { dict -> Tool? in
            guard let name = dict["name"] as? String else { return nil }
            let description = dict["description"] as? String

            var schema = JSONSchema.object(properties: [:])
            if let paramsDict = dict["parameters"] as? [String: Any],
               let properties = paramsDict["properties"] as? [String: Any] {
                var props: [String: JSONSchema] = [:]
                for (key, value) in properties {
                    if let propDict = value as? [String: Any],
                       let type = propDict["type"] as? String {
                        let desc = propDict["description"] as? String
                        switch type {
                        case "integer": props[key] = .integer(description: desc)
                        case "number":  props[key] = .number(description: desc)
                        case "string":  props[key] = .string(description: desc)
                        case "boolean": props[key] = .boolean(description: desc)
                        default:        props[key] = .string(description: desc)
                        }
                    }
                }
                schema = .object(properties: props)
            }

            return .function(.init(name: name, description: description, parameters: schema))
        }
    }

    // MARK: - Garbage Transcription Detection

    /// Returns true if the transcription looks like noise rather than real speech.
    ///
    /// Kitchen microphones pick up sizzling, clanking, fans etc. that VAD
    /// sometimes falsely triggers on. The Whisper transcriber then produces
    /// garbage like "請。", "…", single random characters, or just punctuation.
    ///
    /// Real speech always contains recognisable words (even short ones like
    /// "no", "next", "stop", or foreign ingredient names like "mirin").
    static func isGarbageTranscription(_ transcript: String) -> Bool {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty or whitespace-only
        if trimmed.isEmpty { return true }

        // Strip all punctuation and whitespace — what's left?
        let stripped = trimmed.unicodeScalars.filter {
            !CharacterSet.punctuationCharacters.contains($0) &&
            !CharacterSet.whitespacesAndNewlines.contains($0) &&
            !CharacterSet.symbols.contains($0)
        }
        let letterContent = String(stripped)

        // Nothing left after stripping punctuation (e.g. "…", "。", "...")
        if letterContent.isEmpty { return true }

        // Single-character non-Latin transcriptions are usually noise.
        // Keep two-character utterances to avoid rejecting short multilingual words.
        if letterContent.count <= 1 {
            let latinRange = letterContent.range(
                of: "[a-zA-Z]",
                options: .regularExpression
            )
            if latinRange == nil {
                return true  // 1-2 non-Latin chars = noise
            }
        }

        return false
    }
}
