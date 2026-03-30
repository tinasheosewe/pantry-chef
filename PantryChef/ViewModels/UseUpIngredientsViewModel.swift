import SwiftUI

@Observable
@MainActor
final class UseUpIngredientsViewModel {

    // MARK: - Dependencies

    let appState: AppState

    // MARK: - Navigation (drives navigationDestination)

    var showingSuggestions: Bool = false
    var showingRecipe: Bool = false

    // MARK: - Selection State

    var selectedPantryIDs: Set<UUID> = []
    var searchText: String = ""
    var extraIngredients: [String] = []
    var extraIngredientText: String = ""
    var strictIngredients: Bool = false
    var requireAllIngredients: Bool = true

    // MARK: - Suggestion State

    var suggestions: [RecipeNameSuggestion] = []
    var noResultsMessage: String?
    var isLoadingSuggestions: Bool = false
    @ObservationIgnored private var previousNames: [String] = []

    // MARK: - Generation State

    var selectedSuggestion: RecipeNameSuggestion?
    var generatedRecipe: AppState.NormalizedAIRecipe?
    var isGeneratingRecipe: Bool = false

    // MARK: - Loading Status Messages

    private static let suggestionTips = [
        "Scanning your ingredients…",
        "Thinking of recipes…",
        "Finding the best matches…",
        "Almost there…",
    ]

    private static let generationTips = [
        "Writing out the recipe…",
        "Measuring ingredients…",
        "Drafting cooking steps…",
        "Polishing the details…",
    ]

    var loadingStatusIndex: Int = 0

    var suggestionStatusMessage: String {
        Self.suggestionTips[min(loadingStatusIndex, Self.suggestionTips.count - 1)]
    }

    var generationStatusMessage: String {
        Self.generationTips[min(loadingStatusIndex, Self.generationTips.count - 1)]
    }

    // MARK: - Init

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Computed

    var isLoading: Bool {
        isLoadingSuggestions || isGeneratingRecipe
    }

    var pantryItems: [PantryItem] {
        appState.pantryItems
    }

    var filteredPantryItems: [PantryItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return pantryItems }
        return pantryItems.filter { $0.name.lowercased().contains(query) }
    }

    var groupedPantryItems: [(FoodCategory, [PantryItem])] {
        Dictionary(grouping: filteredPantryItems, by: \.category)
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    var selectedIngredientNames: [String] {
        let pantryNames = pantryItems
            .filter { selectedPantryIDs.contains($0.id) }
            .map(\.name)
        return pantryNames + extraIngredients
    }

    var canGetSuggestions: Bool {
        !selectedIngredientNames.isEmpty
    }

    var selectedCount: Int {
        selectedPantryIDs.count + extraIngredients.count
    }

    // MARK: - Selection Actions

    func togglePantryItem(_ item: PantryItem) {
        if selectedPantryIDs.contains(item.id) {
            selectedPantryIDs.remove(item.id)
        } else {
            selectedPantryIDs.insert(item.id)
        }
    }

    func addExtraIngredient() {
        let trimmed = extraIngredientText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !extraIngredients.contains(trimmed) else { return }
        extraIngredients.append(trimmed)
        extraIngredientText = ""
    }

    func removeExtraIngredient(_ ingredient: String) {
        extraIngredients.removeAll { $0 == ingredient }
    }

    // MARK: - Loading Status Cycling

    func startStatusCycling() async {
        loadingStatusIndex = 0
        while isLoading {
            try? await Task.sleep(for: .seconds(3))
            guard isLoading else { break }
            loadingStatusIndex += 1
        }
    }

    // MARK: - Suggestion Actions

    func fetchSuggestions() async {
        showingSuggestions = true
        isLoadingSuggestions = true
        noResultsMessage = nil
        suggestions = []
        previousNames = []

        async let cycling: () = startStatusCycling()

        let result = await appState.suggestRecipeNames(
            ingredients: selectedIngredientNames,
            strictIngredients: strictIngredients,
            requireAllIngredients: requireAllIngredients,
            excludeNames: []
        )

        suggestions = result.suggestions
        previousNames = result.suggestions.map(\.name)
        noResultsMessage = result.message
        isLoadingSuggestions = false
        _ = await cycling
    }

    func fetchMoreSuggestions() async {
        isLoadingSuggestions = true

        let result = await appState.suggestRecipeNames(
            ingredients: selectedIngredientNames,
            strictIngredients: strictIngredients,
            requireAllIngredients: requireAllIngredients,
            excludeNames: previousNames
        )

        suggestions.append(contentsOf: result.suggestions)
        previousNames.append(contentsOf: result.suggestions.map(\.name))
        if let message = result.message, suggestions.isEmpty {
            noResultsMessage = message
        }
        isLoadingSuggestions = false
    }

    // MARK: - Generation Actions

    func selectAndGenerate(_ suggestion: RecipeNameSuggestion) async {
        // If we already generated a recipe for this suggestion, just re-show it
        if selectedSuggestion?.name == suggestion.name, generatedRecipe != nil {
            showingRecipe = true
            return
        }

        selectedSuggestion = suggestion
        generatedRecipe = nil
        showingRecipe = true
        isGeneratingRecipe = true

        async let cycling: () = startStatusCycling()

        let recipe = await appState.generateRecipeFromSuggestion(
            suggestion,
            ingredients: selectedIngredientNames,
            strictIngredients: strictIngredients,
            requireAllIngredients: requireAllIngredients
        )

        generatedRecipe = recipe
        isGeneratingRecipe = false
        _ = await cycling
    }

    func retryGeneration() async {
        guard let suggestion = selectedSuggestion else { return }
        generatedRecipe = nil
        isGeneratingRecipe = true

        async let cycling: () = startStatusCycling()

        let recipe = await appState.generateRecipeFromSuggestion(
            suggestion,
            ingredients: selectedIngredientNames,
            strictIngredients: strictIngredients,
            requireAllIngredients: requireAllIngredients
        )

        generatedRecipe = recipe
        isGeneratingRecipe = false
        _ = await cycling
    }

    func saveRecipe() async {
        guard let recipe = generatedRecipe else { return }
        await appState.addRecipe(recipe.rawValue)
    }
}
