import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .home

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

                RecipeListView(appState: appState)
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
    }
}
