import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .home
    @State private var showAIChat = false
    @State private var isReady = false

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
        ZStack {
            if isReady {
                mainContent
                    .transition(.opacity)
            } else {
                SplashView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: isReady)
        .task {
            // Wait until AppState has finished its initial load
            while appState.isLoading { try? await Task.sleep(for: .milliseconds(50)) }
            // Brief minimum display so the splash isn't a flash
            try? await Task.sleep(for: .milliseconds(300))
            isReady = true
        }
    }

    // MARK: - Main Content
    private var mainContent: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                HomeView(appState: appState)
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

            // Floating AI Button
            if selectedTab == .home || selectedTab == .pantry || selectedTab == .recipes {
                FloatingAIButton(isPresented: $showAIChat)
                    .padding(.trailing, 20)
                    .padding(.bottom, 90)
            }
        }
        .sheet(isPresented: $showAIChat) {
            AIAssistantView(appState: appState)
        }
    }
}

// MARK: - Splash / Launch View
struct SplashView: View {
    @State private var iconScale: CGFloat = 0.6
    @State private var textOpacity: Double = 0

    var body: some View {
        ZStack {
            // Match the launch screen background
            LinearGradient(
                colors: [
                    Color(red: 0.30, green: 0.69, blue: 0.31),
                    Color(red: 0.22, green: 0.56, blue: 0.24)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                    .scaleEffect(iconScale)

                Text("Pantry Chef")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(textOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                iconScale = 1.0
            }
            withAnimation(.easeIn(duration: 0.4).delay(0.2)) {
                textOpacity = 1.0
            }
        }
    }
}
