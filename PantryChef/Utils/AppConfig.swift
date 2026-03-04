import Foundation

// MARK: - App Configuration
// Replace these with your actual keys before running
enum AppConfig {
    // Supabase
    static let supabaseURL = "https://YOUR_PROJECT.supabase.co"
    static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"

    // OpenAI
    static let openAIAPIKey = "YOUR_OPENAI_API_KEY"

    // App Settings
    static let expiryWarningDays = 3
    static let maxRecipeSuggestions = 5
    static let defaultServings = 4
}
