import Foundation

// MARK: - Ingredient
struct Ingredient: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var rawName: String
    var quantity: Double
    var unit: MeasurementUnit?
    var category: FoodCategory
    var isOptional: Bool
    var notes: String?
    var catalogItemID: String?
    var facets: [PantryFacetSelection]

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double = 1,
        unit: MeasurementUnit? = nil,
        category: FoodCategory = .other,
        isOptional: Bool = false,
        notes: String? = nil,
        catalogItemID: String? = nil,
        facets: [PantryFacetSelection] = []
    ) {
        self.id = id
        self.rawName = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.isOptional = isOptional
        self.notes = notes
        self.catalogItemID = catalogItemID
        self.facets = facets
    }

    var name: String {
        get { rawName }
        set { rawName = newValue }
    }

    var linkedItem: PantryCatalogItemDefinition? {
        catalogItemID.flatMap { PantryCatalog.item(id: $0) }
    }

    var isResolved: Bool {
        linkedItem != nil
    }

    var displayName: String {
        linkedItem?.displayName(for: facets) ?? rawName
    }

    var resolvedCategory: FoodCategory {
        linkedItem?.category ?? category
    }

    func resolved(to catalogItemID: String, facets: [PantryFacetSelection]) -> Ingredient {
        var ingredient = self
        ingredient.catalogItemID = catalogItemID
        ingredient.facets = facets
        if let item = ingredient.linkedItem {
            ingredient.category = item.category
        }
        return ingredient
    }

    func unresolved() -> Ingredient {
        var ingredient = self
        ingredient.catalogItemID = nil
        ingredient.facets = []
        return ingredient
    }

    var displayText: String {
        let unitStr = unit?.rawValue ?? ""
        if quantity == quantity.rounded() {
            return "\(Int(quantity)) \(unitStr) \(displayName)".trimmingCharacters(in: .whitespaces)
        }
        return String(format: "%.1f %@ %@", quantity, unitStr, displayName).trimmingCharacters(in: .whitespaces)
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
        return AppConfig.defaultStepDurationSeconds
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

    func completed() -> Recipe {
        RecipeCompletenessInferer.complete(self)
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
    static let sample = TrustedRecipeCanonicalizer.canonicalize(Recipe(
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
    ))

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
        TrustedRecipeCanonicalizer.canonicalize(Recipe(
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
        )),
        TrustedRecipeCanonicalizer.canonicalize(Recipe(
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
        )),
    ]
}

private enum RecipeCompletenessInferer {
    static func complete(_ recipe: Recipe) -> Recipe {
        var completed = recipe
        completed.servings = max(1, recipe.servings)

        let inferredMealType = recipe.mealType ?? inferMealType(for: recipe)
        completed.mealType = inferredMealType
        completed.cuisine = recipe.cuisine ?? inferCuisine(for: recipe)

        let inferredTimes = inferTimes(for: recipe, mealType: inferredMealType)
        if completed.prepTimeMinutes == nil {
            completed.prepTimeMinutes = inferredTimes.prep
        }
        if completed.cookTimeMinutes == nil {
            completed.cookTimeMinutes = inferredTimes.cook
        }

        completed.nutrition = completeNutrition(for: completed)
        return completed
    }

    private static func inferMealType(for recipe: Recipe) -> MealType {
        let corpus = searchableCorpus(for: recipe)

        if matchesAny(in: corpus, keywords: [
            "dessert", "cake", "cookie", "brownie", "pie", "ice cream", "pudding", "cupcake", "muffin", "tart"
        ]) {
            return .dessert
        }

        if matchesAny(in: corpus, keywords: [
            "breakfast", "omelet", "omelette", "pancake", "waffle", "oatmeal", "granola", "french toast", "breakfast burrito"
        ]) {
            return .breakfast
        }

        if matchesAny(in: corpus, keywords: [
            "snack", "dip", "chips", "popcorn", "energy bites", "protein bites", "smoothie", "trail mix", "granola bar"
        ]) {
            return .snack
        }

        if matchesAny(in: corpus, keywords: [
            "lunch", "sandwich", "wrap", "salad", "grain bowl", "soup", "taco", "quesadilla"
        ]) {
            return .lunch
        }

        return .dinner
    }

    private static func inferCuisine(for recipe: Recipe) -> CuisineType {
        let corpus = searchableCorpus(for: recipe)
        let keywordMap: [(CuisineType, [String])] = [
            (.italian, ["italian", "pasta", "risotto", "parmesan", "mozzarella", "marinara", "pesto", "lasagna", "gnocchi"]),
            (.mexican, ["mexican", "taco", "salsa", "tortilla", "jalapeno", "burrito", "quesadilla", "enchilada", "guacamole"]),
            (.chinese, ["chinese", "soy sauce", "stir fry", "fried rice", "bok choy", "hoisin", "dumpling", "scallion"]),
            (.japanese, ["japanese", "miso", "mirin", "ramen", "udon", "teriyaki", "dashi", "panko", "sushi"]),
            (.indian, ["indian", "curry", "masala", "garam", "turmeric", "paneer", "dal", "tikka", "basmati", "naan"]),
            (.thai, ["thai", "coconut milk", "fish sauce", "lemongrass", "pad thai", "thai basil", "red curry", "green curry"]),
            (.french, ["french", "beurre", "shallot", "gratin", "confit", "vinaigrette", "herbes de provence", "brie"]),
            (.mediterranean, ["mediterranean", "olive", "chickpea", "cucumber", "orzo", "tabbouleh", "mezze"]),
            (.american, ["american", "burger", "barbecue", "bbq", "meatloaf", "mac and cheese", "ranch"]),
            (.korean, ["korean", "gochujang", "kimchi", "bulgogi", "bibimbap", "gochugaru"]),
            (.vietnamese, ["vietnamese", "pho", "nuoc cham", "banh mi", "rice paper", "vermicelli"]),
            (.greek, ["greek", "feta", "tzatziki", "gyro", "kalamata", "souvlaki"]),
            (.middleEastern, ["middle eastern", "tahini", "shawarma", "zaatar", "sumac", "falafel", "hummus", "harissa"]),
            (.ethiopian, ["ethiopian", "berbere", "injera", "wat"]),
            (.caribbean, ["caribbean", "jerk", "plantain", "scotch bonnet", "allspice", "coconut rice"]),
        ]

        var bestMatch: (cuisine: CuisineType, score: Int)?
        for (cuisine, keywords) in keywordMap {
            let score = keywords.reduce(into: 0) { partialResult, keyword in
                if corpus.contains(keyword) {
                    partialResult += 1
                }
            }
            guard score > 0 else { continue }
            if bestMatch == nil || score > bestMatch?.score ?? 0 {
                bestMatch = (cuisine, score)
            }
        }

        return bestMatch?.cuisine ?? .other
    }

    private static func inferTimes(for recipe: Recipe, mealType: MealType?) -> (prep: Int, cook: Int) {
        let stepMinutes = max(0, Int(ceil(Double(recipe.steps.map(\.effectiveDurationSeconds).reduce(0, +)) / 60.0)))
        let ingredientCount = max(recipe.ingredients.count, 1)
        let corpus = searchableCorpus(for: recipe)
        let hasCooking = matchesAny(in: corpus, keywords: [
            "bake", "roast", "simmer", "boil", "fry", "saute", "sauté", "grill", "steam", "preheat", "oven", "stovetop"
        ])

        if !hasCooking {
            let prep = max(5, min(ingredientCount * 3, stepMinutes > 0 ? stepMinutes : defaultPrepTime(for: mealType)))
            return (prep, 0)
        }

        if stepMinutes > 0 {
            let prepTarget = max(5, min(max(stepMinutes / 3, ingredientCount * 2), 25))
            let prep = min(prepTarget, max(stepMinutes - 5, 5))
            let cook = max(stepMinutes - prep, 5)
            return (prep, cook)
        }

        return (defaultPrepTime(for: mealType), defaultCookTime(for: mealType))
    }

    private static func defaultPrepTime(for mealType: MealType?) -> Int {
        switch mealType {
        case .breakfast: return 10
        case .lunch: return 15
        case .snack: return 8
        case .dessert: return 20
        case .dinner, .none: return 15
        }
    }

    private static func defaultCookTime(for mealType: MealType?) -> Int {
        switch mealType {
        case .breakfast: return 10
        case .lunch: return 15
        case .snack: return 5
        case .dessert: return 25
        case .dinner, .none: return 25
        }
    }

    private static func completeNutrition(for recipe: Recipe) -> NutritionInfo {
        let estimated = estimateNutrition(for: recipe)
        let existing = recipe.nutrition

        let protein = pick(existing?.protein, fallback: estimated.protein)
        let carbohydrates = pick(existing?.carbohydrates, fallback: estimated.carbohydrates)
        let fat = pick(existing?.fat, fallback: estimated.fat)

        let derivedCalories = Int(round((protein * 4) + (carbohydrates * 4) + (fat * 9)))
        let calories = max(existing?.calories ?? 0, derivedCalories, estimated.calories)

        return NutritionInfo(
            calories: calories,
            protein: protein,
            carbohydrates: carbohydrates,
            fat: fat,
            fiber: pickOptional(existing?.fiber, fallback: estimated.fiber),
            sugar: pickOptional(existing?.sugar, fallback: estimated.sugar),
            sodium: pickOptional(existing?.sodium, fallback: estimated.sodium)
        )
    }

    private static func estimateNutrition(for recipe: Recipe) -> NutritionInfo {
        let servings = max(recipe.servings, 1)
        let profiles: [FoodCategory: (calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, sugar: Double, sodium: Double)] = [
            .dairy: (120, 7, 6, 7, 0, 5, 90),
            .produce: (35, 1.5, 7, 0.3, 2.5, 3.5, 20),
            .protein: (180, 22, 0, 8, 0, 0, 85),
            .grains: (180, 5, 35, 2, 2.5, 1, 10),
            .spices: (260, 10, 50, 8, 25, 2, 30),
            .condiments: (150, 2, 15, 8, 0.5, 8, 700),
            .bakingSupplies: (360, 6, 70, 5, 1, 35, 120),
            .frozenFoods: (110, 4, 14, 4, 2, 3, 180),
            .canned: (95, 5, 14, 2, 3, 2, 260),
            .beverages: (40, 0.5, 9, 0, 0, 8, 20),
            .snacks: (480, 8, 55, 24, 4, 8, 280),
            .oils: (884, 0, 0, 100, 0, 0, 0),
            .pasta: (190, 6, 37, 1.5, 2, 1, 10),
            .nuts: (600, 20, 18, 50, 9, 5, 5),
            .other: (120, 4, 14, 4, 1.5, 3, 100),
        ]

        var totals = (calories: 0.0, protein: 0.0, carbs: 0.0, fat: 0.0, fiber: 0.0, sugar: 0.0, sodium: 0.0)

        for ingredient in recipe.ingredients {
            let profile = profiles[ingredient.resolvedCategory] ?? profiles[.other]!
            let quantityFactor = normalizedQuantity(for: ingredient)
            totals.calories += profile.calories * quantityFactor
            totals.protein += profile.protein * quantityFactor
            totals.carbs += profile.carbs * quantityFactor
            totals.fat += profile.fat * quantityFactor
            totals.fiber += profile.fiber * quantityFactor
            totals.sugar += profile.sugar * quantityFactor
            totals.sodium += profile.sodium * quantityFactor
        }

        if totals.calories == 0 {
            let mealType = recipe.mealType ?? inferMealType(for: recipe)
            let baseline = baselineNutrition(for: mealType)
            totals = baseline
        }

        let perServing = (
            calories: totals.calories / Double(servings),
            protein: totals.protein / Double(servings),
            carbs: totals.carbs / Double(servings),
            fat: totals.fat / Double(servings),
            fiber: totals.fiber / Double(servings),
            sugar: totals.sugar / Double(servings),
            sodium: totals.sodium / Double(servings)
        )

        let mealType = recipe.mealType ?? inferMealType(for: recipe)
        return NutritionInfo(
            calories: clamp(Int(round(perServing.calories)), min: baselineRanges(for: mealType).calories.0, max: baselineRanges(for: mealType).calories.1),
            protein: Double(clamp(Int(round(perServing.protein)), min: baselineRanges(for: mealType).protein.0, max: baselineRanges(for: mealType).protein.1)),
            carbohydrates: Double(clamp(Int(round(perServing.carbs)), min: baselineRanges(for: mealType).carbs.0, max: baselineRanges(for: mealType).carbs.1)),
            fat: Double(clamp(Int(round(perServing.fat)), min: baselineRanges(for: mealType).fat.0, max: baselineRanges(for: mealType).fat.1)),
            fiber: Double(clamp(Int(round(perServing.fiber)), min: baselineRanges(for: mealType).fiber.0, max: baselineRanges(for: mealType).fiber.1)),
            sugar: Double(clamp(Int(round(perServing.sugar)), min: baselineRanges(for: mealType).sugar.0, max: baselineRanges(for: mealType).sugar.1)),
            sodium: Double(clamp(Int(round(perServing.sodium)), min: baselineRanges(for: mealType).sodium.0, max: baselineRanges(for: mealType).sodium.1))
        )
    }

    private static func baselineNutrition(for mealType: MealType) -> (calories: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, sugar: Double, sodium: Double) {
        switch mealType {
        case .breakfast:
            return (380, 18, 36, 16, 6, 10, 420)
        case .lunch:
            return (520, 28, 42, 22, 7, 9, 650)
        case .dinner:
            return (640, 34, 48, 28, 8, 8, 780)
        case .snack:
            return (220, 9, 20, 11, 4, 8, 260)
        case .dessert:
            return (340, 5, 42, 16, 2, 24, 220)
        }
    }

    private static func baselineRanges(for mealType: MealType) -> (
        calories: (Int, Int),
        protein: (Int, Int),
        carbs: (Int, Int),
        fat: (Int, Int),
        fiber: (Int, Int),
        sugar: (Int, Int),
        sodium: (Int, Int)
    ) {
        switch mealType {
        case .breakfast:
            return ((250, 700), (8, 40), (18, 80), (6, 35), (2, 14), (2, 28), (100, 900))
        case .lunch:
            return ((300, 850), (12, 55), (20, 95), (8, 40), (3, 16), (2, 24), (150, 1200))
        case .dinner:
            return ((350, 1000), (15, 65), (20, 110), (8, 45), (3, 18), (2, 24), (150, 1500))
        case .snack:
            return ((100, 450), (3, 25), (8, 45), (3, 25), (1, 10), (1, 20), (50, 700))
        case .dessert:
            return ((150, 700), (2, 15), (18, 90), (5, 35), (0, 8), (8, 55), (25, 600))
        }
    }

    private static func normalizedQuantity(for ingredient: Ingredient) -> Double {
        let quantity = max(ingredient.quantity, 0)
        switch ingredient.unit {
        case .gram:
            return quantity / 100.0
        case .kilogram:
            return quantity * 10.0
        case .ounce:
            return quantity * 0.283
        case .pound:
            return quantity * 4.54
        case .milliliter:
            return quantity / 100.0
        case .liter:
            return quantity * 10.0
        case .tablespoon:
            return quantity * 0.15
        case .teaspoon:
            return quantity * 0.05
        case .cup:
            return quantity * 2.4
        case .fluidOunce:
            return quantity * 0.3
        case .piece, .whole:
            return quantity * defaultWeightFactor(for: ingredient, grams: 120)
        case .slice:
            return quantity * defaultWeightFactor(for: ingredient, grams: 30)
        case .clove:
            return quantity * 0.03
        case .bunch:
            return quantity * defaultWeightFactor(for: ingredient, grams: 75)
        case .can:
            return quantity * 4.0
        case .package:
            return quantity * 3.5
        case .loaf:
            return quantity * 4.5
        case .pinch:
            return quantity * 0.01
        case .splash:
            return quantity * 0.02
        case .toTaste:
            return max(quantity * 0.01, 0.01)
        case .none:
            return max(quantity * defaultWeightFactor(for: ingredient, grams: 80), 0.1)
        }
    }

    private static func defaultWeightFactor(for ingredient: Ingredient, grams: Double) -> Double {
        switch ingredient.resolvedCategory {
        case .protein:
            return 0.85
        case .spices:
            return 0.02
        case .condiments:
            return 0.15
        case .oils:
            return 0.14
        case .grains, .pasta:
            return 0.4
        case .nuts:
            return 0.3
        case .produce:
            return grams / 100.0
        default:
            return grams / 100.0
        }
    }

    private static func searchableCorpus(for recipe: Recipe) -> String {
        [
            recipe.title,
            recipe.description ?? "",
            recipe.ingredients.map(\.displayName).joined(separator: " "),
            recipe.steps.map(\.instruction).joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private static func matchesAny(in corpus: String, keywords: [String]) -> Bool {
        keywords.contains { corpus.contains($0) }
    }

    private static func pick(_ value: Double?, fallback: Double) -> Double {
        guard let value, value > 0 else { return fallback }
        return value
    }

    private static func pickOptional(_ value: Double?, fallback: Double?) -> Double? {
        if let value, value > 0 {
            return value
        }
        return fallback
    }

    private static func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

// MARK: - Substitution Entry (local repository result)
struct SubstitutionEntry: Codable, Hashable, Identifiable {
    var id: String { "\(originalItemID)-\(substituteItemID)-\(substituteName)" }
    let originalItemID: String
    let substituteItemID: String
    let substituteName: String
    let substituteFacets: [PantryFacetSelection]
    let ratio: String
    let tasteImpact: SubstitutionImpact
    let textureImpact: SubstitutionImpact
    let cookingImpact: CookingImpact
    let nutritionImpact: String?
    let notes: String?
    let dietary: [DietaryTag]?

    /// Whether this substitute is currently in the user's pantry (set at query time, not persisted).
    var inPantry: Bool = false

    // Coding keys to exclude transient properties
    enum CodingKeys: String, CodingKey {
        case originalItemID, substituteItemID, substituteName, substituteFacets
        case ratio, tasteImpact, textureImpact, cookingImpact
        case nutritionImpact, notes, dietary
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
        let safe = matchPercentage.isFinite ? max(0, min(matchPercentage, 100)) : 0
        return "\(Int(safe))%"
    }

    var effectiveDisplayPercentage: String {
        let safe = effectiveMatchPercentage.isFinite ? max(0, min(effectiveMatchPercentage, 100)) : 0
        return "\(Int(safe))%"
    }

    /// Memberwise init with substitution defaults
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
