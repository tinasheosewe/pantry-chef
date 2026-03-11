import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .home

    /// Recipe resolved from a deep-link notification tap.
    @State private var deepLinkRecipe: Recipe?

    /// When true, the Recipes tab should activate "Can Make" filter on appear.
    @State private var activateCanMakeFilter = false

    enum Tab: String, CaseIterable {
        case home = "Home"
        case pantry = "Pantry"
        case recipes = "Recipes"
        case plan = "Plan"
        case shop = "Shop"

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .pantry: return "refrigerator.fill"
            case .recipes: return "book.fill"
            case .plan: return "calendar"
            case .shop: return "cart.fill"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                HomeView(appState: appState, onSwitchToShopping: {
                    selectedTab = .shop
                }, onSwitchToPlan: {
                    selectedTab = .plan
                }, onSwitchToRecipesCanMake: {
                    activateCanMakeFilter = true
                    selectedTab = .recipes
                })
                    .tabItem {
                        Label(Tab.home.rawValue, systemImage: Tab.home.icon)
                    }
                    .tag(Tab.home)

                PantryView(appState: appState)
                    .tabItem {
                        Label(Tab.pantry.rawValue, systemImage: Tab.pantry.icon)
                    }
                    .tag(Tab.pantry)

                RecipeListView(appState: appState, activateCanMakeFilter: $activateCanMakeFilter)
                    .tabItem {
                        Label(Tab.recipes.rawValue, systemImage: Tab.recipes.icon)
                    }
                    .tag(Tab.recipes)

                MealPlanView(appState: appState)
                    .tabItem {
                        Label(Tab.plan.rawValue, systemImage: Tab.plan.icon)
                    }
                    .tag(Tab.plan)

                ShoppingListView(appState: appState)
                    .tabItem {
                        Label(Tab.shop.rawValue, systemImage: Tab.shop.icon)
                    }
                    .tag(Tab.shop)
            }
            .tint(AppColors.primary)
        }
        .fullScreenCover(item: $deepLinkRecipe) { recipe in
            let session = CookingSession.load(recipeId: recipe.id)
            let stepIndex = session?.currentStepIndex ?? 0
            CookModeView(recipe: recipe, resumeAtStep: stepIndex, isResuming: true)
                .environment(appState)
        }
        .onChange(of: appState.deepLinkCookModeRecipeId) { _, newId in
            guard let recipeId = newId else { return }
            // Clear immediately so it doesn't re-trigger
            appState.deepLinkCookModeRecipeId = nil

            Task { @MainActor in
                for _ in 0..<20 {
                    if let recipe = appState.recipeByIdString(recipeId) {
                        deepLinkRecipe = recipe
                        return
                    }
                    try await Task.sleep(for: .milliseconds(200))
                }
                AppLog.warn("[ContentView] ⚠️ Deep-link recipe \(recipeId.prefix(8))… not found in known recipes")
            }
        }
    }
}
