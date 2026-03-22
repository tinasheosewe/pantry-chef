import SwiftUI

struct MealPlanView: View {
    @State private var viewModel: MealPlanViewModel
    @State private var selectedMealEntry: MealPlanEntry?
    @State private var shoppingConfirmation: ShoppingListConfirmationRequest?

    init(appState: AppState) {
        _viewModel = State(initialValue: MealPlanViewModel(appState: appState))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        AppScreen("mealplan.screen") {
            VStack(spacing: 0) {
                weekNavigation

                AppScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.weekDays, id: \.self) { date in
                            dayRow(date)
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("Meal Plan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        prepareShoppingConfirmation()
                    } label: {
                        Label("Shopping List", systemImage: "cart")
                    }
                    .accessibilityIdentifier("mealplan.shoppingListButton")
                }
            }
            .shoppingListConfirmation($shoppingConfirmation) { itemsToAdd in
                Task {
                    await viewModel.addShoppingItems(itemsToAdd)
                }
            }
            .sheet(isPresented: $viewModel.showRecipePicker) {
                RecipePickerView(
                    recipes: viewModel.appState.allRecipes,
                    onSelect: { recipe in
                        if let slot = viewModel.selectedSlot {
                            Task { await viewModel.assignRecipe(recipe, to: slot) }
                        }
                    }
                )
            }
            .appNavigationSheet(item: $selectedMealEntry) { entry in
                if let recipe = entry.recipe {
                    RecipeDetailView(recipe: recipe)
                    .environment(viewModel.appState)
                }
            }
            .onChange(of: viewModel.appState.mealPlan) { _, _ in
                viewModel.reloadEntries()
            }
        }
    }

    private func prepareShoppingConfirmation() {
        shoppingConfirmation = ShoppingListConfirmationRequest(items: viewModel.previewShoppingList())
    }

    // MARK: - Week Navigation
    private var weekNavigation: some View {
        HStack {
            Button {
                viewModel.previousWeek()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(AppColors.primaryGreen)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.weekDateRangeText)
                    .font(.headline)
                    .foregroundStyle(AppColors.darkText)
                Text("\(viewModel.totalPlannedMeals) meals planned")
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
            }

            Spacer()

            Button {
                viewModel.nextWeek()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(AppColors.primaryGreen)
            }
        }
        .padding()
        .background(AppColors.cardBackground)
        .overlay(alignment: .bottom) {
            Button("Today") {
                viewModel.goToCurrentWeek()
            }
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(AppColors.primaryGreen)
            .offset(y: 12)
        }
    }

    // MARK: - Day Row
    private func dayRow(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(date, format: .dateTime.weekday(.wide))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Calendar.current.isDateInToday(date) ? AppColors.primaryGreen : AppColors.darkText)
                    Text(date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                Spacer()

                if Calendar.current.isDateInToday(date) {
                    Text("Today")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.primaryGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.primaryGreen.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 8) {
                ForEach([MealType.breakfast, .lunch, .dinner]) { mealType in
                    mealSlot(date: date, mealType: mealType)
                }
            }
        }
        .padding()
        .background(Calendar.current.isDateInToday(date) ? AppColors.primaryGreen.opacity(0.03) : .clear)
    }

    // MARK: - Meal Slot
    private func mealSlot(date: Date, mealType: MealType) -> some View {
        let entry = viewModel.entriesFor(date: date, mealType: mealType)

        return Button {
            if let entry, entry.isPlanned, entry.recipe != nil {
                selectedMealEntry = entry
            } else {
                viewModel.selectSlot(date: date, mealType: mealType)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mealType.icon)
                    .font(.caption)
                    .foregroundStyle(entry != nil ? AppColors.primaryGreen : AppColors.mediumGray)

                Text(mealType.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.subtleText)

                if let entry, entry.isPlanned {
                    Text(entry.displayName)
                        .font(.system(size: 10))
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.darkText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(AppColors.mediumGray)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(entry?.isPlanned == true ? AppColors.primaryGreen.opacity(0.08) : AppColors.lightGray)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .contextMenu {
            if let entry, entry.isPlanned {
                if entry.recipe != nil {
                    Button {
                        selectedMealEntry = entry
                    } label: {
                        Label("View Recipe", systemImage: "book")
                    }
                }
                Button {
                    viewModel.selectSlot(date: date, mealType: mealType)
                } label: {
                    Label("Change Recipe", systemImage: "arrow.triangle.swap")
                }
                Button(role: .destructive) {
                    Task { await viewModel.removeEntry(entry) }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Recipe Picker View
struct RecipePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let recipes: [Recipe]
    let onSelect: (Recipe) -> Void
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebouncer = TaskDebouncer()

    var filteredRecipes: [Recipe] {
        if debouncedSearchText.isEmpty { return recipes }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(debouncedSearchText) }
    }

    var body: some View {
        NavigationStack {
            AppList {
                ForEach(filteredRecipes) { recipe in
                    Button {
                        onSelect(recipe)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: recipe.mealType?.icon ?? "fork.knife")
                                .font(.title3)
                                .foregroundStyle(AppColors.primaryGreen)
                                .frame(width: 40, height: 40)
                                .background(AppColors.primaryGreen.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(AppColors.darkText)

                                HStack {
                                    DifficultyBadge(difficulty: recipe.difficulty)
                                    Text(recipe.totalTimeDisplay)
                                        .font(.caption2)
                                        .foregroundStyle(AppColors.subtleText)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search recipes")
            .onChange(of: searchText) {
                let normalized = searchText.trimmingCharacters(in: .whitespaces)
                searchDebouncer.schedule(after: DebounceDurations.quickSearch) {
                    debouncedSearchText = normalized
                }
            }
            .navigationTitle("Choose Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
