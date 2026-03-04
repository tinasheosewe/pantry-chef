import SwiftUI

@MainActor
final class RecipeViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedDifficulty: DifficultyLevel?
    @Published var selectedMealType: MealType?
    @Published var selectedDietaryTags: Set<DietaryTag> = []
    @Published var showAddRecipe = false
    @Published var showImportURL = false
    @Published var showPhotoImport = false
    @Published var sortOrder: SortOrder = .recent
    @Published var showOnlyFavorites = false
    @Published var isLoading = false
    @Published var importedRecipe: Recipe?

    // AI Results
    @Published var whatCanIMakeResults: [PantryMatchResult] = []
    @Published var showWhatCanIMake = false

    enum SortOrder: String, CaseIterable {
        case recent = "Recent"
        case name = "Name"
        case difficulty = "Difficulty"
        case time = "Time"
        case mostCooked = "Most Cooked"
    }

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var filteredRecipes: [Recipe] {
        var recipes = appState.recipes

        if !searchText.isEmpty {
            recipes = recipes.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        if showOnlyFavorites {
            recipes = recipes.filter { $0.isFavorite }
        }

        if let difficulty = selectedDifficulty {
            recipes = recipes.filter { $0.difficulty == difficulty }
        }

        if let mealType = selectedMealType {
            recipes = recipes.filter { $0.mealType == mealType }
        }

        if !selectedDietaryTags.isEmpty {
            recipes = recipes.filter { recipe in
                selectedDietaryTags.isSubset(of: Set(recipe.dietaryTags))
            }
        }

        switch sortOrder {
        case .recent:
            recipes.sort { $0.dateAdded > $1.dateAdded }
        case .name:
            recipes.sort { $0.title < $1.title }
        case .difficulty:
            recipes.sort { $0.difficulty.rawValue < $1.difficulty.rawValue }
        case .time:
            recipes.sort { ($0.totalTimeMinutes ?? 999) < ($1.totalTimeMinutes ?? 999) }
        case .mostCooked:
            recipes.sort { $0.timesCooked > $1.timesCooked }
        }

        return recipes
    }

    func addRecipe(_ recipe: Recipe) async {
        await appState.addRecipe(recipe)
    }

    func deleteRecipe(_ recipe: Recipe) async {
        await appState.deleteRecipe(recipe)
    }

    func toggleFavorite(_ recipe: Recipe) async {
        var updated = recipe
        updated.isFavorite.toggle()
        await appState.addRecipe(updated) // Acts as upsert
    }

    func whatCanIMake() {
        whatCanIMakeResults = appState.recipes
            .map { $0.pantryMatch(pantry: appState.pantryItems) }
            .sorted { $0.matchPercentage > $1.matchPercentage }
        showWhatCanIMake = true
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
        selectedDietaryTags = []
        showOnlyFavorites = false
        searchText = ""
    }

    var hasActiveFilters: Bool {
        selectedDifficulty != nil || selectedMealType != nil || !selectedDietaryTags.isEmpty || showOnlyFavorites
    }
}
