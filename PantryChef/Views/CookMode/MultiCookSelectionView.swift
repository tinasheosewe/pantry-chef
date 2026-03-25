import SwiftUI

// MARK: - Multi-Cook Selection View
//
// Allows the user to select 2+ recipes to cook simultaneously.
// Shows the scheduler preview with time savings estimate.

struct MultiCookSelectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRecipeIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchDebouncer = TaskDebouncer()
    @State private var showGathering = false
    @State private var showMultiCookMode = false
    @State private var scheduleSummary: ScheduleSummary?

    private var availableRecipes: [Recipe] {
        var seenIDs: Set<UUID> = []
        return appState.allRecipes.filter { recipe in
            seenIDs.insert(recipe.id).inserted
        }
    }

    private var filteredRecipes: [Recipe] {
        SearchQuerySupport.filtered(availableRecipes, query: debouncedSearchText) { recipe in
            [recipe.title, recipe.source.label, recipe.totalTimeDisplay].joined(separator: " ")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                schedulePreview

                AppSearchField(
                    "Search recipes to cook together",
                    text: $searchText,
                    onTextChange: { text in
                        SearchQuerySupport.schedule(text: text, debouncer: searchDebouncer) {
                            debouncedSearchText = $0
                        }
                    }
                )
                .padding(.horizontal)
                .padding(.top, 12)

                AppList {
                    Section {
                        ForEach(filteredRecipes) { recipe in
                            Button {
                                toggleSelection(recipe.id)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(selectedRecipeIds.contains(recipe.id)
                                                  ? PCColors.accent
                                                  : PCColors.fillTertiary)
                                            .frame(width: 32, height: 32)

                                        if selectedRecipeIds.contains(recipe.id) {
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.white)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(recipe.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(PCColors.textPrimary)

                                        HStack(spacing: 8) {
                                            Label(recipe.totalTimeDisplay, systemImage: "clock")
                                                .font(.caption)
                                                .foregroundStyle(PCColors.textSecondary)
                                            Text("\(recipe.steps.count) steps")
                                                .font(.caption)
                                                .foregroundStyle(PCColors.textSecondary)
                                        }
                                    }

                                    Spacer()

                                    // Show active session badge if exists
                                    if appState.activeCooks.session(for: recipe.id) != nil {
                                        Text("Active")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(PCColors.expiring)
                                            .clipShape(Capsule())
                                    } else if !recipe.source.isUserRecipe {
                                        Text(recipe.source.label)
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(PCColors.teal)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(PCColors.teal.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Select 2 or more recipes to cook together")
                    } footer: {
                        if filteredRecipes.isEmpty {
                            Text("No recipes match your current search.")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Multi-Cook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        showGathering = true
                    }
                    .fontWeight(.bold)
                    .disabled(selectedRecipeIds.count < 2)
                }
            }
            .sheet(isPresented: $showGathering) {
                let selectedRecipes = availableRecipes.filter { selectedRecipeIds.contains($0.id) }
                IngredientGatheringView(recipes: selectedRecipes) {
                    showGathering = false
                    showMultiCookMode = true
                }
            }
            .fullScreenCover(isPresented: $showMultiCookMode) {
                let selectedRecipes = availableRecipes.filter { selectedRecipeIds.contains($0.id) }
                let blocks = MultiRecipeScheduler.schedule(recipes: selectedRecipes)
                MultiCookModeView(
                    recipes: selectedRecipes,
                    blocks: blocks
                )
                .environment(appState)
            }
        }
    }

    // MARK: - Schedule Preview

    private var schedulePreview: some View {
        let summary = previewSummary

        return VStack(spacing: 10) {
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("\(selectedRecipeIds.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(PCColors.accent)
                    Text("Recipes")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }

                VStack(spacing: 2) {
                    Text("\(summary.blockCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(PCColors.info)
                    Text("Steps")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }

                VStack(spacing: 2) {
                    Text(formatDuration(summary.interleavedSeconds))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(PCColors.textPrimary)
                    Text("Total Time")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }

                VStack(spacing: 2) {
                    Text(savedTimeText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(summary.savedSeconds > 0 ? PCColors.accent : PCColors.textSecondary)
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }
            Text(schedulePreviewMessage)
                .font(.caption)
                .foregroundStyle(PCColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(PCColors.accent.opacity(0.08))
    }

    private var selectedRecipes: [Recipe] {
        availableRecipes.filter { selectedRecipeIds.contains($0.id) }
    }

    private var previewSummary: ScheduleSummary {
        guard let scheduleSummary else {
            return ScheduleSummary(
                blockCount: selectedRecipes.reduce(0) { $0 + $1.steps.count },
                interleavedSeconds: selectedRecipes.compactMap(\.totalTimeMinutes).reduce(0, +) * 60,
                savedSeconds: 0
            )
        }

        return scheduleSummary
    }

    private var savedTimeText: String {
        previewSummary.savedSeconds > 0 ? "-\(formatDuration(previewSummary.savedSeconds))" : "0m"
    }

    private var schedulePreviewMessage: String {
        switch selectedRecipeIds.count {
        case 0:
            return "Select recipes to preview overlap and time savings"
        case 1:
            return "Select 1 more recipe to compare overlap savings"
        default:
            return previewSummary.savedSeconds > 0
                ? "Estimated overlap savings across selected recipes"
                : "No overlap savings detected for this combination"
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedRecipeIds.contains(id) {
            selectedRecipeIds.remove(id)
        } else {
            selectedRecipeIds.insert(id)
        }
        recalculateScheduleSummary()
    }

    private func recalculateScheduleSummary() {
        guard selectedRecipes.count >= 2 else {
            scheduleSummary = nil
            return
        }

        let blocks = MultiRecipeScheduler.schedule(recipes: selectedRecipes)
        let sequential = MultiRecipeScheduler.sequentialTime(recipes: selectedRecipes)
        let interleaved = MultiRecipeScheduler.estimatedTotalTime(blocks: blocks)
        scheduleSummary = ScheduleSummary(
            blockCount: blocks.count,
            interleavedSeconds: interleaved,
            savedSeconds: max(0, sequential - interleaved)
        )
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let rm = m % 60
        return rm > 0 ? "\(h)h\(rm)m" : "\(h)h"
    }
}

private struct ScheduleSummary {
    let blockCount: Int
    let interleavedSeconds: Int
    let savedSeconds: Int

    static let empty = ScheduleSummary(blockCount: 0, interleavedSeconds: 0, savedSeconds: 0)
}
