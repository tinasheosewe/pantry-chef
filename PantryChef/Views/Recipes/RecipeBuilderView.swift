import SwiftUI

/// Compact recipe configurator sheet — all taps, no typing.
/// Pre-filled from the user's search query; "Just generate" skips straight to AI.
struct RecipeBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let query: String
    let onGenerated: (Recipe) -> Void

    @State private var servings: Int = 4
    @State private var spiceLevel: RecipeGenerationPreferences.SpiceLevel = .medium
    @State private var maxTime: TimeOption = .noLimit
    @State private var dietaryTags: Set<DietaryTag> = []
    @State private var usePantry: Bool = false
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var statusMessage: String = ""

    enum TimeOption: String, CaseIterable {
        case under30 = "< 30 min"
        case thirtyTo60 = "30–60 min"
        case sixtyTo90 = "60–90 min"
        case noLimit = "No Limit"

        var minutes: Int? {
            switch self {
            case .under30: return 30
            case .thirtyTo60: return 60
            case .sixtyTo90: return 90
            case .noLimit: return nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Servings
                    optionSection(title: "Servings") {
                        chipRow(values: [2, 4, 6, 8], selected: servings) { servings = $0 }
                    }

                    // Spice Level
                    optionSection(title: "Spice Level") {
                        HStack(spacing: 8) {
                            ForEach(RecipeGenerationPreferences.SpiceLevel.allCases, id: \.self) { level in
                                chipButton(
                                    label: level.icon,
                                    subtitle: level.rawValue,
                                    isSelected: spiceLevel == level
                                ) {
                                    spiceLevel = level
                                }
                            }
                        }
                    }

                    // Time
                    optionSection(title: "Total Time") {
                        HStack(spacing: 8) {
                            ForEach(TimeOption.allCases, id: \.self) { option in
                                chipButton(
                                    label: option.rawValue,
                                    isSelected: maxTime == option
                                ) {
                                    maxTime = option
                                }
                            }
                        }
                    }

                    // Dietary
                    optionSection(title: "Dietary") {
                        let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(DietaryTag.allCases.prefix(8)) { tag in
                                chipButton(
                                    label: tag.rawValue,
                                    isSelected: dietaryTags.contains(tag)
                                ) {
                                    if dietaryTags.contains(tag) {
                                        dietaryTags.remove(tag)
                                    } else {
                                        dietaryTags.insert(tag)
                                    }
                                }
                            }
                        }
                    }

                    // Use Pantry
                    optionSection(title: "Ingredients") {
                        HStack(spacing: 12) {
                            pantryToggle(
                                label: "Use My Pantry",
                                icon: "refrigerator.fill",
                                isSelected: usePantry
                            ) {
                                usePantry = true
                            }
                            pantryToggle(
                                label: "Classic Recipe",
                                icon: "book.fill",
                                isSelected: !usePantry
                            ) {
                                usePantry = false
                            }
                        }
                        if usePantry {
                            Text("\(appState.pantryItems.count) pantry items will be considered")
                                .font(.caption)
                                .foregroundStyle(AppColors.subtleText)
                                .transition(.opacity)
                        }
                    }

                    // Error
                    if let error = generationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(AppColors.softRed)
                            .padding(.horizontal)
                    }

                    // Generate / Status
                    VStack(spacing: 14) {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(AppColors.primaryGreen)

                            Text(statusMessage)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(AppColors.darkText)
                                .multilineTextAlignment(.center)
                                .id(statusMessage)
                                .transition(.push(from: .bottom))

                            Text("Usually takes about 30 seconds")
                                .font(.caption2)
                                .foregroundStyle(AppColors.subtleText)
                        } else {
                            Button {
                                Task { await generate() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                    Text("Generate Recipe")
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColors.primaryGreen)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .animation(.easeInOut(duration: 0.35), value: statusMessage)
                    .animation(.easeInOut(duration: 0.25), value: isGenerating)

                    // Skip link
                    if !isGenerating {
                        Button {
                            Task { await generate() }
                        } label: {
                            Text("Just generate with defaults →")
                                .font(.footnote)
                                .foregroundStyle(AppColors.subtleText)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(AppColors.background)
            .navigationTitle("Recipe Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isGenerating)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(AppColors.warmOrange)
                Text(query.capitalized)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.darkText)
            }
            Text("Customize your recipe or tap Generate to go with smart defaults")
                .font(.subheadline)
                .foregroundStyle(AppColors.subtleText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    // MARK: - Section Builder

    private func optionSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.darkText)
            content()
        }
        .padding(.horizontal)
    }

    // MARK: - Chip Components

    private func chipRow(values: [Int], selected: Int, onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(values, id: \.self) { value in
                chipButton(label: "\(value)", isSelected: selected == value) {
                    onSelect(value)
                }
            }
        }
    }

    private func chipButton(label: String, subtitle: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                }
            }
            .foregroundStyle(isSelected ? .white : AppColors.darkText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? AppColors.primaryGreen : AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : AppColors.mediumGray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func pantryToggle(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? .white : AppColors.darkText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? AppColors.primaryGreen : AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : AppColors.mediumGray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Generation

    private func generate() async {
        isGenerating = true
        generationError = nil

        let prefs = RecipeGenerationPreferences(
            servings: servings,
            maxTimeMinutes: maxTime.minutes,
            spiceLevel: spiceLevel,
            dietaryTags: Array(dietaryTags),
            usePantry: usePantry,
            pantryIngredients: usePantry ? appState.pantryItems.map(\.name) : []
        )

        // Show an immediate first message while the AI call fires
        statusMessage = "Researching the best \(query.capitalized) recipes…"

        // Fire status messages + recipe generation in parallel
        async let statusFetch = appState.aiService.generateStatusMessages(query: query, preferences: prefs)
        async let recipeFetch = appState.aiService.generateRecipe(query: query, preferences: prefs)

        // Status messages come back fast (~2s), start cycling them
        let messages = await statusFetch
        statusMessage = messages.first ?? statusMessage

        let messageCount = max(messages.count, 1)
        let interval: UInt64 = UInt64(max(3.0, 28.0 / Double(messageCount)) * 1_000_000_000)
        let tickerTask = Task {
            for msg in messages.dropFirst() {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                await MainActor.run { statusMessage = msg }
            }
            // Hold final message until generation completes
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        // Wait for the recipe
        if let recipe = await recipeFetch {
            tickerTask.cancel()
            await appState.cacheDiscoverRecipe(recipe)
            appState.refreshDiscoverRecipes()
            dismiss()
            onGenerated(recipe)
        } else {
            tickerTask.cancel()
            generationError = "Failed to generate recipe. Please try again."
        }
        isGenerating = false
        statusMessage = ""
    }
}
