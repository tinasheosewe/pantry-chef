import Foundation

/// Loads bundled seed recipes and manages the on-device recipe cache.
/// Lazy caching: API results are cached on detail view; enriched on first cook.
@MainActor
final class RecipeRepository {

    static let shared = RecipeRepository()

    /// Bundled seed recipes (shipped with app)
    private(set) var seedRecipes: [Recipe] = []

    /// Cached API recipes (persisted to disk, 7-day TTL)
    private(set) var cachedRecipes: [Recipe] = []

    /// File URL for the disk cache
    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cached_recipes.json")
    }

    private init() {
        loadSeedRecipes()
        loadCachedRecipes()
    }

    // MARK: - Public API

    /// All non-user recipes (seed + cached)
    var discoverRecipes: [Recipe] {
        var all = seedRecipes
        // Avoid duplicates by title
        let seedTitles = Set(seedRecipes.map { $0.title.lowercased() })
        let unique = cachedRecipes.filter { !seedTitles.contains($0.title.lowercased()) }
        all.append(contentsOf: unique)
        return all
    }

    /// Filter discover recipes by criteria
    func filtered(
        cuisine: CuisineType? = nil,
        mealType: MealType? = nil,
        difficulty: DifficultyLevel? = nil,
        dietaryTags: Set<DietaryTag> = [],
        searchQuery: String = "",
        pantry: [PantryItem]? = nil,
        onlyMakeable: Bool = false
    ) -> [Recipe] {
        var recipes = discoverRecipes

        if let cuisine {
            recipes = recipes.filter { $0.cuisine == cuisine }
        }
        if let mealType {
            recipes = recipes.filter { $0.mealType == mealType }
        }
        if let difficulty {
            recipes = recipes.filter { $0.difficulty == difficulty }
        }
        if !dietaryTags.isEmpty {
            recipes = recipes.filter { recipe in
                dietaryTags.isSubset(of: Set(recipe.dietaryTags))
            }
        }
        if !searchQuery.isEmpty {
            recipes = recipes.filter {
                $0.title.localizedCaseInsensitiveContains(searchQuery) ||
                ($0.description?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            }
        }
        if onlyMakeable, let pantry {
            recipes = recipes.filter { recipe in
                let match = recipe.pantryMatch(pantry: pantry)
                return match.canMake || match.canMakeWithSubstitutions
            }
        }

        return recipes
    }

    /// Cache an API recipe for future access
    func cacheRecipe(_ recipe: Recipe) {
        if !cachedRecipes.contains(where: { $0.id == recipe.id }) {
            cachedRecipes.append(recipe)
            saveCachedRecipes()
        }
    }

    /// Cache multiple recipes
    func cacheRecipes(_ recipes: [Recipe]) {
        var changed = false
        for recipe in recipes {
            if !cachedRecipes.contains(where: { $0.id == recipe.id }) {
                cachedRecipes.append(recipe)
                changed = true
            }
        }
        if changed { saveCachedRecipes() }
    }

    /// Update favorite state in cached recipe
    func updateFavoriteState(id: UUID, isFavorite: Bool) {
        if let idx = cachedRecipes.firstIndex(where: { $0.id == id }) {
            cachedRecipes[idx].isFavorite = isFavorite
            saveCachedRecipes()
        }
    }

    /// Clear old cache entries (older than 7 days)
    func pruneCache() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let before = cachedRecipes.count
        cachedRecipes.removeAll { $0.dateAdded < cutoff }
        if cachedRecipes.count != before { saveCachedRecipes() }
    }

    // MARK: - Seed Loading

    private func loadSeedRecipes() {
        guard let url = Bundle.main.url(forResource: "seed_recipes", withExtension: "json") else {
            print("[RecipeRepository] ❌ seed_recipes.json NOT FOUND in bundle")
            seedRecipes = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            print("[RecipeRepository] ✅ Loaded seed_recipes.json (\(data.count) bytes)")
            parseSeedJSON(data)
        } catch {
            print("[RecipeRepository] ❌ Failed to read seed_recipes.json: \(error)")
            seedRecipes = []
        }
    }

    private func parseSeedJSON(_ data: Data) {
        struct SeedIngredient: Decodable {
            let name: String
            let quantity: Double
            let unit: String?
            let category: String?
            let isOptional: Bool?
        }

        struct SeedStep: Decodable {
            let stepNumber: Int
            let instruction: String
            let timerMinutes: Int?
            let estimatedDurationSeconds: Int?
        }

        struct SeedNutrition: Decodable {
            let calories: Int
            let protein: Double
            let carbohydrates: Double
            let fat: Double
            let fiber: Double?
            let sugar: Double?
            let sodium: Double?
        }

        struct SeedRecipe: Decodable {
            let title: String
            let description: String?
            let cuisine: String?
            let mealType: String?
            let difficulty: Int
            let servings: Int
            let prepTimeMinutes: Int?
            let cookTimeMinutes: Int?
            let dietaryTags: [String]
            let ingredients: [SeedIngredient]
            let steps: [SeedStep]
            let nutrition: SeedNutrition?
        }

        let seedList: [SeedRecipe]
        do {
            seedList = try JSONDecoder().decode([SeedRecipe].self, from: data)
            print("[RecipeRepository] ✅ Decoded \(seedList.count) seed recipes")
        } catch {
            print("[RecipeRepository] ❌ JSON decode FAILED: \(error)")
            return
        }

        seedRecipes = seedList.map { seed in
            Recipe(
                title: seed.title,
                description: seed.description,
                ingredients: seed.ingredients.map { ing in
                    Ingredient(
                        name: ing.name,
                        quantity: ing.quantity,
                        unit: MeasurementUnit.parse(ing.unit),
                        category: FoodCategory.infer(from: ing.category),
                        isOptional: ing.isOptional ?? false
                    )
                },
                steps: seed.steps.map { step in
                    RecipeStep(
                        stepNumber: step.stepNumber,
                        instruction: step.instruction,
                        timerMinutes: step.timerMinutes,
                        estimatedDurationSeconds: step.estimatedDurationSeconds
                    )
                },
                servings: seed.servings,
                prepTimeMinutes: seed.prepTimeMinutes,
                cookTimeMinutes: seed.cookTimeMinutes,
                difficulty: DifficultyLevel(rawValue: seed.difficulty) ?? .easy,
                dietaryTags: seed.dietaryTags.compactMap { DietaryTag(rawValue: $0) },
                mealType: seed.mealType.flatMap { MealType(rawValue: $0) },
                cuisine: seed.cuisine.flatMap { CuisineType(rawValue: $0) },
                source: .bundled,
                nutrition: seed.nutrition.map {
                    NutritionInfo(
                        calories: $0.calories,
                        protein: $0.protein,
                        carbohydrates: $0.carbohydrates,
                        fat: $0.fat,
                        fiber: $0.fiber,
                        sugar: $0.sugar,
                        sodium: $0.sodium
                    )
                }
            )
        }
    }

    // MARK: - Cache Persistence

    private func loadCachedRecipes() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            cachedRecipes = []
            return
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            cachedRecipes = try JSONDecoder().decode([Recipe].self, from: data)
        } catch {
            print("[RecipeRepository] ⚠️ Failed to load cache: \(error)")
            cachedRecipes = []
        }
    }

    private func saveCachedRecipes() {
        do {
            let data = try JSONEncoder().encode(cachedRecipes)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("[RecipeRepository] ⚠️ Failed to save cache: \(error)")
        }
    }

}
