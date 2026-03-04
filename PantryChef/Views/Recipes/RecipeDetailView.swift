import SwiftUI

struct RecipeDetailView: View {
    @EnvironmentObject var appState: AppState
    @State private var recipe: Recipe
    @State private var servings: Int
    @State private var showCookMode = false
    @State private var showSubstitutions = false
    @State private var showHealthier = false
    @State private var showShoppingList = false
    @State private var substitutions: [SubstitutionSuggestion] = []
    @State private var healthierSuggestion: HealthierSuggestion?
    @State private var shoppingList: [ShoppingItem] = []
    @State private var isLoadingAI = false

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
                // Hero Image
                heroImage

                VStack(alignment: .leading, spacing: 20) {
                    // Title & Meta
                    titleSection

                    // Pantry Match Bar
                    pantryMatchSection

                    // Action Buttons
                    actionButtons

                    // Servings Adjuster
                    servingsAdjuster

                    // Nutrition
                    if let nutrition = scaledRecipe.nutrition {
                        nutritionSection(nutrition)
                    }

                    // Ingredients
                    ingredientsSection

                    // Steps
                    stepsSection

                    // Dietary Tags
                    if !recipe.dietaryTags.isEmpty {
                        dietaryTagsSection
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(AppColors.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button {
                        recipe.isFavorite.toggle()
                    } label: {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(recipe.isFavorite ? .red : AppColors.mediumGray)
                    }

                    Button {
                        showCookMode = true
                    } label: {
                        Label("Cook", systemImage: "play.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.primaryGreen)
                }
            }
        }
        .fullScreenCover(isPresented: $showCookMode) {
            CookModeView(recipe: scaledRecipe)
        }
        .sheet(isPresented: $showSubstitutions) {
            SubstitutionsView(substitutions: substitutions)
        }
        .sheet(isPresented: $showHealthier) {
            if let suggestion = healthierSuggestion {
                HealthierView(suggestion: suggestion)
            }
        }
        .sheet(isPresented: $showShoppingList) {
            ShoppingPreviewView(items: shoppingList)
        }
    }

    // MARK: - Hero Image
    private var heroImage: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [AppColors.primaryGreen.opacity(0.2), AppColors.primaryGreen.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 220)

            Image(systemName: recipe.mealType?.icon ?? "fork.knife")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.primaryGreen.opacity(0.4))
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

            if !pantryMatch.missingIngredients.isEmpty {
                Text("Missing: \(pantryMatch.missingIngredients.map { $0.name }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 12) {
            ActionButton(icon: "cart", title: "What to Buy", color: AppColors.warmOrange) {
                Task {
                    isLoadingAI = true
                    shoppingList = await appState.getShoppingList(for: recipe)
                    isLoadingAI = false
                    showShoppingList = true
                }
            }

            ActionButton(icon: "arrow.triangle.2.circlepath", title: "Substitutes", color: .purple) {
                Task {
                    isLoadingAI = true
                    substitutions = await appState.getSubstitutions(for: recipe)
                    isLoadingAI = false
                    showSubstitutions = true
                }
            }

            ActionButton(icon: "heart.circle", title: "Healthier", color: AppColors.primaryGreen) {
                Task {
                    isLoadingAI = true
                    healthierSuggestion = await appState.getHealthierVersion(of: recipe)
                    isLoadingAI = false
                    showHealthier = true
                }
            }
        }
        .overlay {
            if isLoadingAI {
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
                NutritionCircle(label: "Fat", value: Int(nutrition.fat), unit: "g", color: .blue)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Ingredients Section
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ingredients", subtitle: "\(scaledRecipe.ingredients.count) items")

            ForEach(scaledRecipe.ingredients) { ingredient in
                HStack(spacing: 12) {
                    let isAvailable = appState.pantryItems.contains {
                        $0.name.lowercased().contains(ingredient.name.lowercased())
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
                        // Add to app state shopping list
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
    @State private var title = ""
    @State private var description = ""
    @State private var servings = 4
    @State private var prepTime = ""
    @State private var cookTime = ""
    @State private var difficulty: DifficultyLevel = .easy
    @State private var mealType: MealType = .dinner
    @State private var ingredients: [Ingredient] = []
    @State private var steps: [RecipeStep] = []
    @State private var dietaryTags: Set<DietaryTag> = []

    // Ingredient entry
    @State private var newIngredientName = ""
    @State private var newIngredientQty = ""
    @State private var newIngredientUnit: MeasurementUnit = .piece

    // Step entry
    @State private var newStepText = ""

    let onSave: (Recipe) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Recipe Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3)

                    Stepper("Servings: \(servings)", value: $servings, in: 1...20)

                    HStack {
                        TextField("Prep (min)", text: $prepTime)
                            .keyboardType(.numberPad)
                        TextField("Cook (min)", text: $cookTime)
                            .keyboardType(.numberPad)
                    }

                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(DifficultyLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }

                    Picker("Meal Type", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                }

                Section("Ingredients (\(ingredients.count))") {
                    ForEach(ingredients) { ingredient in
                        Text(ingredient.displayText)
                    }
                    .onDelete { indexSet in
                        ingredients.remove(atOffsets: indexSet)
                    }

                    HStack {
                        TextField("Name", text: $newIngredientName)
                        TextField("Qty", text: $newIngredientQty)
                            .keyboardType(.decimalPad)
                            .frame(width: 50)
                        Picker("", selection: $newIngredientUnit) {
                            ForEach(MeasurementUnit.allCases) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .frame(width: 80)

                        Button {
                            let qty = Double(newIngredientQty) ?? 1
                            ingredients.append(Ingredient(
                                name: newIngredientName,
                                quantity: qty,
                                unit: newIngredientUnit
                            ))
                            newIngredientName = ""
                            newIngredientQty = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(AppColors.primaryGreen)
                        }
                        .disabled(newIngredientName.isEmpty)
                    }
                }

                Section("Steps (\(steps.count))") {
                    ForEach(steps) { step in
                        HStack(alignment: .top) {
                            Text("\(step.stepNumber).")
                                .fontWeight(.bold)
                            Text(step.instruction)
                        }
                    }
                    .onDelete { indexSet in
                        steps.remove(atOffsets: indexSet)
                    }

                    HStack {
                        TextField("Add step...", text: $newStepText, axis: .vertical)
                        Button {
                            steps.append(RecipeStep(
                                stepNumber: steps.count + 1,
                                instruction: newStepText
                            ))
                            newStepText = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(AppColors.primaryGreen)
                        }
                        .disabled(newStepText.isEmpty)
                    }
                }

                Section("Dietary Tags") {
                    FlowLayout(spacing: 8) {
                        ForEach(DietaryTag.allCases) { tag in
                            Button {
                                if dietaryTags.contains(tag) {
                                    dietaryTags.remove(tag)
                                } else {
                                    dietaryTags.insert(tag)
                                }
                            } label: {
                                DietaryTagChip(tag: tag, isSelected: dietaryTags.contains(tag))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let recipe = Recipe(
                            title: title,
                            description: description.isEmpty ? nil : description,
                            ingredients: ingredients,
                            steps: steps,
                            servings: servings,
                            prepTimeMinutes: Int(prepTime),
                            cookTimeMinutes: Int(cookTime),
                            difficulty: difficulty,
                            dietaryTags: Array(dietaryTags),
                            mealType: mealType
                        )
                        onSave(recipe)
                        dismiss()
                    }
                    .disabled(title.isEmpty || ingredients.isEmpty || steps.isEmpty)
                }
            }
        }
    }
}

// MARK: - Import Recipe URL View
struct ImportRecipeURLView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: RecipeViewModel
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

                Text("Paste a recipe URL and we'll extract the recipe details using AI.")
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
