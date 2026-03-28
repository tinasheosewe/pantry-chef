import SwiftUI

// MARK: - Design Tokens

enum PCTokens {
    // MARK: Layout
    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSmall: CGFloat = 10
    static let cardShadowRadius: CGFloat = 4
    static let cardShadowY: CGFloat = 2
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 24
    static let rowHeight: CGFloat = 56
    static let iconSize: CGFloat = 24
    static let iconSizeSmall: CGFloat = 20
    static let iconSizeLarge: CGFloat = 32
    static let chipHeight: CGFloat = 34
    static let miniPlayerHeight: CGFloat = 56
    static let tabBarHeight: CGFloat = 56
    static let fabSize: CGFloat = 56

    // MARK: Spacing
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32
}

// MARK: - Semantic Colors

enum PCColors {
    // Brand
    static let accent = Color(red: 0.87, green: 0.36, blue: 0.24)
    static let accentSecondary = Color(red: 0.91, green: 0.49, blue: 0.19)

    // Greens
    static let fresh = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let freshSubtle = Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.12)

    // Amber / Warning
    static let expiring = Color(red: 0.98, green: 0.62, blue: 0.20)
    static let expiringSubtle = Color(red: 0.98, green: 0.62, blue: 0.20).opacity(0.12)

    // Red / Error
    static let expired = Color(red: 0.96, green: 0.40, blue: 0.40)
    static let expiredSubtle = Color(red: 0.96, green: 0.40, blue: 0.40).opacity(0.12)

    // Blues
    static let info = Color(red: 0.24, green: 0.51, blue: 0.96)
    static let infoSubtle = Color(red: 0.24, green: 0.51, blue: 0.96).opacity(0.12)

    // Teal
    static let teal = Color(red: 0.06, green: 0.73, blue: 0.70)

    // Neutrals (adaptive)
    static var background: Color { Color(.systemGroupedBackground) }
    static var cardBackground: Color { Color(.secondarySystemGroupedBackground) }
    static var surfaceSecondary: Color { Color(.tertiarySystemGroupedBackground) }
    static var textPrimary: Color { Color(.label) }
    static var textSecondary: Color { Color(.secondaryLabel) }
    static var textTertiary: Color { Color(.tertiaryLabel) }
    static var separator: Color { Color(.separator) }
    static var fill: Color { Color(.systemFill) }
    static var fillSecondary: Color { Color(.secondarySystemFill) }
    static var fillTertiary: Color { Color(.tertiarySystemFill) }
}

// MARK: - Font Tokens

enum PCFont {
    static let largeTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    static let title = Font.system(size: 20, weight: .bold, design: .default)
    static let headline = Font.system(size: 17, weight: .semibold, design: .default)
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    static let callout = Font.system(size: 14, weight: .regular, design: .default)
    static let caption = Font.system(size: 13, weight: .regular, design: .default)
    static let captionBold = Font.system(size: 13, weight: .semibold, design: .default)
    static let micro = Font.system(size: 11, weight: .medium, design: .default)
}

// MARK: - Card Shadow

struct PCCardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(
                color: Color.black.opacity(0.06),
                radius: PCTokens.cardShadowRadius,
                x: 0,
                y: PCTokens.cardShadowY
            )
    }
}

extension View {
    func pcCardShadow() -> some View {
        modifier(PCCardShadow())
    }

    func pcCard() -> some View {
        self
            .background(PCColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadius))
            .pcCardShadow()
    }
}
