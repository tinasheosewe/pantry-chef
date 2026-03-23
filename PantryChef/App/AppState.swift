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
    // MARK: - Services (protocol-typed for testability)
    let storageService: StorageServiceProtocol
    let aiService: AIServiceProtocol
    let pantryItemPreferenceStore: PantryItemPreferenceStoreProtocol
    let ingredientCandidateParser: IngredientCandidateParserProtocol
    let recipeIngredientResolver: RecipeIngredientResolverProtocol
    let recipeRepository = RecipeRepository.shared

    // MARK: - Shared State
    var pantryItems: [PantryItem] = []
    var recipes: [Recipe] = []    // User's own recipes
    var mealPlan: [MealPlanEntry] = []
    var shoppingItems: [ShoppingItem] = []
    var isLoading = false
    var errorMessage: String?
    private var hasScheduledInitialLoad = false

    /// Set by notification tap to deep-link into cook mode for a specific recipe.
    var deepLinkCookModeRecipeId: String?

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
            mealPlan: mealPlan,
            pantryItems: pantryItems,
            recipes: recipes,
            discoverRecipes: discoverRecipes
        )
    }

    var recipeCatalogRefreshState: RecipeCatalogRefreshState {
        RecipeCatalogRefreshState(
            pantryItems: pantryItems,
            recipes: recipes,
            discoverRecipes: discoverRecipes
        )
    }

    /// All non-user recipes (bundled + cached API) — eagerly loaded for observability
    var discoverRecipes: [Recipe] = []

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

    func suggestedRecipeForCurrentPantry() -> Recipe? {
        guard !pantryItems.isEmpty, !recipes.isEmpty else { return nil }

        var bestRecipe: Recipe?
        var bestMatchPercentage = -1.0
        for recipe in recipes {
            let matchPercentage = recipe.pantryMatch(pantry: pantryItems).matchPercentage
            if matchPercentage > bestMatchPercentage {
                bestMatchPercentage = matchPercentage
                bestRecipe = recipe
            }
        }

        return bestRecipe
    }

    func weeklyNutritionSummary() -> WeeklyNutritionSummary? {
        let plannedRecipes = mealPlan.filter(\.isPlanned).compactMap(\.recipe)
        guard !plannedRecipes.isEmpty else { return nil }

        var totalCalories = 0
        var totalProtein = 0.0
        var totalCarbs = 0.0
        var totalFat = 0.0

        for recipe in plannedRecipes {
            if let nutrition = recipe.nutrition {
                totalCalories += nutrition.calories
                totalProtein += nutrition.protein
                totalCarbs += nutrition.carbohydrates
                totalFat += nutrition.fat
            }
        }

        return WeeklyNutritionSummary(
            totalCalories: totalCalories,
            avgCaloriesPerMeal: totalCalories / plannedRecipes.count,
            totalProtein: totalProtein,
            totalCarbs: totalCarbs,
            totalFat: totalFat,
            mealsPlanned: plannedRecipes.count
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
        allRecipes.first { $0.id.uuidString == id }
    }

    /// Reload discover recipes from the repository (call after caching new recipes)
    func refreshDiscoverRecipes() {
        discoverRecipes = mergedDiscoverRecipes(withPersisted: discoverRecipes.filter { !$0.source.isUserRecipe })
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
        recipes = launchOptions.seedRecipes ? Recipe.samples : []
        discoverRecipes = []
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
        recipes = Recipe.samples
        discoverRecipes = []
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

        do {
            let fetchedItems = try await storageService.fetchPantryItems()
            pantryItems = fetchedItems
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedRecipes = try await storageService.fetchRecipes()
            recipes = fetchedRecipes.filter { $0.source.isUserRecipe }
            let persistedDiscover = fetchedRecipes.filter { !$0.source.isUserRecipe }
            discoverRecipes = mergedDiscoverRecipes(withPersisted: persistedDiscover)
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedPlan = try await storageService.fetchMealPlan()
            let sanitizedPlan = sanitizeMealPlanEntries(fetchedPlan)
            mealPlan = sanitizedPlan.visibleEntries
            await purgeMealPlanEntries(sanitizedPlan.removedEntries)
        } catch {
            failures.append(error.localizedDescription)
        }
        await Task.yield()

        do {
            let fetchedShopping = try await storageService.fetchShoppingItems()
            shoppingItems = fetchedShopping
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removePantryItem(_ item: PantryItem) async {
        do {
            try await storageService.deletePantryItem(item)
            pantryItems.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePantryItem(_ item: PantryItem) async {
        do {
            let updated = try await storageService.updatePantryItem(item)
            if let index = pantryItems.firstIndex(where: { $0.id == item.id }) {
                pantryItems[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Recipe Actions
    func addRecipe(_ recipe: Recipe) async {
        do {
            let canonicalRecipe = await canonicalizedRecipeForPersistence(recipe)
            let saved = try await storageService.addRecipe(canonicalRecipe)
            if saved.source.isUserRecipe {
                recipes.append(saved)
            } else {
                discoverRecipes = mergedDiscoverRecipes(withPersisted: discoverRecipes.filter { !$0.source.isUserRecipe } + [saved])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateRecipe(_ recipe: Recipe) async {
        do {
            let canonicalRecipe = await canonicalizedRecipeForPersistence(recipe)
            let updated = try await storageService.updateRecipe(canonicalRecipe)
            if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
                recipes[index] = updated
            } else if let index = discoverRecipes.firstIndex(where: { $0.id == recipe.id }) {
                discoverRecipes[index] = updated
            }
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
        if let idx = discoverRecipes.firstIndex(where: { $0.id == recipe.id }) {
            discoverRecipes[idx].isFavorite = updated.isFavorite
        }
    }

    func deleteRecipe(_ recipe: Recipe) async {
        do {
            try await storageService.deleteRecipe(recipe)
            recipes.removeAll { $0.id == recipe.id }
            if !recipe.source.isUserRecipe {
                discoverRecipes.removeAll { $0.id == recipe.id }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cacheDiscoverRecipe(_ recipe: Recipe) async {
        guard !recipe.source.isUserRecipe else { return }
        do {
            let canonicalRecipe = await canonicalizedRecipeForPersistence(recipe)
            _ = try await storageService.updateRecipe(canonicalRecipe)
            let persistedDiscover = discoverRecipes.filter { !$0.source.isUserRecipe && $0.source != .bundled }
            discoverRecipes = mergedDiscoverRecipes(withPersisted: persistedDiscover + [canonicalRecipe])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - AI Actions
    func getShoppingList(for recipe: Recipe) async -> [ShoppingItem] {
        await aiService.generateShoppingList(recipe: recipe, pantry: pantryItems)
    }

    func getRecipeSuggestions() async -> [Recipe] {
        await aiService.suggestRecipes(pantry: pantryItems)
    }

    func getSubstitutions(for recipe: Recipe) async -> [SubstitutionSuggestion] {
        await aiService.suggestSubstitutions(recipe: recipe, pantry: pantryItems)
    }

    func getHealthierVersion(of recipe: Recipe) async -> HealthierSuggestion? {
        await aiService.makeItHealthier(recipe: recipe)
    }

    func getLeftoverIdeas(ingredients: [String]) async -> [Recipe] {
        await aiService.leftoverTransformer(ingredients: ingredients)
    }

    // MARK: - Meal Plan Actions
    func addToMealPlan(_ entry: MealPlanEntry) async {
        guard entry.isPlanned else { return }

        do {
            let conflictingEntries = mealPlan.filter { isSameMealSlot($0, entry) }
            for conflict in conflictingEntries {
                try await storageService.deleteMealPlanEntry(conflict)
            }

            let saved = try await storageService.addMealPlanEntry(entry)
            mealPlan.removeAll { isSameMealSlot($0, saved) }
            mealPlan.append(saved)
            mealPlan = sanitizeMealPlanEntries(mealPlan).visibleEntries
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFromMealPlan(_ entry: MealPlanEntry) async {
        do {
            try await storageService.deleteMealPlanEntry(entry)
            mealPlan.removeAll { $0.id == entry.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Shopping Actions
    func previewShoppingListFromMealPlan() -> [ShoppingItem] {
        let recipes = mealPlan.compactMap(\.recipe)
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
        shoppingItems = mergeShoppingItems(existing: shoppingItems, additions: items)
        await persistShoppingItems()
    }

    func toggleShoppingItem(_ item: ShoppingItem) async {
        if let index = shoppingItems.firstIndex(where: { $0.id == item.id }) {
            shoppingItems[index].isChecked.toggle()
            await persistShoppingItems()
        }
    }

    func setShoppingItems(_ items: [ShoppingItem]) async {
        shoppingItems = items
        await persistShoppingItems()
    }

    func addShoppingItem(_ item: ShoppingItem) async {
        await addShoppingItems([item])
    }

    func removeShoppingItem(_ item: ShoppingItem) async {
        shoppingItems.removeAll { $0.id == item.id }
        await persistShoppingItems()
    }

    func removeCheckedShoppingItems() async {
        shoppingItems.removeAll { $0.isChecked }
        await persistShoppingItems()
    }

    // MARK: - Cook Mode
    func markRecipeAsCooked(_ recipe: Recipe) async {
        // Pantry stock is user-maintained. Cooking a recipe does not decrement pantry items.
    }

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

    private func canonicalizedRecipeForPersistence(_ recipe: Recipe) async -> Recipe {
        let canonicalRecipe = TrustedRecipeCanonicalizer.canonicalize(recipe)
        let resolutionDraft = await recipeIngredientResolver.resolve(recipe: canonicalRecipe)

        if resolutionDraft.isReadyToBuild {
            return resolutionDraft.builtRecipe()
        }

        return canonicalRecipe
    }

    private func shouldIncludeInShoppingList(_ ingredient: Ingredient) -> Bool {
        guard !isExcludedShoppingIngredient(named: ingredient.name) else {
            return false
        }

        return !pantryItems.contains { pantryItem in
            IngredientMatcher.pantryItemMatchesIngredient(pantryItem, ingredient: ingredient) &&
            IngredientMatcher.hasEnoughQuantity(pantryItem: pantryItem, ingredient: ingredient)
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

    private func mergedDiscoverRecipes(withPersisted persisted: [Recipe]) -> [Recipe] {
        let seed = recipeRepository.seedRecipes
        var result: [Recipe] = []
        var seen = Set<UUID>()

        for recipe in seed + persisted {
            if seen.insert(recipe.id).inserted {
                result.append(recipe)
            }
        }
        return result
    }

    private func sanitizeMealPlanEntries(_ entries: [MealPlanEntry]) -> SanitizedMealPlan {
        var latestEntryBySlot: [MealPlanSlotKey: MealPlanEntry] = [:]
        var slotOrder: [MealPlanSlotKey] = []
        var removedEntries: [MealPlanEntry] = []

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard entry.isPlanned else {
                removedEntries.append(entry)
                continue
            }

            let slotKey = MealPlanSlotKey(entry)
            if let replaced = latestEntryBySlot.updateValue(entry, forKey: slotKey) {
                removedEntries.append(replaced)
            } else {
                slotOrder.append(slotKey)
            }
        }

        let visibleEntries = slotOrder
            .compactMap { latestEntryBySlot[$0] }
            .sorted { lhs, rhs in
                if Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date) {
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

struct HomeDashboardRefreshState: Hashable {
    let mealPlan: [MealPlanEntry]
    let pantryItems: [PantryItem]
    let recipes: [Recipe]
    let discoverRecipes: [Recipe]
}

struct RecipeCatalogRefreshState: Hashable {
    let pantryItems: [PantryItem]
    let recipes: [Recipe]
    let discoverRecipes: [Recipe]
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

private struct MealPlanSlotKey: Hashable {
    let day: Date
    let mealType: MealType

    init(_ entry: MealPlanEntry) {
        day = Calendar.current.startOfDay(for: entry.date)
        mealType = entry.mealType
    }
}
