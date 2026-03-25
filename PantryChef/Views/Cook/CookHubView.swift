import SwiftUI

struct CookHubView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var resumeRecipe: Recipe?
    @State private var launchingStage: CookQueueStage?
    @State private var sourceSearchText = ""
    @State private var debouncedSourceSearchText = ""
    @State private var sourceSearchDebouncer = TaskDebouncer()
    @State private var showGathering = false
    @State private var showSoloCookMode = false
    @State private var showMultiCookMode = false
    @State private var showMultiCookSelection = false
    @State private var showMealPlanQueueFlow = false
    @State private var showNoPlannedMealsAlert = false
    @State private var showRecipeLibraryDrawer = false
    @State private var queueDraft = CookQueueDraft()

    private var launchingRecipes: [Recipe] {
        guard let launchingStage else { return [] }
        return appState.resolvedRecipes(for: launchingStage)
    }

    private var queueContext: (queueID: UUID, stageID: UUID)? {
        guard let launchingStage else { return nil }
        return appState.cookQueueContext(for: launchingStage.id)
    }

    private var queueSummary: String {
        guard let queue = appState.cookQueue else {
            return "Build a serial or parallel cooking run from your meal plan and recipes."
        }

        return "\(queue.stages.count) \(queue.stages.count == 1 ? "stage" : "stages") remaining"
    }

    private var currentWeekPlannedRecipeEntries: [MealPlanEntry] {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        return appState.plannedEntries(forWeekStarting: weekStart)
            .filter { $0.scaledRecipeForPlanning != nil }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.mealType.rawValue < rhs.mealType.rawValue
                }
                return lhs.date < rhs.date
            }
    }

    private var recipeLibrarySources: [CookRecipeSource] {
        var seenIDs: Set<UUID> = []
        return appState.allRecipes
            .filter { recipe in
                seenIDs.insert(recipe.id).inserted
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { recipe in
                CookRecipeSource(
                    id: "library-\(recipe.id.uuidString)",
                    recipeID: recipe.id,
                    displayTitle: recipe.title,
                    subtitle: recipe.source.label,
                    detail: "\(recipe.totalTimeDisplay) • \(recipe.steps.count) steps",
                    sourceEntryIDs: [],
                    badgeTitle: recipe.source.isUserRecipe ? "Library" : recipe.source.label,
                    badgeColor: recipe.source.isUserRecipe ? PCColors.teal : PCColors.expiring
                )
            }
    }

    private var filteredRecipeLibrarySources: [CookRecipeSource] {
        filterSources(recipeLibrarySources)
    }

    private var allRecipeSources: [CookRecipeSource] {
        recipeLibrarySources
    }

    private var recipeLibraryDrawerWidth: CGFloat {
        horizontalSizeClass == .regular ? 286 : 208
    }

    private var recipeDrawerHandleWidth: CGFloat {
        horizontalSizeClass == .regular ? 42 : 28
    }

    private var mainContentTrailingInset: CGFloat {
        guard horizontalSizeClass == .regular, showRecipeLibraryDrawer else { return 0 }
        return recipeLibraryDrawerWidth + 8
    }

    var body: some View {
        AppScreen("cook.screen") {
            ZStack(alignment: .trailing) {
                AppScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        workspaceHeader

                        if appState.activeCooks.hasActiveSessions {
                            activeSessionsSection
                        }

                        queueBuilderSection
                    }
                    .padding()
                    .padding(.trailing, mainContentTrailingInset)
                }

                if showRecipeLibraryDrawer {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeRecipeLibraryDrawer()
                        }
                }

                recipeLibraryDrawer
            }
            .navigationTitle("Cook")
            .toolbar {
                if appState.cookQueue != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear Queue") {
                            Task {
                                await appState.clearCookQueue()
                            }
                        }
                        .foregroundStyle(PCColors.expired)
                    }
                }
            }
            .sheet(isPresented: $showMultiCookSelection) {
                MultiCookSelectionView()
                    .environment(appState)
            }
            .sheet(isPresented: $showMealPlanQueueFlow) {
                MealPlanCookQueueSelectionView(entries: currentWeekPlannedRecipeEntries) { workspace in
                    Task {
                        await appState.appendCookQueueStages(workspace.buildStages())
                    }
                }
            }
            .alert("Nothing To Add", isPresented: $showNoPlannedMealsAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("There are no planned recipe meals available to import into Cook right now.")
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
            .fullScreenCover(item: $resumeRecipe) { recipe in
                let session = CookingSession.load(recipeId: recipe.id)
                let stepIndex = session?.currentStepIndex ?? 0
                let queueContext = session.flatMap { appState.cookQueueContext(for: $0) }
                CookModeView(
                    recipe: recipe,
                    resumeAtStep: stepIndex,
                    isResuming: true,
                    queueID: queueContext?.queueID,
                    queueStageID: queueContext?.stageID
                )
                .environment(appState)
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
            .onAppear {
                syncQueueDraft()
                appState.activeCooks.refresh()
            }
            .onChange(of: appState.cookQueueRevision) { _, _ in
                syncQueueDraft()
            }
        }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cooking Workspace")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(PCColors.textPrimary)

            Text("Import planned meals from Meal Plan, or open the recipe drawer on the right and drag recipes into the queue board without losing your place.")
                .font(.subheadline)
                .foregroundStyle(PCColors.textSecondary)

            HStack(spacing: 12) {
                workspaceMetric(title: "Active", value: "\(appState.activeCooks.count)", color: PCColors.expiring)
                workspaceMetric(title: "Queue", value: "\(appState.cookQueue?.stages.count ?? 0)", color: PCColors.info)
                workspaceMetric(title: "Up Next", value: queueSummaryValue, color: PCColors.accent)
            }

            HStack(spacing: 12) {
                Button {
                    if currentWeekPlannedRecipeEntries.isEmpty {
                        showNoPlannedMealsAlert = true
                    } else {
                        showMealPlanQueueFlow = true
                    }
                } label: {
                    Label("Add From Meal Plan", systemImage: "calendar.badge.plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(PCColors.info)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    showMultiCookSelection = true
                } label: {
                    Label("Multi-Cook Search", systemImage: "magnifyingglass")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(PCColors.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            if appState.cookQueue?.currentStage != nil {
                Button {
                    launchCurrentStage()
                } label: {
                    Label("Start Next Stage", systemImage: "play.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(PCColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding()
        .pcCard()
    }

    private var activeSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Active Sessions",
                subtitle: "Resume voice-guided cooks without hunting through other screens."
            )

            ForEach(appState.activeCooks.activeSessions) { session in
                Button {
                    if let recipe = appState.allRecipes.first(where: { $0.id == session.recipeId }) {
                        resumeRecipe = recipe
                    }
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(PCColors.expiring.opacity(0.15))
                                .frame(width: 46, height: 46)
                            Image(systemName: "frying.pan.fill")
                                .foregroundStyle(PCColors.expiring)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.recipeName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(PCColors.textPrimary)

                            Text("Step \(session.currentStepIndex + 1) of \(session.totalSteps)")
                                .font(.caption)
                                .foregroundStyle(PCColors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(PCColors.textTertiary)
                    }
                    .padding()
                    .background(PCColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var queueBuilderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Queue Builder",
                subtitle: appState.cookQueue == nil ? "Import from Meal Plan or drag from Recipe Library into this board." : queueSummary
            )

            if queueDraft.stages.isEmpty {
                emptyQueueBoard
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(queueDraft.stages.enumerated()), id: \.element.id) { index, stage in
                        stageInsertionZone(afterStageID: index == 0 ? nil : queueDraft.stages[index - 1].id)
                        stageCard(stage)
                    }

                    stageInsertionZone(afterStageID: queueDraft.stages.last?.id)
                }
            }
        }
    }

    private var emptyQueueBoard: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(PCColors.cardBackground)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.title)
                        .foregroundStyle(PCColors.info)
                    Text("Cook queue is empty")
                        .font(.headline)
                        .foregroundStyle(PCColors.textPrimary)
                    Text("Use Add From Meal Plan or drag a recipe from the library drawer and drop it here to create the first stage.")
                        .font(.subheadline)
                        .foregroundStyle(PCColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Label("Drop Here To Create Stage", systemImage: "arrow.down.to.line")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.info)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(PCColors.info.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(.vertical, 36)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [8, 8]))
                    .foregroundStyle(PCColors.info.opacity(0.45))
            }
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items: items, placement: .afterStage(nil))
            }
    }

    private var recipeLibraryDrawer: some View {
        Group {
            if showRecipeLibraryDrawer {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recipe Library")
                                .font(.headline)
                                .foregroundStyle(PCColors.textPrimary)
                            Text("Search, browse, and drag recipes into the queue without scrolling away from the board.")
                                .font(.caption)
                                .foregroundStyle(PCColors.textSecondary)
                        }

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                showRecipeLibraryDrawer = false
                            }
                        } label: {
                            Image(systemName: "sidebar.right")
                                .font(.title3)
                                .foregroundStyle(PCColors.info)
                                .frame(width: 36, height: 36)
                                .background(PCColors.info.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }

                    AppSearchField(
                        "Search recipe library",
                        text: $sourceSearchText,
                        onTextChange: { text in
                            SearchQuerySupport.schedule(text: text, debouncer: sourceSearchDebouncer) {
                                debouncedSourceSearchText = $0
                            }
                        }
                    )

                    if filteredRecipeLibrarySources.isEmpty {
                        EmptyStateView(
                            icon: "book.closed",
                            title: "No recipes found",
                            message: recipeLibrarySources.isEmpty
                                ? "Your recipe library is empty right now."
                                : "Try a different search query for the recipe drawer."
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(filteredRecipeLibrarySources) { source in
                                    recipeLibraryDrawerTile(source)
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
                .padding(16)
                .frame(width: recipeLibraryDrawerWidth)
                .frame(maxHeight: .infinity)
                .background(PCColors.cardBackground)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 0, topTrailingRadius: 0))
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                .padding(.vertical, 4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        showRecipeLibraryDrawer = true
                    }
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "books.vertical.fill")
                            .font(.title3)

                        Text("Recipes")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .fixedSize()
                            .rotationEffect(.degrees(-90))
                            .frame(height: horizontalSizeClass == .regular ? 92 : 82)
                    }
                    .foregroundStyle(PCColors.info)
                    .frame(width: recipeDrawerHandleWidth)
                    .padding(.vertical, horizontalSizeClass == .regular ? 14 : 12)
                    .background(PCColors.cardBackground)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 0, topTrailingRadius: 0))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 18)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private func workspaceMetric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(PCColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func recipeLibraryDrawerTile(_ source: CookRecipeSource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(source.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PCColors.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(source.badgeTitle)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(source.badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(source.badgeColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(source.subtitle)
                .font(.caption)
                .foregroundStyle(PCColors.textSecondary)

            Text(source.detail)
                .font(.caption2)
                .foregroundStyle(PCColors.textSecondary)

            HStack(spacing: 6) {
                Image(systemName: "hand.draw.fill")
                    .font(.caption2)
                Text("Drag To Queue")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(PCColors.info)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PCColors.fillTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(PCColors.info.opacity(0.14), lineWidth: 1)
        }
        .onDrag {
            let provider = NSItemProvider(object: CookDragPayload.source(source.id).rawValue as NSString)
            DispatchQueue.main.async {
                closeRecipeLibraryDrawer()
            }
            return provider
        }
    }

    private func stageCard(_ stage: CookQueueDraft.Stage) -> some View {
        let actualStage = appState.cookQueue?.stages.first(where: { $0.id == stage.id })
        let resolvedRecipes = actualStage.map(appState.resolvedRecipes(for:)) ?? []
        let hasActiveSession = resolvedRecipes.contains { CookingSession.load(recipeId: $0.id) != nil }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.recipeTiles.count > 1 ? "Parallel Stage" : "Solo Stage")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                    Text(stageStatusSubtitle(stage))
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }

                Spacer()

                Text(stage.statusTitle)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(stage.statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(stage.statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            FlowLayout(spacing: 10) {
                ForEach(stage.recipeTiles) { tile in
                    recipeTile(tile, in: stage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(PCColors.fillTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items: items, placement: .intoStage(stage.id))
            }

            HStack(spacing: 10) {
                if let actualStage, stage.isEditable {
                    Button {
                        launchStage(actualStage)
                    } label: {
                        Text(hasActiveSession ? "Resume" : "Start")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(PCColors.accent)
                            .clipShape(Capsule())
                    }

                    Button {
                        Task {
                            await appState.skipCookQueueStage(actualStage.id)
                        }
                    } label: {
                        Text("Skip")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(PCColors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(PCColors.fillTertiary)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                if stage.isEditable {
                    Button {
                        removeStage(stage.id)
                    } label: {
                        Text("Remove Stage")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(PCColors.expired)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(PCColors.expired.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .background(PCColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func recipeTile(_ tile: CookQueueDraft.RecipeTile, in stage: CookQueueDraft.Stage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tile.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                        .lineLimit(2)

                    if let recipe = appState.allRecipes.first(where: { $0.id == tile.recipeID }) {
                        Text(recipe.totalTimeDisplay)
                            .font(.caption2)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                if stage.isEditable {
                    Button {
                        removeTile(tile.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(PCColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(stage.recipeTiles.count > 1 ? "Drop onto another row to make this serial." : "Drop onto a row to make it parallel.")
                .font(.caption2)
                .foregroundStyle(PCColors.textSecondary)
        }
        .padding(12)
        .frame(width: 170, alignment: .leading)
        .background(PCColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(PCColors.textTertiary.opacity(0.18), lineWidth: 1)
        }
        .draggable(CookDragPayload.tile(tile.id).rawValue)
    }

    private func stageInsertionZone(afterStageID: UUID?) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
            .foregroundStyle(PCColors.info.opacity(0.45))
            .frame(height: 44)
            .overlay {
                Label("Drop Here For Next Stage", systemImage: "arrow.down.to.line")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(PCColors.info)
            }
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items: items, placement: .afterStage(afterStageID))
            }
    }

    private func stageStatusSubtitle(_ stage: CookQueueDraft.Stage) -> String {
        if stage.recipeTiles.count > 1 {
            return "These recipes will cook in parallel."
        }
        return "This recipe will cook as its own stage."
    }

    private var queueSummaryValue: String {
        guard let currentStage = appState.cookQueue?.currentStage else {
            return "None"
        }
        return currentStage.isParallelBatch ? "Batch" : "Solo"
    }

    private func syncQueueDraft() {
        queueDraft = CookQueueDraft(queue: appState.cookQueue)
    }

    private func launchCurrentStage() {
        guard let stage = appState.cookQueue?.currentStage else { return }
        launchStage(stage)
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

    private func removeStage(_ stageID: UUID) {
        queueDraft.removeStage(stageID)
        persistQueueDraft()
    }

    private func removeTile(_ tileID: UUID) {
        queueDraft.removeTile(tileID)
        persistQueueDraft()
    }

    private func handleDrop(items: [String], placement: CookQueueDropPlacement) -> Bool {
        guard let item = items.first,
              let payload = CookDragPayload(rawValue: item) else {
            return false
        }

        let didApply: Bool
        switch payload {
        case .tile(let tileID):
            didApply = queueDraft.moveTile(tileID, to: placement)
        case .source(let sourceID):
            guard let source = allRecipeSources.first(where: { $0.id == sourceID }) else {
                return false
            }
            didApply = queueDraft.insertSource(source, to: placement)
        }

        guard didApply else { return false }
        persistQueueDraft()
        return true
    }

    private func filterSources(_ sources: [CookRecipeSource]) -> [CookRecipeSource] {
        SearchQuerySupport.filtered(sources, query: debouncedSourceSearchText) { source in
            [source.displayTitle, source.subtitle, source.detail, source.badgeTitle].joined(separator: " ")
        }
    }

    private func persistQueueDraft() {
        let updatedStages = queueDraft.makeStages()
        Task {
            await appState.replaceCookQueueStages(updatedStages)
        }
    }

    private func closeRecipeLibraryDrawer() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            showRecipeLibraryDrawer = false
        }
    }
}

private struct MealPlanCookQueueSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let entries: [MealPlanEntry]
    let onSave: (MealPlanCookQueueReviewWorkspace) -> Void

    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var searchDebouncer = TaskDebouncer()
    @State private var showingReview = false
    @State private var reviewWorkspace = MealPlanCookQueueReviewWorkspace(entries: [])

    private var filteredEntries: [MealPlanEntry] {
        SearchQuerySupport.filtered(entries, query: debouncedSearchText) { entry in
            [entry.displayName, entry.mealType.rawValue, entry.date.formatted(date: .abbreviated, time: .omitted), entry.planningSubtitle ?? ""]
                .joined(separator: " ")
        }
        .sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.mealType.rawValue < rhs.mealType.rawValue
            }
            return lhs.date < rhs.date
        }
    }

    private var selectedEntries: [MealPlanEntry] {
        entries.filter { selectedEntryIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.mealType.rawValue < rhs.mealType.rawValue
                }
                return lhs.date < rhs.date
            }
    }

    private var entriesByDay: [(date: Date, entries: [MealPlanEntry])] {
        let grouped = Dictionary(grouping: filteredEntries) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { date in
            (date, grouped[date, default: []])
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if filteredEntries.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.exclamationmark",
                        title: entries.isEmpty ? "No recipes planned this week" : "No meals found",
                        message: entries.isEmpty
                            ? "Only planned recipe meals can be imported into the cook queue from here."
                            : "Try a different search for your planned recipes."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AppList {
                        Section {
                            Text("Select the meal-plan recipes you want to add to the cook queue. Dates stay visible here so you can import the right meals in the right order.")
                                .font(.subheadline)
                                .foregroundStyle(PCColors.textSecondary)
                        }

                        ForEach(entriesByDay, id: \.date) { group in
                            Section(group.date.formatted(date: .abbreviated, time: .omitted)) {
                                ForEach(group.entries) { entry in
                                    queueSelectionRow(entry)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search planned recipes")
            .onChange(of: searchText) {
                SearchQuerySupport.schedule(text: searchText, debouncer: searchDebouncer) {
                    debouncedSearchText = $0
                }
            }
            .navigationTitle("Add From Meal Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !selectedEntries.isEmpty {
                        Button {
                            let sorted = selectedEntries.sorted { lhs, rhs in
                                if lhs.date == rhs.date {
                                    return lhs.mealType.rawValue < rhs.mealType.rawValue
                                }
                                return lhs.date < rhs.date
                            }
                            reviewWorkspace = MealPlanCookQueueReviewWorkspace(entries: sorted)
                            showingReview = true
                        } label: {
                            HStack(spacing: 4) {
                                Text("Review")
                                Text("\(selectedEntries.count)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PCColors.accent)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedEntries.isEmpty {
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(selectedEntries.count) meals selected")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(PCColors.textPrimary)
                                Text("Recipe scaling and meal-plan links carry into the queue.")
                                    .font(.caption)
                                    .foregroundStyle(PCColors.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    .background(.ultraThinMaterial)
                }
            }
            .navigationDestination(isPresented: $showingReview) {
                MealPlanCookQueueReviewView(workspace: $reviewWorkspace) { workspace in
                    onSave(workspace)
                    dismiss()
                }
            }
        }
    }

    private func queueSelectionRow(_ entry: MealPlanEntry) -> some View {
        let isSelected = selectedEntryIDs.contains(entry.id)

        return Button {
            if isSelected {
                selectedEntryIDs.remove(entry.id)
            } else {
                selectedEntryIDs.insert(entry.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.recipe?.mealType?.icon ?? entry.mealType.icon)
                    .font(.title3)
                    .foregroundStyle(PCColors.accent)
                    .frame(width: 40, height: 40)
                    .background(PCColors.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                    Text("\(entry.mealType.rawValue) • \(entry.planningSubtitle ?? "Planned")")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? PCColors.accent : PCColors.textTertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

struct MealPlanCookQueueReviewView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var workspace: MealPlanCookQueueReviewWorkspace
    let onSave: (MealPlanCookQueueReviewWorkspace) -> Void

    private var canSave: Bool {
        !workspace.buildStages().isEmpty
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    draftSidebar
                } detail: {
                    draftDetail
                }
            } else {
                VStack(spacing: 0) {
                    draftSidebar
                    Divider()
                    draftDetail
                }
            }
        }
        .navigationTitle("Review Queue")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onSave(workspace)
                } label: {
                    Text("Add to Queue")
                }
                .disabled(!canSave)
            }
        }
        .safeAreaInset(edge: .bottom) {
            summaryBar
        }
    }

    private var draftSidebar: some View {
        AppList {
            Section {
                Text("Review each selected meal, keep or remove it, and decide whether it starts a new stage or cooks in parallel with the previous one.")
                    .font(.subheadline)
                    .foregroundStyle(PCColors.textSecondary)
            }

            Section {
                ForEach(workspace.drafts) { draft in
                    draftRow(draft)
                }
            } header: {
                SectionHeader(
                    title: workspace.projectedStageCount == 1 ? "1 Queue Stage" : "\(workspace.projectedStageCount) Queue Stages",
                    subtitle: "\(workspace.includedRecipeCount) meals included • Estimated cook time: \(workspace.estimatedTotalTimeText)"
                )
                .padding(.top, 8)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PCColors.background)
    }

    @ViewBuilder
    private var draftDetail: some View {
        if let focusedDraft = workspace.focusedDraft {
            AppScrollView {
                draftEditor(binding(for: focusedDraft))
                    .padding()
            }
            .background(PCColors.background)
        } else {
            EmptyStateView(
                icon: "list.bullet.rectangle.portrait",
                title: "Nothing selected",
                message: "Choose a meal from the list to review its queue placement."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PCColors.background)
        }
    }

    private func draftRow(_ draft: MealPlanCookQueueReviewDraft) -> some View {
        let isFocused = workspace.focusedDraftID == draft.id

        return Button {
            workspace.focusedDraftID = draft.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: draft.entry.recipe?.mealType?.icon ?? draft.entry.mealType.icon)
                    .font(.title3)
                    .foregroundStyle(PCColors.accent)
                    .frame(width: 40, height: 40)
                    .background(PCColors.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.entry.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                    Text(draft.sourceSummary)
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                    Text(draft.isIncluded ? draft.stagePlacement.title : "Removed from queue")
                        .font(.caption2)
                        .foregroundStyle(draft.isIncluded ? PCColors.textSecondary : PCColors.expired)
                }

                Spacer()

                if isFocused {
                    Image(systemName: "chevron.right.circle.fill")
                        .foregroundStyle(PCColors.info)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func draftEditor(_ draft: Binding<MealPlanCookQueueReviewDraft>) -> some View {
        let canCookWithPrevious = workspace.canDraftCookWithPrevious(draft.wrappedValue.id)

        return VStack(alignment: .leading, spacing: 16) {
            Text(draft.wrappedValue.entry.displayName)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(PCColors.textPrimary)

            Text("\(draft.wrappedValue.sourceSummary) • \(draft.wrappedValue.entry.planningSubtitle ?? "Planned")")
                .font(.subheadline)
                .foregroundStyle(PCColors.textSecondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Queue Inclusion")
                    .font(.headline)
                    .foregroundStyle(PCColors.textPrimary)

                Toggle("Include this meal in the cook queue", isOn: Binding(
                    get: { draft.wrappedValue.isIncluded },
                    set: { newValue in
                        var updated = draft.wrappedValue
                        updated.isIncluded = newValue
                        workspace.updateDraft(updated)
                    }
                ))
            }
            .padding()
            .background(PCColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 10) {
                Text("Stage Placement")
                    .font(.headline)
                    .foregroundStyle(PCColors.textPrimary)

                if canCookWithPrevious {
                    Picker("Stage Placement", selection: Binding(
                        get: { draft.wrappedValue.stagePlacement },
                        set: { newValue in
                            var updated = draft.wrappedValue
                            updated.stagePlacement = newValue
                            workspace.updateDraft(updated)
                        }
                    )) {
                        ForEach(CookQueueStagePlacement.allCases, id: \.self) { placement in
                            Text(placement.title).tag(placement)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(draft.wrappedValue.stagePlacement.subtitle)
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                } else {
                    Text("This meal starts a new stage because nothing earlier in the selection is currently included.")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }
            .padding()
            .background(PCColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var summaryBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(canSave ? "Add \(workspace.projectedStageCount) stages to cook queue" : "Include at least one meal to continue")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                    Text("You can still start, skip, remove, or rearrange stages later from Cook.")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private func binding(for draft: MealPlanCookQueueReviewDraft) -> Binding<MealPlanCookQueueReviewDraft> {
        Binding(
            get: { workspace.drafts.first(where: { $0.id == draft.id }) ?? draft },
            set: { updatedDraft in
                workspace.updateDraft(updatedDraft)
            }
        )
    }
}

private enum CookDragPayload: RawRepresentable {
    case tile(UUID)
    case source(String)

    init?(rawValue: String) {
        if rawValue.hasPrefix("tile:"),
           let id = UUID(uuidString: String(rawValue.dropFirst(5))) {
            self = .tile(id)
            return
        }

        if rawValue.hasPrefix("source:") {
            self = .source(String(rawValue.dropFirst(7)))
            return
        }

        return nil
    }

    var rawValue: String {
        switch self {
        case .tile(let id):
            return "tile:\(id.uuidString)"
        case .source(let sourceID):
            return "source:\(sourceID)"
        }
    }
}

private struct CookRecipeSource: Identifiable, Equatable {
    let id: String
    let recipeID: UUID
    let displayTitle: String
    let subtitle: String
    let detail: String
    let sourceEntryIDs: [UUID]
    let badgeTitle: String
    let badgeColor: Color
}

private enum CookQueueDropPlacement {
    case intoStage(UUID)
    case afterStage(UUID?)
}

private struct CookQueueDraft: Equatable {
    struct RecipeTile: Identifiable, Equatable {
        let id: UUID
        let recipeID: UUID
        let displayTitle: String
        let sourceMealPlanEntryIDs: [UUID]
    }

    struct Stage: Identifiable, Equatable {
        let id: UUID
        let addedAt: Date
        var status: CookQueueStageStatus
        var recipeTiles: [RecipeTile]

        var isEditable: Bool {
            status == .pending
        }

        var statusTitle: String {
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

        var statusColor: Color {
            switch status {
            case .pending:
                return PCColors.info
            case .active:
                return PCColors.accent
            case .completed:
                return PCColors.expiring
            case .skipped:
                return PCColors.textTertiary
            }
        }
    }

    var stages: [Stage] = []

    init() { }

    init(queue: CookQueue?) {
        guard let queue else { return }

        self.stages = queue.stages.map { stage in
            Stage(
                id: stage.id,
                addedAt: stage.addedAt,
                status: stage.status,
                recipeTiles: zip(stage.recipeIDs, stage.recipeTitleSnapshots).map { recipeID, title in
                    RecipeTile(
                        id: UUID(),
                        recipeID: recipeID,
                        displayTitle: title,
                        sourceMealPlanEntryIDs: stage.sourceMealPlanEntryIDs
                    )
                }
            )
        }
    }

    mutating func removeStage(_ stageID: UUID) {
        stages.removeAll { $0.id == stageID }
    }

    mutating func removeTile(_ tileID: UUID) {
        guard let location = tileLocation(for: tileID) else { return }
        stages[location.stageIndex].recipeTiles.remove(at: location.tileIndex)
        stages.removeAll { $0.recipeTiles.isEmpty }
    }

    mutating func moveTile(_ tileID: UUID, to placement: CookQueueDropPlacement) -> Bool {
        guard let sourceLocation = tileLocation(for: tileID),
              stages[sourceLocation.stageIndex].isEditable else {
            return false
        }

        let tile = stages[sourceLocation.stageIndex].recipeTiles.remove(at: sourceLocation.tileIndex)
        if stages[sourceLocation.stageIndex].recipeTiles.isEmpty {
            stages.remove(at: sourceLocation.stageIndex)
        }

        switch placement {
        case .intoStage(let stageID):
            guard let destinationIndex = stages.firstIndex(where: { $0.id == stageID }),
                  stages[destinationIndex].isEditable else {
                restore(tile, at: sourceLocation)
                return false
            }

            if stages[destinationIndex].recipeTiles.contains(where: { $0.id == tile.id }) {
                return false
            }

            stages[destinationIndex].recipeTiles.append(tile)
            return true

        case .afterStage(let stageID):
            let insertIndex: Int
            if let stageID,
               let destinationIndex = stages.firstIndex(where: { $0.id == stageID }) {
                insertIndex = destinationIndex + 1
            } else {
                insertIndex = 0
            }

            let newStage = Stage(
                id: UUID(),
                addedAt: Date(),
                status: .pending,
                recipeTiles: [tile]
            )
            stages.insert(newStage, at: min(insertIndex, stages.count))
            return true
        }
    }

    mutating func insertSource(_ source: CookRecipeSource, to placement: CookQueueDropPlacement) -> Bool {
        let tile = RecipeTile(
            id: UUID(),
            recipeID: source.recipeID,
            displayTitle: source.displayTitle,
            sourceMealPlanEntryIDs: source.sourceEntryIDs
        )

        switch placement {
        case .intoStage(let stageID):
            guard let destinationIndex = stages.firstIndex(where: { $0.id == stageID }),
                  stages[destinationIndex].isEditable else {
                return false
            }
            stages[destinationIndex].recipeTiles.append(tile)
            return true

        case .afterStage(let stageID):
            let insertIndex: Int
            if let stageID,
               let destinationIndex = stages.firstIndex(where: { $0.id == stageID }) {
                insertIndex = destinationIndex + 1
            } else {
                insertIndex = 0
            }

            let newStage = Stage(
                id: UUID(),
                addedAt: Date(),
                status: .pending,
                recipeTiles: [tile]
            )
            stages.insert(newStage, at: min(insertIndex, stages.count))
            return true
        }
    }

    func makeStages() -> [CookQueueStage] {
        stages.compactMap { stage in
            guard !stage.recipeTiles.isEmpty else { return nil }
            let sourceEntryIDs = Array(Set(stage.recipeTiles.flatMap(\.sourceMealPlanEntryIDs)))
            return CookQueueStage(
                id: stage.id,
                recipeIDs: stage.recipeTiles.map(\.recipeID),
                recipeTitleSnapshots: stage.recipeTiles.map(\.displayTitle),
                sourceMealPlanEntryIDs: sourceEntryIDs,
                addedAt: stage.addedAt,
                status: stage.status
            )
        }
    }

    private func tileLocation(for tileID: UUID) -> (stageIndex: Int, tileIndex: Int)? {
        for stageIndex in stages.indices {
            if let tileIndex = stages[stageIndex].recipeTiles.firstIndex(where: { $0.id == tileID }) {
                return (stageIndex, tileIndex)
            }
        }
        return nil
    }

    private mutating func restore(_ tile: RecipeTile, at location: (stageIndex: Int, tileIndex: Int)) {
        guard stages.indices.contains(location.stageIndex) else {
            let restoredStage = Stage(id: UUID(), addedAt: Date(), status: .pending, recipeTiles: [tile])
            stages.insert(restoredStage, at: min(location.stageIndex, stages.count))
            return
        }

        let safeIndex = min(location.tileIndex, stages[location.stageIndex].recipeTiles.count)
        stages[location.stageIndex].recipeTiles.insert(tile, at: safeIndex)
    }
}