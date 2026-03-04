import Foundation

// MARK: - AI Response Models

struct SubstitutionSuggestion: Identifiable, Codable {
    let id: UUID
    let originalIngredient: String
    let substituteName: String
    let ratio: String // e.g., "1:1", "use half the amount"
    let tasteImpact: String
    let textureImpact: String
    let nutritionImpact: String
    let confidence: Double // 0-1

    init(
        id: UUID = UUID(),
        originalIngredient: String,
        substituteName: String,
        ratio: String,
        tasteImpact: String,
        textureImpact: String,
        nutritionImpact: String,
        confidence: Double
    ) {
        self.id = id
        self.originalIngredient = originalIngredient
        self.substituteName = substituteName
        self.ratio = ratio
        self.tasteImpact = tasteImpact
        self.textureImpact = textureImpact
        self.nutritionImpact = nutritionImpact
        self.confidence = confidence
    }

    var confidenceLabel: String {
        switch confidence {
        case 0.8...1.0: return "Excellent"
        case 0.6..<0.8: return "Good"
        case 0.4..<0.6: return "Decent"
        default: return "Experimental"
        }
    }

    static let sample = SubstitutionSuggestion(
        originalIngredient: "Sour Cream",
        substituteName: "Greek Yogurt",
        ratio: "1:1",
        tasteImpact: "Slightly tangier",
        textureImpact: "Very similar, slightly thinner",
        nutritionImpact: "40% fewer calories, higher protein",
        confidence: 0.92
    )
}

struct HealthierSuggestion: Identifiable, Codable {
    let id: UUID
    let originalRecipeTitle: String
    let suggestions: [HealthTweak]
    let estimatedCalorieReduction: Int?
    let overallImpact: String

    init(
        id: UUID = UUID(),
        originalRecipeTitle: String,
        suggestions: [HealthTweak],
        estimatedCalorieReduction: Int? = nil,
        overallImpact: String
    ) {
        self.id = id
        self.originalRecipeTitle = originalRecipeTitle
        self.suggestions = suggestions
        self.estimatedCalorieReduction = estimatedCalorieReduction
        self.overallImpact = overallImpact
    }

    static let sample = HealthierSuggestion(
        originalRecipeTitle: "Chicken Stir Fry",
        suggestions: [
            HealthTweak(change: "Use coconut aminos instead of soy sauce", benefit: "60% less sodium"),
            HealthTweak(change: "Add broccoli and snap peas", benefit: "More fiber and vitamins"),
            HealthTweak(change: "Use brown rice instead of white", benefit: "More fiber, lower glycemic index"),
        ],
        estimatedCalorieReduction: 45,
        overallImpact: "Lower sodium, more fiber, similar taste profile"
    )
}

struct HealthTweak: Identifiable, Codable {
    let id: UUID
    let change: String
    let benefit: String

    init(id: UUID = UUID(), change: String, benefit: String) {
        self.id = id
        self.change = change
        self.benefit = benefit
    }
}

// MARK: - Chat Message
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date

    enum Role {
        case user
        case assistant
    }

    init(role: Role, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - Barcode Lookup Result
struct BarcodeLookupResult: Codable {
    let barcode: String
    let productName: String
    let brand: String?
    let category: FoodCategory?
    let imageURL: String?
}

// MARK: - Recipe Import Result
struct RecipeImportResult: Codable {
    let title: String
    let description: String?
    let ingredients: [Ingredient]
    let steps: [RecipeStep]
    let servings: Int?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let imageURL: String?
    let dietaryTags: [DietaryTag]?

    func toRecipe() -> Recipe {
        Recipe(
            title: title,
            description: description,
            ingredients: ingredients,
            steps: steps,
            servings: servings ?? 4,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            dietaryTags: dietaryTags ?? [],
            imageURL: imageURL
        )
    }
}
