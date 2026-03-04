import SwiftUI

@Observable
@MainActor
final class PantryViewModel {
    var searchText = ""
    var selectedCategory: FoodCategory?
    var showAddItem = false
    var showBarcodeScanner = false
    var showReceiptScanner = false
    var showVoiceInput = false
    var sortOrder: SortOrder = .category
    var isLoading = false

    enum SortOrder: String, CaseIterable {
        case category = "Category"
        case expiry = "Expiry Date"
        case name = "Name"
        case dateAdded = "Date Added"
    }

    let appState: AppState
    let barcodeScanner = BarcodeScannerService()
    let receiptScanner = ReceiptScannerService()

    init(appState: AppState) {
        self.appState = appState
    }

    var filteredItems: [PantryItem] {
        var items = appState.pantryItems

        if !searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        if let category = selectedCategory {
            items = items.filter { $0.category == category }
        }

        switch sortOrder {
        case .category:
            items.sort { $0.category.rawValue < $1.category.rawValue }
        case .expiry:
            items.sort { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }
        case .name:
            items.sort { $0.name < $1.name }
        case .dateAdded:
            items.sort { $0.dateAdded > $1.dateAdded }
        }

        return items
    }

    var groupedByCategory: [(FoodCategory, [PantryItem])] {
        let grouped = Dictionary(grouping: filteredItems, by: { $0.category })
        return grouped.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    var activeCategoryCount: [FoodCategory: Int] {
        Dictionary(grouping: appState.pantryItems, by: { $0.category })
            .mapValues { $0.count }
    }

    func addItem(_ item: PantryItem) async {
        await appState.addPantryItem(item)
    }

    func deleteItem(_ item: PantryItem) async {
        await appState.removePantryItem(item)
    }

    func updateItem(_ item: PantryItem) async {
        await appState.updatePantryItem(item)
    }

    func handleBarcodeScanned(_ barcode: String) async {
        isLoading = true
        defer { isLoading = false }

        if let result = await barcodeScanner.lookupBarcode(barcode) {
            let item = PantryItem(
                name: result.productName,
                category: result.category ?? .other,
                quantity: 1,
                unit: .piece,
                barcode: barcode,
                imageURL: result.imageURL
            )
            await addItem(item)
        }
    }

    func handleReceiptScanned(items: [String]) async {
        for itemName in items {
            let item = PantryItem(name: itemName, category: .other)
            await addItem(item)
        }
    }
}
