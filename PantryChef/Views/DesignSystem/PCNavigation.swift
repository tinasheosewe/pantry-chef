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

// MARK: - PCTintedButton

struct PCTintedButton: View {
    let title: String
    var icon: String?
    var color: Color
    let action: () -> Void

    init(_ title: String, icon: String? = nil, color: Color = PCColors.accent, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let icon {
                    Image(systemName: icon)
                }
            }
            .font(PCFont.captionBold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, PCTokens.spacingMD)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: PCTokens.cornerRadius - 2))
        }
    }
}

// MARK: - PCCapsuleButton

struct PCCapsuleButton: View {
    let title: String
    var color: Color = PCColors.accent
    var style: Style = .filled
    let action: () -> Void

    enum Style {
        case filled, tinted, plain
    }

    init(_ title: String, color: Color = PCColors.accent, style: Style = .filled, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PCFont.captionBold)
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, PCTokens.spacingMD)
                .padding(.vertical, PCTokens.spacingSM)
                .background(backgroundColor)
                .clipShape(Capsule())
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .filled: return .white
        case .tinted, .plain: return color
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .filled: return color
        case .tinted: return color.opacity(0.12)
        case .plain: return PCColors.fillTertiary
        }
    }
}


