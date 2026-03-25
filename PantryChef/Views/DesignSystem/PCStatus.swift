import SwiftUI

// MARK: - PCStatusDot

struct PCStatusDot: View {
    let color: Color
    var size: CGFloat = 8

    init(_ color: Color, size: CGFloat = 8) {
        self.color = color
        self.size = size
    }

    init(expiryStatus: ExpiryStatus, size: CGFloat = 8) {
        self.size = size
        switch expiryStatus {
        case .fresh: self.color = PCColors.fresh
        case .expiringSoon: self.color = PCColors.expiring
        case .expired: self.color = PCColors.expired
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// MARK: - PCProgressRing

struct PCProgressRing: View {
    let progress: Double
    var size: CGFloat = 40
    var lineWidth: CGFloat = 4
    var tintColor: Color = PCColors.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(tintColor.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(tintColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private var clampedProgress: Double {
        max(0, min(progress, 1))
    }
}

// MARK: - PCProgressRingLabeled

struct PCProgressRingLabeled: View {
    let progress: Double
    let label: String
    var size: CGFloat = 60
    var lineWidth: CGFloat = 5
    var tintColor: Color = PCColors.accent

    var body: some View {
        VStack(spacing: PCTokens.spacingXS) {
            ZStack {
                PCProgressRing(progress: progress, size: size, lineWidth: lineWidth, tintColor: tintColor)
                Text("\(Int(progress * 100))%")
                    .font(PCFont.micro)
                    .foregroundStyle(PCColors.textSecondary)
            }
            Text(label)
                .font(PCFont.micro)
                .foregroundStyle(PCColors.textSecondary)
        }
    }
}

// MARK: - PCBadge

struct PCBadge: View {
    let text: String
    var color: Color = PCColors.accent

    var body: some View {
        Text(text)
            .font(PCFont.micro)
            .fontWeight(.semibold)
            .padding(.horizontal, PCTokens.spacingSM)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - PCExpiryBadge

struct PCExpiryBadge: View {
    let status: ExpiryStatus
    let daysLeft: Int?

    var body: some View {
        HStack(spacing: PCTokens.spacingXS) {
            PCStatusDot(expiryStatus: status)
            Text(badgeText)
                .font(PCFont.micro)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, PCTokens.spacingSM)
        .padding(.vertical, PCTokens.spacingXS)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .fresh: return PCColors.fresh
        case .expiringSoon: return PCColors.expiring
        case .expired: return PCColors.expired
        }
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

// MARK: - PCCategoryIcon

struct PCCategoryIcon: View {
    let category: FoodCategory
    var size: CGFloat = PCTokens.iconSizeLarge

    var body: some View {
        Image(systemName: category.icon)
            .font(.system(size: size * 0.5))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
    }
}

// MARK: - PCDifficultyBadge

struct PCDifficultyBadge: View {
    let difficulty: DifficultyLevel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Circle()
                    .fill(index <= difficulty.rawValue ? PCColors.expiring : PCColors.fillSecondary)
                    .frame(width: 6, height: 6)
            }
            Text(difficulty.label)
                .font(PCFont.micro)
                .foregroundStyle(PCColors.textSecondary)
        }
    }
}

// MARK: - PCDietaryTagChip

struct PCDietaryTagChip: View {
    let tag: DietaryTag
    var isSelected = false

    var body: some View {
        HStack(spacing: PCTokens.spacingXS) {
            Image(systemName: tag.icon)
                .font(.system(size: 11))
            Text(tag.rawValue)
                .font(PCFont.micro)
        }
        .padding(.horizontal, PCTokens.spacingMD)
        .padding(.vertical, PCTokens.spacingXS + 2)
        .background(isSelected ? PCColors.fresh.opacity(0.15) : PCColors.fillTertiary)
        .foregroundStyle(isSelected ? PCColors.fresh : PCColors.textSecondary)
        .clipShape(Capsule())
    }
}

// MARK: - PCEmptyState

struct PCEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: PCTokens.spacingLG) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(PCColors.textTertiary)

            Text(title)
                .font(PCFont.headline)
                .foregroundStyle(PCColors.textPrimary)

            Text(message)
                .font(PCFont.body)
                .foregroundStyle(PCColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(PCFont.captionBold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, PCTokens.spacingXL)
                        .padding(.vertical, PCTokens.spacingMD)
                        .background(PCColors.accent)
                        .clipShape(Capsule())
                }
                .padding(.top, PCTokens.spacingSM)
            }
        }
        .padding()
    }
}

// MARK: - PCLoadingState

struct PCLoadingState: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: PCTokens.spacingLG) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(PCFont.body)
                .foregroundStyle(PCColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PCNutritionBar

struct PCNutritionBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    let color: Color
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: PCTokens.spacingXS) {
            HStack {
                Text(label)
                    .font(PCFont.caption)
                    .foregroundStyle(PCColors.textSecondary)
                Spacer()
                Text("\(Int(value))\(unit)")
                    .font(PCFont.captionBold)
                    .foregroundStyle(PCColors.textPrimary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PCColors.fillSecondary)
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
