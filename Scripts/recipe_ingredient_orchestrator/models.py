"""Pydantic data models for the recipe/ingredient generation pipeline."""

from __future__ import annotations

import re
from typing import Optional

from pydantic import BaseModel, Field, field_validator

from .schemas import (
    CookingImpact,
    CuisineType,
    DietaryTag,
    DifficultyLevel,
    FacetKey,
    FoodCategory,
    GenerationMode,
    MealType,
    MeasurementUnit,
    PantryStorage,
    ReviewStatus,
    SubstitutionImpact,
)


# ---------------------------------------------------------------------------
# Ingredient catalog models
# ---------------------------------------------------------------------------

class FacetDefinition(BaseModel):
    """A refinement axis on a catalog entry (e.g. variant: [cheddar, mozzarella])."""
    key: FacetKey
    options: list[str] = Field(min_length=1)


class FacetSelection(BaseModel):
    """A specific facet choice (e.g. variant=balsamic)."""
    key: FacetKey
    value: str


class FreshnessRange(BaseModel):
    """Shelf-life range in days for a given storage type."""
    min_days: int = Field(ge=0)
    max_days: int = Field(ge=1)


class StorageFreshness(BaseModel):
    """Shelf-life for a specific storage type."""
    storage: PantryStorage
    min_days: int = Field(ge=0)
    max_days: int = Field(ge=1)


class SubstitutionSuggestion(BaseModel):
    """LLM-proposed substitute before catalog linking.

    substitute_name is free text; it becomes a validated substitute_id
    after the linking pass.
    """
    substitute_name: str
    substitute_facets: list[FacetSelection] = Field(default_factory=list)
    ratio: str = Field(description="e.g. '1:1', '2:1'")
    taste_impact: SubstitutionImpact = SubstitutionImpact.NONE
    texture_impact: SubstitutionImpact = SubstitutionImpact.NONE
    cooking_impact: CookingImpact = CookingImpact.NONE
    notes: Optional[str] = None


class Substitution(BaseModel):
    """A validated substitute linked to an existing catalog entry."""
    substitute_id: str
    substitute_facets: list[FacetSelection] = Field(default_factory=list)
    ratio: str
    taste_impact: SubstitutionImpact = SubstitutionImpact.NONE
    texture_impact: SubstitutionImpact = SubstitutionImpact.NONE
    cooking_impact: CookingImpact = CookingImpact.NONE
    notes: Optional[str] = None


class CatalogEntry(BaseModel):
    """A first-class ingredient in the pantry catalog.

    Follows the generic-base-with-facet-specificity pattern: one entry for
    'Vinegar' with variant facet [balsamic, red wine, rice, …], not separate
    entries for each type.
    """
    id: str = Field(description="kebab-case slug, e.g. 'olive-oil'")
    name: str = Field(description="Generic base display name, e.g. 'Olive Oil'")
    category: FoodCategory
    default_unit: Optional[MeasurementUnit] = None
    default_quantity: Optional[float] = None
    default_storage: PantryStorage = PantryStorage.PANTRY
    aliases: list[str] = Field(default_factory=list)
    facets: list[FacetDefinition] = Field(default_factory=list)
    default_selections: list[FacetSelection] = Field(default_factory=list)
    substitution_suggestions: list[SubstitutionSuggestion] = Field(default_factory=list)
    substitutions: list[Substitution] = Field(default_factory=list)
    freshness_by_storage: list[StorageFreshness] = Field(default_factory=list)

    @field_validator("id")
    @classmethod
    def id_must_be_kebab(cls, v: str) -> str:
        if not re.match(r"^[a-z0-9]+(?:-[a-z0-9]+)*$", v):
            raise ValueError(f"id must be kebab-case, got '{v}'")
        return v


# ---------------------------------------------------------------------------
# Recipe models
# ---------------------------------------------------------------------------

class RecipeIngredient(BaseModel):
    """An ingredient as used in a recipe, linked to a catalog entry."""
    name: str = Field(description="Display name as used in recipe text")
    quantity: float
    unit: Optional[MeasurementUnit] = None
    category: FoodCategory = FoodCategory.OTHER
    catalog_entry_id: Optional[str] = None
    facet_selections: list[FacetSelection] = Field(default_factory=list)
    is_optional: bool = False


class RecipeStep(BaseModel):
    step_number: int = Field(ge=1)
    instruction: str
    timer_minutes: Optional[int] = None
    estimated_duration_seconds: Optional[int] = None


class NutritionInfo(BaseModel):
    calories: int
    protein: float = Field(description="grams")
    carbohydrates: float = Field(description="grams")
    fat: float = Field(description="grams")
    fiber: Optional[float] = None
    sugar: Optional[float] = None
    sodium: Optional[float] = Field(default=None, description="mg")


class Recipe(BaseModel):
    title: str
    description: Optional[str] = None
    cuisine: Optional[CuisineType] = None
    meal_type: Optional[MealType] = None
    difficulty: DifficultyLevel = DifficultyLevel.MEDIUM
    servings: int = Field(default=4, ge=1)
    prep_time_minutes: Optional[int] = None
    cook_time_minutes: Optional[int] = None
    dietary_tags: list[DietaryTag] = Field(default_factory=list)
    ingredients: list[RecipeIngredient] = Field(min_length=1)
    steps: list[RecipeStep] = Field(min_length=1)
    nutrition: Optional[NutritionInfo] = None


# ---------------------------------------------------------------------------
# Generation pipeline models
# ---------------------------------------------------------------------------

class DishBrief(BaseModel):
    """A planned dish to generate."""
    title: str
    cuisine: Optional[CuisineType] = None
    meal_type: Optional[MealType] = None
    servings: int = 4
    pantry_focus: list[str] = Field(default_factory=list, description="Key ingredients")
    goals: list[str] = Field(default_factory=list, description="e.g. 'quick weeknight', 'impressive dinner party'")


class GenerationRequest(BaseModel):
    """What the user asked for — either parsed from flags or from NL prompt."""
    mode: GenerationMode
    count: int = Field(ge=1)
    cuisine: Optional[CuisineType] = None
    meal_type: Optional[MealType] = None
    category: Optional[FoodCategory] = None
    prompt: Optional[str] = None


class ResolvedIngredient(BaseModel):
    """Resolution result for a single recipe ingredient."""
    original_name: str
    catalog_entry_id: str
    facet_selections: list[FacetSelection] = Field(default_factory=list)
    quantity: float
    unit: Optional[MeasurementUnit] = None
    category: FoodCategory = FoodCategory.OTHER
    is_optional: bool = False


class ResolutionResult(BaseModel):
    """Output of ingredient resolution for one recipe."""
    resolved: list[ResolvedIngredient]
    new_entries: list[CatalogEntry] = Field(default_factory=list)


class ReviewIssue(BaseModel):
    code: str
    severity: str
    message: str


class ReviewResult(BaseModel):
    status: ReviewStatus
    issues: list[ReviewIssue] = Field(default_factory=list)
    feedback: Optional[str] = None
