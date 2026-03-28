import Foundation

@MainActor
final class UserDefaultsCookingSessionStore: CookingSessionStoreProtocol {
    func loadAll() -> [CookingSession] {
        CookingSession.loadAll()
    }

    func load(recipeId: UUID) -> CookingSession? {
        CookingSession.load(recipeId: recipeId)
    }

    func save(_ session: CookingSession) {
        session.save()
    }

    func clear(recipeId: UUID) {
        CookingSession.clear(recipeId: recipeId)
    }

    func clearAll() {
        CookingSession.clearAll()
    }
}

@MainActor
final class UserDefaultsCookModePreferenceStore: CookModePreferenceStoreProtocol {
    private let userDefaults: UserDefaults
    private let mutedKey: String

    init(userDefaults: UserDefaults = .standard, mutedKey: String = "cookMode.isMuted") {
        self.userDefaults = userDefaults
        self.mutedKey = mutedKey
    }

    var isMuted: Bool {
        get { userDefaults.bool(forKey: mutedKey) }
        set { userDefaults.set(newValue, forKey: mutedKey) }
    }

    func reset() {
        userDefaults.removeObject(forKey: mutedKey)
    }
}