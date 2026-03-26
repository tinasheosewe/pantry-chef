import SwiftUI

enum PantryCookReviewSelection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case keep
    case remove
    case subtractRecipeAmount

    var id: Self { self }

    var title: String {
        switch self {
        case .keep:
            return "Keep"
        case .remove:
            return "Used up"
        case .subtractRecipeAmount:
            return "Subtract"
        }
    }

    var systemImage: String {
        switch self {
        case .keep:
            return "checkmark.circle"
        case .remove:
            return "trash"
        case .subtractRecipeAmount:
            return "minus.circle"
        }
    }
}

struct PantryCookReviewItem: Identifiable, Hashable, Sendable {
    var id: UUID { pantryItem.id }

    let pantryItem: PantryItem
    let matchedIngredientNames: [String]
    let matchedIngredientTexts: [String]
    let subtractQuantity: Double?
    let subtractUnit: MeasurementUnit?
    var selection: PantryCookReviewSelection

    init(
        pantryItem: PantryItem,
        matchedIngredientNames: [String],
        matchedIngredientTexts: [String],
        subtractQuantity: Double?,
        subtractUnit: MeasurementUnit?,
        selection: PantryCookReviewSelection = .keep
    ) {
        self.pantryItem = pantryItem
        self.matchedIngredientNames = matchedIngredientNames
        self.matchedIngredientTexts = matchedIngredientTexts
        self.subtractQuantity = subtractQuantity
        self.subtractUnit = subtractUnit
        self.selection = selection
    }

    var quantityMode: PantryQuantityMode {
        pantryItem.quantityMode
    }

    var supportsSubtraction: Bool {
        pantryItem.isTrackingExactQuantity && subtractQuantity != nil && subtractUnit != nil
    }

    var availableSelections: [PantryCookReviewSelection] {
        supportsSubtraction ? [.keep, .subtractRecipeAmount, .remove] : [.keep, .remove]
    }

    var pantryDetailText: String {
        switch pantryItem.quantityMode {
        case .presenceOnly:
            return PantryQuantityMode.presenceOnly.title
        case .exact:
            guard let quantity = pantryItem.quantity,
                  let unit = pantryItem.unit else {
                return PantryQuantityMode.exact.title
            }
            return "Tracked: \(Self.formattedQuantity(quantity)) \(unit.rawValue)"
        }
    }

    var recipeUsageText: String {
        if let subtractQuantity,
           let subtractUnit {
            return "Recipe uses \(Self.formattedQuantity(subtractQuantity)) \(subtractUnit.rawValue)"
        }

        if matchedIngredientTexts.count == 1, let ingredientText = matchedIngredientTexts.first {
            return ingredientText
        }

        return matchedIngredientTexts.joined(separator: " • ")
    }

    private static func formattedQuantity(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

@Observable
@MainActor
final class AppState {
    enum AIRecipeNormalizationError: LocalizedError {
        case disambiguationFailed([String])

        var errorDescription: String? {
            switch self {
            case .disambiguationFailed(let ingredientNames):
                let joinedNames = ingredientNames.joined(separator: ", ")
                return "Couldn't confidently match AI-generated ingredients (\(joinedNames)). Please try again."
            }
        }
    }

    enum RecipeIntakeNormalizationError: LocalizedError {
        case unresolvedIngredients([String])

        var errorDescription: String? {
            switch self {
            case .unresolvedIngredients(let ingredientNames):
                let joinedNames = ingredientNames.joined(separator: ", ")
                return "Resolve recipe ingredients before saving: \(joinedNames)."
            }
        }
    }

    struct NormalizedAIRecipe: Identifiable, Hashable, Sendable {
        fileprivate let rawValue: Recipe

        var id: UUID { rawValue.id }
        var recipe: Recipe { rawValue }
    }

    struct ReviewableImportedRecipe: Identifiable, Hashable, Sendable {
        fileprivate let rawValue: Recipe

        init?(recipe: Recipe) {
            guard recipe.source == .imported else {
                return nil
            }
            self.rawValue = recipe
        }

        var id: UUID { rawValue.id }
        var recipe: Recipe { rawValue }

        func reviewed(_ editedRecipe: Recipe) -> Recipe {
            var reviewedRecipe = editedRecipe
            reviewedRecipe.source = .user
            return reviewedRecipe
        }
    }

    private struct DiscoverRecipeRecord: Identifiable, Hashable, Sendable {
        var recipe: Recipe

        var id: UUID { recipe.id }

        init?(nonAIRecipe recipe: Recipe) {
            guard !recipe.source.isUserRecipe, recipe.source != .aiGenerated else {
                return nil
            }
            self.recipe = recipe
        }

        init(normalizedAIRecipe: NormalizedAIRecipe) {
            self.recipe = normalizedAIRecipe.rawValue
        }

        static func persisted(_ recipe: Recipe) -> DiscoverRecipeRecord? {
            guard !recipe.source.isUserRecipe else {
                return nil
            }

            if recipe.source == .aiGenerated {
                return DiscoverRecipeRecord(normalizedAIRecipe: NormalizedAIRecipe(rawValue: recipe))
            }

            return DiscoverRecipeRecord(nonAIRecipe: recipe)
        }
    }

    // MARK: - Services (protocol-typed for testability)
    let storageService: StorageServiceProtocol
    let aiService: AIServiceProtocol
    let pantryItemPreferenceStore: PantryItemPreferenceStoreProtocol
    let ingredientCandidateParser: IngredientCandidateParserProtocol
    let recipeIngredientResolver: RecipeIngredientResolverProtocol
    let recipeRepository = RecipeRepository.shared

    // MARK: - Shared State
    var pantryItems: [PantryItem] = []
    var preparedDishes: [PreparedDish] = []
    var preparedDishHistory: [PreparedDishHistoryItem] = []
    var recipes: [Recipe] = []    // User's own recipes
    var mealPlan: [MealPlanEntry] = []
    var shoppingItems: [ShoppingItem] = []
    var cookQueue: CookQueue?
    var isLoading = false
    var errorMessage: String?
    private var hasScheduledInitialLoad = false
    private(set) var pantryRevision = 0
    private(set) var preparedDishesRevision = 0
    private(set) var preparedDishHistoryRevision = 0
    private(set) var recipesRevision = 0
    private(set) var discoverRecipesRevision = 0
    private(set) var mealPlanRevision = 0
    private(set) var shoppingRevision = 0
    private(set) var cookQueueRevision = 0
    private var cachedSuggestedRecipeKey: SuggestedRecipeCacheKey?
    private var cachedSuggestedRecipe: Recipe?

    /// Set by notification tap to deep-link into cook mode for a specific recipe.
    var deepLinkCookModeRecipeId: String?

    /// Set by child screens to request a root tab switch.
    var requestedRootTab: RootTab?

    /// Tracks all active cooking sessions for the UI.
    let activeCooks = ActiveCooksManager()

    private struct PantryCookReviewAccumulator {
        let pantryItem: PantryItem
        var matchedIngredientNames: [String] = []
        var matchedIngredientTexts: [String] = []
        var subtractQuantity: Double = 0
        var subtractionFailed = false

        mutating func append(_ ingredient: Ingredient, subtractableAmount: Double?) {
            if !matchedIngredientNames.contains(ingredient.displayName) {
                matchedIngredientNames.append(ingredient.displayName)
            }
            matchedIngredientTexts.append(ingredient.displayText)

            guard pantryItem.isTrackingExactQuantity else {
                return
            }

            guard let subtractableAmount else {
                subtractionFailed = true
                return
            }

            subtractQuantity += subtractableAmount
        }

        func build() -> PantryCookReviewItem {
            PantryCookReviewItem(
                pantryItem: pantryItem,
                matchedIngredientNames: matchedIngredientNames,
                matchedIngredientTexts: matchedIngredientTexts,
                subtractQuantity: pantryItem.isTrackingExactQuantity && !subtractionFailed ? subtractQuantity : nil,
                subtractUnit: pantryItem.isTrackingExactQuantity ? pantryItem.unit : nil
            )
        }
    }

    // MARK: - Computed
    var expiringItems: [PantryItem] {
        let threeDaysFromNow = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return pantryItems
            .filter {
                guard let expiryDate = $0.expiryDate else { return false }
                return expiryDate <= threeDaysFromNow
            }
            .sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }
    }

    var expiringPreparedDishes: [PreparedDish] {
        let threeDaysFromNow = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return preparedDishes
            .filter {
                guard let useByDate = $0.useByDate else { return false }
                return useByDate <= threeDaysFromNow
            }
            .sorted { ($0.useByDate ?? .distantFuture) < ($1.useByDate ?? .distantFuture) }
    }

    var expiredItems: [PantryItem] {
        pantryItems.filter {
            guard let expiryDate = $0.expiryDate else { return false }
            return expiryDate < Date()
        }
    }

    var pantryByCategory: [FoodCategory: [PantryItem]] {
        Dictionary(grouping: pantryItems, by: { $0.category })
    }

    var homeDashboardRefreshState: HomeDashboardRefreshState {
        HomeDashboardRefreshState(
            mealPlanRevision: mealPlanRevision,
            pantryRevision: pantryRevision,
            preparedDishesRevision: preparedDishesRevision,
            recipesRevision: recipesRevision,
            discoverRecipesRevision: discoverRecipesRevision
        )
    }

    var recipeCatalogRefreshState: RecipeCatalogRefreshState {
        RecipeCatalogRefreshState(
            pantryRevision: pantryRevision,
            recipesRevision: recipesRevision,
            discoverRecipesRevision: discoverRecipesRevision
        )
    }

    /// All non-user recipes (bundled + cached API) — eagerly loaded for observability
    private var discoverRecipeStore: [DiscoverRecipeRecord] = []

    var discoverRecipes: [Recipe] {
        discoverRecipeStore.map(\.recipe)
    }

    /// All recipes combined (user + discover) for unified search
    var allRecipes: [Recipe] {
        recipes + discoverRecipes
    }

    func plannedEntries(on date: Date) -> [MealPlanEntry] {
        let targetDay = Calendar.current.startOfDay(for: date)
        return mealPlan.filter {
            $0.isPlanned && Calendar.current.isDate($0.date, inSameDayAs: targetDay)
        }
    }

    func plannedEntries(forWeekStarting weekStartDate: Date) -> [MealPlanEntry] {
        let weekDays = (0..<7).compactMap { dayOffset in
            Calendar.current.date(byAdding: .day, value: dayOffset, to: weekStartDate)
        }

        return mealPlan.filter { entry in
            entry.isPlanned && weekDays.contains { Calendar.current.isDate(entry.date, inSameDayAs: $0) }
        }
    }

    func preparedFoodSourceEntriesFromMealPlan() -> [MealPlanEntry] {
        mealPlan.filter { entry in
            entry.isPlanned && !entry.isPreparedFoodPlan
        }
    }

    func matchingPreparedDishes(for entry: MealPlanEntry) -> [PreparedDish] {
        guard let matchKey = entry.preparedFoodMatchKey else { return [] }

        return preparedDishes
            .filter { $0.preparedFoodMatchKey == matchKey }
            .sorted { lhs, rhs in
                if lhs.dateAdded == rhs.dateAdded {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.dateAdded > rhs.dateAdded
            }
    }

    func suggestedRecipeForCurrentPantry() -> Recipe? {
        guard !pantryItems.isEmpty, !allRecipes.isEmpty else { return nil }

        let cacheKey = SuggestedRecipeCacheKey(
            pantryRevision: pantryRevision,
            recipesRevision: recipesRevision,
            discoverRecipesRevision: discoverRecipesRevision
        )
        if cachedSuggestedRecipeKey == cacheKey {
            return cachedSuggestedRecipe
        }

        var bestRecipe: Recipe?
        var bestMatchPercentage = -1.0
        for recipe in allRecipes {
            let matchPercentage = recipe.pantryMatch(pantry: pantryItems).matchPercentage
            if matchPercentage > bestMatchPercentage {
                bestMatchPercentage = matchPercentage
                bestRecipe = recipe
            }
        }

        cachedSuggestedRecipeKey = cacheKey
        cachedSuggestedRecipe = bestRecipe

        return bestRecipe
    }

    func weeklyNutritionSummary() -> WeeklyNutritionSummary? {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        let weeklyEntries = plannedEntries(forWeekStarting: weekStart)
        let plannedRecipes = weeklyEntries.compactMap(\.scaledRecipeForPlanning)
        let plannedPreparedNutrition = weeklyEntries.compactMap { $0.preparedDish?.nutrition }
        let recipeNutrition = plannedRecipes.compactMap(\.nutrition)
        let nutritionSources = recipeNutrition + plannedPreparedNutrition
        guard !nutritionSources.isEmpty else { return nil }

        var totalCalories = 0
        var totalProtein = 0.0
        var totalCarbs = 0.0
        var totalFat = 0.0

        for nutrition in nutritionSources {
            totalCalories += nutrition.calories
            totalProtein += nutrition.protein
            totalCarbs += nutrition.carbohydrates
            totalFat += nutrition.fat
        }

        return WeeklyNutritionSummary(
            totalCalories: totalCalories,
            avgCaloriesPerMeal: totalCalories / nutritionSources.count,
            totalProtein: totalProtein,
            totalCarbs: totalCarbs,
            totalFat: totalFat,
            mealsPlanned: nutritionSources.count
        )
    }

    func homeDashboardSnapshot(for date: Date = Date()) -> HomeDashboardSnapshot {
        HomeDashboardSnapshot(
            todaysMeals: plannedEntries(on: date),
            expiringItems: expiringItems,
            suggestedRecipe: suggestedRecipeForCurrentPantry(),
            weeklyNutrition: weeklyNutritionSummary()
        )
    }

    private static let launchOptions = AppLaunchOptions.current

    /// Resolve a recipe by UUID string across all known sources.
    func recipeByIdString(_ id: String) -> Recipe? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return recipes.first(where: { $0.id == uuid })
            ?? discoverRecipeStore.first(where: { $0.recipe.id == uuid })?.recipe
    }

    /// Reload discover recipes from the repository (call after caching new recipes)
    func refreshDiscoverRecipes() {
        setDiscoverRecipes(mergedDiscoverRecipes(withPersisted: persistedDiscoverRecipes()))
    }

    func scheduleInitialLoadIfNeeded() {
        guard !hasScheduledInitialLoad else { return }
        hasScheduledInitialLoad = true

        Task { [weak self] in
            await Task.yield()
            await self?.loadAllData()
        }
    }

    // MARK: - Init (DI-friendly)
    init() {
        let launchOptions = Self.launchOptions
        self.pantryItemPreferenceStore = PantryItemPreferenceStore()
        self.storageService = StorageService(
            isStoredInMemoryOnly: launchOptions.useInMemoryStorage,
            shouldBootstrap: launchOptions.shouldBootstrapStorage,
            resetPersistentStore: launchOptions.resetPersistentStore
        )
        self.aiService = AIService()
        self.ingredientCandidateParser = IngredientCandidateParser()
        self.recipeIngredientResolver = RecipeIngredientResolver(candidateParser: ingredientCandidateParser, aiService: aiService)
        pantryItems = launchOptions.seedPantryItems ? PantryItem.samples : []
        preparedDishes = []
        preparedDishHistory = []
        recipes = launchOptions.seedRecipes ? Recipe.samples : []
        cookQueue = nil
        discoverRecipeStore = []
        if !pantryItems.isEmpty { pantryRevision = 1 }
        if !preparedDishes.isEmpty { preparedDishesRevision = 1 }
        if !recipes.isEmpty { recipesRevision = 1 }
    }

    init(
        storageService: StorageServiceProtocol,
        aiService: AIServiceProtocol,
        ingredientCandidateParser: IngredientCandidateParserProtocol = IngredientCandidateParser(),
        pantryItemPreferenceStore: PantryItemPreferenceStoreProtocol = PantryItemPreferenceStore(),
        recipeIngredientResolver: RecipeIngredientResolverProtocol? = nil,
        shouldLoadOnInit: Bool = true
    ) {
        self.storageService = storageService
        self.aiService = aiService
        self.ingredientCandidateParser = ingredientCandidateParser
        self.pantryItemPreferenceStore = pantryItemPreferenceStore
        self.recipeIngredientResolver = recipeIngredientResolver ?? RecipeIngredientResolver(candidateParser: ingredientCandidateParser, aiService: aiService)
        pantryItems = PantryItem.samples
        preparedDishes = []
        preparedDishHistory = []
        recipes = Recipe.samples
        cookQueue = nil
        discoverRecipeStore = []
        pantryRevision = PantryItem.samples.isEmpty ? 0 : 1
        preparedDishesRevision = 0
        preparedDishHistoryRevision = 0
        recipesRevision = Recipe.samples.isEmpty ? 0 : 1
        hasScheduledInitialLoad = !shouldLoadOnInit
    }

    func pantryItemDefaultPreference(for catalogItemID: String?) -> PantryItemDefaultPreference? {
        guard let catalogItemID else { return nil }
        return pantryItemPreferenceStore.preference(for: catalogItemID)
    }

    func savePantryItemDefaultPreference(_ draft: PantryIntakeRowDraft) {
        guard let preference = PantryItemDefaultPreference(draft: draft) else { return }
        pantryItemPreferenceStore.savePreference(preference)
    }

    func removePantryItemDefaultPreference(for catalogItemID: String) {
        pantryItemPreferenceStore.removePreference(for: catalogItemID)
    }

    // MARK: - Data Loading (for refresh / future network-backed store)
    func loadAllData() async {
        isLoading = true
        defer {
            isLoading = false
        }

        await Task.yield()

        var failures: [String] = []

        if let storageService = storageService as? StorageService {
            do {
                let snapshot = try await storageService.fetchStartupSnapshot()
                setPantryItems(snapshot.pantryItems)
                setPreparedDishes(snapshot.preparedDishes)
                setPreparedDishHistoryItems(snapshot.preparedDishHistory)
                setRecipes(snapshot.recipes.filter { $0.source.isUserRecipe })
                let persistedDiscover = snapshot.recipes.filter { !$0.source.isUserRecipe }
                setDiscoverRecipes(mergedDiscoverRecipes(withPersisted: persistedDiscover))

                let sanitizedPlan = sanitizeMealPlanEntries(snapshot.mealPlan)
                setMealPlanEntries(sanitizedPlan.visibleEntries)
                await purgeMealPlanEntries(sanitizedPlan.removedEntries)

                setShoppingItemsValue(snapshot.shoppingItems)
                setCookQueueValue(snapshot.cookQueue)
                errorMessage = nil
                return
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        do {
            let fetchedItems = try await storageService.fetchPantryItems()
            setPantryItems(fetchedItems)
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedPreparedDishes = try await storageService.fetchPreparedDishes()
            setPreparedDishes(fetchedPreparedDishes)
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedPreparedDishHistory = try await storageService.fetchPreparedDishHistory()
            setPreparedDishHistoryItems(fetchedPreparedDishHistory)
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedRecipes = try await storageService.fetchRecipes()
            setRecipes(fetchedRecipes.filter { $0.source.isUserRecipe })
            let persistedDiscover = fetchedRecipes.filter { !$0.source.isUserRecipe }
            setDiscoverRecipes(mergedDiscoverRecipes(withPersisted: persistedDiscover))
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedPlan = try await storageService.fetchMealPlan()
            let sanitizedPlan = sanitizeMealPlanEntries(fetchedPlan)
            setMealPlanEntries(sanitizedPlan.visibleEntries)
            await purgeMealPlanEntries(sanitizedPlan.removedEntries)
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedShopping = try await storageService.fetchShoppingItems()
            setShoppingItemsValue(fetchedShopping)
        } catch {
            failures.append(error.localizedDescription)
        }

        await Task.yield()

        do {
            let fetchedCookQueue = try await storageService.fetchCookQueue()
            setCookQueueValue(fetchedCookQueue)
        } catch {
            failures.append(error.localizedDescription)
        }

        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    // MARK: - Pantry Actions
    func addPantryItem(_ item: PantryItem) async {
        if let existingIndex = pantryItems.firstIndex(where: { pantryItemsCanMerge($0, item) }) {
            var merged = pantryItems[existingIndex]
            merged = mergePantryItem(merged, with: item)
            await updatePantryItem(merged)
            return
        }

        do {
            let saved = try await storageService.addPantryItem(item)
            pantryItems.append(saved)
            markPantryChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removePantryItem(_ item: PantryItem) async {
        do {
            try await storageService.deletePantryItem(item)
            let originalCount = pantryItems.count
            pantryItems.removeAll { $0.id == item.id }
            if pantryItems.count != originalCount {
                markPantryChanged()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePantryItem(_ item: PantryItem) async {
        do {
            let updated = try await storageService.updatePantryItem(item)
            if let index = pantryItems.firstIndex(where: { $0.id == item.id }) {
                pantryItems[index] = updated
                markPantryChanged()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Recipe Actions
    func addRecipe(_ recipe: Recipe) async {
        do {
            let recipeToPersist = try await preparedRecipeForIntake(recipe)

            let saved = try await storageService.addRecipe(recipeToPersist)
            if saved.source.isUserRecipe {
                recipes.append(saved)
                markRecipesChanged()
            } else {
                setDiscoverRecipes(mergedDiscoverRecipes(withPersisted: persistedDiscoverRecipes() + [saved]))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateRecipe(_ recipe: Recipe) async {
        do {
            let recipeToPersist = try await preparedRecipeForIntake(recipe)

            let updated = try await storageService.updateRecipe(recipeToPersist)
            if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
                recipes[index] = updated
                markRecipesChanged()
            } else if let index = discoverRecipeStore.firstIndex(where: { $0.id == recipe.id }),
                      let discoverRecord = DiscoverRecipeRecord.persisted(updated) {
                discoverRecipeStore[index] = discoverRecord
                markDiscoverRecipesChanged()
            }

            await syncPreparedDishesLinked(to: updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle favorite and handle cross-list movement:
    /// - Favoriting a discover/AI recipe saves a copy into My Recipes (with isFavorite = true)
    /// - Unfavoriting a saved-from-discover recipe removes it from My Recipes
    func toggleFavoriteWithSave(_ recipe: Recipe) async {
        var updated = recipe
        updated.isFavorite.toggle()

        let isAlreadyInMyRecipes = recipes.contains { $0.id == recipe.id }
        let hasLinkedDiscoverRecipe = discoverRecipes.contains { $0.id == recipe.id && !$0.source.isUserRecipe }

        if updated.isFavorite && !isAlreadyInMyRecipes {
            // Save to My Recipes
            var savedCopy = updated
            savedCopy.source = .user
            await addRecipe(savedCopy)
        } else if !updated.isFavorite && isAlreadyInMyRecipes && (!recipe.source.isUserRecipe || hasLinkedDiscoverRecipe) {
            // Remove non-user recipes from My Recipes when un-hearted
            await removeFromMyRecipes(id: recipe.id)
        } else {
            // Normal update for user-created recipes
            await updateRecipe(updated)
        }

        // Also update in discover cache so the heart state is reflected there
        if let idx = discoverRecipeStore.firstIndex(where: { $0.id == recipe.id }) {
            discoverRecipeStore[idx].recipe.isFavorite = updated.isFavorite
            markDiscoverRecipesChanged()
        }
    }

    func deleteRecipe(_ recipe: Recipe) async {
        do {
            try await storageService.deleteRecipe(recipe)
            let originalRecipeCount = recipes.count
            recipes.removeAll { $0.id == recipe.id }
            if recipes.count != originalRecipeCount {
                markRecipesChanged()
            }
            if !recipe.source.isUserRecipe {
                let originalDiscoverCount = discoverRecipeStore.count
                discoverRecipeStore.removeAll { $0.id == recipe.id }
                if discoverRecipeStore.count != originalDiscoverCount {
                    markDiscoverRecipesChanged()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cacheDiscoverRecipe(_ recipe: NormalizedAIRecipe) async -> NormalizedAIRecipe? {
        do {
            _ = try await storageService.updateRecipe(recipe.rawValue)
            setDiscoverRecipes(mergedDiscoverRecipes(withPersisted: persistedDiscoverRecipes() + [recipe.rawValue]))
        } catch {
            errorMessage = error.localizedDescription
        }

        return recipe
    }

    func cacheDiscoverRecipe(_ recipe: Recipe) async -> Recipe? {
        let recipeToPersist: Recipe
        do {
            recipeToPersist = try await preparedRecipeForIntake(recipe)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }

        guard let discoverRecord = DiscoverRecipeRecord(nonAIRecipe: recipeToPersist) else {
            return nil
        }

        do {
            _ = try await storageService.updateRecipe(discoverRecord.recipe)
            setDiscoverRecipes(mergedDiscoverRecipes(withPersisted: persistedDiscoverRecipes() + [discoverRecord.recipe]))
        } catch {
            errorMessage = error.localizedDescription
        }

        return discoverRecord.recipe
    }

    // MARK: - AI Actions
    func getShoppingList(for recipe: Recipe) async -> [ShoppingItem] {
        var items = await aiService.generateShoppingList(recipe: recipe, pantry: pantryItems)
        for i in items.indices {
            items[i].recipeSource = recipe.title
        }
        return items
    }

    func getRecipeSuggestions() async -> [NormalizedAIRecipe] {
        let suggestedRecipes = await aiService.suggestRecipes(pantry: pantryItems)
        return await normalizeAIRecipes(suggestedRecipes)
    }

    func generateRecipe(query: String, preferences: RecipeGenerationPreferences) async -> NormalizedAIRecipe? {
        guard let recipe = await aiService.generateRecipe(query: query, preferences: preferences) else {
            return nil
        }

        return await normalizedAIRecipe(recipe)
    }

    func importRecipeFromURL(_ urlString: String) async -> ReviewableImportedRecipe? {
        guard let result = await aiService.parseRecipeFromURL(urlString) else {
            return nil
        }

        return await importedRecipeDraft(from: result.toRecipe(source: .imported))
    }

    func importRecipeFromText(_ text: String) async -> ReviewableImportedRecipe? {
        guard let result = await aiService.parseRecipeFromText(text) else {
            return nil
        }

        return await importedRecipeDraft(from: result.toRecipe(source: .imported))
    }

    func getSubstitutions(for recipe: Recipe) async -> [SubstitutionSuggestion] {
        await aiService.suggestSubstitutions(recipe: recipe, pantry: pantryItems)
    }

    func getHealthierVersion(of recipe: Recipe) async -> HealthierSuggestion? {
        await aiService.makeItHealthier(recipe: recipe)
    }

    func getLeftoverIdeas(ingredients: [String]) async -> [NormalizedAIRecipe] {
        let recipes = await aiService.leftoverTransformer(ingredients: ingredients)
        return await normalizeAIRecipes(recipes)
    }

    // MARK: - Prepared Dish Actions
    func addPreparedDish(_ dish: PreparedDish) async {
        do {
            let saved = try await storageService.addPreparedDish(dish)
            preparedDishes.append(saved)
            markPreparedDishesChanged()
            refreshPreparedDishHistory(with: saved)
            await persistPreparedDishHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePreparedDish(_ dish: PreparedDish) async {
        do {
            let previousDish = preparedDishes.first(where: { $0.id == dish.id })
            let updated = try await storageService.updatePreparedDish(dish)
            if let index = preparedDishes.firstIndex(where: { $0.id == dish.id }) {
                preparedDishes[index] = updated
                markPreparedDishesChanged()
            }
            if let previousDish {
                let shouldRefreshHistory = previousDish.historyTemplateSignature != updated.historyTemplateSignature
                    || updated.servingsRemaining > previousDish.servingsRemaining
                if shouldRefreshHistory {
                    refreshPreparedDishHistory(with: updated)
                    await persistPreparedDishHistory()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removePreparedDish(_ dish: PreparedDish) async {
        do {
            try await storageService.deletePreparedDish(dish)
            let originalDishCount = preparedDishes.count
            preparedDishes.removeAll { $0.id == dish.id }
            if preparedDishes.count != originalDishCount {
                markPreparedDishesChanged()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func adjustPreparedDishServings(_ dish: PreparedDish, delta: Int) async -> Bool {
        guard delta != 0 else { return false }
        guard let currentDish = preparedDishById(dish.id) else { return false }

        let updatedServings = currentDish.servingsRemaining + delta
        if updatedServings <= 0 {
            await removePreparedDish(currentDish)
            return true
        }

        var updatedDish = currentDish
        updatedDish.servingsRemaining = updatedServings
        await updatePreparedDish(updatedDish)
        return false
    }

    func preparedDishById(_ id: UUID) -> PreparedDish? {
        preparedDishes.first { $0.id == id }
    }

    func preparedDishHistoryItem(by id: UUID) -> PreparedDishHistoryItem? {
        preparedDishHistory.first { $0.id == id }
    }

    func modifyRecipe(_ recipe: Recipe, feedback: String) async -> NormalizedAIRecipe? {
        let pantryNames = pantryItems.map(\.name)
        guard let modifiedRecipe = await aiService.modifyRecipe(recipe, feedback: feedback, pantryIngredients: pantryNames) else {
            return nil
        }

        return await normalizedAIRecipe(modifiedRecipe)
    }

    // MARK: - Meal Plan Actions
    func addToMealPlan(_ entry: MealPlanEntry, replaceExistingSlot: Bool = false) async {
        await addToMealPlan([entry], replaceExistingSlot: replaceExistingSlot)
    }

    func addToMealPlan(_ entries: [MealPlanEntry], replaceExistingSlot: Bool = false) async {
        let plannedEntries = entries.filter(\.isPlanned)
        guard !plannedEntries.isEmpty else { return }

        do {
            if replaceExistingSlot, let slotSeed = plannedEntries.first {
                let conflictingEntries = mealPlan.filter { isSameMealSlot($0, slotSeed) }
                for conflict in conflictingEntries {
                    try await storageService.deleteMealPlanEntry(conflict)
                }
                mealPlan.removeAll { isSameMealSlot($0, slotSeed) }
            }

            for entry in plannedEntries {
                let saved = try await storageService.addMealPlanEntry(entry)
                mealPlan.append(saved)
            }

            setMealPlanEntries(sanitizeMealPlanEntries(mealPlan).visibleEntries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFromMealPlan(_ entry: MealPlanEntry) async {
        do {
            try await storageService.deleteMealPlanEntry(entry)
            let originalCount = mealPlan.count
            mealPlan.removeAll { $0.id == entry.id }
            if mealPlan.count != originalCount {
                markMealPlanChanged()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateMealPlanEntry(_ entry: MealPlanEntry) async {
        do {
            let updated = try await storageService.updateMealPlanEntry(entry)
            if let index = mealPlan.firstIndex(where: { $0.id == entry.id }) {
                mealPlan[index] = updated
                setMealPlanEntries(sanitizeMealPlanEntries(mealPlan).visibleEntries)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logMealPlanEntriesEaten(_ selections: [MealPlanEatenLoggingSelection]) async {
        let requests = selections.compactMap { selection -> MealPlanEatenLoggingRequest? in
            guard let currentEntry = mealPlan.first(where: { $0.id == selection.entryID }) else { return nil }
            guard currentEntry.supportsMealLogging else { return nil }

            let currentEatenServings = currentEntry.effectiveEatenServings
            let targetEatenServings = Swift.max(currentEatenServings, selection.targetEatenServings)
            guard targetEatenServings > currentEatenServings else { return nil }

            return MealPlanEatenLoggingRequest(
                entry: currentEntry,
                targetEatenServings: targetEatenServings,
                preparedDishID: selection.preparedDishID
            )
        }

        guard !requests.isEmpty else { return }

        let requestedServingsByPreparedDishID = requests.reduce(into: [UUID: Int]()) { partialResult, request in
            guard request.additionalServings > 0 else { return }
            guard let preparedDishID = request.preparedDishID else { return }
            partialResult[preparedDishID, default: 0] += request.additionalServings
        }

        for request in requests where request.additionalServings > 0 {
            guard let preparedDishID = request.preparedDishID else {
                errorMessage = "Choose which Prepared Food item was eaten before saving."
                return
            }

            let matchingDishIDs = Set(matchingPreparedDishes(for: request.entry).map(\.id))
            guard matchingDishIDs.contains(preparedDishID) else {
                errorMessage = "The selected Prepared Food item no longer matches \(request.entry.displayName)."
                return
            }
        }

        for (preparedDishID, requestedServings) in requestedServingsByPreparedDishID {
            guard let preparedDish = preparedDishById(preparedDishID) else { continue }
            guard requestedServings <= preparedDish.servingsRemaining else {
                errorMessage = "Not enough servings remain in \(preparedDish.name) to log those meals as eaten."
                return
            }
        }

        for request in requests {
            if request.additionalServings > 0, let preparedDishID = request.preparedDishID {
                if let currentPreparedDish = preparedDishById(preparedDishID) {
                    _ = await adjustPreparedDishServings(currentPreparedDish, delta: -request.additionalServings)
                }
            }

            do {
                let updatedEntry = request.entry.updatingEatenServings(request.targetEatenServings)
                let saved = try await storageService.updateMealPlanEntry(updatedEntry)
                if let index = mealPlan.firstIndex(where: { $0.id == saved.id }) {
                    mealPlan[index] = saved
                }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        setMealPlanEntries(sanitizeMealPlanEntries(mealPlan).visibleEntries)
    }

    func logMealPlanEntriesEaten(_ entries: [MealPlanEntry]) async {
        let selections = entries.map { entry in
            MealPlanEatenLoggingSelection(
                entryID: entry.id,
                targetEatenServings: entry.effectiveEatenServings,
                preparedDishID: entry.preparedDish?.id
            )
        }
        await logMealPlanEntriesEaten(selections)
    }

    // MARK: - Shopping Actions
    func previewShoppingListFromMealPlan() -> [ShoppingItem] {
        let recipes = mealPlan.compactMap(\.scaledRecipeForPlanning)
        let candidates = recipes.flatMap { recipe in
            recipe.ingredients.compactMap { ingredient -> ShoppingItem? in
                guard shouldIncludeInShoppingList(ingredient) else { return nil }
                return ShoppingItem(ingredient: ingredient, recipeSource: recipe.title)
            }
        }

        return mergeShoppingItems(existing: [], additions: candidates)
    }

    func generateShoppingListFromMealPlan() async {
        await addShoppingItems(previewShoppingListFromMealPlan())
    }

    func addShoppingItems(_ items: [ShoppingItem]) async {
        setShoppingItemsValue(mergeShoppingItems(existing: shoppingItems, additions: items))
        await persistShoppingItems()
    }

    func toggleShoppingItem(_ item: ShoppingItem) async {
        if let index = shoppingItems.firstIndex(where: { $0.id == item.id }) {
            shoppingItems[index].isChecked.toggle()
            markShoppingChanged()
            await persistShoppingItems()
        }
    }

    func setShoppingItems(_ items: [ShoppingItem]) async {
        setShoppingItemsValue(items)
        await persistShoppingItems()
    }

    func addShoppingItem(_ item: ShoppingItem) async {
        await addShoppingItems([item])
    }

    func removeShoppingItem(_ item: ShoppingItem) async {
        let originalCount = shoppingItems.count
        shoppingItems.removeAll { $0.id == item.id }
        if shoppingItems.count != originalCount {
            markShoppingChanged()
        }
        await persistShoppingItems()
    }

    func updateShoppingItem(_ item: ShoppingItem) async {
        guard let index = shoppingItems.firstIndex(where: { $0.id == item.id }) else { return }
        shoppingItems[index] = item
        markShoppingChanged()
        await persistShoppingItems()
    }

    func replaceShoppingItems(_ items: [ShoppingItem]) async {
        guard !items.isEmpty else { return }

        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var didChange = false

        for index in shoppingItems.indices {
            guard let updated = itemsByID[shoppingItems[index].id] else { continue }
            shoppingItems[index] = updated
            didChange = true
        }

        guard didChange else { return }
        markShoppingChanged()
        await persistShoppingItems()
    }

    func removeCheckedShoppingItems() async {
        let originalCount = shoppingItems.count
        shoppingItems.removeAll { $0.isChecked }
        if shoppingItems.count != originalCount {
            markShoppingChanged()
        }
        await persistShoppingItems()
    }

    // MARK: - Cook Queue
    func addRecipesToCookQueue(_ recipes: [Recipe], asParallelBatch: Bool = false, sourceEntries: [MealPlanEntry] = []) async {
        guard !recipes.isEmpty else { return }

        let sourceEntryIDs = sourceEntries.map(\.id)
        let newStages: [CookQueueStage]
        if asParallelBatch {
            newStages = [CookQueueStage(recipes: recipes, sourceMealPlanEntryIDs: sourceEntryIDs)]
        } else {
            newStages = recipes.map { recipe in
                let matchingEntryIDs = sourceEntries
                    .filter { $0.recipe?.id == recipe.id }
                    .map(\.id)
                return CookQueueStage(recipes: [recipe], sourceMealPlanEntryIDs: matchingEntryIDs)
            }
        }

        if var existingQueue = cookQueue {
            existingQueue.appendStages(newStages)
            setCookQueueValue(existingQueue)
        } else {
            setCookQueueValue(CookQueue(stages: newStages))
        }

        await persistCookQueue()
    }

    func moveCookQueueStage(_ stageID: UUID, by offset: Int) async {
        guard var queue = cookQueue else { return }
        queue.moveStage(stageID, by: offset)
        setCookQueueValue(queue)
        await persistCookQueue()
    }

    func bundleCookQueueStageWithNext(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }
        queue.bundleStageWithNext(stageID)
        setCookQueueValue(queue)
        await persistCookQueue()
    }

    func splitCookQueueStage(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }
        queue.splitStage(stageID)
        setCookQueueValue(queue)
        await persistCookQueue()
    }

    func startCookQueueStage(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }
        queue.startStage(stageID)
        setCookQueueValue(queue)
        await persistCookQueue()
    }

    func completeCookQueueStage(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }

        // Stamp cookedAt on linked meal plan entries and auto-create prepared dishes
        if let stage = queue.stages.first(where: { $0.id == stageID }) {
            await stampCookedMealPlanEntries(stage.sourceMealPlanEntryIDs)
        }

        queue.completeStage(stageID)
        setCookQueueValue(queue.isEmpty ? nil : queue)
        await persistCookQueue()
    }

    func stampCookedMealPlanEntriesByRecipe(_ recipeID: UUID) async {
        let entryIDs = mealPlan
            .filter { $0.recipe?.id == recipeID && $0.cookedAt == nil }
            .map(\.id)
        await stampCookedMealPlanEntries(entryIDs)
    }

    private func stampCookedMealPlanEntries(_ entryIDs: [UUID]) async {
        guard !entryIDs.isEmpty else { return }
        let now = Date()
        for entryID in entryIDs {
            guard var entry = mealPlan.first(where: { $0.id == entryID }),
                  entry.cookedAt == nil else { continue }
            entry.cookedAt = now
            await updateMealPlanEntry(entry)
        }
    }

    func addPreparedDishForRecipe(_ recipe: Recipe) async {
        let dish = PreparedDish(
            name: recipe.title,
            mealTypes: [recipe.mealType].compactMap { $0 },
            servingsRemaining: recipe.servings,
            storage: .refrigerated,
            recipeID: recipe.id
        )
        await addPreparedDish(dish)
    }

    func skipCookQueueStage(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }
        queue.skipStage(stageID)
        setCookQueueValue(queue.isEmpty ? nil : queue)
        await persistCookQueue()
    }

    func removeCookQueueStage(_ stageID: UUID) async {
        guard var queue = cookQueue else { return }
        queue.removeStage(stageID)
        setCookQueueValue(queue.stages.isEmpty ? nil : queue)
        await persistCookQueue()
    }

    func clearCookQueue() async {
        setCookQueueValue(nil)
        await persistCookQueue()
    }

    func replaceCookQueueStages(_ stages: [CookQueueStage], name: String? = nil) async {
        let normalizedStages = stages.filter { !$0.recipeIDs.isEmpty }

        guard !normalizedStages.isEmpty else {
            setCookQueueValue(nil)
            await persistCookQueue()
            return
        }

        if var existingQueue = cookQueue {
            existingQueue.name = name ?? existingQueue.name
            existingQueue.replaceStages(normalizedStages)
            setCookQueueValue(existingQueue)
        } else {
            setCookQueueValue(CookQueue(name: name ?? "Cook Queue", stages: normalizedStages))
        }

        await persistCookQueue()
    }

    func appendCookQueueStages(_ stages: [CookQueueStage], name: String? = nil) async {
        let normalizedStages = stages.filter { !$0.recipeIDs.isEmpty }
        guard !normalizedStages.isEmpty else { return }

        if var existingQueue = cookQueue {
            existingQueue.name = name ?? existingQueue.name
            existingQueue.appendStages(normalizedStages)
            setCookQueueValue(existingQueue)
        } else {
            setCookQueueValue(CookQueue(name: name ?? "Cook Queue", stages: normalizedStages))
        }

        await persistCookQueue()
    }

    func requestRootTab(_ tab: RootTab) {
        requestedRootTab = tab
    }

    func resolvedRecipes(for stage: CookQueueStage) -> [Recipe] {
        stage.recipeIDs.compactMap { recipeID in
            allRecipes.first(where: { $0.id == recipeID })
        }
    }

    func cookQueueContext(for stageID: UUID) -> (queueID: UUID, stageID: UUID)? {
        guard let queue = cookQueue, queue.stages.contains(where: { $0.id == stageID }) else {
            return nil
        }
        return (queue.id, stageID)
    }

    func cookQueueContext(for session: CookingSession) -> (queueID: UUID, stageID: UUID)? {
        guard let queueID = session.queueId, let stageID = session.queueStageId else { return nil }
        guard cookQueue?.id == queueID else { return nil }
        return (queueID, stageID)
    }

    // MARK: - Cook Mode

    func pantryCookReviewItems(for recipe: Recipe) -> [PantryCookReviewItem] {
        let ingredients = recipe.ingredients.filter { !$0.isOptional }
        var accumulators: [UUID: PantryCookReviewAccumulator] = [:]
        var order: [UUID] = []

        for ingredient in ingredients {
            guard let pantryItem = pantryItems.first(where: {
                IngredientMatcher.pantryItemMatchesIngredient($0, ingredient: ingredient)
            }) else {
                continue
            }

            if accumulators[pantryItem.id] == nil {
                accumulators[pantryItem.id] = PantryCookReviewAccumulator(pantryItem: pantryItem)
                order.append(pantryItem.id)
            }

            let subtractableAmount = subtractableRecipeAmount(for: ingredient, pantryItem: pantryItem)
            accumulators[pantryItem.id]?.append(ingredient, subtractableAmount: subtractableAmount)
        }

        return order
            .compactMap { accumulators[$0]?.build() }
            .sorted { lhs, rhs in
                if lhs.quantityMode != rhs.quantityMode {
                    return lhs.quantityMode == .exact
                }
                return lhs.pantryItem.name.localizedCaseInsensitiveCompare(rhs.pantryItem.name) == .orderedAscending
            }
    }

    func applyPantryCookReview(_ items: [PantryCookReviewItem]) async {
        for item in items {
            guard let currentItem = pantryItems.first(where: { $0.id == item.pantryItem.id }) else {
                continue
            }

            switch item.selection {
            case .keep:
                continue
            case .remove:
                await removePantryItem(currentItem)
            case .subtractRecipeAmount:
                guard let subtractQuantity = item.subtractQuantity else {
                    continue
                }

                let remainingQuantity = (currentItem.quantity ?? 0) - subtractQuantity
                if remainingQuantity <= 0 {
                    await removePantryItem(currentItem)
                } else {
                    var updatedItem = currentItem
                    updatedItem.quantity = remainingQuantity
                    await updatePantryItem(updatedItem)
                }
            }
        }
    }

    private func persistShoppingItems() async {
        do {
            try await storageService.saveShoppingItems(shoppingItems)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistPreparedDishHistory() async {
        do {
            try await storageService.savePreparedDishHistory(preparedDishHistory)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistCookQueue() async {
        do {
            try await storageService.saveCookQueue(cookQueue)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func normalizedAIRecipe(_ recipe: Recipe) async -> NormalizedAIRecipe? {
        do {
            return try await requireNormalizedAIRecipe(recipe)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func normalizeAIRecipes(_ recipes: [Recipe]) async -> [NormalizedAIRecipe] {
        var normalizedRecipes: [NormalizedAIRecipe] = []
        normalizedRecipes.reserveCapacity(recipes.count)

        for recipe in recipes {
            guard let normalizedRecipe = await normalizedAIRecipe(recipe) else {
                return []
            }
            normalizedRecipes.append(normalizedRecipe)
        }

        return normalizedRecipes
    }

    private func canonicalizedRecipeForPersistence(_ recipe: Recipe) async -> Recipe {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await recipeIngredientResolver.resolve(recipe: canonicalRecipe)

        if resolutionDraft.isReadyToBuild {
            return resolutionDraft.builtRecipe()
        }

        return canonicalRecipe
    }

    private func preparedRecipeForIntake(_ recipe: Recipe) async throws -> Recipe {
        if recipe.source == .aiGenerated {
            return try await requireNormalizedAIRecipe(recipe).rawValue
        }

        return try await requireResolvedRecipeForPersistence(recipe)
    }

    private func requireResolvedRecipeForPersistence(_ recipe: Recipe) async throws -> Recipe {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await recipeIngredientResolver.resolve(recipe: canonicalRecipe)

        guard resolutionDraft.isReadyToBuild, !resolutionDraft.requiresIngredientEdits else {
            let unresolvedNames = unresolvedIngredientNames(in: resolutionDraft)
            throw RecipeIntakeNormalizationError.unresolvedIngredients(unresolvedNames)
        }

        return resolutionDraft.builtRecipe()
    }

    private func requireNormalizedAIRecipe(_ recipe: Recipe) async throws -> NormalizedAIRecipe {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await recipeIngredientResolver.resolve(recipe: canonicalRecipe)
        let disambiguatedDraft = try await aiDisambiguatedRecipeDraft(from: resolutionDraft)
        return NormalizedAIRecipe(rawValue: disambiguatedDraft.builtRecipe())
    }

    private func importedRecipeDraft(from recipe: Recipe) async -> ReviewableImportedRecipe? {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await recipeIngredientResolver.resolve(recipe: canonicalRecipe)
        let resolvedRecipe = resolutionDraft.isReadyToBuild ? resolutionDraft.builtRecipe() : canonicalRecipe
        return ReviewableImportedRecipe(recipe: resolvedRecipe)
    }

    private func unresolvedIngredientNames(in draft: RecipeResolutionDraft) -> [String] {
        let ambiguous = draft.ambiguousIngredients.map { $0.ingredient.rawName }
        let unknown = draft.unknownIngredients.map { $0.ingredient.rawName }
        let names = ambiguous + unknown
        return names.isEmpty ? draft.recipe.ingredients.map(\ .rawName) : names
    }

    private func aiDisambiguatedRecipeDraft(from draft: RecipeResolutionDraft) async throws -> RecipeResolutionDraft {
        guard !draft.requiresIngredientEdits else {
            throw AIRecipeNormalizationError.disambiguationFailed(draft.unknownIngredients.map { $0.ingredient.rawName })
        }

        let ambiguousIngredients = draft.ambiguousIngredients
        guard !ambiguousIngredients.isEmpty else {
            return draft
        }

        let requests = ambiguousIngredients.map { ingredientDraft in
            IngredientResolutionRequest(
                ingredientID: ingredientDraft.ingredient.id,
                rawName: ingredientDraft.ingredient.rawName,
                quantity: ingredientDraft.ingredient.quantity,
                unit: ingredientDraft.ingredient.unit,
                category: ingredientDraft.ingredient.category,
                notes: ingredientDraft.ingredient.notes,
                candidates: ingredientDraft.candidates
            )
        }

        guard let decisions = await aiService.disambiguateIngredients(requests),
              decisions.count == requests.count else {
            throw AIRecipeNormalizationError.disambiguationFailed(ambiguousIngredients.map { $0.ingredient.rawName })
        }

        let decisionsByIngredient = Dictionary(uniqueKeysWithValues: decisions.map { ($0.ingredientID, $0) })
        var updatedDraft = draft

        for index in updatedDraft.ingredients.indices {
            guard updatedDraft.ingredients[index].status == .ambiguous else {
                continue
            }

            let ingredientDraft = updatedDraft.ingredients[index]
            guard let decision = decisionsByIngredient[ingredientDraft.ingredient.id],
                  decision.status == .resolved,
                  let selectedCandidateID = decision.selectedCandidateID,
                  let candidate = ingredientDraft.candidates.first(where: { $0.id == selectedCandidateID }) else {
                throw AIRecipeNormalizationError.disambiguationFailed([ingredientDraft.ingredient.rawName])
            }

            updatedDraft.ingredients[index].status = .resolved
            updatedDraft.ingredients[index].selectedCandidateID = candidate.id
            updatedDraft.ingredients[index].confidence = max(decision.confidence, candidate.score)
            updatedDraft.ingredients[index].rationale = decision.rationale
        }

        guard updatedDraft.isReadyToBuild, !updatedDraft.requiresIngredientEdits else {
            let unresolvedNames = updatedDraft.ingredients
                .filter { $0.status != .resolved }
                .map { $0.ingredient.rawName }
            throw AIRecipeNormalizationError.disambiguationFailed(unresolvedNames)
        }

        return updatedDraft
    }

    private func shouldIncludeInShoppingList(_ ingredient: Ingredient) -> Bool {
        guard !isExcludedShoppingIngredient(named: ingredient.name) else {
            return false
        }

        let exactMatchIngredient: Ingredient
        if ingredient.catalogItemID != nil {
            exactMatchIngredient = ingredient
        } else if let catalogItemID = IngredientMatcher.resolvedCatalogItemID(for: ingredient.name) {
            exactMatchIngredient = ingredient.resolved(to: catalogItemID, facets: ingredient.facets)
        } else {
            exactMatchIngredient = ingredient
        }

        return !pantryItems.contains { pantryItem in
            IngredientMatcher.pantryItemMatchesIngredient(pantryItem, ingredient: exactMatchIngredient)
                && IngredientMatcher.hasEnoughQuantity(pantryItem: pantryItem, ingredient: exactMatchIngredient)
        }
    }

    private func isExcludedShoppingIngredient(named name: String) -> Bool {
        let normalized = IngredientMatcher.normalize(name)
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let waterModifiers: Set<String> = ["cold", "hot", "warm", "ice", "iced", "boiling", "filtered"]
        let ignoredWaterTokens = waterModifiers.union(["water"])

        if normalized == "water" {
            return true
        }

        return !tokens.isEmpty
            && tokens.contains("water")
            && tokens.subtracting(ignoredWaterTokens).isEmpty
    }

    private func mergeShoppingItems(existing: [ShoppingItem], additions: [ShoppingItem]) -> [ShoppingItem] {
        var merged = existing

        for item in additions {
            guard !isExcludedShoppingIngredient(named: item.name) else { continue }

            if let index = merged.firstIndex(where: { $0.matchesIdentity(of: item) }) {
                merged[index] = mergeShoppingItem(merged[index], with: item)
            } else {
                merged.append(item)
            }
        }

        return merged
    }

    private func mergeShoppingItem(_ existing: ShoppingItem, with addition: ShoppingItem) -> ShoppingItem {
        var merged = existing
        merged.catalogItemID = existing.catalogItemID ?? addition.catalogItemID
        merged.name = merged.resolvedCatalogItem?.name ?? (
            existing.name.count <= addition.name.count ? existing.name : addition.name
        )

        if merged.category == .other {
            merged.category = addition.category
        }

        merged.recipeSource = mergedRecipeSources(existing.recipeSource, addition.recipeSource)

        switch combinedQuantity(
            existingQuantity: existing.quantity,
            existingUnit: existing.unit,
            addedQuantity: addition.quantity,
            addedUnit: addition.unit
        ) {
        case let (.merged(quantity, unit)):
            merged.quantity = quantity
            merged.unit = unit
        case .keepExisting:
            break
        case let .replaceExisting(quantity, unit):
            merged.quantity = quantity
            merged.unit = unit
        }

        return merged
    }

    private func pantryItemsCanMerge(_ existing: PantryItem, _ addition: PantryItem) -> Bool {
        let identitiesMatch: Bool
        if let existingCatalogItemID = existing.catalogItemID, let additionCatalogItemID = addition.catalogItemID {
            identitiesMatch = existingCatalogItemID == additionCatalogItemID
                && normalizedPantryIdentityFacets(existing) == normalizedPantryIdentityFacets(addition)
        } else if existing.catalogItemID == nil, addition.catalogItemID == nil {
            identitiesMatch = IngredientMatcher.normalize(existing.name) == IngredientMatcher.normalize(addition.name)
                && existing.category == addition.category
        } else {
            identitiesMatch = false
        }

        guard identitiesMatch, existing.storage == addition.storage else {
            return false
        }

        let mergedQuantityMode = PantryQuantityMode.merged(existing.quantityMode, addition.quantityMode)
        guard mergedQuantityMode == .exact else {
            return true
        }

        switch combinedQuantity(
            existingQuantity: existing.quantity,
            existingUnit: existing.unit,
            addedQuantity: addition.quantity,
            addedUnit: addition.unit
        ) {
        case .merged, .replaceExisting:
            return true
        case .keepExisting:
            return existing.quantity == nil && addition.quantity == nil
        }
    }

    private func mergePantryItem(_ existing: PantryItem, with addition: PantryItem) -> PantryItem {
        var merged = existing
        merged.catalogItemID = existing.catalogItemID ?? addition.catalogItemID
        merged.quantityMode = PantryQuantityMode.merged(existing.quantityMode, addition.quantityMode)
        if merged.facets.isEmpty || addition.facets.count > merged.facets.count {
            merged.facets = addition.facets
        }

        if merged.quantityMode == .presenceOnly {
            merged.quantity = nil
            merged.unit = nil
        } else {
            switch combinedQuantity(
                existingQuantity: existing.quantity,
                existingUnit: existing.unit,
                addedQuantity: addition.quantity,
                addedUnit: addition.unit
            ) {
            case let .merged(quantity, unit):
                merged.quantity = quantity
                merged.unit = unit
            case .keepExisting:
                break
            case let .replaceExisting(quantity, unit):
                merged.quantity = quantity
                merged.unit = unit
            }
        }

        if let existingExpiryDate = merged.expiryDate, let additionExpiryDate = addition.expiryDate {
            if additionExpiryDate < existingExpiryDate {
                merged.expiryDate = additionExpiryDate
                merged.freshnessSource = addition.freshnessSource
            }
        } else if merged.expiryDate == nil {
            merged.expiryDate = addition.expiryDate
            if addition.expiryDate != nil {
                merged.freshnessSource = addition.freshnessSource
            }
        }

        if merged.notes == nil {
            merged.notes = addition.notes
        }

        return merged
    }

    private func normalizedPantryIdentityFacets(_ item: PantryItem) -> [PantryFacetSelection] {
        guard let catalogItemID = item.catalogItemID,
              let catalogItem = PantryCatalog.item(id: catalogItemID) else {
            return item.facets
        }

        var facetsByKey: [PantryFacetKey: PantryFacetSelection] = [:]
        for facet in catalogItem.defaultSelections {
            facetsByKey[facet.key] = facet
        }

        for facet in item.facets where catalogItem.options(for: facet.key).contains(facet.value) {
            facetsByKey[facet.key] = facet
        }

        return catalogItem.facets.compactMap { facetsByKey[$0.key] }
    }

    private func mergedRecipeSources(_ lhs: String?, _ rhs: String?) -> String? {
        let combined = [lhs, rhs]
            .compactMap { $0?.trimmed.nilIfEmpty }
            .flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }

        guard !combined.isEmpty else { return nil }

        var seen = Set<String>()
        let unique = combined.filter { seen.insert($0.lowercased()).inserted }
        return unique.joined(separator: ", ")
    }

    private func combinedQuantity(
        existingQuantity: Double?,
        existingUnit: MeasurementUnit?,
        addedQuantity: Double?,
        addedUnit: MeasurementUnit?
    ) -> QuantityMergeOutcome {
        switch (existingQuantity, existingUnit, addedQuantity, addedUnit) {
        case let (lhs?, lhsUnit?, rhs?, rhsUnit?):
            if lhsUnit == rhsUnit {
                return .merged(lhs + rhs, lhsUnit)
            }

            if let converted = UnitConverter.convert(rhs, from: rhsUnit, to: lhsUnit) {
                return .merged(lhs + converted, lhsUnit)
            }

            if let converted = convertCountUnit(rhs, from: rhsUnit, to: lhsUnit) {
                return .merged(lhs + converted, lhsUnit)
            }

            return .keepExisting
        case let (nil, nil, rhs?, rhsUnit?):
            return .replaceExisting(rhs, rhsUnit)
        case let (lhs?, lhsUnit?, nil, _):
            return .merged(lhs, lhsUnit)
        case let (nil, _, rhs?, rhsUnit):
            return .replaceExisting(rhs, rhsUnit)
        default:
            return .keepExisting
        }
    }

    private func convertCountUnit(_ value: Double, from: MeasurementUnit, to: MeasurementUnit) -> Double? {
        let countUnits: Set<MeasurementUnit> = [.piece, .whole]
        guard countUnits.contains(from), countUnits.contains(to) else { return nil }
        return value
    }

    private func setPantryItems(_ items: [PantryItem]) {
        pantryItems = items
        markPantryChanged()
    }

    private func setPreparedDishes(_ items: [PreparedDish]) {
        preparedDishes = items
        markPreparedDishesChanged()
    }

    private func setPreparedDishHistoryItems(_ items: [PreparedDishHistoryItem]) {
        preparedDishHistory = items.sorted { lhs, rhs in
            if lhs.recipeID != rhs.recipeID {
                return lhs.recipeID != nil
            }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }
        markPreparedDishHistoryChanged()
    }

    private func setRecipes(_ items: [Recipe]) {
        recipes = items
        markRecipesChanged()
    }

    private func setDiscoverRecipes(_ items: [DiscoverRecipeRecord]) {
        discoverRecipeStore = items
        markDiscoverRecipesChanged()
    }

    func replaceDiscoverRecipesForTesting(_ items: [Recipe]) {
        setDiscoverRecipes(discoverEntries(from: items))
    }

    private func setMealPlanEntries(_ entries: [MealPlanEntry]) {
        mealPlan = entries
        markMealPlanChanged()
    }

    private func setShoppingItemsValue(_ items: [ShoppingItem]) {
        shoppingItems = items
        markShoppingChanged()
    }

    private func setCookQueueValue(_ queue: CookQueue?) {
        cookQueue = queue
        markCookQueueChanged()
    }

    private func markPantryChanged() {
        pantryRevision &+= 1
        cachedSuggestedRecipeKey = nil
    }

    private func markPreparedDishesChanged() {
        preparedDishesRevision &+= 1
    }

    private func markPreparedDishHistoryChanged() {
        preparedDishHistoryRevision &+= 1
    }

    private func markRecipesChanged() {
        recipesRevision &+= 1
        cachedSuggestedRecipeKey = nil
    }

    private func markDiscoverRecipesChanged() {
        discoverRecipesRevision &+= 1
    }

    private func markMealPlanChanged() {
        mealPlanRevision &+= 1
    }

    private func markShoppingChanged() {
        shoppingRevision &+= 1
    }

    private func markCookQueueChanged() {
        cookQueueRevision &+= 1
    }

    private func refreshPreparedDishHistory(with dish: PreparedDish) {
        let existingIndex = preparedDishHistory.firstIndex(where: { historyItem in
            historyItem.matches(dish)
        })

        if let existingIndex {
            preparedDishHistory[existingIndex] = PreparedDishHistoryItem(
                dish: dish,
                previousItem: preparedDishHistory[existingIndex]
            )
        } else {
            preparedDishHistory.append(PreparedDishHistoryItem(dish: dish))
        }

        setPreparedDishHistoryItems(preparedDishHistory)
    }

    private func subtractableRecipeAmount(for ingredient: Ingredient, pantryItem: PantryItem) -> Double? {
        guard pantryItem.isTrackingExactQuantity else {
            return nil
        }

        guard let pantryUnit = pantryItem.unit else {
            return ingredient.unit == nil ? ingredient.quantity : nil
        }

        guard let ingredientUnit = ingredient.unit else {
            return nil
        }

        if pantryUnit == ingredientUnit {
            return ingredient.quantity
        }

        if let converted = UnitConverter.convert(ingredient.quantity, from: ingredientUnit, to: pantryUnit) {
            return converted
        }

        return convertCountUnit(ingredient.quantity, from: ingredientUnit, to: pantryUnit)
    }

    private func discoverEntries(from recipes: [Recipe]) -> [DiscoverRecipeRecord] {
        recipes.compactMap(DiscoverRecipeRecord.persisted)
    }

    private func persistedDiscoverRecipes() -> [Recipe] {
        discoverRecipeStore
            .map(\.recipe)
            .filter { $0.source != .bundled }
    }

    private func mergedDiscoverRecipes(withPersisted persisted: [Recipe]) -> [DiscoverRecipeRecord] {
        let seed = recipeRepository.seedRecipes
        var result: [Recipe] = []
        var seen = Set<UUID>()

        for recipe in seed + persisted {
            if seen.insert(recipe.id).inserted {
                result.append(recipe)
            }
        }
        return discoverEntries(from: result)
    }

    private func sanitizeMealPlanEntries(_ entries: [MealPlanEntry]) -> SanitizedMealPlan {
        var removedEntries: [MealPlanEntry] = []
        var visibleEntries: [MealPlanEntry] = []

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard entry.isPlanned else {
                removedEntries.append(entry)
                continue
            }
            visibleEntries.append(entry)
        }

        visibleEntries.sort { lhs, rhs in
            if Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) {
                if lhs.mealType == rhs.mealType {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.mealType.rawValue < rhs.mealType.rawValue
            }
            return lhs.date < rhs.date
        }

        return SanitizedMealPlan(visibleEntries: visibleEntries, removedEntries: removedEntries)
    }

    private func purgeMealPlanEntries(_ entries: [MealPlanEntry]) async {
        guard !entries.isEmpty else { return }

        for entry in entries {
            do {
                try await storageService.deleteMealPlanEntry(entry)
            } catch {
                AppLog.warn("[AppState] Failed to purge invalid meal plan entry \(entry.id.uuidString): \(error.localizedDescription)")
            }
        }
    }

    private func isSameMealSlot(_ lhs: MealPlanEntry, _ rhs: MealPlanEntry) -> Bool {
        Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) && lhs.mealType == rhs.mealType
    }

    private func syncPreparedDishesLinked(to recipe: Recipe) async {
        let linkedDishes = preparedDishes.filter { $0.recipeID == recipe.id }
        guard !linkedDishes.isEmpty else { return }

        for dish in linkedDishes {
            var draft = PreparedDishDraft(dish: dish)
            draft.syncLinkedRecipe(recipe)

            guard let syncedDish = draft.buildDish(using: recipe) else { continue }

            do {
                let updatedDish = try await storageService.updatePreparedDish(syncedDish)
                if let index = preparedDishes.firstIndex(where: { $0.id == updatedDish.id }) {
                    preparedDishes[index] = updatedDish
                }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        markPreparedDishesChanged()
    }

    private func removeFromMyRecipes(id: UUID) async {
        guard let saved = recipes.first(where: { $0.id == id }) else { return }
        do {
            try await storageService.deleteRecipe(saved)
            recipes.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum RootTab: String, CaseIterable, Hashable {
    case today = "Today"
    case recipes = "Recipes"
    case kitchen = "Kitchen"
    case plan = "Plan"

    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .recipes: return "book"
        case .kitchen: return "refrigerator"
        case .plan: return "calendar"
        }
    }
}

struct HomeDashboardRefreshState: Hashable {
    let mealPlanRevision: Int
    let pantryRevision: Int
    let preparedDishesRevision: Int
    let recipesRevision: Int
    let discoverRecipesRevision: Int
}

struct MealPlanEatenLoggingSelection: Identifiable, Hashable, Sendable {
    var id: UUID { entryID }

    let entryID: UUID
    let targetEatenServings: Int
    let preparedDishID: UUID?
}

private struct MealPlanEatenLoggingRequest {
    let entry: MealPlanEntry
    let targetEatenServings: Int
    let preparedDishID: UUID?

    var additionalServings: Int {
        targetEatenServings - entry.effectiveEatenServings
    }
}

struct RecipeCatalogRefreshState: Hashable {
    let pantryRevision: Int
    let recipesRevision: Int
    let discoverRecipesRevision: Int
}

struct HomeDashboardSnapshot: Equatable {
    let todaysMeals: [MealPlanEntry]
    let expiringItems: [PantryItem]
    let suggestedRecipe: Recipe?
    let weeklyNutrition: WeeklyNutritionSummary?
}

private enum QuantityMergeOutcome {
    case merged(Double, MeasurementUnit?)
    case replaceExisting(Double?, MeasurementUnit?)
    case keepExisting
}

private struct SanitizedMealPlan {
    let visibleEntries: [MealPlanEntry]
    let removedEntries: [MealPlanEntry]
}

private struct SuggestedRecipeCacheKey: Hashable {
    let pantryRevision: Int
    let recipesRevision: Int
    let discoverRecipesRevision: Int
}
