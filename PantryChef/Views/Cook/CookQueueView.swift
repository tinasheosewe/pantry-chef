import SwiftUI
struct CookQueueView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState

    @State private var launchingStage: CookQueueStage?
    @State private var showGathering = false
    @State private var resumingSession: CookingSession?
    @State private var showEndOtherCookAlert = false
    @State private var pendingLaunchStage: CookQueueStage?

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
                    ScrollView {
                        LazyVStack(spacing: PCTokens.spacingMD) {
                            // Active cook banner
                            if let session = appState.activeCooks.activeSessions.first {
                                activeCookBanner(session)
                                    .padding(.horizontal)
                                    .padding(.top, PCTokens.spacingSM)
                            }

                            Text("Queue recipes or meal-plan meals into solo or parallel stages. Finish a stage to unlock the next one without losing your place.")
                                .font(.subheadline)
                                .foregroundStyle(PCColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.top, PCTokens.spacingSM)

                            VStack(alignment: .leading, spacing: PCTokens.spacingSM) {
                                let pendingStages = queue.stages.filter { $0.status == .pending }
                                SectionHeader(
                                    title: queue.name,
                                    subtitle: "\(pendingStages.count) \(pendingStages.count == 1 ? "stage" : "stages") queued"
                                )
                                .padding(.horizontal)

                                ForEach(pendingStages) { stage in
                                    queueStageRow(stage)
                                        .padding(PCTokens.cardPadding)
                                        .pcCard()
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.bottom, PCTokens.spacingLG)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if queue != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear") {
                            Task {
                                await appState.clearCookQueue()
                            }
                        }
                        .foregroundStyle(PCColors.expired)
                    }
                }
            }
            .alert("End Current Cook?", isPresented: $showEndOtherCookAlert) {
                Button("End & Start New", role: .destructive) {
                    appState.activeCooks.endAllSessions()
                    if let stage = pendingLaunchStage {
                        pendingLaunchStage = nil
                        performLaunchStage(stage)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingLaunchStage = nil
                }
            } message: {
                Text("You already have an active cooking session. End it to start a new one.")
            }
            .sheet(isPresented: $showGathering) {
                IngredientGatheringView(recipes: launchingRecipes) {
                    if launchingRecipes.count > 1 {
                        let blocks = MultiRecipeScheduler.schedule(recipes: launchingRecipes)
                        MultiCookModeView(
                            recipes: launchingRecipes,
                            blocks: blocks,
                            queueID: queueContext?.queueID,
                            queueStageID: queueContext?.stageID
                        )
                        .environment(appState)
                    } else if let recipe = launchingRecipes.first {
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
            }
            .onDisappear {
                launchingStage = nil
            }
            .fullScreenCover(item: $resumingSession) { session in
                if let recipe = appState.allRecipes.first(where: { $0.id == session.recipeId }) {
                    CookModeView(
                        recipe: recipe,
                        resumeAtStep: session.currentStepIndex,
                        isResuming: true,
                        queueID: session.queueId,
                        queueStageID: session.queueStageId
                    )
                    .environment(appState)
                }
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
                    .foregroundStyle(stage.isParallelBatch ? PCColors.info : PCColors.accent)
                    .frame(width: 40, height: 40)
                    .background((stage.isParallelBatch ? PCColors.info : PCColors.accent).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                    Text(stage.subtitle)
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                    if !recipes.isEmpty {
                        Text(recipes.map(\.totalTimeDisplay).joined(separator: " • "))
                            .font(.caption2)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                    if !canStart {
                        Text("One or more recipes in this stage can no longer be found.")
                            .font(.caption2)
                            .foregroundStyle(PCColors.expired)
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
                    Button {
                        launchStage(stage)
                    } label: {
                        Text(hasActiveSession ? "Resume" : "Start")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(canStart ? PCColors.accent : PCColors.textTertiary)
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
                            .background(PCColors.fillTertiary)
                            .foregroundStyle(PCColors.textPrimary)
                            .clipShape(Capsule())
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
                        .background(PCColors.fillTertiary)
                        .foregroundStyle(PCColors.textPrimary)
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
                        .background(PCColors.expired.opacity(0.12))
                        .foregroundStyle(PCColors.expired)
                        .clipShape(Capsule())
                }
            }
        }
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
        let stageRecipeIDs = Set(stage.recipeIDs)
        let hasConflict = appState.activeCooks.activeSessions.contains { !stageRecipeIDs.contains($0.recipeId) }
        if hasConflict {
            pendingLaunchStage = stage
            showEndOtherCookAlert = true
            return
        }
        performLaunchStage(stage)
    }

    private func performLaunchStage(_ stage: CookQueueStage) {
        launchingStage = stage
        Task {
            await appState.startCookQueueStage(stage.id)
            let recipes = appState.resolvedRecipes(for: stage)
            guard !recipes.isEmpty else { return }

            if recipes.count == 1, let recipe = recipes.first,
               let session = CookingSession.load(recipeId: recipe.id) {
                resumingSession = session
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
            return PCColors.info
        case .active:
            return PCColors.accent
        case .completed:
            return PCColors.expiring
        case .skipped:
            return PCColors.textTertiary
        }
    }

    @ViewBuilder
    private func activeCookBanner(_ session: CookingSession) -> some View {
        let stepProgress = "Step \(session.currentStepIndex + 1) of \(session.totalSteps)"

        Button {
            resumingSession = session
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(PCColors.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.recipeName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                    Text(stepProgress)
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }

                Spacer()

                Text("Continue")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(PCColors.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .padding(PCTokens.cardPadding)
            .background(PCColors.accent.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: PCTokens.cornerRadius)
                    .strokeBorder(PCColors.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

