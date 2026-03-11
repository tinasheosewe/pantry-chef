import Foundation

// MARK: - App Configuration
enum AppConfig {
    private static let missingPrefix = "__MISSING_CONFIG__"

    // OpenAI
    static let openAIAPIKey = requiredConfigValue("OPENAI_API_KEY")

    // Spoonacular
    static let spoonacularAPIKey = requiredConfigValue("SPOONACULAR_API_KEY")

    // App Settings
    static let expiryWarningDays = 3
    static let maxRecipeSuggestions = 5
    static let defaultServings = 4
    static let enablePerformanceLogging: Bool = {
        let value = ProcessInfo.processInfo.environment["PANTRYCHEF_PERF_LOGS"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }()

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

        PerfLog.event("[AppConfig] Missing required config value: \(key)")
        return "\(missingPrefix):\(key)"
    }
}
