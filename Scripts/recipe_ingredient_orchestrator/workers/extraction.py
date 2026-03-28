from __future__ import annotations

from ..models import IngredientMention, RecipeCandidate, make_identifier


class IngredientExtractionWorker:
    def extract(self, recipe: RecipeCandidate) -> list[IngredientMention]:
        return [
            IngredientMention(
                mention_id=make_identifier("mention"),
                raw_name=ingredient.name,
                quantity=ingredient.quantity,
                unit=ingredient.unit,
                category=ingredient.category,
                is_optional=ingredient.is_optional,
                notes=ingredient.notes,
            )
            for ingredient in recipe.ingredients
        ]