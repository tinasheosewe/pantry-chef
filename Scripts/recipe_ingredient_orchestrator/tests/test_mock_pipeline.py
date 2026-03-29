from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

PACKAGE_PARENT = Path(__file__).resolve().parents[2]
if str(PACKAGE_PARENT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_PARENT))

from recipe_ingredient_orchestrator.artifacts import ArtifactWriter
from recipe_ingredient_orchestrator.campaigns import CampaignStore, RecipeCampaignRunner
from recipe_ingredient_orchestrator.config import OrchestratorConfig
from recipe_ingredient_orchestrator.corpus_builder import _catalog_entry_from_payload, _catalog_entry_quality_issue, _ingredient_focus_plan, _plan_unique_recipe_batch
from recipe_ingredient_orchestrator.corpus import RecipeCorpusIndex
from recipe_ingredient_orchestrator.models import (
    AttemptTrace,
    CampaignSpec,
    CatalogEntry,
    DishSpec,
    FacetDefinition,
    FacetSelection,
    FreshnessRange,
    IngredientEnrichmentDecision,
    IngredientReference,
    IngredientStorage,
    RecipeCandidate,
    RecipeIngredientInput,
    RecipeReviewReport,
    RecipeStepInput,
    ReviewIssue,
)
from recipe_ingredient_orchestrator.pipeline import RecipeIngredientOrchestrator
from recipe_ingredient_orchestrator.promotion import IngredientPromotionStore
from recipe_ingredient_orchestrator.request_planning import RequestPlanningService
from recipe_ingredient_orchestrator.services import MutableIngredientCatalog, ScriptedAmbiguityResolver, ScriptedIngredientEnricher, StaticRecipeGenerator, build_default_catalog as build_empty_default_catalog
from recipe_ingredient_orchestrator.workers import (
    IngredientExtractionWorker,
    IngredientResolutionWorker,
    RecipeReconciliationWorker,
    RecipeValidationWorker,
)


def _test_entries() -> list[CatalogEntry]:
    """Minimal, self-contained catalog entries for test assertions."""
    return [
        CatalogEntry(item_id="chicken-breast", name="Chicken Breast", category="Protein", aliases={"chicken breast": [], "chicken": []}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="chicken-thigh", name="Chicken Thigh", category="Protein", aliases={"chicken thigh": []}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="salmon", name="Salmon", category="Protein", aliases={"salmon": [], "salmon fillet": [FacetSelection(key="cut", value="fillet")]}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="shrimp", name="Shrimp", category="Protein", aliases={"shrimp": [], "prawns": []}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="pork", name="Pork", category="Protein", aliases={"pork": [], "ground pork": [FacetSelection(key="form", value="ground")]}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="bacon", name="Bacon", category="Protein", aliases={"bacon": [], "lardons": [FacetSelection(key="cut", value="lardons")]}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="white-fish", name="White Fish", category="Protein", aliases={"white fish": [], "white fish fillets": [FacetSelection(key="cut", value="fillet")], "white fish fillet": [FacetSelection(key="cut", value="fillet")]}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="eggs", name="Eggs", category="Protein", aliases={"eggs": [], "egg": [], "large eggs": []}, default_unit="piece", quality_status="enriched"),
        CatalogEntry(item_id="pasta", name="Pasta", category="Pasta & Noodles", aliases={"pasta": [], "fettuccine": [FacetSelection(key="form", value="fettuccine")], "spaghetti": [FacetSelection(key="form", value="spaghetti")], "penne": [FacetSelection(key="form", value="penne")]}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="rice", name="Rice", category="Grains & Cereals", aliases={"rice": [], "jasmine rice": [FacetSelection(key="variety", value="jasmine")], "brown rice": [FacetSelection(key="variety", value="brown")], "basmati rice": [FacetSelection(key="variety", value="basmati")]}, default_unit="cup", quality_status="enriched"),
        CatalogEntry(item_id="heavy-cream", name="Heavy Cream", category="Dairy", aliases={"heavy cream": [], "cream": [], "double cream": []}, default_unit="cup", quality_status="enriched"),
        CatalogEntry(item_id="butter", name="Butter", category="Dairy", aliases={"butter": [], "unsalted butter": [FacetSelection(key="style", value="unsalted")]}, default_unit="tbsp", quality_status="enriched"),
        CatalogEntry(item_id="parmesan", name="Parmesan", category="Dairy", aliases={"parmesan": [], "parmesan cheese": []}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="mozzarella", name="Mozzarella", category="Dairy", aliases={"mozzarella": [], "fresh mozzarella": [FacetSelection(key="style", value="fresh")]}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="cheddar", name="Cheddar", category="Dairy", aliases={"cheddar": [], "cheddar cheese": []}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="garlic", name="Garlic", category="Produce", aliases={"garlic": [], "garlic cloves": [FacetSelection(key="form", value="clove")]}, default_unit="clove", quality_status="enriched"),
        CatalogEntry(item_id="onion", name="Onion", category="Produce", aliases={"onion": [], "yellow onion": [FacetSelection(key="variety", value="yellow")], "red onion": [FacetSelection(key="variety", value="red")]}, default_unit="piece", quality_status="enriched"),
        CatalogEntry(item_id="lemon", name="Lemon", category="Produce", aliases={"lemon": [], "lemon juice": [FacetSelection(key="form", value="juice")], "lemon zest": [FacetSelection(key="form", value="zest")]}, default_unit="piece", quality_status="enriched"),
        CatalogEntry(item_id="spinach", name="Spinach", category="Produce", aliases={"spinach": [], "baby spinach": [FacetSelection(key="variety", value="baby")]}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="mushroom", name="Mushroom", category="Produce", aliases={"mushroom": [], "mushrooms": [], "cremini mushrooms": [FacetSelection(key="variety", value="cremini")]}, default_unit="g", quality_status="enriched"),
        CatalogEntry(item_id="tomato", name="Tomato", category="Produce", aliases={"tomato": [], "tomatoes": []}, default_unit="piece", quality_status="enriched"),
        CatalogEntry(item_id="apple", name="Apple", category="Produce", aliases={"apple": [], "apples": [], "granny smith apple": [FacetSelection(key="variety", value="granny smith")], "granny smith apples": [FacetSelection(key="variety", value="granny smith")]}, default_unit="piece", quality_status="enriched"),
        CatalogEntry(item_id="eggplant", name="Eggplant", category="Produce", aliases={"eggplant": [], "aubergine": []}, default_unit="piece", quality_status="enriched"),
        CatalogEntry(item_id="zucchini", name="Zucchini", category="Produce", aliases={"zucchini": [], "courgette": []}, default_unit="piece", quality_status="enriched"),
        CatalogEntry(item_id="fennel", name="Fennel", category="Produce", aliases={"fennel": [], "fennel bulb": [FacetSelection(key="part", value="bulb")]}, default_unit="piece", quality_status="enriched"),
        CatalogEntry(item_id="olive-oil", name="Olive Oil", category="Oils & Fats", aliases={"olive oil": [], "extra virgin olive oil": [FacetSelection(key="style", value="extra virgin")]}, default_unit="tbsp", quality_status="enriched"),
        CatalogEntry(item_id="salt", name="Salt", category="Spices & Herbs", aliases={"salt": [], "kosher salt": [FacetSelection(key="grain", value="kosher")]}, default_unit="pinch", quality_status="enriched"),
        CatalogEntry(item_id="black-pepper", name="Black Pepper", category="Spices & Herbs", aliases={"black pepper": [], "pepper": []}, default_unit="tsp", quality_status="enriched"),
        CatalogEntry(item_id="bay-leaf", name="Bay Leaf", category="Spices & Herbs", aliases={"bay leaf": [], "bay leaves": []}, default_unit="piece", quality_status="enriched"),
        CatalogEntry(item_id="dill", name="Dill", category="Spices & Herbs", aliases={"dill": [], "fresh dill": [FacetSelection(key="form", value="fresh")]}, default_unit="bunch", quality_status="enriched"),
        CatalogEntry(item_id="nutmeg", name="Nutmeg", category="Spices & Herbs", aliases={"nutmeg": [], "ground nutmeg": [FacetSelection(key="form", value="ground")]}, default_unit="tsp", quality_status="enriched"),
        CatalogEntry(item_id="saffron", name="Saffron", category="Spices & Herbs", aliases={"saffron": [], "saffron threads": [FacetSelection(key="form", value="threads")]}, default_unit="pinch", quality_status="enriched"),
        CatalogEntry(item_id="vanilla-extract", name="Vanilla Extract", category="Baking Supplies", aliases={"vanilla extract": []}, default_unit="tsp", quality_status="enriched"),
        CatalogEntry(item_id="all-purpose-flour", name="All-Purpose Flour", category="Baking Supplies", aliases={"all purpose flour": [], "flour": [], "plain flour": []}, default_unit="cup", quality_status="enriched"),
        CatalogEntry(item_id="cornstarch", name="Cornstarch", category="Baking Supplies", aliases={"cornstarch": []}, default_unit="tbsp", quality_status="enriched"),
        CatalogEntry(item_id="sugar", name="Sugar", category="Baking Supplies", aliases={"sugar": [], "caster sugar": [FacetSelection(key="variety", value="caster")], "granulated sugar": [FacetSelection(key="variety", value="granulated")], "white sugar": [FacetSelection(key="variety", value="white")]}, default_unit="cup", quality_status="enriched"),
        CatalogEntry(item_id="brown-sugar", name="Brown Sugar", category="Baking Supplies", aliases={"brown sugar": []}, default_unit="cup", quality_status="enriched"),
        CatalogEntry(item_id="chicken-broth", name="Chicken Broth", category="Canned & Jarred", aliases={"chicken broth": [], "chicken stock": []}, default_unit="cup", quality_status="enriched"),
        CatalogEntry(item_id="puff-pastry", name="Puff Pastry", category="Frozen Foods", aliases={"puff pastry": [], "frozen puff pastry": [FacetSelection(key="state", value="frozen")]}, default_unit="pkg", quality_status="enriched"),
        CatalogEntry(item_id="water", name="Water", category="Beverages", aliases={"water": [], "cold water": [FacetSelection(key="temperature", value="cold")]}, default_unit="cup", quality_status="enriched"),
        CatalogEntry(item_id="orange-juice", name="Orange Juice", category="Beverages", aliases={"orange juice": []}, default_unit="cup", quality_status="enriched"),
        CatalogEntry(item_id="parchment-paper", name="Parchment Paper", category="Other", aliases={"parchment paper": [], "baking parchment": []}, default_unit="piece", quality_status="enriched"),
    ]


def _build_test_catalog(storage_dir: Path | None = None) -> MutableIngredientCatalog:
    return MutableIngredientCatalog(_test_entries(), storage_dir=storage_dir)


build_default_catalog = _build_test_catalog


class FakeChatClient:
    def __init__(self, payloads: list[dict]) -> None:
        self._payloads = list(payloads)

    def complete_json(
        self,
        system_prompt: str,
        user_prompt: str,
        schema: dict,
        schema_name: str,
        temperature: float,
        model: str | None = None,
    ) -> dict:
        self.last_call = {
            "system_prompt": system_prompt,
            "user_prompt": user_prompt,
            "schema": schema,
            "schema_name": schema_name,
            "temperature": temperature,
            "model": model,
        }
        if not self._payloads:
            raise AssertionError("FakeChatClient had no payloads remaining.")
        return self._payloads.pop(0)


class FailingSecondCallChatClient(FakeChatClient):
    def complete_json(
        self,
        system_prompt: str,
        user_prompt: str,
        schema: dict,
        schema_name: str,
        temperature: float,
        model: str | None = None,
    ) -> dict:
        if schema_name == "exact_dish_brief":
            raise ValueError("forced exact-dish failure")
        return super().complete_json(system_prompt, user_prompt, schema, schema_name, temperature, model=model)


class SequencedRecipeGenerator:
    def __init__(self, candidates: list[RecipeCandidate]) -> None:
        self._candidates = candidates
        self._index = 0
        self.feedback_history: list[list[str]] = []

    def generate(self, spec: DishSpec, revision_feedback: list[str] | None = None) -> RecipeCandidate:
        self.feedback_history.append(list(revision_feedback or []))
        candidate = self._candidates[min(self._index, len(self._candidates) - 1)]
        self._index += 1
        return candidate


class TitleAwareStaticRecipeGenerator:
    def __init__(self, candidate: RecipeCandidate) -> None:
        self._candidate = candidate

    def generate(self, spec: DishSpec, revision_feedback: list[str] | None = None) -> RecipeCandidate:
        return RecipeCandidate(
            title=spec.title,
            description=self._candidate.description,
            ingredients=self._candidate.ingredients,
            steps=self._candidate.steps,
            servings=self._candidate.servings,
            prep_time_minutes=self._candidate.prep_time_minutes,
            cook_time_minutes=self._candidate.cook_time_minutes,
            difficulty=self._candidate.difficulty,
            dietary_tags=list(self._candidate.dietary_tags),
            meal_type=self._candidate.meal_type,
            cuisine=self._candidate.cuisine,
            source=self._candidate.source,
        )


class ScriptedRecipeReviewer:
    def __init__(self, reports: list[RecipeReviewReport]) -> None:
        self._reports = list(reports)

    def review(self, spec, candidate, artifact, validation, attempt_number):
        if not self._reports:
            raise AssertionError("ScriptedRecipeReviewer had no reports remaining.")
        return self._reports.pop(0)


def _recipe_batch_payload(*titles: str) -> dict:
    return {
        "name": "recipe-corpus-batch-test",
        "dishes": [
            {
                "title": title,
                "cuisine": "Mediterranean",
                "meal_type": "Dinner",
                "servings": 4,
                "goals": ["Weeknight"],
                "pantry_focus": ["chickpeas", "olive oil"],
                "notes": None,
            }
            for title in titles
        ],
    }


class MockPipelineTests(unittest.TestCase):
    def test_mock_pipeline_exports_a_recipe_in_app_shape(self) -> None:
        candidate = RecipeCandidate(
            title="Creamy Garlic Chicken Pasta",
            description="Mock recipe used to validate the external orchestration slice.",
            ingredients=[
                RecipeIngredientInput(name="chicken", quantity=500, unit="g", category="Protein"),
                RecipeIngredientInput(name="fettuccine", quantity=400, unit="g", category="Pasta & Noodles"),
                RecipeIngredientInput(name="cream", quantity=1, unit="cup", category="Dairy"),
                RecipeIngredientInput(name="garlic", quantity=4, unit="clove", category="Produce"),
                RecipeIngredientInput(name="parmesan", quantity=80, unit="g", category="Dairy"),
            ],
            steps=[
                RecipeStepInput(step_number=1, instruction="Slice the chicken."),
                RecipeStepInput(step_number=2, instruction="Cook the pasta."),
                RecipeStepInput(step_number=3, instruction="Build the sauce with cream and parmesan."),
            ],
            servings=4,
            prep_time_minutes=15,
            cook_time_minutes=20,
            difficulty=2,
            meal_type="Dinner",
            cuisine="Italian",
        )

        orchestrator = RecipeIngredientOrchestrator(
            recipe_generator=TitleAwareStaticRecipeGenerator(candidate),
            extraction_worker=IngredientExtractionWorker(),
            resolution_worker=IngredientResolutionWorker(
                catalog=build_default_catalog(),
                ambiguity_resolver=ScriptedAmbiguityResolver(
                    {
                        "chicken": "chicken-breast",
                        "cream": "heavy-cream",
                    }
                ),
            ),
            reconciliation_worker=RecipeReconciliationWorker(),
            validation_worker=RecipeValidationWorker(),
        )

        pipeline_run = orchestrator.run(
            DishSpec(
                title="Creamy Garlic Chicken Pasta",
                cuisine="Italian",
                meal_type="Dinner",
                servings=4,
            )
        )

        self.assertTrue(pipeline_run.validation.is_valid, pipeline_run.validation.errors)
        exported_recipe = pipeline_run.resolved_recipe.to_app_recipe_dict()
        self.assertEqual(exported_recipe["title"], "Creamy Garlic Chicken Pasta")
        self.assertEqual(len(exported_recipe["steps"]), 3)

        ingredient_index = {ingredient["name"]: ingredient for ingredient in exported_recipe["ingredients"]}
        self.assertEqual(ingredient_index["chicken"]["catalogItemID"], "chicken-breast")
        self.assertEqual(ingredient_index["cream"]["catalogItemID"], "heavy-cream")
        self.assertEqual(ingredient_index["fettuccine"]["catalogItemID"], "pasta")
        self.assertEqual(
            ingredient_index["fettuccine"]["facets"],
            [{"key": "form", "value": "fettuccine"}],
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            artifact_paths = ArtifactWriter().write(pipeline_run, Path(tmpdir))
            pipeline_payload = json.loads(Path(artifact_paths["pipeline_run"]).read_text(encoding="utf-8"))
            exported_payload = json.loads(Path(artifact_paths["exported_recipe"]).read_text(encoding="utf-8"))
            seed_recipe_payload = json.loads(Path(artifact_paths["app_seed_recipe"]).read_text(encoding="utf-8"))

        self.assertEqual(pipeline_payload["kind"], "recipe-ingredient-pipeline-run")
        self.assertTrue(pipeline_payload["validation"]["is_valid"])
        self.assertGreaterEqual(pipeline_payload["duration_seconds"], 0)
        self.assertIn("started_at", pipeline_payload)
        self.assertEqual(exported_payload["source"], "aiGenerated")
        self.assertEqual(seed_recipe_payload["mealType"], "Dinner")
        self.assertEqual(seed_recipe_payload["steps"][0]["stepNumber"], 1)

    def test_default_catalog_covers_salmon_rice_bowl_inputs(self) -> None:
        candidate = RecipeCandidate(
            title="Lemon Herb Salmon Rice Bowl",
            description="Mock recipe used to validate broader default catalog coverage.",
            ingredients=[
                RecipeIngredientInput(name="salmon", quantity=500, unit="g", category="Protein"),
                RecipeIngredientInput(name="jasmine rice", quantity=2, unit="cup", category="Grains & Cereals"),
                RecipeIngredientInput(name="lemon", quantity=1, unit="piece", category="Produce"),
                RecipeIngredientInput(name="fresh dill", quantity=1, unit="bunch", category="Spices & Herbs"),
                RecipeIngredientInput(name="baby spinach", quantity=120, unit="g", category="Produce"),
            ],
            steps=[
                RecipeStepInput(step_number=1, instruction="Cook the rice."),
                RecipeStepInput(step_number=2, instruction="Roast the salmon with lemon and dill."),
                RecipeStepInput(step_number=3, instruction="Serve over spinach."),
            ],
            servings=4,
            prep_time_minutes=15,
            cook_time_minutes=20,
            difficulty=2,
            meal_type="Dinner",
            cuisine="Mediterranean",
        )

        orchestrator = RecipeIngredientOrchestrator(
            recipe_generator=TitleAwareStaticRecipeGenerator(candidate),
            extraction_worker=IngredientExtractionWorker(),
            resolution_worker=IngredientResolutionWorker(
                catalog=build_default_catalog(),
                ambiguity_resolver=ScriptedAmbiguityResolver({}),
            ),
            reconciliation_worker=RecipeReconciliationWorker(),
            validation_worker=RecipeValidationWorker(),
        )

        pipeline_run = orchestrator.run(
            DishSpec(
                title="Lemon Herb Salmon Rice Bowl",
                cuisine="Mediterranean",
                meal_type="Dinner",
                servings=4,
            )
        )

        self.assertTrue(pipeline_run.validation.is_valid, pipeline_run.validation.errors)
        ingredient_index = {
            ingredient.raw_name: ingredient.catalog_item_id
            for ingredient in pipeline_run.resolved_recipe.ingredients
        }
        self.assertEqual(ingredient_index["salmon"], "salmon")
        self.assertEqual(ingredient_index["jasmine rice"], "rice")
        self.assertEqual(ingredient_index["lemon"], "lemon")
        self.assertEqual(ingredient_index["fresh dill"], "dill")
        self.assertEqual(ingredient_index["baby spinach"], "spinach")

    def test_default_catalog_covers_common_broth_inputs(self) -> None:
        candidate = RecipeCandidate(
            title="Weeknight Chicken Rice Soup",
            description="Mock recipe used to validate broth coverage.",
            ingredients=[
                RecipeIngredientInput(name="chicken broth", quantity=4, unit="cup", category="Canned & Jarred"),
                RecipeIngredientInput(name="rice", quantity=1, unit="cup", category="Grains & Cereals"),
                RecipeIngredientInput(name="garlic", quantity=2, unit="clove", category="Produce"),
            ],
            steps=[
                RecipeStepInput(step_number=1, instruction="Bring the broth to a simmer."),
                RecipeStepInput(step_number=2, instruction="Add rice and garlic and cook until tender."),
            ],
            servings=4,
            prep_time_minutes=10,
            cook_time_minutes=25,
            difficulty=1,
            meal_type="Dinner",
            cuisine="Other",
        )

        orchestrator = RecipeIngredientOrchestrator(
            recipe_generator=TitleAwareStaticRecipeGenerator(candidate),
            extraction_worker=IngredientExtractionWorker(),
            resolution_worker=IngredientResolutionWorker(
                catalog=build_default_catalog(),
                ambiguity_resolver=ScriptedAmbiguityResolver({}),
            ),
            reconciliation_worker=RecipeReconciliationWorker(),
            validation_worker=RecipeValidationWorker(),
        )

        pipeline_run = orchestrator.run(
            DishSpec(
                title="Weeknight Chicken Rice Soup",
                meal_type="Dinner",
                servings=4,
            )
        )

        self.assertTrue(pipeline_run.validation.is_valid, pipeline_run.validation.errors)
        ingredient_index = {
            ingredient.raw_name: ingredient.catalog_item_id
            for ingredient in pipeline_run.resolved_recipe.ingredients
        }
        self.assertEqual(ingredient_index["chicken broth"], "chicken-broth")

    def test_default_catalog_covers_common_french_inputs(self) -> None:
        candidate = RecipeCandidate(
            title="French Pantry Coverage",
            description="Validate broader pantry coverage for French-style recipes.",
            ingredients=[
                RecipeIngredientInput(name="bacon", quantity=200, unit="g", category="Protein"),
                RecipeIngredientInput(name="nutmeg", quantity=1, unit="tsp", category="Spices & Herbs"),
                RecipeIngredientInput(name="bay leaves", quantity=2, unit="piece", category="Spices & Herbs"),
                RecipeIngredientInput(name="fennel bulb", quantity=1, unit="piece", category="Produce"),
                RecipeIngredientInput(name="saffron threads", quantity=1, unit="pinch", category="Spices & Herbs"),
                RecipeIngredientInput(name="vanilla extract", quantity=1, unit="tsp", category="Baking Supplies"),
                RecipeIngredientInput(name="frozen puff pastry", quantity=1, unit="pkg", category="Frozen Foods"),
                RecipeIngredientInput(name="white fish fillets", quantity=400, unit="g", category="Protein"),
                RecipeIngredientInput(name="granny smith apples", quantity=4, unit="piece", category="Produce"),
                RecipeIngredientInput(name="orange juice", quantity=0.5, unit="cup", category="Beverages"),
                RecipeIngredientInput(name="eggplant", quantity=1, unit="piece", category="Produce"),
                RecipeIngredientInput(name="zucchini", quantity=1, unit="piece", category="Produce"),
                RecipeIngredientInput(name="cold water", quantity=0.25, unit="cup", category="Beverages"),
                RecipeIngredientInput(name="parchment paper", quantity=1, unit="piece", category="Other"),
            ],
            steps=[
                RecipeStepInput(step_number=1, instruction="Prepare the ingredients."),
                RecipeStepInput(step_number=2, instruction="Cook or bake as needed."),
            ],
            servings=4,
            prep_time_minutes=20,
            cook_time_minutes=45,
            difficulty=2,
            meal_type="Dinner",
            cuisine="French",
        )

        orchestrator = RecipeIngredientOrchestrator(
            recipe_generator=TitleAwareStaticRecipeGenerator(candidate),
            extraction_worker=IngredientExtractionWorker(),
            resolution_worker=IngredientResolutionWorker(
                catalog=build_default_catalog(),
                ambiguity_resolver=ScriptedAmbiguityResolver({}),
            ),
            reconciliation_worker=RecipeReconciliationWorker(),
            validation_worker=RecipeValidationWorker(),
        )

        pipeline_run = orchestrator.run(DishSpec(title="French Pantry Coverage", cuisine="French", meal_type="Dinner", servings=4))

        self.assertTrue(pipeline_run.validation.is_valid, pipeline_run.validation.errors)
        ingredient_index = {
            ingredient.raw_name: ingredient.catalog_item_id
            for ingredient in pipeline_run.resolved_recipe.ingredients
        }
        self.assertEqual(ingredient_index["bacon"], "bacon")
        self.assertEqual(ingredient_index["nutmeg"], "nutmeg")
        self.assertEqual(ingredient_index["bay leaves"], "bay-leaf")
        self.assertEqual(ingredient_index["fennel bulb"], "fennel")
        self.assertEqual(ingredient_index["saffron threads"], "saffron")
        self.assertEqual(ingredient_index["vanilla extract"], "vanilla-extract")
        self.assertEqual(ingredient_index["frozen puff pastry"], "puff-pastry")
        self.assertEqual(ingredient_index["white fish fillets"], "white-fish")
        self.assertEqual(ingredient_index["granny smith apples"], "apple")
        self.assertEqual(ingredient_index["orange juice"], "orange-juice")
        self.assertEqual(ingredient_index["eggplant"], "eggplant")
        self.assertEqual(ingredient_index["zucchini"], "zucchini")
        self.assertEqual(ingredient_index["cold water"], "water")
        self.assertEqual(ingredient_index["parchment paper"], "parchment-paper")

    def test_orchestrator_enriches_same_recipe_without_regenerating(self) -> None:
        candidate = RecipeCandidate(
            title="Simple Apple Tart",
            description="Test ingredient enrichment flow.",
            ingredients=[
                RecipeIngredientInput(name="granny smith apples", quantity=3, unit="piece", category="Produce"),
                RecipeIngredientInput(name="caster sugar", quantity=0.5, unit="cup", category="Baking Supplies"),
                RecipeIngredientInput(name="silicone baking liner", quantity=1, unit="piece", category="Other"),
                RecipeIngredientInput(name="butter", quantity=2, unit="tbsp", category="Dairy"),
            ],
            steps=[
                RecipeStepInput(step_number=1, instruction="Prepare the apples and sugar."),
                RecipeStepInput(step_number=2, instruction="Bake until golden."),
            ],
            servings=4,
            prep_time_minutes=15,
            cook_time_minutes=35,
            difficulty=2,
            meal_type="Dessert",
            cuisine="French",
        )

        generator = SequencedRecipeGenerator([candidate])
        orchestrator = RecipeIngredientOrchestrator(
            recipe_generator=generator,
            extraction_worker=IngredientExtractionWorker(),
            resolution_worker=IngredientResolutionWorker(
                catalog=build_default_catalog(),
                ambiguity_resolver=ScriptedAmbiguityResolver({}),
            ),
            reconciliation_worker=RecipeReconciliationWorker(),
            validation_worker=RecipeValidationWorker(),
            ingredient_enricher=ScriptedIngredientEnricher(
                {
                    "caster sugar": IngredientEnrichmentDecision(
                        raw_name="caster sugar",
                        action="add_catalog_entry",
                        canonical_name="Sugar",
                        category="Baking Supplies",
                        aliases=["caster sugar", "superfine sugar"],
                        default_unit="cup",
                        rationale="Broaden the supermarket term to the pantry ingredient sugar.",
                    ),
                    "silicone baking liner": IngredientEnrichmentDecision(
                        raw_name="silicone baking liner",
                        action="ignore",
                        rationale="This is a baking aid, not a pantry ingredient.",
                    ),
                }
            ),
            max_attempts=3,
            max_resolution_cycles=2,
        )

        pipeline_run = orchestrator.run(DishSpec(title="Simple Apple Tart", cuisine="French", meal_type="Dessert", servings=4))

        self.assertTrue(pipeline_run.validation.is_valid, pipeline_run.validation.errors)
        self.assertEqual(pipeline_run.generation_attempts, 1)
        self.assertEqual(len(generator.feedback_history), 1)
        self.assertEqual([decision.raw_name for decision in pipeline_run.ingredient_enrichment_decisions], ["silicone baking liner"])
        ingredient_status = {ingredient.raw_name: ingredient.status for ingredient in pipeline_run.resolved_recipe.ingredients}
        ingredient_catalog_ids = {ingredient.raw_name: ingredient.catalog_item_id for ingredient in pipeline_run.resolved_recipe.ingredients}
        self.assertEqual(ingredient_catalog_ids["caster sugar"], "sugar")
        self.assertEqual(ingredient_status["silicone baking liner"], "ignored")

    def test_placeholder_ingredients_are_eventually_enriched(self) -> None:
        candidate = RecipeCandidate(
            title="Placeholder Upgrade Tart",
            description="Exercise placeholder upgrade behavior.",
            ingredients=[
                RecipeIngredientInput(name="panela", quantity=0.5, unit="cup", category="Baking Supplies"),
                RecipeIngredientInput(name="butter", quantity=2, unit="tbsp", category="Dairy"),
            ],
            steps=[
                RecipeStepInput(step_number=1, instruction="Mix the ingredients."),
                RecipeStepInput(step_number=2, instruction="Bake until done."),
            ],
            servings=4,
            prep_time_minutes=10,
            cook_time_minutes=25,
            difficulty=2,
            meal_type="Dessert",
            cuisine="French",
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            storage_dir = Path(tmpdir) / "catalog"

            first_orchestrator = RecipeIngredientOrchestrator(
                recipe_generator=StaticRecipeGenerator(candidate),
                extraction_worker=IngredientExtractionWorker(),
                resolution_worker=IngredientResolutionWorker(
                    catalog=build_default_catalog(storage_dir=storage_dir),
                    ambiguity_resolver=ScriptedAmbiguityResolver({}),
                ),
                reconciliation_worker=RecipeReconciliationWorker(),
                validation_worker=RecipeValidationWorker(),
                ingredient_enricher=ScriptedIngredientEnricher({}),
                max_attempts=1,
                max_resolution_cycles=1,
            )

            first_run = first_orchestrator.run(
                DishSpec(title="Placeholder Upgrade Tart", cuisine="French", meal_type="Dessert", servings=4)
            )

            first_sugar = next(
                ingredient for ingredient in first_run.resolved_recipe.ingredients if ingredient.raw_name == "panela"
            )
            self.assertEqual(first_sugar.catalog_item_id, "panela")
            self.assertIsNotNone(first_sugar.ingredient_record)
            self.assertEqual(first_sugar.ingredient_record.quality_status, "placeholder")

            second_orchestrator = RecipeIngredientOrchestrator(
                recipe_generator=StaticRecipeGenerator(candidate),
                extraction_worker=IngredientExtractionWorker(),
                resolution_worker=IngredientResolutionWorker(
                    catalog=build_default_catalog(storage_dir=storage_dir),
                    ambiguity_resolver=ScriptedAmbiguityResolver({}),
                ),
                reconciliation_worker=RecipeReconciliationWorker(),
                validation_worker=RecipeValidationWorker(),
                ingredient_enricher=ScriptedIngredientEnricher(
                    {
                        "panela": IngredientEnrichmentDecision(
                            raw_name="panela",
                            action="add_catalog_entry",
                            canonical_name="Sugar",
                            category="Baking Supplies",
                            aliases=["panela"],
                            default_unit="cup",
                            rationale="Broaden panela to the canonical pantry ingredient sugar.",
                            quality_status="enriched",
                        )
                    }
                ),
                max_attempts=1,
                max_resolution_cycles=2,
            )

            second_run = second_orchestrator.run(
                DishSpec(title="Placeholder Upgrade Tart", cuisine="French", meal_type="Dessert", servings=4)
            )

            second_sugar = next(
                ingredient for ingredient in second_run.resolved_recipe.ingredients if ingredient.raw_name == "panela"
            )
            self.assertEqual(second_sugar.catalog_item_id, "sugar")
            self.assertIsNotNone(second_sugar.ingredient_record)
            self.assertEqual(second_sugar.ingredient_record.quality_status, "enriched")
            self.assertTrue((storage_dir / "sugar.json").exists())
            self.assertFalse((storage_dir / "panela.json").exists())

    def test_campaign_runner_writes_state_and_promoted_ingredients(self) -> None:
        candidate = RecipeCandidate(
            title="Creamy Garlic Chicken Pasta",
            description="Mock recipe used to validate campaign persistence.",
            ingredients=[
                RecipeIngredientInput(name="chicken", quantity=500, unit="g", category="Protein"),
                RecipeIngredientInput(name="cream", quantity=1, unit="cup", category="Dairy"),
                RecipeIngredientInput(name="garlic", quantity=4, unit="clove", category="Produce"),
            ],
            steps=[
                RecipeStepInput(step_number=1, instruction="Prep ingredients."),
                RecipeStepInput(step_number=2, instruction="Cook everything together."),
            ],
            servings=4,
            prep_time_minutes=15,
            cook_time_minutes=20,
            difficulty=2,
            meal_type="Dinner",
            cuisine="Italian",
        )

        orchestrator = RecipeIngredientOrchestrator(
            recipe_generator=TitleAwareStaticRecipeGenerator(candidate),
            extraction_worker=IngredientExtractionWorker(),
            resolution_worker=IngredientResolutionWorker(
                catalog=build_default_catalog(),
                ambiguity_resolver=ScriptedAmbiguityResolver(
                    {
                        "chicken": "chicken-breast",
                        "cream": "heavy-cream",
                    }
                ),
            ),
            reconciliation_worker=RecipeReconciliationWorker(),
            validation_worker=RecipeValidationWorker(),
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            runner = RecipeCampaignRunner(
                orchestrator=orchestrator,
                artifact_writer=ArtifactWriter(),
                promotion_store=IngredientPromotionStore(),
                root_dir=Path(tmpdir),
                max_workers=1,
            )
            state = runner.run_campaign(
                CampaignSpec(
                    name="test-campaign",
                    dishes=[
                        DishSpec(
                            title="Creamy Garlic Chicken Pasta",
                            cuisine="Italian",
                            meal_type="Dinner",
                            servings=4,
                        )
                    ],
                )
            )

            self.assertEqual(state.status, "completed")
            self.assertEqual(len(state.items), 1)
            item = state.items[0]
            self.assertEqual(item.status, "completed")
            self.assertTrue(item.exported_recipe_path)
            self.assertTrue(item.pipeline_run_path)
            self.assertIn("chicken-breast", item.promoted_item_ids)
            self.assertIn("heavy-cream", item.promoted_item_ids)

            state_path = Path(tmpdir) / state.campaign_id / "state.json"
            metrics_path = Path(tmpdir) / state.campaign_id / "campaign_metrics.json"
            app_import_bundle_path = Path(tmpdir) / state.campaign_id / "app_import" / "seed_recipes.json"
            promotion_path = Path(tmpdir) / state.campaign_id / "ingredient_corpus" / "promoted" / "chicken-breast.json"
            self.assertTrue(state_path.exists())
            self.assertTrue(metrics_path.exists())
            self.assertTrue(app_import_bundle_path.exists())
            self.assertTrue(promotion_path.exists())

            stored_state = json.loads(state_path.read_text(encoding="utf-8"))
            stored_metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
            app_import_bundle = json.loads(app_import_bundle_path.read_text(encoding="utf-8"))
            stored_promotion = json.loads(promotion_path.read_text(encoding="utf-8"))
            self.assertEqual(stored_state["status"], "completed")
            self.assertEqual(stored_metrics["summary"]["promoted_item_count"], 3)
            self.assertEqual(stored_metrics["summary"]["resolved_ingredient_count"], 3)
            self.assertEqual(len(app_import_bundle), 1)
            self.assertEqual(app_import_bundle[0]["title"], "Creamy Garlic Chicken Pasta")
            self.assertEqual(stored_promotion["item_id"], "chicken-breast")

    def test_campaign_runner_parallel_overlap_writes_complete_successfully(self) -> None:
        candidate = RecipeCandidate(
            title="Creamy Garlic Chicken Pasta",
            description="Mock recipe used to validate concurrent promotion writes.",
            ingredients=[
                RecipeIngredientInput(name="chicken", quantity=500, unit="g", category="Protein"),
                RecipeIngredientInput(name="cream", quantity=1, unit="cup", category="Dairy"),
                RecipeIngredientInput(name="garlic", quantity=4, unit="clove", category="Produce"),
            ],
            steps=[
                RecipeStepInput(step_number=1, instruction="Prep ingredients."),
                RecipeStepInput(step_number=2, instruction="Cook everything together."),
            ],
            servings=4,
            prep_time_minutes=15,
            cook_time_minutes=20,
            difficulty=2,
            meal_type="Dinner",
            cuisine="Italian",
        )

        orchestrator = RecipeIngredientOrchestrator(
            recipe_generator=TitleAwareStaticRecipeGenerator(candidate),
            extraction_worker=IngredientExtractionWorker(),
            resolution_worker=IngredientResolutionWorker(
                catalog=build_default_catalog(),
                ambiguity_resolver=ScriptedAmbiguityResolver(
                    {
                        "chicken": "chicken-breast",
                        "cream": "heavy-cream",
                    }
                ),
            ),
            reconciliation_worker=RecipeReconciliationWorker(),
            validation_worker=RecipeValidationWorker(),
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            runner = RecipeCampaignRunner(
                orchestrator=orchestrator,
                artifact_writer=ArtifactWriter(),
                promotion_store=IngredientPromotionStore(),
                root_dir=Path(tmpdir),
                max_workers=3,
            )
            state = runner.run_campaign(
                CampaignSpec(
                    name="parallel-overlap-campaign",
                    dishes=[
                        DishSpec(title="Dish A", meal_type="Dinner", servings=4),
                        DishSpec(title="Dish B", meal_type="Dinner", servings=4),
                        DishSpec(title="Dish C", meal_type="Dinner", servings=4),
                    ],
                )
            )

            self.assertEqual(state.status, "completed")
            self.assertTrue(all(item.status == "completed" for item in state.items))

            promotion_path = Path(tmpdir) / state.campaign_id / "ingredient_corpus" / "promoted" / "chicken-breast.json"
            bundle_path = Path(tmpdir) / state.campaign_id / "app_import" / "seed_recipes.json"
            promoted_payload = json.loads(promotion_path.read_text(encoding="utf-8"))
            bundle_payload = json.loads(bundle_path.read_text(encoding="utf-8"))

            self.assertEqual(len(bundle_payload), 3)
            self.assertEqual(len(promoted_payload["evidence"]), 3)

    def test_config_resolves_openai_key_from_same_xcconfig_chain_as_app(self) -> None:
        original_env = os.environ.pop("OPENAI_API_KEY", None)
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                root = Path(tmpdir)
                config_dir = root / "Config"
                base_dir = root / "Scripts" / "recipe_ingredient_orchestrator"
                config_dir.mkdir(parents=True)
                base_dir.mkdir(parents=True)

                (config_dir / "Secrets.xcconfig").write_text(
                    '#include? "LocalSecrets.xcconfig"\n',
                    encoding="utf-8",
                )
                (config_dir / "LocalSecrets.xcconfig").write_text(
                    'OPENAI_API_KEY = sk-test-from-local-secrets\n',
                    encoding="utf-8",
                )

                config = OrchestratorConfig.from_env(base_dir=base_dir)
                self.assertEqual(config.openai_api_key, "sk-test-from-local-secrets")
                self.assertEqual(config.openai_api_key_source, "xcconfig:Config/LocalSecrets.xcconfig")
        finally:
            if original_env is not None:
                os.environ["OPENAI_API_KEY"] = original_env

    def test_request_planner_retries_until_model_plan_is_unique(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            resource_dir = root / "PantryChef" / "Resources"
            resource_dir.mkdir(parents=True)
            (resource_dir / "seed_recipes.json").write_text(
                json.dumps(
                    [
                        {
                            "title": "Butter Chicken",
                            "description": "Existing recipe.",
                            "cuisine": "Indian",
                            "mealType": "Dinner",
                            "difficulty": 3,
                            "servings": 4,
                            "prepTimeMinutes": 20,
                            "cookTimeMinutes": 30,
                            "dietaryTags": [],
                            "ingredients": [{"name": "Chicken", "quantity": 1, "unit": "lb", "category": "Protein"}],
                            "steps": [{"stepNumber": 1, "instruction": "Cook.", "estimatedDurationSeconds": 60}],
                        }
                    ]
                ),
                encoding="utf-8",
            )

            planner = RequestPlanningService(
                RecipeCorpusIndex.from_project_root(root),
                client=FakeChatClient(
                    [
                        {
                            "desired_count": 3,
                            "cuisine": "Indian",
                            "meal_type": "Dinner",
                            "exact_title": None,
                        },
                        {
                            "name": "request-indian-3",
                            "dishes": [
                                {
                                    "title": "Butter Chicken",
                                    "cuisine": "Indian",
                                    "meal_type": "Dinner",
                                    "servings": 4,
                                    "goals": ["comforting"],
                                    "pantry_focus": ["chicken", "tomato", "cream"],
                                    "notes": "First attempt duplicates existing corpus.",
                                },
                                {
                                    "title": "Chana Masala",
                                    "cuisine": "Indian",
                                    "meal_type": "Dinner",
                                    "servings": 4,
                                    "goals": ["hearty"],
                                    "pantry_focus": ["chickpeas", "tomato", "garlic"],
                                    "notes": "Unique candidate.",
                                },
                                {
                                    "title": "Aloo Gobi",
                                    "cuisine": "Indian",
                                    "meal_type": "Dinner",
                                    "servings": 4,
                                    "goals": ["vegetarian"],
                                    "pantry_focus": ["potato", "cauliflower", "turmeric"],
                                    "notes": "Unique candidate.",
                                },
                            ],
                        },
                        {
                            "name": "request-indian-3",
                            "dishes": [
                                {
                                    "title": "Chana Masala",
                                    "cuisine": "Indian",
                                    "meal_type": "Dinner",
                                    "servings": 4,
                                    "goals": ["hearty"],
                                    "pantry_focus": ["chickpeas", "tomato", "garlic"],
                                    "notes": "Unique candidate.",
                                },
                                {
                                    "title": "Aloo Gobi",
                                    "cuisine": "Indian",
                                    "meal_type": "Dinner",
                                    "servings": 4,
                                    "goals": ["vegetarian"],
                                    "pantry_focus": ["potato", "cauliflower", "turmeric"],
                                    "notes": "Unique candidate.",
                                },
                                {
                                    "title": "Dal Tadka",
                                    "cuisine": "Indian",
                                    "meal_type": "Dinner",
                                    "servings": 4,
                                    "goals": ["protein rich"],
                                    "pantry_focus": ["lentils", "garlic", "cumin"],
                                    "notes": "Second attempt is fully unique.",
                                },
                            ],
                        },
                    ]
                ),
            )
            spec = planner.plan("generate 3 indian recipes")

            self.assertEqual(len(spec.dishes), 3)
            self.assertTrue(all(dish.cuisine == "Indian" for dish in spec.dishes))
            self.assertEqual(len({dish.title for dish in spec.dishes}), 3)
            self.assertNotIn("Butter Chicken", {dish.title for dish in spec.dishes})
            for dish in spec.dishes:
                self.assertNotIn(dish.title, dish.avoid_titles)
                self.assertEqual(len(set(dish.avoid_titles)), len(dish.avoid_titles))

    def test_request_planner_handles_single_explicit_recipe_request(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            resource_dir = root / "PantryChef" / "Resources"
            resource_dir.mkdir(parents=True)
            (resource_dir / "seed_recipes.json").write_text("[]\n", encoding="utf-8")

            planner = RequestPlanningService(
                RecipeCorpusIndex.from_project_root(root),
                client=FakeChatClient(
                    [
                        {
                            "desired_count": 1,
                            "cuisine": "French",
                            "meal_type": "Dinner",
                            "exact_title": "Duck Confit",
                        },
                        {
                            "title": "Duck Confit",
                            "cuisine": "French",
                            "meal_type": "Dinner",
                            "servings": 4,
                            "pantry_focus": ["duck legs", "duck fat", "garlic", "thyme", "salt"],
                            "goals": ["classic texture", "realistic curing workflow"],
                            "notes": "Structured exact-dish brief.",
                        },
                    ]
                ),
            )
            spec = planner.plan("generate a duck confit recipe")

            self.assertEqual(len(spec.dishes), 1)
            self.assertEqual(spec.dishes[0].title, "Duck Confit")
            self.assertEqual(spec.dishes[0].cuisine, "French")

    def test_corpus_index_detects_duplicate_candidate_titles(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            resource_dir = root / "PantryChef" / "Resources"
            resource_dir.mkdir(parents=True)
            (resource_dir / "seed_recipes.json").write_text(
                json.dumps(
                    [
                        {
                            "title": "Chicken Tacos",
                            "description": "Existing recipe.",
                            "cuisine": "Mexican",
                            "mealType": "Dinner",
                            "difficulty": 2,
                            "servings": 4,
                            "prepTimeMinutes": 15,
                            "cookTimeMinutes": 15,
                            "dietaryTags": [],
                            "ingredients": [
                                {"name": "Chicken Breast", "quantity": 1, "unit": "lb", "category": "Protein"},
                                {"name": "Tortilla", "quantity": 8, "unit": "piece", "category": "Grains & Cereals"},
                            ],
                            "steps": [{"stepNumber": 1, "instruction": "Cook.", "estimatedDurationSeconds": 60}],
                        }
                    ]
                ),
                encoding="utf-8",
            )

            corpus_index = RecipeCorpusIndex.from_project_root(root)
            candidate = RecipeCandidate(
                title="Chicken Tacos",
                description="Potential duplicate.",
                ingredients=[
                    RecipeIngredientInput(name="Chicken Breast", quantity=500, unit="g", category="Protein"),
                    RecipeIngredientInput(name="Tortilla", quantity=8, unit="piece", category="Grains & Cereals"),
                ],
                steps=[RecipeStepInput(step_number=1, instruction="Cook everything.")],
                servings=4,
                prep_time_minutes=15,
                cook_time_minutes=15,
                difficulty=2,
                meal_type="Dinner",
                cuisine="Mexican",
            )

            reason = corpus_index.duplicate_reason_for_candidate(candidate)
            self.assertIsNotNone(reason)
            self.assertIn("duplicates existing recipe", reason)

    def test_request_planner_rejects_single_recipe_duplicates(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            resource_dir = root / "PantryChef" / "Resources"
            resource_dir.mkdir(parents=True)
            (resource_dir / "seed_recipes.json").write_text(
                json.dumps(
                    [
                        {
                            "title": "Duck Confit",
                            "description": "Existing recipe.",
                            "cuisine": "French",
                            "mealType": "Dinner",
                            "difficulty": 4,
                            "servings": 4,
                            "prepTimeMinutes": 30,
                            "cookTimeMinutes": 180,
                            "dietaryTags": [],
                            "ingredients": [{"name": "Duck Leg", "quantity": 4, "unit": "piece", "category": "Protein"}],
                            "steps": [{"stepNumber": 1, "instruction": "Cook.", "estimatedDurationSeconds": 60}],
                        }
                    ]
                ),
                encoding="utf-8",
            )

            planner = RequestPlanningService(
                RecipeCorpusIndex.from_project_root(root),
                client=FakeChatClient(
                    [
                        {
                            "desired_count": 1,
                            "cuisine": "French",
                            "meal_type": "Dinner",
                            "exact_title": "Duck Confit",
                        }
                    ]
                ),
            )
            with self.assertRaisesRegex(RuntimeError, "duplicates existing recipe"):
                planner.plan("generate a duck confit recipe")

    def test_exact_dish_planning_requires_model_confirmation(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            resource_dir = root / "PantryChef" / "Resources"
            resource_dir.mkdir(parents=True)
            (resource_dir / "seed_recipes.json").write_text("[]\n", encoding="utf-8")

            planner = RequestPlanningService(
                RecipeCorpusIndex.from_project_root(root),
                client=FailingSecondCallChatClient(
                    [
                        {
                            "desired_count": 1,
                            "cuisine": "French",
                            "meal_type": "Dinner",
                            "exact_title": "Duck Confit",
                        },
                    ]
                ),
            )

            with self.assertRaisesRegex(RuntimeError, "Unable to build an exact-dish brief"):
                planner.plan("generate a duck confit recipe")

    def test_request_planner_uses_model_intent_and_exact_dish_briefing(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            resource_dir = root / "PantryChef" / "Resources"
            resource_dir.mkdir(parents=True)
            (resource_dir / "seed_recipes.json").write_text("[]\n", encoding="utf-8")

            planner = RequestPlanningService(
                RecipeCorpusIndex.from_project_root(root),
                client=FakeChatClient(
                    [
                        {
                            "desired_count": 1,
                            "cuisine": "French",
                            "meal_type": "Dinner",
                            "exact_title": "Duck Confit",
                        },
                        {
                            "title": "Duck Confit",
                            "cuisine": "French",
                            "meal_type": "Dinner",
                            "servings": 4,
                            "pantry_focus": ["duck legs", "duck fat", "garlic", "thyme", "salt"],
                            "goals": ["classic texture", "realistic curing workflow"],
                            "notes": "Structured exact-dish brief.",
                        },
                    ]
                ),
            )

            spec = planner.plan("generate a duck confit recipe")

            self.assertEqual(len(spec.dishes), 1)
            self.assertEqual(spec.dishes[0].title, "Duck Confit")
            self.assertEqual(spec.dishes[0].cuisine, "French")
            self.assertIn("duck legs", spec.dishes[0].pantry_focus)
            self.assertIn("realistic curing workflow", spec.dishes[0].goals)

    def test_title_mismatch_fails_validation_without_being_hidden(self) -> None:
        candidate = RecipeCandidate(
            title="Rustic Meat Pie with Herb Pastry Crust",
            description="Wrongly titled version of the requested dish.",
            ingredients=[
                RecipeIngredientInput(name="ground pork", quantity=1, unit="lb", category="Protein"),
                RecipeIngredientInput(name="all purpose flour", quantity=2, unit="cup", category="Baking Supplies"),
            ],
            steps=[
                RecipeStepInput(step_number=1, instruction="Prepare the pastry."),
                RecipeStepInput(step_number=2, instruction="Bake the pie."),
            ],
            servings=6,
            prep_time_minutes=30,
            cook_time_minutes=60,
            difficulty=4,
            meal_type="Lunch",
            cuisine="French",
        )

        orchestrator = RecipeIngredientOrchestrator(
            recipe_generator=StaticRecipeGenerator(candidate),
            extraction_worker=IngredientExtractionWorker(),
            resolution_worker=IngredientResolutionWorker(
                catalog=build_default_catalog(),
                ambiguity_resolver=ScriptedAmbiguityResolver({"ground pork": "pork"}),
            ),
            reconciliation_worker=RecipeReconciliationWorker(),
            validation_worker=RecipeValidationWorker(),
        )

        pipeline_run = orchestrator.run(
            DishSpec(title="Pâté en Croûte", cuisine="French", meal_type="Lunch", servings=6)
        )

        self.assertFalse(pipeline_run.validation.is_valid)
        self.assertIn("requested_title_mismatch", pipeline_run.validation.error_codes)
        self.assertEqual(pipeline_run.failure_code, "dish_alignment_failed")
        self.assertEqual(pipeline_run.recipe_candidate.title, "Rustic Meat Pie with Herb Pastry Crust")
        self.assertEqual(pipeline_run.resolved_recipe.title, "Rustic Meat Pie with Herb Pastry Crust")

    def test_duplicate_reason_catches_near_duplicate_titles(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            resource_dir = root / "PantryChef" / "Resources"
            resource_dir.mkdir(parents=True)
            (resource_dir / "seed_recipes.json").write_text(
                json.dumps(
                    [
                        {
                            "title": "Chicken Parmesan",
                            "description": "Existing recipe.",
                            "cuisine": "Italian",
                            "mealType": "Dinner",
                            "difficulty": 2,
                            "servings": 4,
                            "prepTimeMinutes": 20,
                            "cookTimeMinutes": 25,
                            "dietaryTags": [],
                            "ingredients": [
                                {"name": "Chicken Breast", "quantity": 1, "unit": "lb", "category": "Protein"},
                                {"name": "Parmesan", "quantity": 50, "unit": "g", "category": "Dairy"},
                            ],
                            "steps": [{"stepNumber": 1, "instruction": "Bread and bake the chicken.", "estimatedDurationSeconds": 60}],
                        }
                    ]
                ),
                encoding="utf-8",
            )

            corpus_index = RecipeCorpusIndex.from_project_root(root)
            reason = corpus_index.duplicate_reason_for_title("Chicken Parm")
            self.assertIsNotNone(reason)
            self.assertIn("too similar", reason)

    def test_orchestrator_retries_after_semantic_review_revision(self) -> None:
        first_candidate = RecipeCandidate(
            title="Duck Confit",
            description="First draft.",
            ingredients=[
                RecipeIngredientInput(name="chicken", quantity=500, unit="g", category="Protein"),
                RecipeIngredientInput(name="salt", quantity=1, unit="pinch", category="Spices & Herbs"),
            ],
            steps=[RecipeStepInput(step_number=1, instruction="Cook the protein.")],
            servings=4,
            prep_time_minutes=10,
            cook_time_minutes=20,
            difficulty=2,
            meal_type="Dinner",
            cuisine="French",
        )
        second_candidate = RecipeCandidate(
            title="Duck Confit",
            description="Revised draft.",
            ingredients=[
                RecipeIngredientInput(name="chicken thigh", quantity=500, unit="g", category="Protein"),
                RecipeIngredientInput(name="garlic", quantity=4, unit="clove", category="Produce"),
                RecipeIngredientInput(name="olive oil", quantity=2, unit="tbsp", category="Oils & Fats"),
                RecipeIngredientInput(name="salt", quantity=1, unit="pinch", category="Spices & Herbs"),
            ],
            steps=[
                RecipeStepInput(step_number=1, instruction="Season the meat and rest it."),
                RecipeStepInput(step_number=2, instruction="Cook it slowly with the aromatics until tender."),
            ],
            servings=4,
            prep_time_minutes=30,
            cook_time_minutes=180,
            difficulty=4,
            meal_type="Dinner",
            cuisine="French",
        )

        generator = SequencedRecipeGenerator([first_candidate, second_candidate])
        reviewer = ScriptedRecipeReviewer(
            [
                RecipeReviewReport(
                    status="revise",
                    reviewer="scripted",
                    rationale="The first draft is not credible for duck confit.",
                    issues=[ReviewIssue(code="dish_mismatch", severity="error", message="Use a confit-style fat cook instead of a generic protein saute.")],
                    revision_instructions=["Revise the recipe so it uses a slow confit-style preparation and more appropriate ingredients."],
                    retryable=True,
                ),
                RecipeReviewReport(
                    status="accepted",
                    reviewer="scripted",
                    rationale="The revised recipe is acceptable.",
                    retryable=False,
                ),
            ]
        )

        orchestrator = RecipeIngredientOrchestrator(
            recipe_generator=generator,
            extraction_worker=IngredientExtractionWorker(),
            resolution_worker=IngredientResolutionWorker(
                catalog=build_default_catalog(),
                ambiguity_resolver=ScriptedAmbiguityResolver({"chicken": "chicken-breast", "chicken thigh": "chicken-thigh"}),
            ),
            reconciliation_worker=RecipeReconciliationWorker(),
            validation_worker=RecipeValidationWorker(),
            review_worker=reviewer,
            max_attempts=2,
        )

        pipeline_run = orchestrator.run(DishSpec(title="Duck Confit", cuisine="French", meal_type="Dinner", servings=4))

        self.assertTrue(pipeline_run.validation.is_valid)
        self.assertEqual(pipeline_run.review.status, "accepted")
        self.assertEqual(pipeline_run.generation_attempts, 2)
        self.assertEqual(pipeline_run.attempt_history[0].failure_code, "semantic_review_revision")
        self.assertIn("slow confit-style preparation", generator.feedback_history[1][0])

    def test_campaign_runner_writes_durable_accepted_bundle(self) -> None:
        candidate = RecipeCandidate(
            title="Creamy Garlic Chicken Pasta",
            description="Accepted corpus candidate.",
            ingredients=[
                RecipeIngredientInput(name="chicken", quantity=500, unit="g", category="Protein"),
                RecipeIngredientInput(name="cream", quantity=1, unit="cup", category="Dairy"),
                RecipeIngredientInput(name="garlic", quantity=4, unit="clove", category="Produce"),
            ],
            steps=[
                RecipeStepInput(step_number=1, instruction="Prep ingredients."),
                RecipeStepInput(step_number=2, instruction="Cook everything together."),
            ],
            servings=4,
            prep_time_minutes=15,
            cook_time_minutes=20,
            difficulty=2,
            meal_type="Dinner",
            cuisine="Italian",
        )

        orchestrator = RecipeIngredientOrchestrator(
            recipe_generator=StaticRecipeGenerator(candidate),
            extraction_worker=IngredientExtractionWorker(),
            resolution_worker=IngredientResolutionWorker(
                catalog=build_default_catalog(),
                ambiguity_resolver=ScriptedAmbiguityResolver({"chicken": "chicken-breast", "cream": "heavy-cream"}),
            ),
            reconciliation_worker=RecipeReconciliationWorker(),
            validation_worker=RecipeValidationWorker(),
        )

        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            (root / "PantryChef" / "Resources").mkdir(parents=True)
            (root / "PantryChef" / "Resources" / "seed_recipes.json").write_text("[]\n", encoding="utf-8")
            runner = RecipeCampaignRunner(
                orchestrator=orchestrator,
                artifact_writer=ArtifactWriter(),
                promotion_store=IngredientPromotionStore(),
                root_dir=root / "runtime",
                accepted_root=root / "accepted",
                max_workers=1,
            )
            state = runner.run_campaign(
                CampaignSpec(
                    name="accepted-corpus-campaign",
                    dishes=[DishSpec(title="Creamy Garlic Chicken Pasta", cuisine="Italian", meal_type="Dinner", servings=4)],
                )
            )

            accepted_bundle = root / "accepted" / state.campaign_id / "seed_recipes.json"
            self.assertTrue(accepted_bundle.exists())

            restored_state = CampaignStore(root / "runtime" / state.campaign_id).load()
            self.assertIsInstance(restored_state.items[0].attempt_history[0], AttemptTrace)

            corpus_index = RecipeCorpusIndex.from_project_root(root, accepted_root=root / "accepted")
            self.assertEqual(corpus_index.recipe_count, 1)
            self.assertIn("duplicates existing recipe", corpus_index.duplicate_reason_for_title("Creamy Garlic Chicken Pasta"))

    def test_ingredient_focus_plan_targets_underrepresented_categories(self) -> None:
        entries = [
            CatalogEntry(item_id=f"produce-{index}", name=f"Produce {index}", category="Produce", aliases={f"Produce {index}": []}, quality_status="enriched")
            for index in range(18)
        ]
        entries.extend(
            CatalogEntry(item_id=f"dairy-{index}", name=f"Dairy {index}", category="Dairy", aliases={f"Dairy {index}": []}, quality_status="enriched")
            for index in range(8)
        )

        plan = _ingredient_focus_plan(entries, target_count=300, batch_size=24, attempt_number=0)

        self.assertEqual(sum(plan["category_targets"].values()), 24)
        self.assertNotIn("Produce", plan["focus_categories"])
        self.assertEqual(set(plan["focus_categories"]), set(plan["category_targets"].keys()))

    def test_catalog_entry_quality_issue_rejects_duplicates_and_generic_buckets(self) -> None:
        generic_bucket_entry = CatalogEntry(
            item_id="assorted-variety-mixed-nuts-deluxe",
            name="Assorted Variety Mixed Nuts Deluxe",
            category="Snacks",
            aliases={"Assorted Variety Mixed Nuts Deluxe": []},
            quality_status="enriched",
        )
        duplicate_entry = CatalogEntry(
            item_id="olive-oil",
            name="Olive Oil",
            category="Oils & Fats",
            aliases={"Olive Oil": []},
            quality_status="enriched",
        )

        self.assertEqual(
            _catalog_entry_quality_issue(
                generic_bucket_entry,
                existing_item_ids=set(),
                existing_names=set(),
                seen_generated_ids=set(),
                seen_generated_names=set(),
            ),
            "overly generic family bucket",
        )
        self.assertEqual(
            _catalog_entry_quality_issue(
                duplicate_entry,
                existing_item_ids={"olive-oil"},
                existing_names=set(),
                seen_generated_ids=set(),
                seen_generated_names=set(),
            ),
            "duplicate item id",
        )

    def test_catalog_entry_payload_preserves_explicit_structure(self) -> None:
        entry = _catalog_entry_from_payload(
            {
                "name": "Granulated Sugar",
                "category": "Baking Supplies",
                "aliases": ["white sugar"],
                "default_unit": "cup",
                "facet_definitions": [{"key": "variant", "options": ["granulated"]}],
                "default_facets": [{"key": "variant", "value": "granulated"}],
                "substitutes": [
                    {
                        "name": "Brown Sugar",
                        "rationale": "Adds a deeper molasses note.",
                        "facets": [{"key": "variant", "value": "brown"}],
                        "ratio": "1:1",
                        "tasteImpact": "Moderate",
                        "textureImpact": "Moderate",
                        "cookingImpact": "Moderate Adjustment",
                        "nutritionImpact": None,
                        "notes": "Adds a deeper molasses note.",
                        "dietary": [],
                    }
                ],
                "storage": {
                    "preferred": "pantry",
                    "pantry_days": 365,
                    "refrigerator_days": None,
                    "freezer_days": None,
                    "notes": "Keep dry.",
                },
                "rationale": "Common sweetener used in baking.",
            }
        )

        self.assertEqual(entry.item_id, "granulated-sugar")
        self.assertEqual(entry.name, "Granulated Sugar")
        self.assertIsNone(entry.default_quantity)
        self.assertEqual(entry.default_facets, [FacetSelection(key="variant", value="granulated")])
        self.assertTrue(any(definition.key == "variant" for definition in entry.facet_definitions))
        self.assertEqual(entry.aliases["Granulated Sugar"], [FacetSelection(key="variant", value="granulated")])
        self.assertEqual(entry.aliases["White Sugar"], [FacetSelection(key="variant", value="granulated")])
        self.assertEqual(entry.substitutes[0].item_id, "brown-sugar")
        self.assertEqual(entry.substitutes[0].facets, [FacetSelection(key="variant", value="brown")])
        self.assertEqual(entry.to_app_catalog_item_dict()["defaultStorage"], "Pantry")
        self.assertEqual(entry.to_app_catalog_item_dict()["freshnessByStorage"]["Pantry"], {"minDays": 274, "maxDays": 456})

    def test_catalog_entry_payload_builds_structured_substitution_metadata(self) -> None:
        entry = _catalog_entry_from_payload(
            {
                "name": "Chicken Broth",
                "category": "Canned & Jarred",
                "aliases": ["chicken stock"],
                "default_unit": "L",
                "facet_definitions": [{"key": "base", "options": ["chicken"]}],
                "default_facets": [{"key": "base", "value": "chicken"}],
                "substitutes": [
                    {
                        "name": "Vegetable Stock",
                        "rationale": "Neutral savory base.",
                        "facets": [{"key": "base", "value": "vegetable"}],
                        "ratio": "1:1",
                        "tasteImpact": "Moderate",
                        "textureImpact": "Moderate",
                        "cookingImpact": "Moderate Adjustment",
                        "nutritionImpact": None,
                        "notes": "Neutral savory base.",
                        "dietary": [],
                    },
                    {
                        "name": "Beef Broth",
                        "rationale": "Richer and darker flavor.",
                        "facets": [{"key": "base", "value": "beef"}],
                        "ratio": "1:1",
                        "tasteImpact": "Moderate",
                        "textureImpact": "Moderate",
                        "cookingImpact": "Moderate Adjustment",
                        "nutritionImpact": None,
                        "notes": "Richer and darker flavor.",
                        "dietary": [],
                    },
                ],
                "storage": {
                    "preferred": "pantry",
                    "pantry_days": 180,
                    "refrigerator_days": 5,
                    "freezer_days": 60,
                    "notes": "Refrigerate after opening.",
                },
                "rationale": "Savory cooking liquid.",
            }
        )

        self.assertEqual(entry.item_id, "chicken-broth")
        self.assertEqual(entry.default_facets, [FacetSelection(key="base", value="chicken")])
        self.assertEqual(
            entry.substitutes[0],
            IngredientReference(
                item_id="vegetable-stock",
                name="Vegetable Stock",
                rationale="Neutral savory base.",
                facets=[FacetSelection(key="base", value="vegetable")],
                ratio="1:1",
                taste_impact="Moderate",
                texture_impact="Moderate",
                cooking_impact="Moderate Adjustment",
                nutrition_impact=None,
                notes="Neutral savory base.",
                dietary=[],
            ),
        )
        self.assertEqual(entry.to_app_catalog_item_dict()["substitutions"][1]["substituteFacets"], [{"key": "base", "value": "beef"}])

    def test_catalog_merge_preserves_structured_metadata(self) -> None:
        catalog = build_empty_default_catalog()
        catalog.upsert_entries(
            [
                CatalogEntry(
                    item_id="fish-sauce",
                    name="Fish Sauce",
                    category="Condiments & Sauces",
                    aliases={"Fish Sauce": []},
                    quality_status="seed",
                    provenance=["seed"],
                )
            ]
        )

        catalog.upsert_entries(
            [
                CatalogEntry(
                    item_id="fish-sauce",
                    name="Fish Sauce",
                    category="Condiments & Sauces",
                    aliases={"nam pla": [FacetSelection(key="style", value="thai")]},
                    default_unit="tsp",
                    default_quantity=150.0,
                    facet_definitions=[FacetDefinition(key="style", options=["thai"])],
                    default_facets=[FacetSelection(key="style", value="thai")],
                    unit_overrides={"style": {"thai": "tbsp"}},
                    substitutes=[IngredientReference(item_id="soy-sauce", name="Soy Sauce", rationale="Closest pantry substitute.")],
                    storage=IngredientStorage(
                        preferred="pantry",
                        pantry_days=365,
                        refrigerator_days=30,
                        freezer_days=None,
                        notes="Refrigerate after opening.",
                    ),
                    freshness_by_storage={"pantry": FreshnessRange(min_days=180, max_days=365)},
                    quality_status="enriched",
                    provenance=["ingredient_enrichment"],
                )
            ]
        )

        merged = catalog.entries()[0]
        self.assertEqual(merged.default_unit, "tsp")
        self.assertEqual(merged.default_quantity, 150.0)
        self.assertEqual(merged.facet_definitions, [FacetDefinition(key="style", options=["thai"])])
        self.assertEqual(merged.default_facets, [FacetSelection(key="style", value="thai")])
        self.assertEqual(merged.unit_overrides, {"style": {"thai": "tbsp"}})
        self.assertEqual(merged.substitutes, [IngredientReference(item_id="soy-sauce", name="Soy Sauce", rationale="Closest pantry substitute.", facets=[], ratio="1:1", taste_impact="Moderate", texture_impact="Moderate", cooking_impact="Moderate Adjustment", nutrition_impact=None, notes="Closest pantry substitute.", dietary=[])])
        self.assertEqual(merged.storage, IngredientStorage(preferred="pantry", pantry_days=365, refrigerator_days=30, freezer_days=None, notes="Refrigerate after opening."))
        self.assertEqual(merged.freshness_by_storage, {"pantry": FreshnessRange(min_days=180, max_days=365)})
        self.assertIn("Fish Sauce", merged.aliases)
        self.assertIn("Nam Pla", merged.aliases)
        self.assertEqual(merged.quality_status, "enriched")

    def test_plan_unique_recipe_batch_accumulates_unique_dishes(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            (root / "PantryChef" / "Resources").mkdir(parents=True)
            (root / "PantryChef" / "Resources" / "seed_recipes.json").write_text(
                json.dumps(
                    [
                        {
                            "title": "Mediterranean Chickpea Salad with Canned Olives",
                            "description": "Existing seed recipe.",
                            "ingredients": [{"name": "chickpeas"}],
                            "steps": [{"instruction": "Mix and serve."}],
                            "servings": 2,
                            "prepTimeMinutes": 10,
                            "cookTimeMinutes": 0,
                            "difficulty": 1,
                            "mealType": "Lunch",
                            "cuisine": "Mediterranean",
                        }
                    ],
                    indent=2,
                )
                + "\n",
                encoding="utf-8",
            )

            corpus_index = RecipeCorpusIndex.from_project_root(root)
            plan = _plan_unique_recipe_batch(
                client=FakeChatClient(
                    [
                        _recipe_batch_payload(
                            "Mediterranean Chickpea Salad with Canned Olives",
                            "Thai Peanut Noodles",
                        ),
                        _recipe_batch_payload(
                            "Italian White Bean Soup",
                            "Korean Gochujang Tofu Bowl",
                        ),
                    ]
                ),
                model=None,
                target_batch_size=3,
                corpus_index=corpus_index,
                underrepresented_cuisines=["Thai", "Korean", "Italian"],
                underrepresented_meal_types=["Dinner"],
                remaining_target=900,
                attempt_number=0,
            )

            self.assertEqual(plan["planner_attempts"], 2)
            self.assertEqual(len(plan["spec"].dishes), 3)
            self.assertEqual(
                [dish.title for dish in plan["spec"].dishes],
                [
                    "Thai Peanut Noodles",
                    "Italian White Bean Soup",
                    "Korean Gochujang Tofu Bowl",
                ],
            )
            self.assertEqual(plan["planner_batches"][0]["added_unique_dishes"], 1)
            self.assertEqual(plan["planner_batches"][1]["added_unique_dishes"], 2)


if __name__ == "__main__":
    unittest.main()