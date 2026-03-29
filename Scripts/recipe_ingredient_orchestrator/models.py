from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4


ARTIFACT_KIND = "recipe-ingredient-pipeline-run"
ARTIFACT_VERSION = "1.0"


def make_identifier(prefix: str) -> str:
    return f"{prefix}_{uuid4().hex}"


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def slugify(value: str) -> str:
    cleaned = "".join(character.lower() if character.isalnum() else "-" for character in value.strip())
    while "--" in cleaned:
        cleaned = cleaned.replace("--", "-")
    return cleaned.strip("-") or "item"


@dataclass(frozen=True)
class FacetSelection:
    key: str
    value: str


@dataclass(frozen=True)
class FacetDefinition:
    key: str
    options: list[str]


@dataclass(frozen=True)
class FreshnessRange:
    min_days: int
    max_days: int


@dataclass(frozen=True)
class IngredientReference:
    item_id: str
    name: str
    rationale: str | None = None
    facets: list[FacetSelection] = field(default_factory=list)
    ratio: str | None = None
    taste_impact: str | None = None
    texture_impact: str | None = None
    cooking_impact: str | None = None
    nutrition_impact: str | None = None
    notes: str | None = None
    dietary: list[str] = field(default_factory=list)

    def to_app_substitution_dict(self) -> dict[str, Any]:
        return {
            "substituteItemID": self.item_id,
            "substituteFacets": [asdict(facet) for facet in self.facets],
            "ratio": self.ratio or "1:1",
            "tasteImpact": self.taste_impact or "Moderate",
            "textureImpact": self.texture_impact or "Moderate",
            "cookingImpact": self.cooking_impact or "Moderate Adjustment",
            "nutritionImpact": self.nutrition_impact,
            "notes": self.notes or self.rationale,
            "dietary": list(self.dietary),
        }


@dataclass(frozen=True)
class IngredientStorage:
    preferred: str | None = None
    pantry_days: int | None = None
    refrigerator_days: int | None = None
    freezer_days: int | None = None
    notes: str | None = None


@dataclass(frozen=True)
class DishSpec:
    title: str
    cuisine: str | None = None
    meal_type: str | None = None
    servings: int = 4
    goals: list[str] = field(default_factory=list)
    pantry_focus: list[str] = field(default_factory=list)
    avoid_titles: list[str] = field(default_factory=list)
    notes: str | None = None
    dish_id: str = field(default_factory=lambda: make_identifier("dish"))


@dataclass(frozen=True)
class RecipeIngredientInput:
    name: str
    quantity: float
    unit: str | None
    category: str
    is_optional: bool = False
    notes: str | None = None


@dataclass(frozen=True)
class RecipeStepInput:
    step_number: int
    instruction: str
    timer_minutes: int | None = None
    estimated_duration_seconds: int | None = None
    tip: str | None = None


@dataclass(frozen=True)
class RecipeCandidate:
    title: str
    description: str | None
    ingredients: list[RecipeIngredientInput]
    steps: list[RecipeStepInput]
    servings: int
    prep_time_minutes: int | None
    cook_time_minutes: int | None
    difficulty: int
    dietary_tags: list[str] = field(default_factory=list)
    meal_type: str | None = None
    cuisine: str | None = None
    source: str = "aiGenerated"
    recipe_id: str = field(default_factory=lambda: make_identifier("recipe"))


@dataclass(frozen=True)
class IngredientMention:
    mention_id: str
    raw_name: str
    quantity: float
    unit: str | None
    category: str
    is_optional: bool
    notes: str | None = None


@dataclass(frozen=True)
class CatalogEntry:
    item_id: str
    name: str
    category: str
    aliases: dict[str, list[FacetSelection]]
    default_unit: str | None = None
    default_quantity: float | None = None
    facet_definitions: list[FacetDefinition] = field(default_factory=list)
    default_facets: list[FacetSelection] = field(default_factory=list)
    unit_overrides: dict[str, dict[str, str]] = field(default_factory=dict)
    notes: str | None = None
    substitutes: list[IngredientReference] = field(default_factory=list)
    storage: IngredientStorage | None = None
    freshness_by_storage: dict[str, FreshnessRange] = field(default_factory=dict)
    quality_status: str = "seed"
    provenance: list[str] = field(default_factory=list)
    evidence_count: int = 0
    recipe_reference_count: int = 0
    first_seen_at: str | None = None
    last_seen_at: str | None = None

    def app_default_storage(self) -> str:
        preferred = None if self.storage is None else self.storage.preferred
        if preferred == "refrigerator":
            return "Refrigerated"
        if preferred == "freezer":
            return "Frozen"
        return "Pantry"

    def app_freshness_by_storage(self) -> dict[str, dict[str, int]]:
        freshness = self.freshness_by_storage or self._freshness_from_storage_days()
        return {
            self._app_storage_name(storage_key): {
                "minDays": value.min_days,
                "maxDays": value.max_days,
            }
            for storage_key, value in freshness.items()
        }

    def to_app_catalog_item_dict(self) -> dict[str, Any]:
        return {
            "id": self.item_id,
            "name": self.name,
            "category": self.category,
            "defaultUnit": self.default_unit,
            "defaultQuantity": self.default_quantity,
            "defaultStorage": self.app_default_storage(),
            "aliases": sorted(self.aliases.keys()),
            "facets": [asdict(definition) for definition in self.facet_definitions],
            "defaultSelections": [asdict(facet) for facet in self.default_facets],
            "substitutions": [reference.to_app_substitution_dict() for reference in self.substitutes],
            "unitOverrides": dict(self.unit_overrides),
            "freshnessByStorage": self.app_freshness_by_storage(),
            "notes": self.notes,
            "qualityStatus": self.quality_status,
            "provenance": list(self.provenance),
        }

    def _freshness_from_storage_days(self) -> dict[str, FreshnessRange]:
        if self.storage is None:
            return {}

        freshness: dict[str, FreshnessRange] = {}
        for storage_key, days in {
            "pantry": self.storage.pantry_days,
            "refrigerator": self.storage.refrigerator_days,
            "freezer": self.storage.freezer_days,
        }.items():
            if days is None:
                continue
            minimum = max(1, int(round(days * 0.75)))
            maximum = max(minimum, int(round(days * 1.25)))
            freshness[storage_key] = FreshnessRange(min_days=minimum, max_days=maximum)
        return freshness

    @staticmethod
    def _app_storage_name(storage_key: str) -> str:
        if storage_key == "refrigerator":
            return "Refrigerated"
        if storage_key == "freezer":
            return "Frozen"
        return "Pantry"


@dataclass(frozen=True)
class IngredientEnrichmentDecision:
    raw_name: str
    action: str
    rationale: str
    canonical_name: str | None = None
    category: str | None = None
    aliases: list[str] = field(default_factory=list)
    default_unit: str | None = None
    default_quantity: float | None = None
    facet_definitions: list[FacetDefinition] = field(default_factory=list)
    default_facets: list[FacetSelection] = field(default_factory=list)
    unit_overrides: dict[str, dict[str, str]] = field(default_factory=dict)
    substitutes: list[IngredientReference] = field(default_factory=list)
    storage: IngredientStorage | None = None
    freshness_by_storage: dict[str, FreshnessRange] = field(default_factory=dict)
    quality_status: str = "enriched"


@dataclass(frozen=True)
class IngredientEnrichmentReport:
    decisions: list[IngredientEnrichmentDecision] = field(default_factory=list)
    generated_entries: list[CatalogEntry] = field(default_factory=list)
    ignored_mentions: dict[str, str] = field(default_factory=dict)

    @property
    def has_effect(self) -> bool:
        return bool(self.generated_entries or self.ignored_mentions)


@dataclass(frozen=True)
class IngredientCandidate:
    candidate_id: str
    catalog_item_id: str
    display_name: str
    score: float
    rationale: str
    facets: list[FacetSelection] = field(default_factory=list)
    catalog_entry: CatalogEntry | None = None


@dataclass(frozen=True)
class ResolutionRecord:
    mention_id: str
    status: str
    selected_candidate_id: str | None
    selected_catalog_item_id: str | None
    confidence: float
    rationale: str
    candidates: list[IngredientCandidate] = field(default_factory=list)


@dataclass(frozen=True)
class ResolvedIngredient:
    mention_id: str
    raw_name: str
    quantity: float
    unit: str | None
    category: str
    is_optional: bool
    notes: str | None
    status: str
    catalog_item_id: str | None
    display_name: str
    confidence: float
    rationale: str
    facets: list[FacetSelection] = field(default_factory=list)
    ingredient_record: CatalogEntry | None = None


@dataclass(frozen=True)
class ValidationReport:
    is_valid: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    error_codes: list[str] = field(default_factory=list)
    warning_codes: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class ReviewIssue:
    code: str
    severity: str
    message: str


@dataclass(frozen=True)
class RecipeReviewReport:
    status: str
    reviewer: str
    rationale: str
    issues: list[ReviewIssue] = field(default_factory=list)
    revision_instructions: list[str] = field(default_factory=list)
    retryable: bool = False


@dataclass(frozen=True)
class AttemptTrace:
    attempt_number: int
    status: str
    failure_code: str | None = None
    message: str | None = None
    validation_error_codes: list[str] = field(default_factory=list)
    review_status: str | None = None
    review_issue_codes: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class ResolvedRecipeArtifact:
    recipe_id: str
    title: str
    description: str | None
    ingredients: list[ResolvedIngredient]
    steps: list[RecipeStepInput]
    servings: int
    prep_time_minutes: int | None
    cook_time_minutes: int | None
    difficulty: int
    dietary_tags: list[str] = field(default_factory=list)
    meal_type: str | None = None
    cuisine: str | None = None
    source: str = "aiGenerated"

    def unresolved_ingredients(self) -> list[ResolvedIngredient]:
        return [ingredient for ingredient in self.ingredients if ingredient.status == "unresolved"]

    def resolved_ingredients(self) -> list[ResolvedIngredient]:
        return [ingredient for ingredient in self.ingredients if ingredient.status == "resolved"]

    def ignored_ingredients(self) -> list[ResolvedIngredient]:
        return [ingredient for ingredient in self.ingredients if ingredient.status == "ignored"]

    def to_app_recipe_dict(self) -> dict[str, Any]:
        return {
            "title": self.title,
            "description": self.description,
            "cuisine": self.cuisine,
            "mealType": self.meal_type,
            "difficulty": self.difficulty,
            "servings": self.servings,
            "prepTimeMinutes": self.prep_time_minutes,
            "cookTimeMinutes": self.cook_time_minutes,
            "dietaryTags": self.dietary_tags,
            "source": self.source,
            "ingredients": [
                {
                    "name": ingredient.raw_name,
                    "quantity": ingredient.quantity,
                    "unit": ingredient.unit,
                    "category": ingredient.category,
                    "isOptional": ingredient.is_optional,
                    "notes": ingredient.notes,
                    "catalogItemID": ingredient.catalog_item_id,
                    "facets": [asdict(facet) for facet in ingredient.facets],
                    "ingredientRecord": None if ingredient.ingredient_record is None else asdict(ingredient.ingredient_record),
                }
                for ingredient in self.ingredients
            ],
            "steps": [
                {
                    "stepNumber": step.step_number,
                    "instruction": step.instruction,
                    "timerMinutes": step.timer_minutes,
                    "tip": step.tip,
                    "estimatedDurationSeconds": step.estimated_duration_seconds,
                    "tasks": [],
                }
                for step in self.steps
            ],
        }

    def to_seed_recipe_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "title": self.title,
            "description": self.description,
            "cuisine": self.cuisine,
            "mealType": self.meal_type,
            "difficulty": self.difficulty,
            "servings": self.servings,
            "prepTimeMinutes": self.prep_time_minutes,
            "cookTimeMinutes": self.cook_time_minutes,
            "dietaryTags": list(self.dietary_tags),
            "ingredients": [
                {
                    "name": ingredient.raw_name,
                    "quantity": ingredient.quantity,
                    "unit": ingredient.unit,
                    "category": ingredient.category,
                    "isOptional": ingredient.is_optional,
                }
                for ingredient in self.ingredients
            ],
            "steps": [
                {
                    "stepNumber": step.step_number,
                    "instruction": step.instruction,
                    "timerMinutes": step.timer_minutes,
                    "estimatedDurationSeconds": step.estimated_duration_seconds,
                }
                for step in self.steps
            ],
        }
        return payload


@dataclass(frozen=True)
class PipelineRun:
    spec: DishSpec
    recipe_candidate: RecipeCandidate
    ingredient_mentions: list[IngredientMention]
    resolution_records: list[ResolutionRecord]
    resolved_recipe: ResolvedRecipeArtifact
    validation: ValidationReport
    review: RecipeReviewReport | None = None
    ingredient_enrichment_decisions: list[IngredientEnrichmentDecision] = field(default_factory=list)
    attempt_history: list[AttemptTrace] = field(default_factory=list)
    generation_attempts: int = 1
    failure_code: str | None = None
    run_id: str = field(default_factory=lambda: make_identifier("run"))
    started_at: str = field(default_factory=utc_now_iso)
    generated_at: str = field(default_factory=utc_now_iso)
    duration_seconds: float = 0.0
    kind: str = ARTIFACT_KIND
    version: str = ARTIFACT_VERSION

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["exportedRecipe"] = self.resolved_recipe.to_app_recipe_dict()
        return payload


@dataclass(frozen=True)
class CampaignSpec:
    dishes: list[DishSpec]
    name: str | None = None
    max_concurrency: int | None = None
    campaign_id: str = field(default_factory=lambda: make_identifier("campaign"))
    created_at: str = field(default_factory=utc_now_iso)


@dataclass
class CampaignItemState:
    spec: DishSpec
    status: str = "pending"
    attempts: int = 0
    run_id: str | None = None
    run_dir: str | None = None
    pipeline_run_path: str | None = None
    exported_recipe_path: str | None = None
    app_seed_recipe_path: str | None = None
    promoted_item_ids: list[str] = field(default_factory=list)
    quarantine_path: str | None = None
    duration_seconds: float | None = None
    resolved_ingredient_count: int = 0
    unresolved_ingredient_count: int = 0
    unresolved_ingredient_names: list[str] = field(default_factory=list)
    generation_attempts: int = 0
    failure_code: str | None = None
    review_status: str | None = None
    review_issue_count: int = 0
    attempt_history: list[AttemptTrace] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    completed_at: str | None = None


@dataclass
class CampaignState:
    campaign_id: str
    name: str | None
    created_at: str
    updated_at: str
    status: str
    items: list[CampaignItemState]


@dataclass(frozen=True)
class IngredientPromotionSummary:
    promoted_item_ids: list[str] = field(default_factory=list)
    promoted_paths: list[str] = field(default_factory=list)
    quarantine_path: str | None = None