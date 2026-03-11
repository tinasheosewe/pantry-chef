import Foundation

// MARK: - Ingredient
struct Ingredient: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var quantity: Double
    var unit: MeasurementUnit?
    var category: FoodCategory
    var isOptional: Bool
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double = 1,
        unit: MeasurementUnit? = nil,
        category: FoodCategory = .other,
        isOptional: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.isOptional = isOptional
        self.notes = notes
    }

    var displayText: String {
        let unitStr = unit?.rawValue ?? ""
        if quantity == quantity.rounded() {
            return "\(Int(quantity)) \(unitStr) \(name)".trimmingCharacters(in: .whitespaces)
        }
        return String(format: "%.1f %@ %@", quantity, unitStr, name).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Recipe Step
struct RecipeStep: Identifiable, Codable, Hashable {
    var id: UUID
    var stepNumber: Int
    var instruction: String
    var timerMinutes: Int?
    var tip: String?
    /// Realistic wall-clock duration for this step in seconds.
    /// Used for deterministic background notification scheduling.
    var estimatedDurationSeconds: Int?
    /// Atomic tasks within this step for cross-recipe merging/scheduling.
    var tasks: [StepTask]

    init(
        id: UUID = UUID(),
        stepNumber: Int,
        instruction: String,
        timerMinutes: Int? = nil,
        tip: String? = nil,
        estimatedDurationSeconds: Int? = nil,
        tasks: [StepTask] = []
    ) {
        self.id = id
        self.stepNumber = stepNumber
        self.instruction = instruction
        self.timerMinutes = timerMinutes
        self.tip = tip
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.tasks = tasks
    }

    /// Best estimate of this step's duration in seconds.
    /// Priority: estimatedDurationSeconds > timerMinutes*60 > 90s default.
    var effectiveDurationSeconds: Int {
        if let est = estimatedDurationSeconds { return est }
        if let timer = timerMinutes { return timer * 60 }
        return 90 // sensible default for an untimed prep step
    }
}

// MARK: - Nutrition Info
struct NutritionInfo: Codable, Hashable {
    var calories: Int
    var protein: Double // grams
    var carbohydrates: Double // grams
    var fat: Double // grams
    var fiber: Double? // grams
    var sugar: Double? // grams
    var sodium: Double? // mg

    var macroSummary: String {
        "P: \(Int(protein))g  C: \(Int(carbohydrates))g  F: \(Int(fat))g"
    }

    static let sample = NutritionInfo(
        calories: 450,
        protein: 35,
        carbohydrates: 40,
        fat: 15,
        fiber: 5,
        sugar: 8,
        sodium: 600
    )
}

// MARK: - Recipe
struct Recipe: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var description: String?
    var ingredients: [Ingredient]
    var steps: [RecipeStep]
    var servings: Int
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var difficulty: DifficultyLevel
    var dietaryTags: [DietaryTag]
    var mealType: MealType?
    var cuisine: CuisineType?
    var source: RecipeSource
    var nutrition: NutritionInfo?
    var imageURL: String?
    var sourceURL: String?
    var isFavorite: Bool
    var dateAdded: Date
    var timesCooked: Int
    var rating: Int? // 1-5

    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        ingredients: [Ingredient] = [],
        steps: [RecipeStep] = [],
        servings: Int = 4,
        prepTimeMinutes: Int? = nil,
        cookTimeMinutes: Int? = nil,
        difficulty: DifficultyLevel = .easy,
        dietaryTags: [DietaryTag] = [],
        mealType: MealType? = nil,
        cuisine: CuisineType? = nil,
        source: RecipeSource = .user,
        nutrition: NutritionInfo? = nil,
        imageURL: String? = nil,
        sourceURL: String? = nil,
        isFavorite: Bool = false,
        dateAdded: Date = Date(),
        timesCooked: Int = 0,
        rating: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.ingredients = ingredients
        self.steps = steps
        self.servings = servings
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.difficulty = difficulty
        self.dietaryTags = dietaryTags
        self.mealType = mealType
        self.cuisine = cuisine
        self.source = source
        self.nutrition = nutrition
        self.imageURL = imageURL
        self.sourceURL = sourceURL
        self.isFavorite = isFavorite
        self.dateAdded = dateAdded
        self.timesCooked = timesCooked
        self.rating = rating
    }

    var totalTimeMinutes: Int? {
        guard let prep = prepTimeMinutes, let cook = cookTimeMinutes else {
            return prepTimeMinutes ?? cookTimeMinutes
        }
        return prep + cook
    }

    var totalTimeDisplay: String {
        guard let total = totalTimeMinutes else { return "N/A" }
        if total < 60 { return "\(total) min" }
        let hours = total / 60
        let mins = total % 60
        return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
    }

    func scaled(to newServings: Int) -> Recipe {
        guard servings > 0, newServings > 0 else { return self }
        let factor = Double(newServings) / Double(servings)
        var scaled = self
        scaled.servings = newServings
        scaled.ingredients = ingredients.map { ingredient in
            var newIngredient = ingredient
            newIngredient.quantity = ingredient.quantity * factor
            return newIngredient
        }
        if let nutrition {
            scaled.nutrition = NutritionInfo(
                calories: Int(Double(nutrition.calories) * factor),
                protein: nutrition.protein * factor,
                carbohydrates: nutrition.carbohydrates * factor,
                fat: nutrition.fat * factor,
                fiber: nutrition.fiber.map { $0 * factor },
                sugar: nutrition.sugar.map { $0 * factor },
                sodium: nutrition.sodium.map { $0 * factor }
            )
        }
        return scaled
    }

    // MARK: - Pantry Matching
    func pantryMatch(pantry: [PantryItem]) -> PantryMatchResult {
        IngredientMatcher.match(recipe: self, pantry: pantry)
    }

    // MARK: - Stable IDs for built-in recipes (survive app restarts for CookingSession matching)
    static let stirFryId  = UUID(uuidString: "A1B2C3D4-0001-0001-0001-AABBCCDDEEFF")!
    static let avocadoId  = UUID(uuidString: "A1B2C3D4-0002-0002-0002-AABBCCDDEEFF")!
    static let friedRiceId = UUID(uuidString: "A1B2C3D4-0003-0003-0003-AABBCCDDEEFF")!

    // MARK: - Stable task IDs for dependency wiring (built-in recipes)
    // Stir Fry tasks
    private static let sf0 = UUID(uuidString: "10000000-0000-0000-0000-000000000000")!  // boil rice
    private static let sf1 = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!  // slice chicken
    private static let sf2 = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!  // dice onion
    private static let sf3 = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!  // mince garlic
    private static let sf4 = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!  // slice bell pepper
    private static let sf5 = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!  // heat oil
    private static let sf6 = UUID(uuidString: "10000000-0000-0000-0000-000000000006")!  // fry chicken
    private static let sf7 = UUID(uuidString: "10000000-0000-0000-0000-000000000007")!  // sauté vegetables
    private static let sf8 = UUID(uuidString: "10000000-0000-0000-0000-000000000008")!  // toss soy sauce
    private static let sf9 = UUID(uuidString: "10000000-0000-0000-0000-000000000009")!  // plate

    // MARK: - Sample Data
    static let sample = Recipe(
        id: stirFryId,
        title: "Simple Chicken Stir Fry",
        description: "A quick and healthy chicken stir fry with vegetables.",
        ingredients: [
            Ingredient(name: "Chicken Breast", quantity: 500, unit: .gram, category: .protein),
            Ingredient(name: "Onion", quantity: 1, unit: .whole, category: .produce),
            Ingredient(name: "Garlic", quantity: 3, unit: .clove, category: .produce),
            Ingredient(name: "Soy Sauce", quantity: 2, unit: .tablespoon, category: .condiments),
            Ingredient(name: "Olive Oil", quantity: 2, unit: .tablespoon, category: .oils),
            Ingredient(name: "Rice", quantity: 2, unit: .cup, category: .grains),
            Ingredient(name: "Bell Pepper", quantity: 1, unit: .whole, category: .produce),
            Ingredient(name: "Salt", quantity: 1, unit: .pinch, category: .spices, isOptional: true),
        ],
        steps: [
            RecipeStep(stepNumber: 1, instruction: "Cook the rice according to package directions.", timerMinutes: 15, estimatedDurationSeconds: 900, tasks: [
                StepTask(id: sf0, action: .boil, ingredient: "rice", quantity: 2, unit: "cup", durationSeconds: 900, type: .passive, requiresEquipment: "stovetop", dependsOn: [])
            ]),
            RecipeStep(stepNumber: 2, instruction: "Slice the chicken breast into thin strips.", estimatedDurationSeconds: 120, tasks: [
                StepTask(id: sf1, action: .cut(.slice), ingredient: "chicken breast", quantity: 500, unit: "g", durationSeconds: 120, type: .active, requiresEquipment: "cutting board", effort: .medium, dependsOn: [])
            ]),
            RecipeStep(stepNumber: 3, instruction: "Dice the onion, mince the garlic, and slice the bell pepper.",
                       tip: "Dice means cutting into small cubes, about 1/4 inch.", estimatedDurationSeconds: 180, tasks: [
                StepTask(id: sf2, action: .cut(.dice), ingredient: "onion", quantity: 1, unit: "whole", durationSeconds: 60, type: .active, requiresEquipment: "cutting board", dependsOn: []),
                StepTask(id: sf3, action: .cut(.mince), ingredient: "garlic", quantity: 3, unit: "clove", durationSeconds: 30, type: .active, requiresEquipment: "cutting board", dependsOn: []),
                StepTask(id: sf4, action: .cut(.slice), ingredient: "bell pepper", quantity: 1, unit: "whole", durationSeconds: 60, type: .active, requiresEquipment: "cutting board", dependsOn: [])
            ]),
            RecipeStep(stepNumber: 4, instruction: "Heat olive oil in a large pan over medium-high heat.", estimatedDurationSeconds: 60, tasks: [
                StepTask(id: sf5, action: .heat, ingredient: "olive oil", quantity: 2, unit: "tbsp", durationSeconds: 60, type: .active, requiresEquipment: "stovetop", dependsOn: [])
            ]),
            RecipeStep(stepNumber: 5, instruction: "Cook the chicken strips until golden brown, about 5-6 minutes.", timerMinutes: 6, estimatedDurationSeconds: 360, tasks: [
                StepTask(id: sf6, action: .fry(.pan), ingredient: "chicken", quantity: 500, unit: "g", durationSeconds: 360, type: .active, requiresEquipment: "stovetop", effort: .medium, dependsOn: [sf1, sf5])
            ]),
            RecipeStep(stepNumber: 6, instruction: "Add onion, garlic, and bell pepper. Cook for 3 minutes.", timerMinutes: 3, estimatedDurationSeconds: 180, tasks: [
                StepTask(id: sf7, action: .saute, ingredient: "vegetables", durationSeconds: 180, type: .active, requiresEquipment: "stovetop", effort: .medium, dependsOn: [sf2, sf3, sf4, sf6])
            ]),
            RecipeStep(stepNumber: 7, instruction: "Add soy sauce and toss everything together. Cook 1 more minute.", timerMinutes: 1, estimatedDurationSeconds: 60, tasks: [
                StepTask(id: sf8, action: .toss, ingredient: "soy sauce", quantity: 2, unit: "tbsp", durationSeconds: 60, type: .active, requiresEquipment: "stovetop", dependsOn: [sf7])
            ]),
            RecipeStep(stepNumber: 8, instruction: "Serve the stir fry over the cooked rice. Enjoy!", estimatedDurationSeconds: 30, tasks: [
                StepTask(id: sf9, action: .plate, durationSeconds: 30, type: .active, dependsOn: [sf0, sf8])
            ]),
        ],
        servings: 4,
        prepTimeMinutes: 15,
        cookTimeMinutes: 25,
        difficulty: .beginner,
        dietaryTags: [.dairyFree],
        mealType: .dinner,
        cuisine: .chinese,
        nutrition: NutritionInfo(
            calories: 420,
            protein: 38,
            carbohydrates: 45,
            fat: 10,
            fiber: 3,
            sugar: 4,
            sodium: 580
        ),
        isFavorite: true
    )

    // Avocado Toast tasks
    private static let at0 = UUID(uuidString: "20000000-0000-0000-0000-000000000000")!  // toast bread
    private static let at1 = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!  // halve avocado
    private static let at2 = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!  // mash avocado
    private static let at3 = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!  // season salt
    private static let at4 = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!  // plate

    // Fried Rice tasks
    private static let fr0 = UUID(uuidString: "30000000-0000-0000-0000-000000000000")!  // heat oil
    private static let fr1 = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!  // scramble eggs
    private static let fr2 = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!  // dice onion
    private static let fr3 = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!  // mince garlic
    private static let fr4 = UUID(uuidString: "30000000-0000-0000-0000-000000000004")!  // sauté onion+garlic
    private static let fr5 = UUID(uuidString: "30000000-0000-0000-0000-000000000005")!  // stir fry rice
    private static let fr6 = UUID(uuidString: "30000000-0000-0000-0000-000000000006")!  // toss soy+eggs
    private static let fr7 = UUID(uuidString: "30000000-0000-0000-0000-000000000007")!  // serve

    static let samples: [Recipe] = [
        sample,
        Recipe(
            id: avocadoId,
            title: "Avocado Toast",
            description: "Quick, healthy, and delicious breakfast.",
            ingredients: [
                Ingredient(name: "Bread", quantity: 2, unit: .slice, category: .grains),
                Ingredient(name: "Avocado", quantity: 1, unit: .whole, category: .produce),
                Ingredient(name: "Salt", quantity: 1, unit: .pinch, category: .spices),
                Ingredient(name: "Lemon Juice", quantity: 1, unit: .tablespoon, category: .produce, isOptional: true),
                Ingredient(name: "Red Pepper Flakes", quantity: 1, unit: .pinch, category: .spices, isOptional: true),
            ],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Toast the bread until golden and crispy.", estimatedDurationSeconds: 180, tasks: [
                    StepTask(id: at0, action: .heat, ingredient: "bread", quantity: 2, unit: "slice", durationSeconds: 180, type: .passive, requiresEquipment: "toaster", dependsOn: [])
                ]),
                RecipeStep(stepNumber: 2, instruction: "Halve the avocado, remove the pit, and scoop the flesh into a bowl.", estimatedDurationSeconds: 30, tasks: [
                    StepTask(id: at1, action: .cut(.halve), ingredient: "avocado", quantity: 1, unit: "whole", durationSeconds: 30, type: .active, dependsOn: [])
                ]),
                RecipeStep(stepNumber: 3, instruction: "Mash the avocado with a fork. Add salt and lemon juice if using.", estimatedDurationSeconds: 60, tasks: [
                    StepTask(id: at2, action: .mix, ingredient: "avocado", durationSeconds: 45, type: .active, dependsOn: [at1]),
                    StepTask(id: at3, action: .season, ingredient: "salt", quantity: 1, unit: "pinch", durationSeconds: 15, type: .active, dependsOn: [at2])
                ]),
                RecipeStep(stepNumber: 4, instruction: "Spread the mashed avocado on the toast. Add red pepper flakes if desired.", estimatedDurationSeconds: 30, tasks: [
                    StepTask(id: at4, action: .plate, durationSeconds: 30, type: .active, dependsOn: [at0, at3])
                ]),
            ],
            servings: 1,
            prepTimeMinutes: 5,
            cookTimeMinutes: 3,
            difficulty: .beginner,
            dietaryTags: [.vegan, .dairyFree],
            mealType: .breakfast,
            cuisine: .american,
            nutrition: NutritionInfo(calories: 280, protein: 6, carbohydrates: 30, fat: 16, fiber: 8, sugar: 2, sodium: 300)
        ),
        Recipe(
            id: friedRiceId,
            title: "Egg Fried Rice",
            description: "A classic quick dinner using leftover rice.",
            ingredients: [
                Ingredient(name: "Rice", quantity: 3, unit: .cup, category: .grains),
                Ingredient(name: "Eggs", quantity: 3, unit: .piece, category: .dairy),
                Ingredient(name: "Soy Sauce", quantity: 3, unit: .tablespoon, category: .condiments),
                Ingredient(name: "Garlic", quantity: 2, unit: .clove, category: .produce),
                Ingredient(name: "Onion", quantity: 1, unit: .whole, category: .produce),
                Ingredient(name: "Olive Oil", quantity: 2, unit: .tablespoon, category: .oils),
                Ingredient(name: "Salt", quantity: 1, unit: .pinch, category: .spices, isOptional: true),
            ],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Heat oil in a large pan or wok over high heat.", estimatedDurationSeconds: 60, tasks: [
                    StepTask(id: fr0, action: .heat, ingredient: "olive oil", quantity: 2, unit: "tbsp", durationSeconds: 60, type: .active, requiresEquipment: "stovetop", dependsOn: [])
                ]),
                RecipeStep(stepNumber: 2, instruction: "Scramble the eggs and set aside.", estimatedDurationSeconds: 90, tasks: [
                    StepTask(id: fr1, action: .scramble, ingredient: "eggs", quantity: 3, unit: "piece", durationSeconds: 90, type: .active, requiresEquipment: "stovetop", effort: .medium, dependsOn: [fr0])
                ]),
                RecipeStep(stepNumber: 3, instruction: "Sauté diced onion and minced garlic until fragrant.", timerMinutes: 2, estimatedDurationSeconds: 120, tasks: [
                    StepTask(id: fr2, action: .cut(.dice), ingredient: "onion", quantity: 1, unit: "whole", durationSeconds: 30, type: .active, requiresEquipment: "cutting board", dependsOn: []),
                    StepTask(id: fr3, action: .cut(.mince), ingredient: "garlic", quantity: 2, unit: "clove", durationSeconds: 20, type: .active, requiresEquipment: "cutting board", dependsOn: []),
                    StepTask(id: fr4, action: .saute, ingredient: "onion and garlic", durationSeconds: 120, type: .active, requiresEquipment: "stovetop", effort: .medium, dependsOn: [fr1, fr2, fr3])
                ]),
                RecipeStep(stepNumber: 4, instruction: "Add rice and stir-fry for 3-4 minutes until heated through.", timerMinutes: 4, estimatedDurationSeconds: 240, tasks: [
                    StepTask(id: fr5, action: .fry(.stir), ingredient: "rice", quantity: 3, unit: "cup", durationSeconds: 240, type: .active, requiresEquipment: "stovetop", effort: .hard, dependsOn: [fr4])
                ]),
                RecipeStep(stepNumber: 5, instruction: "Add soy sauce and scrambled eggs. Toss together and serve.", estimatedDurationSeconds: 60, tasks: [
                    StepTask(id: fr6, action: .toss, ingredient: "soy sauce and eggs", durationSeconds: 30, type: .active, requiresEquipment: "stovetop", dependsOn: [fr5]),
                    StepTask(id: fr7, action: .serve, durationSeconds: 30, type: .active, dependsOn: [fr6])
                ]),
            ],
            servings: 3,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            difficulty: .beginner,
            dietaryTags: [.dairyFree],
            mealType: .dinner,
            cuisine: .chinese,
            nutrition: NutritionInfo(calories: 380, protein: 14, carbohydrates: 52, fat: 12, fiber: 2, sugar: 3, sodium: 700)
        ),
    ]
}

// MARK: - Substitution Entry (local repository result)
struct SubstitutionEntry: Codable, Hashable, Identifiable {
    var id: String { "\(original)-\(substitute)" }
    let original: String
    let substitute: String
    let ratio: String?                      // nil for unenriched MISKG entries
    let tasteImpact: SubstitutionImpact?    // nil for unenriched
    let textureImpact: SubstitutionImpact?  // nil for unenriched
    let nutritionImpact: String?            // e.g. "Higher protein, Lower fat"
    let notes: String?
    let dietary: [DietaryTag]?
    let enriched: Bool                      // true = hand-curated with full metadata

    /// Whether this substitute is currently in the user's pantry (set at query time, not persisted).
    var inPantry: Bool = false

    // Coding keys to exclude transient properties
    enum CodingKeys: String, CodingKey {
        case original, substitute, ratio, tasteImpact, textureImpact
        case nutritionImpact, notes, dietary, enriched
    }
}

// MARK: - Ingredient Match Detail
enum IngredientMatchType: Hashable {
    case fullMatch
    case partialMatch(have: Double, need: Double)
    case noMatch
}

struct IngredientMatchDetail: Identifiable, Hashable {
    let id = UUID()
    let ingredient: Ingredient
    let matchType: IngredientMatchType
    let matchedPantryItem: PantryItem?
}

// MARK: - Pantry Match Result
struct PantryMatchResult: Identifiable {
    let id = UUID()
    let recipe: Recipe
    let matchedIngredients: [Ingredient]
    let missingIngredients: [Ingredient]
    let matchPercentage: Double

    /// Missing ingredients that have local substitutes the user owns
    let substitutableIngredients: [(ingredient: Ingredient, substitutions: [SubstitutionEntry])]
    /// True if all missing ingredients can be covered by pantry substitutes
    let canMakeWithSubstitutions: Bool
    /// Match % counting subs as partial credit
    let effectiveMatchPercentage: Double

    var canMake: Bool { missingIngredients.isEmpty }

    var displayPercentage: String {
        "\(Int(matchPercentage))%"
    }

    var effectiveDisplayPercentage: String {
        "\(Int(effectiveMatchPercentage))%"
    }

    /// Convenience init for backward compat (no substitution data)
    init(
        recipe: Recipe,
        matchedIngredients: [Ingredient],
        missingIngredients: [Ingredient],
        matchPercentage: Double,
        substitutableIngredients: [(ingredient: Ingredient, substitutions: [SubstitutionEntry])] = [],
        canMakeWithSubstitutions: Bool = false,
        effectiveMatchPercentage: Double? = nil
    ) {
        self.recipe = recipe
        self.matchedIngredients = matchedIngredients
        self.missingIngredients = missingIngredients
        self.matchPercentage = matchPercentage
        self.substitutableIngredients = substitutableIngredients
        self.canMakeWithSubstitutions = canMakeWithSubstitutions
        self.effectiveMatchPercentage = effectiveMatchPercentage ?? matchPercentage
    }
}
