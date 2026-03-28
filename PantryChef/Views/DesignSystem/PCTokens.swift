import SwiftUI

// MARK: - Design Tokens

enum PCTokens {
    // MARK: Layout
    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSmall: CGFloat = 10
    static let cardShadowRadius: CGFloat = 18
    static let cardShadowY: CGFloat = 10
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
    static let accent = Color(red: 0.84, green: 0.48, blue: 0.24)
    static let accentSecondary = Color(red: 0.69, green: 0.56, blue: 0.28)

    // Greens
    static let fresh = Color(red: 0.45, green: 0.72, blue: 0.38)
    static let freshSubtle = Color(red: 0.45, green: 0.72, blue: 0.38).opacity(0.18)

    // Amber / Warning
    static let expiring = Color(red: 0.90, green: 0.67, blue: 0.32)
    static let expiringSubtle = Color(red: 0.90, green: 0.67, blue: 0.32).opacity(0.18)

    // Red / Error
    static let expired = Color(red: 0.76, green: 0.37, blue: 0.32)
    static let expiredSubtle = Color(red: 0.76, green: 0.37, blue: 0.32).opacity(0.18)

    // Blues
    static let info = Color(red: 0.42, green: 0.63, blue: 0.78)
    static let infoSubtle = Color(red: 0.42, green: 0.63, blue: 0.78).opacity(0.18)

    // Teal
    static let teal = Color(red: 0.35, green: 0.69, blue: 0.64)

    // Shell
    static let shellTop = Color(red: 0.15, green: 0.18, blue: 0.14)
    static let shellBottom = Color(red: 0.05, green: 0.06, blue: 0.05)
    static let shellGlow = Color(red: 0.41, green: 0.31, blue: 0.16).opacity(0.24)

    // Neutrals
    static var background: Color { shellBottom }
    static var cardBackground: Color { Color(red: 0.12, green: 0.14, blue: 0.11) }
    static var surfaceSecondary: Color { Color(red: 0.16, green: 0.19, blue: 0.15) }
    static var textPrimary: Color { Color(red: 0.95, green: 0.92, blue: 0.86) }
    static var textSecondary: Color { Color(red: 0.73, green: 0.70, blue: 0.64) }
    static var textTertiary: Color { Color(red: 0.50, green: 0.49, blue: 0.44) }
    static var separator: Color { Color.white.opacity(0.08) }
    static var fill: Color { Color.white.opacity(0.08) }
    static var fillSecondary: Color { Color.white.opacity(0.12) }
    static var fillTertiary: Color { Color.white.opacity(0.06) }

    static var shellGradient: LinearGradient {
        LinearGradient(
            colors: [shellTop, shellBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glassStroke: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
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
                color: Color.black.opacity(0.28),
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
            .overlay(
                RoundedRectangle(cornerRadius: PCTokens.cornerRadius)
                    .stroke(PCColors.glassStroke, lineWidth: 1)
            )
            .pcCardShadow()
    }
}
