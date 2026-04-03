import SwiftUI

enum IngredientCatalogSettingsSupport {
    static func filteredCustomItems(
        searchText: String,
        items: [PantryCatalogItemDefinition]
    ) -> [PantryCatalogItemDefinition] {
        guard !searchText.trimmed.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter { $0.name.lowercased().contains(query) }
    }

    static func filteredCatalogItems(
        searchText: String,
        allItems: [PantryCatalogItemDefinition] = PantryCatalog.allItems,
        search: (String) -> [CatalogSearchResult] = CatalogSearchEngine.search
    ) -> [PantryCatalogItemDefinition] {
        let items = allItems.filter { !$0.isUserDefined }
        let query = searchText.trimmed
        guard !query.isEmpty else { return items }

        var seenItemIDs: Set<String> = []
        return search(query)
            .map(\.item)
            .filter { !$0.isUserDefined }
            .filter { seenItemIDs.insert($0.id).inserted }
    }
}

struct IngredientCatalogSettingsView: View {
    enum SettingsTab: String, CaseIterable {
        case custom = "Custom"
        case catalog = "Catalog"
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .custom
    @State private var customSearchText = ""
    @State private var catalogSearchText = ""
    @State private var showingAddCustom = false
    @State private var editingItemID: String?
    @State private var refreshToken = UUID()

    let appState: AppState

    private var customItems: [PantryCatalogItemDefinition] {
        _ = refreshToken
        return IngredientCatalogSettingsSupport.filteredCustomItems(
            searchText: customSearchText,
            items: PantryCatalog.userItems
        )
    }

    private var catalogItems: [PantryCatalogItemDefinition] {
        _ = refreshToken
        return IngredientCatalogSettingsSupport.filteredCatalogItems(
            searchText: catalogSearchText,
            allItems: PantryCatalog.allItems
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ZStack {
                    // Custom tab list
                    Group {
                        if customItems.isEmpty && customSearchText.trimmed.isEmpty {
                            customEmptyState
                        } else {
                            List {
                                ForEach(customItems) { item in
                                    ingredientRow(item)
                                }
                            }
                            .searchable(text: $customSearchText, prompt: "Search custom ingredients")
                        }
                    }
                    .opacity(selectedTab == .custom ? 1 : 0)
                    .allowsHitTesting(selectedTab == .custom)

                    // Catalog tab list
                    Group {
                        if catalogItems.isEmpty && catalogSearchText.trimmed.isEmpty {
                            catalogEmptyState
                        } else {
                            List {
                                ForEach(catalogItems) { item in
                                    ingredientRow(item)
                                }
                            }
                            .searchable(text: $catalogSearchText, prompt: "Search catalog ingredients")
                        }
                    }
                    .opacity(selectedTab == .catalog ? 1 : 0)
                    .allowsHitTesting(selectedTab == .catalog)
                }
            }
            .navigationTitle("Ingredient Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if selectedTab == .custom {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddCustom = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pantryCatalogDidChange)) { _ in
                refreshToken = UUID()
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

    // MARK: - Subviews

    @ViewBuilder
    private var customEmptyState: some View {
        EmptyStateView(
            icon: "book.closed",
            title: "No Custom Ingredients",
            message: "Custom ingredients you create will appear here for management.",
            actionTitle: "Add Custom Ingredient"
        ) {
            showingAddCustom = true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var catalogEmptyState: some View {
        EmptyStateView(
            icon: "tray",
            title: "No Results",
            message: "No catalog ingredients found."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ingredientRow(_ item: PantryCatalogItemDefinition) -> some View {
        Button {
            editingItemID = item.id
        } label: {
            HStack(spacing: 12) {
                CategoryIcon(category: item.category, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.titleCasedName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(PCColors.textPrimary)
                        if selectedTab == .catalog && PantryCatalog.hasUserModifications(catalogItemID: item.id) {
                            Text("Modified")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(PCColors.accent.opacity(0.15))
                                .foregroundStyle(PCColors.accent)
                                .clipShape(Capsule())
                        }
                    }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

}
