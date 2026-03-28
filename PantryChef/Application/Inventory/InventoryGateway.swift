import Foundation

@MainActor
protocol InventoryGatewayProtocol {
    func upsertPantryItem(_ item: PantryItem) async
    func removePantryItem(_ item: PantryItem) async
    func upsertShoppingItem(_ item: ShoppingItem) async
    func addShoppingItems(_ items: [ShoppingItem]) async
    func toggleShoppingItem(_ item: ShoppingItem) async
    func removeShoppingItem(_ item: ShoppingItem) async
    func removeCheckedShoppingItems() async
    func replaceShoppingItems(_ items: [ShoppingItem]) async
    func transferCheckedShoppingItemsToPantry() async
    func upsertPreparedDish(_ dish: PreparedDish) async
    func addPreparedDishes(_ dishes: [PreparedDish]) async
    func removePreparedDish(_ dish: PreparedDish) async
    func adjustPreparedDishServings(_ dish: PreparedDish, delta: Int) async -> Bool
    func applyCookReview(_ items: [PantryCookReviewItem]) async
}

@MainActor
struct InventoryGateway: InventoryGatewayProtocol {
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func upsertPantryItem(_ item: PantryItem) async {
        if appState.pantryItems.contains(where: { $0.id == item.id }) {
            await appState.updatePantryItem(item)
        } else {
            await appState.addPantryItem(item)
        }
    }

    func removePantryItem(_ item: PantryItem) async {
        await appState.removePantryItem(item)
    }

    func upsertShoppingItem(_ item: ShoppingItem) async {
        if appState.shoppingItems.contains(where: { $0.id == item.id }) {
            await appState.updateShoppingItem(item)
        } else {
            await appState.addShoppingItem(item)
        }
    }

    func addShoppingItems(_ items: [ShoppingItem]) async {
        await appState.addShoppingItems(items)
    }

    func toggleShoppingItem(_ item: ShoppingItem) async {
        await appState.toggleShoppingItem(item)
    }

    func removeShoppingItem(_ item: ShoppingItem) async {
        await appState.removeShoppingItem(item)
    }

    func removeCheckedShoppingItems() async {
        await appState.removeCheckedShoppingItems()
    }

    func replaceShoppingItems(_ items: [ShoppingItem]) async {
        await appState.replaceShoppingItems(items)
    }

    func transferCheckedShoppingItemsToPantry() async {
        let checkedItems = appState.shoppingItems.filter(\.isChecked)
        for item in checkedItems {
            await upsertPantryItem(item.pantryItemForTransfer())
        }
        await removeCheckedShoppingItems()
    }

    func upsertPreparedDish(_ dish: PreparedDish) async {
        if appState.preparedDishes.contains(where: { $0.id == dish.id }) {
            await appState.updatePreparedDish(dish)
        } else {
            await appState.addPreparedDish(dish)
        }
    }

    func addPreparedDishes(_ dishes: [PreparedDish]) async {
        for dish in dishes {
            await upsertPreparedDish(dish)
        }
    }

    func removePreparedDish(_ dish: PreparedDish) async {
        await appState.removePreparedDish(dish)
    }

    func adjustPreparedDishServings(_ dish: PreparedDish, delta: Int) async -> Bool {
        await appState.adjustPreparedDishServings(dish, delta: delta)
    }

    func applyCookReview(_ items: [PantryCookReviewItem]) async {
        await appState.applyPantryCookReview(items)
    }
}

@MainActor
extension AppState {
    var inventoryGateway: any InventoryGatewayProtocol {
        InventoryGateway(appState: self)
    }
}