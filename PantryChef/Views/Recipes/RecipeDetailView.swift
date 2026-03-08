import SwiftUI

struct RecipeDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var recipe: Recipe
    @State private var servings: Int
    @State private var showCookMode = false
    @State private var showGathering = false
    @State private var isFetchingSteps = false
    @State private var showSubstitutions = false
    @State private var showShoppingList = false
    @State private var substitutions: [SubstitutionSuggestion] = []
    @State private var healthierSuggestion: HealthierSuggestion?
    @State private var shoppingList: [ShoppingItem] = []
    @State private var isLoadingAction = false
    @State private var actionErrorMessage: String?
    @State private var existingSession: CookingSession?
    @State private var showModify = false
    @State private var modifyText = ""
    @State private var isModifying = false
    @State private var showEditor = false

    init(recipe: Recipe) {
        _recipe = State(initialValue: recipe)
        _servings = State(initialValue: recipe.servings)
    }

    private var scaledRecipe: Recipe {
        recipe.scaled(to: servings)
    }

    private var pantryMatch: PantryMatchResult {
        recipe.pantryMatch(pantry: appState.pantryItems)
    }

    var body: some View {
        ScrollView {
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
                    }
                }
                .padding(.horizontal)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            existingSession = CookingSession.load(recipeId: recipe.id)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(AppColors.accentTeal)
                    }
                    Button {
                        recipe.isFavorite.toggle()
                        Task {
                            await appState.toggleFavoriteWithSave(recipe)
                        }
                    } label: {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(recipe.isFavorite ? .red : AppColors.mediumGray)
                    }
                }
            }
        }
        .sheet(isPresented: $showGathering) {
            IngredientGatheringView(recipes: [scaledRecipe]) {
                showGathering = false
                showCookMode = true
            }
        }
        .fullScreenCover(isPresented: $showCookMode) {
            if let session = existingSession {
                CookModeView(recipe: scaledRecipe, resumeAtStep: session.currentStepIndex, isResuming: true)
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
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                RecipeEditorView(
                    recipe: recipe,
                    isNewRecipe: false,
                    onSave: { saved in
                        recipe = saved
                        servings = saved.servings
                        Task { await appState.updateRecipe(saved) }
                        showEditor = false
                    },
                    onSaveAsNew: { newRecipe in
                        Task { await appState.addRecipe(newRecipe) }
                        showEditor = false
                    }
                )
                .navigationTitle("Edit Recipe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showEditor = false }
                    }
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
    }

    // MARK: - Fetch Steps Fallback

    /// For Spoonacular recipes that arrived without steps (complexSearch sometimes
    /// omits analyzedInstructions), fetch the full recipe detail before entering cook mode.
    private func fetchStepsThenCook(spoonId: Int) async {
        isFetchingSteps = true
        defer { isFetchingSteps = false }
        do {
            if let detailed = try await SpoonacularService.shared.getRecipeDetail(id: spoonId),
               !detailed.steps.isEmpty {
                recipe = Recipe(
                    id: recipe.id,
                    title: recipe.title,
                    description: recipe.description,
                    ingredients: detailed.ingredients.isEmpty ? recipe.ingredients : detailed.ingredients,
                    steps: detailed.steps,
                    servings: recipe.servings,
                    prepTimeMinutes: recipe.prepTimeMinutes ?? detailed.prepTimeMinutes,
                    cookTimeMinutes: recipe.cookTimeMinutes ?? detailed.cookTimeMinutes,
                    difficulty: detailed.difficulty,
                    dietaryTags: recipe.dietaryTags,
                    mealType: recipe.mealType,
                    cuisine: recipe.cuisine,
                    source: recipe.source,
                    nutrition: recipe.nutrition ?? detailed.nutrition,
                    imageURL: recipe.imageURL,
                    sourceURL: recipe.sourceURL
                )
            }
        } catch {
            print("[RecipeDetailView] Failed to fetch steps: \(error)")
        }
        // Proceed to cook even if fetch failed — user can still see the recipe
        showGathering = true
    }

    // MARK: - Hero Image
    private var heroImage: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.primaryGreen.opacity(0.18),
                            AppColors.accentTeal.opacity(0.10),
                            AppColors.warmOrange.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 220)

            Image(systemName: recipe.mealType?.icon ?? "fork.knife")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.primaryGreen.opacity(0.35))
        }
    }

    // MARK: - Title Section
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(AppColors.darkText)

            if let desc = recipe.description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.subtleText)
            }

            HStack(spacing: 16) {
                DifficultyBadge(difficulty: recipe.difficulty)

                if let time = recipe.totalTimeDisplay as String? {
                    Label(time, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                if let prep = recipe.prepTimeMinutes {
                    Label("\(prep)m prep", systemImage: "hand.raised")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                if recipe.timesCooked > 0 {
                    Label("Cooked \(recipe.timesCooked)x", systemImage: "flame")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }
            }
        }
    }

    // MARK: - Pantry Match Section
    private var pantryMatchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pantry Match")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(pantryMatch.displayPercentage)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(pantryMatch.canMake ? AppColors.primaryGreen : AppColors.warmOrange)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.lightGray)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(pantryMatch.canMake ? AppColors.primaryGreen : AppColors.warmOrange)
                        .frame(width: geo.size.width * pantryMatch.matchPercentage / 100)
                }
            }
            .frame(height: 8)

            // Status line
            if pantryMatch.canMake {
                Label("You have everything!", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.primaryGreen)
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
                        .foregroundStyle(AppColors.subtleText)

                    ForEach(pantryMatch.missingIngredients, id: \.name) { ingredient in
                        missingIngredientRow(ingredient)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .cardStyle()
    }

    private func missingIngredientRow(_ ingredient: Ingredient) -> some View {
        let subs = SubstitutionRepository.shared.substitutions(for: ingredient.name)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.softRed)
                Text(ingredient.name)
                    .font(.caption)
                    .foregroundStyle(AppColors.darkText)

                let qty = ingredient.displayText
                    .replacingOccurrences(of: ingredient.name, with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !qty.isEmpty {
                    Text("(\(qty))")
                        .font(.caption2)
                        .foregroundStyle(AppColors.subtleText)
                }
            }

            if !subs.isEmpty {
                ForEach(subs.prefix(2), id: \.substitute) { sub in
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(red: 0.60, green: 0.76, blue: 0.25))
                        Text(sub.substitute)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(Color(red: 0.60, green: 0.76, blue: 0.25))
                        Text("(\(sub.ratio))")
                            .font(.system(size: 9))
                            .foregroundStyle(AppColors.subtleText)
                        let worst = sub.tasteImpact.ordinal >= sub.textureImpact.ordinal
                            ? sub.tasteImpact : sub.textureImpact
                        if worst != .none {
                            Text(worst.rawValue.lowercased())
                                .font(.system(size: 8))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(worst.color.opacity(0.15))
                                .foregroundStyle(worst.color)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.leading, 16)
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
                } else {
                    // If this is a Spoonacular recipe with no steps, fetch full details first
                    if recipe.steps.isEmpty, case .spoonacular(let spoonId) = recipe.source {
                        Task { await fetchStepsThenCook(spoonId: spoonId) }
                    } else {
                        showGathering = true   // new session — show ingredients first
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isFetchingSteps {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: existingSession != nil ? "arrow.counterclockwise" : "play.fill")
                            .font(.title3)
                    }
                    if let session = existingSession {
                        Text("Resume Cooking (step \(session.currentStepIndex + 1)/\(session.totalSteps))")
                            .font(.headline)
                    } else {
                        Text(isFetchingSteps ? "Loading Steps…" : "Start Cooking")
                            .font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(existingSession != nil ? AppColors.warmOrange : AppColors.primaryGreen)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isFetchingSteps)

            HStack(spacing: 12) {
                ActionButton(icon: "cart", title: "What to Buy", color: AppColors.warmOrange) {
                Task {
                    isLoadingAction = true
                    let result = await appState.getShoppingList(for: recipe)
                    isLoadingAction = false
                    if result.isEmpty {
                        actionErrorMessage = "Couldn't generate shopping list. Please check your internet connection and try again."
                    } else {
                        shoppingList = result
                        showShoppingList = true
                    }
                }
            }

            ActionButton(icon: "arrow.triangle.2.circlepath", title: "Substitutes", color: AppColors.accentTeal) {
                Task {
                    isLoadingAction = true
                    let result = await appState.getSubstitutions(for: recipe)
                    isLoadingAction = false
                    if result.isEmpty {
                        actionErrorMessage = "Couldn't find substitutions. Please check your internet connection and try again."
                    } else {
                        substitutions = result
                        showSubstitutions = true
                    }
                }
            }

            ActionButton(icon: "heart.circle", title: "Healthier", color: AppColors.primaryGreen) {
                Task {
                    isLoadingAction = true
                    let result = await appState.getHealthierVersion(of: recipe)
                    isLoadingAction = false
                    if let result {
                        healthierSuggestion = result
                    } else {
                        actionErrorMessage = "Couldn't generate healthier suggestions. Please check your internet connection and try again."
                    }
                }
            }
            }
        }
        .overlay {
            if isLoadingAction {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(ProgressView())
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
                        .foregroundStyle(servings > 1 ? AppColors.primaryGreen : AppColors.mediumGray)
                }
                .disabled(servings <= 1)

                Text("\(servings)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(width: 40)

                Button {
                    servings += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppColors.primaryGreen)
                }
            }
        }
        .padding()
        .background(AppColors.lightGray)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Nutrition Section
    private func nutritionSection(_ nutrition: NutritionInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Nutrition", subtitle: "Per serving")

            HStack(spacing: 16) {
                NutritionCircle(label: "Calories", value: nutrition.calories, unit: "kcal", color: AppColors.warmOrange)
                NutritionCircle(label: "Protein", value: Int(nutrition.protein), unit: "g", color: AppColors.softRed)
                NutritionCircle(label: "Carbs", value: Int(nutrition.carbohydrates), unit: "g", color: AppColors.primaryGreen)
                NutritionCircle(label: "Fat", value: Int(nutrition.fat), unit: "g", color: AppColors.accentBlue)
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
                                .foregroundStyle(AppColors.subtleText)
                            Text(item.1)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppColors.darkText)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Modify Section
    private var modifySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showModify.toggle()
                    if !showModify { modifyText = "" }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.accentTeal)
                    Text("Modify Recipe")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.darkText)
                    Spacer()
                    Image(systemName: showModify ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }
            }

            if showModify {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Describe what you'd like changed — be as specific or vague as you want.")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)

                    HStack(spacing: 4) {
                        ForEach(["Make it spicier", "Use my pantry", "Halve the carbs", "Make it faster"], id: \.self) { suggestion in
                            Button {
                                modifyText = suggestion
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppColors.accentTeal)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(AppColors.accentTeal.opacity(0.1))
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
                            .background(AppColors.lightGray)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

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
                            .background(modifyText.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.mediumGray : AppColors.accentTeal)
                            .clipShape(Circle())
                        }
                        .disabled(modifyText.trimmingCharacters(in: .whitespaces).isEmpty || isModifying)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .cardStyle()
    }

    private func performModify() async {
        hideKeyboard()
        isModifying = true
        let pantryNames = appState.pantryItems.map(\.name)
        if let modified = await appState.aiService.modifyRecipe(recipe, feedback: modifyText, pantryIngredients: pantryNames) {
            withAnimation {
                recipe = modified
                servings = modified.servings
            }
            modifyText = ""
            showModify = false
            // Persist if it's a saved recipe
            if appState.recipes.contains(where: { $0.id == recipe.id }) {
                await appState.updateRecipe(recipe)
            }
        } else {
            actionErrorMessage = "Couldn't modify the recipe. Please try again."
        }
        isModifying = false
    }

    // MARK: - Ingredients Section
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ingredients", subtitle: "\(scaledRecipe.ingredients.count) items")

            ForEach(scaledRecipe.ingredients) { ingredient in
                HStack(spacing: 12) {
                    let isAvailable = appState.pantryItems.contains {
                        let pName = $0.name.lowercased()
                        let iName = ingredient.name.lowercased()
                        return pName.contains(iName) || iName.contains(pName)
                    }

                    Image(systemName: isAvailable ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isAvailable ? AppColors.primaryGreen : AppColors.mediumGray)
                        .font(.subheadline)

                    Text(ingredient.displayText)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.darkText)

                    if ingredient.isOptional {
                        Text("optional")
                            .font(.caption2)
                            .foregroundStyle(AppColors.subtleText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.lightGray)
                            .clipShape(Capsule())
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Steps Section
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Steps", subtitle: "\(recipe.steps.count) steps")

            ForEach(recipe.steps.sorted { $0.stepNumber < $1.stepNumber }) { step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(step.stepNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(AppColors.primaryGreen)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.instruction)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.darkText)

                        if let timer = step.timerMinutes {
                            Label("\(timer) min", systemImage: "timer")
                                .font(.caption)
                                .foregroundStyle(AppColors.warmOrange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.warmOrange.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        if let tip = step.tip {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.warmOrange)
                                Text(tip)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.subtleText)
                            }
                            .padding(8)
                            .background(AppColors.warmOrange.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Dietary Tags Section
    private var dietaryTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dietary Info")
                .font(.subheadline)
                .fontWeight(.medium)

            FlowLayout(spacing: 8) {
                ForEach(recipe.dietaryTags) { tag in
                    DietaryTagChip(tag: tag)
                }
            }
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.darkText)
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

    var body: some View {
        NavigationStack {
            List {
                if substitutions.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: "No substitutions needed",
                        message: "You have all the ingredients!"
                    )
                } else {
                    ForEach(substitutions) { sub in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(sub.originalIngredient)
                                    .font(.subheadline)
                                    .strikethrough()
                                    .foregroundStyle(AppColors.subtleText)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.mediumGray)
                                Text(sub.substituteName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppColors.primaryGreen)
                            }

                            Text("Ratio: \(sub.ratio)")
                                .font(.caption)
                                .foregroundStyle(AppColors.subtleText)

                            HStack(spacing: 16) {
                                DetailChip(icon: "mouth", text: sub.tasteImpact)
                                DetailChip(icon: "hand.point.up", text: sub.textureImpact)
                            }

                            Text(sub.nutritionImpact)
                                .font(.caption)
                                .foregroundStyle(AppColors.primaryGreen)

                            HStack {
                                Text("Confidence: \(sub.confidenceLabel)")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.subtleText)
                                Spacer()
                                ConfidenceBar(confidence: sub.confidence)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Substitutions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
        .foregroundStyle(AppColors.subtleText)
    }
}

// MARK: - Confidence Bar
struct ConfidenceBar: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Double(index) / 5.0 < confidence ? AppColors.primaryGreen : AppColors.lightGray)
                    .frame(width: 12, height: 6)
            }
        }
    }
}

// MARK: - Healthier View
struct HealthierView: View {
    @Environment(\.dismiss) private var dismiss
    let suggestion: HealthierSuggestion

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(suggestion.overallImpact)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.primaryGreen)

                    if let reduction = suggestion.estimatedCalorieReduction {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(AppColors.primaryGreen)
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
                                .foregroundStyle(AppColors.primaryGreen)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Suggestions")
                }
            }
            .navigationTitle("Make It Healthier")
            .navigationBarTitleDisplayMode(.inline)
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
            List {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Shopping List") {
                        // Merge new items into existing shopping list, deduplicating by name
                        var existingNames = Set(appState.shoppingItems.map { $0.name.lowercased() })
                        for item in items {
                            if existingNames.insert(item.name.lowercased()).inserted {
                                appState.shoppingItems.append(item)
                            }
                        }
                        dismiss()
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
    @State private var parsedRecipe: Recipe?
    @State private var errorMessage: String?

    let onSave: (Recipe) -> Void

    private var isURL: Bool {
        inputText.trimmed.isValidURL
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let recipe = parsedRecipe {
                    // Structured editor for parsed recipe
                    RecipeEditorView(recipe: recipe, isNewRecipe: true) { saved in
                        onSave(saved)
                        dismiss()
                    }
                } else {
                    inputForm
                }
            }
            .background(AppColors.background)
            .navigationTitle(parsedRecipe != nil ? "Review Recipe" : "Add Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if parsedRecipe != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            parsedRecipe = nil
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
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColors.primaryGreen)

                    Text("Paste a recipe")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Paste a recipe URL, or type / paste the full recipe text and we'll turn it into a structured recipe for you.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.subtleText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 20)

                // Hint chips
                VStack(alignment: .leading, spacing: 6) {
                    Text("Works with:")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                    HStack(spacing: 6) {
                        ForEach(["Recipe URLs", "Copy-paste text", "Free-form notes"], id: \.self) { hint in
                            Text(hint)
                                .font(.caption2)
                                .foregroundStyle(AppColors.primaryGreen)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.primaryGreen.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                // Text input area
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("https://example.com/recipe\n\nor paste recipe text here...\n\ne.g.\nChicken Stir Fry\n2 chicken breasts, sliced\n1 bell pepper, diced\n3 tbsp soy sauce\n\n1. Heat oil in a wok...\n2. Cook chicken until golden...")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.mediumGray)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                        }
                        TextEditor(text: $inputText)
                            .font(.subheadline)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    .frame(minHeight: 220)
                    .background(AppColors.lightGray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if isURL {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption2)
                            Text("URL detected — will fetch and parse")
                                .font(.caption)
                        }
                        .foregroundStyle(AppColors.primaryGreen)
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
                    .foregroundStyle(AppColors.softRed)
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
                    .background(inputText.trimmed.isEmpty || isParsing ? AppColors.mediumGray : AppColors.primaryGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(inputText.trimmed.isEmpty || isParsing)
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Parse Input

    private func parseInput() async {
        isParsing = true
        errorMessage = nil

        let text = inputText.trimmed

        if text.isValidURL {
            if let result = await appState.aiService.parseRecipeFromURL(text) {
                parsedRecipe = result.toRecipe()
            } else {
                errorMessage = "Couldn't parse recipe from that URL. Try pasting the recipe text instead."
            }
        } else {
            if let result = await appState.aiService.parseRecipeFromText(text) {
                parsedRecipe = result.toRecipe()
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
                    .foregroundStyle(AppColors.primaryGreen)

                Text("Import from URL")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Paste a recipe URL and we'll extract the recipe details for you.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.subtleText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                TextField("https://example.com/recipe...", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .padding(.horizontal)

                Button {
                    Task {
                        await viewModel.importFromURL(urlString)
                        if viewModel.importedRecipe != nil {
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
                .tint(AppColors.primaryGreen)
                .padding(.horizontal)
                .disabled(urlString.isEmpty || viewModel.isLoading)

                Spacer()
            }
            .padding(.top, 40)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Flow Layout
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

// MARK: - Recipe Photo Import View
struct RecipePhotoImportView: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: RecipeViewModel
    @State private var capturedImage: UIImage?
    @State private var showImagePicker = false
    @State private var extractedText: String?
    @State private var isExtracting = false
    @State private var isParsing = false
    @State private var errorText: String?

    private let photoScanner = RecipePhotoScannerService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if capturedImage == nil {
                    Spacer()
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 56))
                        .foregroundStyle(AppColors.primaryGreen)

                    Text("Import from Photo")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Take a photo of a recipe from a cookbook, magazine, or recipe card and we'll turn it into a structured recipe.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.subtleText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button("Take Photo or Choose from Library") {
                        showImagePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.primaryGreen)

                    Spacer()
                } else if isExtracting {
                    Spacer()
                    ProgressView("Extracting text from photo...")
                    Spacer()
                } else if isParsing {
                    Spacer()
                    ProgressView("Parsing recipe...")
                    Spacer()
                } else if let errorText {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.warmOrange)
                    Text(errorText)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.subtleText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("Try Again") {
                        capturedImage = nil
                        self.errorText = nil
                        extractedText = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.warmOrange)
                    Spacer()
                }
            }
            .padding(.top, 40)
            .navigationTitle("Photo Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $capturedImage)
            }
            .onChange(of: capturedImage) { _, newImage in
                guard let image = newImage else { return }
                Task { await processPhoto(image: image) }
            }
        }
    }

    private func processPhoto(image: UIImage) async {
        isExtracting = true
        errorText = nil

        guard let text = await photoScanner.extractText(from: image) else {
            isExtracting = false
            errorText = "Could not extract text from the photo. Try a clearer image."
            return
        }
        extractedText = text
        isExtracting = false

        isParsing = true
        await viewModel.importFromPhoto(extractedText: text)
        isParsing = false

        if viewModel.importedRecipe != nil {
            dismiss()
        } else {
            errorText = "Could not parse recipe from the extracted text. Try a different photo."
        }
    }
}
