"""Tests for RecipeReviewer — accept, revise, reject flows."""

import pytest

from recipe_ingredient_orchestrator.models import (
    Recipe,
    RecipeIngredient,
    RecipeStep,
    ReviewIssue,
    ReviewResult,
)
from recipe_ingredient_orchestrator.schemas import (
    MeasurementUnit,
    ReviewStatus,
)

from tests.factories import make_mock_client


def _make_recipe(**overrides) -> Recipe:
    defaults = dict(
        title="Test Recipe",
        ingredients=[RecipeIngredient(name="Salt", quantity=1, unit=MeasurementUnit.TSP)],
        steps=[RecipeStep(step_number=1, instruction="Add salt")],
    )
    defaults.update(overrides)
    return Recipe(**defaults)


class TestRecipeReviewer:
    @pytest.mark.asyncio
    async def test_accepted(self, settings):
        result = ReviewResult(status=ReviewStatus.ACCEPTED)
        client = make_mock_client({ReviewResult: result})

        from recipe_ingredient_orchestrator.reviewer import RecipeReviewer
        reviewer = RecipeReviewer(client, settings)
        outcome = await reviewer.review(_make_recipe())

        assert outcome.status == ReviewStatus.ACCEPTED

    @pytest.mark.asyncio
    async def test_rejected_with_issues(self, settings):
        result = ReviewResult(
            status=ReviewStatus.REJECTED,
            feedback="Recipe is incoherent",
            issues=[
                ReviewIssue(code="BAD_STEPS", severity="critical", message="Steps don't make sense"),
            ],
        )
        client = make_mock_client({ReviewResult: result})

        from recipe_ingredient_orchestrator.reviewer import RecipeReviewer
        reviewer = RecipeReviewer(client, settings)
        outcome = await reviewer.review(_make_recipe())

        assert outcome.status == ReviewStatus.REJECTED
        assert len(outcome.issues) == 1
        assert outcome.feedback is not None

    @pytest.mark.asyncio
    async def test_revise(self, settings):
        result = ReviewResult(
            status=ReviewStatus.REVISE,
            feedback="Step 3 timer is too short for braising",
        )
        client = make_mock_client({ReviewResult: result})

        from recipe_ingredient_orchestrator.reviewer import RecipeReviewer
        reviewer = RecipeReviewer(client, settings)
        outcome = await reviewer.review(_make_recipe())

        assert outcome.status == ReviewStatus.REVISE
        assert "braising" in outcome.feedback
