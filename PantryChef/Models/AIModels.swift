import Foundation

// MARK: - AI boundary DTOs
//
// The only AI result/parse types the live app uses (makeItHealthier / modifyRecipe).
// The legacy Recipe-shaped models and their conversions were removed with the
// legacy domain; the parsed `RawFullRecipe` maps straight to `Dish` via
// `RawFullRecipe.toDish` (Helpers/AIDishMapping.swift).

// MARK: Make-it-healthier result

struct HealthierSuggestion: Identifiable, Codable {
    let id: UUID
    let originalRecipeTitle: String
    let suggestions: [HealthTweak]
    let estimatedCalorieReduction: Int?
    let overallImpact: String

    init(id: UUID = UUID(), originalRecipeTitle: String, suggestions: [HealthTweak],
         estimatedCalorieReduction: Int? = nil, overallImpact: String) {
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
        self.id = id; self.change = change; self.benefit = benefit
    }
}

// MARK: Raw decode types (mirror the LLM structured-output JSON shape)

struct RawHealthierResult: Decodable {
    let suggestions: [RawHealthTweakItem]
    let estimatedCalorieReduction: Int?
    let overallImpact: String

    func toHealthierSuggestion(recipeTitle: String) -> HealthierSuggestion {
        HealthierSuggestion(
            originalRecipeTitle: recipeTitle,
            suggestions: suggestions.map { HealthTweak(change: $0.change, benefit: $0.benefit) },
            estimatedCalorieReduction: estimatedCalorieReduction,
            overallImpact: overallImpact
        )
    }
}

struct RawHealthTweakItem: Decodable {
    let change: String
    let benefit: String
}

/// Discriminated union: a modified recipe, or a rejection for off-topic requests.
struct RawRecipeOrRejection: Decodable {
    let rejected: Bool
    let rejectionReason: String?
    let rejectionMessage: String?
    let recipe: RawFullRecipe?
}

struct RawFullRecipe: Decodable {
    let title: String
    let description: String?
    let ingredients: [RawIngredient]
    let steps: [RawStep]
    let servings: Int?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let dietaryTags: [String]?
    let difficulty: Int?
    let mealType: String?
    let cuisine: String?
    let calories: Int?
    let protein: Double?
    let carbohydrates: Double?
    let fat: Double?
    let fiber: Double?
    let sugar: Double?
    let sodium: Double?
}

struct RawIngredient: Decodable {
    let name: String
    let quantity: Double
    let unit: String
    let category: String
}

struct RawStep: Decodable {
    let stepNumber: Int
    let instruction: String
    let timerMinutes: Int?
    let estimatedDurationSeconds: Int?
    let tasks: [RawTask]
}

struct RawTask: Decodable {
    let taskIndex: Int
    let action: String
    let ingredient: String?
    let durationSeconds: Int
    let type: String
    /// "prep" | "cook" | "finish" — the model now tags this; optional so older or
    /// off-path responses still decode (the mapper falls back to text inference).
    let phase: String?
    let effort: String
    let requiresEquipment: String?
    let dependsOn: [Int]
}
