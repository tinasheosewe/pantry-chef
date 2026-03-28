import SwiftUI

// MARK: - Active Cooks Protocol

@MainActor
protocol ActiveCooksManaging: AnyObject {
    var activeSessions: [CookingSession] { get }
    var hasActiveSessions: Bool { get }
    var count: Int { get }
    func refresh()
    func session(for recipeId: UUID) -> CookingSession?
    func endSession(for recipeId: UUID)
    func endAllSessions()
}

// MARK: - Active Cooks Manager
//
// Observable object that provides the current list of active cooking sessions
// for UI binding. Wraps CookingSession persistence layer.

@Observable
@MainActor
final class ActiveCooksManager: ActiveCooksManaging {
    /// All active (non-expired) cooking sessions.
    var activeSessions: [CookingSession] = []

    /// Whether any session is currently active.
    var hasActiveSessions: Bool { !activeSessions.isEmpty }

    /// Number of currently active sessions.
    var count: Int { activeSessions.count }

    init() {
        refresh()
    }

    /// Reload from UserDefaults.
    func refresh() {
        activeSessions = CookingSession.loadAll()
    }

    /// Check if a specific recipe has an active session.
    func session(for recipeId: UUID) -> CookingSession? {
        activeSessions.first { $0.recipeId == recipeId }
    }

    /// End a specific session.
    func endSession(for recipeId: UUID) {
        CookingSession.clear(recipeId: recipeId)
        refresh()
    }

    /// End all sessions.
    func endAllSessions() {
        CookingSession.clearAll()
        refresh()
    }
}
