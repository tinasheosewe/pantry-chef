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

    init(apiKey: String = AppConfig.openAIAPIKey) {
        self.apiKey = apiKey
    }

    // MARK: - Prepare Audio

    /// Fetches an ephemeral key from OpenAI for WebRTC connection.
    /// Call before connect() — the key is short-lived (~2 minutes).
    func prepareAudio() async {
        statusMessage = "Setting up…"
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
            session.modalities = [.text, .audio]
            session.audio.output.voice = .sage
            session.audio.input.transcription = .init(model: .gpt4oMini)
            session.audio.input.turnDetection = .serverVad(
                createResponse: true,
                prefixPaddingMs: 300,
                silenceDurationMs: 800,
                threshold: 0.5
            )
            session.tools = sdkTools
            session.toolChoice = .auto
            session.temperature = 0.75
        }

        // Connect asynchronously via WebRTC
        Task { [weak self] in
            guard let self, let conv = self.conversation else { return }
            do {
                try await conv.connect(ephemeralKey: key)
                print("[RealtimeService] Connected via WebRTC")
                self.isConnected = true
                self.statusMessage = "Connected"

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
        cleanUpConversation()
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

    /// Calls OpenAI's REST API to create a short-lived session token
    /// for WebRTC authentication.
    private func fetchEphemeralKey() async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/realtime/sessions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-realtime-preview",
            "voice": "sage"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "RealtimeService", code: code,
                userInfo: [NSLocalizedDescriptionKey:
                    "Ephemeral key request failed (\(code)): \(bodyStr)"]
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientSecret = json["client_secret"] as? [String: Any],
              let key = clientSecret["value"] as? String else {
            throw NSError(
                domain: "RealtimeService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid ephemeral key response"]
            )
        }

        return key
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
        if conv.isModelSpeaking {
            if let lastMsg = conv.messages.last(where: { $0.role == .assistant }) {
                let text = extractTranscript(from: lastMsg)
                if !text.isEmpty { transcript = text }
            }
        } else if wasModelSpeaking {
            // Model just stopped → clear the rolling transcript
            transcript = ""
        }

        // ── User transcript ──
        if let lastUserMsg = conv.messages.last(where: { $0.role == .user }) {
            let text = extractTranscript(from: lastUserMsg)
            if !text.isEmpty { userTranscript = text }
        }

        // ── Function calls ──
        for entry in conv.entries {
            if case let .functionCall(fc) = entry,
               fc.status == .completed,
               !processedFunctionCallIds.contains(fc.callId) {
                processedFunctionCallIds.insert(fc.callId)
                dispatchFunctionCall(fc, via: conv)
            }
        }

        // ── Status message ──
        if conv.status == .connected {
            if conv.isModelSpeaking {
                statusMessage = "Speaking…"
            } else {
                statusMessage = "Listening…"
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

    /// Calls the onFunctionCall callback and sends the result back to the API.
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

        // Notify the view model
        onFunctionCall?(fc.name, args)

        // Respond to the API with a success result
        do {
            try conv.send(result: Item.FunctionCallOutput(
                id: UUID().uuidString,
                callId: fc.callId,
                output: "{\"status\":\"done\"}"
            ))
            try conv.send(event: .createResponse())
        } catch {
            print("[RealtimeService] ❌ Function response error: \(error)")
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
}
