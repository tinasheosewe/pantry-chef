import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: RootTab = .home

    /// Recipe resolved from a deep-link notification tap.
    @State private var deepLinkRecipe: Recipe?

    /// When true, the Recipes tab should activate "Can Make" filter on appear.
    @State private var activateCanMakeFilter = false

    var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()

            ZStack {
                ForEach(RootTab.allCases, id: \.self) { tab in
                    rootTabContent(for: tab)
                        .opacity(selectedTab == tab ? 1 : 0)
                        .allowsHitTesting(selectedTab == tab)
                        .accessibilityHidden(selectedTab != tab)
                        .zIndex(selectedTab == tab ? 1 : 0)
                }
            }
        }
        .accessibilityIdentifier("root.tabHost")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            rootTabBar
        }
        .fullScreenCover(item: $deepLinkRecipe) { recipe in
            let session = CookingSession.load(recipeId: recipe.id)
            let stepIndex = session?.currentStepIndex ?? 0
            CookModeView(recipe: recipe, resumeAtStep: stepIndex, isResuming: true)
                .environment(appState)
        }
        .task {
            appState.scheduleInitialLoadIfNeeded()
        }
        .onChange(of: appState.requestedRootTab) { _, newTab in
            guard let newTab else { return }
            selectedTab = newTab
            appState.requestedRootTab = nil
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

    @ViewBuilder
    private func rootTabContent(for tab: RootTab) -> some View {
        switch tab {
        case .home:
            HomeView(appState: appState, onSwitchToShopping: {
                selectedTab = .shop
            }, onSwitchToPlan: {
                selectedTab = .plan
            }, onSwitchToRecipesCanMake: {
                activateCanMakeFilter = true
                selectedTab = .recipes
            }, onSwitchToCook: {
                selectedTab = .cook
            })
        case .pantry:
            PantryView(appState: appState)
        case .recipes:
            RecipeListView(appState: appState, activateCanMakeFilter: $activateCanMakeFilter)
        case .cook:
            CookHubView()
                .environment(appState)
        case .plan:
            MealPlanView(appState: appState)
        case .shop:
            ShoppingListView(appState: appState)
        }
    }

    private var rootTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(RootTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .font(.subheadline)
                                Text(tab.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(selectedTab == tab ? Color.white : AppColors.darkText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(selectedTab == tab ? AppColors.primaryGreen : AppColors.cardBackground)
                            .clipShape(Capsule())
                            .shadow(color: Color.black.opacity(selectedTab == tab ? 0.08 : 0.03), radius: 8, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                        .accessibilityIdentifier("root.tabButton.\(tab.rawValue.lowercased())")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
            .onAppear {
                proxy.scrollTo(selectedTab, anchor: .center)
            }
            .onChange(of: selectedTab) { _, newTab in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newTab, anchor: .center)
                }
            }
        }
    }
}
