"""Tests for GenerationOrchestrator — scenario tests for each mode."""

import pytest

from recipe_ingredient_orchestrator.catalog import InMemoryCatalog
from recipe_ingredient_orchestrator.config import Settings
from recipe_ingredient_orchestrator.ingredient_generator import (
    IngredientBatchResponse,
    IngredientGenerator,
)
from recipe_ingredient_orchestrator.recipe_generator import (
    DishBriefBatchResponse,
    RawIngredient,
    RawRecipeResponse,
    RawStep,
    RecipeGenerator,
)
from recipe_ingredient_orchestrator.models import (
    DishBrief,
    GenerationRequest,
    ResolvedIngredient,
    ResolutionResult,
    ReviewResult,
)
from recipe_ingredient_orchestrator.orchestrator import GenerationOrchestrator
from recipe_ingredient_orchestrator.reviewer import RecipeReviewer
from recipe_ingredient_orchestrator.schemas import (
    CuisineType,
    FoodCategory,
    GenerationMode,
    MealType,
    MeasurementUnit,
    ReviewStatus,
)
from recipe_ingredient_orchestrator.writer import OutputWriter

from recipe_ingredient_orchestrator.tests.factories import make_catalog_entry, make_mock_client


class _CallTracker:
    """Tracks which phase-specific responses are requested."""

    def __init__(self):
        self.phases: list[str] = []

    def make_generate(self, phase_responses: dict):
        """Create a generate function that tracks calls by response model.

        phase_responses maps response_model type → (phase_name, response).
        """
        async def generate(*, messages, response_model, model, temperature=0.7):
            if response_model in phase_responses:
                name, response = phase_responses[response_model]
                self.phases.append(name)
                return response() if callable(response) else response
            raise ValueError(f"Unexpected response_model: {response_model.__name__}")
        return generate


def _build_orchestrator(client, settings, catalog, output_dir):
    writer = OutputWriter(output_dir)
    return GenerationOrchestrator(
        client=client,
        catalog=catalog,
        ingredient_gen=IngredientGenerator(client, settings),
        recipe_gen=RecipeGenerator(client, settings),
        reviewer=RecipeReviewer(client, settings),
        writer=writer,
        settings=settings,
    )


class TestIngredientsOnlyMode:
    @pytest.mark.asyncio
    async def test_generates_ingredients_and_writes_output(self, settings, catalog, tmp_path):
        entries = [
            make_catalog_entry(id="flour", name="Flour", category=FoodCategory.BAKING_SUPPLIES),
            make_catalog_entry(id="sugar", name="Sugar", category=FoodCategory.BAKING_SUPPLIES),
        ]
        client = make_mock_client({
            IngredientBatchResponse: IngredientBatchResponse(entries=entries),
        })
        settings = Settings(openai_api_key="test-key", output_dir=str(tmp_path))
        orch = _build_orchestrator(client, settings, catalog, tmp_path)

        request = GenerationRequest(mode=GenerationMode.INGREDIENTS, count=2)
        await orch.run(request)

        assert catalog.size == 2
        assert (tmp_path / "ingredient_catalog.json").exists()
        assert (tmp_path / "summary.json").exists()


class TestRecipesOnlyMode:
    @pytest.mark.asyncio
    async def test_plans_generates_reviews_writes(self, settings, catalog, tmp_path):
        """Full recipe pipeline: plan → generate → resolve → review → write."""
        await catalog.add(make_catalog_entry(id="pasta", name="Pasta", category=FoodCategory.PASTA_NOODLES))

        briefs = [DishBrief(title="Pasta Dish", cuisine=CuisineType.ITALIAN, meal_type=MealType.DINNER)]
        raw = RawRecipeResponse(
            title="Pasta Dish",
            cuisine="Italian",
            meal_type="Dinner",
            difficulty=2,
            ingredients=[RawIngredient(name="Pasta", quantity=200, unit="g")],
            steps=[RawStep(step_number=1, instruction="Cook pasta")],
        )
        resolution = ResolutionResult(
            resolved=[
                ResolvedIngredient(
                    original_name="Pasta",
                    catalog_entry_id="pasta",
                    quantity=200,
                    unit=MeasurementUnit.G,
                    category=FoodCategory.PASTA_NOODLES,
                )
            ],
        )
        review = ReviewResult(status=ReviewStatus.ACCEPTED)

        # Build a sequenced mock that handles different response_model types
        response_queue = [
            DishBriefBatchResponse(dishes=briefs),  # planning
            raw,         # recipe generation
            resolution,  # ingredient resolution
            review,      # review
        ]
        idx = 0

        async def sequenced_generate(*, messages, response_model, model, temperature=0.7):
            nonlocal idx
            result = response_queue[idx]
            idx += 1
            return result

        client = make_mock_client()
        client.generate = sequenced_generate

        settings = Settings(openai_api_key="test-key", output_dir=str(tmp_path), recipe_batch_size=10)
        orch = _build_orchestrator(client, settings, catalog, tmp_path)

        request = GenerationRequest(mode=GenerationMode.RECIPES, count=1)
        await orch.run(request)

        assert (tmp_path / "recipes.json").exists()
        assert (tmp_path / "ingredient_catalog.json").exists()


class TestReviewRetry:
    @pytest.mark.asyncio
    async def test_revise_then_accept(self, settings, catalog, tmp_path):
        """If review says revise, regenerate then accept on second attempt."""
        await catalog.add(make_catalog_entry(id="salt", name="Salt"))

        briefs = [DishBrief(title="Salty Dish")]
        raw = RawRecipeResponse(
            title="Salty Dish",
            difficulty=1,
            ingredients=[RawIngredient(name="Salt", quantity=1, unit="tsp")],
            steps=[RawStep(step_number=1, instruction="Add salt")],
        )
        resolution = ResolutionResult(
            resolved=[
                ResolvedIngredient(original_name="Salt", catalog_entry_id="salt", quantity=1, unit=MeasurementUnit.TSP)
            ],
        )
        revise_review = ReviewResult(status=ReviewStatus.REVISE, feedback="Needs more steps")
        accept_review = ReviewResult(status=ReviewStatus.ACCEPTED)

        call_idx = 0
        responses = [
            DishBriefBatchResponse(dishes=briefs),  # plan
            raw, resolution, revise_review,          # first attempt: generate, resolve, review=revise
            raw, resolution, accept_review,          # retry: regenerate, resolve, review=accept
        ]

        async def sequenced(*, messages, response_model, model, temperature=0.7):
            nonlocal call_idx
            r = responses[call_idx]
            call_idx += 1
            return r

        client = make_mock_client()
        client.generate = sequenced

        settings = Settings(openai_api_key="test-key", output_dir=str(tmp_path), recipe_batch_size=10)
        orch = _build_orchestrator(client, settings, catalog, tmp_path)

        request = GenerationRequest(mode=GenerationMode.RECIPES, count=1)
        await orch.run(request)

        assert (tmp_path / "recipes.json").exists()

    @pytest.mark.asyncio
    async def test_rejected_recipe_dropped(self, settings, catalog, tmp_path):
        """A rejected recipe should not appear in output."""
        await catalog.add(make_catalog_entry(id="salt", name="Salt"))

        briefs = [DishBrief(title="Bad Dish")]
        raw = RawRecipeResponse(
            title="Bad Dish",
            difficulty=1,
            ingredients=[RawIngredient(name="Salt", quantity=1, unit="tsp")],
            steps=[RawStep(step_number=1, instruction="Bad")],
        )
        resolution = ResolutionResult(
            resolved=[
                ResolvedIngredient(original_name="Salt", catalog_entry_id="salt", quantity=1, unit=MeasurementUnit.TSP)
            ],
        )
        rejected = ReviewResult(status=ReviewStatus.REJECTED, feedback="Terrible recipe")

        responses = [
            DishBriefBatchResponse(dishes=briefs),
            raw, resolution, rejected,
        ]
        idx = 0

        async def sequenced(*, messages, response_model, model, temperature=0.7):
            nonlocal idx
            r = responses[idx]
            idx += 1
            return r

        client = make_mock_client()
        client.generate = sequenced

        settings = Settings(openai_api_key="test-key", output_dir=str(tmp_path), recipe_batch_size=10)
        orch = _build_orchestrator(client, settings, catalog, tmp_path)

        request = GenerationRequest(mode=GenerationMode.RECIPES, count=1)
        await orch.run(request)

        import json
        summary = json.loads((tmp_path / "summary.json").read_text())
        assert summary["recipes"] == 0
        assert not (tmp_path / "recipes.json").exists()


class TestBothMode:
    @pytest.mark.asyncio
    async def test_ingredients_then_recipes(self, settings, catalog, tmp_path):
        """Both mode should run ingredients first, then recipes."""
        ingredient_entries = [
            make_catalog_entry(id="salt", name="Salt"),
            make_catalog_entry(id="pasta", name="Pasta", category=FoodCategory.PASTA_NOODLES),
        ]

        briefs = [DishBrief(title="Salted Pasta")]
        raw = RawRecipeResponse(
            title="Salted Pasta",
            difficulty=1,
            ingredients=[RawIngredient(name="Pasta", quantity=200, unit="g")],
            steps=[RawStep(step_number=1, instruction="Cook")],
        )
        resolution = ResolutionResult(
            resolved=[
                ResolvedIngredient(original_name="Pasta", catalog_entry_id="pasta", quantity=200, unit=MeasurementUnit.G, category=FoodCategory.PASTA_NOODLES)
            ],
        )
        review = ReviewResult(status=ReviewStatus.ACCEPTED)

        responses = [
            IngredientBatchResponse(entries=ingredient_entries),  # ingredients
            DishBriefBatchResponse(dishes=briefs),               # plan
            raw, resolution, review,                              # recipe flow
        ]
        idx = 0

        async def sequenced(*, messages, response_model, model, temperature=0.7):
            nonlocal idx
            r = responses[idx]
            idx += 1
            return r

        client = make_mock_client()
        client.generate = sequenced

        settings = Settings(openai_api_key="test-key", output_dir=str(tmp_path), recipe_batch_size=10)
        orch = _build_orchestrator(client, settings, catalog, tmp_path)

        request = GenerationRequest(mode=GenerationMode.BOTH, count=1)
        await orch.run(request)

        # Ingredients should have been generated first
        assert catalog.size >= 1
        assert (tmp_path / "recipes.json").exists()
        assert (tmp_path / "ingredient_catalog.json").exists()
