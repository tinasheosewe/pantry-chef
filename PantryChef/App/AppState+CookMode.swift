import Foundation

// MARK: - Cook Mode

extension AppState {
    func pantryCookReviewItems(for recipe: Recipe) -> [PantryCookReviewItem] {
        pantryDomainService.pantryCookReviewItems(for: recipe, state: self)
    }

    func applyPantryCookReview(_ items: [PantryCookReviewItem]) async {
        await pantryDomainService.applyPantryCookReview(items, state: self)
    }

    func subtractableRecipeAmount(for ingredient: Ingredient, pantryItem: PantryItem) -> Double? {
        pantryDomainService.subtractableRecipeAmount(for: ingredient, pantryItem: pantryItem, state: self)
    }
}
