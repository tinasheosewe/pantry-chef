import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var resumeRecipe: Recipe?
    @State private var selectedMealEntry: MealPlanEntry?
    @State private var selectedPreparedDish: PreparedDish?
    @State private var shoppingConfirmation: ShoppingListConfirmationRequest?

    var onSwitchToShopping: (() -> Void)?
    var onSwitchToPlan: (() -> Void)?
    var onSwitchToRecipesCanMake: (() -> Void)?
    var onSwitchToCook: (() -> Void)?

    init(appState: AppState, onSwitchToShopping: (() -> Void)? = nil, onSwitchToPlan: (() -> Void)? = nil, onSwitchToRecipesCanMake: (() -> Void)? = nil, onSwitchToCook: (() -> Void)? = nil) {
        _viewModel = State(initialValue: HomeViewModel(appState: appState))
        self.onSwitchToShopping = onSwitchToShopping
        self.onSwitchToPlan = onSwitchToPlan
        self.onSwitchToRecipesCanMake = onSwitchToRecipesCanMake
        self.onSwitchToCook = onSwitchToCook
    }

    var body: some View {
        AppScreen("home.screen") {
            PCScrollView {
                VStack(spacing: PCTokens.sectionSpacing) {
                    greetingHeader

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
        VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
            Text(viewModel.greetingMessage)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(PCColors.textPrimary)

            Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(PCFont.body)
                .foregroundStyle(PCColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, PCTokens.spacingSM)
    }

    // MARK: - Today's Meal Plan Card
    private var todaysMealPlanCard: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
            PCSectionHeader(title: "Today's Plan", actionTitle: "View All") {
                onSwitchToPlan?()
            }

            if viewModel.todaysMeals.isEmpty {
                Button {
                    onSwitchToPlan?()
                } label: {
                    HStack(spacing: PCTokens.spacingMD) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.title2)
                            .foregroundStyle(PCColors.separator)
                        VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
                            Text("No meals planned")
                                .font(PCFont.headline)
                                .foregroundStyle(PCColors.textPrimary)
                            Text("Tap to plan your day")
                                .font(PCFont.caption)
                                .foregroundStyle(PCColors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(PCTokens.cardPadding)
                    .background(PCColors.fillTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadius))
                }
                .buttonStyle(.plain)
            } else {
                ForEach(viewModel.todaysMeals) { entry in
                    todayMealRow(entry)
                }
            }
        }
        .padding(PCTokens.cardPadding)
        .pcCard()
    }

    // MARK: - Expiring Soon Card
    private var expiringSoonCard: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
            PCSectionHeader(
                title: "Expiring Soon",
                subtitle: "\(viewModel.expiringItems.count) items need attention"
            )

            ForEach(viewModel.expiringItems.prefix(5)) { item in
                HStack(spacing: PCTokens.spacingMD) {
                    PCCategoryIcon(category: item.category)
                    Text(item.name)
                        .font(PCFont.body)
                        .foregroundStyle(PCColors.textPrimary)
                    Spacer()
                    PCExpiryBadge(status: item.expiryStatus, daysLeft: item.daysUntilExpiry)
                }
            }

            if viewModel.expiringItems.count > 5 {
                Text("+ \(viewModel.expiringItems.count - 5) more")
                    .font(PCFont.caption)
                    .foregroundStyle(PCColors.textSecondary)
            }
        }
        .padding(PCTokens.cardPadding)
        .pcCard()
    }

    private var expiringPreparedDishesCard: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
            PCSectionHeader(
                title: "Use Prepared Dishes Soon",
                subtitle: "\(viewModel.expiringPreparedDishes.count) dishes are close to their use-by date"
            )

            ForEach(viewModel.expiringPreparedDishes.prefix(3)) { dish in
                Button {
                    selectedPreparedDish = dish
                } label: {
                    HStack(spacing: PCTokens.spacingMD) {
                        Image(systemName: "takeoutbag.and.cup.and.straw")
                            .font(.title3)
                            .foregroundStyle(PCColors.expiring)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(dish.name)
                                .font(PCFont.headline)
                                .foregroundStyle(PCColors.textPrimary)

                            Text("\(dish.servingsDisplay) • \(dish.mealTypesSummary)")
                                .font(PCFont.caption)
                                .foregroundStyle(PCColors.textSecondary)
                        }

                        Spacer()

                        PCExpiryBadge(status: dish.expiryStatus, daysLeft: dish.daysUntilUseBy)
                    }
                }
                .buttonStyle(.plain)
            }

            if viewModel.expiringPreparedDishes.count > 3 {
                Text("+ \(viewModel.expiringPreparedDishes.count - 3) more")
                    .font(PCFont.caption)
                    .foregroundStyle(PCColors.textSecondary)
            }
        }
        .padding(PCTokens.cardPadding)
        .pcCard()
    }

    // MARK: - Quick Actions Row
    private var quickActionsRow: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
            Text("Quick Actions")
                .font(PCFont.headline)
                .foregroundStyle(PCColors.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: PCTokens.spacingMD) {
                QuickActionButton(icon: "fork.knife", title: "What can\nI make?", color: PCColors.accent) {
                    onSwitchToRecipesCanMake?()
                }
                .accessibilityIdentifier("home.quickAction.canMake")
                QuickActionButton(icon: "cart.fill", title: "What to\nbuy?", color: PCColors.expiring) {
                    prepareShoppingConfirmation()
                }
                .accessibilityIdentifier("home.quickAction.shopping")
                QuickActionButton(icon: "calendar", title: "Plan\nmeals", color: PCColors.info) {
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
        let row = HStack(spacing: PCTokens.spacingMD) {
            Image(systemName: entry.mealType.icon)
                .font(.title3)
                .foregroundStyle(PCColors.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.mealType.rawValue)
                    .font(PCFont.micro)
                    .foregroundStyle(PCColors.textTertiary)
                Text(entry.displayName)
                    .font(PCFont.headline)
                    .foregroundStyle(PCColors.textPrimary)
                if let planningSubtitle = entry.planningSubtitle {
                    Text(planningSubtitle)
                        .font(PCFont.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }

            Spacer()

            if entry.recipe != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(PCColors.textTertiary)
            } else if entry.preparedDish != nil || entry.isPreparedFoodPlan {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(PCColors.textTertiary)
            }
        }
        .padding(.vertical, PCTokens.spacingXS)

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
        VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
            PCSectionHeader(title: "Suggested for You", subtitle: "Based on your pantry")

            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                HStack(spacing: PCTokens.spacingLG) {
                    RoundedRectangle(cornerRadius: PCTokens.cornerRadius)
                        .fill(PCColors.accent.opacity(0.12))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "fork.knife")
                                .font(.title2)
                                .foregroundStyle(PCColors.accent)
                        )

                    VStack(alignment: .leading, spacing: PCTokens.spacingSM) {
                        Text(recipe.title)
                            .font(PCFont.headline)
                            .foregroundStyle(PCColors.textPrimary)

                        if let desc = recipe.description {
                            Text(desc)
                                .font(PCFont.caption)
                                .foregroundStyle(PCColors.textSecondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: PCTokens.spacingMD) {
                            PCDifficultyBadge(difficulty: recipe.difficulty)
                            Label(recipe.totalTimeDisplay, systemImage: "clock")
                                .font(PCFont.caption)
                                .foregroundStyle(PCColors.textSecondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(PCColors.textTertiary)
                }
            }
        }
        .padding(PCTokens.cardPadding)
        .pcCard()
    }

    // MARK: - Weekly Nutrition Card
    private func weeklyNutritionCard(_ nutrition: WeeklyNutritionSummary) -> some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
            PCSectionHeader(
                title: "This Week",
                subtitle: "\(nutrition.mealsPlanned) meals planned"
            )

            HStack(spacing: PCTokens.spacingLG) {
                NutritionCircle(label: "Avg Cal", value: nutrition.avgCaloriesPerMeal, unit: "kcal", color: PCColors.expiring)
                NutritionCircle(label: "Protein", value: nutrition.avgProteinPerMeal, unit: "g", color: PCColors.expired)
                NutritionCircle(label: "Carbs", value: nutrition.avgCarbsPerMeal, unit: "g", color: PCColors.fresh)
                NutritionCircle(label: "Fat", value: nutrition.avgFatPerMeal, unit: "g", color: PCColors.info)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(PCTokens.cardPadding)
        .pcCard()
    }

    // MARK: - Batch Prep Card
    private var batchPrepCard: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingSM) {
            HStack {
                Image(systemName: "clock.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(PCColors.accent)
                Text("Batch Prep Tip")
                    .font(PCFont.headline)
            }
            Text("It's the weekend! Consider prepping meals for the week. Check your meal plan and cook in batches to save time.")
                .font(PCFont.body)
                .foregroundStyle(PCColors.textSecondary)
        }
        .padding(PCTokens.cardPadding)
        .pcCard()
    }

    // MARK: - Active Cooks Banner
    private var activeCooksBanner: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(PCColors.expiring)
                Text("Active Cooks")
                    .font(PCFont.headline)
                    .foregroundStyle(PCColors.textPrimary)
                Spacer()
                PCBadge(text: "\(viewModel.appState.activeCooks.count)", color: PCColors.expiring)
            }

            ForEach(viewModel.appState.activeCooks.activeSessions) { session in
                Button {
                    if let recipe = viewModel.appState.allRecipes.first(where: { $0.id == session.recipeId }) {
                        resumeRecipe = recipe
                    }
                } label: {
                    HStack(spacing: PCTokens.spacingMD) {
                        Image(systemName: "frying.pan.fill")
                            .font(.system(size: PCTokens.iconSize))
                            .foregroundStyle(PCColors.accent)
                            .frame(width: 44, height: 44)
                            .background(PCColors.accent.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
                            Text(session.recipeName)
                                .font(PCFont.headline)
                                .foregroundStyle(PCColors.textPrimary)
                            Text("Step \(session.currentStepIndex + 1) of \(session.totalSteps)")
                                .font(PCFont.caption)
                                .foregroundStyle(PCColors.textSecondary)
                        }

                        Spacer()

                        let elapsed = Int(Date().timeIntervalSince(session.backgroundedAt))
                        let minutes = elapsed / 60
                        Text(minutes < 1 ? "Just now" : "\(minutes)m ago")
                            .font(PCFont.micro)
                            .foregroundStyle(PCColors.textTertiary)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(PCColors.textTertiary)
                    }
                    .padding(.vertical, PCTokens.spacingSM)
                }
            }
        }
        .padding(PCTokens.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: PCTokens.cornerRadius)
                .fill(PCColors.expiring.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: PCTokens.cornerRadius)
                        .strokeBorder(PCColors.expiring.opacity(0.2), lineWidth: 1)
                )
        )
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
            VStack(spacing: PCTokens.spacingSM) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(title)
                    .font(PCFont.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(PCColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, PCTokens.cardPadding)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadius))
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
        VStack(spacing: PCTokens.spacingXS) {
            Text("\(value)")
                .font(PCFont.headline)
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 10))
                .foregroundStyle(PCColors.textTertiary)
            Text(label)
                .font(PCFont.micro)
                .foregroundStyle(PCColors.textSecondary)
        }
    }
}
