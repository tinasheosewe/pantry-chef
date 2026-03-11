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
