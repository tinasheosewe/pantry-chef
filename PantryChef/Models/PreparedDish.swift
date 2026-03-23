import Foundation

struct PreparedDish: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var mealTypes: [MealType]
    var servingsRemaining: Int
    var storage: PantryStorage
    var useByDate: Date?
    var dateAdded: Date
    var freshnessSource: PantryFreshnessSource
    var notes: String?
    var recipeID: UUID?
    var nutrition: NutritionInfo?

    init(
        id: UUID = UUID(),
        name: String,
        mealTypes: [MealType],
        servingsRemaining: Int,
        storage: PantryStorage,
        useByDate: Date? = nil,
        dateAdded: Date = Date(),
        freshnessSource: PantryFreshnessSource = .none,
        notes: String? = nil,
        recipeID: UUID? = nil,
        nutrition: NutritionInfo? = nil
    ) {
        self.id = id
        self.name = name.trimmed
        self.mealTypes = Self.normalizedMealTypes(mealTypes)
        self.servingsRemaining = max(1, servingsRemaining)
        self.storage = storage
        self.useByDate = useByDate
        self.dateAdded = dateAdded
        self.freshnessSource = useByDate == nil ? .none : freshnessSource
        self.notes = notes?.trimmed.nilIfEmpty
        self.recipeID = recipeID
        self.nutrition = nutrition
    }

    var expiryStatus: ExpiryStatus {
        guard let useByDate else { return .fresh }
        let now = Date()
        if useByDate < now {
            return .expired
        }
        let threeDaysFromNow = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
        if useByDate <= threeDaysFromNow {
            return .expiringSoon
        }
        return .fresh
    }

    var daysUntilUseBy: Int? {
        guard let useByDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: useByDate).day
    }

    var servingsDisplay: String {
        servingsRemaining == 1 ? "1 serving" : "\(servingsRemaining) servings"
    }

    var mealTypesSummary: String {
        mealTypes.map(\.rawValue).joined(separator: " • ")
    }

    var hasNutrition: Bool {
        nutrition != nil
    }

    static let samples: [PreparedDish] = [
        PreparedDish(
            name: "Lentil Soup",
            mealTypes: [.lunch, .dinner],
            servingsRemaining: 2,
            storage: .refrigerated,
            useByDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
            freshnessSource: .estimated,
            notes: "Leftover from batch cook"
        ),
        PreparedDish(
            name: "Takeout Sushi",
            mealTypes: [.lunch, .dinner],
            servingsRemaining: 1,
            storage: .refrigerated,
            useByDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
            freshnessSource: .userProvided
        ),
    ]

    private static func normalizedMealTypes(_ mealTypes: [MealType]) -> [MealType] {
        var seen = Set<MealType>()
        return mealTypes.filter { seen.insert($0).inserted }
    }
}

enum PreparedDishFreshnessPolicy {
    static func estimatedUseByDate(for storage: PantryStorage, referenceDate: Date = Date()) -> Date {
        let daysToAdd: Int
        switch storage {
        case .pantry:
            daysToAdd = 2
        case .refrigerated:
            daysToAdd = 4
        case .frozen:
            daysToAdd = 90
        }

        return Calendar.current.date(byAdding: .day, value: daysToAdd, to: referenceDate) ?? referenceDate
    }
}

struct PreparedDishDraft: Identifiable, Hashable {
    let id: UUID
    var name: String
    var mealTypes: Set<MealType>
    var servingsRemaining: Int
    var storage: PantryStorage
    var useEstimatedFreshness: Bool
    var manualUseByDate: Date
    var dateAdded: Date
    var notes: String
    var recipeID: UUID?
    var caloriesText: String
    var proteinText: String
    var carbsText: String
    var fatText: String

    init(id: UUID = UUID(), dish: PreparedDish? = nil) {
        self.id = dish?.id ?? id
        self.name = dish?.name ?? ""
        self.mealTypes = Set(dish?.mealTypes ?? [.lunch, .dinner])
        self.servingsRemaining = dish?.servingsRemaining ?? 1
        self.storage = dish?.storage ?? .refrigerated
        self.useEstimatedFreshness = dish?.freshnessSource != .userProvided
        self.manualUseByDate = dish?.useByDate ?? PreparedDishFreshnessPolicy.estimatedUseByDate(for: dish?.storage ?? .refrigerated)
        self.dateAdded = dish?.dateAdded ?? Date()
        self.notes = dish?.notes ?? ""
        self.recipeID = dish?.recipeID
        self.caloriesText = dish?.nutrition.map { String($0.calories) } ?? ""
        self.proteinText = dish?.nutrition.map { Self.decimalString($0.protein) } ?? ""
        self.carbsText = dish?.nutrition.map { Self.decimalString($0.carbohydrates) } ?? ""
        self.fatText = dish?.nutrition.map { Self.decimalString($0.fat) } ?? ""
    }

    var resolvedUseByDate: Date {
        useEstimatedFreshness ? PreparedDishFreshnessPolicy.estimatedUseByDate(for: storage, referenceDate: dateAdded) : manualUseByDate
    }

    var hasPartialNutrition: Bool {
        let fields = [caloriesText, proteinText, carbsText, fatText].map { !$0.trimmed.isEmpty }
        return fields.contains(true) && fields.contains(false)
    }

    var nutritionIsInvalid: Bool {
        guard !hasPartialNutrition else { return true }
        guard !caloriesText.trimmed.isEmpty else { return false }
        return Int(caloriesText.trimmed) == nil
            || Double(proteinText.trimmed) == nil
            || Double(carbsText.trimmed) == nil
            || Double(fatText.trimmed) == nil
    }

    var isValid: Bool {
        !name.trimmed.isEmpty && !mealTypes.isEmpty && servingsRemaining > 0 && !nutritionIsInvalid
    }

    func buildDish() -> PreparedDish? {
        guard isValid else { return nil }

        return PreparedDish(
            id: id,
            name: name,
            mealTypes: mealTypes.sorted { $0.rawValue < $1.rawValue },
            servingsRemaining: servingsRemaining,
            storage: storage,
            useByDate: resolvedUseByDate,
            dateAdded: dateAdded,
            freshnessSource: useEstimatedFreshness ? .estimated : .userProvided,
            notes: notes,
            recipeID: recipeID,
            nutrition: nutrition
        )
    }

    var nutrition: NutritionInfo? {
        guard !caloriesText.trimmed.isEmpty,
              let calories = Int(caloriesText.trimmed),
              let protein = Double(proteinText.trimmed),
              let carbohydrates = Double(carbsText.trimmed),
              let fat = Double(fatText.trimmed) else {
            return nil
        }

        return NutritionInfo(
            calories: calories,
            protein: protein,
            carbohydrates: carbohydrates,
            fat: fat,
            fiber: nil,
            sugar: nil,
            sodium: nil
        )
    }

    private static func decimalString(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    static func nutritionStrings(from nutrition: NutritionInfo) -> (protein: String, carbs: String, fat: String) {
        (
            protein: decimalString(nutrition.protein),
            carbs: decimalString(nutrition.carbohydrates),
            fat: decimalString(nutrition.fat)
        )
    }
}