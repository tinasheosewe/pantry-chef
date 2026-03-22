import Foundation

/// Loads bundled seed recipes and manages the on-device recipe cache.
/// Lazy caching: API results are cached on detail view; enriched on first cook.
@MainActor
final class RecipeRepository {

    static let shared = RecipeRepository()

    /// Bundled seed recipes (shipped with app)
    private var seedRecipeStore: [Recipe] = []

    /// Cached API recipes (persisted to disk, 7-day TTL)
    private var cachedRecipeStore: [Recipe] = []
    private var hasLoadedSeedRecipes = false
    private var hasLoadedCachedRecipes = false

    /// File URL for the disk cache
    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cached_recipes.json")
    }

    private init() {}

    var seedRecipes: [Recipe] {
        ensureLoaded()
        return seedRecipeStore
    }

    // MARK: - Public API

    /// All non-user recipes (seed + cached)
    var discoverRecipes: [Recipe] {
        ensureLoaded()

        var all = seedRecipeStore
        // Avoid duplicates by title
        let seedTitles = Set(seedRecipeStore.map { $0.title.lowercased() })
        let unique = cachedRecipeStore.filter { !seedTitles.contains($0.title.lowercased()) }
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
        ensureLoaded()
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        if !cachedRecipeStore.contains(where: { $0.id == canonicalRecipe.id }) {
            cachedRecipeStore.append(canonicalRecipe)
            saveCachedRecipes()
        }
    }

    /// Cache multiple recipes
    func cacheRecipes(_ recipes: [Recipe]) {
        ensureLoaded()
        var changed = false
        for recipe in recipes {
            let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
            if !cachedRecipeStore.contains(where: { $0.id == canonicalRecipe.id }) {
                cachedRecipeStore.append(canonicalRecipe)
                changed = true
            }
        }
        if changed { saveCachedRecipes() }
    }

    /// Update favorite state in cached recipe
    func updateFavoriteState(id: UUID, isFavorite: Bool) {
        ensureLoaded()
        if let idx = cachedRecipeStore.firstIndex(where: { $0.id == id }) {
            cachedRecipeStore[idx].isFavorite = isFavorite
            saveCachedRecipes()
        }
    }

    /// Clear old cache entries (older than 7 days)
    func pruneCache() {
        ensureLoaded()
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let before = cachedRecipeStore.count
        cachedRecipeStore.removeAll { $0.dateAdded < cutoff }
        if cachedRecipeStore.count != before { saveCachedRecipes() }
    }

    private func ensureLoaded() {
        if !hasLoadedSeedRecipes {
            loadSeedRecipes()
        }
        if !hasLoadedCachedRecipes {
            loadCachedRecipes()
        }
    }

    // MARK: - Seed Loading

    private func loadSeedRecipes() {
        defer { hasLoadedSeedRecipes = true }

        guard let url = Bundle.main.url(forResource: "seed_recipes", withExtension: "json") else {
            seedRecipeStore = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            parseSeedJSON(data)
        } catch {
            seedRecipeStore = []
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
        } catch {
            return
        }

        seedRecipeStore = seedList.map { seed in
            TrustedRecipeCanonicalizer.canonicalize(Recipe(
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
            ))
        }
    }

    // MARK: - Cache Persistence

    private func loadCachedRecipes() {
        defer { hasLoadedCachedRecipes = true }

        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            cachedRecipeStore = []
            return
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            cachedRecipeStore = try JSONDecoder().decode([Recipe].self, from: data).map(TrustedRecipeCanonicalizer.canonicalize)
        } catch {
            cachedRecipeStore = []
        }
    }

    private func saveCachedRecipes() {
        do {
            let data = try JSONEncoder().encode(cachedRecipeStore)
            try data.write(to: cacheURL, options: .atomic)
        } catch { }
    }

}
