import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var showWhatCanIMake = false
    @State private var whatCanIMakeResults: [PantryMatchResult] = []
    @State private var showReceiptScanner = false

    var onSwitchToShopping: (() -> Void)?
    var onSwitchToPlan: (() -> Void)?

    init(appState: AppState, onSwitchToShopping: (() -> Void)? = nil, onSwitchToPlan: (() -> Void)? = nil) {
        _viewModel = State(initialValue: HomeViewModel(appState: appState))
        self.onSwitchToShopping = onSwitchToShopping
        self.onSwitchToPlan = onSwitchToPlan
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    greetingHeader
                    todaysMealPlanCard

                    if !viewModel.appState.expiringItems.isEmpty {
                        expiringSoonCard
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
            .background(AppColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await viewModel.appState.loadAllData()
                viewModel.refresh()
            }
            .onAppear {
                viewModel.refresh()
            }
            .sheet(isPresented: $showWhatCanIMake) {
                WhatCanIMakeView(results: whatCanIMakeResults)
            }
            .sheet(isPresented: $showReceiptScanner) {
                ReceiptScannerView { items in
                    Task {
                        for itemName in items {
                            let item = PantryItem(name: itemName, category: .other)
                            await viewModel.appState.addPantryItem(item)
                        }
                    }
                }
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

            if viewModel.appState.mealPlan.isEmpty {
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
                    HStack(spacing: 12) {
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
                        }

                        Spacer()

                        if let recipe = entry.recipe, let time = recipe.totalTimeDisplay as String? {
                            Text(time)
                                .font(.caption)
                                .foregroundStyle(AppColors.subtleText)
                        }
                    }
                    .padding(.vertical, 4)
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
                subtitle: "\(viewModel.appState.expiringItems.count) items need attention"
            )

            ForEach(viewModel.appState.expiringItems.prefix(5)) { item in
                HStack(spacing: 12) {
                    CategoryIcon(category: item.category, size: 28)
                    Text(item.name)
                        .font(.subheadline)
                    Spacer()
                    ExpiryBadge(status: item.expiryStatus, daysLeft: item.daysUntilExpiry)
                }
            }

            if viewModel.appState.expiringItems.count > 5 {
                Text("+ \(viewModel.appState.expiringItems.count - 5) more")
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
                    whatCanIMakeResults = viewModel.appState.recipes
                        .map { $0.pantryMatch(pantry: viewModel.appState.pantryItems) }
                        .sorted { $0.matchPercentage > $1.matchPercentage }
                    showWhatCanIMake = true
                }
                QuickActionButton(icon: "cart.fill", title: "What to\nbuy?", color: AppColors.warmOrange) {
                    Task {
                        await viewModel.appState.generateShoppingListFromMealPlan()
                    }
                    onSwitchToShopping?()
                }
                QuickActionButton(icon: "camera.fill", title: "Scan\nreceipt", color: .blue) {
                    showReceiptScanner = true
                }
            }
        }
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
                            if let time = recipe.totalTimeDisplay as String? {
                                Label(time, systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.subtleText)
                            }
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
                NutritionCircle(label: "Avg Cal", value: nutrition.avgCaloriesPerDay, unit: "kcal", color: AppColors.warmOrange)
                NutritionCircle(label: "Protein", value: Int(nutrition.totalProtein / 7), unit: "g", color: AppColors.softRed)
                NutritionCircle(label: "Carbs", value: Int(nutrition.totalCarbs / 7), unit: "g", color: AppColors.primaryGreen)
                NutritionCircle(label: "Fat", value: Int(nutrition.totalFat / 7), unit: "g", color: .blue)
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
