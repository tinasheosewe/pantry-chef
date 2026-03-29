import Foundation
import SwiftUI

// MARK: - Use-Up-Ingredients Models

struct RecipeNameSuggestion: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let confidenceScore: Int
    let confidenceReason: String

    init(id: UUID = UUID(), name: String, description: String, confidenceScore: Int, confidenceReason: String) {
        self.id = id
        self.name = name
        self.description = description
        self.confidenceScore = max(1, min(5, confidenceScore))
        self.confidenceReason = confidenceReason
    }
}

struct RecipeNameSuggestionsResult: Codable {
    let suggestions: [RecipeNameSuggestion]
    let message: String?
}

enum ConfidenceTier {
    case perfectMatch
    case greatFit
    case worthATry
    case creativeStretch

    init(score: Int) {
        switch max(2, min(5, score)) {
        case 5: self = .perfectMatch
        case 4: self = .greatFit
        case 3: self = .worthATry
        default: self = .creativeStretch
        }
    }

    var label: String {
        switch self {
        case .perfectMatch: return "Perfect Match"
        case .greatFit: return "Great Fit"
        case .worthATry: return "Worth a Try"
        case .creativeStretch: return "Creative Stretch"
        }
    }

    var icon: String {
        switch self {
        case .perfectMatch: return "star.fill"
        case .greatFit: return "hand.thumbsup.fill"
        case .worthATry: return "lightbulb.fill"
        case .creativeStretch: return "flask.fill"
        }
    }

    var emoji: String {
        switch self {
        case .perfectMatch: return "🔥"
        case .greatFit: return "👍"
        case .worthATry: return "💡"
        case .creativeStretch: return "🧪"
        }
    }

    var color: Color {
        switch self {
        case .perfectMatch: return .green
        case .greatFit: return .teal
        case .worthATry: return .yellow
        case .creativeStretch: return .orange
        }
    }
}

// MARK: - AI Response Models

struct SubstitutionSuggestion: Identifiable, Codable {
    let id: UUID
    let originalIngredient: String
    let substituteName: String
    let ratio: String
    let tasteImpact: String
    let textureImpact: String
    let cookingImpact: String
    let nutritionImpact: String
    let notes: String?
    var inPantry: Bool

    init(
        id: UUID = UUID(),
        originalIngredient: String,
        substituteName: String,
        ratio: String,
        tasteImpact: String,
        textureImpact: String,
        cookingImpact: String,
        nutritionImpact: String,
        notes: String? = nil,
        inPantry: Bool = false
    ) {
        self.id = id
        self.originalIngredient = originalIngredient
        self.substituteName = substituteName
        self.ratio = ratio
        self.tasteImpact = tasteImpact
        self.textureImpact = textureImpact
        self.cookingImpact = cookingImpact
        self.nutritionImpact = nutritionImpact
        self.notes = notes
        self.inPantry = inPantry
    }

    static let sample = SubstitutionSuggestion(
        originalIngredient: "Sour Cream",
        substituteName: "Greek Yogurt",
        ratio: "1:1",
        tasteImpact: "Slightly tangier",
        textureImpact: "Very similar, slightly thinner",
        cookingImpact: "Slight Adjustment",
        nutritionImpact: "40% fewer calories, higher protein",
        notes: "Works best in dips and baked sauces."
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

// MARK: - Recipe Import Result
struct RecipeImportResult: Codable {
    let title: String
    let description: String?
    let ingredients: [Ingredient]
    let steps: [RecipeStep]
    let servings: Int?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let dietaryTags: [DietaryTag]?
    let difficulty: DifficultyLevel?
    let mealType: MealType?
    let cuisine: CuisineType?
    let nutrition: NutritionInfo?

    func toRecipe(source: RecipeSource = .user) -> Recipe {
        Recipe(
            title: title,
            description: description,
            ingredients: ingredients,
            steps: steps,
            servings: servings ?? 4,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            difficulty: difficulty ?? .easy,
            dietaryTags: dietaryTags ?? [],
            mealType: mealType,
            cuisine: cuisine,
            source: source,
            nutrition: nutrition,
            sourceURL: nil
        )
        .completed()
    }
}

// MARK: - Raw Import Types (matched to LLM structured output schema)
// These mirror the JSON shape the LLM returns, using simple types only.
// They are converted to app model types via toRecipeImportResult().

struct RawImportResult: Decodable {
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

    func toRecipeImportResult() -> RecipeImportResult {
        let convertedIngredients = RecipeConversion.convertIngredients(ingredients)
        let convertedSteps = RecipeConversion.convertSteps(steps)
        let convertedTags = dietaryTags?.compactMap { DietaryTag(rawValue: $0) }
        let convertedDifficulty = difficulty.flatMap { DifficultyLevel(rawValue: $0) }
        let convertedMealType = MealType.parse(mealType)
        let convertedCuisine = CuisineType.parse(cuisine)
        let nutrition = nutritionInfo()

        return RecipeImportResult(
            title: title,
            description: description,
            ingredients: convertedIngredients,
            steps: convertedSteps,
            servings: servings,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            dietaryTags: convertedTags,
            difficulty: convertedDifficulty,
            mealType: convertedMealType,
            cuisine: convertedCuisine,
            nutrition: nutrition
        )
    }

    private func nutritionInfo() -> NutritionInfo? {
        guard calories != nil || protein != nil || carbohydrates != nil || fat != nil || fiber != nil || sugar != nil || sodium != nil else {
            return nil
        }
        return NutritionInfo(
            calories: calories ?? 0,
            protein: protein ?? 0,
            carbohydrates: carbohydrates ?? 0,
            fat: fat ?? 0,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium
        )
    }
}

// MARK: - Raw Full Recipe (for generation, modification, suggestions)

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

    func toRecipe(source: RecipeSource = .aiGenerated, preserving original: Recipe? = nil) -> Recipe {
        let convertedIngredients = RecipeConversion.convertIngredients(ingredients)
        let convertedSteps = RecipeConversion.convertSteps(steps)
        let convertedTags = dietaryTags?.compactMap { DietaryTag(rawValue: $0) } ?? []
        let diff = DifficultyLevel(rawValue: difficulty ?? 2) ?? .easy
        let mt = MealType.parse(mealType)
        let cu = CuisineType.parse(cuisine)
        let nutrition: NutritionInfo? = (calories != nil || protein != nil || carbohydrates != nil || fat != nil || fiber != nil || sugar != nil || sodium != nil) ? NutritionInfo(
            calories: calories ?? 0,
            protein: protein ?? 0,
            carbohydrates: carbohydrates ?? 0,
            fat: fat ?? 0,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium
        ) : nil

        return Recipe(
            id: original?.id ?? UUID(),
            title: title,
            description: description,
            ingredients: convertedIngredients,
            steps: convertedSteps,
            servings: servings ?? original?.servings ?? 4,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            difficulty: diff,
            dietaryTags: convertedTags,
            mealType: mt ?? original?.mealType,
            cuisine: cu ?? original?.cuisine,
            source: source,
            nutrition: nutrition ?? original?.nutrition,
            sourceURL: original?.sourceURL,
            isFavorite: original?.isFavorite ?? false,
            dateAdded: original?.dateAdded ?? Date(),
            timesCooked: original?.timesCooked ?? 0,
            rating: original?.rating
        )
        .completed()
    }
}

// MARK: - Raw Wrapper Types (structured output requires top-level objects)

struct RawRecipeArray: Decodable { let recipes: [RawFullRecipe] }
struct RawShoppingList: Decodable { let items: [RawShoppingItem] }
struct RawDurationList: Decodable { let durations: [RawStepDuration] }
struct RawStatusMessages: Decodable { let messages: [String] }
struct RawIngredientResolutionBatch: Decodable { let decisions: [IngredientResolutionDecision] }

// MARK: - Raw Simple Types

struct RawShoppingItem: Decodable {
    let name: String
    let quantity: Double?
    let unit: String?
    let category: String

    func toShoppingItem() -> ShoppingItem {
        let parsedUnit = unit.flatMap { MeasurementUnit(rawValue: $0) }
        let parsedCategory = FoodCategory(rawValue: category) ?? .other
        return ShoppingItem(
            name: name,
            quantity: quantity,
            unit: parsedUnit,
            category: parsedCategory,
            catalogItemID: IngredientMatcher.resolvedCatalogItemID(for: name)
        )
    }
}

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

struct RawStepDuration: Decodable {
    let stepNumber: Int
    let estimatedDurationSeconds: Int
}

// MARK: - Shared Conversion Helpers

enum RecipeConversion {
    /// Convert RawIngredient array → Ingredient array.
    static func convertIngredients(_ raw: [RawIngredient]) -> [Ingredient] {
        raw.map { r in
            Ingredient(
                name: r.name,
                quantity: r.quantity,
                unit: MeasurementUnit(rawValue: r.unit),
                category: FoodCategory(rawValue: r.category) ?? .other
            )
        }
    }

    /// Convert RawStep array → RecipeStep array with proper task dependency resolution.
    static func convertSteps(_ rawSteps: [RawStep]) -> [RecipeStep] {
        var indexToUUID: [Int: UUID] = [:]
        for step in rawSteps {
            for task in step.tasks {
                indexToUUID[task.taskIndex] = UUID()
            }
        }

        return rawSteps.map { raw in
            let tasks = raw.tasks.map { rawTask in
                let taskID = indexToUUID[rawTask.taskIndex] ?? UUID()
                let deps = rawTask.dependsOn.compactMap { indexToUUID[$0] }
                return StepTask(
                    id: taskID,
                    action: CookingAction.from(string: rawTask.action),
                    ingredient: rawTask.ingredient,
                    durationSeconds: rawTask.durationSeconds,
                    type: rawTask.type == "passive" ? .passive : .active,
                    requiresEquipment: rawTask.requiresEquipment,
                    effort: EffortLevel(from: rawTask.effort),
                    dependsOn: deps
                )
            }
            return RecipeStep(
                stepNumber: raw.stepNumber,
                instruction: raw.instruction,
                timerMinutes: raw.timerMinutes,
                estimatedDurationSeconds: raw.estimatedDurationSeconds,
                tasks: tasks
            )
        }
    }
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
    let effort: String
    let requiresEquipment: String?
    let dependsOn: [Int]
}

// MARK: - CookingAction string parser

extension CookingAction {
    /// Parse a free-form action string from the LLM into a CookingAction.
    static func from(string: String) -> CookingAction {
        switch string.lowercased().trimmingCharacters(in: .whitespaces) {
        case "dice":                                return .cut(.dice)
        case "mince":                               return .cut(.mince)
        case "julienne":                            return .cut(.julienne)
        case "slice":                               return .cut(.slice)
        case "chop", "cut":                         return .cut(.chop)
        case "rough chop", "roughly chop":          return .cut(.rough)
        case "halve":                               return .cut(.halve)
        case "peel":                                return .peel
        case "measure":                             return .measure
        case "mix", "combine", "whisk", "fold", "stir": return .mix
        case "marinate":                            return .marinate
        case "season":                              return .season
        case "heat", "preheat", "warm":             return .heat
        case "saute", "sauté":                      return .saute
        case "boil":                                return .boil
        case "simmer":                              return .simmer
        case "pan fry", "pan-fry":                  return .fry(.pan)
        case "deep fry", "deep-fry":                return .fry(.deep)
        case "stir fry", "stir-fry", "wok":         return .fry(.stir)
        case "fry":                                 return .fry(.pan)
        case "bake":                                return .bake
        case "roast":                               return .roast
        case "grill", "broil", "char":              return .grill
        case "steam":                               return .steam
        case "scramble":                            return .scramble
        case "plate":                               return .plate
        case "garnish", "top", "sprinkle":          return .garnish
        case "rest", "cool":                        return .rest
        case "serve":                               return .serve
        case "toss", "shake":                       return .toss
        default:                                    return .other(string)
        }
    }
}
