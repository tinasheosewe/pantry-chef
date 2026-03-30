import SwiftUI

// MARK: - Active Cooks Protocol

@MainActor
protocol ActiveCooksManaging: AnyObject {
    var activeSessions: [CookingSession] { get }
    var activeMultiCookSessions: [MultiCookSession] { get }
    var hasActiveSessions: Bool { get }
    var count: Int { get }
    func refresh()
    func session(for recipeId: UUID) -> CookingSession?
    func endSession(for recipeId: UUID)
    func endMultiCookSession(id: UUID)
    func endAllSessions()
}

// MARK: - Active Cooks Manager
//
// Observable object that provides the current list of active cooking sessions
// for UI binding. Wraps CookingSession persistence layer.

@Observable
@MainActor
final class ActiveCooksManager: ActiveCooksManaging {
    private let sessionStore: CookingSessionStoreProtocol

    /// All active (non-expired) cooking sessions.
    var activeSessions: [CookingSession] = []

    /// All active multi-cook sessions.
    var activeMultiCookSessions: [MultiCookSession] = []

    /// Whether any session is currently active.
    var hasActiveSessions: Bool { !activeSessions.isEmpty || !activeMultiCookSessions.isEmpty }

    /// Number of currently active sessions.
    var count: Int { activeSessions.count + activeMultiCookSessions.count }

    init(sessionStore: CookingSessionStoreProtocol? = nil) {
        self.sessionStore = sessionStore ?? UserDefaultsCookingSessionStore()
        refresh()
    }

    /// Reload from UserDefaults.
    func refresh() {
        activeSessions = sessionStore.loadAll()
        activeMultiCookSessions = MultiCookSession.loadAll()
    }

    /// Check if a specific recipe has an active session.
    func session(for recipeId: UUID) -> CookingSession? {
        activeSessions.first { $0.recipeId == recipeId }
    }

    /// End a specific session.
    func endSession(for recipeId: UUID) {
        sessionStore.clear(recipeId: recipeId)
        refresh()
    }

    /// End a specific multi-cook session.
    func endMultiCookSession(id: UUID) {
        MultiCookSession.clear(id: id)
        refresh()
    }

    /// End all sessions.
    func endAllSessions() {
        sessionStore.clearAll()
        MultiCookSession.clearAll()
        refresh()
    }
}
