import Foundation

// MARK: - App Configuration
enum AppConfig {
    // OpenAI
    static let openAIAPIKey = "REDACTED_OPENAI_API_KEY"

    // Spoonacular
    static let spoonacularAPIKey = "REDACTED_SPOONACULAR_API_KEY" // Add your key at https://spoonacular.com/food-api

    // App Settings
    static let expiryWarningDays = 3
    static let maxRecipeSuggestions = 5
    static let defaultServings = 4
}
