import SwiftUI

// MARK: - Multi-Cook Selection View
//
// Allows the user to select 2+ recipes to cook simultaneously.
// Shows the scheduler preview with time savings estimate.

struct MultiCookSelectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRecipeIds: Set<UUID> = []
    @State private var showMultiCookMode = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if selectedRecipeIds.count >= 2 {
                    schedulePreview
                }

                List {
                    Section {
                        ForEach(appState.recipes) { recipe in
                            Button {
                                toggleSelection(recipe.id)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(selectedRecipeIds.contains(recipe.id)
                                                  ? AppColors.primaryGreen
                                                  : AppColors.lightGray)
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
                                            .foregroundStyle(AppColors.darkText)

                                        HStack(spacing: 8) {
                                            if let time = recipe.totalTimeDisplay as String? {
                                                Label(time, systemImage: "clock")
                                                    .font(.caption)
                                                    .foregroundStyle(AppColors.subtleText)
                                            }
                                            Text("\(recipe.steps.count) steps")
                                                .font(.caption)
                                                .foregroundStyle(AppColors.subtleText)
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
                                            .background(.orange)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Select 2 or more recipes to cook together")
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Multi-Cook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        showMultiCookMode = true
                    }
                    .fontWeight(.bold)
                    .disabled(selectedRecipeIds.count < 2)
                }
            }
            .fullScreenCover(isPresented: $showMultiCookMode) {
                let selectedRecipes = appState.recipes.filter { selectedRecipeIds.contains($0.id) }
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
        let selectedRecipes = appState.recipes.filter { selectedRecipeIds.contains($0.id) }
        let blocks = MultiRecipeScheduler.schedule(recipes: selectedRecipes)
        let sequential = MultiRecipeScheduler.sequentialTime(recipes: selectedRecipes)
        let interleaved = MultiRecipeScheduler.estimatedTotalTime(blocks: blocks)
        let saved = max(0, sequential - interleaved)

        return VStack(spacing: 8) {
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("\(selectedRecipeIds.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColors.primaryGreen)
                    Text("Recipes")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                VStack(spacing: 2) {
                    Text("\(blocks.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    Text("Steps")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                VStack(spacing: 2) {
                    Text(formatDuration(interleaved))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColors.darkText)
                    Text("Total Time")
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }

                if saved > 0 {
                    VStack(spacing: 2) {
                        Text("-\(formatDuration(saved))")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColors.primaryGreen)
                        Text("Saved")
                            .font(.caption)
                            .foregroundStyle(AppColors.subtleText)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(AppColors.primaryGreen.opacity(0.08))
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedRecipeIds.contains(id) {
            selectedRecipeIds.remove(id)
        } else {
            selectedRecipeIds.insert(id)
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let rm = m % 60
        return rm > 0 ? "\(h)h\(rm)m" : "\(h)h"
    }
}
