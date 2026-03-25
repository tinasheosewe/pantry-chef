import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: RootTab = .today

    /// Recipe resolved from a deep-link notification tap.
    @State private var deepLinkRecipe: Recipe?

    /// When true, the Recipes tab should activate "Can Make" filter on appear.
    @State private var activateCanMakeFilter = false

    /// Controls expansion of cook queue management view.
    @State private var showCookQueueSheet = false

    var body: some View {
        ZStack {
            PCColors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    ForEach(RootTab.allCases, id: \.self) { tab in
                        rootTabContent(for: tab)
                            .opacity(selectedTab == tab ? 1 : 0)
                            .allowsHitTesting(selectedTab == tab)
                            .accessibilityHidden(selectedTab != tab)
                            .zIndex(selectedTab == tab ? 1 : 0)
                    }
                }
                .frame(maxHeight: .infinity)

                VStack(spacing: 0) {
                    if let miniPlayerData = activeCookMiniPlayerData {
                        PCMiniPlayer(
                            recipeName: miniPlayerData.recipeName,
                            stepProgress: miniPlayerData.stepProgress,
                            progress: miniPlayerData.progress,
                            onTap: { showCookQueueSheet = true }
                        )
                    }

                    PCTabBar(selectedTab: $selectedTab)
                }
            }
        }
        .accessibilityIdentifier("root.tabHost")
        .fullScreenCover(item: $deepLinkRecipe) { recipe in
            let session = CookingSession.load(recipeId: recipe.id)
            let stepIndex = session?.currentStepIndex ?? 0
            CookModeView(recipe: recipe, resumeAtStep: stepIndex, isResuming: true)
                .environment(appState)
        }
        .pcSheet(isPresented: $showCookQueueSheet) {
            CookQueueView(appState: appState)
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
            appState.deepLinkCookModeRecipeId = nil

            Task { @MainActor in
                for _ in 0..<20 {
                    if let recipe = appState.recipeByIdString(recipeId) {
                        deepLinkRecipe = recipe
                        return
                    }
                    try await Task.sleep(for: .milliseconds(200))
                }
                AppLog.warn("[ContentView] Deep-link recipe \(recipeId.prefix(8))… not found in known recipes")
            }
        }
    }

    // MARK: - Mini Player Data

    private var activeCookMiniPlayerData: (recipeName: String, stepProgress: String, progress: Double)? {
        if let session = appState.activeCooks.activeSessions.first {
            let progress = session.totalSteps > 0
                ? Double(session.currentStepIndex) / Double(session.totalSteps)
                : 0
            return (
                recipeName: session.recipeName,
                stepProgress: "Step \(session.currentStepIndex + 1) of \(session.totalSteps)",
                progress: progress
            )
        }

        if let queue = appState.cookQueue, let stage = queue.currentStage {
            return (
                recipeName: stage.title,
                stepProgress: stage.subtitle,
                progress: 0.5
            )
        }

        return nil
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func rootTabContent(for tab: RootTab) -> some View {
        switch tab {
        case .today:
            HomeView(appState: appState, onSwitchToShopping: {
                selectedTab = .kitchen
            }, onSwitchToPlan: {
                selectedTab = .plan
            }, onSwitchToRecipesCanMake: {
                activateCanMakeFilter = true
                selectedTab = .recipes
            }, onSwitchToCook: {
                showCookQueueSheet = true
            })
        case .recipes:
            RecipeListView(appState: appState, activateCanMakeFilter: $activateCanMakeFilter)
        case .kitchen:
            KitchenView(appState: appState)
        case .plan:
            MealPlanView(appState: appState)
        }
    }
}
