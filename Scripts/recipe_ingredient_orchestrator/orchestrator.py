"""Main orchestrator — coordinates ingredient and recipe pipelines."""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path

from .catalog import InMemoryCatalog
from .client import LLMClient
from .config import Settings
from .ingredient_generator import IngredientGenerator
from .recipe_generator import RecipeGenerator
from .models import GenerationRequest, Recipe
from .reviewer import RecipeReviewer
from .schemas import GenerationMode, ReviewStatus
from .writer import OutputWriter

logger = logging.getLogger(__name__)


class GenerationOrchestrator:
    """Coordinates ingredient generation, recipe generation, review, and output."""

    def __init__(
        self,
        client: LLMClient,
        catalog: InMemoryCatalog,
        ingredient_gen: IngredientGenerator,
        recipe_gen: RecipeGenerator,
        reviewer: RecipeReviewer,
        writer: OutputWriter,
        settings: Settings,
    ) -> None:
        self._client = client
        self._catalog = catalog
        self._ingredient_gen = ingredient_gen
        self._recipe_gen = recipe_gen
        self._reviewer = reviewer
        self._writer = writer
        self._settings = settings

    async def run(
        self,
        request: GenerationRequest,
        existing_titles: list[str] | None = None,
        existing_recipes: list[Recipe] | None = None,
    ) -> None:
        """Execute the generation pipeline based on request mode."""
        existing_titles = existing_titles or []
        existing_recipes = existing_recipes or []
        recipes: list[Recipe] = []

        logger.info(
            "Starting generation: mode=%s count=%d",
            request.mode.value,
            request.count,
        )

        # -- Ingredient pipeline -------------------------------------------
        if request.mode in (GenerationMode.INGREDIENTS, GenerationMode.BOTH):
            count = request.count
            logger.info("Running ingredient pipeline: %d entries", count)
            await self._ingredient_gen.generate(
                count=count,
                catalog=self._catalog,
                category_filter=request.category.value if request.category else None,
                prompt_context=request.prompt,
            )
            logger.info("Ingredient pipeline complete. Catalog size: %d", self._catalog.size)

        # -- Recipe pipeline -----------------------------------------------
        if request.mode in (GenerationMode.RECIPES, GenerationMode.BOTH):
            count = request.count
            logger.info("Running recipe pipeline: %d recipes", count)

            # Plan dishes in batches
            all_briefs = []
            remaining = count
            while remaining > 0:
                batch_count = min(remaining, self._settings.recipe_batch_size)
                briefs = await self._recipe_gen.plan_dishes(
                    count=batch_count,
                    existing_titles=existing_titles + [r.title for r in recipes] + [b.title for b in all_briefs],
                    cuisine_filter=request.cuisine.value if request.cuisine else None,
                    meal_type_filter=request.meal_type.value if request.meal_type else None,
                    prompt_context=request.prompt,
                )
                all_briefs.extend(briefs)
                remaining -= len(briefs)

            # Generate and review in batches
            for batch_start in range(0, len(all_briefs), self._settings.recipe_batch_size):
                batch = all_briefs[batch_start:batch_start + self._settings.recipe_batch_size]
                batch_recipes = await self._recipe_gen.generate_batch(batch, self._catalog)

                # Review each recipe with retry
                for recipe in batch_recipes:
                    accepted = await self._review_with_retry(recipe, self._catalog)
                    if accepted:
                        recipes.append(accepted)

                logger.info(
                    "Batch %d-%d: %d/%d accepted (total: %d)",
                    batch_start + 1,
                    batch_start + len(batch),
                    len([r for r in batch_recipes]),
                    len(batch),
                    len(recipes),
                )

                # Checkpoint after each batch so progress survives crashes
                self._save_checkpoint(existing_recipes + recipes)

        # -- Substitution linking ------------------------------------------
        if self._catalog.size > 0:
            logger.info("Running substitution linking pass...")
            stats = await self._catalog.link_substitutions()
            logger.info("Substitution linking: %s", stats)

        # -- Write output --------------------------------------------------
        all_recipes = existing_recipes + recipes
        self._writer.write(
            catalog=self._catalog.all_entries(),
            recipes=all_recipes,
        )
        logger.info(
            "Generation complete: %d catalog entries, %d recipes (%d new)",
            self._catalog.size,
            len(all_recipes),
            len(recipes),
        )

    def _save_checkpoint(self, recipes: list[Recipe]) -> None:
        """Persist current recipe progress so it survives crashes."""
        try:
            cp_path = self._writer._output_dir / "recipes_checkpoint.json"
            self._writer._output_dir.mkdir(parents=True, exist_ok=True)
            data = [r.model_dump(mode="json", exclude_none=True) for r in recipes]
            cp_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
            logger.info("Checkpoint saved: %d recipes → %s", len(recipes), cp_path)
        except Exception:
            logger.exception("Failed to write checkpoint")

    async def _review_with_retry(
        self,
        recipe: Recipe,
        catalog: InMemoryCatalog,
    ) -> Recipe | None:
        """Review a recipe. If revise, retry generation with feedback. If reject, drop."""
        current = recipe
        for attempt in range(1, self._settings.max_retries + 1):
            result = await self._reviewer.review(current)

            if result.status == ReviewStatus.ACCEPTED:
                return current

            if result.status == ReviewStatus.REJECTED:
                logger.warning("Recipe '%s' rejected: %s", current.title, result.feedback)
                return None

            # Revise: regenerate with feedback
            logger.info(
                "Recipe '%s' needs revision (attempt %d/%d): %s",
                current.title,
                attempt,
                self._settings.max_retries,
                result.feedback,
            )
            from .models import DishBrief
            brief = DishBrief(
                title=current.title,
                cuisine=current.cuisine,
                meal_type=current.meal_type,
                servings=current.servings,
            )
            current = await self._recipe_gen.generate_one(
                brief=brief,
                catalog=catalog,
                revision_feedback=result.feedback,
            )

        # Exhausted retries — accept the last version
        logger.warning("Recipe '%s' exhausted retries, accepting last version", current.title)
        return current
