import SwiftUI

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
        let rawValue: Recipe

        var id: UUID { rawValue.id }
        var recipe: Recipe { rawValue }
    }

    struct ReviewableImportedRecipe: Identifiable, Hashable, Sendable {
        let rawValue: Recipe

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

    struct DiscoverRecipeRecord: Identifiable, Hashable, Sendable {
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
    let recipeRepository: RecipeCatalogProviding
    let substitutionRepository: any SubstitutionProviding
    let cookingSessionStore: CookingSessionStoreProtocol
    let cookModePreferenceStore: CookModePreferenceStoreProtocol
    let notificationService: CookNotificationServiceProtocol
    let telemetryReporter: any TelemetryReporting

    // MARK: - Shared State
    var pantryItems: [PantryItem] = []
    var preparedDishes: [PreparedDish] = []
    var preparedDishHistory: [PreparedDishHistoryItem] = []
    var recipes: [Recipe] = []    // User's own recipes
    var mealPlan: [MealPlanEntry] = []
    var shoppingItems: [ShoppingItem] = []
    var cookQueue: CookQueue?
    var isLoading = false
    private(set) var lastError: PresentedAppError?
    private var pendingErrors: [PresentedAppError] = []
    var errorMessage: String?
    var hasScheduledInitialLoad = false
    private(set) var pantryRevision = 0
    private(set) var preparedDishesRevision = 0
    private(set) var preparedDishHistoryRevision = 0
    private(set) var recipesRevision = 0
    private(set) var discoverRecipesRevision = 0
    private(set) var mealPlanRevision = 0
    private(set) var shoppingRevision = 0
    private(set) var cookQueueRevision = 0
    var cachedSuggestedRecipeKey: SuggestedRecipeCacheKey?
    var cachedSuggestedRecipe: Recipe?

    /// Centralized navigation state.
    let navigator = NavigationCoordinator()

    /// Tracks all active cooking sessions for the UI.
    let activeCooks: ActiveCooksManaging

    struct PantryCookReviewAccumulator {
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
    var discoverRecipeStore: [DiscoverRecipeRecord] = []

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
        let substitutionRepository = SubstitutionRepository.shared
        let cookingSessionStore = UserDefaultsCookingSessionStore()
        let cookModePreferenceStore = UserDefaultsCookModePreferenceStore()
        let telemetryReporter = AppTelemetryReporter()
        self.pantryItemPreferenceStore = PantryItemPreferenceStore()
        self.storageService = StorageService(
            isStoredInMemoryOnly: launchOptions.useInMemoryStorage,
            shouldBootstrap: launchOptions.shouldBootstrapStorage,
            resetPersistentStore: launchOptions.resetPersistentStore
        )
        self.aiService = AIService(substitutionRepository: substitutionRepository, telemetryReporter: telemetryReporter)
        self.ingredientCandidateParser = IngredientCandidateParser()
        self.recipeIngredientResolver = RecipeIngredientResolver(candidateParser: ingredientCandidateParser, aiService: aiService)
        self.recipeRepository = RecipeRepository.shared
        self.substitutionRepository = substitutionRepository
        self.cookingSessionStore = cookingSessionStore
        self.cookModePreferenceStore = cookModePreferenceStore
        self.activeCooks = ActiveCooksManager(sessionStore: cookingSessionStore)
        self.notificationService = NotificationService()
        self.telemetryReporter = telemetryReporter
        IngredientMatcher.substitutionRepository = substitutionRepository
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
        recipeRepository: RecipeCatalogProviding? = nil,
        substitutionRepository: any SubstitutionProviding = SubstitutionRepository.shared,
        cookingSessionStore: CookingSessionStoreProtocol? = nil,
        cookModePreferenceStore: CookModePreferenceStoreProtocol? = nil,
        activeCooks: ActiveCooksManaging? = nil,
        notificationService: CookNotificationServiceProtocol? = nil,
        telemetryReporter: any TelemetryReporting = AppTelemetryReporter(),
        shouldLoadOnInit: Bool = true
    ) {
        self.storageService = storageService
        self.aiService = aiService
        self.ingredientCandidateParser = ingredientCandidateParser
        self.pantryItemPreferenceStore = pantryItemPreferenceStore
        self.recipeIngredientResolver = recipeIngredientResolver ?? RecipeIngredientResolver(candidateParser: ingredientCandidateParser, aiService: aiService)
        let resolvedCookingSessionStore = cookingSessionStore ?? UserDefaultsCookingSessionStore()
        let resolvedCookModePreferenceStore = cookModePreferenceStore ?? UserDefaultsCookModePreferenceStore()
        self.recipeRepository = recipeRepository ?? RecipeRepository.shared
        self.substitutionRepository = substitutionRepository
        self.cookingSessionStore = resolvedCookingSessionStore
        self.cookModePreferenceStore = resolvedCookModePreferenceStore
        self.activeCooks = activeCooks ?? ActiveCooksManager(sessionStore: resolvedCookingSessionStore)
        self.notificationService = notificationService ?? NotificationService()
        self.telemetryReporter = telemetryReporter
        IngredientMatcher.substitutionRepository = substitutionRepository
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

    // MARK: - Error Handling

    func pushError(_ error: AppError) {
        telemetryReporter.record(TelemetryEvent(
            name: "app.error.presented",
            severity: .error,
            metadata: [
                "type": error.telemetryType,
                "message": error.localizedDescription
            ]
        ))

        let presentedError = PresentedAppError(error: error)
        if lastError == nil {
            lastError = presentedError
            errorMessage = presentedError.localizedDescription
            return
        }

        pendingErrors.append(presentedError)
    }

    func clearError() {
        if pendingErrors.isEmpty {
            lastError = nil
            errorMessage = nil
            return
        }

        let nextError = pendingErrors.removeFirst()
        lastError = nextError
        errorMessage = nextError.localizedDescription
    }

    func requestRootTab(_ tab: RootTab) {
        navigator.requestTab(tab)
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

    // MARK: - Shared Utilities

    func mergedRecipeSources(_ lhs: String?, _ rhs: String?) -> String? {
        let combined = [lhs, rhs]
            .compactMap { $0?.trimmed.nilIfEmpty }
            .flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }

        guard !combined.isEmpty else { return nil }

        var seen = Set<String>()
        let unique = combined.filter { seen.insert($0.lowercased()).inserted }
        return unique.joined(separator: ", ")
    }

    func combinedQuantity(
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

    func convertCountUnit(_ value: Double, from: MeasurementUnit, to: MeasurementUnit) -> Double? {
        let countUnits: Set<MeasurementUnit> = [.piece, .whole]
        guard countUnits.contains(from), countUnits.contains(to) else { return nil }
        return value
    }

    func setPantryItems(_ items: [PantryItem]) {
        pantryItems = items
        markPantryChanged()
    }

    func setPreparedDishes(_ items: [PreparedDish]) {
        preparedDishes = items
        markPreparedDishesChanged()
    }

    func setPreparedDishHistoryItems(_ items: [PreparedDishHistoryItem]) {
        preparedDishHistory = items.sorted { lhs, rhs in
            if lhs.recipeID != rhs.recipeID {
                return lhs.recipeID != nil
            }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }
        markPreparedDishHistoryChanged()
    }

    func setRecipes(_ items: [Recipe]) {
        recipes = items
        markRecipesChanged()
    }

    func setDiscoverRecipes(_ items: [DiscoverRecipeRecord]) {
        discoverRecipeStore = items
        markDiscoverRecipesChanged()
    }

    func replaceDiscoverRecipesForTesting(_ items: [Recipe]) {
        setDiscoverRecipes(discoverEntries(from: items))
    }

    func setMealPlanEntries(_ entries: [MealPlanEntry]) {
        mealPlan = entries
        markMealPlanChanged()
    }

    func setShoppingItemsValue(_ items: [ShoppingItem]) {
        shoppingItems = items
        markShoppingChanged()
    }

    func setCookQueueValue(_ queue: CookQueue?) {
        cookQueue = queue
        markCookQueueChanged()
    }

    func markPantryChanged() {
        pantryRevision &+= 1
        cachedSuggestedRecipeKey = nil
    }

    func markPreparedDishesChanged() {
        preparedDishesRevision &+= 1
    }

    func markPreparedDishHistoryChanged() {
        preparedDishHistoryRevision &+= 1
    }

    func markRecipesChanged() {
        recipesRevision &+= 1
        cachedSuggestedRecipeKey = nil
    }

    func markDiscoverRecipesChanged() {
        discoverRecipesRevision &+= 1
    }

    func markMealPlanChanged() {
        mealPlanRevision &+= 1
    }

    func markShoppingChanged() {
        shoppingRevision &+= 1
    }

    func markCookQueueChanged() {
        cookQueueRevision &+= 1
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

struct MealPlanEatenLoggingRequest {
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

enum QuantityMergeOutcome {
    case merged(Double, MeasurementUnit?)
    case replaceExisting(Double?, MeasurementUnit?)
    case keepExisting
}

struct SanitizedMealPlan {
    let visibleEntries: [MealPlanEntry]
    let removedEntries: [MealPlanEntry]
}

struct SuggestedRecipeCacheKey: Hashable {
    let pantryRevision: Int
    let recipesRevision: Int
    let discoverRecipesRevision: Int
}
