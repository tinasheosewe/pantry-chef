import SwiftUI

@Observable
@MainActor
final class ShoppingViewModel {
    var searchText = ""
    var isLoading = false

    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var items: [ShoppingItem] {
        var list = appState.shoppingItems
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return list
    }

    var groupedByCategory: [(FoodCategory, [ShoppingItem])] {
        let grouped = Dictionary(grouping: items, by: { $0.category })
        return grouped.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    var checkedCount: Int {
        appState.shoppingItems.filter { $0.isChecked }.count
    }

    var totalCount: Int {
        appState.shoppingItems.count
    }

    var progressText: String {
        "\(checkedCount)/\(totalCount) items"
    }

    func toggleItem(_ item: ShoppingItem) {
        appState.toggleShoppingItem(item)
    }

    func removeCheckedItems() {
        Task { await appState.removeCheckedShoppingItems() }
    }

    func addItem(_ item: ShoppingItem) {
        Task { await appState.addShoppingItem(item) }
    }

    func removeItem(_ item: ShoppingItem) {
        Task { await appState.removeShoppingItem(item) }
    }

    func addCheckedToPantry() async {
        let checkedItems = appState.shoppingItems.filter { $0.isChecked }
        for item in checkedItems {
            let pantryItem = PantryItem(
                name: item.name,
                category: item.category,
                quantity: item.quantity,
                unit: item.unit
            )
            await appState.addPantryItem(pantryItem)
        }
        await appState.removeCheckedShoppingItems()
    }
}
