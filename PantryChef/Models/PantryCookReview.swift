import Foundation

enum PantryCookReviewSelection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case keep
    case remove
    case subtractRecipeAmount

    var id: Self { self }

    var title: String {
        switch self {
        case .keep:
            return "Keep"
        case .remove:
            return "Used up"
        case .subtractRecipeAmount:
            return "Subtract"
        }
    }

    var systemImage: String {
        switch self {
        case .keep:
            return "checkmark.circle"
        case .remove:
            return "trash"
        case .subtractRecipeAmount:
            return "minus.circle"
        }
    }
}

struct PantryCookReviewItem: Identifiable, Hashable, Sendable {
    var id: UUID { pantryItem.id }

    let pantryItem: PantryItem
    let matchedIngredientNames: [String]
    let matchedIngredientTexts: [String]
    let subtractQuantity: Double?
    let subtractUnit: MeasurementUnit?
    var selection: PantryCookReviewSelection

    init(
        pantryItem: PantryItem,
        matchedIngredientNames: [String],
        matchedIngredientTexts: [String],
        subtractQuantity: Double?,
        subtractUnit: MeasurementUnit?,
        selection: PantryCookReviewSelection = .keep
    ) {
        self.pantryItem = pantryItem
        self.matchedIngredientNames = matchedIngredientNames
        self.matchedIngredientTexts = matchedIngredientTexts
        self.subtractQuantity = subtractQuantity
        self.subtractUnit = subtractUnit
        self.selection = selection
    }

    var quantityMode: PantryQuantityMode {
        pantryItem.quantityMode
    }

    var supportsSubtraction: Bool {
        pantryItem.isTrackingExactQuantity && subtractQuantity != nil && subtractUnit != nil
    }

    var availableSelections: [PantryCookReviewSelection] {
        supportsSubtraction ? [.keep, .subtractRecipeAmount, .remove] : [.keep, .remove]
    }

    var pantryDetailText: String {
        switch pantryItem.quantityMode {
        case .presenceOnly:
            return PantryQuantityMode.presenceOnly.title
        case .exact:
            guard let quantity = pantryItem.quantity,
                  let unit = pantryItem.unit else {
                return PantryQuantityMode.exact.title
            }
            return "Tracked: \(Self.formattedQuantity(quantity)) \(unit.rawValue)"
        }
    }

    var recipeUsageText: String {
        if let subtractQuantity,
           let subtractUnit {
            return "Recipe uses \(Self.formattedQuantity(subtractQuantity)) \(subtractUnit.rawValue)"
        }

        if matchedIngredientTexts.count == 1, let ingredientText = matchedIngredientTexts.first {
            return ingredientText
        }

        return matchedIngredientTexts.joined(separator: " • ")
    }

    private static func formattedQuantity(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}