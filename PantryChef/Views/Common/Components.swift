import SwiftUI

// MARK: - App Colors
struct AppColors {
    @Environment(\.colorScheme) static var colorScheme

    static let primary = Color("AccentColor")

    // Brand palette — bright & warm
    static let primaryGreen = Color(red: 0.13, green: 0.77, blue: 0.37)   // #22C55E — vivid emerald
    static let warmOrange  = Color(red: 0.98, green: 0.62, blue: 0.20)    // #FA9E33 — sunny amber
    static let softRed     = Color(red: 0.96, green: 0.40, blue: 0.40)    // #F56565 — warm coral

    // Neutral palette — clean & airy
    static let lightGray   = Color(red: 0.965, green: 0.969, blue: 0.976) // #F7F8F9 — near-white
    static let mediumGray  = Color(.systemGray3)
    static let darkText    = Color(red: 0.15, green: 0.16, blue: 0.18)    // #262A2E — soft black
    static let subtleText  = Color(red: 0.44, green: 0.47, blue: 0.52)    // #707884 — muted slate
    static let cardBackground = Color.white
    static let background  = Color(red: 0.965, green: 0.969, blue: 0.976) // #F7F8F9

    // Accent helpers
    static let accentTeal  = Color(red: 0.06, green: 0.73, blue: 0.70)    // #0FBAB3 — teal pop
    static let accentBlue  = Color(red: 0.24, green: 0.51, blue: 0.96)    // #3D82F5 — vibrant blue

}

// MARK: - Card Style Modifier
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color(red: 0.15, green: 0.16, blue: 0.18).opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// MARK: - Screen Shells
struct AppScreen<Content: View>: View {
    private let screenID: String
    private let content: Content

    init(_ screenID: String, @ViewBuilder content: () -> Content) {
        self.screenID = screenID
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .accessibilityIdentifier(screenID)
                .background(AppColors.background)
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
    func appInputSurface(background: Color = AppColors.lightGray, cornerRadius: CGFloat = 10) -> some View {
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
                    .foregroundStyle(AppColors.mediumGray)
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
        background: Color = AppColors.lightGray,
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
                .foregroundStyle(AppColors.mediumGray)

            searchField

            if !text.isEmpty {
                Button {
                    trackedText.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.mediumGray)
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
    let items: [ShoppingItem]

    var title: String {
        if items.isEmpty {
            return "Nothing to Add"
        }
        return "Add \(items.count) Item\(items.count == 1 ? "" : "s")?"
    }

    var message: String {
        if items.isEmpty {
            return "Everything needed is already in your pantry."
        }
        return "This will add these items to your cart and exclude ingredients you already have in your pantry."
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
                Button("Add Items") {
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
                    .foregroundStyle(index <= difficulty.rawValue ? AppColors.warmOrange : AppColors.mediumGray)
            }
            Text(difficulty.label)
                .font(.caption2)
                .foregroundStyle(AppColors.subtleText)
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
        .background(isSelected ? AppColors.primaryGreen.opacity(0.15) : AppColors.lightGray)
        .foregroundStyle(isSelected ? AppColors.primaryGreen : AppColors.subtleText)
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
                .foregroundStyle(AppColors.subtleText)
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
                .foregroundStyle(AppColors.mediumGray)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.darkText)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColors.subtleText)
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
                        .background(AppColors.primaryGreen)
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
                    .foregroundStyle(AppColors.darkText)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppColors.subtleText)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.primaryGreen)
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
                    .foregroundStyle(AppColors.subtleText)
                Spacer()
                Text("\(Int(value))\(unit)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.darkText)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.lightGray)
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
