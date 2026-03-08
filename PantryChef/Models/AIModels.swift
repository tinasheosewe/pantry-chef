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

    func toRecipeImportResult() -> RecipeImportResult {
        // Build a taskIndex→UUID lookup so we can wire dependsOn correctly
        var indexToUUID: [Int: UUID] = [:]
        // First pass: assign UUIDs
        for step in steps {
            for task in step.tasks {
                indexToUUID[task.taskIndex] = UUID()
            }
        }

        let convertedIngredients = ingredients.map { raw in
            Ingredient(
                name: raw.name,
                quantity: raw.quantity,
                unit: MeasurementUnit(rawValue: raw.unit),
                category: FoodCategory(rawValue: raw.category) ?? .other
            )
        }

        let convertedSteps = steps.map { raw in
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

        let convertedTags = dietaryTags?.compactMap { DietaryTag(rawValue: $0) }

        return RecipeImportResult(
            title: title,
            description: description,
            ingredients: convertedIngredients,
            steps: convertedSteps,
            servings: servings,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            imageURL: nil,
            dietaryTags: convertedTags
        )
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
