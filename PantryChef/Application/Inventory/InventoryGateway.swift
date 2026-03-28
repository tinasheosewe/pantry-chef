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
    private let shoppingDomainService: any ShoppingDomainServicing

    init(appState: AppState, shoppingDomainService: any ShoppingDomainServicing) {
        self.appState = appState
        self.shoppingDomainService = shoppingDomainService
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
            await shoppingDomainService.updateShoppingItem(item, state: appState)
        } else {
            await shoppingDomainService.addShoppingItem(item, state: appState)
        }
    }

    func addShoppingItems(_ items: [ShoppingItem]) async {
        await shoppingDomainService.addShoppingItems(items, state: appState)
    }

    func toggleShoppingItem(_ item: ShoppingItem) async {
        await shoppingDomainService.toggleShoppingItem(item, state: appState)
    }

    func removeShoppingItem(_ item: ShoppingItem) async {
        await shoppingDomainService.removeShoppingItem(item, state: appState)
    }

    func removeCheckedShoppingItems() async {
        await shoppingDomainService.removeCheckedShoppingItems(state: appState)
    }

    func replaceShoppingItems(_ items: [ShoppingItem]) async {
        await shoppingDomainService.replaceShoppingItems(items, state: appState)
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
        InventoryGateway(appState: self, shoppingDomainService: shoppingDomainService)
    }
}