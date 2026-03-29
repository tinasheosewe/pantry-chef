"""Tests for IngredientGenerator and RecipeGenerator — mock LLM, verify flows."""

import asyncio
from unittest.mock import AsyncMock

import pytest

from recipe_ingredient_orchestrator.catalog import InMemoryCatalog
from recipe_ingredient_orchestrator.config import Settings
from recipe_ingredient_orchestrator.generators.ingredients import (
    IngredientBatchResponse,
    IngredientGenerator,
)
from recipe_ingredient_orchestrator.generators.recipes import (
    DishBriefBatchResponse,
    RawIngredient,
    RawNutrition,
    RawRecipeResponse,
    RawStep,
    RecipeGenerator,
)
from recipe_ingredient_orchestrator.models import (
    CatalogEntry,
    DishBrief,
    FacetSelection,
    ResolvedIngredient,
    ResolutionResult,
)
from recipe_ingredient_orchestrator.schemas import (
    CuisineType,
    FacetKey,
    FoodCategory,
    MealType,
    MeasurementUnit,
    PantryStorage,
)

from tests.factories import make_catalog_entry, make_mock_client


# ---------------------------------------------------------------------------
# IngredientGenerator
# ---------------------------------------------------------------------------


class TestIngredientGenerator:
    @pytest.mark.asyncio
    async def test_single_batch(self, settings, catalog):
        entries = [
            make_catalog_entry(id="flour", name="Flour", category=FoodCategory.BAKING_SUPPLIES),
            make_catalog_entry(id="sugar", name="Sugar", category=FoodCategory.BAKING_SUPPLIES),
        ]
        client = make_mock_client({
            IngredientBatchResponse: IngredientBatchResponse(entries=entries),
        })
        gen = IngredientGenerator(client, settings)
        result = await gen.generate(count=2, catalog=catalog)

        assert len(result) == 2
        assert catalog.size == 2

    @pytest.mark.asyncio
    async def test_multiple_batches(self, settings, catalog):
        """When count > batch_size, should issue multiple batches."""
        # Set batch_size to 1 so two items need two batches
        settings = Settings(openai_api_key="test-key", ingredient_batch_size=1)

        call_count = 0

        async def fake_generate(*, messages, response_model, model, temperature=0.7):
            nonlocal call_count
            call_count += 1
            entry_id = f"item-{call_count}"
            entry = make_catalog_entry(id=entry_id, name=f"Item {call_count}")
            return IngredientBatchResponse(entries=[entry])

        client = make_mock_client()
        client.generate = fake_generate
        gen = IngredientGenerator(client, settings)
        result = await gen.generate(count=2, catalog=catalog)

        assert call_count == 2
        assert catalog.size == 2

    @pytest.mark.asyncio
    async def test_dedup_in_catalog(self, settings, catalog):
        """If the batch returns an entry already in catalog, it's skipped."""
        existing = make_catalog_entry(id="flour", name="Flour", category=FoodCategory.BAKING_SUPPLIES)
        await catalog.add(existing)

        entries = [
            make_catalog_entry(id="flour", name="Flour", category=FoodCategory.BAKING_SUPPLIES),
            make_catalog_entry(id="sugar", name="Sugar", category=FoodCategory.BAKING_SUPPLIES),
        ]
        client = make_mock_client({
            IngredientBatchResponse: IngredientBatchResponse(entries=entries),
        })
        gen = IngredientGenerator(client, settings)
        result = await gen.generate(count=1, catalog=catalog)

        assert catalog.size == 2  # flour + sugar


# ---------------------------------------------------------------------------
# RecipeGenerator
# ---------------------------------------------------------------------------


class TestRecipeGeneratorPlanDishes:
    @pytest.mark.asyncio
    async def test_plan_returns_briefs(self, settings):
        briefs = [
            DishBrief(title="Spaghetti Carbonara", cuisine=CuisineType.ITALIAN, meal_type=MealType.DINNER),
            DishBrief(title="Miso Soup", cuisine=CuisineType.JAPANESE, meal_type=MealType.LUNCH),
        ]
        client = make_mock_client({
            DishBriefBatchResponse: DishBriefBatchResponse(dishes=briefs),
        })
        gen = RecipeGenerator(client, settings)
        result = await gen.plan_dishes(count=2, existing_titles=[])

        assert len(result) == 2
        assert result[0].title == "Spaghetti Carbonara"


class TestRecipeGeneratorGenerateOne:
    @pytest.mark.asyncio
    async def test_generates_resolved_recipe(self, settings, catalog):
        """Full flow: raw recipe → resolution → add catalog entries → recipe."""
        # Seed the catalog with something
        await catalog.add(make_catalog_entry(id="pasta", name="Pasta", category=FoodCategory.PASTA_NOODLES))

        raw = RawRecipeResponse(
            title="Pasta Aglio e Olio",
            description="Simple garlic pasta",
            cuisine="Italian",
            meal_type="Dinner",
            difficulty=2,
            servings=2,
            prep_time_minutes=5,
            cook_time_minutes=15,
            dietary_tags=["Vegetarian"],
            ingredients=[
                RawIngredient(name="Spaghetti", quantity=200, unit="g", category="Pasta & Noodles"),
                RawIngredient(name="Garlic", quantity=4, unit="Cloves", category="Produce"),
            ],
            steps=[
                RawStep(step_number=1, instruction="Boil spaghetti", timer_minutes=10, estimated_duration_seconds=600),
                RawStep(step_number=2, instruction="Sauté garlic"),
            ],
            nutrition=RawNutrition(calories=400, protein=12, carbohydrates=60, fat=10),
        )

        garlic_entry = make_catalog_entry(id="garlic", name="Garlic", category=FoodCategory.PRODUCE)
        resolution = ResolutionResult(
            resolved=[
                ResolvedIngredient(
                    original_name="Spaghetti",
                    catalog_entry_id="pasta",
                    facet_selections=[FacetSelection(key=FacetKey.VARIANT, value="spaghetti")],
                    quantity=200,
                    unit=MeasurementUnit.G,
                    category=FoodCategory.PASTA_NOODLES,
                ),
                ResolvedIngredient(
                    original_name="Garlic",
                    catalog_entry_id="garlic",
                    quantity=4,
                    category=FoodCategory.PRODUCE,
                ),
            ],
            new_entries=[garlic_entry],
        )

        # Mock: first call → raw recipe, second → resolution
        responses = [raw, resolution]
        call_idx = 0

        async def sequence_generate(*, messages, response_model, model, temperature=0.7):
            nonlocal call_idx
            result = responses[call_idx]
            call_idx += 1
            return result

        client = make_mock_client()
        client.generate = sequence_generate

        gen = RecipeGenerator(client, settings)
        brief = DishBrief(title="Pasta Aglio e Olio", cuisine=CuisineType.ITALIAN, meal_type=MealType.DINNER)
        recipe = await gen.generate_one(brief, catalog)

        assert recipe.title == "Pasta Aglio e Olio"
        assert len(recipe.ingredients) == 2
        assert recipe.ingredients[0].catalog_entry_id == "pasta"
        assert recipe.ingredients[1].catalog_entry_id == "garlic"
        # Garlic should have been added to catalog
        assert catalog.has("garlic")


class TestRecipeGeneratorBatch:
    @pytest.mark.asyncio
    async def test_batch_handles_failures_gracefully(self, settings, catalog):
        """If one recipe in a batch fails, others should still succeed."""
        call_count = 0

        async def failing_generate(*, messages, response_model, model, temperature=0.7):
            nonlocal call_count
            call_count += 1
            if call_count in (1, 2):
                # First recipe: raw + resolution
                if call_count == 1:
                    return RawRecipeResponse(
                        title="Good Recipe",
                        cuisine="Italian",
                        difficulty=3,
                        ingredients=[RawIngredient(name="Salt", quantity=1, unit="tsp")],
                        steps=[RawStep(step_number=1, instruction="Salt it")],
                    )
                else:
                    return ResolutionResult(
                        resolved=[
                            ResolvedIngredient(
                                original_name="Salt",
                                catalog_entry_id="salt",
                                quantity=1,
                                unit=MeasurementUnit.TSP,
                            )
                        ]
                    )
            # Second recipe: raise error
            raise RuntimeError("LLM failed")

        await catalog.add(make_catalog_entry())
        client = make_mock_client()
        client.generate = failing_generate

        gen = RecipeGenerator(client, settings)
        briefs = [
            DishBrief(title="Good Recipe", cuisine=CuisineType.ITALIAN),
            DishBrief(title="Bad Recipe", cuisine=CuisineType.JAPANESE),
        ]
        recipes = await gen.generate_batch(briefs, catalog)

        # At least one should succeed
        assert len(recipes) >= 1
        assert recipes[0].title == "Good Recipe"
