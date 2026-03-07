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

    /// Legacy single-session key for migration.
    private static let legacyStorageKey = "active_cooking_session"

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
        // Migrate legacy single session if present
        migrateLegacySession()

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

    private static func migrateLegacySession() {
        guard let data = UserDefaults.standard.data(forKey: legacyStorageKey),
              let legacy = try? JSONDecoder().decode(LegacyCookingSession.self, from: data) else { return }

        // Convert to new format and save
        let session = CookingSession(
            recipeId: legacy.recipeId,
            recipeName: legacy.recipeName,
            totalSteps: legacy.totalSteps,
            stepSummaries: legacy.stepSummaries.map {
                StepSummary(stepNumber: $0.stepNumber, instruction: $0.instruction, timerMinutes: $0.timerMinutes)
            },
            currentStepIndex: legacy.currentStepIndex,
            startedAt: legacy.startedAt,
            backgroundedAt: legacy.backgroundedAt,
            isActive: legacy.isActive,
            expiryTimeoutSeconds: legacy.expiryTimeoutSeconds
        )
        session.save()
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        print("[CookingSession] Migrated legacy session for \(legacy.recipeName)")
    }
}

// MARK: - Legacy format for migration

private struct LegacyCookingSession: Codable {
    let recipeId: UUID
    let recipeName: String
    let totalSteps: Int
    let stepSummaries: [LegacyStepSummary]
    var currentStepIndex: Int
    let startedAt: Date
    let backgroundedAt: Date
    var isActive: Bool
    var expiryTimeoutSeconds: TimeInterval

    struct LegacyStepSummary: Codable {
        let stepNumber: Int
        let instruction: String
        let timerMinutes: Int?
    }
}
