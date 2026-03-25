import SwiftUI

// MARK: - PCTabBar

struct PCTabBar: View {
    @Binding var selectedTab: RootTab
    var showMiniPlayer: Bool = false
    var miniPlayerContent: AnyView?

    var body: some View {
        VStack(spacing: 0) {
            if showMiniPlayer, let miniPlayerContent {
                miniPlayerContent
            }

            Divider()

            HStack(spacing: 0) {
                ForEach(RootTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: PCTokens.spacingXS) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20))
                                .symbolVariant(selectedTab == tab ? .fill : .none)
                            Text(tab.rawValue)
                                .font(PCFont.micro)
                        }
                        .foregroundStyle(selectedTab == tab ? PCColors.accent : PCColors.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, PCTokens.spacingSM)
                        .padding(.bottom, PCTokens.spacingXS)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("root.tabButton.\(tab.rawValue.lowercased())")
                }
            }
            .padding(.horizontal, PCTokens.spacingSM)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - PCMiniPlayer

struct PCMiniPlayer: View {
    let recipeName: String
    let stepProgress: String
    let progress: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: PCTokens.spacingMD) {
                Image(systemName: "frying.pan.fill")
                    .font(.system(size: PCTokens.iconSizeSmall))
                    .foregroundStyle(PCColors.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recipeName)
                        .font(PCFont.captionBold)
                        .foregroundStyle(PCColors.textPrimary)
                        .lineLimit(1)
                    Text(stepProgress)
                        .font(PCFont.micro)
                        .foregroundStyle(PCColors.textSecondary)
                }

                Spacer(minLength: 0)

                PCProgressRing(progress: progress, size: 28, lineWidth: 3, tintColor: PCColors.accent)

                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PCColors.textTertiary)
            }
            .padding(.horizontal, PCTokens.spacingLG)
            .padding(.vertical, PCTokens.spacingMD)
            .background(PCColors.cardBackground)
            .pcCardShadow()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PCFilterChips

struct PCFilterChips<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item?
    let label: (Item) -> String
    var heroItem: Item?

    var body: some View {
        PCChipPicker(
            items: items,
            selection: $selection,
            label: label,
            heroItem: heroItem
        )
    }
}

// MARK: - PCFABButton

struct PCFABButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: PCTokens.iconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: PCTokens.fabSize, height: PCTokens.fabSize)
                .background(PCColors.accent)
                .clipShape(Circle())
                .shadow(color: PCColors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - PCOverflowMenu

struct PCOverflowMenu<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: PCTokens.iconSize))
                .foregroundStyle(PCColors.textSecondary)
        }
    }
}

// MARK: - PCFeedbackBanner

struct PCFeedbackBanner: View {
    let message: String
    var icon: String = "checkmark.circle.fill"
    var style: BannerStyle = .success

    enum BannerStyle {
        case success, warning, error, info

        var color: Color {
            switch self {
            case .success: return PCColors.fresh
            case .warning: return PCColors.expiring
            case .error: return PCColors.expired
            case .info: return PCColors.info
            }
        }
    }

    var body: some View {
        HStack(spacing: PCTokens.spacingSM) {
            Image(systemName: icon)
                .foregroundStyle(style.color)
            Text(message)
                .font(PCFont.captionBold)
                .foregroundStyle(PCColors.textPrimary)
            Spacer()
        }
        .padding(PCTokens.spacingMD)
        .background(style.color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadiusSmall))
    }
}

// MARK: - PCPrimaryButton

struct PCPrimaryButton: View {
    let title: String
    var icon: String?
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PCTokens.spacingSM) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: PCTokens.iconSizeSmall))
                }
                Text(title)
                    .font(PCFont.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, PCTokens.spacingMD + 2)
            .background(isDisabled ? PCColors.textTertiary : PCColors.accent)
            .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadius))
        }
        .disabled(isDisabled || isLoading)
    }
}

// MARK: - PCSecondaryButton

struct PCSecondaryButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PCTokens.spacingSM) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: PCTokens.iconSizeSmall))
                }
                Text(title)
                    .font(PCFont.captionBold)
            }
            .foregroundStyle(PCColors.accent)
            .padding(.horizontal, PCTokens.spacingLG)
            .padding(.vertical, PCTokens.spacingSM + 2)
            .background(PCColors.accent.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Pantry Cook Review (migrated from Components.swift)

struct PCPantryCookReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let recipeTitle: String
    let onApply: ([PantryCookReviewItem]) async -> Void
    let onCompletion: () -> Void

    @Binding private var items: [PantryCookReviewItem]
    @State private var isApplying = false

    init(
        recipeTitle: String,
        items: Binding<[PantryCookReviewItem]>,
        onApply: @escaping ([PantryCookReviewItem]) async -> Void,
        onCompletion: @escaping () -> Void = {}
    ) {
        self.recipeTitle = recipeTitle
        self.onApply = onApply
        self.onCompletion = onCompletion
        _items = items
    }

    private var exactItems: [PantryCookReviewItem] {
        items.filter { $0.quantityMode == .exact }
    }

    private var presenceOnlyItems: [PantryCookReviewItem] {
        items.filter { $0.quantityMode == .presenceOnly }
    }

    var body: some View {
        VStack(spacing: 0) {
            PCScrollView {
                VStack(alignment: .leading, spacing: PCTokens.spacingXL) {
                    VStack(alignment: .leading, spacing: PCTokens.spacingSM) {
                        Text("Update Pantry?")
                            .font(PCFont.title)
                            .foregroundStyle(PCColors.textPrimary)

                        Text("Mark what you finished while cooking \(recipeTitle). Nothing is removed automatically.")
                            .font(PCFont.body)
                            .foregroundStyle(PCColors.textSecondary)
                    }

                    if !exactItems.isEmpty {
                        reviewSection(
                            title: "Tracked Exactly",
                            subtitle: "You can subtract the recipe amount or mark the item as used up.",
                            items: exactItems
                        )
                    }

                    if !presenceOnlyItems.isEmpty {
                        reviewSection(
                            title: "Tracked By Presence",
                            subtitle: "These items can only be kept or removed.",
                            items: presenceOnlyItems
                        )
                    }
                }
                .padding()
            }
        }
        .background(PCColors.background)
        .navigationTitle("Pantry Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                    onCompletion()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Update") {
                    Task {
                        isApplying = true
                        await onApply(items)
                        isApplying = false
                        dismiss()
                        onCompletion()
                    }
                }
                .fontWeight(.semibold)
                .disabled(isApplying)
            }
        }
    }

    private func reviewSection(title: String, subtitle: String, items: [PantryCookReviewItem]) -> some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
            PCSectionHeader(title: title, subtitle: subtitle)

            ForEach(items) { item in
                PCPantryCookReviewRow(item: binding(for: item))
            }
        }
    }

    private func binding(for item: PantryCookReviewItem) -> Binding<PantryCookReviewItem> {
        Binding(
            get: { items.first(where: { $0.id == item.id }) ?? item },
            set: { updated in
                guard let index = items.firstIndex(where: { $0.id == updated.id }) else { return }
                items[index] = updated
            }
        )
    }
}

private struct PCPantryCookReviewRow: View {
    @Binding var item: PantryCookReviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
            HStack(alignment: .top, spacing: PCTokens.spacingMD) {
                VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
                    Text(item.pantryItem.name)
                        .font(PCFont.headline)
                        .foregroundStyle(PCColors.textPrimary)

                    Text(item.pantryDetailText)
                        .font(PCFont.body)
                        .foregroundStyle(PCColors.textSecondary)

                    Text(item.recipeUsageText)
                        .font(PCFont.caption)
                        .foregroundStyle(PCColors.textPrimary)

                    if !item.matchedIngredientNames.isEmpty {
                        Text(item.matchedIngredientNames.joined(separator: ", "))
                            .font(PCFont.micro)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                }

                Spacer(minLength: PCTokens.spacingMD)

                PCBadge(
                    text: item.quantityMode.title,
                    color: item.quantityMode == .exact ? PCColors.info : PCColors.expiring
                )
            }

            HStack(spacing: PCTokens.spacingSM) {
                ForEach(item.availableSelections) { selection in
                    Button {
                        item.selection = selection
                    } label: {
                        HStack(spacing: PCTokens.spacingXS) {
                            Image(systemName: selection.systemImage)
                                .font(PCFont.caption)
                            Text(selection.title)
                                .font(PCFont.captionBold)
                        }
                        .foregroundStyle(
                            item.selection == selection
                                ? Color.white
                                : selectionColor(for: selection)
                        )
                        .padding(.horizontal, PCTokens.spacingMD)
                        .padding(.vertical, PCTokens.spacingSM)
                        .background(
                            item.selection == selection
                                ? selectionColor(for: selection)
                                : selectionColor(for: selection).opacity(0.12)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(PCTokens.cardPadding)
        .pcCard()
    }

    private func selectionColor(for selection: PantryCookReviewSelection) -> Color {
        switch selection {
        case .keep: return PCColors.fresh
        case .remove: return PCColors.expired
        case .subtractRecipeAmount: return PCColors.info
        }
    }
}

// MARK: - Shopping List Confirmation (migrated from Components.swift)

struct PCShoppingConfirmationRequest {
    enum Context {
        case generic
        case mealPlan
    }

    let items: [ShoppingItem]
    let context: Context

    init(items: [ShoppingItem], context: Context = .generic) {
        self.items = items
        self.context = context
    }

    var title: String {
        if items.isEmpty {
            return "Nothing to Add"
        }
        switch context {
        case .generic:
            return "Add \(items.count) Item\(items.count == 1 ? "" : "s")?"
        case .mealPlan:
            return "Add Missing Ingredients?"
        }
    }

    var message: String {
        if items.isEmpty {
            switch context {
            case .generic:
                return "Everything needed is already in your pantry."
            case .mealPlan:
                return "Your meal plan is already covered by what you have on hand."
            }
        }
        switch context {
        case .generic:
            return "This will add these items to your cart and exclude ingredients you already have in your pantry."
        case .mealPlan:
            return "We'll add the ingredients you're still missing from your meal plan to your shopping list."
        }
    }
}

private struct PCShoppingConfirmationModifier: ViewModifier {
    @Binding var request: PCShoppingConfirmationRequest?
    let onConfirm: ([ShoppingItem]) -> Void

    private var isPresented: Binding<Bool> {
        Binding(
            get: { request != nil },
            set: { isShowing in if !isShowing { request = nil } }
        )
    }

    func body(content: Content) -> some View {
        let currentRequest = request

        return content.alert(currentRequest?.title ?? "", isPresented: isPresented) {
            if let currentRequest, currentRequest.items.isEmpty {
                Button("OK", role: .cancel) { request = nil }
            } else if let currentRequest {
                Button("Cancel", role: .cancel) { request = nil }
                Button(currentRequest.context == .mealPlan ? "Add to Shopping List" : "Add Items") {
                    onConfirm(currentRequest.items)
                    request = nil
                }
            }
        } message: {
            Text(currentRequest?.message ?? "")
        }
    }
}

extension View {
    func pcShoppingConfirmation(
        _ request: Binding<PCShoppingConfirmationRequest?>,
        onConfirm: @escaping ([ShoppingItem]) -> Void
    ) -> some View {
        modifier(PCShoppingConfirmationModifier(request: request, onConfirm: onConfirm))
    }
}

// MARK: - Input Styling (migrated)

private struct PCInputSurfaceModifier: ViewModifier {
    let background: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func pcInputSurface(background: Color = PCColors.fillTertiary, cornerRadius: CGFloat = PCTokens.cornerRadiusSmall) -> some View {
        modifier(PCInputSurfaceModifier(background: background, cornerRadius: cornerRadius))
    }
}
