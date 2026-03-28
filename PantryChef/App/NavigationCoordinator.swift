import SwiftUI

/// Centralizes app-wide navigation state: root tab switching and deep links.
@Observable
@MainActor
final class NavigationCoordinator {
    /// Set by child screens to request a root tab switch.
    var requestedRootTab: RootTab?

    /// Set by notification tap to deep-link into cook mode for a specific recipe.
    var deepLinkCookModeRecipeId: String?

    func requestTab(_ tab: RootTab) {
        requestedRootTab = tab
    }

    func deepLinkToCookMode(recipeId: String) {
        deepLinkCookModeRecipeId = recipeId
    }
}
