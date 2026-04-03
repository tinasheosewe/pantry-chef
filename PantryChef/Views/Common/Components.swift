import SwiftUI

extension Image {
    func pcTopBarIcon() -> some View {
        self
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 20, height: 20)
    }
}

// MARK: - Screen Shells
struct AppScreen<Content: View>: View {
    private let screenID: String
    private let isEmbedded: Bool
    private let content: Content

    init(_ screenID: String, isEmbedded: Bool = false, @ViewBuilder content: () -> Content) {
        self.screenID = screenID
        self.isEmbedded = isEmbedded
        self.content = content()
    }

    var body: some View {
        if isEmbedded {
            content
                .accessibilityIdentifier(screenID)
                .background(PCColors.background)
        } else {
            NavigationStack {
                content
                    .accessibilityIdentifier(screenID)
                    .background(PCColors.background)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

struct AppNavigationSheet<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension View {
    func appNavigationSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented) {
            AppNavigationSheet(content: content)
        }
    }

    func appNavigationSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        sheet(item: item) { item in
            AppNavigationSheet {
                content(item)
            }
        }
    }
}

struct AppDetailCard<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle)
            content
        }
        .padding()
        .pcCard()
    }
}

struct AppDetailRow: View {
    private let title: String
    private let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(PCColors.textSecondary)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(PCColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct AppDetailRowGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
    }
}

struct AppIngredientDetailRow: View {
    let ingredientText: String
    let isAvailable: Bool
    let isOptional: Bool
    var accessoryText: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isAvailable ? PCColors.fresh : PCColors.separator)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 6) {
                Text(ingredientText)
                    .font(.subheadline)
                    .foregroundStyle(PCColors.textPrimary)

                HStack(spacing: 8) {
                    if isOptional {
                        Text("optional")
                            .font(.caption2)
                            .foregroundStyle(PCColors.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PCColors.fillTertiary)
                            .clipShape(Capsule())
                    }

                    if let accessoryText, !accessoryText.isEmpty {
                        Text(accessoryText)
                            .font(.caption2)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

struct AppIngredientDetailGroup<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        AppDetailCard(title, subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
    }
}

struct PantryCookReviewSheet: View {
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Update Pantry?")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(PCColors.textPrimary)

                        Text("Mark what you finished while cooking \(recipeTitle). Nothing is removed automatically.")
                            .font(.subheadline)
                            .foregroundStyle(PCColors.textSecondary)
                    }

                    if !exactItems.isEmpty {
                        reviewSection(title: "Tracked Exactly", subtitle: "You can subtract the recipe amount or mark the item as used up.", items: exactItems)
                    }

                    if !presenceOnlyItems.isEmpty {
                        reviewSection(title: "Tracked By Presence", subtitle: "These items can only be kept or removed.", items: presenceOnlyItems)
                    }
                }
                .padding()
            }
        }
        .background(PCColors.background)
        .navigationTitle("Pantry Review")
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
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle)

            ForEach(items) { item in
                PantryCookReviewRow(item: binding(for: item))
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

private struct PantryCookReviewRow: View {
    @Binding var item: PantryCookReviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(item.availableSelections) { selection in
                    Button {
                        item.selection = selection
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selection.systemImage)
                                .font(.caption)
                            Text(selection.title)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(item.selection == selection ? Color.white : buttonForeground(for: selection))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(item.selection == selection ? buttonBackground(for: selection) : buttonBackground(for: selection).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.pantryItem.name)
                        .font(.headline)
                        .foregroundStyle(PCColors.textPrimary)

                    Text(item.pantryDetailText)
                        .font(.subheadline)
                        .foregroundStyle(PCColors.textSecondary)

                    Text(item.recipeUsageText)
                        .font(.caption)
                        .foregroundStyle(PCColors.textPrimary)

                    if !item.matchedIngredientNames.isEmpty {
                        Text(item.matchedIngredientNames.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                }

                Spacer(minLength: 12)

                Text(item.quantityMode.title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(quantityModeColor.opacity(0.14))
                    .foregroundStyle(quantityModeColor)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(PCColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 2)
    }

    private var quantityModeColor: Color {
        item.quantityMode == .exact ? PCColors.info : PCColors.expiring
    }

    private func buttonBackground(for selection: PantryCookReviewSelection) -> Color {
        switch selection {
        case .keep:
            return PCColors.fresh
        case .remove:
            return PCColors.expired
        case .subtractRecipeAmount:
            return PCColors.info
        }
    }

    private func buttonForeground(for selection: PantryCookReviewSelection) -> Color {
        switch selection {
        case .keep:
            return PCColors.fresh
        case .remove:
            return PCColors.expired
        case .subtractRecipeAmount:
            return PCColors.info
        }
    }
}

// MARK: - Input Styling
private struct AppInputSurfaceModifier: ViewModifier {
    let background: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

private struct AppTextEntryModifier: ViewModifier {
    let autocapitalization: TextInputAutocapitalization?
    let autocorrectionDisabled: Bool
    let expandsTapTarget: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let configuredContent = content
            .textInputAutocapitalization(autocapitalization)
            .disableAutocorrection(autocorrectionDisabled)

        if expandsTapTarget {
            configuredContent.expandedTapTargetForTextInput()
        } else {
            configuredContent
        }
    }
}

extension View {
    func appInputSurface(background: Color = PCColors.fillTertiary, cornerRadius: CGFloat = 10) -> some View {
        modifier(AppInputSurfaceModifier(background: background, cornerRadius: cornerRadius))
    }

    func appTextEntry(
        autocapitalization: TextInputAutocapitalization? = nil,
        autocorrectionDisabled: Bool = false,
        expandsTapTarget: Bool = true
    ) -> some View {
        modifier(
            AppTextEntryModifier(
                autocapitalization: autocapitalization,
                autocorrectionDisabled: autocorrectionDisabled,
                expandsTapTarget: expandsTapTarget
            )
        )
    }
}

struct AppMultilineInput: View {
    @Binding private var text: String
    private let prompt: String
    private let minHeight: CGFloat
    private let cornerRadius: CGFloat

    init(
        text: Binding<String>,
        prompt: String,
        minHeight: CGFloat = 80,
        cornerRadius: CGFloat = 10
    ) {
        _text = text
        self.prompt = prompt
        self.minHeight = minHeight
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(PCColors.separator)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }

            TextEditor(text: $text)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
        }
        .frame(minHeight: minHeight)
        .appInputSurface(cornerRadius: cornerRadius)
    }
}

struct AppSearchField: View {
    @Binding private var text: String

    private let placeholder: String
    private let focus: FocusState<Bool>.Binding?
    private let onTextChange: ((String) -> Void)?
    private let background: Color
    private let cornerRadius: CGFloat
    private let padding: CGFloat

    init(
        _ placeholder: String,
        text: Binding<String>,
        focus: FocusState<Bool>.Binding? = nil,
        background: Color = PCColors.fillTertiary,
        cornerRadius: CGFloat = 10,
        padding: CGFloat = 10,
        onTextChange: ((String) -> Void)? = nil
    ) {
        self.placeholder = placeholder
        _text = text
        self.focus = focus
        self.background = background
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.onTextChange = onTextChange
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(PCColors.separator)

            searchField

            if !text.isEmpty {
                Button {
                    trackedText.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PCColors.separator)
                }
            }
        }
        .padding(padding)
        .appInputSurface(background: background, cornerRadius: cornerRadius)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onTapGesture {
            focus?.wrappedValue = true
        }
    }

    private var trackedText: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                text = newValue
                onTextChange?(newValue)
            }
        )
    }

    @ViewBuilder
    private var searchField: some View {
        let field = TextField(placeholder, text: trackedText)
            .font(.subheadline)
            .appTextEntry(autocapitalization: .words, autocorrectionDisabled: true)

        if let focus {
            field.focused(focus)
        } else {
            field
        }
    }
}

// MARK: - Shopping Confirmation
struct ShoppingListConfirmationRequest {
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

private struct ShoppingListConfirmationModifier: ViewModifier {
    @Binding var request: ShoppingListConfirmationRequest?
    let onConfirm: ([ShoppingItem]) -> Void

    private var isPresented: Binding<Bool> {
        Binding(
            get: { request != nil },
            set: { isShowing in
                if !isShowing {
                    request = nil
                }
            }
        )
    }

    func body(content: Content) -> some View {
        let currentRequest = request

        return content.alert(currentRequest?.title ?? "", isPresented: isPresented) {
            if let currentRequest, currentRequest.items.isEmpty {
                Button("OK", role: .cancel) {
                    request = nil
                }
            } else if let currentRequest {
                Button("Cancel", role: .cancel) {
                    request = nil
                }
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
    func shoppingListConfirmation(
        _ request: Binding<ShoppingListConfirmationRequest?>,
        onConfirm: @escaping ([ShoppingItem]) -> Void
    ) -> some View {
        modifier(ShoppingListConfirmationModifier(request: request, onConfirm: onConfirm))
    }
}

// MARK: - Expiry Badge
struct ExpiryBadge: View {
    let status: ExpiryStatus
    let daysLeft: Int?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)

            Text(badgeText)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
            .background(status.color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var badgeText: String {
        switch status {
        case .expired: return "Expired"
        case .expiringSoon:
            if let days = daysLeft {
                return days == 0 ? "Today" : days == 1 ? "Tomorrow" : "\(days)d left"
            }
            return "Soon"
        case .fresh:
            if let days = daysLeft {
                return "\(days)d left"
            }
            return "Fresh"
        }
    }
}

// MARK: - Category Icon
struct CategoryIcon: View {
    let category: FoodCategory
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: category.icon)
            .font(.system(size: size * 0.5))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}

// MARK: - Difficulty Badge
struct DifficultyBadge: View {
    let difficulty: DifficultyLevel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(index <= difficulty.rawValue ? PCColors.expiring : PCColors.separator)
            }
            Text(difficulty.label)
                .font(.caption2)
                .foregroundStyle(PCColors.textSecondary)
        }
    }
}

// MARK: - Dietary Tag Chip
struct DietaryTagChip: View {
    let tag: DietaryTag
    var isSelected = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tag.icon)
                .font(.caption2)
            Text(tag.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? PCColors.fresh.opacity(0.15) : PCColors.fillTertiary)
        .foregroundStyle(isSelected ? PCColors.fresh : PCColors.textSecondary)
        .clipShape(Capsule())
    }
}

// MARK: - Loading View
struct LoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(PCColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(PCColors.separator)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(PCColors.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(PCColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(PCColors.accent)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }
        }
        .padding()
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PCColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(PCColors.accent)
                }
            }
        }
    }
}

// MARK: - Nutrition Bar
struct NutritionBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    let color: Color
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(PCColors.textSecondary)
                Spacer()
                Text("\(Int(value))\(unit)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(PCColors.textPrimary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PCColors.fillTertiary)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * safeRatio, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private var safeRatio: Double {
        guard maxValue > 0, value.isFinite, maxValue.isFinite else { return 0 }
        return max(0, min(value / maxValue, 1))
    }
}
