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
    CookingImpact,
    DietaryTag,
    DifficultyLevel,
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
            facets=[FacetDefinition(key="variant", options=["extra-virgin", "virgin", "light"])],
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
            facets=[FacetDefinition(key="variant", options=["balsamic", "red wine", "rice"])],
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
                    facet_selections=[FacetSelection(key="variant", value="spaghetti")],
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


class TestFlexibleFacetKeys:
    """Tests that facet keys accept any string, not just predefined constants."""

    def test_arbitrary_facet_key_allowed(self):
        """Domain-specific facet keys like 'grade' should be valid."""
        entry = CatalogEntry(
            id="saffron",
            name="Saffron",
            category=FoodCategory.SPICES_HERBS,
            facets=[
                FacetDefinition(key="grade", options=["Spanish", "Iranian", "Kashmiri"]),
                FacetDefinition(key="variant", options=["threads", "powder"]),
            ],
        )
        # Both standard and custom keys should work
        assert len(entry.facets) == 2
        assert entry.facets[0].key == "grade"
        assert entry.facets[1].key == "variant"

    def test_age_facet_for_cheese(self):
        """Cheese can have 'age' as a custom facet key."""
        entry = CatalogEntry(
            id="parmesan",
            name="Parmesan",
            category=FoodCategory.DAIRY,
            facets=[
                FacetDefinition(key="age", options=["12 months", "24 months", "36 months"]),
            ],
        )
        assert entry.facets[0].key == "age"

    def test_region_facet_for_wine(self):
        """Wine can have 'region' as a custom facet key."""
        selection = FacetSelection(key="region", value="Bordeaux")
        assert selection.key == "region"
        assert selection.value == "Bordeaux"


class TestFlexibleCuisine:
    """Tests that cuisine accepts any string, not just enum values."""

    def test_peruvian_cuisine_allowed(self):
        """Peruvian and other cuisines not in the original enum should work."""
        recipe = Recipe(
            title="Ceviche",
            cuisine="Peruvian",
            ingredients=[RecipeIngredient(name="Fish", quantity=500, unit=MeasurementUnit.G)],
            steps=[RecipeStep(step_number=1, instruction="Marinate fish in lime juice")],
        )
        assert recipe.cuisine == "Peruvian"

    def test_turkish_cuisine_allowed(self):
        recipe = Recipe(
            title="Lahmacun",
            cuisine="Turkish",
            ingredients=[RecipeIngredient(name="Lamb", quantity=300, unit=MeasurementUnit.G)],
            steps=[RecipeStep(step_number=1, instruction="Prepare the dough")],
        )
        assert recipe.cuisine == "Turkish"

    def test_filipino_cuisine_allowed(self):
        recipe = Recipe(
            title="Adobo",
            cuisine="Filipino",
            ingredients=[RecipeIngredient(name="Chicken", quantity=1, unit=MeasurementUnit.LB)],
            steps=[RecipeStep(step_number=1, instruction="Marinate chicken")],
        )
        assert recipe.cuisine == "Filipino"


class TestRequiredImpactFields:
    """Tests that substitution impact fields are required, not optional."""

    def test_substitution_suggestion_requires_all_impacts(self):
        """SubstitutionSuggestion should fail validation without impact fields."""
        with pytest.raises(ValidationError) as exc_info:
            SubstitutionSuggestion(
                substitute_name="Butter",
                ratio="1:1",
                # Missing: taste_impact, texture_impact, cooking_impact
            )
        errors = exc_info.value.errors()
        missing_fields = {e["loc"][0] for e in errors}
        assert "taste_impact" in missing_fields
        assert "texture_impact" in missing_fields
        assert "cooking_impact" in missing_fields

    def test_substitution_suggestion_valid_with_all_impacts(self):
        """SubstitutionSuggestion should pass with all impact fields."""
        sub = SubstitutionSuggestion(
            substitute_name="Butter",
            ratio="1:1",
            taste_impact=SubstitutionImpact.SLIGHT,
            texture_impact=SubstitutionImpact.MODERATE,
            cooking_impact=CookingImpact.SLIGHT,
        )
        assert sub.taste_impact == SubstitutionImpact.SLIGHT
        assert sub.texture_impact == SubstitutionImpact.MODERATE
        assert sub.cooking_impact == CookingImpact.SLIGHT

    def test_substitution_requires_all_impacts(self):
        """Substitution (linked) should also fail without impact fields."""
        with pytest.raises(ValidationError) as exc_info:
            Substitution(
                substitute_id="butter",
                ratio="1:1",
                # Missing impacts
            )
        errors = exc_info.value.errors()
        missing_fields = {e["loc"][0] for e in errors}
        assert "taste_impact" in missing_fields
        assert "texture_impact" in missing_fields
        assert "cooking_impact" in missing_fields
