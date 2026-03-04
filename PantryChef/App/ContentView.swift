import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .home
    @State private var showAIChat = false

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
                HomeView()
                    .tabItem {
                        Label(Tab.home.rawValue, systemImage: Tab.home.icon)
                    }
                    .tag(Tab.home)

                PantryView()
                    .tabItem {
                        Label(Tab.pantry.rawValue, systemImage: Tab.pantry.icon)
                    }
                    .tag(Tab.pantry)

                RecipeListView()
                    .tabItem {
                        Label(Tab.recipes.rawValue, systemImage: Tab.recipes.icon)
                    }
                    .tag(Tab.recipes)

                MealPlanView()
                    .tabItem {
                        Label(Tab.plan.rawValue, systemImage: Tab.plan.icon)
                    }
                    .tag(Tab.plan)

                ShoppingListView()
                    .tabItem {
                        Label(Tab.shop.rawValue, systemImage: Tab.shop.icon)
                    }
                    .tag(Tab.shop)
            }
            .tint(AppColors.primary)

            // Floating AI Button
            if selectedTab == .home || selectedTab == .pantry || selectedTab == .recipes {
                FloatingAIButton(isPresented: $showAIChat)
                    .padding(.trailing, 20)
                    .padding(.bottom, 90)
            }
        }
        .sheet(isPresented: $showAIChat) {
            AIAssistantView()
        }
    }
}
