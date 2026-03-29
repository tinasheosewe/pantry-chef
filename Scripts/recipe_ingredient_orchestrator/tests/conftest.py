"""Shared fixtures for orchestrator tests."""

from __future__ import annotations

import pytest

from recipe_ingredient_orchestrator.catalog import InMemoryCatalog
from recipe_ingredient_orchestrator.config import Settings


@pytest.fixture
def settings() -> Settings:
    return Settings(openai_api_key="test-key")


@pytest.fixture
def catalog() -> InMemoryCatalog:
    return InMemoryCatalog()
