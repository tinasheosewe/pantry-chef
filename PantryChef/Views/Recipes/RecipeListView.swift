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
    @State private var launchRecipe: Recipe?
    @Binding var activateCanMakeFilter: Bool

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

        AppScreen("recipes.screen") {
            VStack(spacing: 0) {
                sectionPicker(discoverCount: selectedSection == .discover ? filteredDiscoverRecipes.count : nil)
                searchAndFilterBar

                if selectedSection == .myRecipes {
                    userRecipesContent(recipes: filteredUserRecipes)
                } else {
                    discoverContent(recipes: filteredDiscoverRecipes, hasQuery: hasQuery, trimmedQuery: trimmedQuery)
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { viewModel.showAddRecipe = true } label: {
                            Label("Add Recipe", systemImage: "square.and.pencil")
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
                    viewModel.addRecipe(recipe)
                }
                .environment(viewModel.appState)
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
            .navigationDestination(item: $launchRecipe) { recipe in
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
            .appNavigationSheet(item: Binding(
                get: { viewModel.importedRecipeDraft },
                set: { viewModel.importedRecipeDraft = $0 }
            )) { importedRecipe in
                RecipeEditorView(importedRecipe: importedRecipe, isNewRecipe: true) { saved in
                    viewModel.addRecipe(saved)
                    viewModel.importedRecipeDraft = nil
                }
                .navigationTitle("Review Recipe")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            viewModel.importedRecipeDraft = nil
                        }
                    }
                }
                .environment(viewModel.appState)
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
            .onChange(of: viewModel.coverageRefreshState) {
                viewModel.scheduleBackgroundMatchPrewarm(visibleDiscoverCount: discoverVisibleCount)
                viewModel.scheduleFullMetricsCoverage(reason: "coverage-refresh")
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
        PCSegmentedPicker(
            items: RecipeSection.allCases,
            selection: $selectedSection,
            label: { $0.rawValue },
            badge: { section in
                if section == .discover, let count = discoverCount, count > 0 {
                    return count
                }
                return nil
            },
            onSelect: { section in
                if section == .discover { discoverTapStartedAt = CFAbsoluteTimeGetCurrent() }
            }
        )
        .pickerPadding()
    }

    // MARK: - Search & Filter Bar
    private var searchAndFilterBar: some View {
        @Bindable var viewModel = viewModel
        return PCSearchFilterBar(
            placeholder: "Search recipes...",
            searchText: $viewModel.searchText,
            accessibilityID: "recipes.searchField",
            onTextChange: { _ in viewModel.onSearchTextChanged(isDiscoverTab: selectedSection == .discover) }
        ) {
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
                        .font(PCFont.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(PCColors.expired)
                }
            }
        }
    }

    // MARK: - Cuisine Picker

    private var cuisinePickerContent: some View {
        AppScrollView {
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
                                .foregroundStyle(PCColors.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .foregroundStyle(PCColors.textPrimary)

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
                                    .foregroundStyle(PCColors.accent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .foregroundStyle(PCColors.textPrimary)
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
            if recipes.isEmpty && !hasQuery {
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
            PCColors.background
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
        return AppScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 16) {
                // AI Generate tile — first card in Discover when query is 3+ chars
                if showAIGenerateTile {
                    Button {
                        showRecipeBuilder = true
                    } label: {
                        RecipeIdeaTileView(query: query)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(displayedRecipes) { recipe in
                    NavigationLink(value: recipe.id) {
                        RecipeCardView(recipe: recipe, pantry: pantry, metrics: matchMetrics[recipe.id])
                    }
                    .accessibilityIdentifier("recipes.card.\(recipe.id.uuidString)")
                    .contextMenu {
                        if isUserSection {
                            Button { viewModel.toggleFavorite(recipe) } label: {
                                Label(recipe.isFavorite ? "Unfavorite" : "Favorite",
                                      systemImage: recipe.isFavorite ? "heart.slash" : "heart")
                            }
                            Button(role: .destructive) {
                                viewModel.deleteRecipe(recipe)
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
                            }
                        }
                    }
                    .task {
                        guard AppLaunchOptions.current.openSeededRecipeDetail else { return }
                        guard launchRecipe == nil else { return }
                        launchRecipe = viewModel.recipeForNavigation(id: Recipe.stirFryId)
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
            HStack(spacing: PCTokens.spacingXS) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(PCFont.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, PCTokens.spacingMD)
            .padding(.vertical, PCTokens.spacingSM)
            .background(isSelected ? PCColors.accent : PCColors.fillTertiary)
            .foregroundStyle(isSelected ? .white : PCColors.textSecondary)
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
        VStack(alignment: .leading, spacing: PCTokens.spacingSM) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: PCTokens.cornerRadius)
                    .fill(PCColors.accent.opacity(0.08))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay(
                        VStack(spacing: PCTokens.spacingXS) {
                            Image(systemName: recipe.mealType?.icon ?? "fork.knife")
                                .font(.title)
                                .foregroundStyle(PCColors.accent.opacity(0.4))
                            if let cuisine = recipe.cuisine {
                                Text(cuisine.icon)
                                    .font(PCFont.caption)
                            }
                        }
                    )

                VStack(alignment: .trailing, spacing: PCTokens.spacingXS) {
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(6)
                            .background(.white.opacity(0.9))
                            .clipShape(Circle())
                    }

                    if !pantry.isEmpty {
                        matchBadge
                    }
                }
                .padding(PCTokens.spacingSM)
            }

            HStack(spacing: PCTokens.spacingXS) {
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
                    .font(PCFont.headline)
                    .foregroundStyle(PCColors.textPrimary)
                    .lineLimit(2)
                    .accessibilityIdentifier("recipes.card.title.\(recipe.id.uuidString)")
            }

            HStack(spacing: PCTokens.spacingSM) {
                Label(recipe.totalTimeDisplay, systemImage: "clock")
                    .font(PCFont.micro)
                    .foregroundStyle(PCColors.textSecondary)
                PCDifficultyBadge(difficulty: recipe.difficulty)
            }

            pantryMatchStatus

            Spacer(minLength: 0)
        }
        .padding(PCTokens.spacingMD)
        .frame(maxHeight: .infinity, alignment: .top)
        .pcCard()
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
        if pct >= 100 { return PCColors.fresh }
        if pct >= 75 { return Color(red: 0.60, green: 0.76, blue: 0.25) }
        if pct >= 50 { return PCColors.expiring }
        return PCColors.expired
    }

    private var pantryMatchStatus: some View {
        HStack(spacing: PCTokens.spacingXS) {
            if metrics.canMake {
                PCStatusDot(PCColors.fresh)
                Text("Ready to cook")
                    .font(PCFont.micro)
                    .foregroundStyle(PCColors.fresh)
            } else if metrics.canMakeWithSubstitutions {
                PCStatusDot(Color(red: 0.60, green: 0.76, blue: 0.25))
                Text("With subs")
                    .font(PCFont.micro)
                    .foregroundStyle(Color(red: 0.60, green: 0.76, blue: 0.25))
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(red: 0.60, green: 0.76, blue: 0.25))
            } else {
                PCStatusDot(PCColors.expiring)
                Text("Need \(metrics.missingIngredientCount) item\(metrics.missingIngredientCount == 1 ? "" : "s")")
                    .font(PCFont.micro)
                    .foregroundStyle(PCColors.expiring)
            }
        }
    }

    private var sourceColor: Color {
        switch recipe.source {
        case .user: return PCColors.fresh
        case .bundled: return PCColors.expiring
        case .imported: return Color(red: 0.72, green: 0.56, blue: 0.41)
        case .aiGenerated: return PCColors.teal
        }
    }
}

// MARK: - Recipe Idea Tile
struct RecipeIdeaTileView: View {
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingSM) {
            ZStack {
                RoundedRectangle(cornerRadius: PCTokens.cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                PCColors.expiring.opacity(0.15),
                                PCColors.teal.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(4/3, contentMode: .fit)

                VStack(spacing: PCTokens.spacingSM) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [PCColors.expiring, PCColors.teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("Chef")
                        .font(PCFont.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }

            HStack(spacing: PCTokens.spacingXS) {
                Text("Chef")
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(PCColors.teal)
                    .clipShape(Capsule())

                Text("Create \"\(query)\"")
                    .font(PCFont.headline)
                    .foregroundStyle(PCColors.textPrimary)
                    .lineLimit(2)
            }

            HStack(spacing: PCTokens.spacingSM) {
                Label("Custom", systemImage: "slider.horizontal.3")
                    .font(PCFont.micro)
                    .foregroundStyle(PCColors.textSecondary)
            }

            HStack(spacing: PCTokens.spacingXS) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8))
                    .foregroundStyle(PCColors.expiring)
                Text("Tap to customize & generate")
                    .font(PCFont.micro)
                    .foregroundStyle(PCColors.expiring)
            }

            Spacer(minLength: 0)
        }
        .padding(PCTokens.spacingMD)
        .frame(maxHeight: .infinity, alignment: .top)
        .pcCard()
    }
}


