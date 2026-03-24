import SwiftUI

struct PreparedDishesView: View {
    @State private var viewModel: PreparedDishViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var showMealPlanQuickAddSelection = false
    @State private var showMealPlanQuickAddReview = false
    @State private var showHistoryPicker = false
    @State private var mealPlanQuickAddDrafts: [MealPlanPreparedDishReviewDraft] = []
    @State private var historySeedItem: PreparedDishHistoryItem?
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

            if !viewModel.appState.preparedDishHistory.isEmpty {
                historySummaryCard
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            if viewModel.filteredDishes.isEmpty {
                EmptyStateView(
                    icon: "takeoutbag.and.cup.and.straw",
                    title: "No prepared dishes",
                    message: "Track leftovers, takeout, and ready-to-eat meals.",
                    actionTitle: "Add Prepared Dish"
                ) {
                    presentSingleAdd()
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
        .overlay(alignment: .bottom) {
            if let feedback = viewModel.feedbackBanner {
                Text(feedback.message)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.darkText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppColors.cardBackground)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
                    .padding(.bottom, isEmbedded ? 10 : 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.feedbackBanner)
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .primaryAction) {
                    addMenuLabel(title: "Add Prepared Dish")
                }
            }
        }
        .sheet(isPresented: $viewModel.showAddDish) {
            PreparedDishEditorView(appState: viewModel.appState) { dish in
                viewModel.addDish(dish)
            }
        }
        .sheet(isPresented: $showHistoryPicker) {
            PreparedDishHistoryPickerView(appState: viewModel.appState) { item in
                showHistoryPicker = false
                Task { @MainActor in
                    historySeedItem = item
                }
            }
        }
        .sheet(isPresented: $showMealPlanQuickAddSelection) {
            PreparedDishMealPlanSelectionView(appState: viewModel.appState) { entries in
                mealPlanQuickAddDrafts = entries.map(MealPlanPreparedDishReviewDraft.init)
                showMealPlanQuickAddSelection = false
                Task { @MainActor in
                    showMealPlanQuickAddReview = true
                }
            }
        }
        .sheet(isPresented: $showMealPlanQuickAddReview, onDismiss: {
            mealPlanQuickAddDrafts = []
        }) {
            PreparedDishMealPlanReviewView(appState: viewModel.appState, drafts: $mealPlanQuickAddDrafts) { dishes in
                for dish in dishes {
                    viewModel.addDish(dish)
                }
                showMealPlanQuickAddReview = false
            }
        }
        .sheet(item: $viewModel.editingDish) { dish in
            PreparedDishEditorView(appState: viewModel.appState, dish: dish) { updatedDish in
                viewModel.updateDish(updatedDish)
            }
        }
        .sheet(item: $historySeedItem) { item in
            PreparedDishEditorView(appState: viewModel.appState, initialDraft: item.makeDraft()) { dish in
                viewModel.addDish(dish)
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

            addMenuLabel(title: "Add")
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

    private var historySummaryCard: some View {
        Button {
            showHistoryPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.title3)
                    .foregroundStyle(AppColors.accentBlue)
                    .frame(width: 40, height: 40)
                    .background(AppColors.accentBlue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Re-add Previous")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.darkText)
                    Text("\(viewModel.appState.preparedDishHistory.count) saved dishes ready to reuse")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.mediumGray)
            }
            .padding()
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
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

    private func presentSingleAdd() {
        viewModel.showAddDish = true
    }

    @ViewBuilder
    private func addMenuLabel(title: String) -> some View {
        Menu {
            Button {
                presentSingleAdd()
            } label: {
                Label("Single Meal", systemImage: "plus.circle")
            }

            Button {
                showMealPlanQuickAddSelection = true
            } label: {
                Label("From Meal Plan", systemImage: "calendar.badge.plus")
            }
        } label: {
            Label(title, systemImage: "plus")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.primaryGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.primaryGreen.opacity(0.12))
                .clipShape(Capsule())
        }
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

    init(appState: AppState, dish: PreparedDish? = nil, initialDraft: PreparedDishDraft? = nil, seedRecipe: Recipe? = nil, onSave: @escaping (PreparedDish) -> Void) {
        self.appState = appState
        self.existingDish = dish
        self.onSave = onSave
        var resolvedInitialDraft = initialDraft ?? PreparedDishDraft(dish: dish)
        if dish == nil, initialDraft == nil, let seedRecipe {
            resolvedInitialDraft.recipeID = seedRecipe.id
            resolvedInitialDraft.syncLinkedRecipe(seedRecipe)
        }
        _draft = State(initialValue: resolvedInitialDraft)
    }

    private var linkedRecipe: Recipe? {
        guard let recipeID = draft.recipeID else { return nil }
        return appState.allRecipes.first { $0.id == recipeID }
    }

    var body: some View {
        AppNavigationSheet {
            AppScrollView {
                PreparedDishDraftForm(
                    appState: appState,
                    draft: $draft,
                    linkedRecipe: linkedRecipe,
                    showRecipePicker: $showRecipePicker
                )
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
        }
    }
}

private struct PreparedDishHistoryPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState
    let onSelect: (PreparedDishHistoryItem) -> Void

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebouncer = TaskDebouncer()

    private var filteredItems: [PreparedDishHistoryItem] {
        SearchQuerySupport.filtered(appState.preparedDishHistory, query: debouncedSearchText) { item in
            [item.name, item.mealTypesSummary, item.notes ?? ""].joined(separator: " ")
        }
        .sorted { lhs, rhs in
            if lhs.recipeID != rhs.recipeID {
                return lhs.recipeID != nil
            }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if filteredItems.isEmpty {
                    EmptyStateView(
                        icon: "clock.badge.questionmark",
                        title: appState.preparedDishHistory.isEmpty ? "No reusable history yet" : "No previous dishes found",
                        message: appState.preparedDishHistory.isEmpty
                            ? "Prepared dishes you add here will automatically become reusable templates for later."
                            : "Try a different search to find a previous prepared dish."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AppList {
                        Section {
                            Text("Pick a previous dish to prefill a new Prepared Food entry. You can still adjust servings, storage, and freshness before saving.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.subtleText)
                        }

                        Section {
                            ForEach(filteredItems) { item in
                                Button {
                                    onSelect(item)
                                } label: {
                                    historyRow(item)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            SectionHeader(
                                title: "Previous Dishes",
                                subtitle: "Recipe-linked dishes are shown first, then the most recent items."
                            )
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search previous dishes")
            .onChange(of: searchText) {
                SearchQuerySupport.schedule(text: searchText, debouncer: searchDebouncer) {
                    debouncedSearchText = $0
                }
            }
            .navigationTitle("Re-add Previous")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func historyRow(_ item: PreparedDishHistoryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.title3)
                .foregroundStyle(item.recipeID != nil ? AppColors.primaryGreen : AppColors.accentBlue)
                .frame(width: 40, height: 40)
                .background((item.recipeID != nil ? AppColors.primaryGreen : AppColors.accentBlue).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.darkText)
                Text("\(item.servingsText) • \(item.storage.rawValue) • \(item.mealTypesSummary)")
                    .font(.caption)
                    .foregroundStyle(AppColors.subtleText)
                Text(item.timesPrepared == 1 ? "Used once" : "Used \(item.timesPrepared)x")
                    .font(.caption2)
                    .foregroundStyle(AppColors.subtleText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if item.recipeID != nil {
                    Text("Linked")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.primaryGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.primaryGreen.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(item.lastUsedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(AppColors.subtleText)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PreparedDishDraftForm: View {
    let appState: AppState
    @Binding var draft: PreparedDishDraft
    let linkedRecipe: Recipe?
    @Binding var showRecipePicker: Bool

    private var useByDateBinding: Binding<Date> {
        Binding(
            get: { draft.useByDateWasEdited ? draft.manualUseByDate : draft.estimatedUseByDate },
            set: { draft.updateUseByDate($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            basicSection
            freshnessSection
            recipeSection
            nutritionSection
            notesSection
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

@MainActor
struct MealPlanPreparedDishReviewDraft: Identifiable, Hashable {
    let id: UUID
    let sourceEntry: MealPlanEntry
    var draft: PreparedDishDraft

    init(entry: MealPlanEntry) {
        id = entry.id
        sourceEntry = entry
        draft = entry.makePreparedDishDraft()
    }

    var sourceSummary: String {
        "\(sourceEntry.date.formatted(date: .abbreviated, time: .omitted)) • \(sourceEntry.mealType.rawValue)"
    }

    func linkedRecipe(in appState: AppState) -> Recipe? {
        guard let recipeID = draft.recipeID else { return nil }
        return appState.allRecipes.first { $0.id == recipeID }
    }

    func resolvedTitle(in appState: AppState) -> String {
        draft.resolvedName(using: linkedRecipe(in: appState)).nilIfEmpty ?? sourceEntry.displayName
    }

    func reviewSummary(in appState: AppState) -> String {
        var parts: [String] = []
        parts.append(draft.servingsRemaining == 1 ? "1 serving" : "\(draft.servingsRemaining) servings")
        parts.append(draft.storage.rawValue)

        let mealTypes = draft.mealTypes
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.rawValue)
            .joined(separator: " • ")
        if !mealTypes.isEmpty {
            parts.append(mealTypes)
        }

        if let linkedRecipe = linkedRecipe(in: appState) {
            parts.append("Linked to \(linkedRecipe.title)")
        }

        return parts.joined(separator: " • ")
    }

    func isValid(in appState: AppState) -> Bool {
        draft.isValid(using: linkedRecipe(in: appState))
    }

    func buildDish(in appState: AppState) -> PreparedDish? {
        draft.buildDish(using: linkedRecipe(in: appState))
    }
}

struct PreparedDishMealPlanSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState
    let onContinue: ([MealPlanEntry]) -> Void

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var searchDebouncer = TaskDebouncer()

    private var filteredEntries: [MealPlanEntry] {
        let plannedEntries = appState.preparedFoodSourceEntriesFromMealPlan()
        return SearchQuerySupport.filtered(plannedEntries, query: debouncedSearchText) { entry in
            [entry.displayName, entry.mealType.rawValue, entry.date.formatted(date: .abbreviated, time: .omitted)]
                .joined(separator: " ")
        }
    }

    private var selectedEntries: [MealPlanEntry] {
        appState.preparedFoodSourceEntriesFromMealPlan().filter { selectedEntryIDs.contains($0.id) }
    }

    private var entriesByDay: [(date: Date, entries: [MealPlanEntry])] {
        let grouped = Dictionary(grouping: filteredEntries) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { date in
            let entries = grouped[date, default: []].sorted {
                if $0.mealType == $1.mealType {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.mealType.rawValue < $1.mealType.rawValue
            }
            return (date, entries)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if filteredEntries.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.exclamationmark",
                        title: "No eligible meal-plan items",
                        message: "Only recipes and custom planned meals can be added to Prepared Food from here."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AppList {
                        Section {
                            Text("Select one or more meal-plan entries, then review them before adding them to Prepared Food.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.subtleText)
                        }

                        ForEach(entriesByDay, id: \.date) { group in
                            Section(group.date.formatted(date: .abbreviated, time: .omitted)) {
                                ForEach(group.entries) { entry in
                                    mealPlanEntryRow(entry)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search meal plan")
            .onChange(of: searchText) {
                SearchQuerySupport.schedule(text: searchText, debouncer: searchDebouncer) {
                    debouncedSearchText = $0
                }
            }
            .navigationTitle("From Meal Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                selectionSummaryBar
            }
        }
    }

    private func mealPlanEntryRow(_ entry: MealPlanEntry) -> some View {
        let isSelected = selectedEntryIDs.contains(entry.id)
        let accent = entry.preparedDish != nil ? AppColors.warmOrange : AppColors.primaryGreen
        let icon = entry.recipe != nil ? (entry.recipe?.mealType?.icon ?? "book") : entry.preparedDish != nil ? "takeoutbag.and.cup.and.straw" : entry.mealType.icon

        return Button {
            if isSelected {
                selectedEntryIDs.remove(entry.id)
            } else {
                selectedEntryIDs.insert(entry.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.darkText)
                    Text("\(entry.mealType.rawValue) • \(entry.planningSubtitle ?? entry.sourceDateText)")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppColors.primaryGreen : AppColors.mediumGray)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var selectionSummaryBar: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedEntries.isEmpty ? "Select meal-plan items" : "\(selectedEntries.count) items selected")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.darkText)
                    Text("Selected meals open in a review step before anything is added.")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                Spacer()

                Button {
                    onContinue(selectedEntries)
                } label: {
                    Text("Review")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(selectedEntries.isEmpty ? AppColors.mediumGray : AppColors.accentBlue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .disabled(selectedEntries.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
}

struct PreparedDishMealPlanReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState
    @Binding var drafts: [MealPlanPreparedDishReviewDraft]
    let onSave: ([PreparedDish]) -> Void

    @State private var editingDraft: MealPlanPreparedDishReviewDraft?
    @State private var isSaving = false

    private var validDraftCount: Int {
        drafts.filter { $0.isValid(in: appState) }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if drafts.isEmpty {
                    EmptyStateView(
                        icon: "square.stack.3d.up.slash",
                        title: "Nothing selected yet",
                        message: "Pick meal-plan items first, then review them here."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AppList {
                        Section {
                            ForEach(drafts) { reviewDraft in
                                reviewDraftRow(reviewDraft)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            }
                        } header: {
                            SectionHeader(
                                title: "Review Items",
                                subtitle: "\(validDraftCount) ready • \(drafts.count - validDraftCount) need edits"
                            )
                            .padding(.top, 8)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppColors.background)
                }
            }
            .navigationTitle("Review Prepared Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                reviewSummaryBar
            }
        }
        .sheet(item: $editingDraft) { reviewDraft in
            PreparedDishMealPlanDraftEditorView(appState: appState, reviewDraft: reviewDraft) { updatedDraft in
                if let index = drafts.firstIndex(where: { $0.id == updatedDraft.id }) {
                    drafts[index] = updatedDraft
                }
            }
        }
    }

    private func reviewDraftRow(_ reviewDraft: MealPlanPreparedDishReviewDraft) -> some View {
        let accent = reviewDraft.sourceEntry.preparedDish != nil ? AppColors.warmOrange : AppColors.primaryGreen

        return Button {
            editingDraft = reviewDraft
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: reviewDraft.sourceEntry.preparedDish != nil ? "takeoutbag.and.cup.and.straw" : "fork.knife")
                        .font(.title3)
                        .foregroundStyle(accent)
                        .frame(width: 40, height: 40)
                        .background(accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(reviewDraft.resolvedTitle(in: appState))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.darkText)
                        Text(reviewDraft.sourceSummary)
                            .font(.caption)
                            .foregroundStyle(AppColors.subtleText)
                        Text(reviewDraft.reviewSummary(in: appState))
                            .font(.caption2)
                            .foregroundStyle(AppColors.subtleText)
                    }

                    Spacer()
                    PantryDraftStateBadge(state: reviewDraft.isValid(in: appState) ? .valid : .incomplete)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppColors.cardBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var reviewSummaryBar: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(drafts.isEmpty ? "Nothing to add" : "\(drafts.count) dishes staged")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.darkText)
                    Text(validDraftCount == drafts.count ? "Everything is ready to add." : "Review incomplete items before adding them.")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                Spacer()

                Button {
                    let dishes = drafts.compactMap { $0.buildDish(in: appState) }
                    guard dishes.count == drafts.count else { return }
                    isSaving = true
                    onSave(dishes)
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Add to Prepared Food")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(validDraftCount == drafts.count && !drafts.isEmpty ? AppColors.primaryGreen : AppColors.mediumGray)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(validDraftCount != drafts.count || drafts.isEmpty || isSaving)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
}

struct PreparedDishMealPlanDraftEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState
    let onSave: (MealPlanPreparedDishReviewDraft) -> Void

    @State private var reviewDraft: MealPlanPreparedDishReviewDraft
    @State private var showRecipePicker = false

    init(appState: AppState, reviewDraft: MealPlanPreparedDishReviewDraft, onSave: @escaping (MealPlanPreparedDishReviewDraft) -> Void) {
        self.appState = appState
        self.onSave = onSave
        _reviewDraft = State(initialValue: reviewDraft)
    }

    private var linkedRecipe: Recipe? {
        reviewDraft.linkedRecipe(in: appState)
    }

    var body: some View {
        AppNavigationSheet {
            AppScrollView {
                PreparedDishDraftForm(
                    appState: appState,
                    draft: $reviewDraft.draft,
                    linkedRecipe: linkedRecipe,
                    showRecipePicker: $showRecipePicker
                )
                .padding()
            }
            .background(AppColors.background)
            .navigationTitle("Edit Selected Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(reviewDraft)
                        dismiss()
                    }
                    .disabled(!reviewDraft.isValid(in: appState))
                }
            }
        }
    }
}

private extension MealPlanEntry {
    var sourceDateText: String {
        date.formatted(date: .abbreviated, time: .omitted)
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