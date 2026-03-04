import SwiftUI

struct ShoppingListView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: ShoppingViewModel
    @State private var showAddItem = false
    @State private var newItemName = ""

    init() {
        _viewModel = StateObject(wrappedValue: ShoppingViewModel(appState: AppState()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                if !viewModel.items.isEmpty {
                    progressHeader
                }

                // Content
                if viewModel.items.isEmpty {
                    EmptyStateView(
                        icon: "cart",
                        title: "Shopping list is empty",
                        message: "Add items manually or generate a list from your meal plan.",
                        actionTitle: "Add Item"
                    ) {
                        showAddItem = true
                    }
                } else {
                    shoppingList
                }
            }
            .background(AppColors.background)
            .navigationTitle("Shopping List")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showAddItem = true
                        } label: {
                            Label("Add Item", systemImage: "plus")
                        }

                        Button {
                            Task { await viewModel.addCheckedToPantry() }
                        } label: {
                            Label("Checked → Pantry", systemImage: "arrow.right.circle")
                        }

                        Button(role: .destructive) {
                            viewModel.removeCheckedItems()
                        } label: {
                            Label("Clear Checked", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Add Item", isPresented: $showAddItem) {
                TextField("Item name", text: $newItemName)
                Button("Add") {
                    if !newItemName.isEmpty {
                        viewModel.addItem(ShoppingItem(name: newItemName))
                        newItemName = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newItemName = ""
                }
            }
        }
    }

    // MARK: - Progress Header
    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text(viewModel.progressText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.darkText)
                Spacer()
                if viewModel.checkedCount > 0 {
                    Button("Add to Pantry") {
                        Task { await viewModel.addCheckedToPantry() }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.primaryGreen)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.lightGray)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.primaryGreen)
                        .frame(width: viewModel.totalCount > 0 ?
                               geo.size.width * CGFloat(viewModel.checkedCount) / CGFloat(viewModel.totalCount) : 0)
                        .animation(.easeInOut, value: viewModel.checkedCount)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(AppColors.cardBackground)
    }

    // MARK: - Shopping List
    private var shoppingList: some View {
        List {
            ForEach(viewModel.groupedByCategory, id: \.0) { category, items in
                Section {
                    ForEach(items) { item in
                        ShoppingItemRow(item: item) {
                            viewModel.toggleItem(item)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.removeItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        CategoryIcon(category: category, size: 20)
                        Text(category.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Shopping Item Row
struct ShoppingItemRow: View {
    let item: ShoppingItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? AppColors.primaryGreen : AppColors.mediumGray)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(item.isChecked ? AppColors.subtleText : AppColors.darkText)
                        .strikethrough(item.isChecked)

                    if let qty = item.quantity {
                        Text("\(qty == qty.rounded() ? "\(Int(qty))" : String(format: "%.1f", qty)) \(item.unit?.rawValue ?? "")")
                            .font(.caption)
                            .foregroundStyle(AppColors.subtleText)
                    }
                }

                Spacer()

                if let source = item.recipeSource {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(AppColors.subtleText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.lightGray)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}
