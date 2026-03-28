import Foundation

// MARK: - App Configuration
enum AppConfig {
    private static let missingPrefix = "__MISSING_CONFIG__"

    // OpenAI
    static let openAIAPIKey = requiredConfigValue("OPENAI_API_KEY")
    static let sentryDSN = optionalConfigValue("SENTRY_DSN")

    #if DEBUG
    static let runtimeEnvironment = "debug"
    #else
    static let runtimeEnvironment = "release"
    #endif

    // App Settings
    static let expiryWarningDays = 3
    static let maxRecipeSuggestions = 5
    static let defaultServings = 4

    // Session & Background
    /// How long a backgrounded cooking session stays valid (seconds).
    static let sessionExpiryTimeout: TimeInterval = 7200 // 2 hours

    // Deep-link retry
    static let deepLinkMaxRetries = 20
    static let deepLinkRetryDelayMs = 200

    // Scheduling
    /// Max attention-effort points a cook can handle in one time block.
    static let effortBudget = 3
    /// Default step duration when no timer or estimate is available (seconds).
    static let defaultStepDurationSeconds = 90
    /// Threshold (seconds) at which a running timer is shown in "expiring" style.
    static let timerExpiryThresholdSeconds = 10

    // AI Networking
    static let aiMaxRetries = 3
    static let aiChatTimeoutSeconds: TimeInterval = 30
    static let aiURLFetchTimeoutSeconds: TimeInterval = 15
    static let aiMaxRecipeTextChars = 12_000
    static let aiBackoffMultiplier: Double = 1.5
    static let aiTopSubstitutionCount = 3

    // UI Limits
    static let pantrySearchMaxResults = 6
    static let facetOptionsMaxShown = 3
    static let matchingItemsDropdownMax = 8

    static func isMissing(_ value: String) -> Bool {
        value.hasPrefix(missingPrefix)
    }

    private static func requiredConfigValue(_ key: String) -> String {
        if let env = ProcessInfo.processInfo.environment[key], !env.isEmpty {
            return env
        }

        if let plist = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }

        return "\(missingPrefix):\(key)"
    }

    private static func optionalConfigValue(_ key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key] {
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let plist = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
                return nil
            }
            return trimmed
        }

        return nil
    }
}
