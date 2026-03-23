import SwiftUI

struct PreparedDishesView: View {
    @State private var viewModel: PreparedDishViewModel
    @FocusState private var isSearchFocused: Bool
    private let isEmbedded: Bool

    init(appState: AppState, isEmbedded: Bool = false) {
        _viewModel = State(initialValue: PreparedDishViewModel(appState: appState))
        self.isEmbedded = isEmbedded
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        let content = VStack(spacing: 0) {
            if isEmbedded {
                embeddedHeader
            }

            searchAndFilters

            if viewModel.filteredDishes.isEmpty {
                EmptyStateView(
                    icon: "takeoutbag.and.cup.and.straw",
                    title: "No prepared dishes",
                    message: "Track leftovers, takeout, and ready-to-eat meals.",
                    actionTitle: "Add Prepared Dish"
                ) {
                    viewModel.showAddDish = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AppList {
                    ForEach(viewModel.filteredDishes) { dish in
                        HStack(spacing: 12) {
                            Button {
                                viewModel.selectedDish = dish
                            } label: {
                                PreparedDishRow(dish: dish)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                viewModel.consumeServing(dish)
                            } label: {
                                quickAdjustButton(for: dish)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(dish.servingsRemaining == 1 ? "Finish prepared dish" : "Use one serving")
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.deleteDish(dish)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                viewModel.editingDish = dish
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(AppColors.accentBlue)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                Task {
                                    _ = await viewModel.appState.adjustPreparedDishServings(dish, delta: 1)
                                }
                            } label: {
                                Label("Add Serving", systemImage: "plus")
                            }
                            .tint(AppColors.primaryGreen)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .overlay(alignment: .top) {
            if let feedback = viewModel.feedbackBanner {
                Text(feedback.message)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.darkText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppColors.cardBackground)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
                    .padding(.top, isEmbedded ? 8 : 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.feedbackBanner)
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showAddDish = true
                    } label: {
                        Label("Add Prepared Dish", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showAddDish) {
            PreparedDishEditorView(appState: viewModel.appState) { dish in
                viewModel.addDish(dish)
            }
        }
        .sheet(item: $viewModel.editingDish) { dish in
            PreparedDishEditorView(appState: viewModel.appState, dish: dish) { updatedDish in
                viewModel.updateDish(updatedDish)
            }
        }
        .appNavigationSheet(item: $viewModel.selectedDish) { dish in
            PreparedDishDetailView(dish: dish)
                .environment(viewModel.appState)
        }

        if isEmbedded {
            content
        } else {
            content
                .navigationTitle("Prepared Dishes")
        }
    }

    private var embeddedHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Track leftovers, takeout, and ready-to-eat meals.")
                .font(.caption)
                .foregroundStyle(AppColors.subtleText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button {
                viewModel.showAddDish = true
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.primaryGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.primaryGreen.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(AppColors.cardBackground)
    }

    private var searchAndFilters: some View {
        @Bindable var viewModel = viewModel

        return VStack(spacing: 8) {
            AppSearchField(
                "Search prepared dishes...",
                text: $viewModel.searchText,
                focus: $isSearchFocused,
                onTextChange: { _ in
                    viewModel.onSearchTextChanged()
                }
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryPill(title: "All", isSelected: viewModel.selectedMealType == nil) {
                        viewModel.selectedMealType = nil
                    }

                    ForEach(MealType.allCases) { mealType in
                        if let count = viewModel.mealTypeCounts[mealType], count > 0 {
                            CategoryPill(
                                title: "\(mealType.rawValue) (\(count))",
                                isSelected: viewModel.selectedMealType == mealType
                            ) {
                                viewModel.selectedMealType = viewModel.selectedMealType == mealType ? nil : mealType
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(AppColors.cardBackground)
    }

    @ViewBuilder
    private func quickAdjustButton(for dish: PreparedDish) -> some View {
        VStack(spacing: 4) {
            Image(systemName: dish.servingsRemaining == 1 ? "checkmark.circle.fill" : "minus.circle.fill")
                .font(.headline)
            Text(dish.servingsRemaining == 1 ? "Finish" : "Use 1")
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .frame(width: 64)
        .padding(.vertical, 10)
        .background((dish.servingsRemaining == 1 ? AppColors.softRed : AppColors.warmOrange).opacity(0.14))
        .foregroundStyle(dish.servingsRemaining == 1 ? AppColors.softRed : AppColors.warmOrange)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PreparedDishRow: View {
    let dish: PreparedDish

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "takeoutbag.and.cup.and.straw")
                .font(.title3)
                .foregroundStyle(AppColors.warmOrange)
                .frame(width: 36, height: 36)
                .background(AppColors.warmOrange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(dish.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.darkText)

                Text("\(dish.servingsDisplay) • \(dish.mealTypesSummary)")
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)

                Label(dish.storage.rawValue, systemImage: dish.storage.icon)
                    .font(.caption2)
                    .foregroundStyle(AppColors.subtleText)
            }

            Spacer()

            if dish.useByDate != nil {
                ExpiryBadge(status: dish.expiryStatus, daysLeft: dish.daysUntilUseBy)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PreparedDishDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let dish: PreparedDish

    @State private var editingDish: PreparedDish?

    private var currentDish: PreparedDish {
        appState.preparedDishById(dish.id) ?? dish
    }

    private var linkedRecipe: Recipe? {
        guard let recipeID = currentDish.recipeID else { return nil }
        return appState.allRecipes.first { $0.id == recipeID }
    }

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                AppDetailCard("Planning") {
                    AppDetailRowGroup {
                        AppDetailRow("Meal types", value: currentDish.mealTypesSummary)
                        AppDetailRow("Servings remaining", value: currentDish.servingsDisplay)
                        AppDetailRow("Storage", value: currentDish.storage.rawValue)
                    }
                }

                AppDetailCard("Adjust Servings") {
                    Text("Quickly update this dish as you eat through it.")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                let removed = await appState.adjustPreparedDishServings(currentDish, delta: -1)
                                if removed {
                                    dismiss()
                                }
                            }
                        } label: {
                            quickActionLabel(
                                title: currentDish.servingsRemaining == 1 ? "Finish Dish" : "Use 1 Serving",
                                systemImage: currentDish.servingsRemaining == 1 ? "checkmark.circle.fill" : "minus.circle.fill",
                                color: currentDish.servingsRemaining == 1 ? AppColors.softRed : AppColors.warmOrange
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task {
                                _ = await appState.adjustPreparedDishServings(currentDish, delta: 1)
                            }
                        } label: {
                            quickActionLabel(title: "Add 1 Serving", systemImage: "plus.circle.fill", color: AppColors.primaryGreen)
                        }
                        .buttonStyle(.plain)
                    }
                }

                AppDetailCard("Freshness") {
                    AppDetailRowGroup {
                        AppDetailRow("Use by", value: useByText)
                    }
                }

                if let linkedRecipe {
                    AppDetailCard("Linked Recipe") {
                        NavigationLink(destination: RecipeDetailView(recipe: linkedRecipe).environment(appState)) {
                            HStack {
                                Text(linkedRecipe.title)
                                    .foregroundStyle(AppColors.darkText)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(AppColors.mediumGray)
                            }
                        }
                    }

                    AppIngredientDetailGroup("Ingredients", subtitle: "From linked recipe") {
                        ForEach(linkedRecipe.ingredients) { ingredient in
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

                if let nutrition = currentDish.nutrition {
                    AppDetailCard("Nutrition") {
                        AppDetailRowGroup {
                            AppDetailRow("Calories", value: "\(nutrition.calories)")
                            AppDetailRow("Macros", value: nutrition.macroSummary)
                        }
                    }
                }

                if let notes = currentDish.notes, !notes.isEmpty {
                    AppDetailCard("Notes") {
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(AppColors.darkText)
                    }
                }
            }
            .padding()
        }
        .background(AppColors.background)
        .navigationTitle(currentDish.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    editingDish = currentDish
                }
            }
        }
        .sheet(item: $editingDish) { dish in
            PreparedDishEditorView(appState: appState, dish: dish) { updatedDish in
                Task {
                    await appState.updatePreparedDish(updatedDish)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(currentDish.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(AppColors.darkText)

            HStack(spacing: 10) {
                pill(text: currentDish.servingsDisplay, color: AppColors.warmOrange)
                pill(text: currentDish.storage.rawValue, color: AppColors.accentBlue)
                if currentDish.expiryStatus != .fresh {
                    pill(text: currentDish.expiryStatus == .expired ? "Expired" : "Use soon", color: AppColors.softRed)
                }
            }
        }
    }

    private var useByText: String {
        guard let useByDate = currentDish.useByDate else { return "Not set" }
        return useByDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func pill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func quickActionLabel(title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.14))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PreparedDishEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState
    let onSave: (PreparedDish) -> Void

    private let existingDish: PreparedDish?

    @State private var draft: PreparedDishDraft
    @State private var showRecipePicker = false

    init(appState: AppState, dish: PreparedDish? = nil, seedRecipe: Recipe? = nil, onSave: @escaping (PreparedDish) -> Void) {
        self.appState = appState
        self.existingDish = dish
        self.onSave = onSave
        var initialDraft = PreparedDishDraft(dish: dish)
        if dish == nil, let seedRecipe {
            initialDraft.recipeID = seedRecipe.id
            initialDraft.syncLinkedRecipe(seedRecipe)
        }
        _draft = State(initialValue: initialDraft)
    }

    private var linkedRecipe: Recipe? {
        guard let recipeID = draft.recipeID else { return nil }
        return appState.allRecipes.first { $0.id == recipeID }
    }

    private var useByDateBinding: Binding<Date> {
        Binding(
            get: { draft.useByDateWasEdited ? draft.manualUseByDate : draft.estimatedUseByDate },
            set: { draft.updateUseByDate($0) }
        )
    }

    var body: some View {
        AppNavigationSheet {
            AppScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    basicSection
                    freshnessSection
                    recipeSection
                    nutritionSection
                    notesSection
                }
                .padding()
            }
            .background(AppColors.background)
            .navigationTitle(existingDish == nil ? "Add Prepared Dish" : "Edit Prepared Dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let dish = draft.buildDish(using: linkedRecipe) else { return }
                        onSave(dish)
                        dismiss()
                    }
                    .disabled(!draft.isValid(using: linkedRecipe))
                }
            }
            .sheet(isPresented: $showRecipePicker) {
                MealPickerView(
                    recipes: appState.allRecipes,
                    preparedDishes: [],
                    onSelectRecipe: { recipe in
                        draft.recipeID = recipe.id
                        draft.syncLinkedRecipe(recipe)
                    },
                    onSelectPreparedDish: { _ in }
                )
            }
        }
    }

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Basics")
                .font(.headline)
                .foregroundStyle(AppColors.darkText)

            TextField("Dish name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Meal types")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.subtleText)

                FlexibleMealTypeChips(selectedMealTypes: $draft.mealTypes)
            }

            Stepper(value: $draft.servingsRemaining, in: 1...24) {
                Text("Servings remaining: \(draft.servingsRemaining)")
                    .foregroundStyle(AppColors.darkText)
            }

            Picker("Storage", selection: $draft.storage) {
                ForEach(PantryStorage.allCases) { storage in
                    Text(storage.rawValue).tag(storage)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .cardStyle()
    }

    private var freshnessSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Freshness")
                .font(.headline)
                .foregroundStyle(AppColors.darkText)

            DatePicker("Use by date", selection: useByDateBinding, displayedComponents: .date)

            Text(
                draft.useByDateWasEdited
                    ? "Use-by date set manually."
                    : "Prepopulated from estimated freshness for \(draft.storage.rawValue.lowercased()) storage. Edit it if needed."
            )
            .font(.subheadline)
            .foregroundStyle(AppColors.subtleText)
        }
        .padding()
        .cardStyle()
    }

    private var recipeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recipe Link")
                .font(.headline)
                .foregroundStyle(AppColors.darkText)

            Button {
                showRecipePicker = true
            } label: {
                HStack {
                    Text(linkedRecipe?.title ?? "Select recipe")
                        .foregroundStyle(AppColors.darkText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppColors.mediumGray)
                }
            }

            if linkedRecipe != nil {
                Text("Changing the linked recipe updates the name, meal type, servings, and nutrition to match it.")
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
            }

            if draft.recipeID != nil {
                Button("Remove recipe link") {
                    draft.recipeID = nil
                }
                .font(.caption)
                .foregroundStyle(AppColors.softRed)
            }
        }
        .padding()
        .cardStyle()
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrition")
                .font(.headline)
                .foregroundStyle(AppColors.darkText)

            Text("Leave blank unless you want to track calories and macros for this prepared dish.")
                .font(.caption)
                .foregroundStyle(AppColors.subtleText)

            TextField("Calories", text: $draft.caloriesText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                TextField("Protein", text: $draft.proteinText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                TextField("Carbs", text: $draft.carbsText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                TextField("Fat", text: $draft.fatText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }

            if draft.nutritionIsInvalid {
                Text("Enter all four nutrition fields with valid numbers, or leave them all blank.")
                    .font(.caption)
                    .foregroundStyle(AppColors.softRed)
            }
        }
        .padding()
        .cardStyle()
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.headline)
                .foregroundStyle(AppColors.darkText)

            TextEditor(text: $draft.notes)
                .frame(minHeight: 120)
                .padding(8)
                .background(AppColors.lightGray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .cardStyle()
    }
}

private struct FlexibleMealTypeChips: View {
    @Binding var selectedMealTypes: Set<MealType>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(MealType.allCases) { mealType in
                Button {
                    if selectedMealTypes.contains(mealType) {
                        selectedMealTypes.remove(mealType)
                    } else {
                        selectedMealTypes.insert(mealType)
                    }
                } label: {
                    Text(mealType.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(selectedMealTypes.contains(mealType) ? AppColors.primaryGreen : AppColors.lightGray)
                        .foregroundStyle(selectedMealTypes.contains(mealType) ? Color.white : AppColors.subtleText)
                        .clipShape(Capsule())
                }
            }
        }
    }
}