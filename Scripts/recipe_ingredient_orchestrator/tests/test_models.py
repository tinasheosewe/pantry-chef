"""Tests for Pydantic models — validation, constraints, serialization."""

import pytest
from pydantic import ValidationError

from recipe_ingredient_orchestrator.models import (
    CatalogEntry,
    FacetDefinition,
    FacetSelection,
    FreshnessRange,
    GenerationRequest,
    NutritionInfo,
    Recipe,
    RecipeIngredient,
    RecipeStep,
    ReviewResult,
    StorageFreshness,
    Substitution,
    SubstitutionSuggestion,
)
from recipe_ingredient_orchestrator.schemas import (
    DietaryTag,
    DifficultyLevel,
    FacetKey,
    FoodCategory,
    GenerationMode,
    MeasurementUnit,
    PantryStorage,
    ReviewStatus,
    SubstitutionImpact,
)


class TestCatalogEntry:
    def test_valid_entry(self):
        entry = CatalogEntry(
            id="olive-oil",
            name="Olive Oil",
            category=FoodCategory.OILS_FATS,
            default_unit=MeasurementUnit.TBSP,
            default_storage=PantryStorage.PANTRY,
            aliases=["EVOO"],
            facets=[FacetDefinition(key=FacetKey.VARIANT, options=["extra-virgin", "virgin", "light"])],
        )
        assert entry.id == "olive-oil"
        assert entry.category == FoodCategory.OILS_FATS

    def test_kebab_case_enforced(self):
        with pytest.raises(ValidationError, match="kebab-case"):
            CatalogEntry(id="Olive Oil", name="Olive Oil", category=FoodCategory.OILS_FATS)

    def test_roundtrip_serialization(self):
        entry = CatalogEntry(
            id="vinegar",
            name="Vinegar",
            category=FoodCategory.CONDIMENTS_SAUCES,
            facets=[FacetDefinition(key=FacetKey.VARIANT, options=["balsamic", "red wine", "rice"])],
            freshness_by_storage=[StorageFreshness(storage=PantryStorage.PANTRY, min_days=365, max_days=730)],
        )
        data = entry.model_dump(mode="json")
        restored = CatalogEntry.model_validate(data)
        assert restored == entry


class TestRecipe:
    def test_valid_recipe(self):
        recipe = Recipe(
            title="Test Recipe",
            ingredients=[RecipeIngredient(name="Salt", quantity=1, unit=MeasurementUnit.TSP)],
            steps=[RecipeStep(step_number=1, instruction="Add salt")],
        )
        assert recipe.servings == 4  # default

    def test_empty_ingredients_rejected(self):
        with pytest.raises(ValidationError):
            Recipe(
                title="Empty",
                ingredients=[],
                steps=[RecipeStep(step_number=1, instruction="Nothing")],
            )

    def test_empty_steps_rejected(self):
        with pytest.raises(ValidationError):
            Recipe(
                title="No Steps",
                ingredients=[RecipeIngredient(name="Salt", quantity=1)],
                steps=[],
            )

    def test_roundtrip_serialization(self):
        recipe = Recipe(
            title="Pasta",
            cuisine="Italian",
            meal_type="Dinner",
            difficulty=DifficultyLevel.EASY,
            dietary_tags=[DietaryTag.VEGETARIAN],
            ingredients=[
                RecipeIngredient(
                    name="Spaghetti",
                    quantity=500,
                    unit=MeasurementUnit.G,
                    category=FoodCategory.PASTA_NOODLES,
                    catalog_entry_id="pasta",
                    facet_selections=[FacetSelection(key=FacetKey.VARIANT, value="spaghetti")],
                )
            ],
            steps=[RecipeStep(step_number=1, instruction="Boil pasta", timer_minutes=10, estimated_duration_seconds=600)],
            nutrition=NutritionInfo(calories=400, protein=12, carbohydrates=70, fat=5),
        )
        data = recipe.model_dump(mode="json")
        restored = Recipe.model_validate(data)
        assert restored.title == "Pasta"
        assert restored.ingredients[0].catalog_entry_id == "pasta"


class TestGenerationRequest:
    def test_mode_required(self):
        req = GenerationRequest(mode=GenerationMode.RECIPES, count=5)
        assert req.count == 5

    def test_count_must_be_positive(self):
        with pytest.raises(ValidationError):
            GenerationRequest(mode=GenerationMode.RECIPES, count=0)


class TestReviewResult:
    def test_accepted(self):
        r = ReviewResult(status=ReviewStatus.ACCEPTED)
        assert r.status == ReviewStatus.ACCEPTED

    def test_revise_with_feedback(self):
        r = ReviewResult(status=ReviewStatus.REVISE, feedback="Needs more detail in steps")
        assert r.feedback is not None
