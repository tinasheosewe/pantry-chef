import Foundation

enum CookQueueStageStatus: String, Codable, CaseIterable, Hashable {
    case pending
    case active
    case completed
    case skipped
}

struct CookQueueStage: Identifiable, Codable, Hashable {
    var id: UUID
    var recipeIDs: [UUID]
    var recipeTitleSnapshots: [String]
    var sourceMealPlanEntryIDs: [UUID]
    var addedAt: Date
    var status: CookQueueStageStatus

    init(
        id: UUID = UUID(),
        recipes: [Recipe],
        sourceMealPlanEntryIDs: [UUID] = [],
        addedAt: Date = Date(),
        status: CookQueueStageStatus = .pending
    ) {
        self.id = id
        self.recipeIDs = recipes.map(\.id)
        self.recipeTitleSnapshots = recipes.map(\.title)
        self.sourceMealPlanEntryIDs = sourceMealPlanEntryIDs
        self.addedAt = addedAt
        self.status = status
    }

    init(
        id: UUID = UUID(),
        recipeIDs: [UUID],
        recipeTitleSnapshots: [String],
        sourceMealPlanEntryIDs: [UUID] = [],
        addedAt: Date = Date(),
        status: CookQueueStageStatus = .pending
    ) {
        self.id = id
        self.recipeIDs = recipeIDs
        self.recipeTitleSnapshots = recipeTitleSnapshots
        self.sourceMealPlanEntryIDs = sourceMealPlanEntryIDs
        self.addedAt = addedAt
        self.status = status
    }

    var isParallelBatch: Bool {
        recipeIDs.count > 1
    }

    var title: String {
        switch recipeTitleSnapshots.count {
        case 0:
            return "Untitled Stage"
        case 1:
            return recipeTitleSnapshots[0]
        case 2:
            return recipeTitleSnapshots.joined(separator: " + ")
        default:
            return "\(recipeTitleSnapshots[0]) + \(recipeTitleSnapshots.count - 1) more"
        }
    }

    var subtitle: String {
        let mode = isParallelBatch ? "Parallel batch" : "Solo cook"
        return sourceMealPlanEntryIDs.isEmpty ? mode : "\(mode) • From Meal Plan"
    }
}

struct CookQueue: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var stages: [CookQueueStage]

    init(
        id: UUID = UUID(),
        name: String = "Cook Queue",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        stages: [CookQueueStage] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stages = stages
    }

    var isEmpty: Bool {
        stages.isEmpty
    }

    var pendingStageCount: Int {
        stages.filter { $0.status == .pending || $0.status == .active }.count
    }

    var currentStage: CookQueueStage? {
        stages.first(where: { $0.status == .active }) ?? stages.first(where: { $0.status == .pending })
    }

    mutating func appendStages(_ newStages: [CookQueueStage], updatedAt: Date = Date()) {
        guard !newStages.isEmpty else { return }
        stages.append(contentsOf: newStages)
        self.updatedAt = updatedAt
    }

    mutating func replaceStages(_ newStages: [CookQueueStage], updatedAt: Date = Date()) {
        stages = newStages
        self.updatedAt = updatedAt
    }

    mutating func startStage(_ stageID: UUID, updatedAt: Date = Date()) {
        var didChange = false
        for index in stages.indices {
            if stages[index].id == stageID {
                if stages[index].status != .completed && stages[index].status != .skipped {
                    stages[index].status = .active
                    didChange = true
                }
            } else if stages[index].status == .active {
                stages[index].status = .pending
                didChange = true
            }
        }
        if didChange {
            self.updatedAt = updatedAt
        }
    }

    mutating func completeStage(_ stageID: UUID, updatedAt: Date = Date()) {
        stages.removeAll { $0.id == stageID }
        self.updatedAt = updatedAt
    }

    mutating func skipStage(_ stageID: UUID, updatedAt: Date = Date()) {
        stages.removeAll { $0.id == stageID }
        self.updatedAt = updatedAt
    }

    mutating func removeStage(_ stageID: UUID, updatedAt: Date = Date()) {
        let originalCount = stages.count
        stages.removeAll { $0.id == stageID }
        if stages.count != originalCount {
            self.updatedAt = updatedAt
        }
    }

    mutating func moveStage(_ stageID: UUID, by offset: Int, updatedAt: Date = Date()) {
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        let destination = max(0, min(stages.count - 1, index + offset))
        guard destination != index else { return }

        let stage = stages.remove(at: index)
        stages.insert(stage, at: destination)
        self.updatedAt = updatedAt
    }

    mutating func bundleStageWithNext(_ stageID: UUID, updatedAt: Date = Date()) {
        guard let index = stages.firstIndex(where: { $0.id == stageID }),
              index + 1 < stages.count else {
            return
        }

        let first = stages[index]
        let second = stages[index + 1]
        guard first.status == .pending,
              second.status == .pending else {
            return
        }

        let bundledStage = CookQueueStage(
            recipeIDs: first.recipeIDs + second.recipeIDs,
            recipeTitleSnapshots: first.recipeTitleSnapshots + second.recipeTitleSnapshots,
            sourceMealPlanEntryIDs: first.sourceMealPlanEntryIDs + second.sourceMealPlanEntryIDs,
            addedAt: min(first.addedAt, second.addedAt),
            status: .pending
        )

        stages.replaceSubrange(index...index + 1, with: [bundledStage])
        self.updatedAt = updatedAt
    }

    mutating func splitStage(_ stageID: UUID, updatedAt: Date = Date()) {
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }

        let stage = stages[index]
        guard stage.recipeIDs.count > 1,
              stage.status == .pending else {
            return
        }

        let splitStages = zip(stage.recipeIDs, stage.recipeTitleSnapshots).map { recipeID, title in
            CookQueueStage(
                recipeIDs: [recipeID],
                recipeTitleSnapshots: [title],
                sourceMealPlanEntryIDs: stage.sourceMealPlanEntryIDs,
                addedAt: stage.addedAt,
                status: .pending
            )
        }

        stages.replaceSubrange(index...index, with: splitStages)
        self.updatedAt = updatedAt
    }
}

enum CookQueueStagePlacement: String, CaseIterable, Codable, Hashable {
    case newStage
    case withPrevious

    var title: String {
        switch self {
        case .newStage:
            return "New Stage"
        case .withPrevious:
            return "Cook With Previous"
        }
    }

    var subtitle: String {
        switch self {
        case .newStage:
            return "Start a separate stage in the queue."
        case .withPrevious:
            return "Run in parallel with the previous selected meal."
        }
    }
}

struct MealPlanCookQueueReviewDraft: Identifiable, Hashable {
    let entry: MealPlanEntry
    var isIncluded: Bool
    var stagePlacement: CookQueueStagePlacement

    var id: UUID { entry.id }

    init(entry: MealPlanEntry, isFirst: Bool) {
        self.entry = entry
        self.isIncluded = true
        self.stagePlacement = isFirst ? .newStage : .newStage
    }

    var recipe: Recipe? {
        entry.scaledRecipeForPlanning
    }

    var canCookWithPrevious: Bool {
        recipe != nil
    }

    var sourceSummary: String {
        "\(entry.date.formatted(date: .abbreviated, time: .omitted)) • \(entry.mealType.rawValue)"
    }
}

struct MealPlanCookQueueReviewWorkspace: Identifiable, Hashable {
    let id: UUID
    var drafts: [MealPlanCookQueueReviewDraft]
    var focusedDraftID: UUID?

    init(entries: [MealPlanEntry]) {
        self.id = UUID()
        self.drafts = entries.enumerated().map { index, entry in
            MealPlanCookQueueReviewDraft(entry: entry, isFirst: index == 0)
        }
        self.focusedDraftID = drafts.first?.id
    }

    var focusedDraft: MealPlanCookQueueReviewDraft? {
        guard let focusedDraftID else { return nil }
        return drafts.first(where: { $0.id == focusedDraftID })
    }

    var includedDrafts: [MealPlanCookQueueReviewDraft] {
        drafts.filter { $0.isIncluded && $0.recipe != nil }
    }

    var projectedStageCount: Int {
        buildStages().count
    }

    var includedRecipeCount: Int {
        includedDrafts.count
    }

    var estimatedTotalTimeText: String {
        let stages = buildStages()
        let totalSeconds = stages.reduce(0) { partialResult, stage in
            let recipes = includedDrafts
                .filter { stage.recipeIDs.contains($0.entry.recipe?.id ?? $0.entry.id) || stage.sourceMealPlanEntryIDs.contains($0.entry.id) }
                .compactMap(\.recipe)

            if stage.isParallelBatch, recipes.count > 1 {
                return partialResult + MultiRecipeScheduler.estimatedInterleavedTime(recipes: recipes)
            }

            let minutes = recipes.compactMap(\.totalTimeMinutes).reduce(0, +)
            return partialResult + (minutes * 60)
        }

        let minutes = totalSeconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h\(remainder)m"
    }

    mutating func updateDraft(_ updatedDraft: MealPlanCookQueueReviewDraft) {
        guard let index = drafts.firstIndex(where: { $0.id == updatedDraft.id }) else { return }
        drafts[index] = updatedDraft
        normalizeStagePlacements()
    }

    mutating func removeDraft(_ draftID: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return }
        drafts[index].isIncluded = false
        normalizeStagePlacements()
        if focusedDraftID == draftID {
            focusedDraftID = includedDrafts.first?.id ?? drafts.first(where: { $0.isIncluded })?.id ?? drafts.first?.id
        }
    }

    func buildStages() -> [CookQueueStage] {
        var stages: [CookQueueStage] = []

        for draft in drafts where draft.isIncluded {
            guard let recipe = draft.recipe else { continue }

            if draft.stagePlacement == .withPrevious, !stages.isEmpty {
                stages[stages.count - 1].recipeIDs.append(recipe.id)
                stages[stages.count - 1].recipeTitleSnapshots.append(recipe.title)
                stages[stages.count - 1].sourceMealPlanEntryIDs.append(draft.entry.id)
            } else {
                stages.append(CookQueueStage(recipes: [recipe], sourceMealPlanEntryIDs: [draft.entry.id]))
            }
        }

        return stages
    }

    func canDraftCookWithPrevious(_ draftID: UUID) -> Bool {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { return false }
        return drafts[..<index].contains { $0.isIncluded && $0.recipe != nil }
    }

    mutating func normalizeStagePlacements() {
        var hasIncludedDraft = false

        for index in drafts.indices {
            guard drafts[index].isIncluded else { continue }

            if !hasIncludedDraft {
                drafts[index].stagePlacement = .newStage
                hasIncludedDraft = true
                continue
            }

            if drafts[index].stagePlacement == .withPrevious {
                continue
            }

            drafts[index].stagePlacement = .newStage
        }
    }
}

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

    /// When the session moved into background mode.
    let backgroundedAt: Date?

    /// Whether the session is still active.
    var isActive: Bool

    /// Auto-expire timeout in seconds (default: 2 hours).
    var expiryTimeoutSeconds: TimeInterval

    /// Whether this is part of a multi-recipe cook session.
    var multiCookSessionId: UUID?

    /// Optional queue metadata so resumed sessions can continue their queue stage.
    var queueId: UUID?
    var queueStageId: UUID?

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
        case queueId, queueStageId
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
        backgroundedAt    = try c.decodeIfPresent(Date.self,     forKey: .backgroundedAt)
        isActive          = try c.decodeIfPresent(Bool.self,     forKey: .isActive) ?? true
        expiryTimeoutSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .expiryTimeoutSeconds) ?? AppConfig.sessionExpiryTimeout
        multiCookSessionId   = try c.decodeIfPresent(UUID.self,  forKey: .multiCookSessionId)
        queueId             = try c.decodeIfPresent(UUID.self,   forKey: .queueId)
        queueStageId        = try c.decodeIfPresent(UUID.self,   forKey: .queueStageId)
    }

    /// Memberwise initializer (used when creating a new session in code).
    init(
        recipeId: UUID,
        recipeName: String,
        totalSteps: Int,
        stepSummaries: [StepSummary],
        currentStepIndex: Int,
        startedAt: Date,
        backgroundedAt: Date? = nil,
        isActive: Bool,
        expiryTimeoutSeconds: TimeInterval = AppConfig.sessionExpiryTimeout,
        multiCookSessionId: UUID? = nil,
        queueId: UUID? = nil,
        queueStageId: UUID? = nil
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
        self.queueId = queueId
        self.queueStageId = queueStageId
    }

    // MARK: - Computed

    var isExpired: Bool {
        guard let backgroundedAt else { return false }
        return Date().timeIntervalSince(backgroundedAt) > expiryTimeoutSeconds
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

    // MARK: - Internal

    private static func saveAll(_ sessions: [CookingSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

}

// MARK: - Multi-Cook Session Persistence
//
// Persists the LLM-generated block schedule and current progress so the
// mini player can appear and multi-cook can be resumed after backgrounding.

struct MultiCookSession: Codable, Identifiable, Hashable {
    let id: UUID
    let recipeIDs: [UUID]
    let recipeNames: [String]
    let blocks: [MultiRecipeScheduler.ScheduledBlock]
    var currentBlockIndex: Int
    let startedAt: Date
    var lastUpdatedAt: Date
    var queueID: UUID?
    var queueStageID: UUID?

    static func == (lhs: MultiCookSession, rhs: MultiCookSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var totalBlocks: Int { blocks.count }
    var progress: Double {
        guard totalBlocks > 0 else { return 0 }
        return Double(currentBlockIndex + 1) / Double(totalBlocks)
    }

    var isExpired: Bool {
        Date().timeIntervalSince(lastUpdatedAt) > AppConfig.sessionExpiryTimeout
    }

    // MARK: - Persistence

    private static let storageKey = "active_multi_cook_sessions"

    func save() {
        var sessions = Self.loadAll()
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx] = self
        } else {
            sessions.append(self)
        }
        Self.saveAll(sessions)
    }

    static func loadAll() -> [MultiCookSession] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        let sessions = (try? JSONDecoder().decode([MultiCookSession].self, from: data)) ?? []
        let active = sessions.filter { !$0.isExpired }
        if active.count != sessions.count { saveAll(active) }
        return active
    }

    static func load(id: UUID) -> MultiCookSession? {
        loadAll().first { $0.id == id }
    }

    static func clear(id: UUID) {
        var sessions = loadAll()
        sessions.removeAll { $0.id == id }
        saveAll(sessions)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func saveAll(_ sessions: [MultiCookSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
