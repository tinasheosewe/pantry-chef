import SwiftUI

// MARK: - Ingredient Gathering View
//
// Full-screen "get your ingredients ready" checklist shown before
// the interactive cook mode begins (both single and multi-recipe).
// Ingredients are grouped by category so the user can work through
// the kitchen efficiently.

struct IngredientGatheringView<Destination: View>: View {
    let recipes: [Recipe]
    @ViewBuilder let destination: () -> Destination

    @Environment(\.dismiss) private var dismiss
    @State private var checkedIds: Set<UUID> = []
    @State private var showDestination = false

    /// Merged & deduplicated ingredients across all selected recipes,
    /// grouped by `FoodCategory`.
    private var groupedIngredients: [(category: FoodCategory, items: [MergedIngredient])] {
        // Merge duplicates by lowercased name
        var map: [String: MergedIngredient] = [:]
        for recipe in recipes {
            for ing in recipe.ingredients {
                let key = ing.name.lowercased()
                if var existing = map[key] {
                    existing.totalQuantity += ing.quantity
                    if !existing.recipeNames.contains(recipe.title) {
                        existing.recipeNames.append(recipe.title)
                    }
                    map[key] = existing
                } else {
                    map[key] = MergedIngredient(
                        id: ing.id,
                        name: ing.name,
                        totalQuantity: ing.quantity,
                        unit: ing.unit,
                        category: ing.category,
                        isOptional: ing.isOptional,
                        recipeNames: [recipe.title]
                    )
                }
            }
        }

        let all = Array(map.values).sorted { $0.name < $1.name }
        let grouped = Dictionary(grouping: all) { $0.category }

        // Sort by category case order
        return FoodCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (category: cat, items: items)
        }
    }

    private var allIds: Set<UUID> {
        var ids = Set<UUID>()
        for group in groupedIngredients {
            for item in group.items {
                ids.insert(item.id)
            }
        }
        return ids
    }

    private var allChecked: Bool {
        allIds.isSubset(of: checkedIds)
    }

    private var isMultiRecipe: Bool { recipes.count > 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBanner

                AppScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedIngredients, id: \.category) { group in
                            categorySection(group.category, items: group.items)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 100) // room for button
                }

                startButton
            }
            .background(PCColors.background)
            .navigationTitle("Gather Ingredients")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(allChecked ? "Uncheck All" : "Check All") {
                        if allChecked {
                            checkedIds.removeAll()
                        } else {
                            checkedIds = allIds
                        }
                    }
                    .font(.caption)
                }
            }
            .navigationDestination(isPresented: $showDestination) {
                destination()
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .onChange(of: showDestination) { _, isShowing in
            if !isShowing {
                // Cook mode dismissed — close the entire gathering flow
                dismiss()
            }
        }
    }

    // MARK: - Header

    private var headerBanner: some View {
        VStack(spacing: 6) {
            Image(systemName: "basket.fill")
                .font(.title)
                .foregroundStyle(PCColors.accent)

            Text("Get everything ready")
                .font(.headline)
                .foregroundStyle(PCColors.textPrimary)

            if isMultiRecipe {
                Text(recipes.map(\.title).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else if let title = recipes.first?.title {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(PCColors.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(PCColors.accent.opacity(0.08))
    }

    // MARK: - Category Section

    private func categorySection(_ category: FoodCategory, items: [MergedIngredient]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category header
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                    .foregroundStyle(category.color)
                Text(category.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PCColors.textPrimary)
            }

            // Items
            VStack(spacing: 0) {
                ForEach(items) { item in
                    ingredientRow(item)
                    if item.id != items.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .background(PCColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Ingredient Row

    private func ingredientRow(_ item: MergedIngredient) -> some View {
        Button {
            if checkedIds.contains(item.id) {
                checkedIds.remove(item.id)
            } else {
                checkedIds.insert(item.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: checkedIds.contains(item.id)
                      ? "checkmark.circle.fill"
                      : "circle")
                    .font(.title3)
                    .foregroundStyle(checkedIds.contains(item.id)
                                    ? PCColors.accent
                                    : PCColors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.displayText)
                            .font(.body)
                            .foregroundStyle(checkedIds.contains(item.id)
                                            ? PCColors.textSecondary
                                            : PCColors.textPrimary)
                            .strikethrough(checkedIds.contains(item.id))

                        if item.isOptional {
                            Text("optional")
                                .font(.caption2)
                                .foregroundStyle(PCColors.expiring)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(PCColors.expiring.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    if isMultiRecipe && item.recipeNames.count > 1 {
                        Text(item.recipeNames.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Start Button

    private var startButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                showDestination = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                    Text("Start Cooking")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(PCColors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Merged Ingredient

/// A single ingredient row that may combine quantities from multiple recipes.
private struct MergedIngredient: Identifiable {
    let id: UUID
    let name: String
    var totalQuantity: Double
    let unit: MeasurementUnit?
    let category: FoodCategory
    let isOptional: Bool
    var recipeNames: [String]

    var displayText: String {
        let unitStr = unit?.rawValue ?? ""
        if totalQuantity == totalQuantity.rounded() {
            return "\(Int(totalQuantity)) \(unitStr) \(name)".trimmingCharacters(in: .whitespaces)
        }
        return String(format: "%.1f %@ %@", totalQuantity, unitStr, name).trimmingCharacters(in: .whitespaces)
    }
}
