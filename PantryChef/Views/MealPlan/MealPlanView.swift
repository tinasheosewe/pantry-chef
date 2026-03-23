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
                viewModel.addShoppingItems(itemsToAdd)
            }
            .sheet(isPresented: $viewModel.showMealPicker) {
                MealPickerView(
                    recipes: viewModel.appState.allRecipes,
                    preparedDishes: viewModel.appState.preparedDishes,
                    onSelectRecipe: { recipe in
                        if let slot = viewModel.selectedSlot {
                            viewModel.assignRecipe(recipe, to: slot)
                        }
                    },
                    onSelectPreparedDish: { dish in
                        if let slot = viewModel.selectedSlot {
                            viewModel.assignPreparedDish(dish, to: slot)
                        }
                    }
                )
            }
            .appNavigationSheet(item: $selectedMealEntry) { entry in
                if let recipe = entry.recipe {
                    RecipeDetailView(recipe: recipe)
                    .environment(viewModel.appState)
                } else if let preparedDish = entry.preparedDish {
                    PreparedDishDetailView(dish: preparedDish)
                        .environment(viewModel.appState)
                }
            }
        }
    }

    private func prepareShoppingConfirmation() {
        shoppingConfirmation = ShoppingListConfirmationRequest(items: viewModel.previewShoppingList(), context: .mealPlan)
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
            if let entry, entry.isPlanned, (entry.recipe != nil || entry.preparedDish != nil) {
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
                if entry.recipe != nil || entry.preparedDish != nil {
                    Button {
                        selectedMealEntry = entry
                    } label: {
                        Label(entry.recipe != nil ? "View Recipe" : "View Prepared Dish", systemImage: entry.recipe != nil ? "book" : "takeoutbag.and.cup.and.straw")
                    }
                }
                Button {
                    viewModel.selectSlot(date: date, mealType: mealType)
                } label: {
                    Label("Change Meal", systemImage: "arrow.triangle.swap")
                }
                Button(role: .destructive) {
                    viewModel.removeEntry(entry)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Recipe Picker View
struct MealPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let recipes: [Recipe]
    let preparedDishes: [PreparedDish]
    let onSelectRecipe: (Recipe) -> Void
    let onSelectPreparedDish: (PreparedDish) -> Void
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebouncer = TaskDebouncer()

    var filteredRecipes: [Recipe] {
        SearchQuerySupport.filtered(recipes, query: debouncedSearchText) { $0.title }
    }

    var filteredPreparedDishes: [PreparedDish] {
        SearchQuerySupport.filtered(preparedDishes, query: debouncedSearchText) { $0.name }
    }

    var body: some View {
        NavigationStack {
            AppList {
                if !filteredPreparedDishes.isEmpty {
                    Section("Prepared Dishes") {
                        ForEach(filteredPreparedDishes) { dish in
                            Button {
                                onSelectPreparedDish(dish)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "takeoutbag.and.cup.and.straw")
                                        .font(.title3)
                                        .foregroundStyle(AppColors.warmOrange)
                                        .frame(width: 40, height: 40)
                                        .background(AppColors.warmOrange.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(dish.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(AppColors.darkText)

                                        Text("\(dish.servingsDisplay) • \(dish.mealTypesSummary)")
                                            .font(.caption2)
                                            .foregroundStyle(AppColors.subtleText)
                                    }

                                    Spacer()

                                    if dish.useByDate != nil {
                                        ExpiryBadge(status: dish.expiryStatus, daysLeft: dish.daysUntilUseBy)
                                    }
                                }
                            }
                        }
                    }
                }

                if !filteredRecipes.isEmpty {
                    Section("Recipes") {
                        ForEach(filteredRecipes) { recipe in
                            Button {
                                onSelectRecipe(recipe)
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
                }
            }
            .searchable(text: $searchText, prompt: "Search recipes")
            .onChange(of: searchText) {
                SearchQuerySupport.schedule(text: searchText, debouncer: searchDebouncer) {
                    debouncedSearchText = $0
                }
            }
            .navigationTitle("Choose Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
