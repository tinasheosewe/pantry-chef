"""LLM-based recipe quality reviewer with retry support."""

from __future__ import annotations

import logging

from .client import LLMClient
from .config import Settings
from .models import Recipe, ReviewResult
from .prompts import recipe_review_messages
from .schemas import ReviewStatus

logger = logging.getLogger(__name__)


class RecipeReviewer:
    """Reviews generated recipes via LLM and supports revision retries."""

    def __init__(self, client: LLMClient, settings: Settings) -> None:
        self._client = client
        self._settings = settings

    async def review(self, recipe: Recipe) -> ReviewResult:
        """Submit a recipe for quality review."""
        recipe_dict = recipe.model_dump(mode="json", exclude_none=True)
        messages = recipe_review_messages(recipe_dict)
        result = await self._client.generate(
            messages=messages,
            response_model=ReviewResult,
            model=self._settings.review_model,
            temperature=0.2,
        )
        logger.info(
            "Review '%s': %s (%d issues)",
            recipe.title,
            result.status.value,
            len(result.issues),
        )
        return result
