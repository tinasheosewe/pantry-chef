import SwiftUI

// MARK: - App Colors
struct AppColors {
    @Environment(\.colorScheme) static var colorScheme

    static let primary = Color("AccentColor")
    static let primaryGreen = Color(red: 0.30, green: 0.69, blue: 0.31)
    static let warmOrange = Color(red: 0.96, green: 0.65, blue: 0.14)
    static let softRed = Color(red: 0.90, green: 0.30, blue: 0.24)
    static let lightGray = Color(.systemGray6)
    static let mediumGray = Color(.systemGray3)
    static let darkText = Color(.label)
    static let subtleText = Color(.secondaryLabel)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let background = Color(.systemGroupedBackground)

    static func categoryColor(_ category: FoodCategory) -> Color {
        switch category {
        case .dairy: return .blue.opacity(0.7)
        case .produce: return .green
        case .protein: return .red.opacity(0.7)
        case .grains: return .orange.opacity(0.8)
        case .spices: return .orange
        case .condiments: return .purple.opacity(0.7)
        case .bakingSupplies: return .pink
        case .frozenFoods: return .cyan
        case .canned: return .brown
        case .beverages: return .teal
        case .snacks: return .yellow.opacity(0.8)
        case .oils: return Color(red: 0.85, green: 0.65, blue: 0.13)
        case .pasta: return .indigo.opacity(0.7)
        case .nuts: return Color(red: 0.82, green: 0.71, blue: 0.55)
        case .other: return .gray
        }
    }

    static func expiryColor(_ status: ExpiryStatus) -> Color {
        switch status {
        case .fresh: return primaryGreen
        case .expiringSoon: return warmOrange
        case .expired: return softRed
        }
    }
}

// MARK: - Card Style Modifier
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
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
                .fill(AppColors.expiryColor(status))
                .frame(width: 8, height: 8)

            Text(badgeText)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(AppColors.expiryColor(status))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppColors.expiryColor(status).opacity(0.12))
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
            .background(AppColors.categoryColor(category))
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
                        .frame(width: min(geometry.size.width * (value / maxValue), geometry.size.width), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}
