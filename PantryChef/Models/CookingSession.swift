import Foundation

// MARK: - Cooking Session
//
// Lightweight persistence model for "Continue in Background" sessions.
// Supports multiple parallel cooking sessions (one per recipe).
// Saved to UserDefaults when cook mode auto-backgrounds or the user dismisses.
// Each session is keyed by recipeId.

struct CookingSession: Codable, Identifiable {

    var id: UUID { recipeId }

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

    /// Whether this is part of a multi-recipe cook session.
    var multiCookSessionId: UUID?

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

    // MARK: - Persistence (multi-session array)

    private static let storageKey = "active_cooking_sessions"

    /// Save this session (upserts into the sessions array).
    func save() {
        var sessions = Self.loadAll()
        if let idx = sessions.firstIndex(where: { $0.recipeId == recipeId }) {
            sessions[idx] = self
        } else {
            sessions.append(self)
        }
        Self.saveAll(sessions)
        print("[CookingSession] Saved session for \(recipeName) (step \(currentStepIndex + 1)/\(totalSteps)) — \(sessions.count) active")
    }

    /// Load all active sessions, clearing expired ones.
    static func loadAll() -> [CookingSession] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let sessions = try? JSONDecoder().decode([CookingSession].self, from: data) else {
            return []
        }

        let active = sessions.filter { !$0.isExpired && $0.isActive }
        if active.count != sessions.count {
            // Clean up expired/inactive sessions
            saveAll(active)
        }
        return active
    }

    /// Load a specific session by recipe ID.
    static func load(recipeId: UUID) -> CookingSession? {
        loadAll().first { $0.recipeId == recipeId }
    }

    /// Load any single active session (backward compatibility).
    static func load() -> CookingSession? {
        loadAll().first
    }

    /// Remove a specific session.
    static func clear(recipeId: UUID) {
        var sessions = loadAll()
        sessions.removeAll { $0.recipeId == recipeId }
        saveAll(sessions)
        print("[CookingSession] Cleared session for recipe \(recipeId.uuidString.prefix(8))… — \(sessions.count) remaining")
    }

    /// Clear all sessions.
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        print("[CookingSession] Cleared all sessions")
    }

    /// Backward-compatible clear (clears all).
    static func clear() {
        clearAll()
    }

    // MARK: - Internal

    private static func saveAll(_ sessions: [CookingSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

}
