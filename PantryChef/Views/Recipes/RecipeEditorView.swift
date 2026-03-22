import SwiftUI

// MARK: - Recipe Editor View

/// A full structured editor for a recipe. Used after importing (URL / text / photo)
/// and when editing an existing recipe from RecipeDetailView.
struct RecipeEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var recipe: Recipe
    @State private var showNutrition: Bool
    @State private var isResolving = false
    @State private var resolutionErrorMessage: String?
    @State private var resolutionDraft: RecipeResolutionDraft?
    @State private var pendingSaveAsNew = false
    @FocusState private var focusedField: Field?

    let isNewRecipe: Bool
    let onSave: (Recipe) -> Void
    let onSaveAsNew: ((Recipe) -> Void)?

    private let maxServings = 100

    private enum Field: Hashable {
        case title
        case description
        case ingredientName(UUID)
        case stepInstruction(UUID)
    }

    init(
        recipe: Recipe,
        isNewRecipe: Bool = true,
        onSave: @escaping (Recipe) -> Void,
        onSaveAsNew: ((Recipe) -> Void)? = nil
    ) {
        _recipe = State(initialValue: recipe)
        _showNutrition = State(initialValue: recipe.nutrition != nil)
        self.isNewRecipe = isNewRecipe
        self.onSave = onSave
        self.onSaveAsNew = onSaveAsNew
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleSection
                detailsSection
                classificationSection
                ingredientsSection
                stepsSection
                nutritionSection
                saveSection
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.background)
        .sheet(item: $resolutionDraft) { draft in
            NavigationStack {
                IngredientResolutionReviewView(draft: draft) { resolvedRecipe in
                    resolutionDraft = nil
                    completeSave(with: resolvedRecipe)
                } onCancel: {
                    resolutionDraft = nil
                }
            }
        }
    }

    // MARK: - Title & Description

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Title & Description")

            TextField("Recipe title", text: $recipe.title)
                .font(.title3)
                .fontWeight(.semibold)
                .focused($focusedField, equals: .title)
                .padding(12)
                .background(AppColors.lightGray)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            ZStack(alignment: .topLeading) {
                if recipe.description?.isEmpty ?? true {
                    Text("Add a description (optional)")
                        .foregroundStyle(AppColors.mediumGray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }
                TextEditor(text: descriptionBinding)
                    .focused($focusedField, equals: .description)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            .frame(minHeight: 80)
            .background(AppColors.lightGray)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding()
        .cardStyle()
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { recipe.description ?? "" },
            set: { recipe.description = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Details")

            // Servings
            HStack {
                Label("Servings", systemImage: "person.2")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.darkText)
                Spacer()
                HStack(spacing: 14) {
                    Button {
                        if recipe.servings > 1 { recipe.servings -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(recipe.servings > 1 ? AppColors.primaryGreen : AppColors.mediumGray)
                    }
                    .disabled(recipe.servings <= 1)

                    Text("\(recipe.servings)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(width: 30)

                    Button {
                        if recipe.servings < maxServings { recipe.servings += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(recipe.servings < maxServings ? AppColors.primaryGreen : AppColors.mediumGray)
                    }
                    .disabled(recipe.servings >= maxServings)
                }
            }

            Divider()

            // Prep time
            timeRow(label: "Prep Time", icon: "hand.raised", binding: optionalIntBinding(\.prepTimeMinutes))

            Divider()

            // Cook time
            timeRow(label: "Cook Time", icon: "flame", binding: optionalIntBinding(\.cookTimeMinutes))

            Divider()

            // Difficulty
            HStack {
                Label("Difficulty", systemImage: "chart.bar")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.darkText)
                Spacer()
                Picker("", selection: $recipe.difficulty) {
                    ForEach(DifficultyLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppColors.primaryGreen)
            }
        }
        .padding()
        .cardStyle()
    }

    private func timeRow(label: String, icon: String, binding: Binding<String>) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(AppColors.darkText)
            Spacer()
            TextField("—", text: binding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(AppColors.lightGray)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("min")
                .font(.caption)
                .foregroundStyle(AppColors.subtleText)
        }
    }

    private func optionalIntBinding(_ keyPath: WritableKeyPath<Recipe, Int?>) -> Binding<String> {
        Binding(
            get: { recipe[keyPath: keyPath].map { "\($0)" } ?? "" },
            set: { recipe[keyPath: keyPath] = Int($0) }
        )
    }

    // MARK: - Classification

    private var classificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Classification")

            HStack {
                Label("Meal Type", systemImage: "fork.knife")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.darkText)
                Spacer()
                Picker("", selection: $recipe.mealType) {
                    Text("None").tag(nil as MealType?)
                    ForEach(MealType.allCases) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type as MealType?)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppColors.primaryGreen)
            }

            Divider()

            HStack {
                Label("Cuisine", systemImage: "globe")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.darkText)
                Spacer()
                Picker("", selection: $recipe.cuisine) {
                    Text("None").tag(nil as CuisineType?)
                    ForEach(CuisineType.allCases) { type in
                        Text("\(type.icon) \(type.rawValue)").tag(type as CuisineType?)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppColors.primaryGreen)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Dietary Tags")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.darkText)

                FlowLayout(spacing: 8) {
                    ForEach(DietaryTag.allCases) { tag in
                        Button {
                            if recipe.dietaryTags.contains(tag) {
                                recipe.dietaryTags.removeAll { $0 == tag }
                            } else {
                                recipe.dietaryTags.append(tag)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: tag.icon)
                                    .font(.caption2)
                                Text(tag.rawValue)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(recipe.dietaryTags.contains(tag) ? AppColors.primaryGreen.opacity(0.2) : AppColors.lightGray)
                            .foregroundStyle(recipe.dietaryTags.contains(tag) ? AppColors.primaryGreen : AppColors.subtleText)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Ingredients",
                subtitle: "\(recipe.ingredients.count) items",
                actionTitle: "+ Add"
            ) {
                withAnimation {
                    recipe.ingredients.append(Ingredient(name: ""))
                }
            }

            ForEach($recipe.ingredients) { $ingredient in
                ingredientRow(ingredient: $ingredient)
            }

            if recipe.ingredients.isEmpty {
                Text("No ingredients yet. Tap + Add above.")
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .cardStyle()
    }

    private func ingredientRow(ingredient: Binding<Ingredient>) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Quantity
                TextField("Qty", value: ingredient.quantity, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .frame(width: 55)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .background(AppColors.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Unit picker
                Picker("", selection: ingredient.unit) {
                    Text("—").tag(nil as MeasurementUnit?)
                    ForEach(MeasurementUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit as MeasurementUnit?)
                    }
                }
                .pickerStyle(.menu)
                .tint(AppColors.darkText)

                // Name
                TextField("Ingredient name", text: ingredient.name)
                    .font(.subheadline)
                    .focused($focusedField, equals: .ingredientName(ingredient.id))

                // Delete
                Button {
                    withAnimation {
                        recipe.ingredients.removeAll { $0.id == ingredient.id }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.softRed.opacity(0.7))
                }
            }

            HStack(spacing: 12) {
                // Category
                HStack(spacing: 4) {
                    Image(systemName: ingredient.wrappedValue.category.icon)
                        .font(.caption2)
                        .foregroundStyle(ingredient.wrappedValue.category.color)
                    Picker("", selection: ingredient.category) {
                        ForEach(FoodCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(ingredient.wrappedValue.category.color)
                }
                .font(.caption)

                Spacer()

                // Optional toggle
                Toggle(isOn: ingredient.isOptional) {
                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .background(AppColors.lightGray)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Steps",
                subtitle: "\(recipe.steps.count) steps",
                actionTitle: "+ Add"
            ) {
                withAnimation {
                    recipe.steps.append(RecipeStep(
                        stepNumber: recipe.steps.count + 1,
                        instruction: ""
                    ))
                }
            }

            ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, _ in
                stepRow(index: index)
            }

            if recipe.steps.isEmpty {
                Text("No steps yet. Tap + Add above.")
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .cardStyle()
    }

    private func stepRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // Step number badge
                Text("\(index + 1)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(AppColors.primaryGreen)
                    .clipShape(Circle())

                // Instruction
                if index < recipe.steps.count {
                    TextField("Step instruction", text: $recipe.steps[index].instruction, axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(2...8)
                        .focused($focusedField, equals: .stepInstruction(recipe.steps[index].id))
                }

                // Action buttons column
                VStack(spacing: 6) {
                    Button {
                        guard index > 0 else { return }
                        withAnimation {
                            recipe.steps.swapAt(index, index - 1)
                            renumberSteps()
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                            .foregroundStyle(index > 0 ? AppColors.subtleText : AppColors.mediumGray.opacity(0.4))
                    }
                    .disabled(index == 0)

                    Button {
                        guard index < recipe.steps.count - 1 else { return }
                        withAnimation {
                            recipe.steps.swapAt(index, index + 1)
                            renumberSteps()
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.caption2)
                            .foregroundStyle(index < recipe.steps.count - 1 ? AppColors.subtleText : AppColors.mediumGray.opacity(0.4))
                    }
                    .disabled(index >= recipe.steps.count - 1)

                    Button {
                        withAnimation {
                            recipe.steps.remove(at: index)
                            renumberSteps()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppColors.softRed.opacity(0.7))
                    }
                }
            }

            // Timer row
            if index < recipe.steps.count {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundStyle(AppColors.warmOrange)
                    Text("Timer:")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                    TextField("—", text: optionalStepIntBinding(index: index, keyPath: \.timerMinutes))
                        .keyboardType(.numberPad)
                        .frame(width: 40)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(AppColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("min")
                        .font(.caption2)
                        .foregroundStyle(AppColors.subtleText)
                }
            }
        }
        .padding(10)
        .background(AppColors.lightGray)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func optionalStepIntBinding(index: Int, keyPath: WritableKeyPath<RecipeStep, Int?>) -> Binding<String> {
        Binding(
            get: {
                guard index < recipe.steps.count else { return "" }
                return recipe.steps[index][keyPath: keyPath].map { "\($0)" } ?? ""
            },
            set: {
                guard index < recipe.steps.count else { return }
                recipe.steps[index][keyPath: keyPath] = Int($0)
            }
        )
    }

    private func renumberSteps() {
        for i in recipe.steps.indices {
            recipe.steps[i].stepNumber = i + 1
        }
    }

    // MARK: - Nutrition

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    showNutrition.toggle()
                    if showNutrition && recipe.nutrition == nil {
                        recipe.nutrition = NutritionInfo(calories: 0, protein: 0, carbohydrates: 0, fat: 0)
                    }
                }
            } label: {
                HStack {
                    Text("Nutrition")
                        .font(.headline)
                        .foregroundStyle(AppColors.darkText)
                    Text("Per serving")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                    Spacer()
                    Image(systemName: showNutrition ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }
            }

            if showNutrition, recipe.nutrition != nil {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    nutritionField("Calories", unit: "kcal", binding: nutritionIntBinding(\.calories))
                    nutritionField("Protein", unit: "g", binding: nutritionDoubleBinding(\.protein))
                    nutritionField("Carbs", unit: "g", binding: nutritionDoubleBinding(\.carbohydrates))
                    nutritionField("Fat", unit: "g", binding: nutritionDoubleBinding(\.fat))
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    nutritionOptField("Fiber", unit: "g", binding: nutritionOptDoubleBinding(\.fiber))
                    nutritionOptField("Sugar", unit: "g", binding: nutritionOptDoubleBinding(\.sugar))
                    nutritionOptField("Sodium", unit: "mg", binding: nutritionOptDoubleBinding(\.sodium))
                }

                Button(role: .destructive) {
                    withAnimation {
                        recipe.nutrition = nil
                        showNutrition = false
                    }
                } label: {
                    Text("Remove Nutrition Info")
                        .font(.caption)
                        .foregroundStyle(AppColors.softRed)
                }
            }
        }
        .padding()
        .cardStyle()
    }

    private func nutritionField(_ label: String, unit: String, binding: Binding<String>) -> some View {
        VStack(spacing: 4) {
            TextField("0", text: binding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .padding(6)
                .background(AppColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("\(label) (\(unit))")
                .font(.caption2)
                .foregroundStyle(AppColors.subtleText)
        }
    }

    private func nutritionOptField(_ label: String, unit: String, binding: Binding<String>) -> some View {
        VStack(spacing: 4) {
            TextField("—", text: binding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .padding(6)
                .background(AppColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("\(label) (\(unit))")
                .font(.caption2)
                .foregroundStyle(AppColors.subtleText)
        }
    }

    private func nutritionIntBinding(_ keyPath: WritableKeyPath<NutritionInfo, Int>) -> Binding<String> {
        Binding(
            get: {
                guard let val = recipe.nutrition?[keyPath: keyPath], val != 0 else { return "" }
                return "\(val)"
            },
            set: { recipe.nutrition?[keyPath: keyPath] = Int($0) ?? 0 }
        )
    }

    private func nutritionDoubleBinding(_ keyPath: WritableKeyPath<NutritionInfo, Double>) -> Binding<String> {
        Binding(
            get: {
                guard let val = recipe.nutrition?[keyPath: keyPath], val != 0 else { return "" }
                return String(format: "%.0f", val)
            },
            set: { recipe.nutrition?[keyPath: keyPath] = Double($0) ?? 0 }
        )
    }

    private func nutritionOptDoubleBinding(_ keyPath: WritableKeyPath<NutritionInfo, Double?>) -> Binding<String> {
        Binding(
            get: {
                guard let val = recipe.nutrition?[keyPath: keyPath] else { return "" }
                return String(format: "%.0f", val)
            },
            set: {
                if let num = Double($0) {
                    recipe.nutrition?[keyPath: keyPath] = num
                } else {
                    recipe.nutrition?[keyPath: keyPath] = nil
                }
            }
        )
    }

    // MARK: - Save Section

    private var saveSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await handleSave() }
            } label: {
                Group {
                    if isResolving {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Resolving Ingredients")
                        }
                    } else {
                        Text(isNewRecipe ? "Save Recipe" : "Save Changes")
                    }
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(canSave && !isResolving ? AppColors.primaryGreen : AppColors.mediumGray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSave || isResolving)

            if let resolutionErrorMessage {
                Text(resolutionErrorMessage)
                    .font(.caption)
                    .foregroundStyle(AppColors.softRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !isNewRecipe, let onSaveAsNew {
                Button {
                    Task {
                        await handleSave(saveAsNew: onSaveAsNew)
                    }
                } label: {
                    Text("Save as New Recipe")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(AppColors.primaryGreen)
                        .background(AppColors.primaryGreen.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSave || isResolving)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    /// Clean up the recipe before saving — remove empty ingredients/steps, renumber.
    private func finalizeSave() {
        recipe.ingredients.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        recipe.steps.removeAll { $0.instruction.trimmingCharacters(in: .whitespaces).isEmpty }
        renumberSteps()
        // Clean nutrition if all zeros
        if let n = recipe.nutrition, n.calories == 0 && n.protein == 0 && n.carbohydrates == 0 && n.fat == 0 {
            recipe.nutrition = nil
        }
    }

    private var canSave: Bool {
        let hasTitle = !recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasIngredients = recipe.ingredients.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let hasSteps = recipe.steps.contains { !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasTitle && hasIngredients && hasSteps
    }

    private func handleSave(saveAsNew: ((Recipe) -> Void)? = nil) async {
        resolutionErrorMessage = nil
        finalizeSave()
        pendingSaveAsNew = saveAsNew != nil

        isResolving = true
        let draft = await appState.recipeIngredientResolver.resolve(recipe: recipe)
        isResolving = false

        if draft.isReadyToBuild {
            if draft.requiresIngredientEdits {
                let unresolvedNames = draft.unknownIngredients
                    .map { $0.ingredient.rawName }
                    .joined(separator: ", ")
                resolutionErrorMessage = "Edit unresolved ingredients before saving: \(unresolvedNames)."
            } else {
                completeSave(with: draft.builtRecipe())
            }
            return
        }

        if draft.requiresIngredientEdits {
            let unresolvedNames = draft.unknownIngredients
                .map { $0.ingredient.rawName }
                .joined(separator: ", ")
            resolutionErrorMessage = "Edit unresolved ingredients before saving: \(unresolvedNames)."
            return
        }

        resolutionDraft = draft
    }

    private func completeSave(with resolvedRecipe: Recipe) {
        var recipeToSave = resolvedRecipe

        if pendingSaveAsNew, let onSaveAsNew {
            recipeToSave.id = UUID()
            recipeToSave.dateAdded = Date()
            recipeToSave.timesCooked = 0
            recipeToSave.source = .user
            recipeToSave.isFavorite = false
            onSaveAsNew(recipeToSave)
        } else {
            onSave(recipeToSave)
        }

        pendingSaveAsNew = false
    }
}

private struct IngredientResolutionReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecipeResolutionDraft

    let onConfirm: (Recipe) -> Void
    let onCancel: () -> Void

    init(
        draft: RecipeResolutionDraft,
        onConfirm: @escaping (Recipe) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    private var canConfirm: Bool {
        draft.ambiguousIngredients.allSatisfy { $0.selectedCandidateID != nil }
    }

    var body: some View {
        List {
            Section {
                Text("Choose a registry match for each ambiguous ingredient before saving this recipe.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.subtleText)
            }

            ForEach(draft.ingredients.indices, id: \.self) { index in
                let ingredientDraft = draft.ingredients[index]
                if ingredientDraft.requiresUserChoice {
                    Section(ingredientDraft.ingredient.displayText) {
                        ForEach(ingredientDraft.candidates) { candidate in
                            Button {
                                draft.ingredients[index].chooseCandidate(candidate)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: draft.ingredients[index].selectedCandidateID == candidate.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(draft.ingredients[index].selectedCandidateID == candidate.id ? AppColors.primaryGreen : AppColors.mediumGray)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(candidate.displayName)
                                            .font(.subheadline)
                                            .foregroundStyle(AppColors.darkText)

                                        Text(candidate.rationale)
                                            .font(.caption)
                                            .foregroundStyle(AppColors.subtleText)
                                    }

                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !draft.unknownIngredients.isEmpty {
                Section("Unknown Ingredients") {
                    ForEach(draft.unknownIngredients) { ingredientDraft in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ingredientDraft.ingredient.displayText)
                                .font(.subheadline)
                            Text("This ingredient will stay unresolved and keep its original text.")
                                .font(.caption)
                                .foregroundStyle(AppColors.subtleText)
                        }
                    }
                }
            }
        }
        .navigationTitle("Resolve Ingredients")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    onCancel()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    let recipe = draft.builtRecipe()
                    onConfirm(recipe)
                    dismiss()
                }
                .disabled(!canConfirm)
            }
        }
    }
}
