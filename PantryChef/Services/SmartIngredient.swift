import Foundation

/// Promotes an AI recipe's catalog-misses to first-class *smart items* — so a novel
/// ingredient ("gochujang", "nduja") gets the same expiry clock, aisle, and readiness
/// matching as any catalog ingredient, and the catalog self-extends per user. The
/// category comes from the AI (FoodCategory's rawValue *is* the AI category string);
/// storage and shelf life fall to sensible per-category defaults the user can correct
/// in the review editor. Reuses the same `registerUserItem` path the manual
/// custom-ingredient form uses, so there's one definition of "first-class ingredient".
enum SmartIngredient {

    /// Re-point every freeform line (no catalog id) at a newly-registered — or already
    /// existing — catalog item, using the AI's per-ingredient category as the hint.
    static func promote(dish: Dish, rawIngredients: [RawIngredient]) -> Dish {
        var dish = dish
        for i in dish.ingredients.indices where dish.ingredients[i].catalogItemID == nil {
            let line = dish.ingredients[i]
            guard !line.name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let aiCategory = rawIngredients
                .first { $0.name.caseInsensitiveCompare(line.name) == .orderedSame }?.category
            let category = aiCategory.flatMap { FoodCategory(rawValue: $0) } ?? .other
            guard let id = registerSmartItem(name: line.name, category: category) else { continue }
            dish.ingredients[i] = RecipeLine(id: line.id, key: line.key, amount: line.amount,
                                             name: line.name, isStaple: line.isStaple,
                                             essential: line.essential, catalogItemID: id)
        }
        return dish
    }

    /// Register a user catalog item from a full AI ingredient definition (the manual
    /// "Smart-fill" path, where the AI proposes category + storage + shelf life).
    /// Returns the new — or existing — catalog id.
    static func register(name: String, definition: AIIngredientDefinition) -> String? {
        var draft = CustomIngredientDraft(name: name)
        draft.applyAIDefinition(definition)
        return register(draft.buildDefinition())
    }

    /// Build + register a user catalog item for a novel ingredient; returns its id, the
    /// id of an existing match (dedup / name collision), or nil if it couldn't register.
    private static func registerSmartItem(name: String, category: FoodCategory) -> String? {
        var draft = CustomIngredientDraft(name: name)
        draft.category = category
        draft.defaultStorage = defaultStorage(for: category)   // shelf life defaults off storage
        return register(draft.buildDefinition())
    }

    private static func register(_ def: PantryCatalogItemDefinition) -> String? {
        switch PantryCatalog.registerUserItem(def) {
        case .success: return def.id
        case .failure(.duplicateUserItem(let existing)): return existing
        case .failure(.nameCollision(let existing, _)): return existing  // exists under another name
        case .failure: return nil
        }
    }

    private static func defaultStorage(for category: FoodCategory) -> PantryStorage {
        switch category {
        case .produce, .protein, .dairy: return .refrigerated
        case .frozenFoods: return .frozen
        default: return .pantry
        }
    }
}
