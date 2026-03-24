import SwiftUI

struct MealPlanView: View {
    @State private var viewModel: MealPlanViewModel
    @State private var selectedMealEntry: MealPlanEntry?
    @State private var selectedMealSlot: MealSlotPresentation?
    @State private var shoppingConfirmation: ShoppingListConfirmationRequest?
    @State private var showPreparedFoodSelection = false
    @State private var showPreparedFoodReview = false
    @State private var preparedFoodDrafts: [MealPlanPreparedDishReviewDraft] = []
    @State private var showMealLoggingSelection = false
    @State private var showMealLoggingReview = false
    @State private var mealLoggingDrafts: [MealPlanEatenReviewDraft] = []

    init(appState: AppState) {
        _viewModel = State(initialValue: MealPlanViewModel(appState: appState))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        AppScreen("mealplan.screen") {
            VStack(spacing: 0) {
                weekNavigation
                compactActionBar

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
            .shoppingListConfirmation($shoppingConfirmation) { itemsToAdd in
                viewModel.addShoppingItems(itemsToAdd)
            }
            .sheet(isPresented: $showPreparedFoodSelection) {
                PreparedDishMealPlanSelectionView(appState: viewModel.appState) { entries in
                    preparedFoodDrafts = entries.map(MealPlanPreparedDishReviewDraft.init)
                    showPreparedFoodSelection = false
                    Task { @MainActor in
                        showPreparedFoodReview = true
                    }
                }
            }
            .sheet(isPresented: $showPreparedFoodReview, onDismiss: {
                preparedFoodDrafts = []
            }) {
                PreparedDishMealPlanReviewView(appState: viewModel.appState, drafts: $preparedFoodDrafts) { dishes in
                    Task {
                        for dish in dishes {
                            await viewModel.appState.addPreparedDish(dish)
                        }
                    }
                    showPreparedFoodReview = false
                }
            }
            .sheet(isPresented: $showMealLoggingSelection) {
                MealPlanEatenSelectionView(entries: mealEntriesEligibleForLogging) { entries in
                    mealLoggingDrafts = entries.map {
                        MealPlanEatenReviewDraft(
                            entry: $0,
                            candidatePreparedDishes: viewModel.appState.matchingPreparedDishes(for: $0)
                        )
                    }
                    showMealLoggingSelection = false
                    Task { @MainActor in
                        showMealLoggingReview = true
                    }
                }
            }
            .sheet(isPresented: $showMealLoggingReview, onDismiss: {
                mealLoggingDrafts = []
            }) {
                MealPlanEatenReviewView(appState: viewModel.appState, drafts: $mealLoggingDrafts) { selections in
                    viewModel.logEntriesEaten(selections)
                    showMealLoggingReview = false
                }
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

    private var preparedFoodSourceEntries: [MealPlanEntry] {
        viewModel.appState.preparedFoodSourceEntriesFromMealPlan()
    }

    private var mealEntriesEligibleForLogging: [MealPlanEntry] {
        viewModel.entries.filter { entry in
            entry.supportsMealLogging
                && !entry.isFullyEaten
                && !viewModel.appState.matchingPreparedDishes(for: entry).isEmpty
        }
    }

    private var compactActionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                compactActionButton(
                    title: "Prepared Food",
                    systemImage: "calendar.badge.plus",
                    tint: AppColors.primaryGreen,
                    isDisabled: preparedFoodSourceEntries.isEmpty,
                    action: {
                        showPreparedFoodSelection = true
                    }
                )

                compactActionButton(
                    title: "Log Eating",
                    systemImage: "checklist.checked",
                    tint: AppColors.warmOrange,
                    isDisabled: false,
                    action: {
                        showMealLoggingSelection = true
                    }
                )

                compactActionButton(
                    title: "Shopping List",
                    systemImage: "cart",
                    tint: AppColors.accentBlue,
                    isDisabled: false,
                    accessibilityIdentifier: "mealplan.shoppingListButton",
                    action: {
                        prepareShoppingConfirmation()
                    }
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(AppColors.cardBackground)
    }

    private func compactActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        isDisabled: Bool,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(isDisabled ? AppColors.mediumGray : tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isDisabled ? AppColors.lightGray : tint.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
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
                    } else if let statusSummary = primaryEntry.mealLoggingSummary ?? primaryEntry.planningSubtitle {
                        Text(statusSummary)
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

struct CookQueueView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState

    @State private var launchingStage: CookQueueStage?
    @State private var showGathering = false
    @State private var showSoloCookMode = false
    @State private var showMultiCookMode = false

    private var queue: CookQueue? {
        appState.cookQueue
    }

    private var launchingRecipes: [Recipe] {
        guard let launchingStage else { return [] }
        return appState.resolvedRecipes(for: launchingStage)
    }

    private var queueContext: (queueID: UUID, stageID: UUID)? {
        guard let launchingStage else { return nil }
        return appState.cookQueueContext(for: launchingStage.id)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let queue, !queue.stages.isEmpty {
                    AppList {
                        Section {
                            Text("Queue recipes or meal-plan meals into solo or parallel stages. Finish a stage to unlock the next one without losing your place.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.subtleText)
                        }

                        Section {
                            ForEach(queue.stages) { stage in
                                queueStageRow(stage)
                            }
                        } header: {
                            SectionHeader(
                                title: queue.name,
                                subtitle: queue.pendingStageCount == 0
                                    ? "All stages are complete or skipped."
                                    : "\(queue.pendingStageCount) stages remaining • \(queue.completedStageCount) finished"
                            )
                            .padding(.top, 8)
                        }
                    }
                } else {
                    EmptyStateView(
                        icon: "list.number",
                        title: "Cook queue is empty",
                        message: "Add recipes from Recipe detail or queue planned meals from Meal Plan to build your next cooking run."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Cook Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if queue != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear") {
                            Task {
                                await appState.clearCookQueue()
                            }
                        }
                        .foregroundStyle(AppColors.softRed)
                    }
                }
            }
            .sheet(isPresented: $showGathering) {
                IngredientGatheringView(recipes: launchingRecipes) {
                    showGathering = false
                    if launchingRecipes.count > 1 {
                        showMultiCookMode = true
                    } else {
                        showSoloCookMode = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showSoloCookMode, onDismiss: {
                launchingStage = nil
            }) {
                if let recipe = launchingRecipes.first {
                    let session = CookingSession.load(recipeId: recipe.id)
                    CookModeView(
                        recipe: recipe,
                        resumeAtStep: session?.currentStepIndex ?? 0,
                        isResuming: session != nil,
                        queueID: queueContext?.queueID,
                        queueStageID: queueContext?.stageID
                    )
                    .environment(appState)
                }
            }
            .fullScreenCover(isPresented: $showMultiCookMode, onDismiss: {
                launchingStage = nil
            }) {
                let blocks = MultiRecipeScheduler.schedule(recipes: launchingRecipes)
                MultiCookModeView(
                    recipes: launchingRecipes,
                    blocks: blocks,
                    queueID: queueContext?.queueID,
                    queueStageID: queueContext?.stageID
                )
                .environment(appState)
            }
        }
    }

    private func queueStageRow(_ stage: CookQueueStage) -> some View {
        let recipes = appState.resolvedRecipes(for: stage)
        let canStart = !recipes.isEmpty
        let hasActiveSession = recipes.contains { CookingSession.load(recipeId: $0.id) != nil }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: stage.isParallelBatch ? "square.stack.3d.up.fill" : "frying.pan.fill")
                    .font(.title3)
                    .foregroundStyle(stage.isParallelBatch ? AppColors.accentBlue : AppColors.primaryGreen)
                    .frame(width: 40, height: 40)
                    .background((stage.isParallelBatch ? AppColors.accentBlue : AppColors.primaryGreen).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.darkText)
                    Text(stage.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                    if !recipes.isEmpty {
                        Text(recipes.map(\.totalTimeDisplay).joined(separator: " • "))
                            .font(.caption2)
                            .foregroundStyle(AppColors.subtleText)
                    }
                    if !canStart {
                        Text("One or more recipes in this stage can no longer be found.")
                            .font(.caption2)
                            .foregroundStyle(AppColors.softRed)
                    }
                }

                Spacer()

                Text(statusTitle(for: stage.status))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor(for: stage.status))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(for: stage.status).opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                if stage.status == .pending || stage.status == .active {
                    Button {
                        launchStage(stage)
                    } label: {
                        Text(hasActiveSession ? "Resume" : "Start")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(canStart ? AppColors.primaryGreen : AppColors.mediumGray)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(!canStart)

                    Button {
                        Task {
                            await appState.skipCookQueueStage(stage.id)
                        }
                    } label: {
                        Text("Skip")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.lightGray)
                            .foregroundStyle(AppColors.darkText)
                            .clipShape(Capsule())
                    }
                }

                Menu {
                    Button {
                        Task {
                            await appState.moveCookQueueStage(stage.id, by: -1)
                        }
                    } label: {
                        Label("Move Earlier", systemImage: "arrow.up")
                    }
                    .disabled(!canMoveStage(stage, by: -1))

                    Button {
                        Task {
                            await appState.moveCookQueueStage(stage.id, by: 1)
                        }
                    } label: {
                        Label("Move Later", systemImage: "arrow.down")
                    }
                    .disabled(!canMoveStage(stage, by: 1))

                    Button {
                        Task {
                            await appState.bundleCookQueueStageWithNext(stage.id)
                        }
                    } label: {
                        Label("Bundle With Next", systemImage: "square.stack.3d.up")
                    }
                    .disabled(!canBundleWithNext(stage))

                    Button {
                        Task {
                            await appState.splitCookQueueStage(stage.id)
                        }
                    } label: {
                        Label("Split Batch", systemImage: "square.split.2x1")
                    }
                    .disabled(!canSplit(stage))
                } label: {
                    Text("Edit")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.lightGray)
                        .foregroundStyle(AppColors.darkText)
                        .clipShape(Capsule())
                }

                Button {
                    Task {
                        await appState.removeCookQueueStage(stage.id)
                    }
                } label: {
                    Text("Remove")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.softRed.opacity(0.12))
                        .foregroundStyle(AppColors.softRed)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func canMoveStage(_ stage: CookQueueStage, by offset: Int) -> Bool {
        guard let queue,
              let index = queue.stages.firstIndex(where: { $0.id == stage.id }) else {
            return false
        }

        let destination = index + offset
        return destination >= 0 && destination < queue.stages.count
    }

    private func canBundleWithNext(_ stage: CookQueueStage) -> Bool {
        guard let queue,
              let index = queue.stages.firstIndex(where: { $0.id == stage.id }),
              index + 1 < queue.stages.count else {
            return false
        }

        return stage.status == .pending && queue.stages[index + 1].status == .pending
    }

    private func canSplit(_ stage: CookQueueStage) -> Bool {
        stage.status == .pending && stage.recipeIDs.count > 1
    }

    private func launchStage(_ stage: CookQueueStage) {
        launchingStage = stage
        Task {
            await appState.startCookQueueStage(stage.id)
            let recipes = appState.resolvedRecipes(for: stage)
            guard !recipes.isEmpty else { return }

            if recipes.count == 1, let recipe = recipes.first, CookingSession.load(recipeId: recipe.id) != nil {
                showSoloCookMode = true
            } else {
                showGathering = true
            }
        }
    }

    private func statusTitle(for status: CookQueueStageStatus) -> String {
        switch status {
        case .pending:
            return "Queued"
        case .active:
            return "Active"
        case .completed:
            return "Done"
        case .skipped:
            return "Skipped"
        }
    }

    private func statusColor(for status: CookQueueStageStatus) -> Color {
        switch status {
        case .pending:
            return AppColors.accentBlue
        case .active:
            return AppColors.primaryGreen
        case .completed:
            return AppColors.warmOrange
        case .skipped:
            return AppColors.mediumGray
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
                                mealEntryRow(title: recipe.title, subtitle: mealEntrySubtitle(for: entry), systemImage: recipe.mealType?.icon ?? "book")
                            }
                        } else if let preparedDish = entry.preparedDish {
                            NavigationLink(destination: PreparedDishDetailView(dish: preparedDish).environment(appState)) {
                                mealEntryRow(title: preparedDish.name, subtitle: mealEntrySubtitle(for: entry), systemImage: "takeoutbag.and.cup.and.straw")
                            }
                        } else {
                            mealEntryRow(title: entry.displayName, subtitle: mealEntrySubtitle(for: entry), systemImage: "fork.knife")
                        }

                        if entry.supportsPlannedServings {
                            Stepper(value: plannedServingsBinding(for: entry), in: entry.editablePlannedServingsRange) {
                                Text(entry.plannedServingsLabel ?? "1 serving planned")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.subtleText)
                            }
                        }

                        if let eatenProgressLabel = entry.eatenProgressLabel {
                            Text(eatenProgressLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(entry.isFullyEaten ? AppColors.primaryGreen : AppColors.accentBlue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background((entry.isFullyEaten ? AppColors.primaryGreen : AppColors.accentBlue).opacity(0.12))
                                .clipShape(Capsule())
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

    private func mealEntrySubtitle(for entry: MealPlanEntry) -> String? {
        let pieces: [String] = [entry.planningSubtitle, entry.mealLoggingSummary].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " • ")
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

private struct MealPlanEatenReviewDraft: Identifiable, Hashable {
    let id: UUID
    let entry: MealPlanEntry
    let candidatePreparedDishes: [PreparedDish]
    var targetEatenServings: Int
    var selectedPreparedDishID: UUID?

    init(entry: MealPlanEntry, candidatePreparedDishes: [PreparedDish]) {
        self.id = entry.id
        self.entry = entry
        self.candidatePreparedDishes = candidatePreparedDishes
        self.targetEatenServings = entry.effectiveEatenServings
        self.selectedPreparedDishID = candidatePreparedDishes.count == 1 ? candidatePreparedDishes.first?.id : nil
    }

    var plannedServings: Int {
        entry.trackingPlannedServings ?? 0
    }

    var currentEatenServings: Int {
        entry.effectiveEatenServings
    }

    var additionalServings: Int {
        Swift.max(0, targetEatenServings - currentEatenServings)
    }

    var isDirty: Bool {
        targetEatenServings > currentEatenServings
    }

    var requiresPreparedDishSelection: Bool {
        additionalServings > 0 && selectedPreparedDishID == nil
    }

    var selectedPreparedDishName: String? {
        candidatePreparedDishes.first(where: { $0.id == selectedPreparedDishID })?.name
    }

    var loggingSelection: MealPlanEatenLoggingSelection {
        MealPlanEatenLoggingSelection(
            entryID: entry.id,
            targetEatenServings: targetEatenServings,
            preparedDishID: selectedPreparedDishID
        )
    }

    var sourceSummary: String {
        "\(entry.date.formatted(date: .abbreviated, time: .omitted)) • \(entry.mealType.rawValue)"
    }

    var progressText: String {
        if targetEatenServings >= plannedServings {
            return plannedServings == 1 ? "Finished" : "Finished • \(plannedServings) of \(plannedServings) eaten"
        }
        if targetEatenServings == 0 {
            return plannedServings == 1 ? "0 of 1 eaten" : "0 of \(plannedServings) eaten"
        }
        return "\(targetEatenServings) of \(plannedServings) eaten"
    }

    var preparedFoodSelectionSummary: String {
        if let selectedPreparedDishName {
            return "Using Prepared Food: \(selectedPreparedDishName)"
        }

        if candidatePreparedDishes.isEmpty {
            return "No matching Prepared Food available"
        }

        if candidatePreparedDishes.count == 1, let name = candidatePreparedDishes.first?.name {
            return "Prepared Food: \(name)"
        }

        return "Choose 1 of \(candidatePreparedDishes.count) matching Prepared Food items"
    }
}

private struct MealPlanEatenSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let entries: [MealPlanEntry]
    let onContinue: ([MealPlanEntry]) -> Void

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var searchDebouncer = TaskDebouncer()

    private var filteredEntries: [MealPlanEntry] {
        SearchQuerySupport.filtered(entries, query: debouncedSearchText) { entry in
            [entry.displayName, entry.mealType.rawValue, entry.date.formatted(date: .abbreviated, time: .omitted)]
                .joined(separator: " ")
        }
    }

    private var selectedEntries: [MealPlanEntry] {
        entries.filter { selectedEntryIDs.contains($0.id) }
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
                        icon: "fork.knife.circle",
                        title: entries.isEmpty ? "Nothing left to log" : "No meals found",
                        message: entries.isEmpty
                            ? "Meals only show up here when they still have servings left to log and there is matching Prepared Food available right now."
                            : "Try a different search for this week’s meals."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AppList {
                        Section {
                            Text("Select meals from this week, then choose the matching Prepared Food and how many servings were actually eaten before saving once.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.subtleText)
                        }

                        ForEach(entriesByDay, id: \.date) { group in
                            Section(group.date.formatted(date: .abbreviated, time: .omitted)) {
                                ForEach(group.entries) { entry in
                                    selectionRow(for: entry)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search this week")
            .onChange(of: searchText) {
                SearchQuerySupport.schedule(text: searchText, debouncer: searchDebouncer) {
                    debouncedSearchText = $0
                }
            }
            .navigationTitle("Log Eating")
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

    private func selectionRow(for entry: MealPlanEntry) -> some View {
        let isSelected = selectedEntryIDs.contains(entry.id)
        let accent = entry.isPreparedFoodPlan ? AppColors.warmOrange : AppColors.primaryGreen

        return Button {
            if isSelected {
                selectedEntryIDs.remove(entry.id)
            } else {
                selectedEntryIDs.insert(entry.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.recipe != nil ? (entry.recipe?.mealType?.icon ?? "book") : entry.isPreparedFoodPlan ? "takeoutbag.and.cup.and.straw" : entry.mealType.icon)
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
                    Text("\(entry.mealType.rawValue) • \(entry.mealLoggingSummary ?? entry.planningSubtitle ?? "1 planned")")
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
                    Text(selectedEntries.isEmpty ? "Select meals to update" : "\(selectedEntries.count) meals selected")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.darkText)
                    Text("You’ll set eaten amounts in the next step.")
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

private struct MealPlanEatenReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState
    @Binding var drafts: [MealPlanEatenReviewDraft]
    let onSave: ([MealPlanEatenLoggingSelection]) -> Void

    private var hasChanges: Bool {
        drafts.contains(where: \.isDirty)
    }

    private var hasMissingSelections: Bool {
        drafts.contains(where: \.requiresPreparedDishSelection)
    }

    private var overdrawMessages: [String] {
        let grouped = drafts.reduce(into: [UUID: Int]()) { partialResult, draft in
            guard let preparedDishID = draft.selectedPreparedDishID else { return }
            partialResult[preparedDishID, default: 0] += draft.additionalServings
        }

        return grouped.compactMap { preparedDishID, requestedServings in
            guard requestedServings > 0, let preparedDish = appState.preparedDishById(preparedDishID) else { return nil }
            guard requestedServings > preparedDish.servingsRemaining else { return nil }
            return "\(preparedDish.name) only has \(preparedDish.servingsRemaining) servings left, but this batch would log \(requestedServings)."
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if drafts.isEmpty {
                    EmptyStateView(
                        icon: "fork.knife.circle",
                        title: "Nothing selected yet",
                        message: "Pick meals first, then set how much was eaten here."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AppList {
                        Section {
                            HStack(spacing: 10) {
                                quickApplyButton(title: "Clear All") {
                                    clearAllToZero()
                                }

                                quickApplyButton(title: "+1 To All") {
                                    applyIncrementToAll(1)
                                }

                                quickApplyButton(title: "Finish All") {
                                    setAllToFinished()
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if !overdrawMessages.isEmpty {
                            Section {
                                ForEach(overdrawMessages, id: \.self) { message in
                                    Text(message)
                                        .font(.subheadline)
                                        .foregroundStyle(AppColors.softRed)
                                }
                            }
                        }

                        Section {
                            ForEach($drafts) { $draft in
                                reviewRow($draft)
                            }
                        } header: {
                            SectionHeader(
                                title: "Selected Meals",
                                subtitle: hasChanges ? "Review the eaten amounts, then save them together." : "Set servings eaten for any meals you’re updating."
                            )
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .navigationTitle("Log Eating")
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
    }

    private func reviewRow(_ draft: Binding<MealPlanEatenReviewDraft>) -> some View {
        let accent = draft.wrappedValue.entry.isPreparedFoodPlan ? AppColors.warmOrange : AppColors.primaryGreen

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: draft.wrappedValue.entry.recipe != nil ? (draft.wrappedValue.entry.recipe?.mealType?.icon ?? "book") : draft.wrappedValue.entry.isPreparedFoodPlan ? "takeoutbag.and.cup.and.straw" : draft.wrappedValue.entry.mealType.icon)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.wrappedValue.entry.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.darkText)
                    Text(draft.wrappedValue.sourceSummary)
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                    Text(draft.wrappedValue.progressText)
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                    Text(draft.wrappedValue.preparedFoodSelectionSummary)
                        .font(.caption2)
                        .foregroundStyle(draft.wrappedValue.requiresPreparedDishSelection ? AppColors.softRed : AppColors.subtleText)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if !draft.wrappedValue.candidatePreparedDishes.isEmpty {
                    Picker("Prepared Food", selection: Binding(
                        get: { draft.wrappedValue.selectedPreparedDishID },
                        set: { draft.wrappedValue.selectedPreparedDishID = $0 }
                    )) {
                        Text("Select Prepared Food").tag(Optional<UUID>.none)
                        ForEach(draft.wrappedValue.candidatePreparedDishes) { dish in
                            Text("\(dish.name) • \(dish.servingsDisplay)").tag(Optional(dish.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }

                HStack(spacing: 8) {
                    quickEntryButton(title: "+1") {
                        draft.wrappedValue.targetEatenServings = Swift.min(draft.wrappedValue.plannedServings, draft.wrappedValue.targetEatenServings + 1)
                    }

                    quickEntryButton(title: "+2") {
                        draft.wrappedValue.targetEatenServings = Swift.min(draft.wrappedValue.plannedServings, draft.wrappedValue.targetEatenServings + 2)
                    }

                    quickEntryButton(title: "Finished") {
                        draft.wrappedValue.targetEatenServings = draft.wrappedValue.plannedServings
                    }
                }

                Stepper(value: draft.targetEatenServings, in: draft.wrappedValue.currentEatenServings...draft.wrappedValue.plannedServings) {
                    Text("Servings eaten: \(draft.wrappedValue.targetEatenServings) of \(draft.wrappedValue.plannedServings)")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var reviewSummaryBar: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasChanges ? "Ready to save eaten amounts" : "Set at least one meal to save")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.darkText)
                    Text(reviewSummaryText)
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                Spacer()

                Button {
                    onSave(drafts.map(\.loggingSelection))
                } label: {
                    Text("Save Eaten Amounts")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(hasChanges && !hasMissingSelections && overdrawMessages.isEmpty ? AppColors.primaryGreen : AppColors.mediumGray)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .disabled(!hasChanges || hasMissingSelections || !overdrawMessages.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    private var reviewSummaryText: String {
        if !overdrawMessages.isEmpty {
            return "Resolve the Prepared Food overdraw warning before saving."
        }

        if hasMissingSelections {
            return "Choose which Prepared Food item each updated meal should draw from before saving."
        }

        return "Prepared Food will decrement only for the extra eaten servings you log."
    }

    private func applyIncrementToAll(_ increment: Int) {
        for index in drafts.indices {
            drafts[index].targetEatenServings = Swift.min(drafts[index].plannedServings, drafts[index].targetEatenServings + increment)
        }
    }

    private func setAllToFinished() {
        for index in drafts.indices {
            drafts[index].targetEatenServings = drafts[index].plannedServings
        }
    }

    private func clearAllToZero() {
        for index in drafts.indices {
            drafts[index].targetEatenServings = 0
        }
    }

    private func quickApplyButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.lightGray)
                .foregroundStyle(AppColors.darkText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func quickEntryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.lightGray)
                .foregroundStyle(AppColors.darkText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
