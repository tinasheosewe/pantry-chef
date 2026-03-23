import SwiftUI

struct PreparedDishesView: View {
    @State private var viewModel: PreparedDishViewModel
    @FocusState private var isSearchFocused: Bool

    init(appState: AppState) {
        _viewModel = State(initialValue: PreparedDishViewModel(appState: appState))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            searchAndFilters

            if viewModel.filteredDishes.isEmpty {
                EmptyStateView(
                    icon: "takeoutbag.and.cup.and.straw",
                    title: "No prepared dishes",
                    message: "Track leftovers, takeout, and ready-to-eat meals separately from pantry ingredients.",
                    actionTitle: "Add Prepared Dish"
                ) {
                    viewModel.showAddDish = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AppList {
                    ForEach(viewModel.filteredDishes) { dish in
                        Button {
                            viewModel.selectedDish = dish
                        } label: {
                            PreparedDishRow(dish: dish)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Prepared Dishes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showAddDish = true
                } label: {
                    Label("Add Prepared Dish", systemImage: "plus")
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
    let dish: PreparedDish

    @State private var editingDish: PreparedDish?

    private var linkedRecipe: Recipe? {
        guard let recipeID = dish.recipeID else { return nil }
        return appState.allRecipes.first { $0.id == recipeID }
    }

    var body: some View {
        AppScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                detailCard(title: "Planning") {
                    detailRow(title: "Meal types", value: dish.mealTypesSummary)
                    detailRow(title: "Servings remaining", value: dish.servingsDisplay)
                    detailRow(title: "Storage", value: dish.storage.rawValue)
                }

                detailCard(title: "Freshness") {
                    detailRow(title: "Use by", value: useByText)
                    detailRow(title: "Source", value: dish.freshnessSource == .estimated ? "Estimated" : "User provided")
                }

                if let linkedRecipe {
                    detailCard(title: "Linked Recipe") {
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
                }

                if let nutrition = dish.nutrition {
                    detailCard(title: "Nutrition") {
                        detailRow(title: "Calories", value: "\(nutrition.calories)")
                        detailRow(title: "Macros", value: nutrition.macroSummary)
                    }
                }

                if let notes = dish.notes, !notes.isEmpty {
                    detailCard(title: "Notes") {
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(AppColors.darkText)
                    }
                }
            }
            .padding()
        }
        .background(AppColors.background)
        .navigationTitle(dish.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    editingDish = dish
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
            Text(dish.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(AppColors.darkText)

            HStack(spacing: 10) {
                pill(text: dish.servingsDisplay, color: AppColors.warmOrange)
                pill(text: dish.storage.rawValue, color: AppColors.accentBlue)
                if dish.expiryStatus != .fresh {
                    pill(text: dish.expiryStatus == .expired ? "Expired" : "Use soon", color: AppColors.softRed)
                }
            }
        }
    }

    private var useByText: String {
        guard let useByDate = dish.useByDate else { return "Not set" }
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

    private func detailCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.darkText)
            content()
        }
        .padding()
        .cardStyle()
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppColors.subtleText)
            Spacer()
            Text(value)
                .foregroundStyle(AppColors.darkText)
        }
        .font(.subheadline)
    }
}

struct PreparedDishEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState
    let onSave: (PreparedDish) -> Void

    private let existingDish: PreparedDish?

    @State private var draft: PreparedDishDraft
    @State private var showRecipePicker = false

    init(appState: AppState, dish: PreparedDish? = nil, onSave: @escaping (PreparedDish) -> Void) {
        self.appState = appState
        self.existingDish = dish
        self.onSave = onSave
        _draft = State(initialValue: PreparedDishDraft(dish: dish))
    }

    private var linkedRecipe: Recipe? {
        guard let recipeID = draft.recipeID else { return nil }
        return appState.allRecipes.first { $0.id == recipeID }
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
                        guard let dish = draft.buildDish() else { return }
                        onSave(dish)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
            .sheet(isPresented: $showRecipePicker) {
                MealPickerView(
                    recipes: appState.allRecipes,
                    preparedDishes: [],
                    onSelectRecipe: { recipe in
                        draft.recipeID = recipe.id
                        if draft.caloriesText.trimmed.isEmpty, let nutrition = recipe.nutrition {
                            let nutritionStrings = PreparedDishDraft.nutritionStrings(from: nutrition)
                            draft.caloriesText = String(nutrition.calories)
                            draft.proteinText = nutritionStrings.protein
                            draft.carbsText = nutritionStrings.carbs
                            draft.fatText = nutritionStrings.fat
                        }
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

            Toggle("Use estimated freshness", isOn: $draft.useEstimatedFreshness)

            if draft.useEstimatedFreshness {
                Text("Estimated use by: \(draft.resolvedUseByDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.subtleText)
            } else {
                DatePicker("Use by date", selection: $draft.manualUseByDate, displayedComponents: .date)
            }
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