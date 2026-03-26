import SwiftUI


private struct RecipeMultiCookQueueSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let baseRecipe: Recipe
    let appState: AppState
    let onSave: ([Recipe]) -> Void

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebouncer = TaskDebouncer()
    @State private var selectedRecipeIDs: Set<UUID> = []

    private var availableRecipes: [Recipe] {
        var seenIDs: Set<UUID> = [baseRecipe.id]
        return appState.allRecipes.filter { recipe in
            guard recipe.id != baseRecipe.id else { return false }
            return seenIDs.insert(recipe.id).inserted
        }
    }

    private var selectedRecipes: [Recipe] {
        [baseRecipe] + availableRecipes.filter { selectedRecipeIDs.contains($0.id) }
    }

    private var filteredRecipes: [Recipe] {
        SearchQuerySupport.filtered(availableRecipes, query: debouncedSearchText) { recipe in
            [recipe.title, recipe.totalTimeDisplay, recipe.source.label].joined(separator: " ")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppSearchField(
                    "Search recipes to add",
                    text: $searchText,
                    onTextChange: { text in
                        SearchQuerySupport.schedule(text: text, debouncer: searchDebouncer) {
                            debouncedSearchText = $0
                        }
                    }
                )
                .padding(.horizontal)
                .padding(.top, 12)

                AppList {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(baseRecipe.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(PCColors.textPrimary)
                            Text("This recipe is always included. Add one or more other recipes to queue them as one parallel stage.")
                                .font(.caption)
                                .foregroundStyle(PCColors.textSecondary)
                        }
                    } header: {
                        Text("Base Recipe")
                    }

                    Section {
                        ForEach(filteredRecipes) { recipe in
                            Button {
                                toggle(recipe.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedRecipeIDs.contains(recipe.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedRecipeIDs.contains(recipe.id) ? PCColors.accent : PCColors.textTertiary)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(recipe.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(PCColors.textPrimary)
                                        HStack(spacing: 8) {
                                            Text(recipe.totalTimeDisplay)
                                                .font(.caption)
                                                .foregroundStyle(PCColors.textSecondary)
                                            if !recipe.source.isUserRecipe {
                                                Text(recipe.source.label)
                                                    .font(.caption2)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(PCColors.teal)
                                            }
                                        }
                                    }

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Add More Recipes")
                    } footer: {
                        if filteredRecipes.isEmpty {
                            Text("No recipes match your current search.")
                        }
                    }
                }
            }
            .navigationTitle("Queue Multi-Cook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Queue") {
                        onSave(selectedRecipes)
                    }
                    .disabled(selectedRecipeIDs.isEmpty)
                }
            }
        }
    }

    private func toggle(_ recipeID: UUID) {
        if selectedRecipeIDs.contains(recipeID) {
            selectedRecipeIDs.remove(recipeID)
        } else {
            selectedRecipeIDs.insert(recipeID)
        }
    }
}
struct RecipeDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var recipe: Recipe
    @State private var servings: Int
    @State private var showCookMode = false
    @State private var showGathering = false
    @State private var showSubstitutions = false
    @State private var showShoppingList = false
    @State private var showPantryReview = false
    @State private var substitutions: [SubstitutionSuggestion] = []
    @State private var healthierSuggestion: HealthierSuggestion?
    @State private var shoppingList: [ShoppingItem] = []
    @State private var pantryReviewItems: [PantryCookReviewItem] = []
    @State private var loadingActions: Set<RecipeAction> = []
    @State private var actionErrorMessage: String?
    @State private var existingSession: CookingSession?
    @State private var showEndOtherCookAlert = false
    @State private var showModify = false
    @State private var modifyText = ""
    @State private var isModifying = false
    @State private var showEditor = false
    private let maxServings = 100

    init(recipe: Recipe) {
        _recipe = State(initialValue: recipe)
        _servings = State(initialValue: recipe.servings)
    }

    private var scaledRecipe: Recipe {
        recipe.scaled(to: servings)
    }

    private var pantryMatch: PantryMatchResult {
        scaledRecipe.pantryMatch(pantry: appState.pantryItems)
    }

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroImage

                VStack(alignment: .leading, spacing: 20) {
                    titleSection
                    pantryMatchSection
                    actionButtons
                    modifySection
                    servingsAdjuster

                    if let nutrition = scaledRecipe.nutrition {
                        nutritionSection(nutrition)
                    }

                    ingredientsSection
                    stepsSection

                    if !recipe.dietaryTags.isEmpty {
                        dietaryTagsSection
                            .padding(.bottom, 16)
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(PCColors.background)
        .onAppear {
            existingSession = CookingSession.load(recipeId: recipe.id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    recipe.isFavorite.toggle()
                    Task {
                        await appState.toggleFavoriteWithSave(recipe)
                    }
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(recipe.isFavorite ? .red : PCColors.textTertiary)
                }
                .accessibilityIdentifier("recipe.detail.favoriteButton")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(PCColors.teal)
                }
                .accessibilityIdentifier("recipe.detail.editButton")
            }
        }
        .sheet(isPresented: $showGathering) {
            IngredientGatheringView(recipes: [scaledRecipe]) {
                CookModeView(recipe: scaledRecipe)
                    .environment(appState)
            }
        }
        .fullScreenCover(isPresented: $showCookMode) {
            let queueContext = existingSession.flatMap { appState.cookQueueContext(for: $0) }
            if let session = existingSession {
                CookModeView(
                    recipe: scaledRecipe,
                    resumeAtStep: session.currentStepIndex,
                    isResuming: true,
                    queueID: queueContext?.queueID,
                    queueStageID: queueContext?.stageID
                )
            } else {
                CookModeView(recipe: scaledRecipe)
            }
        }
        .sheet(isPresented: $showSubstitutions) {
            SubstitutionsView(substitutions: substitutions)
        }
        .sheet(item: $healthierSuggestion) { suggestion in
            HealthierView(suggestion: suggestion)
        }
        .sheet(isPresented: $showShoppingList) {
            ShoppingPreviewView(items: shoppingList)
        }
        .appNavigationSheet(isPresented: $showPantryReview) {
            PantryCookReviewSheet(
                recipeTitle: scaledRecipe.title,
                items: $pantryReviewItems,
                onApply: { items in
                    await appState.applyPantryCookReview(items)
                }
            )
        }
        .appNavigationSheet(isPresented: $showEditor) {
            RecipeEditorView(
                recipe: recipe,
                isNewRecipe: false,
                onSave: { saved in
                    handleSavedRecipe(saved)
                },
                onSaveAsNew: { newRecipe in
                    handleSavedRecipeAsNew(newRecipe)
                }
            )
            .navigationTitle("Edit Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEditor = false }
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(actionErrorMessage ?? "Something went wrong. Please try again.")
        }
        .alert("End Current Cook?", isPresented: $showEndOtherCookAlert) {
            Button("End & Start New", role: .destructive) {
                appState.activeCooks.endAllSessions()
                showGathering = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You already have an active cooking session. End it to start a new one.")
        }
    }

    private func presentPantryReview() {
        let reviewItems = appState.pantryCookReviewItems(for: scaledRecipe)
        guard !reviewItems.isEmpty else {
            actionErrorMessage = "No pantry-tracked items from this recipe are currently matched in your pantry."
            return
        }

        pantryReviewItems = reviewItems
        showPantryReview = true
    }

    // MARK: - Hero Image
    private var heroImage: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            PCColors.accent.opacity(0.18),
                            PCColors.teal.opacity(0.10),
                            PCColors.expiring.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 220)

            Image(systemName: recipe.mealType?.icon ?? "fork.knife")
                .font(.system(size: 56))
                .foregroundStyle(PCColors.accent.opacity(0.35))
        }
    }

    // MARK: - Title Section
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(PCColors.textPrimary)

            if let desc = recipe.description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(PCColors.textSecondary)
            }

            HStack(spacing: 16) {
                DifficultyBadge(difficulty: recipe.difficulty)

                Label(recipe.totalTimeDisplay, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)

                if let prep = recipe.prepTimeMinutes {
                    Label("\(prep)m prep", systemImage: "hand.raised")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }

                if recipe.timesCooked > 0 {
                    Label("Cooked \(recipe.timesCooked)x", systemImage: "flame")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Pantry Match Section
    private var pantryMatchSection: some View {
        AppDetailCard("Pantry Match") {
            HStack {
                Text("Coverage")
                    .font(.subheadline)
                    .foregroundStyle(PCColors.textSecondary)
                Spacer()
                Text(pantryMatch.displayPercentage)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(pantryMatch.canMake ? PCColors.accent : PCColors.expiring)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PCColors.fillTertiary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(pantryMatch.canMake ? PCColors.accent : PCColors.expiring)
                        .frame(width: geo.size.width * (pantryMatch.matchPercentage.isFinite ? max(0, min(pantryMatch.matchPercentage / 100, 1)) : 0))
                }
            }
            .frame(height: 8)

            // Status line
            if pantryMatch.canMake {
                Label("You have everything!", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(PCColors.accent)
            } else if pantryMatch.canMakeWithSubstitutions {
                Label("Can make with substitutions", systemImage: "arrow.triangle.swap")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.60, green: 0.76, blue: 0.25))
            }

            // Missing ingredients with inline substitution suggestions
            if !pantryMatch.missingIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Missing Ingredients")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(PCColors.textSecondary)

                    ForEach(pantryMatch.missingIngredients, id: \.name) { ingredient in
                        missingIngredientRow(ingredient)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func missingIngredientRow(_ ingredient: Ingredient) -> some View {
        let subs = SubstitutionRepository.shared.substitutions(for: ingredient.name, pantry: appState.pantryItems)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(PCColors.expired)
                Text(ingredient.name)
                    .font(.caption)
                    .foregroundStyle(PCColors.textPrimary)

                let qty = ingredient.displayText
                    .replacingOccurrences(of: ingredient.name, with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !qty.isEmpty {
                    Text("(\(qty))")
                        .font(.caption2)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }

            if !subs.isEmpty {
                ForEach(subs.prefix(3)) { sub in
                    HStack(spacing: 4) {
                        Image(systemName: sub.inPantry ? "checkmark.circle.fill" : "arrow.turn.down.right")
                            .font(.system(size: 8))
                            .foregroundStyle(sub.inPantry ? PCColors.accent : Color(red: 0.60, green: 0.76, blue: 0.25))
                        Text(sub.substituteName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(sub.inPantry ? PCColors.accent : Color(red: 0.60, green: 0.76, blue: 0.25))
                        if sub.inPantry {
                            Text("In pantry")
                                .font(.system(size: 8))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(PCColors.accent.opacity(0.15))
                                .foregroundStyle(PCColors.accent)
                                .clipShape(Capsule())
                        }
                        Text("(\(sub.ratio))")
                            .font(.system(size: 9))
                            .foregroundStyle(PCColors.textSecondary)
                        if sub.cookingImpact != .none {
                            Text(sub.cookingImpact.rawValue.lowercased())
                                .font(.system(size: 8))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(sub.cookingImpact.color.opacity(0.15))
                                .foregroundStyle(sub.cookingImpact.color)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.leading, 16)
                    .opacity(sub.inPantry ? 1.0 : 0.7)
                }
            }
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Prominent Cook button
            Button {
                existingSession = CookingSession.load(recipeId: recipe.id)
                if existingSession != nil {
                    showCookMode = true       // resume — skip gathering
                } else if appState.activeCooks.hasActiveSessions {
                    showEndOtherCookAlert = true
                } else {
                    showGathering = true   // new session — show ingredients first
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: existingSession != nil ? "arrow.counterclockwise" : "play.fill")
                        .font(.title3)
                    if let session = existingSession {
                        Text("Resume Cooking (step \(session.currentStepIndex + 1)/\(session.totalSteps))")
                            .font(.headline)
                    } else {
                        Text("Start Cooking")
                            .font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(existingSession != nil ? PCColors.expiring : PCColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            HStack(spacing: 12) {
                ActionButton(icon: "list.number", title: "Add Queue", color: PCColors.info) {
                    Task {
                        await appState.addRecipesToCookQueue([scaledRecipe])
                    }
                }

                ActionButton(icon: "cart", title: "What to Buy", color: PCColors.expiring, isLoading: loadingActions.contains(.shopping)) {
                    Task {
                        loadingActions.insert(.shopping)
                        let result = await appState.getShoppingList(for: recipe)
                        loadingActions.remove(.shopping)
                        if result.isEmpty {
                            actionErrorMessage = "Couldn't generate shopping list. Please check your internet connection and try again."
                        } else {
                            shoppingList = result
                            showShoppingList = true
                        }
                    }
                }

                ActionButton(icon: "arrow.triangle.2.circlepath", title: "Substitutes", color: PCColors.teal, isLoading: loadingActions.contains(.substitutions)) {
                    Task {
                        loadingActions.insert(.substitutions)
                        let result = await appState.getSubstitutions(for: recipe)
                        loadingActions.remove(.substitutions)
                        if result.isEmpty {
                            actionErrorMessage = "No local substitutions are available for the missing ingredients in this recipe."
                        } else {
                            substitutions = result
                            showSubstitutions = true
                        }
                    }
                }

                ActionButton(icon: "heart.circle", title: "Healthier", color: PCColors.accent, isLoading: loadingActions.contains(.healthier)) {
                    Task {
                        loadingActions.insert(.healthier)
                        let result = await appState.getHealthierVersion(of: recipe)
                        loadingActions.remove(.healthier)
                        if let result {
                            healthierSuggestion = result
                        } else {
                            actionErrorMessage = "Couldn't generate healthier suggestions. Please check your internet connection and try again."
                        }
                    }
                }
            }

            Button {
                presentPantryReview()
            } label: {
                Label("Cooked this? Update pantry", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PCColors.info)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(PCColors.info.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Servings Adjuster
    private var servingsAdjuster: some View {
        HStack {
            Text("Servings")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    if servings > 1 { servings -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(servings > 1 ? PCColors.accent : PCColors.textTertiary)
                }
                .disabled(servings <= 1)

                Text("\(servings)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(width: 40)

                Button {
                    if servings < maxServings {
                        servings += 1
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(servings < maxServings ? PCColors.accent : PCColors.textTertiary)
                }
                .disabled(servings >= maxServings)
            }
        }
        .padding()
        .background(PCColors.fillTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Nutrition Section
    private func nutritionSection(_ nutrition: NutritionInfo) -> some View {
        AppDetailCard("Nutrition", subtitle: "Per serving") {
            HStack(spacing: 16) {
                NutritionCircle(label: "Calories", value: nutrition.calories, unit: "kcal", color: PCColors.expiring)
                NutritionCircle(label: "Protein", value: Int(nutrition.protein), unit: "g", color: PCColors.expired)
                NutritionCircle(label: "Carbs", value: Int(nutrition.carbohydrates), unit: "g", color: PCColors.accent)
                NutritionCircle(label: "Fat", value: Int(nutrition.fat), unit: "g", color: PCColors.info)
            }
            .frame(maxWidth: .infinity)

            // Extended macros
            let extras: [(String, String)] = [
                nutrition.fiber.map { ("Fiber", "\(Int($0))g") },
                nutrition.sugar.map { ("Sugar", "\(Int($0))g") },
                nutrition.sodium.map { ("Sodium", "\(Int($0))mg") },
            ].compactMap { $0 }

            if !extras.isEmpty {
                HStack(spacing: 16) {
                    ForEach(extras, id: \.0) { item in
                        HStack(spacing: 4) {
                            Text(item.0)
                                .font(.caption2)
                                .foregroundStyle(PCColors.textSecondary)
                            Text(item.1)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(PCColors.textPrimary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Modify Section
    private var modifySection: some View {
        AppDetailCard("Recipe Adjustments", subtitle: "Prompt PantryChef to revise this recipe") {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showModify.toggle()
                    if !showModify {
                        modifyText = ""
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.subheadline)
                        .foregroundStyle(PCColors.teal)
                    Text("Modify Recipe")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(PCColors.textPrimary)
                    Spacer()
                    Image(systemName: showModify ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }

            if showModify {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Describe what you'd like changed — be as specific or vague as you want.")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)

                    HStack(spacing: 4) {
                        ForEach(["Make it spicier", "Use my pantry", "Halve the carbs", "Make it faster"], id: \.self) { suggestion in
                            Button {
                                modifyText = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 10))
                                    .foregroundStyle(PCColors.teal)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(PCColors.teal.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("e.g. Make it dairy-free using my pantry", text: $modifyText, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(1...4)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .appInputSurface()

                        Text("\(servings)")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .frame(width: 40)

                        Button {
                            if servings < maxServings {
                                servings += 1
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(servings < maxServings ? PCColors.accent : PCColors.textTertiary)
                        }
                        .disabled(servings >= maxServings)
                        Button {
                            Task { await performModify() }
                        } label: {
                            Group {
                                if isModifying {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(modifyText.trimmingCharacters(in: .whitespaces).isEmpty ? PCColors.textTertiary : PCColors.teal)
                            .clipShape(Circle())
                        }
                        .disabled(modifyText.trimmingCharacters(in: .whitespaces).isEmpty || isModifying)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func performModify() async {
        hideKeyboard()
        isModifying = true
        if let normalizedRecipe = await appState.modifyRecipe(recipe, feedback: modifyText) {
            withAnimation {
                recipe = normalizedRecipe.recipe
                servings = normalizedRecipe.recipe.servings
            }
            modifyText = ""
            showModify = false
            // Persist if it's a saved recipe
            if appState.recipes.contains(where: { $0.id == recipe.id }) {
                await appState.updateRecipe(normalizedRecipe.recipe)
            }
        } else {
            actionErrorMessage = "Couldn't modify the recipe. Please try again."
        }
        isModifying = false
    }

    private func handleSavedRecipe(_ saved: Recipe) {
        recipe = saved
        servings = saved.servings
        showEditor = false
        Task {
            await appState.updateRecipe(saved)
        }
    }

    private func handleSavedRecipeAsNew(_ newRecipe: Recipe) {
        showEditor = false
        Task {
            await appState.addRecipe(newRecipe)
        }
    }

    // MARK: - Ingredients Section
    private var ingredientsSection: some View {
        AppIngredientDetailGroup("Ingredients", subtitle: "\(scaledRecipe.ingredients.count) items") {
            ForEach(scaledRecipe.ingredients) { ingredient in
                let isAvailable = appState.pantryItems.contains {
                    IngredientMatcher.pantryItemMatchesIngredient($0, ingredient: ingredient)
                }

                AppIngredientDetailRow(
                    ingredientText: ingredient.displayText,
                    isAvailable: isAvailable,
                    isOptional: ingredient.isOptional
                )
            }
        }
    }

    // MARK: - Steps Section
    private var stepsSection: some View {
        AppDetailCard("Steps", subtitle: "\(recipe.steps.count) steps") {
            ForEach(recipe.steps.sorted { $0.stepNumber < $1.stepNumber }) { step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(step.stepNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(PCColors.accent)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.instruction)
                            .font(.subheadline)
                            .foregroundStyle(PCColors.textPrimary)

                        if let timer = step.timerMinutes {
                            Label("\(timer) min", systemImage: "timer")
                                .font(.caption)
                                .foregroundStyle(PCColors.expiring)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(PCColors.expiring.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        if let tip = step.tip {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.caption2)
                                    .foregroundStyle(PCColors.expiring)
                                Text(tip)
                                    .font(.caption)
                                    .foregroundStyle(PCColors.textSecondary)
                            }
                            .padding(8)
                            .background(PCColors.expiring.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Dietary Tags Section
    private var dietaryTagsSection: some View {
        AppDetailCard("Dietary Info") {
            FlowLayout(spacing: 8) {
                ForEach(recipe.dietaryTags) { tag in
                    DietaryTagChip(tag: tag)
                }
            }
        }
    }
}

// MARK: - Recipe Action
private enum RecipeAction: Equatable {
    case shopping, substitutions, healthier
}

// MARK: - Action Button
struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(color)
                        .frame(height: 24)
                } else {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(PCColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Substitutions View
struct SubstitutionsView: View {
    @Environment(\.dismiss) private var dismiss
    let substitutions: [SubstitutionSuggestion]

    /// Group substitutions by original ingredient for multi-sub display
    private var grouped: [(ingredient: String, suggestions: [SubstitutionSuggestion])] {
        var dict: [String: [SubstitutionSuggestion]] = [:]
        var order: [String] = []
        for sub in substitutions {
            if dict[sub.originalIngredient] == nil { order.append(sub.originalIngredient) }
            dict[sub.originalIngredient, default: []].append(sub)
        }
        return order.map { (ingredient: $0, suggestions: dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            AppList {
                if substitutions.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: "No substitutions needed",
                        message: "You have all the ingredients!"
                    )
                } else {
                    ForEach(grouped, id: \.ingredient) { group in
                        Section {
                            ForEach(group.suggestions) { sub in
                                substitutionRow(sub)
                                    .opacity(sub.inPantry ? 1.0 : 0.8)
                            }
                        } header: {
                            Text(group.ingredient)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(PCColors.textPrimary)
                        }
                    }
                }
            }
            .navigationTitle("Substitutions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func substitutionRow(_ sub: SubstitutionSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sub.substituteName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(sub.inPantry ? PCColors.accent : PCColors.textPrimary)

                if sub.inPantry {
                    Text("In your pantry")
                        .font(.system(size: 9))
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PCColors.accent.opacity(0.15))
                        .foregroundStyle(PCColors.accent)
                        .clipShape(Capsule())
                }
                Spacer()
            }

            Text("Ratio: \(sub.ratio)")
                .font(.caption)
                .foregroundStyle(PCColors.textSecondary)

            HStack(spacing: 16) {
                if sub.tasteImpact != "None" {
                    DetailChip(icon: "mouth", text: sub.tasteImpact)
                }
                if sub.textureImpact != "None" {
                    DetailChip(icon: "hand.point.up", text: sub.textureImpact)
                }
                if sub.cookingImpact != "None" {
                    DetailChip(icon: "flame", text: sub.cookingImpact)
                }
            }

            Text(sub.nutritionImpact)
                .font(.caption)
                .foregroundStyle(PCColors.accent)

            if let notes = sub.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(PCColors.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail Chip
struct DetailChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(PCColors.textSecondary)
    }
}

// MARK: - Healthier View
struct HealthierView: View {
    @Environment(\.dismiss) private var dismiss
    let suggestion: HealthierSuggestion

    var body: some View {
        NavigationStack {
            AppList {
                Section {
                    Text(suggestion.overallImpact)
                        .font(.subheadline)
                        .foregroundStyle(PCColors.accent)

                    if let reduction = suggestion.estimatedCalorieReduction {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(PCColors.accent)
                            Text("~\(reduction) fewer calories per serving")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                } header: {
                    Text("Impact")
                }

                Section {
                    ForEach(suggestion.suggestions) { tweak in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tweak.change)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(tweak.benefit)
                                .font(.caption)
                                .foregroundStyle(PCColors.accent)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Suggestions")
                }
            }
            .navigationTitle("Make It Healthier")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Shopping Preview View
struct ShoppingPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    let items: [ShoppingItem]

    var body: some View {
        NavigationStack {
            AppList {
                let grouped = Dictionary(grouping: items, by: { $0.category })
                ForEach(grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { category in
                    Section {
                        ForEach(grouped[category] ?? []) { item in
                            Text(item.displayText)
                                .font(.subheadline)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            CategoryIcon(category: category, size: 20)
                            Text(category.rawValue)
                        }
                    }
                }
            }
            .navigationTitle("What to Buy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Shopping List") {
                        let itemsToAdd = items
                        Task {
                            await appState.addShoppingItems(itemsToAdd)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Add Recipe View
struct AddRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var inputText = ""
    @State private var isParsing = false
    @State private var importedRecipeDraft: AppState.ReviewableImportedRecipe?
    @State private var errorMessage: String?

    let onSave: (Recipe) -> Void

    private var isURL: Bool {
        inputText.trimmed.isValidURL
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let importedRecipe = importedRecipeDraft {
                    // Structured editor for parsed recipe
                    RecipeEditorView(importedRecipe: importedRecipe, isNewRecipe: true) { saved in
                        onSave(saved)
                        dismiss()
                    }
                } else {
                    inputForm
                }
            }
            .background(PCColors.background)
            .navigationTitle(importedRecipeDraft != nil ? "Review Recipe" : "Add Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if importedRecipeDraft != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            importedRecipeDraft = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                Text("Re-parse")
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Input Form

    private var inputForm: some View {
        AppScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundStyle(PCColors.accent)

                    Text("Paste a recipe")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Paste a recipe URL, or type / paste the full recipe text and we'll turn it into a structured recipe for you.")
                        .font(.subheadline)
                        .foregroundStyle(PCColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 20)

                // Hint chips
                VStack(alignment: .leading, spacing: 6) {
                    Text("Works with:")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                    HStack(spacing: 6) {
                        ForEach(["Recipe URLs", "Copy-paste text", "Free-form notes"], id: \.self) { hint in
                            Text(hint)
                                .font(.caption2)
                                .foregroundStyle(PCColors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(PCColors.accent.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                // Text input area
                VStack(alignment: .leading, spacing: 6) {
                    AppMultilineInput(
                        text: $inputText,
                        prompt: "https://example.com/recipe\n\nor paste recipe text here...\n\ne.g.\nChicken Stir Fry\n2 chicken breasts, sliced\n1 bell pepper, diced\n3 tbsp soy sauce\n\n1. Heat oil in a wok...\n2. Cook chicken until golden...",
                        minHeight: 220,
                        cornerRadius: 12
                    )

                    if isURL {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption2)
                            Text("URL detected — will fetch and parse")
                                .font(.caption)
                        }
                        .foregroundStyle(PCColors.accent)
                    }
                }
                .padding(.horizontal)

                if let errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(errorMessage)
                            .font(.caption)
                    }
                    .foregroundStyle(PCColors.expired)
                    .padding(.horizontal)
                }

                // Parse button
                Button {
                    Task { await parseInput() }
                } label: {
                    Group {
                        if isParsing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("Parsing recipe...")
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                Text("Parse Recipe")
                            }
                        }
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(inputText.trimmed.isEmpty || isParsing ? PCColors.textTertiary : PCColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(inputText.trimmed.isEmpty || isParsing)
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Parse Input

    private func parseInput() async {
        isParsing = true
        errorMessage = nil

        let text = inputText.trimmed

        if text.isValidURL {
            if let recipe = await appState.importRecipeFromURL(text) {
                importedRecipeDraft = recipe
            } else {
                errorMessage = "Couldn't parse recipe from that URL. Try pasting the recipe text instead."
            }
        } else {
            if let recipe = await appState.importRecipeFromText(text) {
                importedRecipeDraft = recipe
            } else {
                errorMessage = "Couldn't parse the text into a recipe. Try including a title, ingredients, and steps."
            }
        }

        isParsing = false
    }

}

// MARK: - Import Recipe URL View
struct ImportRecipeURLView: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: RecipeViewModel
    @State private var urlString = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(PCColors.accent)

                Text("Import from URL")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Paste a recipe URL and we'll extract the recipe details for you.")
                    .font(.subheadline)
                    .foregroundStyle(PCColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                TextField("https://example.com/recipe...", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .padding(.horizontal)

                Button {
                    viewModel.importFromURL(urlString) {
                        if viewModel.importedRecipeDraft != nil {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Import Recipe")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(PCColors.accent)
                .padding(.horizontal)
                .disabled(urlString.isEmpty || viewModel.isLoading)

                Spacer()
            }
            .padding(.top, 40)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Flow Layout
/// Simple wrapping horizontal layout used for chip-like content.
/// Subviews are laid out left-to-right and wrapped to the next line when needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (positions, CGSize(width: maxX, height: currentY + lineHeight))
    }
}

