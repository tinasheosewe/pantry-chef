import Foundation

/// Loads bundled seed recipes and manages the on-device recipe cache.
/// Lazy caching: API results are cached on detail view; enriched on first cook.
@MainActor
final class RecipeRepository: RecipeCatalogProviding {

    static let shared = RecipeRepository()

    /// Bundled seed recipes (shipped with app)
    private var seedRecipeStore: [Recipe] = []
    private var seedRecipeIDs: Set<UUID> = []
    private var seedRecipeTitlesLowercased: Set<String> = []

    /// Cached API recipes (persisted to disk, 7-day TTL)
    private var cachedRecipeStore: [Recipe] = []
    private var cachedRecipeIDs: Set<UUID> = []
    private var mergedDiscoverRecipeStore: [Recipe] = []
    private var mergedDiscoverRecipesDirty = true
    private var hasLoadedSeedRecipes = false
    private var hasLoadedCachedRecipes = false

    /// File URL for the disk cache
    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cached_recipes.json")
    }

    private var seedCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("seed_recipes_cache_v3.json")
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
        if mergedDiscoverRecipesDirty {
            rebuildMergedDiscoverRecipes()
        }
        return mergedDiscoverRecipeStore
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
        if cachedRecipeIDs.insert(canonicalRecipe.id).inserted {
            cachedRecipeStore.append(canonicalRecipe)
            mergedDiscoverRecipesDirty = true
            saveCachedRecipes()
        }
    }

    /// Cache multiple recipes
    func cacheRecipes(_ recipes: [Recipe]) {
        ensureLoaded()
        var changed = false
        for recipe in recipes {
            let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
            if cachedRecipeIDs.insert(canonicalRecipe.id).inserted {
                cachedRecipeStore.append(canonicalRecipe)
                changed = true
            }
        }
        if changed {
            mergedDiscoverRecipesDirty = true
            saveCachedRecipes()
        }
    }

    /// Update favorite state in cached recipe
    func updateFavoriteState(id: UUID, isFavorite: Bool) {
        ensureLoaded()
        if let idx = cachedRecipeStore.firstIndex(where: { $0.id == id }) {
            cachedRecipeStore[idx].isFavorite = isFavorite
            mergedDiscoverRecipesDirty = true
            saveCachedRecipes()
        }
    }

    /// Clear old cache entries (older than 7 days)
    func pruneCache() {
        ensureLoaded()
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let before = cachedRecipeStore.count
        cachedRecipeStore.removeAll { $0.dateAdded < cutoff }
        if cachedRecipeStore.count != before {
            cachedRecipeIDs = Set(cachedRecipeStore.map(\.id))
            mergedDiscoverRecipesDirty = true
            saveCachedRecipes()
        }
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

        guard let url = BundledSeedRecipeLoader.resourceURL() else {
            seedRecipeStore = []
            seedRecipeIDs = []
            seedRecipeTitlesLowercased = []
            return
        }

        if loadSeedRecipesFromCache(using: url) {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            seedRecipeStore = BundledSeedRecipeLoader.loadRecipes(from: data)
            seedRecipeIDs = Set(seedRecipeStore.map(\.id))
            seedRecipeTitlesLowercased = Set(seedRecipeStore.map { $0.title.lowercased() })
            mergedDiscoverRecipesDirty = true
            persistSeedRecipeCache(using: url)
        } catch {
            seedRecipeStore = []
            seedRecipeIDs = []
            seedRecipeTitlesLowercased = []
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
            cachedRecipeIDs = Set(cachedRecipeStore.map(\.id))
            mergedDiscoverRecipesDirty = true
        } catch {
            cachedRecipeStore = []
            cachedRecipeIDs = []
        }
    }

    private func saveCachedRecipes() {
        do {
            let data = try JSONEncoder().encode(cachedRecipeStore)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            AppLog.warn("[RecipeRepository] Failed to persist cached recipes: \(error.localizedDescription)")
        }
    }

    private func rebuildMergedDiscoverRecipes() {
        var merged = seedRecipeStore
        merged.reserveCapacity(seedRecipeStore.count + cachedRecipeStore.count)
        for recipe in cachedRecipeStore where !seedRecipeTitlesLowercased.contains(recipe.title.lowercased()) {
            merged.append(recipe)
        }
        mergedDiscoverRecipeStore = merged
        mergedDiscoverRecipesDirty = false
    }

    private func loadSeedRecipesFromCache(using seedURL: URL) -> Bool {
        guard let fingerprint = seedResourceFingerprint(for: seedURL) else { return false }
        guard let data = try? Data(contentsOf: seedCacheURL) else { return false }
        guard let payload = try? JSONDecoder().decode(SeedRecipeCachePayload.self, from: data) else { return false }
        guard payload.resourceFingerprint == fingerprint else { return false }

        seedRecipeStore = payload.recipes
        seedRecipeIDs = Set(seedRecipeStore.map(\.id))
        seedRecipeTitlesLowercased = Set(seedRecipeStore.map { $0.title.lowercased() })
        mergedDiscoverRecipesDirty = true
        return true
    }

    private func persistSeedRecipeCache(using seedURL: URL) {
        guard let fingerprint = seedResourceFingerprint(for: seedURL) else { return }
        let payload = SeedRecipeCachePayload(resourceFingerprint: fingerprint, recipes: seedRecipeStore)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try FileManager.default.createDirectory(
                at: seedCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: seedCacheURL, options: .atomic)
        } catch {
            AppLog.warn("[RecipeRepository] Failed to persist seed recipe cache: \(error.localizedDescription)")
        }
    }

    private func seedResourceFingerprint(for url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return "\(modified)-\(size)"
    }

}

private struct SeedRecipeCachePayload: Codable {
    let resourceFingerprint: String
    let recipes: [Recipe]
}

enum BundledSeedRecipeLoader {
    static func resourceURL() -> URL? {
        AppBundleResourceLocator.url(forResource: "seed_recipes", withExtension: "json")
    }

    static func loadRecipes() -> [Recipe] {
        guard let url = resourceURL(),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        return loadRecipes(from: data)
    }

    static func loadRecipes(from data: Data) -> [Recipe] {
        let seedList: [SeedRecipe]
        do {
            seedList = try JSONDecoder().decode([SeedRecipe].self, from: data)
        } catch {
            return []
        }

        return seedList.map { seed in
            TrustedRecipeCanonicalizer.canonicalize(Recipe(
                title: seed.title,
                description: seed.description,
                ingredients: seed.ingredients.map { ing in
                    Ingredient(
                        name: ing.name,
                        quantity: ing.quantity,
                        unit: MeasurementUnit.parse(ing.unit),
                        category: FoodCategory.infer(from: ing.category),
                        isOptional: ing.isOptional ?? false,
                        catalogItemID: ing.catalogEntryId,
                        facets: ing.facetSelections ?? []
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

    private struct SeedIngredient: Decodable {
        let name: String
        let quantity: Double
        let unit: String?
        let category: String?
        let isOptional: Bool?
        let catalogEntryId: String?
        let facetSelections: [PantryFacetSelection]?
    }

    private struct SeedStep: Decodable {
        let stepNumber: Int
        let instruction: String
        let timerMinutes: Int?
        let estimatedDurationSeconds: Int?
    }

    private struct SeedNutrition: Decodable {
        let calories: Int
        let protein: Double
        let carbohydrates: Double
        let fat: Double
        let fiber: Double?
        let sugar: Double?
        let sodium: Double?
    }

    private struct SeedRecipe: Decodable {
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
}
