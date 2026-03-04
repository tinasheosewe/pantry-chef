import SwiftUI

struct RecipeListView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: RecipeViewModel

    init() {
        _viewModel = StateObject(wrappedValue: RecipeViewModel(appState: AppState()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                searchBar

                // Filter Pills
                filterPills

                // Content
                if viewModel.filteredRecipes.isEmpty && appState.recipes.isEmpty {
                    EmptyStateView(
                        icon: "book.closed",
                        title: "No recipes yet",
                        message: "Add recipes manually, import from a URL, or photograph a cookbook page.",
                        actionTitle: "Add Recipe"
                    ) {
                        viewModel.showAddRecipe = true
                    }
                } else if viewModel.filteredRecipes.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No matches",
                        message: "Try adjusting your search or filters.",
                        actionTitle: "Clear Filters"
                    ) {
                        viewModel.clearFilters()
                    }
                } else {
                    recipeGrid
                }
            }
            .background(AppColors.background)
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { viewModel.showAddRecipe = true } label: {
                            Label("Add Manually", systemImage: "square.and.pencil")
                        }
                        Button { viewModel.showImportURL = true } label: {
                            Label("Import from URL", systemImage: "link")
                        }
                        Button { viewModel.showPhotoImport = true } label: {
                            Label("Photo of Recipe", systemImage: "camera")
                        }
                        Divider()
                        Button { viewModel.whatCanIMake() } label: {
                            Label("What Can I Make?", systemImage: "sparkles")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        ForEach(RecipeViewModel.SortOrder.allCases, id: \.self) { order in
                            Button {
                                viewModel.sortOrder = order
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                    if viewModel.sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAddRecipe) {
                AddRecipeView { recipe in
                    Task { await viewModel.addRecipe(recipe) }
                }
            }
            .sheet(isPresented: $viewModel.showImportURL) {
                ImportRecipeURLView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showWhatCanIMake) {
                WhatCanIMakeView(results: viewModel.whatCanIMakeResults)
            }
        }
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.mediumGray)
            TextField("Search recipes...", text: $viewModel.searchText)
                .font(.subheadline)

            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.mediumGray)
                }
            }
        }
        .padding(10)
        .background(AppColors.lightGray)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Filter Pills
    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Favorites toggle
                FilterPill(
                    title: "Favorites",
                    icon: "heart.fill",
                    isSelected: viewModel.showOnlyFavorites
                ) {
                    viewModel.showOnlyFavorites.toggle()
                }

                // Difficulty
                ForEach(DifficultyLevel.allCases) { level in
                    FilterPill(
                        title: level.label,
                        isSelected: viewModel.selectedDifficulty == level
                    ) {
                        viewModel.selectedDifficulty = viewModel.selectedDifficulty == level ? nil : level
                    }
                }

                // Meal Type
                ForEach(MealType.allCases) { type in
                    FilterPill(
                        title: type.rawValue,
                        icon: type.icon,
                        isSelected: viewModel.selectedMealType == type
                    ) {
                        viewModel.selectedMealType = viewModel.selectedMealType == type ? nil : type
                    }
                }

                // Clear all filters
                if viewModel.hasActiveFilters {
                    Button {
                        viewModel.clearFilters()
                    } label: {
                        Text("Clear")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(AppColors.softRed)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Recipe Grid
    private var recipeGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 16) {
                ForEach(viewModel.filteredRecipes) { recipe in
                    NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                        RecipeCardView(recipe: recipe, pantry: appState.pantryItems)
                    }
                    .contextMenu {
                        Button { Task { await viewModel.toggleFavorite(recipe) } } label: {
                            Label(recipe.isFavorite ? "Unfavorite" : "Favorite",
                                  systemImage: recipe.isFavorite ? "heart.slash" : "heart")
                        }
                        Button(role: .destructive) {
                            Task { await viewModel.deleteRecipe(recipe) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Filter Pill
struct FilterPill: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? AppColors.primaryGreen : AppColors.lightGray)
            .foregroundStyle(isSelected ? .white : AppColors.subtleText)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Recipe Card View
struct RecipeCardView: View {
    let recipe: Recipe
    let pantry: [PantryItem]

    private var match: PantryMatchResult {
        recipe.pantryMatch(pantry: pantry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.primaryGreen.opacity(0.1))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay(
                        Image(systemName: recipe.mealType?.icon ?? "fork.knife")
                            .font(.title)
                            .foregroundStyle(AppColors.primaryGreen.opacity(0.5))
                    )

                if recipe.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(6)
                        .background(.white.opacity(0.9))
                        .clipShape(Circle())
                        .padding(8)
                }
            }

            // Title
            Text(recipe.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.darkText)
                .lineLimit(2)

            // Meta
            HStack(spacing: 8) {
                if let time = recipe.totalTimeDisplay as String? {
                    Label(time, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(AppColors.subtleText)
                }

                DifficultyBadge(difficulty: recipe.difficulty)
            }

            // Pantry match indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(match.canMake ? AppColors.primaryGreen : AppColors.warmOrange)
                    .frame(width: 6, height: 6)

                Text(match.canMake ? "Ready to cook" :
                     "Need \(match.missingIngredients.count) item\(match.missingIngredients.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(match.canMake ? AppColors.primaryGreen : AppColors.warmOrange)
            }
        }
        .padding(12)
        .cardStyle()
    }
}

// MARK: - What Can I Make View
struct WhatCanIMakeView: View {
    @Environment(\.dismiss) private var dismiss
    let results: [PantryMatchResult]

    var body: some View {
        NavigationStack {
            List {
                let canMake = results.filter { $0.canMake }
                let nearMisses = results.filter { !$0.canMake && $0.matchPercentage >= 50 }

                if !canMake.isEmpty {
                    Section("Ready to Cook") {
                        ForEach(canMake) { result in
                            matchRow(result)
                        }
                    }
                }

                if !nearMisses.isEmpty {
                    Section("Almost There") {
                        ForEach(nearMisses) { result in
                            matchRow(result)
                        }
                    }
                }

                if canMake.isEmpty && nearMisses.isEmpty {
                    EmptyStateView(
                        icon: "fork.knife",
                        title: "Add more items",
                        message: "Stock your pantry to see recipe matches."
                    )
                }
            }
            .navigationTitle("What Can I Make?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func matchRow(_ result: PantryMatchResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.recipe.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(result.displayPercentage)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(result.canMake ? AppColors.primaryGreen : AppColors.warmOrange)
            }

            if !result.missingIngredients.isEmpty {
                Text("Missing: \(result.missingIngredients.map { $0.name }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
            }

            // Match bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.lightGray)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(result.canMake ? AppColors.primaryGreen : AppColors.warmOrange)
                        .frame(width: geo.size.width * result.matchPercentage / 100)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
    }
}
