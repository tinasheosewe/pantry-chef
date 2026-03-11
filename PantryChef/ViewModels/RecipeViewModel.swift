import SwiftUI

@Observable
@MainActor
final class RecipeViewModel {
    var searchText = ""
    var selectedDifficulty: DifficultyLevel?
    var selectedMealType: MealType?
    var selectedCuisine: CuisineType?
    var selectedDietaryTags: Set<DietaryTag> = []
    var showAddRecipe = false
    var showImportURL = false
    var showPhotoImport = false
    var sortOrder: SortOrder = .recent
    var showOnlyFavorites = false
    var showCanMakeOnly = false          // Filter to recipes user can make
    var showWithSubstitutions = true     // Include recipes makeable with subs
    var isLoading = false
    var importedRecipe: Recipe?

    // Discover search (Spoonacular)
    var discoverSearchResults: [Recipe] = []
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
    @ObservationIgnored private var persistedMetrics: [CollectionSignature: [UUID: RecipeMatchMetrics]] = [:]
    @ObservationIgnored private var loadedPersistedPantrySignature: CollectionSignature?
    @ObservationIgnored private var searchIndexCache: [CollectionSignature: RecipeSearchIndex] = [:]
    @ObservationIgnored private var hasPrewarmedDiscover = false
    @ObservationIgnored private var prewarmTask: Task<Void, Never>?
    @ObservationIgnored private var lastPrewarmedPantrySignature: CollectionSignature?
    @ObservationIgnored private var fullCoverageTask: Task<Void, Never>?
    @ObservationIgnored private var lastFullCoverageKey: FullCoverageKey?
    @ObservationIgnored private let fullCoverageChunkSize = 128
    private var localFilterQuery = ""
    private var currentSearchOffset = 0
    private var totalSearchResults = 0
    /// True until the first API search completes (enables scroll-to-load-more even before any search)
    private(set) var neverSearchedAPI = true
    var hasMorePages: Bool { neverSearchedAPI || currentSearchOffset < totalSearchResults }
    var effectiveSearchQuery: String { localFilterQuery }

    enum SortOrder: String, CaseIterable {
        case recent = "Recent"
        case name = "Name"
        case difficulty = "Difficulty"
        case time = "Time"
        case mostCooked = "Most Cooked"
        case matchPercent = "Match %"
    }

    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        self.localFilterQuery = ""

        // Startup verification: proactively hydrate full pantry metrics cache.
        Task { @MainActor in
            self.scheduleFullMetricsCoverage(reason: "startup")
        }
    }

    // MARK: - Filtered User Recipes

    var filteredUserRecipes: [Recipe] {
        let key = UserFilterCacheKey(
            source: collectionSignature(appState.recipes),
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
        let started = CFAbsoluteTimeGetCurrent()
        let key = DiscoverFilterCacheKey(
            discoverSearchSource: collectionSignature(discoverSearchResults),
            discoverPoolSource: collectionSignature(appState.discoverRecipes),
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
            PerfLog.event("Discover filter cache hit, count=\(cachedDiscoverFilterResult.count)")
            return cachedDiscoverFilterResult
        }
        PerfLog.event("Discover filter cache miss; api=\(discoverSearchResults.count), pool=\(appState.discoverRecipes.count), query='\(localFilterQuery)'")

        // When API search results are present, treat them as the authoritative
        // list to keep Discover rendering fast and pagination stable.
        // Fall back to seed/cached pool only when no API results exist.
        var recipes: [Recipe]
        if !discoverSearchResults.isEmpty {
            recipes = discoverSearchResults
        } else {
            recipes = appState.discoverRecipes
        }

        let pantryMatchCache = PerfLog.timed("Discover pantryMatchCache") {
            pantryMatchCacheIfNeeded(for: recipes)
        }

        recipes = PerfLog.timed("Discover applyCommonFilters") {
            applyCommonFilters(recipes)
        }

        if showCanMakeOnly {
            recipes = PerfLog.timed("Discover applyMakeabilityFilter") {
                applyMakeabilityFilter(recipes, matchCache: pantryMatchCache)
            }
        }

        // Only apply local sort when browsing seed recipes (no API results).
        // When API results are present the server already sorted them
        // (by relevance or popularity) and re-sorting would break
        // pagination order and scroll position.
        if discoverSearchResults.isEmpty {
            recipes = PerfLog.timed("Discover applySortOrder") {
                applySortOrder(recipes, matchCache: pantryMatchCache)
            }
        }

        cachedDiscoverFilterKey = key
        cachedDiscoverFilterResult = recipes
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        PerfLog.event("Discover total filter pass: \(elapsedMs)ms (out=\(recipes.count))")
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
            let index = searchIndex(for: recipes)
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

        let pantrySig = collectionSignature(appState.pantryItems)
        hydratePersistedMetricsIfNeeded(for: pantrySig)

        var metricsMap = persistedMetrics[pantrySig] ?? [:]
        let missingRecipes = recipes.filter { metricsMap[$0.id] == nil }

        if !missingRecipes.isEmpty {
            let pantry = appState.pantryItems
            let computed = Dictionary(uniqueKeysWithValues: missingRecipes.map { recipe in
                let match = recipe.pantryMatch(pantry: pantry)
                return (recipe.id, RecipeMatchMetrics(from: match))
            })
            metricsMap.merge(computed) { _, new in new }
            persistedMetrics[pantrySig] = metricsMap
            persistMetrics(pantrySignature: pantrySig, metrics: metricsMap)
        }

        return Dictionary(uniqueKeysWithValues: recipes.compactMap { recipe in
            guard let metrics = metricsMap[recipe.id] else { return nil }
            return (recipe.id, metrics)
        })
    }

    func matchMap(for recipes: [Recipe]) -> [UUID: PantryMatchResult] {
        guard !appState.pantryItems.isEmpty, !recipes.isEmpty else { return [:] }

        let key = MatchMapCacheKey(
            pantry: collectionSignature(appState.pantryItems),
            recipes: collectionSignature(recipes)
        )
        if let cached = matchMapCache[key] {
            // Keep hot keys near the end (simple LRU behavior)
            matchMapCacheOrder.removeAll { $0 == key }
            matchMapCacheOrder.append(key)
            PerfLog.event("matchMap cache hit, recipes=\(recipes.count)")
            return cached
        }

        let pantry = appState.pantryItems
        let map = PerfLog.timed("matchMap compute recipes=\(recipes.count)") {
            Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0.pantryMatch(pantry: pantry)) })
        }

        insertMatchMapCache(key: key, map: map)

        return map
    }

    private func pantrySignatureIfNeeded() -> CollectionSignature? {
        guard showCanMakeOnly || sortOrder == .matchPercent else { return nil }
        return collectionSignature(appState.pantryItems)
    }

    private func collectionSignature<T: Identifiable>(_ items: [T]) -> CollectionSignature where T.ID == UUID {
        CollectionSignature(
            count: items.count,
            first: items.first?.id,
            last: items.last?.id
        )
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

    func addRecipe(_ recipe: Recipe) async {
        await appState.addRecipe(recipe)
    }

    func deleteRecipe(_ recipe: Recipe) async {
        await appState.deleteRecipe(recipe)
    }

    func toggleFavorite(_ recipe: Recipe) async {
        await appState.toggleFavoriteWithSave(recipe)
    }

    /// Called when searchText changes — debounces then triggers API search on Discover tab.
    func onSearchTextChanged(isDiscoverTab: Bool) {
        localFilterDebouncer.cancel()
        let normalizedQuery = searchText.trimmingCharacters(in: .whitespaces)

        // Debounce local filtering to avoid full-list recomputation on each keystroke.
        localFilterDebouncer.schedule(after: DebounceDurations.quickSearch) {
            self.localFilterQuery = normalizedQuery
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
            appState.errorMessage = error.localizedDescription
        }
    }

    /// Load the next page of API results (called on scroll)
    func loadMoreDiscoverRecipes() async {
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
            appState.errorMessage = error.localizedDescription
        }
    }

    func importFromURL(_ urlString: String) async {
        isLoading = true
        defer { isLoading = false }

        if let result = await appState.aiService.parseRecipeFromURL(urlString) {
            importedRecipe = result.toRecipe()
        }
    }

    func importFromPhoto(extractedText: String) async {
        isLoading = true
        defer { isLoading = false }

        if let result = await appState.aiService.parseRecipeFromText(extractedText) {
            importedRecipe = result.toRecipe()
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
        PerfLog.event("Discover prewarm completed: visible=\(visible.count), total=\(recipes.count)")
    }

    func scheduleBackgroundMatchPrewarm(visibleDiscoverCount: Int) {
        let pantry = appState.pantryItems
        guard !pantry.isEmpty else { return }

        let pantrySig = collectionSignature(pantry)
        if lastPrewarmedPantrySignature == pantrySig {
            return
        }
        lastPrewarmedPantrySignature = pantrySig

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
                        pantry: pantrySig,
                        recipes: self.collectionSignature(userSample)
                    )
                    self.insertMatchMapCache(key: key, map: userMap)
                    let userMetrics = Dictionary(uniqueKeysWithValues: userMap.map { ($0.key, RecipeMatchMetrics(from: $0.value)) })
                    self.insertMetricsCache(pantrySignature: pantrySig, metrics: userMetrics)
                }
                if !discoverMap.isEmpty {
                    let key = MatchMapCacheKey(
                        pantry: pantrySig,
                        recipes: self.collectionSignature(discoverSample)
                    )
                    self.insertMatchMapCache(key: key, map: discoverMap)
                    let discoverMetrics = Dictionary(uniqueKeysWithValues: discoverMap.map { ($0.key, RecipeMatchMetrics(from: $0.value)) })
                    self.insertMetricsCache(pantrySignature: pantrySig, metrics: discoverMetrics)
                }
                PerfLog.event("Background prewarm complete: user=\(userMap.count), discover=\(discoverMap.count)")
            }
        }
    }

    func scheduleFullMetricsCoverage(reason: String) {
        let pantry = appState.pantryItems
        guard !pantry.isEmpty else { return }

        let allRecipes = uniqueRecipes(appState.recipes + appState.discoverRecipes + discoverSearchResults)
        guard !allRecipes.isEmpty else { return }

        let pantrySig = collectionSignature(pantry)
        let coverageKey = FullCoverageKey(
            pantry: pantrySig,
            userRecipes: collectionSignature(appState.recipes),
            discoverRecipes: collectionSignature(appState.discoverRecipes),
            searchedRecipes: collectionSignature(discoverSearchResults)
        )
        if lastFullCoverageKey == coverageKey {
            return
        }
        lastFullCoverageKey = coverageKey

        hydratePersistedMetricsIfNeeded(for: pantrySig)
        let alreadyCached = persistedMetrics[pantrySig] ?? [:]
        let missing = allRecipes.filter { alreadyCached[$0.id] == nil }
        guard !missing.isEmpty else {
            PerfLog.event("Full metrics coverage already complete: total=\(allRecipes.count)")
            return
        }

        fullCoverageTask?.cancel()
        fullCoverageTask = Task.detached(priority: .utility) {
            var chunkStart = 0
            var accumulated: [UUID: RecipeMatchMetrics] = [:]
            while chunkStart < missing.count {
                if Task.isCancelled { return }

                let next = min(chunkStart + self.fullCoverageChunkSize, missing.count)
                let chunk = Array(missing[chunkStart..<next])
                let chunkMetrics = Dictionary(uniqueKeysWithValues: chunk.map { recipe in
                    (recipe.id, RecipeMatchMetrics(from: recipe.pantryMatch(pantry: pantry)))
                })

                accumulated.merge(chunkMetrics) { _, new in new }

                await MainActor.run {
                    self.insertMetricsCache(pantrySignature: pantrySig, metrics: chunkMetrics, persist: false)
                }

                chunkStart = next
            }

            await MainActor.run {
                var merged = self.persistedMetrics[pantrySig] ?? [:]
                merged.merge(accumulated) { _, new in new }
                self.persistedMetrics[pantrySig] = merged
                self.persistMetrics(pantrySignature: pantrySig, metrics: merged)
                PerfLog.event("Full metrics coverage complete (\(reason)): computed=\(accumulated.count), total=\(allRecipes.count)")
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

    private func searchIndex(for recipes: [Recipe]) -> RecipeSearchIndex {
        let signature = collectionSignature(recipes)
        if let cached = searchIndexCache[signature] {
            return cached
        }
        let built = RecipeSearchIndex(recipes: recipes)
        searchIndexCache[signature] = built
        return built
    }

    private func insertMetricsCache(pantrySignature: CollectionSignature, metrics: [UUID: RecipeMatchMetrics], persist: Bool = true) {
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

    private func hydratePersistedMetricsIfNeeded(for pantrySignature: CollectionSignature) {
        guard loadedPersistedPantrySignature != pantrySignature else { return }
        loadedPersistedPantrySignature = pantrySignature
        guard let loaded = loadPersistedMetrics(), loaded.pantrySignature == pantrySignature else {
            return
        }
        persistedMetrics[pantrySignature] = loaded.metrics
        PerfLog.event("Loaded persisted match metrics: \(loaded.metrics.count)")
    }

    private func loadPersistedMetrics() -> PersistedMatchMetricsPayload? {
        guard let fileURL = matchMetricsCacheFileURL else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedMatchMetricsPayload.self, from: data)
    }

    private func persistMetrics(pantrySignature: CollectionSignature, metrics: [UUID: RecipeMatchMetrics]) {
        guard let fileURL = matchMetricsCacheFileURL else { return }
        let payload = PersistedMatchMetricsPayload(pantrySignature: pantrySignature, metrics: metrics)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            PerfLog.event("Failed to persist metrics cache: \(error.localizedDescription)")
        }
    }

    private var matchMetricsCacheFileURL: URL? {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cachesDirectory
            .appendingPathComponent("PantryChef", isDirectory: true)
            .appendingPathComponent("match_metrics_v1.json")
    }
}

private struct CollectionSignature: Hashable, Codable {
    let count: Int
    let first: UUID?
    let last: UUID?
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
    let pantrySignature: CollectionSignature
    let metrics: [UUID: RecipeMatchMetrics]
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

private struct UserFilterCacheKey: Hashable {
    let source: CollectionSignature
    let pantry: CollectionSignature?
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
    let discoverSearchSource: CollectionSignature
    let discoverPoolSource: CollectionSignature
    let pantry: CollectionSignature?
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
    let pantry: CollectionSignature
    let recipes: CollectionSignature
}

private struct FullCoverageKey: Hashable {
    let pantry: CollectionSignature
    let userRecipes: CollectionSignature
    let discoverRecipes: CollectionSignature
    let searchedRecipes: CollectionSignature
}
