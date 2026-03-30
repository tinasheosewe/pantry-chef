import SwiftUI

/// Centralizes app-wide navigation state: root tab switching and deep links.
@Observable
@MainActor
final class NavigationCoordinator {
    var selectedRootTab: RootTab = .today

    /// Set by child screens to request a root tab switch.
    var requestedRootTab: RootTab?

    var showCookQueueSheet = false
    var showUseUpIngredientsSheet = false
    var activateRecipesCanMakeFilter = false

    /// Resolved deep-link target shown by ContentView.
    var deepLinkedCookRecipe: Recipe?

    /// Multi-cook session to resume via deep-link.
    var deepLinkedMultiCookSession: MultiCookSession?

    /// Set by notification tap to deep-link into cook mode for a specific recipe.
    var deepLinkCookModeRecipeId: String?

    func requestTab(_ tab: RootTab) {
        selectedRootTab = tab
        requestedRootTab = tab
    }

    func requestCookQueueSheet() {
        showCookQueueSheet = true
    }

    func requestUseUpIngredientsSheet() {
        showUseUpIngredientsSheet = true
    }

    func requestRecipesCanMake() {
        activateRecipesCanMakeFilter = true
        requestTab(.recipes)
    }

    func deepLinkToCookMode(recipeId: String) {
        deepLinkCookModeRecipeId = recipeId
    }

    func resolveCookModeDeepLink(
        recipeId: String,
        recipeLookup: @escaping @MainActor (String) -> Recipe?,
        maxRetries: Int,
        retryDelayMs: Int
    ) async {
        deepLinkCookModeRecipeId = recipeId

        for _ in 0..<maxRetries {
            guard !Task.isCancelled else { return }
            if let recipe = recipeLookup(recipeId) {
                deepLinkedCookRecipe = recipe
                deepLinkCookModeRecipeId = nil
                return
            }

            try? await Task.sleep(for: .milliseconds(retryDelayMs))
        }

        AppLog.warn("[NavigationCoordinator] Deep-link recipe \(recipeId.prefix(8))… not found in known recipes")
        deepLinkCookModeRecipeId = nil
    }
}
