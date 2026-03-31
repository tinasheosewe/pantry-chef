"""Reusable test factories for mock objects and model instances."""

from __future__ import annotations

import asyncio
from typing import Any, Dict, Optional, TypeVar
from unittest.mock import AsyncMock

from pydantic import BaseModel

from recipe_ingredient_orchestrator.catalog import InMemoryCatalog
from recipe_ingredient_orchestrator.client import LLMClient
from recipe_ingredient_orchestrator.config import Settings
from recipe_ingredient_orchestrator.models import (
    CatalogEntry,
    FacetDefinition,
    FacetSelection,
    FreshnessRange,
    StorageFreshness,
    SubstitutionSuggestion,
)
from recipe_ingredient_orchestrator.schemas import (
    CookingImpact,
    FoodCategory,
    MeasurementUnit,
    PantryStorage,
    SubstitutionImpact,
)

T = TypeVar("T", bound=BaseModel)


def make_mock_client(responses: Optional[Dict[type, Any]] = None) -> LLMClient:
    """Create an LLMClient whose generate() returns canned responses by schema type."""
    client = LLMClient.__new__(LLMClient)
    client._semaphore = asyncio.Semaphore(5)
    responses = responses or {}

    async def fake_generate(*, messages, response_model, model, temperature=0.7):
        if response_model in responses:
            val = responses[response_model]
            return val() if callable(val) else val
        raise ValueError(f"No mock response for {response_model.__name__}")

    client.generate = fake_generate  # type: ignore[assignment]
    client.close = AsyncMock()
    return client


def make_catalog_entry(
    id: str = "salt",
    name: str = "Salt",
    category: FoodCategory = FoodCategory.SPICES_HERBS,
    **overrides: Any,
) -> CatalogEntry:
    """Factory for test catalog entries.

    Generates unique aliases and facets based on the entry name so that
    overlap detection doesn't reject unrelated test entries.
    """
    # Build name-derived defaults so entries don't collide via shared aliases
    lower = name.lower()
    defaults = dict(
        id=id,
        name=name,
        category=category,
        default_unit=MeasurementUnit.TSP,
        default_quantity=1.0,
        default_storage=PantryStorage.PANTRY,
        aliases=[f"{lower} alias-a", f"{lower} alias-b"],
        facets=[FacetDefinition(key="variant", options=[f"{lower}-v1", f"{lower}-v2"])],
        default_selections=[FacetSelection(key="variant", value=f"{lower}-v1")],
        substitution_suggestions=[
            SubstitutionSuggestion(
                substitute_name="Soy Sauce",
                ratio="1/4 tsp salt : 1 tsp soy sauce",
                taste_impact=SubstitutionImpact.MODERATE,
                texture_impact=SubstitutionImpact.SLIGHT,
                cooking_impact=CookingImpact.SLIGHT,
                notes="Adds umami and liquid",
            )
        ],
        freshness_by_storage=[StorageFreshness(storage=PantryStorage.PANTRY, min_days=730, max_days=1825)],
    )
    defaults.update(overrides)
    return CatalogEntry(**defaults)
