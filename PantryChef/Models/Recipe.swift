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

    init(
        id: UUID = UUID(),
        stepNumber: Int,
        instruction: String,
        timerMinutes: Int? = nil,
        tip: String? = nil,
        estimatedDurationSeconds: Int? = nil
    ) {
        self.id = id
        self.stepNumber = stepNumber
        self.instruction = instruction
        self.timerMinutes = timerMinutes
        self.tip = tip
        self.estimatedDurationSeconds = estimatedDurationSeconds
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
        let requiredIngredients = ingredients.filter { !$0.isOptional }
        var matched: [Ingredient] = []
        var missing: [Ingredient] = []

        for ingredient in requiredIngredients {
            let found = pantry.contains { item in
                item.name.lowercased().contains(ingredient.name.lowercased()) ||
                ingredient.name.lowercased().contains(item.name.lowercased())
            }
            if found {
                matched.append(ingredient)
            } else {
                missing.append(ingredient)
            }
        }

        return PantryMatchResult(
            recipe: self,
            matchedIngredients: matched,
            missingIngredients: missing,
            matchPercentage: requiredIngredients.isEmpty ? 0 :
                Double(matched.count) / Double(requiredIngredients.count) * 100
        )
    }

    // MARK: - Sample Data
    static let sample = Recipe(
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
            RecipeStep(stepNumber: 1, instruction: "Cook the rice according to package directions.", timerMinutes: 15, estimatedDurationSeconds: 900),
            RecipeStep(stepNumber: 2, instruction: "Slice the chicken breast into thin strips.", estimatedDurationSeconds: 120),
            RecipeStep(stepNumber: 3, instruction: "Dice the onion, mince the garlic, and slice the bell pepper.",
                       tip: "Dice means cutting into small cubes, about 1/4 inch.", estimatedDurationSeconds: 180),
            RecipeStep(stepNumber: 4, instruction: "Heat olive oil in a large pan over medium-high heat.", estimatedDurationSeconds: 60),
            RecipeStep(stepNumber: 5, instruction: "Cook the chicken strips until golden brown, about 5-6 minutes.", timerMinutes: 6, estimatedDurationSeconds: 360),
            RecipeStep(stepNumber: 6, instruction: "Add onion, garlic, and bell pepper. Cook for 3 minutes.", timerMinutes: 3, estimatedDurationSeconds: 180),
            RecipeStep(stepNumber: 7, instruction: "Add soy sauce and toss everything together. Cook 1 more minute.", timerMinutes: 1, estimatedDurationSeconds: 60),
            RecipeStep(stepNumber: 8, instruction: "Serve the stir fry over the cooked rice. Enjoy!", estimatedDurationSeconds: 30),
        ],
        servings: 4,
        prepTimeMinutes: 15,
        cookTimeMinutes: 25,
        difficulty: .beginner,
        dietaryTags: [.dairyFree],
        mealType: .dinner,
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

    static let samples: [Recipe] = [
        sample,
        Recipe(
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
                RecipeStep(stepNumber: 1, instruction: "Toast the bread until golden and crispy.", estimatedDurationSeconds: 180),
                RecipeStep(stepNumber: 2, instruction: "Halve the avocado, remove the pit, and scoop the flesh into a bowl.", estimatedDurationSeconds: 30),
                RecipeStep(stepNumber: 3, instruction: "Mash the avocado with a fork. Add salt and lemon juice if using.", estimatedDurationSeconds: 60),
                RecipeStep(stepNumber: 4, instruction: "Spread the mashed avocado on the toast. Add red pepper flakes if desired.", estimatedDurationSeconds: 30),
            ],
            servings: 1,
            prepTimeMinutes: 5,
            cookTimeMinutes: 3,
            difficulty: .beginner,
            dietaryTags: [.vegan, .dairyFree],
            mealType: .breakfast,
            nutrition: NutritionInfo(calories: 280, protein: 6, carbohydrates: 30, fat: 16, fiber: 8, sugar: 2, sodium: 300)
        ),
        Recipe(
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
                RecipeStep(stepNumber: 1, instruction: "Heat oil in a large pan or wok over high heat.", estimatedDurationSeconds: 60),
                RecipeStep(stepNumber: 2, instruction: "Scramble the eggs and set aside.", estimatedDurationSeconds: 90),
                RecipeStep(stepNumber: 3, instruction: "Sauté diced onion and minced garlic until fragrant.", timerMinutes: 2, estimatedDurationSeconds: 120),
                RecipeStep(stepNumber: 4, instruction: "Add rice and stir-fry for 3-4 minutes until heated through.", timerMinutes: 4, estimatedDurationSeconds: 240),
                RecipeStep(stepNumber: 5, instruction: "Add soy sauce and scrambled eggs. Toss together and serve.", estimatedDurationSeconds: 60),
            ],
            servings: 3,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            difficulty: .beginner,
            dietaryTags: [.dairyFree],
            mealType: .dinner,
            nutrition: NutritionInfo(calories: 380, protein: 14, carbohydrates: 52, fat: 12, fiber: 2, sugar: 3, sodium: 700)
        ),
    ]
}

// MARK: - Pantry Match Result
struct PantryMatchResult: Identifiable {
    let id = UUID()
    let recipe: Recipe
    let matchedIngredients: [Ingredient]
    let missingIngredients: [Ingredient]
    let matchPercentage: Double

    var canMake: Bool { missingIngredients.isEmpty }

    var displayPercentage: String {
        "\(Int(matchPercentage))%"
    }
}
