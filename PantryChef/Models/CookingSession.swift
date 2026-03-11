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

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case recipeId, recipeName, totalSteps, stepSummaries
        case currentStepIndex, startedAt, backgroundedAt
        case isActive, expiryTimeoutSeconds, multiCookSessionId
    }

    /// Decode with defaults for fields that may be missing in older persisted
    /// sessions. This prevents `JSONDecoder` from raising "invalid reuse after
    /// initialization failure" when stored data predates a schema change.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recipeId          = try c.decode(UUID.self,              forKey: .recipeId)
        recipeName        = try c.decode(String.self,            forKey: .recipeName)
        totalSteps        = try c.decode(Int.self,               forKey: .totalSteps)
        stepSummaries     = try c.decodeIfPresent([StepSummary].self, forKey: .stepSummaries) ?? []
        currentStepIndex  = try c.decode(Int.self,               forKey: .currentStepIndex)
        startedAt         = try c.decode(Date.self,              forKey: .startedAt)
        backgroundedAt    = try c.decode(Date.self,              forKey: .backgroundedAt)
        isActive          = try c.decodeIfPresent(Bool.self,     forKey: .isActive) ?? true
        expiryTimeoutSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .expiryTimeoutSeconds) ?? 7200
        multiCookSessionId   = try c.decodeIfPresent(UUID.self,  forKey: .multiCookSessionId)
    }

    /// Memberwise initializer (used when creating a new session in code).
    init(
        recipeId: UUID,
        recipeName: String,
        totalSteps: Int,
        stepSummaries: [StepSummary],
        currentStepIndex: Int,
        startedAt: Date,
        backgroundedAt: Date,
        isActive: Bool,
        expiryTimeoutSeconds: TimeInterval = 7200,
        multiCookSessionId: UUID? = nil
    ) {
        self.recipeId = recipeId
        self.recipeName = recipeName
        self.totalSteps = totalSteps
        self.stepSummaries = stepSummaries
        self.currentStepIndex = currentStepIndex
        self.startedAt = startedAt
        self.backgroundedAt = backgroundedAt
        self.isActive = isActive
        self.expiryTimeoutSeconds = expiryTimeoutSeconds
        self.multiCookSessionId = multiCookSessionId
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
        AppLog.info("[CookingSession] Saved session for \(recipeName) (step \(currentStepIndex + 1)/\(totalSteps)) — \(sessions.count) active")
    }

    /// Load all active sessions, clearing expired ones.
    /// Uses per-element decoding so one corrupt entry doesn't discard the rest.
    static func loadAll() -> [CookingSession] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }

        let sessions: [CookingSession]
        do {
            sessions = try JSONDecoder().decode([CookingSession].self, from: data)
        } catch {
            // Array-level decode failed — try per-element recovery
            AppLog.warn("[CookingSession] ⚠️ Array decode failed: \(error.localizedDescription)")
            if let raw = try? JSONDecoder().decode([AnyCodable].self, from: data) {
                // Re-encode each element individually and decode
                sessions = raw.compactMap { wrapper -> CookingSession? in
                    guard let elementData = try? JSONEncoder().encode(wrapper) else { return nil }
                    return try? JSONDecoder().decode(CookingSession.self, from: elementData)
                }
            } else {
                // Data is completely unrecoverable — clear it
                UserDefaults.standard.removeObject(forKey: storageKey)
                AppLog.error("[CookingSession] ❌ Cleared unrecoverable session data")
                return []
            }
        }

        let active = sessions.filter { !$0.isExpired && $0.isActive }
        if active.count != sessions.count {
            // Clean up expired/inactive/corrupt sessions
            saveAll(active)
        }
        return active
    }

    /// Passthrough wrapper to let us decode heterogeneous JSON elements one at a time.
    private struct AnyCodable: Codable {
        let value: Any

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let dict = try? container.decode([String: AnyCodableValue].self) {
                value = dict
            } else {
                value = NSNull()
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if let dict = value as? [String: AnyCodableValue] {
                try container.encode(dict)
            }
        }
    }

    /// Minimal type-erased JSON value to re-encode individual elements.
    private enum AnyCodableValue: Codable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case null
        case array([AnyCodableValue])
        case object([String: AnyCodableValue])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let v = try? container.decode(String.self) { self = .string(v) }
            else if let v = try? container.decode(Int.self) { self = .int(v) }
            else if let v = try? container.decode(Double.self) { self = .double(v) }
            else if let v = try? container.decode(Bool.self) { self = .bool(v) }
            else if let v = try? container.decode([AnyCodableValue].self) { self = .array(v) }
            else if let v = try? container.decode([String: AnyCodableValue].self) { self = .object(v) }
            else if container.decodeNil() { self = .null }
            else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type")) }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let v): try container.encode(v)
            case .int(let v):    try container.encode(v)
            case .double(let v): try container.encode(v)
            case .bool(let v):   try container.encode(v)
            case .null:          try container.encodeNil()
            case .array(let v):  try container.encode(v)
            case .object(let v): try container.encode(v)
            }
        }
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
        AppLog.info("[CookingSession] Cleared session for recipe \(recipeId.uuidString.prefix(8))… — \(sessions.count) remaining")
    }

    /// Clear all sessions.
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        AppLog.info("[CookingSession] Cleared all sessions")
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
