import SwiftUI

struct UseUpIngredientsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: UseUpIngredientsViewModel
    @Environment(\.dismiss) private var dismiss

    init(appState: AppState) {
        _viewModel = State(initialValue: UseUpIngredientsViewModel(appState: appState))
    }

    var body: some View {
        NavigationStack {
            ingredientSelectionScreen
                .navigationTitle("Use Up Ingredients")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .navigationDestination(isPresented: $viewModel.showingSuggestions) {
                    suggestionsScreen
                        .navigationTitle("Recipe Ideas")
                        .navigationDestination(isPresented: $viewModel.showingRecipe) {
                            recipeScreen
                                .navigationTitle(viewModel.selectedSuggestion?.name ?? "Recipe")
                        }
                }
        }
        .interactiveDismissDisabled(viewModel.isLoading)
    }

    // MARK: - Screen 1: Ingredient Selection

    private var ingredientSelectionScreen: some View {
        VStack(spacing: 0) {
            PCScrollView {
                VStack(spacing: PCTokens.spacingMD) {
                    Section {
                        Text("Pick ingredients you want to use up, then get AI-generated recipe ideas.")
                            .font(.subheadline)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                    .padding(.horizontal)

                    AppSearchField("Search pantry items", text: $viewModel.searchText)
                        .padding(.horizontal)

                    ForEach(viewModel.groupedPantryItems, id: \.0) { category, items in
                        VStack(alignment: .leading, spacing: PCTokens.spacingSM) {
                            Text(category.rawValue)
                                .font(PCFont.micro)
                                .foregroundStyle(PCColors.textTertiary)
                                .padding(.horizontal)

                            ForEach(items) { item in
                                pantryItemRow(item)
                            }
                        }
                    }

                    extraIngredientsSection
                    strictIngredientsToggle
                }
                .padding(.vertical)
            }

            selectionSummaryBar
        }
    }

    private func pantryItemRow(_ item: PantryItem) -> some View {
        Button {
            viewModel.togglePantryItem(item)
        } label: {
            HStack(spacing: PCTokens.spacingMD) {
                Image(systemName: viewModel.selectedPantryIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(viewModel.selectedPantryIDs.contains(item.id) ? PCColors.accent : PCColors.separator)
                    .font(.title3)

                Text(item.name)
                    .font(PCFont.body)
                    .foregroundStyle(PCColors.textPrimary)

                Spacer()

                if let days = item.daysUntilExpiry, days <= 3 {
                    PCExpiryBadge(status: item.expiryStatus, daysLeft: days)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, PCTokens.spacingXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var extraIngredientsSection: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingSM) {
            Text("Add Extra Ingredients")
                .font(PCFont.headline)
                .foregroundStyle(PCColors.textPrimary)
                .padding(.horizontal)

            HStack(spacing: PCTokens.spacingSM) {
                TextField("e.g., lemon from garden", text: $viewModel.extraIngredientText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.addExtraIngredient() }

                Button {
                    viewModel.addExtraIngredient()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PCColors.accent)
                }
                .disabled(viewModel.extraIngredientText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)

            if !viewModel.extraIngredients.isEmpty {
                FlowLayout(spacing: PCTokens.spacingSM) {
                    ForEach(viewModel.extraIngredients, id: \.self) { ingredient in
                        HStack(spacing: 4) {
                            Text(ingredient)
                                .font(PCFont.caption)
                            Button {
                                viewModel.removeExtraIngredient(ingredient)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(PCColors.accent.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(PCColors.accent)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var strictIngredientsToggle: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
            Toggle("Only use my ingredients", isOn: $viewModel.strictIngredients)
                .font(PCFont.body)
                .padding(.horizontal)

            Text("Off: recipes may include common staples like salt, oil, and garlic")
                .font(PCFont.caption)
                .foregroundStyle(PCColors.textTertiary)
                .padding(.horizontal)
        }
    }

    private var selectionSummaryBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: PCTokens.spacingSM) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(viewModel.selectedCount) ingredient\(viewModel.selectedCount == 1 ? "" : "s") selected")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(PCColors.textPrimary)
                        Text("Tap Get Recipe Ideas to see what you can make.")
                            .font(.caption)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                Button {
                    Task { await viewModel.fetchSuggestions() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Get Recipe Ideas")
                    }
                    .font(PCFont.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(viewModel.canGetSuggestions ? PCColors.accent : PCColors.separator)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadius))
                }
                .disabled(!viewModel.canGetSuggestions)
                .padding(.horizontal)
            }
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Screen 2: Suggestions

    private var suggestionsScreen: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingSuggestions && viewModel.suggestions.isEmpty {
                loadingState(
                    icon: "fork.knife",
                    message: viewModel.suggestionStatusMessage,
                    submessage: "Based on \(viewModel.selectedCount) ingredient\(viewModel.selectedCount == 1 ? "" : "s")"
                )
            } else if let message = viewModel.noResultsMessage, viewModel.suggestions.isEmpty {
                noResultsView(message)
            } else {
                PCScrollView {
                    VStack(spacing: PCTokens.spacingMD) {
                        ForEach(viewModel.suggestions) { suggestion in
                            suggestionRow(suggestion)
                        }

                        if !viewModel.suggestions.isEmpty {
                            showMoreButton
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func noResultsView(_ message: String) -> some View {
        VStack(spacing: PCTokens.spacingMD) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(PCColors.expiring)

            Text(message)
                .font(PCFont.body)
                .foregroundStyle(PCColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    private func suggestionRow(_ suggestion: RecipeNameSuggestion) -> some View {
        let tier = ConfidenceTier(score: suggestion.confidenceScore)

        return Button {
            Task { await viewModel.selectAndGenerate(suggestion) }
        } label: {
            VStack(alignment: .leading, spacing: PCTokens.spacingSM) {
                HStack {
                    Text(suggestion.name)
                        .font(PCFont.headline)
                        .foregroundStyle(PCColors.textPrimary)
                    Spacer()
                    confidenceBadge(tier)
                }

                Text(suggestion.description)
                    .font(PCFont.body)
                    .foregroundStyle(PCColors.textSecondary)

                Text(suggestion.confidenceReason)
                    .font(PCFont.caption)
                    .foregroundStyle(PCColors.textTertiary)
            }
            .padding(PCTokens.cardPadding)
            .pcCard()
        }
        .buttonStyle(.plain)
    }

    private func confidenceBadge(_ tier: ConfidenceTier) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tier.icon)
            Text(tier.label)
                .font(PCFont.micro)
        }
        .foregroundStyle(tier.color)
    }

    private var showMoreButton: some View {
        Button {
            Task { await viewModel.fetchMoreSuggestions() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isLoadingSuggestions {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(viewModel.isLoadingSuggestions ? "Finding more…" : "Show More Ideas")
            }
            .font(PCFont.body)
            .foregroundStyle(PCColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(PCColors.fillTertiary)
            .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadius))
        }
        .disabled(viewModel.isLoadingSuggestions)
    }

    // MARK: - Screen 3: Recipe

    private var recipeScreen: some View {
        VStack(spacing: 0) {
            if viewModel.isGeneratingRecipe {
                generatingRecipeLoadingView
            } else if let normalized = viewModel.generatedRecipe {
                PCScrollView {
                    VStack(spacing: PCTokens.spacingMD) {
                        if let suggestion = viewModel.selectedSuggestion {
                            confidencePill(ConfidenceTier(score: suggestion.confidenceScore), reason: suggestion.confidenceReason)
                        }

                        RecipeDetailView(recipe: normalized.rawValue)
                            .environment(appState)
                    }
                }
            } else {
                generationFailedView
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.generatedRecipe != nil {
                    Button {
                        Task {
                            await viewModel.saveRecipe()
                            dismiss()
                        }
                    } label: {
                        Text("Save Recipe")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.generatedRecipe != nil {
                recipeSummaryBar
            }
        }
    }

    private var generatingRecipeLoadingView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: PCTokens.spacingMD) {
                Image(systemName: "text.page.badge.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(PCColors.accent)
                    .modifier(PulseAnimationModifier())

                Text(viewModel.generationStatusMessage)
                    .font(PCFont.body)
                    .fontWeight(.medium)
                    .foregroundStyle(PCColors.textPrimary)
                    .id(viewModel.generationStatusMessage)
                    .transition(.push(from: .bottom))
                    .animation(.easeInOut(duration: 0.35), value: viewModel.generationStatusMessage)

                if let suggestion = viewModel.selectedSuggestion {
                    VStack(spacing: PCTokens.spacingXS) {
                        Text(suggestion.name)
                            .font(PCFont.headline)
                            .foregroundStyle(PCColors.textPrimary)

                        Text(suggestion.description)
                            .font(PCFont.caption)
                            .foregroundStyle(PCColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, PCTokens.spacingSM)
                }

                ProgressView()
                    .controlSize(.small)
                    .tint(PCColors.accent)
                    .padding(.top, PCTokens.spacingSM)
            }

            Spacer()
        }
    }

    private var generationFailedView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: PCTokens.spacingMD) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(PCColors.expiring)

                Text("Couldn't generate a recipe")
                    .font(PCFont.headline)
                    .foregroundStyle(PCColors.textPrimary)

                Text("This can happen if the AI service is busy. You can try again or go back to pick a different suggestion.")
                    .font(PCFont.body)
                    .foregroundStyle(PCColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    Task { await viewModel.retryGeneration() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(PCFont.body)
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(PCColors.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }

            Spacer()
        }
    }

    private func confidencePill(_ tier: ConfidenceTier, reason: String) -> some View {
        VStack(spacing: PCTokens.spacingXS) {
            HStack(spacing: 6) {
                Text(tier.emoji)
                Text(tier.label)
                    .font(PCFont.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tier.color.opacity(0.15))
            .clipShape(Capsule())
            .foregroundStyle(tier.color)

            Text(reason)
                .font(PCFont.caption)
                .foregroundStyle(PCColors.textTertiary)
        }
        .padding(.horizontal)
    }

    private var recipeSummaryBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recipe ready")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PCColors.textPrimary)
                    Text("Save it to your collection, or go back to try another idea.")
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

    // MARK: - Shared Loading State

    private func loadingState(icon: String, message: String, submessage: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: PCTokens.spacingMD) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(PCColors.accent)
                    .modifier(PulseAnimationModifier())

                Text(message)
                    .font(PCFont.body)
                    .fontWeight(.medium)
                    .foregroundStyle(PCColors.textPrimary)
                    .id(message)
                    .transition(.push(from: .bottom))
                    .animation(.easeInOut(duration: 0.35), value: message)

                Text(submessage)
                    .font(PCFont.caption)
                    .foregroundStyle(PCColors.textTertiary)

                ProgressView()
                    .controlSize(.small)
                    .tint(PCColors.accent)
                    .padding(.top, PCTokens.spacingSM)
            }

            Spacer()
        }
    }
}

// MARK: - Pulse Animation

private struct PulseAnimationModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.15 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}
