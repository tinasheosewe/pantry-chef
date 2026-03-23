import SwiftUI

@Observable
@MainActor
final class RecipeViewModel: AsyncActionHandling {
    var searchText = ""
    var selectedDifficulty: DifficultyLevel?
    var selectedMealType: MealType?
    var selectedCuisine: CuisineType?
    var selectedDietaryTags: Set<DietaryTag> = []
    var showAddRecipe = false
    var showImportURL = false
    var sortOrder: SortOrder = .recent
    var showOnlyFavorites = false
    var showCanMakeOnly = false          // Filter to recipes user can make
    var showWithSubstitutions = true     // Include recipes makeable with subs
    var isLoading = false
    var importedRecipe: Recipe?

    // Discover search (Spoonacular)
    var discoverSearchResults: [Recipe] = [] {
        didSet {
            discoverSearchResultsRevision &+= 1
        }
    }
    var isSearchingAPI = false
    var isLoadingMore = false
    @ObservationIgnored private let apiSearchDebouncer = TaskDebouncer()
    @ObservationIgnored private let localFilterDebouncer = TaskDebouncer()
    @ObservationIgnored private var cachedUserFilterKey: UserFilterCacheKey?
    @ObservationIgnored private var cachedUserFilterResult: [Recipe] = []
    @ObservationIgnored private var cachedDiscoverFilterKey: DiscoverFilterCacheKey?
    @ObservationIgnored private var cachedDiscoverFilterResult: [Recipe] = []
    @ObservationIgnored private var matchMapCache: [MatchMapCacheKey: [UUID: PantryMatchResult]] = [:]
    @ObservationIgnored private var matchMapCacheOrder: [MatchMapCacheKey] = []
    @ObservationIgnored private let maxMatchMapCacheEntries = 8
    @ObservationIgnored private var persistedMetrics: [PantryMetricsSignature: [UUID: PersistedRecipeMatchMetrics]] = [:]
    @ObservationIgnored private var persistedMetricsStoreLoaded = false
    @ObservationIgnored private var persistedMetricSignatureOrder: [PantryMetricsSignature] = []
    @ObservationIgnored private let maxPersistedMetricSignatures = 8
    @ObservationIgnored private var searchIndexCache: [SearchIndexCacheKey: RecipeSearchIndex] = [:]
    @ObservationIgnored private var ingredientDependencyIndexCache: [RecipeContentSignature: RecipeIngredientDependencyIndex] = [:]
    @ObservationIgnored private var pantryDependencyStateCache: [PantryMetricsSignature: PantryDependencyState] = [:]
    @ObservationIgnored private var hasPrewarmedDiscover = false
    @ObservationIgnored private var prewarmTask: Task<Void, Never>?
    @ObservationIgnored private var lastPrewarmedPantryRevision: Int?
    @ObservationIgnored private var fullCoverageTask: Task<Void, Never>?
    @ObservationIgnored private var lastFullCoverageKey: FullCoverageKey?
    @ObservationIgnored private let fullCoverageChunkSize = 128
    @ObservationIgnored private var discoverSearchResultsRevision = 0
    private var localFilterQuery = ""
    private var currentSearchOffset = 0
    private var totalSearchResults = 0
    /// True until the first API search completes (enables scroll-to-load-more even before any search)
    private(set) var neverSearchedAPI = true
    var hasMorePages: Bool { neverSearchedAPI || currentSearchOffset < totalSearchResults }
    var effectiveSearchQuery: String { localFilterQuery }
    var coverageRefreshState: RecipeCoverageRefreshState {
        RecipeCoverageRefreshState(
            catalog: appState.recipeCatalogRefreshState,
            discoverSearchSource: appStateCollectionKey(revision: discoverSearchResultsRevision, count: discoverSearchResults.count)
        )
    }

    enum SortOrder: String, CaseIterable {
        case recent = "Recent"
        case name = "Name"
        case difficulty = "Difficulty"
        case time = "Time"
        case mostCooked = "Most Cooked"
        case matchPercent = "Match %"
    }

    let appState: AppState
    @ObservationIgnored private let recipeActions: RecipeActions

    init(appState: AppState) {
        self.appState = appState
        self.recipeActions = RecipeActions(appState: appState)
        self.localFilterQuery = ""
    }

    // MARK: - Filtered User Recipes

    var filteredUserRecipes: [Recipe] {
        let key = UserFilterCacheKey(
            source: appStateCollectionKey(revision: appState.recipesRevision, count: appState.recipes.count),
            pantry: pantrySignatureIfNeeded(),
            query: localFilterQuery,
            selectedDifficulty: selectedDifficulty,
            selectedMealType: selectedMealType,
            selectedCuisine: selectedCuisine,
            dietaryTags: selectedDietaryTags,
            sortOrder: sortOrder,
            showOnlyFavorites: showOnlyFavorites,
            showCanMakeOnly: showCanMakeOnly,
            showWithSubstitutions: showWithSubstitutions
        )
        if cachedUserFilterKey == key {
            return cachedUserFilterResult
        }

        var recipes = appState.recipes
        let pantryMatchCache = pantryMatchCacheIfNeeded(for: recipes)

        recipes = applyCommonFilters(recipes)

        if showOnlyFavorites {
            recipes = recipes.filter { $0.isFavorite }
        }

        if showCanMakeOnly {
            recipes = applyMakeabilityFilter(recipes, matchCache: pantryMatchCache)
        }

        let result = applySortOrder(recipes, matchCache: pantryMatchCache)
        cachedUserFilterKey = key
        cachedUserFilterResult = result
        return result
    }

    // MARK: - Filtered Discover Recipes (bundled + cached + API search results)

    var filteredDiscoverRecipes: [Recipe] {
        let key = DiscoverFilterCacheKey(
            discoverSearchSource: appStateCollectionKey(revision: discoverSearchResultsRevision, count: discoverSearchResults.count),
            discoverPoolSource: appStateCollectionKey(revision: appState.discoverRecipesRevision, count: appState.discoverRecipes.count),
            pantry: pantrySignatureIfNeeded(),
            query: localFilterQuery,
            selectedDifficulty: selectedDifficulty,
            selectedMealType: selectedMealType,
            selectedCuisine: selectedCuisine,
            dietaryTags: selectedDietaryTags,
            sortOrder: sortOrder,
            showCanMakeOnly: showCanMakeOnly,
            showWithSubstitutions: showWithSubstitutions
        )
        if cachedDiscoverFilterKey == key {
            return cachedDiscoverFilterResult
        }

        // When API search results are present, treat them as the authoritative
        // list to keep Discover rendering fast and pagination stable.
        // Fall back to seed/cached pool only when no API results exist.
        var recipes: [Recipe]
        if !discoverSearchResults.isEmpty {
            recipes = discoverSearchResults
        } else {
            recipes = appState.discoverRecipes
        }

        let pantryMatchCache = pantryMatchCacheIfNeeded(for: recipes)

        recipes = applyCommonFilters(recipes)

        if showCanMakeOnly {
            recipes = applyMakeabilityFilter(recipes, matchCache: pantryMatchCache)
        }

        // Only apply local sort when browsing seed recipes (no API results).
        // When API results are present the server already sorted them
        // (by relevance or popularity) and re-sorting would break
        // pagination order and scroll position.
        if discoverSearchResults.isEmpty {
            recipes = applySortOrder(recipes, matchCache: pantryMatchCache)
        }

        cachedDiscoverFilterKey = key
        cachedDiscoverFilterResult = recipes
        return recipes
    }

    // MARK: - Legacy compatibility

    var filteredRecipes: [Recipe] {
        filteredUserRecipes
    }

    // MARK: - Common Filter Logic

    private func applyCommonFilters(_ input: [Recipe]) -> [Recipe] {
        var recipes = input

        if !localFilterQuery.isEmpty {
            let query = localFilterQuery
            let index = searchIndex(for: recipes, cacheKey: searchIndexCacheKey(for: recipes))
            let queryTokens = RecipeSearchIndex.tokenize(query)
            if let candidateIDs = index.candidateIDs(for: queryTokens), !candidateIDs.isEmpty {
                recipes = recipes.filter { recipe in
                    candidateIDs.contains(recipe.id) && matchesQuery(recipe, query: query)
                }
            } else {
                recipes = recipes.filter { recipe in
                    matchesQuery(recipe, query: query)
                }
            }
        }

        if let difficulty = selectedDifficulty {
            recipes = recipes.filter { $0.difficulty == difficulty }
        }

        if let mealType = selectedMealType {
            recipes = recipes.filter { $0.mealType == mealType }
        }

        if let cuisine = selectedCuisine {
            recipes = recipes.filter { $0.cuisine == cuisine }
        }

        if !selectedDietaryTags.isEmpty {
            recipes = recipes.filter { recipe in
                selectedDietaryTags.isSubset(of: Set(recipe.dietaryTags))
            }
        }

        return recipes
    }

    private func pantryMatchCacheIfNeeded(for recipes: [Recipe]) -> [UUID: PantryMatchResult]? {
        // Filtering and sorting now use persisted lightweight metrics.
        // Keep this hook for compatibility with callers that may still pass a map.
        _ = recipes
        return nil
    }

    func matchMetricsMap(for recipes: [Recipe]) -> [UUID: RecipeMatchMetrics] {
        guard !appState.pantryItems.isEmpty, !recipes.isEmpty else { return [:] }

        let pantry = appState.pantryItems
        let pantrySig = pantryMetricsSignature(for: pantry)
        hydratePersistedMetricsIfNeeded(for: pantrySig)
        let dependencyIndex = ingredientDependencyIndex(for: recipes)
        let pantryState = pantryDependencyState(for: pantry, signature: pantrySig)

        var metricsMap = persistedMetrics[pantrySig] ?? [:]
        let seededMetrics = seedMetricsFromNearbyPantryState(
            pantrySignature: pantrySig,
            pantryState: pantryState,
            recipes: recipes,
            dependencyIndex: dependencyIndex,
            existingMetrics: metricsMap
        )
        if !seededMetrics.isEmpty {
            metricsMap.merge(seededMetrics) { current, _ in current }
            persistedMetrics[pantrySig] = metricsMap
        }

        let missingRecipes = recipes.filter { recipe in
            guard let cached = metricsMap[recipe.id] else { return true }
            return cached.recipeDigest != Self.recipeDigest(recipe)
        }

        if !missingRecipes.isEmpty {
            let computed = Dictionary(uniqueKeysWithValues: missingRecipes.map { recipe in
                let match = recipe.pantryMatch(pantry: pantry)
                return (recipe.id, PersistedRecipeMatchMetrics(recipeDigest: Self.recipeDigest(recipe), metrics: RecipeMatchMetrics(from: match)))
            })
            metricsMap.merge(computed) { _, new in new }
            persistedMetrics[pantrySig] = metricsMap
            persistMetrics(pantrySignature: pantrySig, metrics: metricsMap)
        }

        return Dictionary(uniqueKeysWithValues: recipes.compactMap { recipe in
            guard let metrics = metricsMap[recipe.id]?.metrics else { return nil }
            return (recipe.id, metrics)
        })
    }

    func matchMap(for recipes: [Recipe]) -> [UUID: PantryMatchResult] {
        guard !appState.pantryItems.isEmpty, !recipes.isEmpty else { return [:] }

        let key = MatchMapCacheKey(
            pantry: appStateCollectionKey(revision: appState.pantryRevision, count: appState.pantryItems.count),
            recipes: recipeContentSignature(recipes)
        )
        if let cached = matchMapCache[key] {
            // Keep hot keys near the end (simple LRU behavior)
            matchMapCacheOrder.removeAll { $0 == key }
            matchMapCacheOrder.append(key)
            return cached
        }

        let pantry = appState.pantryItems
        let map = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0.pantryMatch(pantry: pantry)) })

        insertMatchMapCache(key: key, map: map)

        return map
    }

    private func pantrySignatureIfNeeded() -> AppStateCollectionKey? {
        guard showCanMakeOnly || sortOrder == .matchPercent else { return nil }
        return appStateCollectionKey(revision: appState.pantryRevision, count: appState.pantryItems.count)
    }

    private func applyMakeabilityFilter(_ recipes: [Recipe], matchCache: [UUID: PantryMatchResult]? = nil) -> [Recipe] {
        let metrics = matchMetricsMap(for: recipes)
        return recipes.filter { recipe in
            let fallback = matchCache?[recipe.id].map(RecipeMatchMetrics.init(from:))
            let matchMetrics = metrics[recipe.id] ?? fallback
            if matchMetrics?.canMake == true { return true }
            if showWithSubstitutions && matchMetrics?.canMakeWithSubstitutions == true { return true }
            return false
        }
    }

    private func applySortOrder(_ recipes: [Recipe], matchCache: [UUID: PantryMatchResult]? = nil) -> [Recipe] {
        var sorted = recipes
        switch sortOrder {
        case .recent:
            sorted.sort { $0.dateAdded > $1.dateAdded }
        case .name:
            sorted.sort { $0.title < $1.title }
        case .difficulty:
            sorted.sort { $0.difficulty.rawValue < $1.difficulty.rawValue }
        case .time:
            sorted.sort { ($0.totalTimeMinutes ?? 999) < ($1.totalTimeMinutes ?? 999) }
        case .mostCooked:
            sorted.sort { $0.timesCooked > $1.timesCooked }
        case .matchPercent:
            let metrics = matchMetricsMap(for: sorted)
            let percentages = Dictionary(uniqueKeysWithValues:
                sorted.map { recipe in
                    let fallback = matchCache?[recipe.id].map(RecipeMatchMetrics.init(from:))
                    let pct = metrics[recipe.id]?.effectiveMatchPercentage ?? fallback?.effectiveMatchPercentage ?? 0
                    return (recipe.id, pct)
                }
            )
            sorted.sort {
                (percentages[$0.id] ?? 0) > (percentages[$1.id] ?? 0)
            }
        }
        return sorted
    }

    // MARK: - Actions

    func addRecipe(_ recipe: Recipe) {
        runTask { [self] in
            await self.recipeActions.addRecipe(recipe)
        }
    }

    func deleteRecipe(_ recipe: Recipe) {
        runTask { [self] in
            await self.recipeActions.deleteRecipe(recipe)
        }
    }

    func toggleFavorite(_ recipe: Recipe) {
        runTask { [self] in
            await self.recipeActions.toggleFavorite(recipe)
        }
    }

    /// Called when searchText changes — debounces then triggers API search on Discover tab.
    func onSearchTextChanged(isDiscoverTab: Bool) {
        let normalizedQuery = SearchQuerySupport.normalized(searchText)

        // Debounce local filtering to avoid full-list recomputation on each keystroke.
        SearchQuerySupport.schedule(text: searchText, debouncer: localFilterDebouncer) {
            self.localFilterQuery = $0
        }

        apiSearchDebouncer.cancel()
        guard isDiscoverTab else { return }
        guard normalizedQuery.count >= 2 else {
            // Clear API results for very short queries
            if normalizedQuery.isEmpty { discoverSearchResults = [] }
            return
        }
        apiSearchDebouncer.schedule(after: DebounceDurations.apiSearch) {
            await self.searchDiscoverRecipes(query: normalizedQuery)
        }
    }

    func applySearchTextImmediately() {
        localFilterDebouncer.cancel()
        localFilterQuery = SearchQuerySupport.normalized(searchText)
    }

    /// Activate "What Can I Make" mode — pre-applies the can-make filter
    func activateWhatCanIMake() {
        showCanMakeOnly = true
        sortOrder = .matchPercent
    }

    /// Builds the common params from current filter state
    private func buildSearchParams(query: String?, offset: Int) -> SpoonacularService.ComplexSearchParams {
        var params = SpoonacularService.ComplexSearchParams()
        params.query = query
        params.cuisine = selectedCuisine
        params.mealType = selectedMealType
        params.diet = selectedDietaryTags.first
        params.number = 20
        params.offset = offset
        // Sort by popularity when browsing (no search query)
        if query == nil || query?.isEmpty == true {
            params.sort = "popularity"
            params.sortDirection = "desc"
        }
        if showCanMakeOnly {
            params.includeIngredients = appState.pantryItems.map { $0.name }
        }
        return params
    }

    /// Search Spoonacular API for more recipes (resets pagination)
    func searchDiscoverRecipes(query: String? = nil) async {
        // Skip API call when no key is configured — local filtering still works
        guard !AppConfig.spoonacularAPIKey.isEmpty else { return }
        guard !isSearchingAPI else { return }
        isSearchingAPI = true
        defer { isSearchingAPI = false }

        // Reset pagination for new search
        neverSearchedAPI = false
        currentSearchOffset = 0
        totalSearchResults = 0
        discoverSearchResults = []

        let effectiveQuery = query?.isEmpty == true ? nil : query

        do {
            let params = buildSearchParams(query: effectiveQuery, offset: 0)

            let (recipes, total) = try await SpoonacularService.shared.complexSearchWithRecipes(params)
            discoverSearchResults = recipes
            totalSearchResults = total
            currentSearchOffset = recipes.count

            // Cache in the background so UI updates stay responsive.
            Task { [appState] in
                for recipe in recipes {
                    await appState.cacheDiscoverRecipe(recipe)
                }
            }
        } catch {
            captureError(error)
        }
    }

    /// Load the next page of API results (called on scroll)
    func loadMoreDiscoverRecipes() {
        runTask { [self] in
            await self.performLoadMoreDiscoverRecipes()
        }
    }

    private func performLoadMoreDiscoverRecipes() async {
        guard !AppConfig.spoonacularAPIKey.isEmpty else { return }
        guard !isLoadingMore, !isSearchingAPI, hasMorePages else { return }

        // First-ever scroll: treat as initial popular search
        if neverSearchedAPI {
            neverSearchedAPI = false
            await searchDiscoverRecipes(query: searchText.isEmpty ? nil : searchText)
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let effectiveQuery = searchText.isEmpty ? nil : searchText

        do {
            let params = buildSearchParams(query: effectiveQuery, offset: currentSearchOffset)

            let (recipes, total) = try await SpoonacularService.shared.complexSearchWithRecipes(params)
            discoverSearchResults.append(contentsOf: recipes)
            totalSearchResults = total
            currentSearchOffset += recipes.count

            // Cache in the background so pagination remains smooth.
            Task { [appState] in
                for recipe in recipes {
                    await appState.cacheDiscoverRecipe(recipe)
                }
            }
        } catch {
            captureError(error)
        }
    }

    func importFromURL(_ urlString: String, onComplete: (@MainActor () -> Void)? = nil) {
        runLoadingTask { [self] in
            if let result = await appState.aiService.parseRecipeFromURL(urlString) {
                self.importedRecipe = result.toRecipe()
            }
            onComplete?()
        }
    }

    func clearFilters() {
        selectedDifficulty = nil
        selectedMealType = nil
        selectedCuisine = nil
        selectedDietaryTags = []
        showOnlyFavorites = false
        showCanMakeOnly = false
        searchText = ""
        localFilterQuery = ""
        sortOrder = .recent
    }

    var hasActiveFilters: Bool {
        selectedDifficulty != nil ||
        selectedMealType != nil ||
        selectedCuisine != nil ||
        !selectedDietaryTags.isEmpty ||
        showOnlyFavorites ||
        showCanMakeOnly
    }

    func recipeForNavigation(id: UUID) -> Recipe? {
        if let user = appState.recipes.first(where: { $0.id == id }) {
            return user
        }
        if let searched = discoverSearchResults.first(where: { $0.id == id }) {
            return searched
        }
        return appState.discoverRecipes.first(where: { $0.id == id })
    }

    func prewarmDiscover(visibleCount: Int) {
        guard !hasPrewarmedDiscover else { return }
        hasPrewarmedDiscover = true

        let recipes = filteredDiscoverRecipes
        let visible = Array(recipes.prefix(max(visibleCount, 1)))
        _ = matchMap(for: visible)
    }

    func scheduleBackgroundMatchPrewarm(visibleDiscoverCount: Int) {
        let pantry = appState.pantryItems
        guard !pantry.isEmpty else { return }

        let pantryKey = appStateCollectionKey(revision: appState.pantryRevision, count: pantry.count)
        if lastPrewarmedPantryRevision == appState.pantryRevision {
            return
        }
        lastPrewarmedPantryRevision = appState.pantryRevision

        let discoverCandidates = filteredDiscoverRecipes
        let discoverSample = Array(discoverCandidates.prefix(max(visibleDiscoverCount, 1)))
        let userSample = Array(appState.recipes.prefix(24))

        guard !discoverSample.isEmpty || !userSample.isEmpty else { return }

        prewarmTask?.cancel()
        prewarmTask = Task.detached(priority: .utility) {
            let userMap: [UUID: PantryMatchResult] = userSample.isEmpty
                ? [:]
                : Dictionary(uniqueKeysWithValues: userSample.map { ($0.id, $0.pantryMatch(pantry: pantry)) })

            let discoverMap: [UUID: PantryMatchResult] = discoverSample.isEmpty
                ? [:]
                : Dictionary(uniqueKeysWithValues: discoverSample.map { ($0.id, $0.pantryMatch(pantry: pantry)) })

            await MainActor.run {
                if !userMap.isEmpty {
                    let key = MatchMapCacheKey(
                        pantry: pantryKey,
                        recipes: self.recipeContentSignature(userSample)
                    )
                    self.insertMatchMapCache(key: key, map: userMap)
                    let userRecipesByID = Dictionary(uniqueKeysWithValues: userSample.map { ($0.id, $0) })
                    let userMetricPairs: [(UUID, PersistedRecipeMatchMetrics)] = userMap.compactMap { id, match in
                        guard let recipe = userRecipesByID[id] else { return nil }
                        return (id, PersistedRecipeMatchMetrics(recipeDigest: Self.recipeDigest(recipe), metrics: RecipeMatchMetrics(from: match)))
                    }
                    let userMetrics = Dictionary(uniqueKeysWithValues: userMetricPairs)
                    self.insertMetricsCache(pantrySignature: self.pantryMetricsSignature(for: pantry), metrics: userMetrics)
                }
                if !discoverMap.isEmpty {
                    let key = MatchMapCacheKey(
                        pantry: pantryKey,
                        recipes: self.recipeContentSignature(discoverSample)
                    )
                    self.insertMatchMapCache(key: key, map: discoverMap)
                    let discoverRecipesByID = Dictionary(uniqueKeysWithValues: discoverSample.map { ($0.id, $0) })
                    let discoverMetricPairs: [(UUID, PersistedRecipeMatchMetrics)] = discoverMap.compactMap { id, match in
                        guard let recipe = discoverRecipesByID[id] else { return nil }
                        return (id, PersistedRecipeMatchMetrics(recipeDigest: Self.recipeDigest(recipe), metrics: RecipeMatchMetrics(from: match)))
                    }
                    let discoverMetrics = Dictionary(uniqueKeysWithValues: discoverMetricPairs)
                    self.insertMetricsCache(pantrySignature: self.pantryMetricsSignature(for: pantry), metrics: discoverMetrics)
                }
            }
        }
    }

    func scheduleFullMetricsCoverage(reason: String) {
        guard shouldPrecomputeFullCoverage else { return }

        let pantry = appState.pantryItems
        guard !pantry.isEmpty else { return }

        let allRecipes = uniqueRecipes(appState.recipes + appState.discoverRecipes + discoverSearchResults)
        guard !allRecipes.isEmpty else { return }

        let pantrySig = pantryMetricsSignature(for: pantry)
        let coverageKey = FullCoverageKey(
            pantry: appStateCollectionKey(revision: appState.pantryRevision, count: appState.pantryItems.count),
            userRecipes: appStateCollectionKey(revision: appState.recipesRevision, count: appState.recipes.count),
            discoverRecipes: appStateCollectionKey(revision: appState.discoverRecipesRevision, count: appState.discoverRecipes.count),
            searchedRecipes: appStateCollectionKey(revision: discoverSearchResultsRevision, count: discoverSearchResults.count)
        )
        if lastFullCoverageKey == coverageKey {
            return
        }
        lastFullCoverageKey = coverageKey

        hydratePersistedMetricsIfNeeded(for: pantrySig)
        let alreadyCached = persistedMetrics[pantrySig] ?? [:]
        let missing = allRecipes.filter { alreadyCached[$0.id] == nil }
        guard !missing.isEmpty else { return }

        fullCoverageTask?.cancel()
        fullCoverageTask = Task.detached(priority: .utility) {
            var chunkStart = 0
            var accumulated: [UUID: PersistedRecipeMatchMetrics] = [:]
            while chunkStart < missing.count {
                if Task.isCancelled { return }

                let next = min(chunkStart + self.fullCoverageChunkSize, missing.count)
                let chunk = Array(missing[chunkStart..<next])
                let chunkMetrics = Dictionary(uniqueKeysWithValues: chunk.map { recipe in
                    (
                        recipe.id,
                        PersistedRecipeMatchMetrics(
                            recipeDigest: Self.recipeDigest(recipe),
                            metrics: RecipeMatchMetrics(from: recipe.pantryMatch(pantry: pantry))
                        )
                    )
                })

                accumulated.merge(chunkMetrics) { _, new in new }

                await MainActor.run {
                    self.insertMetricsCache(pantrySignature: pantrySig, metrics: chunkMetrics, persist: false)
                }

                chunkStart = next
            }

            let completedMetrics = accumulated

            await MainActor.run {
                var merged = self.persistedMetrics[pantrySig] ?? [:]
                merged.merge(completedMetrics) { _, new in new }
                self.persistedMetrics[pantrySig] = merged
                self.persistMetrics(pantrySignature: pantrySig, metrics: merged)
            }
        }
    }

    private func insertMatchMapCache(key: MatchMapCacheKey, map: [UUID: PantryMatchResult]) {
        matchMapCache[key] = map
        matchMapCacheOrder.removeAll { $0 == key }
        matchMapCacheOrder.append(key)
        if matchMapCacheOrder.count > maxMatchMapCacheEntries,
           let evicted = matchMapCacheOrder.first {
            matchMapCacheOrder.removeFirst()
            matchMapCache.removeValue(forKey: evicted)
        }
    }

    private func matchesQuery(_ recipe: Recipe, query: String) -> Bool {
        recipe.title.localizedCaseInsensitiveContains(query) ||
        (recipe.description?.localizedCaseInsensitiveContains(query) ?? false) ||
        recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) } ||
        (recipe.cuisine?.rawValue.localizedCaseInsensitiveContains(query) ?? false) ||
        (recipe.mealType?.rawValue.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func searchIndex(for recipes: [Recipe], cacheKey: SearchIndexCacheKey) -> RecipeSearchIndex {
        if let cached = searchIndexCache[cacheKey] {
            return cached
        }
        let built = RecipeSearchIndex(recipes: recipes)
        searchIndexCache[cacheKey] = built
        return built
    }

    private func ingredientDependencyIndex(for recipes: [Recipe]) -> RecipeIngredientDependencyIndex {
        let signature = recipeContentSignature(recipes)
        if let cached = ingredientDependencyIndexCache[signature] {
            return cached
        }

        let built = RecipeIngredientDependencyIndex(recipes: recipes)
        ingredientDependencyIndexCache[signature] = built
        return built
    }

    private func pantryDependencyState(for pantry: [PantryItem], signature: PantryMetricsSignature) -> PantryDependencyState {
        if let cached = pantryDependencyStateCache[signature] {
            return cached
        }

        var fingerprintsByKey: [String: [String]] = [:]
        for pantryItem in pantry {
            let fingerprint = pantryDependencyFingerprint(for: pantryItem)
            for key in IngredientMatcher.dependencyKeys(for: pantryItem) {
                fingerprintsByKey[key, default: []].append(fingerprint)
            }
        }

        let built = PantryDependencyState(
            fingerprints: Dictionary(uniqueKeysWithValues: fingerprintsByKey.map { key, fingerprints in
                var hasher = StableDigestHasher()
                hasher.combine(fingerprints.count)
                for fingerprint in fingerprints.sorted() {
                    hasher.combine(fingerprint)
                }
                return (key, hasher.finalize())
            })
        )
        pantryDependencyStateCache[signature] = built
        return built
    }

    private func seedMetricsFromNearbyPantryState(
        pantrySignature: PantryMetricsSignature,
        pantryState: PantryDependencyState,
        recipes: [Recipe],
        dependencyIndex: RecipeIngredientDependencyIndex,
        existingMetrics: [UUID: PersistedRecipeMatchMetrics]
    ) -> [UUID: PersistedRecipeMatchMetrics] {
        let candidateRecipeIDs = Set(recipes.map(\.id))

        for previousSignature in persistedMetricSignatureOrder.reversed() where previousSignature != pantrySignature {
            guard let previousMetrics = persistedMetrics[previousSignature],
                  let previousState = pantryDependencyStateCache[previousSignature] else {
                continue
            }

            let changedKeys = pantryState.changedKeys(comparedTo: previousState)
            let affectedRecipeIDs = dependencyIndex.recipeIDs(affectedBy: changedKeys)
            let reusable = previousMetrics.filter { id, _ in
                candidateRecipeIDs.contains(id)
                    && existingMetrics[id] == nil
                    && !affectedRecipeIDs.contains(id)
            }
            if !reusable.isEmpty {
                return reusable
            }
        }

        return [:]
    }

    private func insertMetricsCache(pantrySignature: PantryMetricsSignature, metrics: [UUID: PersistedRecipeMatchMetrics], persist: Bool = true) {
        guard !metrics.isEmpty else { return }
        var current = persistedMetrics[pantrySignature] ?? [:]
        var changed = false
        for (id, metric) in metrics {
            if current[id] != metric {
                current[id] = metric
                changed = true
            }
        }
        persistedMetrics[pantrySignature] = current
        if changed && persist {
            persistMetrics(pantrySignature: pantrySignature, metrics: current)
        }
    }

    private func uniqueRecipes(_ recipes: [Recipe]) -> [Recipe] {
        var seen: Set<UUID> = []
        var unique: [Recipe] = []
        unique.reserveCapacity(recipes.count)
        for recipe in recipes where seen.insert(recipe.id).inserted {
            unique.append(recipe)
        }
        return unique
    }

    private var shouldPrecomputeFullCoverage: Bool {
        showCanMakeOnly || sortOrder == .matchPercent
    }

    private func searchIndexCacheKey(for recipes: [Recipe]) -> SearchIndexCacheKey {
        if recipes == appState.recipes {
            return .appState(appStateCollectionKey(revision: appState.recipesRevision, count: appState.recipes.count))
        }

        if recipes == appState.discoverRecipes {
            return .appState(appStateCollectionKey(revision: appState.discoverRecipesRevision, count: appState.discoverRecipes.count))
        }

        if recipes == discoverSearchResults {
            return .appState(appStateCollectionKey(revision: discoverSearchResultsRevision, count: discoverSearchResults.count))
        }

        return .content(recipeContentSignature(recipes))
    }

    private func appStateCollectionKey(revision: Int, count: Int) -> AppStateCollectionKey {
        AppStateCollectionKey(revision: revision, count: count)
    }

    private func pantryDependencyFingerprint(for pantryItem: PantryItem) -> String {
        var hasher = StableDigestHasher()
        hasher.combine(pantryItem.id.uuidString)
        hasher.combine(pantryItem.name)
        hasher.combine(pantryItem.catalogItemID ?? "")
        hasher.combine(pantryItem.quantityMode.rawValue)
        hasher.combine(pantryItem.quantity ?? -1)
        hasher.combine(pantryItem.unit?.rawValue ?? "")
        hasher.combine(pantryItem.facets.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: "|"))
        return hasher.finalize()
    }

    private func recipeContentSignature(_ recipes: [Recipe]) -> RecipeContentSignature {
        var hasher = StableDigestHasher()
        hasher.combine(recipes.count)
        for recipe in recipes {
            hasher.combine(Self.recipeDigest(recipe))
        }
        return RecipeContentSignature(count: recipes.count, digest: hasher.finalize())
    }

    nonisolated private static func recipeDigest(_ recipe: Recipe) -> String {
        var hasher = StableDigestHasher()
        hasher.combine(recipe.id.uuidString)
        hasher.combine(recipe.title)
        hasher.combine(recipe.description ?? "")
        hasher.combine(recipe.cuisine?.rawValue ?? "")
        hasher.combine(recipe.mealType?.rawValue ?? "")
        hasher.combine(recipe.isFavorite)
        hasher.combine(recipe.timesCooked)
        hasher.combine(recipe.totalTimeMinutes ?? -1)
        hasher.combine(recipe.ingredients.count)
        for ingredient in recipe.ingredients {
            hasher.combine(ingredient.name)
            hasher.combine(ingredient.displayText)
            hasher.combine(ingredient.quantity)
            hasher.combine(ingredient.unit?.rawValue ?? "")
            hasher.combine(ingredient.isOptional)
        }
        return hasher.finalize()
    }

    private func pantryMetricsSignature(for pantry: [PantryItem]) -> PantryMetricsSignature {
        var hasher = StableDigestHasher()
        hasher.combine(pantry.count)
        for item in pantry.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(item.id.uuidString)
            hasher.combine(item.name)
            hasher.combine(item.category.rawValue)
            hasher.combine(item.quantityMode.rawValue)
            hasher.combine(item.quantity ?? -1)
            hasher.combine(item.unit?.rawValue ?? "")
            hasher.combine(item.catalogItemID ?? "")
            hasher.combine(item.storage.rawValue)
            hasher.combine(item.facets.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: "|"))
        }
        return PantryMetricsSignature(count: pantry.count, digest: hasher.finalize())
    }

    private func hydratePersistedMetricsIfNeeded(for pantrySignature: PantryMetricsSignature) {
        loadPersistedMetricsStoreIfNeeded()
        if persistedMetricSignatureOrder.contains(pantrySignature) {
            persistedMetricSignatureOrder.removeAll { $0 == pantrySignature }
            persistedMetricSignatureOrder.append(pantrySignature)
        }
    }

    private func loadPersistedMetricsStoreIfNeeded() {
        guard !persistedMetricsStoreLoaded else { return }
        persistedMetricsStoreLoaded = true
        guard shouldUsePersistedMetricsStore else { return }

        guard let fileURL = matchMetricsCacheFileURL else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let payload = try? JSONDecoder().decode(PersistedMatchMetricsPayload.self, from: data) else { return }

        persistedMetricSignatureOrder = payload.entries.map(\.pantrySignature)
        persistedMetrics = Dictionary(uniqueKeysWithValues: payload.entries.map { ($0.pantrySignature, $0.metrics) })
    }

    private func persistMetrics(pantrySignature: PantryMetricsSignature, metrics: [UUID: PersistedRecipeMatchMetrics]) {
        guard shouldUsePersistedMetricsStore else { return }
        guard let fileURL = matchMetricsCacheFileURL else { return }
        loadPersistedMetricsStoreIfNeeded()

        persistedMetrics[pantrySignature] = metrics
        persistedMetricSignatureOrder.removeAll { $0 == pantrySignature }
        persistedMetricSignatureOrder.append(pantrySignature)
        while persistedMetricSignatureOrder.count > maxPersistedMetricSignatures {
            let evicted = persistedMetricSignatureOrder.removeFirst()
            persistedMetrics.removeValue(forKey: evicted)
        }

        let payload = PersistedMatchMetricsPayload(
            entries: persistedMetricSignatureOrder.compactMap { signature in
                guard let metrics = persistedMetrics[signature] else { return nil }
                return PersistedMetricEntry(pantrySignature: signature, metrics: metrics)
            }
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: fileURL, options: .atomic)
        } catch { }
    }

    private var matchMetricsCacheFileURL: URL? {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cachesDirectory
            .appendingPathComponent("PantryChef", isDirectory: true)
            .appendingPathComponent("match_metrics_v2.json")
    }

    private var shouldUsePersistedMetricsStore: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
}

struct RecipeMatchMetrics: Codable, Hashable {
    let canMake: Bool
    let canMakeWithSubstitutions: Bool
    let effectiveMatchPercentage: Double
    let missingIngredientCount: Int

    init(canMake: Bool, canMakeWithSubstitutions: Bool, effectiveMatchPercentage: Double, missingIngredientCount: Int) {
        self.canMake = canMake
        self.canMakeWithSubstitutions = canMakeWithSubstitutions
        self.effectiveMatchPercentage = effectiveMatchPercentage
        self.missingIngredientCount = missingIngredientCount
    }

    init(from match: PantryMatchResult) {
        self.init(
            canMake: match.canMake,
            canMakeWithSubstitutions: match.canMakeWithSubstitutions,
            effectiveMatchPercentage: match.effectiveMatchPercentage,
            missingIngredientCount: match.missingIngredients.count
        )
    }
}

private struct PersistedMatchMetricsPayload: Codable {
    let entries: [PersistedMetricEntry]
}

private struct PersistedMetricEntry: Codable, Hashable {
    let pantrySignature: PantryMetricsSignature
    let metrics: [UUID: PersistedRecipeMatchMetrics]
}

private struct PersistedRecipeMatchMetrics: Codable, Hashable {
    let recipeDigest: String
    let metrics: RecipeMatchMetrics
}

private struct RecipeSearchIndex {
    let tokenToRecipeIDs: [String: Set<UUID>]

    init(recipes: [Recipe]) {
        var index: [String: Set<UUID>] = [:]
        for recipe in recipes {
            let searchable = [
                recipe.title,
                recipe.description ?? "",
                recipe.cuisine?.rawValue ?? "",
                recipe.mealType?.rawValue ?? "",
                recipe.ingredients.map(\.name).joined(separator: " "),
            ].joined(separator: " ")

            for token in Self.tokenize(searchable) {
                index[token, default: []].insert(recipe.id)
            }
        }
        self.tokenToRecipeIDs = index
    }

    func candidateIDs(for queryTokens: [String]) -> Set<UUID>? {
        guard !queryTokens.isEmpty else { return nil }
        var resolvedSets: [Set<UUID>] = []

        for token in queryTokens {
            guard token.count >= 2 else { return nil }

            var ids = tokenToRecipeIDs[token] ?? []
            if ids.isEmpty {
                for (indexedToken, indexedIDs) in tokenToRecipeIDs where indexedToken.hasPrefix(token) {
                    ids.formUnion(indexedIDs)
                }
            }
            if ids.isEmpty { return [] }
            resolvedSets.append(ids)
        }

        guard var intersection = resolvedSets.first else { return nil }
        for set in resolvedSets.dropFirst() {
            intersection.formIntersection(set)
            if intersection.isEmpty {
                return []
            }
        }
        return intersection
    }

    static func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

private struct RecipeIngredientDependencyIndex {
    let keysByRecipeID: [UUID: Set<String>]
    let recipeIDsByKey: [String: Set<UUID>]

    init(recipes: [Recipe]) {
        var keysByRecipeID: [UUID: Set<String>] = [:]
        var recipeIDsByKey: [String: Set<UUID>] = [:]

        for recipe in recipes {
            let keys = Set(recipe.ingredients.filter { !$0.isOptional }.flatMap { IngredientMatcher.dependencyKeys(for: $0) })
            keysByRecipeID[recipe.id] = keys
            for key in keys {
                recipeIDsByKey[key, default: []].insert(recipe.id)
            }
        }

        self.keysByRecipeID = keysByRecipeID
        self.recipeIDsByKey = recipeIDsByKey
    }

    func recipeIDs(affectedBy keys: Set<String>) -> Set<UUID> {
        guard !keys.isEmpty else { return [] }
        var affected: Set<UUID> = []
        for key in keys {
            affected.formUnion(recipeIDsByKey[key] ?? [])
        }
        return affected
    }
}

private struct PantryDependencyState {
    let fingerprints: [String: String]

    func changedKeys(comparedTo other: PantryDependencyState) -> Set<String> {
        let allKeys = Set(fingerprints.keys).union(other.fingerprints.keys)
        return Set(allKeys.filter { fingerprints[$0] != other.fingerprints[$0] })
    }
}

private struct UserFilterCacheKey: Hashable {
    let source: AppStateCollectionKey
    let pantry: AppStateCollectionKey?
    let query: String
    let selectedDifficulty: DifficultyLevel?
    let selectedMealType: MealType?
    let selectedCuisine: CuisineType?
    let dietaryTags: Set<DietaryTag>
    let sortOrder: RecipeViewModel.SortOrder
    let showOnlyFavorites: Bool
    let showCanMakeOnly: Bool
    let showWithSubstitutions: Bool
}

private struct DiscoverFilterCacheKey: Hashable {
    let discoverSearchSource: AppStateCollectionKey
    let discoverPoolSource: AppStateCollectionKey
    let pantry: AppStateCollectionKey?
    let query: String
    let selectedDifficulty: DifficultyLevel?
    let selectedMealType: MealType?
    let selectedCuisine: CuisineType?
    let dietaryTags: Set<DietaryTag>
    let sortOrder: RecipeViewModel.SortOrder
    let showCanMakeOnly: Bool
    let showWithSubstitutions: Bool
}

private struct MatchMapCacheKey: Hashable {
    let pantry: AppStateCollectionKey
    let recipes: RecipeContentSignature
}

private struct FullCoverageKey: Hashable {
    let pantry: AppStateCollectionKey
    let userRecipes: AppStateCollectionKey
    let discoverRecipes: AppStateCollectionKey
    let searchedRecipes: AppStateCollectionKey
}

struct RecipeCoverageRefreshState: Hashable {
    let catalog: RecipeCatalogRefreshState
    let discoverSearchSource: AppStateCollectionKey
}

private enum SearchIndexCacheKey: Hashable {
    case appState(AppStateCollectionKey)
    case content(RecipeContentSignature)
}

struct AppStateCollectionKey: Hashable {
    let revision: Int
    let count: Int
}

struct RecipeContentSignature: Hashable, Codable {
    let count: Int
    let digest: String
}

struct PantryMetricsSignature: Hashable, Codable {
    let count: Int
    let digest: String
}

private struct StableDigestHasher {
    private var hash: UInt64 = 0xcbf29ce484222325

    mutating func combine(_ value: String) {
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        combineDelimiter()
    }

    mutating func combine(_ value: Int) {
        combine(String(value))
    }

    mutating func combine(_ value: Double) {
        combine(String(value))
    }

    mutating func combine(_ value: Bool) {
        combine(value ? "1" : "0")
    }

    mutating func finalize() -> String {
        String(hash, radix: 16)
    }

    private mutating func combineDelimiter() {
        hash ^= 0xff
        hash &*= 0x100000001b3
    }
}
