import Foundation

enum PreparedFoodMatchKey: Hashable, Codable, Sendable {
    case recipe(UUID)
    case preparedFoodIdentity(UUID)
}

struct PreparedDish: Identifiable, Codable, Hashable {
    var id: UUID
    var foodIdentityID: UUID
    var name: String
    var mealTypes: [MealType]
    var servingsRemaining: Int
    var storage: PantryStorage
    var useByDate: Date?
    var dateAdded: Date
    var notes: String?
    var recipeID: UUID?
    var nutrition: NutritionInfo?

    init(
        id: UUID = UUID(),
        foodIdentityID: UUID = UUID(),
        name: String,
        mealTypes: [MealType],
        servingsRemaining: Int,
        storage: PantryStorage,
        useByDate: Date? = nil,
        dateAdded: Date = Date(),
        notes: String? = nil,
        recipeID: UUID? = nil,
        nutrition: NutritionInfo? = nil
    ) {
        self.id = id
        self.foodIdentityID = foodIdentityID
        self.name = name.trimmed
        self.mealTypes = Self.normalizedMealTypes(mealTypes)
        self.servingsRemaining = max(1, servingsRemaining)
        self.storage = storage
        self.useByDate = useByDate
        self.dateAdded = dateAdded
        self.notes = notes?.trimmed.nilIfEmpty
        self.recipeID = recipeID
        self.nutrition = nutrition
    }

    var expiryStatus: ExpiryStatus {
        .from(date: useByDate)
    }

    var daysUntilUseBy: Int? {
        ExpiryStatus.daysRemaining(until: useByDate)
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

    var preparedFoodMatchKey: PreparedFoodMatchKey {
        if let recipeID {
            return .recipe(recipeID)
        }
        return .preparedFoodIdentity(foodIdentityID)
    }

    static let samples: [PreparedDish] = [
        PreparedDish(
            name: "Lentil Soup",
            mealTypes: [.lunch, .dinner],
            servingsRemaining: 2,
            storage: .refrigerated,
            useByDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
            notes: "Leftover from batch cook"
        ),
        PreparedDish(
            name: "Takeout Sushi",
            mealTypes: [.lunch, .dinner],
            servingsRemaining: 1,
            storage: .refrigerated,
            useByDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())
        ),
    ]

    fileprivate static func normalizedMealTypes(_ mealTypes: [MealType]) -> [MealType] {
        var seen = Set<MealType>()
        return mealTypes.filter { seen.insert($0).inserted }
    }
}

struct PreparedDishHistoryItem: Identifiable, Codable, Hashable {
    var id: UUID
    var foodIdentityID: UUID
    var name: String
    var mealTypes: [MealType]
    var defaultServings: Int
    var storage: PantryStorage
    var notes: String?
    var recipeID: UUID?
    var nutrition: NutritionInfo?
    var createdAt: Date
    var lastPreparedAt: Date
    var lastUsedAt: Date
    var timesPrepared: Int

    init(
        id: UUID = UUID(),
        foodIdentityID: UUID = UUID(),
        name: String,
        mealTypes: [MealType],
        defaultServings: Int,
        storage: PantryStorage,
        notes: String? = nil,
        recipeID: UUID? = nil,
        nutrition: NutritionInfo? = nil,
        createdAt: Date = Date(),
        lastPreparedAt: Date,
        lastUsedAt: Date,
        timesPrepared: Int = 1
    ) {
        self.id = id
        self.foodIdentityID = foodIdentityID
        self.name = name.trimmed
        self.mealTypes = PreparedDish.normalizedMealTypes(mealTypes)
        self.defaultServings = max(1, defaultServings)
        self.storage = storage
        self.notes = notes?.trimmed.nilIfEmpty
        self.recipeID = recipeID
        self.nutrition = nutrition
        self.createdAt = createdAt
        self.lastPreparedAt = lastPreparedAt
        self.lastUsedAt = lastUsedAt
        self.timesPrepared = max(1, timesPrepared)
    }

    init(dish: PreparedDish, previousItem: PreparedDishHistoryItem? = nil, referenceDate: Date = Date()) {
        self.init(
            id: previousItem?.id ?? UUID(),
            foodIdentityID: previousItem?.foodIdentityID ?? dish.foodIdentityID,
            name: dish.name,
            mealTypes: dish.mealTypes,
            defaultServings: dish.servingsRemaining,
            storage: dish.storage,
            notes: dish.notes,
            recipeID: dish.recipeID,
            nutrition: dish.nutrition,
            createdAt: previousItem?.createdAt ?? referenceDate,
            lastPreparedAt: dish.dateAdded,
            lastUsedAt: referenceDate,
            timesPrepared: (previousItem?.timesPrepared ?? 0) + 1
        )
    }

    var canonicalMatchKey: String {
        if let recipeID {
            return "recipe:\(recipeID.uuidString.lowercased())"
        }

        let normalizedMealTypes = mealTypes
            .map(\.rawValue)
            .sorted()
            .joined(separator: "|")
        return "name:\(name.trimmed.lowercased())|meals:\(normalizedMealTypes)"
    }

    var mealTypesSummary: String {
        mealTypes.map(\.rawValue).joined(separator: " • ")
    }

    var preparedFoodMatchKey: PreparedFoodMatchKey {
        if let recipeID {
            return .recipe(recipeID)
        }
        return .preparedFoodIdentity(foodIdentityID)
    }

    var servingsText: String {
        defaultServings == 1 ? "1 serving" : "\(defaultServings) servings"
    }

    func matches(_ dish: PreparedDish) -> Bool {
        preparedFoodMatchKey == dish.preparedFoodMatchKey
    }

    func makeDraft(referenceDate: Date = Date()) -> PreparedDishDraft {
        var draft = PreparedDishDraft(id: UUID())
        draft.foodIdentityID = foodIdentityID
        draft.name = name
        draft.mealTypes = Set(mealTypes)
        draft.servingsRemaining = defaultServings
        draft.storage = storage
        draft.dateAdded = referenceDate
        draft.manualUseByDate = PreparedDishFreshnessPolicy.estimatedUseByDate(for: storage, referenceDate: referenceDate)
        draft.useByDateWasEdited = false
        draft.notes = notes ?? ""
        draft.recipeID = recipeID

        if let nutrition {
            let nutritionStrings = PreparedDishDraft.nutritionStrings(from: nutrition)
            draft.caloriesText = String(nutrition.calories)
            draft.proteinText = nutritionStrings.protein
            draft.carbsText = nutritionStrings.carbs
            draft.fatText = nutritionStrings.fat
        } else {
            draft.caloriesText = ""
            draft.proteinText = ""
            draft.carbsText = ""
            draft.fatText = ""
        }

        return draft
    }
}

extension PreparedDish {
    var historyTemplateSignature: String {
        let normalizedMealTypes = mealTypes.map(\.rawValue).sorted().joined(separator: "|")
        let nutritionSignature: String
        if let nutrition {
            nutritionSignature = "\(nutrition.calories)|\(nutrition.protein)|\(nutrition.carbohydrates)|\(nutrition.fat)|\(nutrition.fiber ?? -1)|\(nutrition.sugar ?? -1)|\(nutrition.sodium ?? -1)"
        } else {
            nutritionSignature = "none"
        }

        return [
            name.trimmed.lowercased(),
            normalizedMealTypes,
            storage.rawValue,
            notes?.trimmed.lowercased() ?? "",
            recipeID?.uuidString.lowercased() ?? "",
            nutritionSignature,
        ].joined(separator: "||")
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
    var foodIdentityID: UUID
    var name: String
    var mealTypes: Set<MealType>
    var servingsRemaining: Int
    var storage: PantryStorage
    var manualUseByDate: Date
    var useByDateWasEdited: Bool
    var dateAdded: Date
    var notes: String
    var recipeID: UUID?
    var caloriesText: String
    var proteinText: String
    var carbsText: String
    var fatText: String

    init(id: UUID = UUID(), dish: PreparedDish? = nil) {
        self.id = dish?.id ?? id
        self.foodIdentityID = dish?.foodIdentityID ?? UUID()
        self.name = dish?.name ?? ""
        self.mealTypes = Set(dish?.mealTypes ?? [.lunch, .dinner])
        self.servingsRemaining = dish?.servingsRemaining ?? 1
        self.storage = dish?.storage ?? .refrigerated
        self.manualUseByDate = dish?.useByDate ?? PreparedDishFreshnessPolicy.estimatedUseByDate(for: dish?.storage ?? .refrigerated)
        self.useByDateWasEdited = dish?.useByDate != nil
        self.dateAdded = dish?.dateAdded ?? Date()
        self.notes = dish?.notes ?? ""
        self.recipeID = dish?.recipeID
        self.caloriesText = dish?.nutrition.map { String($0.calories) } ?? ""
        self.proteinText = dish?.nutrition.map { Self.decimalString($0.protein) } ?? ""
        self.carbsText = dish?.nutrition.map { Self.decimalString($0.carbohydrates) } ?? ""
        self.fatText = dish?.nutrition.map { Self.decimalString($0.fat) } ?? ""
    }

    var estimatedUseByDate: Date {
        PreparedDishFreshnessPolicy.estimatedUseByDate(for: storage, referenceDate: dateAdded)
    }

    var resolvedUseByDate: Date {
        useByDateWasEdited ? manualUseByDate : estimatedUseByDate
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

    func isValid(using recipe: Recipe?) -> Bool {
        !resolvedName(using: recipe).isEmpty
            && !resolvedMealTypes(using: recipe).isEmpty
            && servingsRemaining > 0
            && !nutritionIsInvalid
    }

    func buildDish() -> PreparedDish? {
        guard isValid else { return nil }

        return PreparedDish(
            id: id,
            foodIdentityID: foodIdentityID,
            name: name,
            mealTypes: mealTypes.sorted { $0.rawValue < $1.rawValue },
            servingsRemaining: servingsRemaining,
            storage: storage,
            useByDate: resolvedUseByDate,
            dateAdded: dateAdded,
            notes: notes,
            recipeID: recipeID,
            nutrition: nutrition
        )
    }

    func buildDish(using recipe: Recipe?) -> PreparedDish? {
        guard isValid(using: recipe) else { return nil }

        return PreparedDish(
            id: id,
            foodIdentityID: foodIdentityID,
            name: resolvedName(using: recipe),
            mealTypes: resolvedMealTypes(using: recipe),
            servingsRemaining: servingsRemaining,
            storage: storage,
            useByDate: resolvedUseByDate,
            dateAdded: dateAdded,
            notes: notes,
            recipeID: recipeID,
            nutrition: resolvedNutrition(using: recipe)
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

    func resolvedName(using recipe: Recipe?) -> String {
        name.trimmed.nilIfEmpty ?? recipe?.title.trimmed ?? ""
    }

    func resolvedMealTypes(using recipe: Recipe?) -> [MealType] {
        let selectedMealTypes = mealTypes.sorted { $0.rawValue < $1.rawValue }
        if !selectedMealTypes.isEmpty {
            return selectedMealTypes
        }
        if let mealType = recipe?.mealType {
            return [mealType]
        }
        return []
    }

    func resolvedNutrition(using recipe: Recipe?) -> NutritionInfo? {
        nutrition ?? recipe?.nutrition
    }

    mutating func updateUseByDate(_ date: Date) {
        manualUseByDate = date
        useByDateWasEdited = true
    }

    mutating func applyLinkedRecipeDefaults(_ recipe: Recipe) {
        if name.trimmed.isEmpty {
            name = recipe.title
        }

        if mealTypes.isEmpty, let mealType = recipe.mealType {
            mealTypes = [mealType]
        }

        if servingsRemaining == 1, recipe.servings > 1 {
            servingsRemaining = recipe.servings
        }

        if caloriesText.trimmed.isEmpty, let nutrition = recipe.nutrition {
            let nutritionStrings = Self.nutritionStrings(from: nutrition)
            caloriesText = String(nutrition.calories)
            proteinText = nutritionStrings.protein
            carbsText = nutritionStrings.carbs
            fatText = nutritionStrings.fat
        }
    }

    mutating func syncLinkedRecipe(_ recipe: Recipe) {
        name = recipe.title
        mealTypes = recipe.mealType.map { [$0] } ?? []
        servingsRemaining = max(1, recipe.servings)

        if let nutrition = recipe.nutrition {
            let nutritionStrings = Self.nutritionStrings(from: nutrition)
            caloriesText = String(nutrition.calories)
            proteinText = nutritionStrings.protein
            carbsText = nutritionStrings.carbs
            fatText = nutritionStrings.fat
        } else {
            caloriesText = ""
            proteinText = ""
            carbsText = ""
            fatText = ""
        }
    }
}

// MARK: - Prepared Dish Batch

/// A group of prepared dishes with the same identity (same name) but potentially different expiry dates.
/// Used for UI grouping with accordion display when multiple batches exist.
struct PreparedDishBatch: Identifiable {
    let dishes: [PreparedDish]

    var id: UUID { dishes.first?.id ?? UUID() }

    /// The first dish serves as the representative for displaying name, meal types, etc.
    var representativeDish: PreparedDish { dishes[0] }

    /// Whether this batch contains multiple dishes with different expiry dates.
    var hasMultipleBatches: Bool { dishes.count > 1 }

    /// The earliest use-by date among all dishes in this batch.
    var earliestUseBy: Date? {
        dishes.compactMap(\.useByDate).min()
    }

    /// The expiry status based on the earliest use-by date.
    var expiryStatus: ExpiryStatus {
        .from(date: earliestUseBy)
    }

    /// Days until the earliest use-by, used for display.
    var daysUntilUseBy: Int? {
        ExpiryStatus.daysRemaining(until: earliestUseBy)
    }

    /// Total servings across all dishes in this batch.
    var totalServings: Int {
        dishes.reduce(0) { $0 + $1.servingsRemaining }
    }

    /// Display string for total servings.
    var servingsDisplay: String {
        totalServings == 1 ? "1 serving" : "\(totalServings) servings"
    }

    /// The normalized identity key for grouping (lowercased, trimmed name).
    static func identityKey(for dish: PreparedDish) -> String {
        dish.name.trimmed.lowercased()
    }
}