import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            PCColors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    ForEach(RootTab.allCases, id: \.self) { tab in
                        rootTabContent(for: tab)
                            .opacity(appState.navigator.selectedRootTab == tab ? 1 : 0)
                            .allowsHitTesting(appState.navigator.selectedRootTab == tab)
                            .accessibilityHidden(appState.navigator.selectedRootTab != tab)
                            .zIndex(appState.navigator.selectedRootTab == tab ? 1 : 0)
                    }
                }
                .frame(maxHeight: .infinity)

                VStack(spacing: 0) {
                    if let miniPlayerData = activeCookMiniPlayerData {
                        PCMiniPlayer(
                            recipeName: miniPlayerData.recipeName,
                            stepProgress: miniPlayerData.stepProgress,
                            progress: miniPlayerData.progress,
                            onTap: { appState.navigator.requestCookQueueSheet() }
                        )
                    }

                    PCTabBar(selectedTab: Binding(
                        get: { appState.navigator.selectedRootTab },
                        set: { appState.navigator.selectedRootTab = $0 }
                    ))
                }
            }
        }
        .accessibilityIdentifier("root.tabHost")
        .fullScreenCover(item: Binding(
            get: { appState.navigator.deepLinkedCookRecipe },
            set: { appState.navigator.deepLinkedCookRecipe = $0 }
        )) { recipe in
            let session = appState.cookingSessionStore.load(recipeId: recipe.id)
            let stepIndex = session?.currentStepIndex ?? 0
            CookModeView(recipe: recipe, resumeAtStep: stepIndex, isResuming: true)
                .environment(appState)
        }
        .appNavigationSheet(isPresented: Binding(
            get: { appState.navigator.showCookQueueSheet },
            set: { appState.navigator.showCookQueueSheet = $0 }
        )) {
            CookQueueView(appState: appState)
        }
        .task {
            appState.scheduleInitialLoadIfNeeded()
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
                appState.navigator.requestTab(.kitchen)
            }, onSwitchToPlan: {
                appState.navigator.requestTab(.plan)
            }, onSwitchToRecipesCanMake: {
                appState.navigator.requestRecipesCanMake()
            }, onSwitchToCook: {
                appState.navigator.requestCookQueueSheet()
            })
        case .recipes:
            RecipeListView(appState: appState, activateCanMakeFilter: Binding(
                get: { appState.navigator.activateRecipesCanMakeFilter },
                set: { appState.navigator.activateRecipesCanMakeFilter = $0 }
            ))
        case .kitchen:
            KitchenView(appState: appState)
        case .plan:
            MealPlanView(appState: appState)
        }
    }
}
