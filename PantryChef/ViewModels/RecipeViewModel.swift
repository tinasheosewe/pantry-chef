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
    private var debounceTask: Task<Void, Never>?
    private var currentSearchOffset = 0
    private var totalSearchResults = 0
    /// True until the first API search completes (enables scroll-to-load-more even before any search)
    private(set) var neverSearchedAPI = true
    var hasMorePages: Bool { neverSearchedAPI || currentSearchOffset < totalSearchResults }

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
    }

    // MARK: - Filtered User Recipes

    var filteredUserRecipes: [Recipe] {
        var recipes = appState.recipes

        recipes = applyCommonFilters(recipes)

        if showOnlyFavorites {
            recipes = recipes.filter { $0.isFavorite }
        }

        if showCanMakeOnly {
            recipes = applyMakeabilityFilter(recipes)
        }

        return applySortOrder(recipes)
    }

    // MARK: - Filtered Discover Recipes (bundled + cached + API search results)

    var filteredDiscoverRecipes: [Recipe] {
        // When we have API search results, use them as the authoritative
        // ordered list so pagination appends stay in order and scroll
        // position is preserved. Only fall back to the seed/cached pool
        // when the user hasn't searched yet.
        var recipes: [Recipe]
        if !discoverSearchResults.isEmpty {
            // Start with API results in their original (server-ordered) position
            recipes = discoverSearchResults
            // Append any seed/cached recipes that aren't already in the API set
            let apiTitles = Set(recipes.map { $0.title.lowercased() })
            let extras = appState.discoverRecipes.filter { !apiTitles.contains($0.title.lowercased()) }
            recipes.append(contentsOf: extras)
        } else {
            recipes = appState.discoverRecipes
        }

        recipes = applyCommonFilters(recipes)

        if showCanMakeOnly {
            recipes = applyMakeabilityFilter(recipes)
        }

        // Only apply local sort when browsing seed recipes (no API results).
        // When API results are present the server already sorted them
        // (by relevance or popularity) and re-sorting would break
        // pagination order and scroll position.
        if discoverSearchResults.isEmpty {
            recipes = applySortOrder(recipes)
        }

        return recipes
    }

    // MARK: - Legacy compatibility

    var filteredRecipes: [Recipe] {
        filteredUserRecipes
    }

    // MARK: - Common Filter Logic

    private func applyCommonFilters(_ input: [Recipe]) -> [Recipe] {
        var recipes = input

        if !searchText.isEmpty {
            let query = searchText
            recipes = recipes.filter { recipe in
                recipe.title.localizedCaseInsensitiveContains(query) ||
                (recipe.description?.localizedCaseInsensitiveContains(query) ?? false) ||
                recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) } ||
                (recipe.cuisine?.rawValue.localizedCaseInsensitiveContains(query) ?? false) ||
                (recipe.mealType?.rawValue.localizedCaseInsensitiveContains(query) ?? false)
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

    private func applyMakeabilityFilter(_ recipes: [Recipe]) -> [Recipe] {
        let pantry = appState.pantryItems
        return recipes.filter { recipe in
            let match = recipe.pantryMatch(pantry: pantry)
            if match.canMake { return true }
            if showWithSubstitutions && match.canMakeWithSubstitutions { return true }
            return false
        }
    }

    private func applySortOrder(_ recipes: [Recipe]) -> [Recipe] {
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
            let pantry = appState.pantryItems
            // Pre-compute match percentages once, then sort by the cached values
            let percentages = Dictionary(uniqueKeysWithValues:
                sorted.map { ($0.id, $0.pantryMatch(pantry: pantry).effectiveMatchPercentage) }
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
        debounceTask?.cancel()
        guard isDiscoverTab else { return }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            // Clear API results for very short queries
            if query.isEmpty { discoverSearchResults = [] }
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms
            guard !Task.isCancelled else { return }
            await searchDiscoverRecipes(query: query)
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

            for recipe in recipes {
                appState.recipeRepository.cacheRecipe(recipe)
            }
            appState.refreshDiscoverRecipes()
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

            for recipe in recipes {
                appState.recipeRepository.cacheRecipe(recipe)
            }
            appState.refreshDiscoverRecipes()
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
}
