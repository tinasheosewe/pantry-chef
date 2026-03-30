"""Recipe generation and ingredient resolution via LLM."""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

from pydantic import BaseModel, Field

from .catalog import InMemoryCatalog
from .client import LLMClient
from .config import Settings
from .models import (
    CatalogEntry,
    DishBrief,
    Recipe,
    RecipeIngredient,
    ResolutionResult,
)
from .prompts import (
    ingredient_resolution_messages,
    recipe_generation_messages,
    recipe_planning_messages,
)

logger = logging.getLogger(__name__)


# -- LLM response models (not reused outside this module) ------------------

class DishBriefBatchResponse(BaseModel):
    dishes: list[DishBrief] = Field(min_length=1)


class RawRecipeResponse(BaseModel):
    """Direct LLM output for a generated recipe (before resolution)."""
    title: str
    description: Optional[str] = None
    cuisine: Optional[str] = None
    meal_type: Optional[str] = None
    difficulty: int = 3
    servings: int = 4
    prep_time_minutes: Optional[int] = None
    cook_time_minutes: Optional[int] = None
    dietary_tags: list[str] = Field(default_factory=list)
    ingredients: list[RawIngredient] = Field(min_length=1)
    steps: list[RawStep] = Field(min_length=1)
    nutrition: Optional[RawNutrition] = None


class RawIngredient(BaseModel):
    name: str
    quantity: float
    unit: Optional[str] = None
    category: Optional[str] = None
    is_optional: bool = False


class RawStep(BaseModel):
    step_number: int
    instruction: str
    timer_minutes: Optional[int] = None
    estimated_duration_seconds: Optional[int] = None


class RawNutrition(BaseModel):
    calories: int
    protein: float
    carbohydrates: float
    fat: float
    fiber: Optional[float] = None
    sugar: Optional[float] = None
    sodium: Optional[float] = None


# Fix forward reference
RawRecipeResponse.model_rebuild()


class RecipeGenerator:
    """Plans dish briefs and generates fully-resolved recipes."""

    def __init__(self, client: LLMClient, settings: Settings) -> None:
        self._client = client
        self._settings = settings

    async def plan_dishes(
        self,
        count: int,
        existing_titles: list[str],
        *,
        cuisine_filter: str | None = None,
        meal_type_filter: str | None = None,
        prompt_context: str | None = None,
    ) -> list[DishBrief]:
        """Ask the LLM to plan diverse dish briefs."""
        messages = recipe_planning_messages(
            count=count,
            existing_titles=existing_titles,
            cuisine_filter=cuisine_filter,
            meal_type_filter=meal_type_filter,
            prompt_context=prompt_context,
        )
        response = await self._client.generate(
            messages=messages,
            response_model=DishBriefBatchResponse,
            model=self._settings.planner_model,
            temperature=0.7,
        )
        logger.info("Planned %d dish briefs", len(response.dishes))
        return response.dishes

    async def generate_one(
        self,
        brief: DishBrief,
        catalog: InMemoryCatalog,
        *,
        revision_feedback: str | None = None,
    ) -> Recipe:
        """Generate a single recipe and resolve its ingredients against the catalog.

        1. Generate a raw recipe from the brief
        2. Resolve all ingredients against the catalog (LLM-based)
        3. Add any new catalog entries created during resolution
        4. Return a fully-resolved Recipe
        """
        # Step 1: Generate raw recipe
        brief_dict = brief.model_dump(exclude_none=True)
        if revision_feedback:
            brief_dict["revision_feedback"] = revision_feedback

        messages = recipe_generation_messages(
            brief=brief_dict,
            catalog_summary=catalog.summary_for_prompt(),
        )
        raw = await self._client.generate(
            messages=messages,
            response_model=RawRecipeResponse,
            model=self._settings.model,
            temperature=0.7,
        )

        # Step 2: Resolve ingredients against catalog
        raw_ingredients = [
            {"name": ing.name, "quantity": ing.quantity, "unit": ing.unit,
             "category": ing.category, "is_optional": ing.is_optional}
            for ing in raw.ingredients
        ]
        resolution_messages = ingredient_resolution_messages(
            recipe_ingredients=raw_ingredients,
            catalog_entries=catalog.entries_for_resolution(),
        )
        resolution = await self._client.generate(
            messages=resolution_messages,
            response_model=ResolutionResult,
            model=self._settings.enrichment_model,
            temperature=0.2,
        )

        # Step 3: Add any new catalog entries
        if resolution.new_entries:
            added = await catalog.add_many(resolution.new_entries)
            logger.info(
                "Recipe '%s': resolution created %d new catalog entries",
                raw.title,
                added,
            )

        # Step 4: Build resolved Recipe
        resolved_ingredients = []
        for ri in resolution.resolved:
            resolved_ingredients.append(RecipeIngredient(
                name=ri.original_name,
                quantity=ri.quantity,
                unit=ri.unit,
                category=ri.category,
                catalog_entry_id=ri.catalog_entry_id,
                facet_selections=ri.facet_selections,
                is_optional=ri.is_optional,
            ))

        from .schemas import (
            CuisineType,
            DietaryTag,
            DifficultyLevel,
            MealType,
        )
        from .models import NutritionInfo, RecipeStep

        def _safe_enum(enum_cls, value, fallback=None):
            try:
                return enum_cls(value)
            except (ValueError, KeyError):
                logger.warning("Unknown %s value '%s', using %s", enum_cls.__name__, value, fallback)
                return fallback

        recipe = Recipe(
            title=raw.title,
            description=raw.description,
            cuisine=_safe_enum(CuisineType, raw.cuisine, CuisineType.OTHER) if raw.cuisine else None,
            meal_type=_safe_enum(MealType, raw.meal_type) if raw.meal_type else None,
            difficulty=_safe_enum(DifficultyLevel, raw.difficulty, DifficultyLevel.MEDIUM) or DifficultyLevel.MEDIUM,
            servings=raw.servings,
            prep_time_minutes=raw.prep_time_minutes,
            cook_time_minutes=raw.cook_time_minutes,
            dietary_tags=[t for t in (_safe_enum(DietaryTag, v) for v in raw.dietary_tags) if t is not None],
            ingredients=resolved_ingredients,
            steps=[
                RecipeStep(
                    step_number=s.step_number,
                    instruction=s.instruction,
                    timer_minutes=s.timer_minutes,
                    estimated_duration_seconds=s.estimated_duration_seconds,
                )
                for s in raw.steps
            ],
            nutrition=NutritionInfo(
                calories=raw.nutrition.calories,
                protein=raw.nutrition.protein,
                carbohydrates=raw.nutrition.carbohydrates,
                fat=raw.nutrition.fat,
                fiber=raw.nutrition.fiber,
                sugar=raw.nutrition.sugar,
                sodium=raw.nutrition.sodium,
            ) if raw.nutrition else None,
        )

        logger.info("Generated recipe: '%s' (%d ingredients)", recipe.title, len(recipe.ingredients))
        return recipe

    async def generate_batch(
        self,
        briefs: list[DishBrief],
        catalog: InMemoryCatalog,
    ) -> list[Recipe]:
        """Generate multiple recipes concurrently (bounded by client semaphore)."""
        tasks = [self.generate_one(brief, catalog) for brief in briefs]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        recipes: list[Recipe] = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                logger.error("Failed to generate '%s': %s", briefs[i].title, result)
            else:
                recipes.append(result)

        logger.info("Batch complete: %d/%d recipes generated", len(recipes), len(briefs))
        return recipes
