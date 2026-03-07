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

    // MARK: - Public state (observed by CookModeViewModel)

    var isConnected = false
    var isModelSpeaking = false
    var isUserSpeaking = false
    var transcript = ""          // rolling text of what the model is saying
    var userTranscript = ""      // rolling text of what the user said
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

    /// Background tasks for state sync and error listening.
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var errorTask: Task<Void, Never>?

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
            print("[RealtimeService] Audio session configured for WebRTC")
        } catch {
            print("[RealtimeService] ⚠️ Audio session setup warning: \(error)")
        }

        do {
            ephemeralKey = try await fetchEphemeralKey()
            statusMessage = "Ready"
            print("[RealtimeService] Ephemeral key obtained")
        } catch {
            errorMessage = "Audio setup failed: \(error.localizedDescription)"
            print("[RealtimeService] ❌ Ephemeral key fetch failed: \(error)")
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
            session.audio.input.turnDetection = .serverVad(
                createResponse: true,
                prefixPaddingMs: 500,
                silenceDurationMs: 800,
                threshold: 0.8
            )
            session.tools = sdkTools
            session.toolChoice = .auto
            // Note: temperature and modalities are not supported by the GA API
            // session.update and will cause the entire update to be rejected.
        }

        // ── Event-driven function call dispatch ──
        // The SDK fires this callback synchronously on MainActor the
        // instant `response.output_item.done` arrives with a function
        // call item.  No polling, no race conditions.
        conversation?.onFunctionCallCompleted = { [weak self] fc in
            guard let self, let conv = self.conversation else { return }
            guard !self.processedFunctionCallIds.contains(fc.callId) else {
                print("[RealtimeService] Skipping duplicate function call: \(fc.name)")
                return
            }
            self.processedFunctionCallIds.insert(fc.callId)
            self.dispatchFunctionCall(fc, via: conv)
        }

        // ── Client-side garbage rejection ──
        // When user transcription arrives, check if it looks like noise
        // (sizzling, clanking, etc. that VAD falsely triggered on).
        // If so, cancel the in-progress response and remove the noise
        // item from the conversation to prevent the AI from responding.
        conversation?.onUserTranscriptionCompleted = { [weak self] itemId, transcript in
            guard let self, let conv = self.conversation else { return }
            if Self.isGarbageTranscription(transcript) {
                print("[RealtimeService] 🗑️ Garbage transcription detected: \"\(transcript)\" — cancelling response")
                do {
                    // Cancel the in-progress response (stops AI from speaking)
                    try conv.send(event: .cancelResponse(eventId: nil, responseId: nil))
                    // Clear the output audio buffer (stops any audio already queued)
                    try conv.send(event: .outputAudioBufferClear(eventId: nil))
                    // Delete the noise item from conversation history so it
                    // doesn't pollute future context
                    try conv.send(event: .deleteConversationItem(eventId: nil, itemId: itemId))
                    print("[RealtimeService] 🗑️ Cancelled response and removed noise item")
                } catch {
                    print("[RealtimeService] ⚠️ Failed to cancel garbage response: \(error)")
                }
            }
        }

        // Connect asynchronously via WebRTC
        let realtimeModel = "gpt-4o-realtime-preview"
        Task { [weak self] in
            guard let self, let conv = self.conversation else { return }
            do {
                try await conv.connect(ephemeralKey: key, model: .custom(realtimeModel))
                print("[RealtimeService] Connected via WebRTC")
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
                    print("[RealtimeService] ⚠️ Session update timed out, sending greeting anyway")
                } else {
                    print("[RealtimeService] Session updated after \(waited * 100)ms")
                }

                // Send any message that was queued before connection completed
                if let msg = self.pendingMessage {
                    self.pendingMessage = nil
                    try conv.send(from: .user, text: msg)
                    print("[RealtimeService] Sent queued message")
                }

                self.startSyncLoop()
                self.startErrorListener()
            } catch {
                self.errorMessage = "Connection failed: \(error.localizedDescription)"
                self.statusMessage = "Disconnected"
                print("[RealtimeService] ❌ WebRTC connect failed: \(error)")
            }
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        print("[RealtimeService] disconnect()")

        // Mute mic and stop audio session BEFORE tearing down the
        // conversation. The SDK's Conversation has an internal retain
        // cycle (Task.detached + guard let self) that prevents deinit,
        // so setting conversation = nil alone won't close WebRTC.
        // Deactivating the audio session kills playback immediately.
        conversation?.muted = true
        cleanUpConversation()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("[RealtimeService] Audio session deactivated")
        } catch {
            print("[RealtimeService] ⚠️ Audio session deactivation: \(error)")
        }

        isConnected = false
        isModelSpeaking = false
        isUserSpeaking = false
        transcript = ""
        userTranscript = ""
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
        print("[RealtimeService] startCapture (unmuted)")
    }

    /// Mutes the microphone (SDK keeps running, just silences input).
    func stopCapture() {
        conversation?.muted = true
        print("[RealtimeService] stopCapture (muted)")
    }

    // MARK: - Send User Message

    func sendUserMessage(_ text: String) {
        guard let conv = conversation, conv.status == .connected else {
            // Connection not ready yet — queue for delivery after connect
            pendingMessage = text
            print("[RealtimeService] Queued message (not connected yet)")
            return
        }
        do {
            try conv.send(from: .user, text: text)
            print("[RealtimeService] Sent user message: \(text.prefix(60))…")
        } catch {
            print("[RealtimeService] ❌ sendUserMessage error: \(error)")
        }
    }

    // MARK: - Ephemeral Key

    /// Calls OpenAI's GA Realtime API to create a short-lived client secret
    /// for WebRTC authentication.
    private func fetchEphemeralKey() async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/realtime/client_secrets")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // GA endpoint takes no model param — model is set on the connect URL
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            print("[RealtimeService] Ephemeral key request failed (\(code)): \(bodyStr)")
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

        print("[RealtimeService] Client secret response keys: \(json.keys.sorted())")

        // GA endpoint returns { "value": "ek_...", "expires_at": ..., "session": {...} }
        if let key = json["value"] as? String { return key }

        // Beta endpoint fallback: { "client_secret": { "value": "ek_..." } }
        if let clientSecret = json["client_secret"] as? [String: Any],
           let key = clientSecret["value"] as? String {
            return key
        }

        let bodyStr = String(data: data, encoding: .utf8) ?? ""
        print("[RealtimeService] ❌ Could not parse key from: \(bodyStr)")
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

        let wasModelSpeaking = isModelSpeaking

        // Mirror SDK state
        isModelSpeaking = conv.isModelSpeaking
        isUserSpeaking = conv.isUserSpeaking

        // Connection monitoring
        if isConnected && conv.status != .connected {
            isConnected = false
            statusMessage = "Disconnected"
            errorMessage = "Voice connection lost. Tap mic to reconnect."
        }

        // ── Transcript: latest assistant message ──
        // Clear stale transcript when model starts a NEW response
        if conv.isModelSpeaking && !wasModelSpeaking {
            transcript = ""
        }
        // Always update from the latest assistant message so we catch
        // deltas that arrive before outputAudioBufferStarted.
        if let lastMsg = conv.messages.last(where: { $0.role == .assistant }) {
            let text = extractTranscript(from: lastMsg)
            if !text.isEmpty { transcript = text }
        }

        // ── User transcript ──
        if let lastUserMsg = conv.messages.last(where: { $0.role == .user }) {
            let text = extractTranscript(from: lastUserMsg)
            if !text.isEmpty { userTranscript = text }
        }

        // ── Function calls ──
        // Handled via event-driven callback (onFunctionCallCompleted)
        // set up in connect(). No polling needed.

        // ── Status message ──
        if conv.status == .connected {
            if conv.isModelSpeaking {
                statusMessage = "Speaking…"
            } else if conv.isUserSpeaking {
                statusMessage = "Listening…"
            } else {
                statusMessage = "Ready"
            }
        }
    }

    // MARK: - Helpers

    /// Extracts display text from a message's content parts.
    private func extractTranscript(from message: Item.Message) -> String {
        message.content.compactMap { content -> String? in
            switch content {
            case .text(let t): return t
            case .audio(let a): return a.transcript
            case .inputText(let t): return t
            case .inputAudio(let a): return a.transcript
            }
        }.joined()
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

        print("[RealtimeService] Function call: \(fc.name)(\(fc.arguments))")

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
            print("[RealtimeService] ❌ Function output error: \(error)")
        }

        // 2. Notify the view model (this may update currentStepIndex etc.)
        onFunctionCall?(fc.name, args)

        // 3. Trigger a follow-up response so the model speaks after the tool call
        do {
            try conv.send(event: .createResponse())
        } catch {
            print("[RealtimeService] ❌ createResponse error: \(error)")
        }
    }

    // MARK: - Error Listener

    private func startErrorListener() {
        guard let conv = conversation else { return }
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            for await error in conv.errors {
                guard let self else { break }
                print("[RealtimeService] API error: \(error.message)")
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

        // Very short (1-2 characters) AND entirely non-Latin script
        // Real commands like "no", "ok" are Latin. Noise like "請" is not.
        // But "mirin" (5 chars) or "五香粉" (3 chars worth of meaning) are real.
        if letterContent.count <= 2 {
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
