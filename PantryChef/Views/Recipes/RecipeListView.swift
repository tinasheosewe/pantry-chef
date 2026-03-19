import SwiftUI

struct RecipeListView: View {
    @State private var viewModel: RecipeViewModel
    @State private var showMultiCookSelection = false
    @State private var selectedSection: RecipeSection = .myRecipes
    @State private var discoverVisibleCount = 12
    @State private var lastLoadMoreTriggerID: UUID?
    @State private var discoverTapStartedAt: CFAbsoluteTime?
    @State private var discoverSwitchStartedAt: CFAbsoluteTime?
    @State private var loggedDiscoverFirstCellForCurrentSwitch = false
    @State private var showCuisinePicker = false
    @State private var showRecipeBuilder = false
    @State private var generatedRecipe: Recipe?
    @Binding var activateCanMakeFilter: Bool
    @FocusState private var isSearchFocused: Bool

    enum RecipeSection: String, CaseIterable {
        case myRecipes = "My Recipes"
        case discover = "Discover"
    }

    init(appState: AppState, activateCanMakeFilter: Binding<Bool> = .constant(false)) {
        _viewModel = State(initialValue: RecipeViewModel(appState: appState))
        _activateCanMakeFilter = activateCanMakeFilter
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let trimmedQuery = viewModel.effectiveSearchQuery
        let hasQuery = trimmedQuery.count >= 3
        let filteredUserRecipes = selectedSection == .myRecipes ? viewModel.filteredUserRecipes : []
        let filteredDiscoverRecipes = selectedSection == .discover ? viewModel.filteredDiscoverRecipes : []

        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                sectionPicker(discoverCount: selectedSection == .discover ? filteredDiscoverRecipes.count : nil)
                filterPills

                if selectedSection == .myRecipes {
                    userRecipesContent(recipes: filteredUserRecipes)
                } else {
                    discoverContent(recipes: filteredDiscoverRecipes, hasQuery: hasQuery, trimmedQuery: trimmedQuery)
                }
            }
            .accessibilityIdentifier("recipes.screen")
            .background(AppColors.background)
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { viewModel.showAddRecipe = true } label: {
                            Label("Add Recipe", systemImage: "square.and.pencil")
                        }
                        Button { viewModel.showPhotoImport = true } label: {
                            Label("Photo of Recipe", systemImage: "camera")
                        }
                        Divider()
                        Button {
                            viewModel.activateWhatCanIMake()
                        } label: {
                            Label("What Can I Make?", systemImage: "sparkles")
                        }
                        Button { showMultiCookSelection = true } label: {
                            Label("Multi-Cook", systemImage: "flame.fill")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityIdentifier("recipes.toolbar.addMenu")
                }

                ToolbarItem(placement: .topBarTrailing) {
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
                    .accessibilityIdentifier("recipes.toolbar.sortMenu")
                }
            }
            .sheet(isPresented: $viewModel.showAddRecipe) {
                AddRecipeView { recipe in
                    Task { await viewModel.addRecipe(recipe) }
                }
                .environment(viewModel.appState)
            }
            .sheet(isPresented: $viewModel.showPhotoImport) {
                RecipePhotoImportView(viewModel: viewModel)
            }
            .sheet(isPresented: $showMultiCookSelection) {
                MultiCookSelectionView()
                    .environment(viewModel.appState)
            }
            .sheet(isPresented: $showRecipeBuilder) {
                RecipeBuilderView(
                    query: viewModel.searchText.trimmingCharacters(in: .whitespaces)
                ) { recipe in
                    generatedRecipe = recipe
                }
                .environment(viewModel.appState)
            }
            .navigationDestination(item: $generatedRecipe) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .navigationDestination(for: UUID.self) { recipeID in
                if let recipe = viewModel.recipeForNavigation(id: recipeID) {
                    RecipeDetailView(recipe: recipe)
                } else {
                    centeredEmptyState {
                        EmptyStateView(
                            icon: "exclamationmark.triangle",
                            title: "Recipe unavailable",
                            message: "This recipe could not be loaded.",
                            actionTitle: "Back"
                        ) {
                        }
                    }
                }
            }
            .sheet(item: Binding(
                get: { viewModel.importedRecipe },
                set: { viewModel.importedRecipe = $0 }
            )) { recipe in
                NavigationStack {
                    RecipeDetailView(recipe: recipe)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    Task { await viewModel.addRecipe(recipe) }
                                    viewModel.importedRecipe = nil
                                }
                            }
                        }
                }
            }
            .onChange(of: activateCanMakeFilter) { _, newValue in
                if newValue {
                    viewModel.activateWhatCanIMake()
                    activateCanMakeFilter = false
                }
            }
            .onChange(of: selectedSection) { _, newValue in
                if newValue == .discover {
                    discoverVisibleCount = 12
                    lastLoadMoreTriggerID = nil
                    discoverSwitchStartedAt = CFAbsoluteTimeGetCurrent()
                    loggedDiscoverFirstCellForCurrentSwitch = false
                    viewModel.scheduleBackgroundMatchPrewarm(visibleDiscoverCount: discoverVisibleCount)
                    viewModel.scheduleFullMetricsCoverage(reason: "discover-tab")
                }
            }
            .onChange(of: viewModel.appState.pantryItems) {
                viewModel.scheduleBackgroundMatchPrewarm(visibleDiscoverCount: discoverVisibleCount)
                viewModel.scheduleFullMetricsCoverage(reason: "pantry-change")
            }
            .onChange(of: viewModel.appState.recipes) {
                viewModel.scheduleFullMetricsCoverage(reason: "user-recipes-change")
            }
            .onChange(of: viewModel.appState.discoverRecipes) {
                viewModel.scheduleFullMetricsCoverage(reason: "discover-recipes-change")
            }
            .onChange(of: viewModel.discoverSearchResults) {
                viewModel.scheduleFullMetricsCoverage(reason: "discover-search-change")
            }
            .onChange(of: viewModel.effectiveSearchQuery) {
                discoverVisibleCount = 12
                lastLoadMoreTriggerID = nil
            }
            .onAppear {
                // Prewarm discover data path so first switch is instant.
                Task { @MainActor in
                    viewModel.prewarmDiscover(visibleCount: discoverVisibleCount)
                    viewModel.scheduleBackgroundMatchPrewarm(visibleDiscoverCount: discoverVisibleCount)
                    viewModel.scheduleFullMetricsCoverage(reason: "list-appear")
                }

                // Safety net: ensure discover recipes are loaded even if init timing was off
                if viewModel.appState.discoverRecipes.isEmpty {
                    viewModel.appState.refreshDiscoverRecipes()
                }
            }
        }
    }

    // MARK: - Section Picker

    private func sectionPicker(discoverCount: Int?) -> some View {
        HStack(spacing: 0) {
            ForEach(RecipeSection.allCases, id: \.self) { section in
                Button {
                    if section == .discover { discoverTapStartedAt = CFAbsoluteTimeGetCurrent() }
                    selectedSection = section
                    // No-op on section switch — state is preserved
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text(section.rawValue)
                                .font(.subheadline)
                                .fontWeight(selectedSection == section ? .semibold : .regular)

                            if section == .discover && selectedSection == .discover {
                                let count = discoverCount ?? 0
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(AppColors.primaryGreen)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .foregroundStyle(selectedSection == section ? AppColors.darkText : AppColors.subtleText)

                        Rectangle()
                            .fill(selectedSection == section ? AppColors.primaryGreen : .clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        @Bindable var viewModel = viewModel
        return HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.mediumGray)
            TextField("Search recipes...", text: $viewModel.searchText)
                .font(.subheadline)
                .focused($isSearchFocused)
                .accessibilityIdentifier("recipes.searchField")
                .onChange(of: viewModel.searchText) {
                    viewModel.onSearchTextChanged(isDiscoverTab: selectedSection == .discover)
                }
            

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
                // Can Make toggle
                FilterPill(
                    title: "Can Make",
                    icon: "checkmark.circle.fill",
                    isSelected: viewModel.showCanMakeOnly
                ) {
                    viewModel.showCanMakeOnly.toggle()
                    if viewModel.showCanMakeOnly {
                        viewModel.sortOrder = .matchPercent
                    }
                }

                if viewModel.showCanMakeOnly {
                    FilterPill(
                        title: "+ Subs",
                        icon: "arrow.triangle.swap",
                        isSelected: viewModel.showWithSubstitutions
                    ) {
                        viewModel.showWithSubstitutions.toggle()
                    }
                }

                if selectedSection == .myRecipes {
                    FilterPill(
                        title: "Favorites",
                        icon: "heart.fill",
                        isSelected: viewModel.showOnlyFavorites
                    ) {
                        viewModel.showOnlyFavorites.toggle()
                    }
                }

                // Cuisine pill
                FilterPill(
                    title: viewModel.selectedCuisine?.rawValue ?? "Cuisine",
                    icon: nil,
                    isSelected: viewModel.selectedCuisine != nil
                ) {
                    showCuisinePicker.toggle()
                }
                .popover(isPresented: $showCuisinePicker) {
                    cuisinePickerContent
                }

                ForEach(MealType.allCases) { type in
                    FilterPill(
                        title: type.rawValue,
                        icon: type.icon,
                        isSelected: viewModel.selectedMealType == type
                    ) {
                        viewModel.selectedMealType = viewModel.selectedMealType == type ? nil : type
                    }
                }

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

    // MARK: - Cuisine Picker

    private var cuisinePickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    viewModel.selectedCuisine = nil
                    showCuisinePicker = false
                } label: {
                    HStack {
                        Text("All Cuisines")
                        Spacer()
                        if viewModel.selectedCuisine == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppColors.primaryGreen)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .foregroundStyle(AppColors.darkText)

                Divider()

                ForEach(CuisineType.allCases) { cuisine in
                    Button {
                        viewModel.selectedCuisine = cuisine
                        showCuisinePicker = false
                    } label: {
                        HStack {
                            Text(cuisine.icon)
                            Text(cuisine.rawValue)
                            Spacer()
                            if viewModel.selectedCuisine == cuisine {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.primaryGreen)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .foregroundStyle(AppColors.darkText)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 220)
        .frame(maxHeight: 350)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - User Recipes Content

    private func userRecipesContent(recipes: [Recipe]) -> some View {
        Group {
            if recipes.isEmpty && viewModel.appState.recipes.isEmpty {
                centeredEmptyState {
                    EmptyStateView(
                        icon: "book.closed",
                        title: "No recipes yet",
                        message: "Add recipes manually, import from a URL, or photograph a cookbook page.",
                        actionTitle: "Add Recipe"
                    ) {
                        viewModel.showAddRecipe = true
                    }
                }
            } else if recipes.isEmpty {
                centeredEmptyState {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No matches",
                        message: "Try adjusting your search or filters.",
                        actionTitle: "Clear Filters"
                    ) {
                        viewModel.clearFilters()
                    }
                }
            } else {
                recipeGrid(recipes: recipes, isUserSection: true, trimmedQuery: nil)
            }
        }
    }

    // MARK: - Discover Content

    private func discoverContent(recipes: [Recipe], hasQuery: Bool, trimmedQuery: String) -> some View {
        Group {
            if viewModel.isSearchingAPI {
                if hasQuery {
                    // Show grid with AI tile + loading indicator while API results load
                    recipeGrid(recipes: recipes, isUserSection: false, trimmedQuery: trimmedQuery)
                } else {
                    centeredEmptyState {
                        ProgressView("Searching...")
                    }
                }
            } else if recipes.isEmpty && !hasQuery {
                centeredEmptyState {
                    if !trimmedQuery.isEmpty {
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "No results",
                            message: "No recipes match \"\(trimmedQuery)\". Try a different search term.",
                            actionTitle: "Clear Search"
                        ) {
                            viewModel.searchText = ""
                        }
                    } else {
                        EmptyStateView(
                            icon: "globe",
                            title: "Discover recipes",
                            message: "Browse featured recipes or search to find new ones. Use \"Can Make\" to filter by your pantry.",
                            actionTitle: "Search by Pantry"
                        ) {
                            viewModel.showCanMakeOnly = true
                            viewModel.sortOrder = .matchPercent
                        }
                    }
                }
            } else {
                recipeGrid(recipes: recipes, isUserSection: false, trimmedQuery: trimmedQuery)
            }
        }
    }

    /// Wraps empty-state content in a full-bleed, centered container
    /// so it fills the available space with the correct background.
    private func centeredEmptyState<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Recipe Grid

    private func recipeGrid(recipes: [Recipe], isUserSection: Bool, trimmedQuery: String?) -> some View {
        let pantry = viewModel.appState.pantryItems
        let query = trimmedQuery ?? ""
        let showAIGenerateTile = !isUserSection && query.count >= 3
        let displayedRecipes = isUserSection ? recipes : Array(recipes.prefix(discoverVisibleCount))
        let matchMetrics = viewModel.matchMetricsMap(for: displayedRecipes)
        return ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 16) {
                // AI Generate tile — first card in Discover when query is 3+ chars
                if showAIGenerateTile {
                    Button {
                        showRecipeBuilder = true
                    } label: {
                        AIGenerateTileView(query: query)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(displayedRecipes) { recipe in
                    NavigationLink(value: recipe.id) {
                        RecipeCardView(recipe: recipe, pantry: pantry, metrics: matchMetrics[recipe.id])
                    }
                    .contextMenu {
                        if isUserSection {
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
                    // Infinite scroll: trigger next page when last few items appear
                    .onAppear {
                        if !isUserSection,
                           !loggedDiscoverFirstCellForCurrentSwitch,
                           discoverSwitchStartedAt != nil {
                            loggedDiscoverFirstCellForCurrentSwitch = true
                        }

                        if !isUserSection,
                           recipe.id == displayedRecipes.last?.id {
                            if displayedRecipes.count < recipes.count {
                                discoverVisibleCount = min(discoverVisibleCount + 24, recipes.count)
                                return
                            }
                            if recipe.id == recipes.last?.id,
                               lastLoadMoreTriggerID != recipe.id,
                               viewModel.hasMorePages {
                                lastLoadMoreTriggerID = recipe.id
                                Task { await viewModel.loadMoreDiscoverRecipes() }
                            }
                        }
                    }
                }
            }
            .padding()

            // Loading indicator at bottom during API search or pagination
            if !isUserSection && (viewModel.isSearchingAPI || viewModel.isLoadingMore) {
                ProgressView()
                    .padding()
            }
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
    private let metrics: RecipeMatchMetrics

    init(recipe: Recipe, pantry: [PantryItem], metrics: RecipeMatchMetrics? = nil) {
        self.recipe = recipe
        self.pantry = pantry
        self.metrics = metrics ?? RecipeMatchMetrics(from: recipe.pantryMatch(pantry: pantry))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.primaryGreen.opacity(0.1))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: recipe.mealType?.icon ?? "fork.knife")
                                .font(.title)
                                .foregroundStyle(AppColors.primaryGreen.opacity(0.5))
                            if let cuisine = recipe.cuisine {
                                Text(cuisine.icon)
                                    .font(.caption)
                            }
                        }
                    )

                VStack(alignment: .trailing, spacing: 4) {
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(6)
                            .background(.white.opacity(0.9))
                            .clipShape(Circle())
                    }

                    // Match percentage badge
                    if !pantry.isEmpty {
                        matchBadge
                    }
                }
                .padding(8)
            }

            HStack(spacing: 4) {
                // Source tag
                if !recipe.source.isUserRecipe {
                    Text(recipe.source.label)
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(sourceColor)
                        .clipShape(Capsule())
                }

                Text(recipe.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.darkText)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Label(recipe.totalTimeDisplay, systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(AppColors.subtleText)
                DifficultyBadge(difficulty: recipe.difficulty)
            }

            // Pantry match status
            pantryMatchStatus

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .cardStyle()
    }

    private var matchBadge: some View {
        let pct = Int(metrics.effectiveMatchPercentage)
        return Text("\(pct)%")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(matchBadgeColor(pct))
            .clipShape(Capsule())
    }

    private func matchBadgeColor(_ pct: Int) -> Color {
        if pct >= 100 { return AppColors.primaryGreen }
        if pct >= 75 { return Color(red: 0.60, green: 0.76, blue: 0.25) }
        if pct >= 50 { return AppColors.warmOrange }
        return AppColors.softRed
    }

    private var pantryMatchStatus: some View {
        HStack(spacing: 4) {
            if metrics.canMake {
                Circle()
                    .fill(AppColors.primaryGreen)
                    .frame(width: 6, height: 6)
                Text("Ready to cook")
                    .font(.caption2)
                    .foregroundStyle(AppColors.primaryGreen)
            } else if metrics.canMakeWithSubstitutions {
                Circle()
                    .fill(Color(red: 0.60, green: 0.76, blue: 0.25))
                    .frame(width: 6, height: 6)
                Text("With subs")
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.60, green: 0.76, blue: 0.25))
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(red: 0.60, green: 0.76, blue: 0.25))
            } else {
                Circle()
                    .fill(AppColors.warmOrange)
                    .frame(width: 6, height: 6)
                Text("Need \(metrics.missingIngredientCount) item\(metrics.missingIngredientCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(AppColors.warmOrange)
            }
        }
    }

    private var sourceColor: Color {
        switch recipe.source {
        case .user: return AppColors.primaryGreen
        case .bundled: return AppColors.warmOrange
        case .spoonacular: return Color(red: 0.38, green: 0.65, blue: 0.96)
        case .aiGenerated: return AppColors.accentTeal
        }
    }
}

// MARK: - AI Generate Tile
struct AIGenerateTileView: View {
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.warmOrange.opacity(0.15),
                                AppColors.accentTeal.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(4/3, contentMode: .fit)

                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColors.warmOrange, AppColors.accentTeal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("Chef")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.subtleText)
                }
            }

            HStack(spacing: 4) {
                Text("Chef")
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppColors.accentTeal)
                    .clipShape(Capsule())

                Text("Create \"\(query)\"")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.darkText)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Label("Custom", systemImage: "slider.horizontal.3")
                    .font(.caption2)
                    .foregroundStyle(AppColors.subtleText)
            }

            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8))
                    .foregroundStyle(AppColors.warmOrange)
                Text("Tap to customize & generate")
                    .font(.caption2)
                    .foregroundStyle(AppColors.warmOrange)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .cardStyle()
    }
}

// MARK: - What Can I Make View (legacy, kept for compatibility)
struct WhatCanIMakeView: View {
    @Environment(\.dismiss) private var dismiss
    let results: [PantryMatchResult]

    var body: some View {
        NavigationStack {
            List {
                let canMake = results.filter { $0.canMake }
                let withSubs = results.filter { !$0.canMake && $0.canMakeWithSubstitutions }
                let nearMisses = results.filter { !$0.canMake && !$0.canMakeWithSubstitutions && $0.matchPercentage >= 50 }

                if !canMake.isEmpty {
                    Section("Ready to Cook") {
                        ForEach(canMake) { result in
                            matchRow(result)
                        }
                    }
                }

                if !withSubs.isEmpty {
                    Section("With Substitutions") {
                        ForEach(withSubs) { result in
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

                if canMake.isEmpty && withSubs.isEmpty && nearMisses.isEmpty {
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

                if result.canMakeWithSubstitutions && !result.canMake {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.60, green: 0.76, blue: 0.25))
                }

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

            if !result.substitutableIngredients.isEmpty {
                Text("Subs available: \(result.substitutableIngredients.map { $0.ingredient.name }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.60, green: 0.76, blue: 0.25))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.lightGray)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(result.canMake ? AppColors.primaryGreen : AppColors.warmOrange)
                        .frame(width: geo.size.width * (result.matchPercentage.isFinite ? max(0, min(result.matchPercentage / 100, 1)) : 0))
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
    }
}
