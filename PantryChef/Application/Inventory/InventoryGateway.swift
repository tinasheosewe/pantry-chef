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
    private let pantryDomainService: any PantryDomainServicing
    private let preparedDishDomainService: any PreparedDishDomainServicing
    private let shoppingDomainService: any ShoppingDomainServicing

    init(
        appState: AppState,
        pantryDomainService: any PantryDomainServicing,
        preparedDishDomainService: any PreparedDishDomainServicing,
        shoppingDomainService: any ShoppingDomainServicing
    ) {
        self.appState = appState
        self.pantryDomainService = pantryDomainService
        self.preparedDishDomainService = preparedDishDomainService
        self.shoppingDomainService = shoppingDomainService
    }

    func upsertPantryItem(_ item: PantryItem) async {
        if appState.pantryItems.contains(where: { $0.id == item.id }) {
            await pantryDomainService.updatePantryItem(item, state: appState)
        } else {
            await pantryDomainService.addPantryItem(item, state: appState)
        }
    }

    func removePantryItem(_ item: PantryItem) async {
        await pantryDomainService.removePantryItem(item, state: appState)
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
            await preparedDishDomainService.updatePreparedDish(dish, state: appState)
        } else {
            await preparedDishDomainService.addPreparedDish(dish, state: appState)
        }
    }

    func addPreparedDishes(_ dishes: [PreparedDish]) async {
        for dish in dishes {
            await upsertPreparedDish(dish)
        }
    }

    func removePreparedDish(_ dish: PreparedDish) async {
        await preparedDishDomainService.removePreparedDish(dish, state: appState)
    }

    func adjustPreparedDishServings(_ dish: PreparedDish, delta: Int) async -> Bool {
        await preparedDishDomainService.adjustPreparedDishServings(dish, delta: delta, state: appState)
    }

    func applyCookReview(_ items: [PantryCookReviewItem]) async {
        await pantryDomainService.applyPantryCookReview(items, state: appState)
    }
}

@MainActor
extension AppState {
    var inventoryGateway: any InventoryGatewayProtocol {
        InventoryGateway(
            appState: self,
            pantryDomainService: pantryDomainService,
            preparedDishDomainService: preparedDishDomainService,
            shoppingDomainService: shoppingDomainService
        )
    }
}