import Foundation

// MARK: - Cooking Session
//
// Lightweight persistence model for "Continue in Background" sessions.
// Saved to UserDefaults when the user explicitly taps "Continue in Background".
// NOT saved on normal cook mode close (X button) — that works exactly as before.

struct CookingSession: Codable {

    /// The recipe being cooked.
    let recipeId: UUID
    let recipeName: String
    let totalSteps: Int

    /// Step-level info for notification content.
    let stepSummaries: [StepSummary]

    /// Which step the user was on when they backgrounded.
    var currentStepIndex: Int

    /// When the cooking session started.
    let startedAt: Date

    /// When the background session was created.
    let backgroundedAt: Date

    /// Whether the session is still active.
    var isActive: Bool

    /// Auto-expire timeout in seconds (default: 2 hours).
    var expiryTimeoutSeconds: TimeInterval

    // MARK: - Step Summary

    struct StepSummary: Codable {
        let stepNumber: Int
        let instruction: String
        let timerMinutes: Int?
    }

    // MARK: - Computed

    var isExpired: Bool {
        Date().timeIntervalSince(backgroundedAt) > expiryTimeoutSeconds
    }

    // MARK: - Persistence

    private static let storageKey = "active_cooking_session"

    /// Save the session to UserDefaults.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
        print("[CookingSession] Saved session for \(recipeName) (step \(currentStepIndex + 1)/\(totalSteps))")
    }

    /// Load the active session, if any. Clears expired sessions automatically.
    static func load() -> CookingSession? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var session = try? JSONDecoder().decode(CookingSession.self, from: data) else {
            return nil
        }

        // Auto-expire check
        if session.isExpired {
            print("[CookingSession] Session expired, clearing")
            session.isActive = false
            clear()
            return nil
        }

        return session.isActive ? session : nil
    }

    /// Clear the persisted session.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        print("[CookingSession] Cleared session")
    }
}
