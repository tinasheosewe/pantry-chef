import SwiftUI

struct KitchenView: View {
    enum Segment: String, CaseIterable, Hashable {
        case pantry = "Pantry"
        case prepared = "Prepared"
        case shopping = "Shopping"
    }

    @State private var segment: Segment = .pantry
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some View {
        AppScreen("kitchen.screen") {
            VStack(spacing: 0) {
                PCSegmentedPicker(
                    items: Segment.allCases,
                    selection: $segment,
                    label: { $0.rawValue },
                    badge: { badgeCount(for: $0) }
                )
                .pickerPadding()

                switch segment {
                case .pantry:
                    PantryView(appState: appState, isEmbedded: true)
                case .prepared:
                    PreparedDishesView(appState: appState, isEmbedded: true)
                case .shopping:
                    ShoppingListView(appState: appState, isEmbedded: true)
                }
            }
            .navigationTitle("Prepared Food")
        }
    }

    private func badgeCount(for segment: Segment) -> Int? {
        switch segment {
        case .pantry:
            let count = appState.pantryItems.count
            return count > 0 ? count : nil
        case .prepared:
            let count = appState.preparedDishes.count
            return count > 0 ? count : nil
        case .shopping:
            let count = appState.shoppingItems.count
            return count > 0 ? count : nil
        }
    }
}
