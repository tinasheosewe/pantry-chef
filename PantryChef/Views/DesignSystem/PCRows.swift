import SwiftUI

// MARK: - PCListRow

struct PCListRow<Leading: View, Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let leading: Leading
    private let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: PCTokens.spacingMD) {
            leading

            VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
                Text(title)
                    .font(PCFont.body)
                    .foregroundStyle(PCColors.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(PCFont.caption)
                        .foregroundStyle(PCColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            trailing
        }
        .frame(minHeight: PCTokens.rowHeight)
        .padding(.horizontal, PCTokens.cardPadding)
        .contentShape(Rectangle())
    }
}

// MARK: - PCCheckableRow

struct PCCheckableRow: View {
    let isChecked: Bool
    let title: String
    var detail: String?
    var trailingText: String?
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: PCTokens.spacingMD) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: PCTokens.iconSize))
                    .foregroundStyle(isChecked ? PCColors.fresh : PCColors.textTertiary)

                VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
                    Text(title)
                        .font(PCFont.body)
                        .foregroundStyle(isChecked ? PCColors.textTertiary : PCColors.textPrimary)
                        .strikethrough(isChecked)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(PCFont.caption)
                            .foregroundStyle(PCColors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if let trailingText {
                    Text(trailingText)
                        .font(PCFont.caption)
                        .foregroundStyle(PCColors.textSecondary)
                }
            }
            .frame(minHeight: PCTokens.rowHeight)
            .padding(.horizontal, PCTokens.cardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PCProgressRow

struct PCProgressRow: View {
    let title: String
    let progress: Double
    var detail: String?
    var tintColor: Color = PCColors.accent

    var body: some View {
        HStack(spacing: PCTokens.spacingMD) {
            VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
                Text(title)
                    .font(PCFont.body)
                    .foregroundStyle(PCColors.textPrimary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(PCFont.caption)
                        .foregroundStyle(PCColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            PCProgressRing(progress: progress, size: 28, lineWidth: 3, tintColor: tintColor)
        }
        .frame(minHeight: PCTokens.rowHeight)
        .padding(.horizontal, PCTokens.cardPadding)
        .contentShape(Rectangle())
    }
}

// MARK: - PCQuantityRow

struct PCQuantityRow: View {
    let title: String
    let quantity: String
    var unit: String?
    var statusColor: Color?
    var icon: String?
    var iconColor: Color?

    var body: some View {
        HStack(spacing: PCTokens.spacingMD) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: PCTokens.iconSizeSmall))
                    .foregroundStyle(iconColor ?? PCColors.textSecondary)
                    .frame(width: PCTokens.iconSizeLarge, height: PCTokens.iconSizeLarge)
                    .background(iconColor?.opacity(0.12) ?? PCColors.fillSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadiusSmall))
            }

            Text(title)
                .font(PCFont.body)
                .foregroundStyle(PCColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: PCTokens.spacingXS) {
                Text(quantity)
                    .font(PCFont.captionBold)
                if let unit {
                    Text(unit)
                        .font(PCFont.caption)
                }
            }
            .foregroundStyle(PCColors.textSecondary)
            .padding(.horizontal, PCTokens.spacingSM)
            .padding(.vertical, PCTokens.spacingXS)
            .background(statusColor?.opacity(0.12) ?? PCColors.fillSecondary)
            .clipShape(Capsule())
        }
        .frame(minHeight: PCTokens.rowHeight)
        .padding(.horizontal, PCTokens.cardPadding)
        .contentShape(Rectangle())
    }
}

// MARK: - PCDetailRow

struct PCDetailRow: View {
    private let title: String
    private let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PCTokens.spacingMD) {
            Text(title)
                .foregroundStyle(PCColors.textSecondary)
            Spacer(minLength: PCTokens.spacingMD)
            Text(value)
                .foregroundStyle(PCColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .font(PCFont.body)
    }
}

// MARK: - PCIngredientRow

struct PCIngredientRow: View {
    let ingredientText: String
    let isAvailable: Bool
    let isOptional: Bool
    var accessoryText: String?

    var body: some View {
        HStack(alignment: .top, spacing: PCTokens.spacingMD) {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isAvailable ? PCColors.fresh : PCColors.textTertiary)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: PCTokens.spacingXS + 2) {
                Text(ingredientText)
                    .font(PCFont.body)
                    .foregroundStyle(PCColors.textPrimary)

                HStack(spacing: PCTokens.spacingSM) {
                    if isOptional {
                        PCBadge(text: "optional", color: PCColors.textTertiary)
                    }
                    if let accessoryText, !accessoryText.isEmpty {
                        Text(accessoryText)
                            .font(PCFont.micro)
                            .foregroundStyle(PCColors.textSecondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}
