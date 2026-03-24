import SwiftUI

struct MealPlanView: View {
    @State private var viewModel: MealPlanViewModel
    @State private var selectedMealEntry: MealPlanEntry?
    @State private var selectedMealSlot: MealSlotPresentation?
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
                if let slot = viewModel.selectedSlot {
                    MealPickerView(
                        recipes: viewModel.appState.allRecipes,
                        preparedDishes: viewModel.appState.preparedDishes,
                        onSelectRecipe: { recipe in
                            viewModel.assignRecipe(recipe, to: slot)
                        },
                        onSelectPreparedDish: { dish in
                            viewModel.assignPreparedDish(dish, to: slot)
                        }
                    )
                }
            }
            .sheet(isPresented: $viewModel.showMultiMealPicker) {
                if let slot = viewModel.selectedSlot {
                    MultiMealPickerView(
                        recipes: viewModel.appState.allRecipes,
                        preparedDishes: viewModel.appState.preparedDishes,
                        onSave: { selections in
                            viewModel.assignSelections(selections, to: slot)
                        }
                    )
                }
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
            .appNavigationSheet(item: $selectedMealSlot) { slot in
                MealSlotEntriesView(
                    slot: slot,
                    appState: viewModel.appState,
                    onRemoveEntry: { entry in
                        viewModel.removeEntry(entry)
                    },
                    onUpdateEntry: { entry in
                        viewModel.updateEntry(entry)
                    },
                    onAddMore: {
                        viewModel.selectSlot(
                            date: slot.date,
                            mealType: slot.mealType,
                            replaceExisting: false,
                            allowsMultipleSelection: true
                        )
                    },
                    onReplaceSlot: {
                        viewModel.selectSlot(date: slot.date, mealType: slot.mealType, replaceExisting: true)
                    }
                )
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
        let entries = viewModel.entriesFor(date: date, mealType: mealType)
        let primaryEntry = entries.first
        let hasMultipleEntries = entries.count > 1

        return Button {
            if hasMultipleEntries {
                selectedMealSlot = MealSlotPresentation(date: date, mealType: mealType)
            } else if let entry = primaryEntry, entry.isPlanned, (entry.recipe != nil || entry.preparedDish != nil) {
                selectedMealEntry = entry
            } else if let entry = primaryEntry, entry.isPlanned {
                selectedMealSlot = MealSlotPresentation(date: date, mealType: mealType)
            } else {
                viewModel.selectSlot(date: date, mealType: mealType, replaceExisting: true)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mealType.icon)
                    .font(.caption)
                    .foregroundStyle(primaryEntry != nil ? AppColors.primaryGreen : AppColors.mediumGray)

                Text(mealType.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.subtleText)

                if let primaryEntry, primaryEntry.isPlanned {
                    Text(primaryEntry.displayName)
                        .font(.system(size: 10))
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.darkText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if hasMultipleEntries {
                        Text("+\(entries.count - 1) more")
                            .font(.system(size: 9))
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.primaryGreen)
                    } else if let planningSubtitle = primaryEntry.planningSubtitle {
                        Text(planningSubtitle)
                            .font(.system(size: 8))
                            .foregroundStyle(AppColors.subtleText)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(AppColors.mediumGray)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(primaryEntry?.isPlanned == true ? AppColors.primaryGreen.opacity(0.08) : AppColors.lightGray)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .contextMenu {
            if entries.count > 1 {
                Button {
                    selectedMealSlot = MealSlotPresentation(date: date, mealType: mealType)
                } label: {
                    Label("View Meals", systemImage: "square.grid.2x2")
                }
            } else if let entry = primaryEntry, entry.isPlanned {
                if entry.recipe != nil || entry.preparedDish != nil {
                    Button {
                        selectedMealEntry = entry
                    } label: {
                        Label(entry.recipe != nil ? "View Recipe" : "View Prepared Dish", systemImage: entry.recipe != nil ? "book" : "takeoutbag.and.cup.and.straw")
                    }
                }

                if entry.supportsPlannedServings {
                    Button {
                        selectedMealSlot = MealSlotPresentation(date: date, mealType: mealType)
                    } label: {
                        Label("Allocate Servings", systemImage: "slider.horizontal.3")
                    }
                }
            }

            Button {
                viewModel.selectSlot(date: date, mealType: mealType, replaceExisting: false, allowsMultipleSelection: true)
            } label: {
                Label(entries.isEmpty ? "Plan Multiple" : "Add Multiple", systemImage: "plus.rectangle.on.rectangle")
            }

            if let entry = primaryEntry, entry.isPlanned {
                Button {
                    viewModel.selectSlot(date: date, mealType: mealType, replaceExisting: true)
                } label: {
                    Label("Change Meal", systemImage: "arrow.triangle.swap")
                }

                if entries.count == 1 {
                    Button(role: .destructive) {
                        viewModel.removeEntry(entry)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) {
                        viewModel.removeEntries(entries)
                    } label: {
                        Label("Clear Slot", systemImage: "trash")
                    }
                }
            }
        }
    }
}

private struct MealSlotPresentation: Identifiable {
    let id = UUID()
    let date: Date
    let mealType: MealType
}

private struct MealSlotEntriesView: View {
    let slot: MealSlotPresentation
    let appState: AppState
    let onRemoveEntry: (MealPlanEntry) -> Void
    let onUpdateEntry: (MealPlanEntry) -> Void
    let onAddMore: () -> Void
    let onReplaceSlot: () -> Void

    private var entries: [MealPlanEntry] {
        appState.plannedEntries(on: slot.date)
            .filter { $0.mealType == slot.mealType }
    }

    var body: some View {
        AppList {
            Section {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        if let recipe = entry.recipe {
                            NavigationLink(destination: RecipeDetailView(recipe: recipe).environment(appState)) {
                                mealEntryRow(title: recipe.title, subtitle: entry.planningSubtitle, systemImage: recipe.mealType?.icon ?? "book")
                            }
                        } else if let preparedDish = entry.preparedDish {
                            NavigationLink(destination: PreparedDishDetailView(dish: preparedDish).environment(appState)) {
                                mealEntryRow(title: preparedDish.name, subtitle: entry.planningSubtitle, systemImage: "takeoutbag.and.cup.and.straw")
                            }
                        } else {
                            mealEntryRow(title: entry.displayName, subtitle: entry.planningSubtitle, systemImage: "fork.knife")
                        }

                        if entry.supportsPlannedServings {
                            Stepper(value: plannedServingsBinding(for: entry), in: entry.editablePlannedServingsRange) {
                                Text(entry.plannedServingsLabel ?? "1 serving planned")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.subtleText)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        onRemoveEntry(entries[index])
                    }
                }
            } header: {
                Text(slot.mealType.rawValue)
            } footer: {
                Text(slot.date.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .navigationTitle("Meal Slot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Replace") {
                    onReplaceSlot()
                }

                Button("Add More") {
                    onAddMore()
                }
            }
        }
    }

    @ViewBuilder
    private func mealEntryRow(title: String, subtitle: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(AppColors.primaryGreen)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(AppColors.darkText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }
            }
        }
    }

    private func plannedServingsBinding(for entry: MealPlanEntry) -> Binding<Int> {
        Binding(
            get: {
                entry.effectivePlannedServings ?? entry.editablePlannedServingsRange.lowerBound
            },
            set: { newValue in
                onUpdateEntry(entry.updatingPlannedServings(newValue))
            }
        )
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
                                            Text(recipe.servings == 1 ? "1 serving" : "\(recipe.servings) servings")
                                                .font(.caption2)
                                                .foregroundStyle(AppColors.subtleText)
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

struct MultiMealPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let recipes: [Recipe]
    let preparedDishes: [PreparedDish]
    let onSave: ([MealSelectionItem]) -> Void

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var stagedSelections: [MealSelectionItem] = []
    @State private var searchDebouncer = TaskDebouncer()

    private var filteredRecipes: [Recipe] {
        SearchQuerySupport.filtered(recipes, query: debouncedSearchText) { $0.title }
    }

    private var filteredPreparedDishes: [PreparedDish] {
        SearchQuerySupport.filtered(preparedDishes, query: debouncedSearchText) { $0.name }
    }

    var body: some View {
        NavigationStack {
            AppList {
                if !stagedSelections.isEmpty {
                    Section("Selected") {
                        ForEach(Array(stagedSelections.enumerated()), id: \.offset) { index, item in
                            HStack {
                                Text(item.displayName)
                                    .foregroundStyle(AppColors.darkText)
                                Spacer()
                                Button {
                                    stagedSelections.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(AppColors.softRed)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !filteredPreparedDishes.isEmpty {
                    Section("Prepared Dishes") {
                        ForEach(filteredPreparedDishes) { dish in
                            Button {
                                stagedSelections.append(.preparedDish(dish))
                            } label: {
                                selectionRow(
                                    title: dish.name,
                                    subtitle: "\(dish.servingsDisplay) • \(dish.mealTypesSummary)",
                                    systemImage: "takeoutbag.and.cup.and.straw",
                                    accent: AppColors.warmOrange,
                                    count: stagedSelections.filter { $0 == .preparedDish(dish) }.count
                                )
                            }
                        }
                    }
                }

                if !filteredRecipes.isEmpty {
                    Section("Recipes") {
                        ForEach(filteredRecipes) { recipe in
                            Button {
                                stagedSelections.append(.recipe(recipe))
                            } label: {
                                selectionRow(
                                    title: recipe.title,
                                    subtitle: "\(recipe.servings == 1 ? "1 serving" : "\(recipe.servings) servings") • \(recipe.totalTimeDisplay)",
                                    systemImage: recipe.mealType?.icon ?? "fork.knife",
                                    accent: AppColors.primaryGreen,
                                    count: stagedSelections.filter { $0 == .recipe(recipe) }.count
                                )
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Add recipes or prepared dishes")
            .onChange(of: searchText) {
                SearchQuerySupport.schedule(text: searchText, debouncer: searchDebouncer) {
                    debouncedSearchText = $0
                }
            }
            .navigationTitle("Add Multiple")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(stagedSelections)
                        dismiss()
                    }
                    .disabled(stagedSelections.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func selectionRow(title: String, subtitle: String, systemImage: String, accent: Color, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.darkText)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppColors.subtleText)
            }

            Spacer()

            if count > 0 {
                Text("x\(count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}
