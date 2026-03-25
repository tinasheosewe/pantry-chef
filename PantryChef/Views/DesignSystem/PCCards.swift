import SwiftUI

// MARK: - PCCard

struct PCCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = PCTokens.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .pcCard()
    }
}

// MARK: - PCInfoCard

struct PCInfoCard<Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
            PCSectionHeader(title: title, subtitle: subtitle)
            content
        }
        .padding(PCTokens.cardPadding)
        .pcCard()
    }
}

// MARK: - PCSummaryCard

struct PCSummaryCard<Accessory: View>: View {
    private let icon: String
    private let iconColor: Color
    private let title: String
    private let subtitle: String?
    private let accessory: Accessory

    init(
        icon: String,
        iconColor: Color = PCColors.accent,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: PCTokens.spacingMD) {
            Image(systemName: icon)
                .font(.system(size: PCTokens.iconSize))
                .foregroundStyle(iconColor)
                .frame(width: PCTokens.iconSizeLarge, height: PCTokens.iconSizeLarge)

            VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
                Text(title)
                    .font(PCFont.headline)
                    .foregroundStyle(PCColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(PCFont.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }

            Spacer(minLength: 0)

            accessory
        }
        .padding(PCTokens.cardPadding)
        .pcCard()
    }
}

// MARK: - PCActionCard

struct PCActionCard: View {
    private let title: String
    private let message: String
    private let actionLabel: String
    private let icon: String?
    private let action: () -> Void

    init(
        title: String,
        message: String,
        actionLabel: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.icon = icon
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingMD) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: PCTokens.iconSizeLarge))
                    .foregroundStyle(PCColors.accent)
            }

            Text(title)
                .font(PCFont.headline)
                .foregroundStyle(PCColors.textPrimary)

            Text(message)
                .font(PCFont.caption)
                .foregroundStyle(PCColors.textSecondary)

            Button(action: action) {
                Text(actionLabel)
                    .font(PCFont.captionBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, PCTokens.spacingLG)
                    .padding(.vertical, PCTokens.spacingSM)
                    .background(PCColors.accent)
                    .clipShape(Capsule())
            }
        }
        .padding(PCTokens.cardPadding)
        .pcCard()
    }
}

// MARK: - Section Header

struct PCSectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
                Text(title)
                    .font(PCFont.headline)
                    .foregroundStyle(PCColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(PCFont.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(PCFont.captionBold)
                        .foregroundStyle(PCColors.accent)
                }
            }
        }
    }
}
