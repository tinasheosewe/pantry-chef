import SwiftUI

struct IngredientCatalogSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingAddCustom = false
    @State private var editingItemID: String?

    let appState: AppState

    private var userItems: [PantryCatalogItemDefinition] {
        let items = PantryCatalog.userItems
        if searchText.trimmed.isEmpty { return items }
        let query = searchText.lowercased()
        return items.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if PantryCatalog.userItems.isEmpty {
                    EmptyStateView(
                        icon: "book.closed",
                        title: "No Custom Ingredients",
                        message: "Custom ingredients you create will appear here for management.",
                        actionTitle: "Add Custom Ingredient"
                    ) {
                        showingAddCustom = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(userItems) { item in
                            Button {
                                editingItemID = item.id
                            } label: {
                                HStack(spacing: 12) {
                                    CategoryIcon(category: item.category, size: 36)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.titleCasedName)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(PCColors.textPrimary)
                                        Text(item.category.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(PCColors.textSecondary)
                                        if !item.facets.isEmpty {
                                            Text(item.facets.map(\.key.title).joined(separator: ", "))
                                                .font(.caption2)
                                                .foregroundStyle(PCColors.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(PCColors.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search custom ingredients")
                }
            }
            .navigationTitle("Custom Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddCustom = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCustom) {
                CustomIngredientDefinitionView(
                    name: "",
                    appState: appState
                )
            }
            .sheet(isPresented: Binding(
                get: { editingItemID != nil },
                set: { if !$0 { editingItemID = nil } }
            )) {
                if let itemID = editingItemID {
                    CustomIngredientDefinitionView(
                        itemID: itemID,
                        appState: appState
                    )
                }
            }
        }
    }
}
