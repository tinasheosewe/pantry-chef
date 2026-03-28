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
                VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
                    Text("Kitchen")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(PCColors.textPrimary)

                    Text("Move between pantry stock, prepared dishes, and shopping without leaving the kitchen workflow.")
                        .font(PCFont.body)
                        .foregroundStyle(PCColors.textSecondary)

                    HStack(spacing: PCTokens.spacingSM) {
                        kitchenCountPill(title: "Pantry", count: appState.pantryItems.count, tint: PCColors.accent)
                        kitchenCountPill(title: "Prepared", count: appState.preparedDishes.count, tint: PCColors.expiring)
                        kitchenCountPill(title: "Shopping", count: appState.shoppingItems.count, tint: PCColors.info)
                    }

                    PCSegmentedPicker(
                        items: Segment.allCases,
                        selection: $segment,
                        label: { $0.rawValue },
                        badge: { badgeCount(for: $0) }
                    )
                }
                .padding()
                .pcCard()
                .padding(.horizontal)
                .padding(.top, PCTokens.spacingSM)

                Group {
                    switch segment {
                    case .pantry:
                        PantryView(appState: appState, isEmbedded: true)
                    case .prepared:
                        PreparedDishesView(appState: appState, isEmbedded: true)
                    case .shopping:
                        ShoppingListView(appState: appState, isEmbedded: true)
                    }
                }
            }
            .navigationTitle("Kitchen")
        }
    }

    private func kitchenCountPill(title: String, count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(PCFont.captionBold)
                .foregroundStyle(PCColors.textPrimary)
            Text(title)
                .font(PCFont.micro)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PCColors.fillTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
