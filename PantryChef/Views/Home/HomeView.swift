import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var resumeRecipe: Recipe?
    @State private var selectedMealEntry: MealPlanEntry?
    @State private var selectedPreparedDish: PreparedDish?
    @State private var shoppingConfirmation: ShoppingListConfirmationRequest?
    @State private var showCookQueueManager = false

    var onSwitchToShopping: (() -> Void)?
    var onSwitchToPlan: (() -> Void)?
    var onSwitchToRecipesCanMake: (() -> Void)?

    init(appState: AppState, onSwitchToShopping: (() -> Void)? = nil, onSwitchToPlan: (() -> Void)? = nil, onSwitchToRecipesCanMake: (() -> Void)? = nil) {
        _viewModel = State(initialValue: HomeViewModel(appState: appState))
        self.onSwitchToShopping = onSwitchToShopping
        self.onSwitchToPlan = onSwitchToPlan
        self.onSwitchToRecipesCanMake = onSwitchToRecipesCanMake
    }

    var body: some View {
        AppScreen("home.screen") {
            AppScrollView {
                VStack(spacing: 20) {
                    greetingHeader

                    // Active cooking sessions banner
                    if viewModel.appState.activeCooks.hasActiveSessions {
                        activeCooksBanner
                    }

                    if viewModel.appState.cookQueue?.stages.isEmpty == false {
                        cookQueueBanner
                    }

                    todaysMealPlanCard

                    if !viewModel.expiringItems.isEmpty {
                        expiringSoonCard
                    }

                    if !viewModel.expiringPreparedDishes.isEmpty {
                        expiringPreparedDishesCard
                    }

                    quickActionsRow

                    if let recipe = viewModel.suggestedRecipe {
                        recipeSuggestionCard(recipe)
                    }

                    if let nutrition = viewModel.weeklyNutrition {
                        weeklyNutritionCard(nutrition)
                    }

                    if Calendar.current.isDateInWeekend(Date()) {
                        batchPrepCard
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await viewModel.appState.loadAllData()
                viewModel.refresh()
            }
            .onAppear {
                viewModel.refresh()
                viewModel.appState.activeCooks.refresh()
            }
            .onChange(of: viewModel.appState.homeDashboardRefreshState) { _, _ in
                viewModel.refresh()
            }
            .shoppingListConfirmation($shoppingConfirmation) { itemsToAdd in
                Task {
                    await viewModel.appState.addShoppingItems(itemsToAdd)
                    onSwitchToShopping?()
                }
            }
            .appNavigationSheet(item: $selectedMealEntry) { entry in
                if let recipe = entry.recipe {
                    RecipeDetailView(recipe: recipe)
                        .environment(viewModel.appState)
                } else if let preparedDish = entry.preparedDish {
                    PreparedDishDetailView(dish: preparedDish)
                        .environment(viewModel.appState)
                }
            }
            .appNavigationSheet(item: $selectedPreparedDish) { dish in
                PreparedDishDetailView(dish: dish)
                    .environment(viewModel.appState)
            }
            .appNavigationSheet(isPresented: $showCookQueueManager) {
                CookQueueView(appState: viewModel.appState)
            }
            .fullScreenCover(item: $resumeRecipe) { recipe in
                let session = CookingSession.load(recipeId: recipe.id)
                let stepIndex = session?.currentStepIndex ?? 0
                let queueContext = session.flatMap { viewModel.appState.cookQueueContext(for: $0) }
                CookModeView(
                    recipe: recipe,
                    resumeAtStep: stepIndex,
                    isResuming: true,
                    queueID: queueContext?.queueID,
                    queueStageID: queueContext?.stageID
                )
                    .environment(viewModel.appState)
            }
        }
    }

    // MARK: - Greeting Header
    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.greetingMessage)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(AppColors.darkText)

            Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
                .foregroundStyle(AppColors.subtleText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Today's Meal Plan Card
    private var todaysMealPlanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Today's Plan", actionTitle: "View All") {
                onSwitchToPlan?()
            }

            if viewModel.todaysMeals.isEmpty {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundStyle(AppColors.mediumGray)
                    VStack(alignment: .leading) {
                        Text("No meals planned")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Tap to plan your day")
                            .font(.caption)
                            .foregroundStyle(AppColors.subtleText)
                    }
                    Spacer()
                }
                .padding()
                .background(AppColors.lightGray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(viewModel.todaysMeals) { entry in
                    todayMealRow(entry)
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Expiring Soon Card
    private var expiringSoonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Expiring Soon",
                subtitle: "\(viewModel.expiringItems.count) items need attention"
            )

            ForEach(viewModel.expiringItems.prefix(5)) { item in
                HStack(spacing: 12) {
                    CategoryIcon(category: item.category, size: 28)
                    Text(item.name)
                        .font(.subheadline)
                    Spacer()
                    ExpiryBadge(status: item.expiryStatus, daysLeft: item.daysUntilExpiry)
                }
            }

            if viewModel.expiringItems.count > 5 {
                Text("+ \(viewModel.expiringItems.count - 5) more")
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
            }
        }
        .padding()
        .cardStyle()
    }

    private var expiringPreparedDishesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Use Prepared Dishes Soon",
                subtitle: "\(viewModel.expiringPreparedDishes.count) dishes are close to their use-by date"
            )

            ForEach(viewModel.expiringPreparedDishes.prefix(3)) { dish in
                Button {
                    selectedPreparedDish = dish
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "takeoutbag.and.cup.and.straw")
                            .font(.title3)
                            .foregroundStyle(AppColors.warmOrange)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(dish.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(AppColors.darkText)

                            Text("\(dish.servingsDisplay) • \(dish.mealTypesSummary)")
                                .font(.caption)
                                .foregroundStyle(AppColors.subtleText)
                        }

                        Spacer()

                        ExpiryBadge(status: dish.expiryStatus, daysLeft: dish.daysUntilUseBy)
                    }
                }
                .buttonStyle(.plain)
            }

            if viewModel.expiringPreparedDishes.count > 3 {
                Text("+ \(viewModel.expiringPreparedDishes.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Quick Actions Row
    private var quickActionsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(AppColors.darkText)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                QuickActionButton(icon: "fork.knife", title: "What can\nI make?", color: AppColors.primaryGreen) {
                    onSwitchToRecipesCanMake?()
                }
                .accessibilityIdentifier("home.quickAction.canMake")
                QuickActionButton(icon: "cart.fill", title: "What to\nbuy?", color: AppColors.warmOrange) {
                    prepareShoppingConfirmation()
                }
                .accessibilityIdentifier("home.quickAction.shopping")
                QuickActionButton(icon: "calendar", title: "Plan\nmeals", color: AppColors.accentBlue) {
                    onSwitchToPlan?()
                }
                .accessibilityIdentifier("home.quickAction.plan")
            }
        }
    }

    private func prepareShoppingConfirmation() {
        shoppingConfirmation = ShoppingListConfirmationRequest(
            items: viewModel.appState.previewShoppingListFromMealPlan(),
            context: .mealPlan
        )
    }

    private func todayMealRow(_ entry: MealPlanEntry) -> some View {
        let row = HStack(spacing: 12) {
            Image(systemName: entry.mealType.icon)
                .font(.title3)
                .foregroundStyle(AppColors.primaryGreen)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.mealType.rawValue)
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
                Text(entry.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.darkText)
                if let planningSubtitle = entry.planningSubtitle {
                    Text(planningSubtitle)
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }
            }

            Spacer()

            if entry.recipe != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.mediumGray)
            } else if entry.preparedDish != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.mediumGray)
            }
        }
        .padding(.vertical, 4)

        if entry.recipe != nil || entry.preparedDish != nil {
            return AnyView(
                Button {
                    selectedMealEntry = entry
                } label: {
                    row
                }
                .buttonStyle(.plain)
            )
        }

        return AnyView(row)
    }

    // MARK: - Recipe Suggestion Card
    private func recipeSuggestionCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Suggested for You", subtitle: "Based on your pantry")

            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.primaryGreen.opacity(0.15))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "fork.knife")
                                .font(.title2)
                                .foregroundStyle(AppColors.primaryGreen)
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(recipe.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.darkText)

                        if let desc = recipe.description {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(AppColors.subtleText)
                                .lineLimit(2)
                        }

                        HStack(spacing: 12) {
                            DifficultyBadge(difficulty: recipe.difficulty)
                            Label(recipe.totalTimeDisplay, systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(AppColors.subtleText)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(AppColors.mediumGray)
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Weekly Nutrition Card
    private func weeklyNutritionCard(_ nutrition: WeeklyNutritionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "This Week",
                subtitle: "\(nutrition.mealsPlanned) meals planned"
            )

            HStack(spacing: 20) {
                NutritionCircle(label: "Avg Cal", value: nutrition.avgCaloriesPerMeal, unit: "kcal", color: AppColors.warmOrange)
                NutritionCircle(label: "Protein", value: nutrition.avgProteinPerMeal, unit: "g", color: AppColors.softRed)
                NutritionCircle(label: "Carbs", value: nutrition.avgCarbsPerMeal, unit: "g", color: AppColors.primaryGreen)
                NutritionCircle(label: "Fat", value: nutrition.avgFatPerMeal, unit: "g", color: AppColors.accentBlue)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Batch Prep Card
    private var batchPrepCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(AppColors.primaryGreen)
                Text("Batch Prep Tip")
                    .font(.headline)
            }
            Text("It's the weekend! Consider prepping meals for the week. Check your meal plan and cook in batches to save time.")
                .font(.subheadline)
                .foregroundStyle(AppColors.subtleText)
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Active Cooks Banner
    private var activeCooksBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(AppColors.warmOrange)
                Text("Active Cooks")
                    .font(.headline)
                    .foregroundStyle(AppColors.darkText)
                Spacer()
                Text("\(viewModel.appState.activeCooks.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.warmOrange)
                    .clipShape(Capsule())
            }

            ForEach(viewModel.appState.activeCooks.activeSessions) { session in
                Button {
                    if let recipe = viewModel.appState.allRecipes.first(where: { $0.id == session.recipeId }) {
                        resumeRecipe = recipe
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppColors.primaryGreen.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "frying.pan.fill")
                                .foregroundStyle(AppColors.primaryGreen)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.recipeName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColors.darkText)
                            Text("Step \(session.currentStepIndex + 1) of \(session.totalSteps)")
                                .font(.caption)
                                .foregroundStyle(AppColors.subtleText)
                        }

                        Spacer()

                        // Elapsed time since backgrounded
                        let elapsed = Int(Date().timeIntervalSince(session.backgroundedAt))
                        let minutes = elapsed / 60
                        Text(minutes < 1 ? "Just now" : "\(minutes)m ago")
                            .font(.caption2)
                            .foregroundStyle(AppColors.subtleText)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(AppColors.mediumGray)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.warmOrange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(AppColors.warmOrange.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var cookQueueBanner: some View {
        let queue = viewModel.appState.cookQueue
        let currentStage = queue?.currentStage
        let remainingCount = queue?.pendingStageCount ?? 0

        return Button {
            showCookQueueManager = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "list.number")
                        .foregroundStyle(AppColors.accentBlue)
                    Text("Cook Queue")
                        .font(.headline)
                        .foregroundStyle(AppColors.darkText)
                    Spacer()
                    Text("\(remainingCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.accentBlue)
                        .clipShape(Capsule())
                }

                if let currentStage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentStage.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.darkText)
                        Text(currentStage.subtitle)
                            .font(.caption)
                            .foregroundStyle(AppColors.subtleText)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.accentBlue.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(AppColors.accentBlue.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Action Button
struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.darkText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColors.lightGray)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Nutrition Circle
struct NutritionCircle: View {
    let label: String
    let value: Int
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 10))
                .foregroundStyle(AppColors.subtleText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColors.subtleText)
        }
    }
}
