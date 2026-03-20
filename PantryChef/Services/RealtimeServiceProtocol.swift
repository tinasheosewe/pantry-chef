import Foundation

// MARK: - Realtime Service Protocol
//
// Abstracts the Realtime API service so CookModeViewModel can be tested
// with a mock that doesn't depend on AVAudioEngine, WebSockets, or
// network connectivity.

@MainActor
protocol RealtimeServiceProtocol: AnyObject {
    // MARK: - Observable state
    var isConnected: Bool { get set }
    var isModelSpeaking: Bool { get set }
    var isUserSpeaking: Bool { get set }
    var transcript: String { get set }
    var statusMessage: String { get set }
    var errorMessage: String? { get set }
    var isAudioReady: Bool { get }

    // MARK: - Callback
    var onFunctionCall: ((String, [String: Any]) -> Void)? { get set }

    // MARK: - Lifecycle
    func prepareAudio() async
    func connect(withInstructions instructions: String, tools: [[String: Any]])
    func disconnect()

    // MARK: - Audio capture
    func startCapture()
    func stopCapture()

    // MARK: - Messaging
    func sendUserMessage(_ text: String)
}
