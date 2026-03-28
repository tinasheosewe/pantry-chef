from __future__ import annotations

import time
from pathlib import Path

from .corpus import RecipeCorpusIndex, normalize_text
from .config import OrchestratorConfig
from .logging_utils import get_logger
from .models import AttemptTrace, DishSpec, PipelineRun, RecipeCandidate, RecipeReviewReport, ResolvedRecipeArtifact, ValidationReport, utc_now_iso
from .openai_client import OpenAIChatClient, OpenAIRequestError
from .services import (
    DeterministicRecipeReviewer,
    DemoRecipeGenerator,
    DuplicateRecipeError,
    HeuristicAmbiguityResolver,
    IngredientEnricher,
    NoOpIngredientEnricher,
    OpenAIRecipeReviewer,
    OpenAIAmbiguityResolver,
    OpenAIIngredientEnricher,
    OpenAIRecipeGenerator,
    RecipeGenerator,
    RecipeReviewer,
    build_empty_catalog,
    build_placeholder_catalog_entries,
    build_default_catalog,
)


logger = get_logger("pipeline")
from .workers import (
    IngredientExtractionWorker,
    IngredientResolutionWorker,
    RecipeReconciliationWorker,
    RecipeValidationWorker,
)


class DishExecutionError(RuntimeError):
    def __init__(self, message: str, failure_code: str, attempt_history: list[AttemptTrace]) -> None:
        super().__init__(message)
        self.failure_code = failure_code
        self.attempt_history = attempt_history


class RecipeIngredientOrchestrator:
    def __init__(
        self,
        recipe_generator: RecipeGenerator,
        extraction_worker: IngredientExtractionWorker,
        resolution_worker: IngredientResolutionWorker,
        reconciliation_worker: RecipeReconciliationWorker,
        validation_worker: RecipeValidationWorker,
        review_worker: RecipeReviewer | None = None,
        ingredient_enricher: IngredientEnricher | None = None,
        max_attempts: int = 3,
        max_resolution_cycles: int = 2,
    ) -> None:
        self._recipe_generator = recipe_generator
        self._extraction_worker = extraction_worker
        self._resolution_worker = resolution_worker
        self._reconciliation_worker = reconciliation_worker
        self._validation_worker = validation_worker
        self._review_worker = review_worker or DeterministicRecipeReviewer()
        self._deterministic_reviewer = DeterministicRecipeReviewer()
        self._ingredient_enricher = ingredient_enricher or NoOpIngredientEnricher()
        self._max_attempts = max(1, max_attempts)
        self._max_resolution_cycles = max(1, max_resolution_cycles)

    def run(self, spec: DishSpec) -> PipelineRun:
        logger.info("Starting dish run title=%s", spec.title)
        started_at = utc_now_iso()
        started_monotonic = time.monotonic()
        revision_feedback: list[str] = []
        attempt_history: list[AttemptTrace] = []
        last_failure_code = "dish_attempts_exhausted"
        last_exception: Exception | None = None
        last_pipeline_run: PipelineRun | None = None

        for attempt_number in range(1, self._max_attempts + 1):
            try:
                logger.info("Dish attempt started title=%s attempt=%s/%s", spec.title, attempt_number, self._max_attempts)
                recipe_candidate = self._recipe_generator.generate(spec, revision_feedback=revision_feedback)
                mentions = self._extraction_worker.extract(recipe_candidate)
                resolved_ingredients, resolution_records, enrichment_decisions = self._resolve_with_enrichment(
                    spec,
                    recipe_candidate,
                    mentions,
                )
                resolved_recipe = self._reconciliation_worker.build(recipe_candidate, resolved_ingredients)
                recipe_candidate, resolved_recipe = _normalize_recipe_metadata(spec, recipe_candidate, resolved_recipe)
                validation = _merge_validation_reports(
                    self._validation_worker.validate(resolved_recipe),
                    _spec_alignment_validation(spec, recipe_candidate),
                )
                if validation.error_codes:
                    review = self._deterministic_reviewer.review(spec, recipe_candidate, resolved_recipe, validation, attempt_number)
                else:
                    review = self._review_worker.review(spec, recipe_candidate, resolved_recipe, validation, attempt_number)
                failure_code = _failure_code_for(validation, review)

                if failure_code is None:
                    logger.info("Dish accepted title=%s attempt=%s", spec.title, attempt_number)
                    attempt_history.append(
                        AttemptTrace(
                            attempt_number=attempt_number,
                            status="accepted",
                            review_status=review.status,
                            review_issue_codes=[issue.code for issue in review.issues],
                        )
                    )
                    return PipelineRun(
                        spec=spec,
                        recipe_candidate=recipe_candidate,
                        ingredient_mentions=mentions,
                        resolution_records=resolution_records,
                        resolved_recipe=resolved_recipe,
                        validation=validation,
                        review=review,
                        ingredient_enrichment_decisions=enrichment_decisions,
                        attempt_history=attempt_history,
                        generation_attempts=attempt_number,
                        started_at=started_at,
                        generated_at=utc_now_iso(),
                        duration_seconds=round(time.monotonic() - started_monotonic, 3),
                    )

                attempt_history.append(
                    AttemptTrace(
                        attempt_number=attempt_number,
                        status="retrying" if attempt_number < self._max_attempts and _is_retryable_failure(validation, review) else "failed",
                        failure_code=failure_code,
                        message=_failure_message(validation, review),
                        validation_error_codes=list(validation.error_codes),
                        review_status=review.status,
                        review_issue_codes=[issue.code for issue in review.issues],
                    )
                )
                logger.warning("Dish attempt failed title=%s attempt=%s failure_code=%s", spec.title, attempt_number, failure_code)
                last_failure_code = failure_code
                last_pipeline_run = PipelineRun(
                    spec=spec,
                    recipe_candidate=recipe_candidate,
                    ingredient_mentions=mentions,
                    resolution_records=resolution_records,
                    resolved_recipe=resolved_recipe,
                    validation=validation,
                    review=review,
                    ingredient_enrichment_decisions=enrichment_decisions,
                    attempt_history=list(attempt_history),
                    generation_attempts=attempt_number,
                    failure_code=failure_code,
                    started_at=started_at,
                    generated_at=utc_now_iso(),
                    duration_seconds=round(time.monotonic() - started_monotonic, 3),
                )
                if attempt_number >= self._max_attempts or not _is_retryable_failure(validation, review):
                    return last_pipeline_run

                revision_feedback = _revision_feedback(validation, review)
            except Exception as exc:
                failure_code = _failure_code_for_exception(exc)
                logger.exception("Dish attempt crashed title=%s attempt=%s failure_code=%s", spec.title, attempt_number, failure_code)
                attempt_history.append(
                    AttemptTrace(
                        attempt_number=attempt_number,
                        status="retrying" if attempt_number < self._max_attempts else "failed",
                        failure_code=failure_code,
                        message=str(exc),
                    )
                )
                last_failure_code = failure_code
                last_exception = exc
                if attempt_number >= self._max_attempts:
                    raise DishExecutionError(str(exc), failure_code, attempt_history) from exc
                revision_feedback = [f"Previous attempt failed before acceptance: {exc}"]

        if last_pipeline_run is not None:
            logger.warning("Returning failed dish result title=%s failure_code=%s", spec.title, last_failure_code)
            return last_pipeline_run
        if last_exception is not None:
            raise DishExecutionError(str(last_exception), last_failure_code, attempt_history) from last_exception
        raise DishExecutionError("Dish generation failed without a recoverable result.", last_failure_code, attempt_history)

    def _resolve_with_enrichment(
        self,
        spec: DishSpec,
        recipe_candidate: RecipeCandidate,
        mentions: list,
    ) -> tuple[list, list, list]:
        ignored_mentions: dict[str, str] = {}
        enrichment_decisions = []

        for cycle_number in range(1, self._max_resolution_cycles + 1):
            logger.info(
                "Ingredient resolution cycle title=%s cycle=%s/%s",
                spec.title,
                cycle_number,
                self._max_resolution_cycles,
            )
            resolved_ingredients, resolution_records = self._resolution_worker.resolve(
                spec,
                recipe_candidate,
                mentions,
                ignored_mentions=ignored_mentions,
                allow_placeholder_resolution=False,
            )
            unresolved_mentions = [
                mention
                for mention, record in zip(mentions, resolution_records)
                if record.status == "unresolved"
            ]
            if not unresolved_mentions:
                return resolved_ingredients, resolution_records, enrichment_decisions

            if cycle_number >= self._max_resolution_cycles:
                placeholder_entries = build_placeholder_catalog_entries(unresolved_mentions)
                self._resolution_worker.upsert_entries(placeholder_entries)
                logger.warning(
                    "Ingredient resolution exhausted; provisioning placeholders title=%s unresolved=%s",
                    spec.title,
                    [mention.raw_name for mention in unresolved_mentions],
                )
                return self._resolution_worker.resolve(
                    spec,
                    recipe_candidate,
                    mentions,
                    ignored_mentions=ignored_mentions,
                    allow_placeholder_resolution=True,
                ) + (enrichment_decisions,)

            enrichment_report = self._ingredient_enricher.enrich(spec, recipe_candidate, unresolved_mentions)
            enrichment_decisions.extend(enrichment_report.decisions)
            if enrichment_report.generated_entries:
                self._resolution_worker.upsert_entries(enrichment_report.generated_entries)
                logger.info(
                    "Ingredient enrichment generated entries title=%s entries=%s",
                    spec.title,
                    [entry.name for entry in enrichment_report.generated_entries],
                )
            if enrichment_report.ignored_mentions:
                ignored_mentions.update(enrichment_report.ignored_mentions)
                logger.info(
                    "Ingredient enrichment ignored mentions title=%s mentions=%s",
                    spec.title,
                    sorted(enrichment_report.ignored_mentions.keys()),
                )
            if not enrichment_report.has_effect:
                placeholder_entries = build_placeholder_catalog_entries(unresolved_mentions)
                self._resolution_worker.upsert_entries(placeholder_entries)
                logger.warning(
                    "Ingredient enrichment produced no new entries; provisioning placeholders title=%s unresolved=%s",
                    spec.title,
                    [mention.raw_name for mention in unresolved_mentions],
                )
                return self._resolution_worker.resolve(
                    spec,
                    recipe_candidate,
                    mentions,
                    ignored_mentions=ignored_mentions,
                    allow_placeholder_resolution=True,
                ) + (enrichment_decisions,)

        return [], [], enrichment_decisions


def build_demo_orchestrator(include_seed_catalog: bool = True) -> RecipeIngredientOrchestrator:
    catalog = build_default_catalog(include_seed_entries=include_seed_catalog)
    return RecipeIngredientOrchestrator(
        recipe_generator=DemoRecipeGenerator(),
        extraction_worker=IngredientExtractionWorker(),
        resolution_worker=IngredientResolutionWorker(
            catalog=catalog,
            ambiguity_resolver=HeuristicAmbiguityResolver(),
        ),
        reconciliation_worker=RecipeReconciliationWorker(),
        validation_worker=RecipeValidationWorker(),
        review_worker=DeterministicRecipeReviewer(),
        ingredient_enricher=NoOpIngredientEnricher(),
    )


def build_production_orchestrator(
    config: OrchestratorConfig | None = None,
    *,
    include_seed_catalog: bool = True,
) -> RecipeIngredientOrchestrator:
    resolved_config = config or OrchestratorConfig.from_env()
    resolved_config.require_openai_api_key()

    client = OpenAIChatClient(resolved_config)
    catalog = build_default_catalog(
        storage_dir=resolved_config.output_root / "ingredient_catalog",
        include_seed_entries=include_seed_catalog,
    ) if include_seed_catalog else build_empty_catalog(storage_dir=resolved_config.output_root / "ingredient_catalog")
    project_root = Path(__file__).resolve().parents[2]
    corpus_index = RecipeCorpusIndex.from_project_root(
        project_root,
        output_root=resolved_config.output_root,
        accepted_root=resolved_config.accepted_root,
    )

    return RecipeIngredientOrchestrator(
        recipe_generator=OpenAIRecipeGenerator(
            client=client,
            corpus_index=corpus_index,
            model=resolved_config.generation_model,
        ),
        extraction_worker=IngredientExtractionWorker(),
        resolution_worker=IngredientResolutionWorker(
            catalog=catalog,
            ambiguity_resolver=OpenAIAmbiguityResolver(
                client=client,
                model=resolved_config.ambiguity_model,
            ),
            auto_accept_score=resolved_config.auto_accept_score,
            auto_accept_margin=resolved_config.auto_accept_margin,
        ),
        reconciliation_worker=RecipeReconciliationWorker(),
        validation_worker=RecipeValidationWorker(),
        review_worker=OpenAIRecipeReviewer(client=client, model=resolved_config.review_model),
        ingredient_enricher=OpenAIIngredientEnricher(client=client, model=resolved_config.ingredient_model),
        max_attempts=resolved_config.max_dish_attempts,
        max_resolution_cycles=resolved_config.max_resolution_cycles,
    )


def _failure_code_for(validation, review: RecipeReviewReport) -> str | None:
    if validation.error_codes:
        if "requested_title_mismatch" in validation.error_codes:
            return "dish_alignment_failed"
        if "unresolved_ingredients" in validation.error_codes:
            return "ingredient_resolution_failed"
        return "recipe_validation_failed"
    if review.status == "revise":
        return "semantic_review_revision"
    if review.status == "rejected":
        return "semantic_review_rejected"
    return None


def _is_retryable_failure(validation, review: RecipeReviewReport) -> bool:
    if validation.error_codes:
        if "unresolved_ingredients" in validation.error_codes:
            return False
        return True
    return review.status in {"revise", "rejected"}


def _revision_feedback(validation, review: RecipeReviewReport) -> list[str]:
    feedback = list(review.revision_instructions)
    feedback.extend(f"Fix validation issue: {message}" for message in validation.errors)
    if not feedback and review.rationale:
        feedback.append(review.rationale)
    return feedback


def _failure_message(validation, review: RecipeReviewReport) -> str:
    messages = [issue.message for issue in review.issues]
    messages.extend(validation.errors)
    if messages:
        return "; ".join(messages)
    return review.rationale


def _failure_code_for_exception(exc: Exception) -> str:
    if isinstance(exc, OpenAIRequestError):
        return "openai_request_failed"
    if isinstance(exc, DuplicateRecipeError):
        return "duplicate_recipe_generated"
    return "pipeline_execution_failed"


_NON_VEGETARIAN_ITEM_IDS = {
    "bacon",
    "chicken-breast",
    "chicken-thigh",
    "duck-leg",
    "fish-fillets",
    "fish-stock",
    "ground-beef",
    "pork",
    "salmon",
    "shrimp",
    "white-fish",
}

_NON_VEGAN_ITEM_IDS = _NON_VEGETARIAN_ITEM_IDS | {
    "butter",
    "cheddar",
    "duck-fat",
    "eggs",
    "heavy-cream",
    "milk",
}

_GLUTEN_ITEM_IDS = {
    "all-purpose-flour",
    "bread",
    "breadcrumbs",
    "pasta",
    "puff-pastry",
}


def _normalize_recipe_metadata(
    spec: DishSpec,
    candidate: RecipeCandidate,
    resolved_recipe: ResolvedRecipeArtifact,
) -> tuple[RecipeCandidate, ResolvedRecipeArtifact]:
    dietary_tags = _normalized_dietary_tags_for_resolved_recipe(resolved_recipe)
    title = candidate.title
    cuisine = candidate.cuisine or spec.cuisine
    meal_type = candidate.meal_type or spec.meal_type

    normalized_candidate = RecipeCandidate(
        title=title,
        description=candidate.description,
        ingredients=candidate.ingredients,
        steps=candidate.steps,
        servings=candidate.servings,
        prep_time_minutes=candidate.prep_time_minutes,
        cook_time_minutes=candidate.cook_time_minutes,
        difficulty=candidate.difficulty,
        dietary_tags=dietary_tags,
        meal_type=meal_type,
        cuisine=cuisine,
        source=candidate.source,
        recipe_id=candidate.recipe_id,
    )
    normalized_resolved = ResolvedRecipeArtifact(
        recipe_id=resolved_recipe.recipe_id,
        title=title,
        description=resolved_recipe.description,
        ingredients=resolved_recipe.ingredients,
        steps=resolved_recipe.steps,
        servings=resolved_recipe.servings,
        prep_time_minutes=resolved_recipe.prep_time_minutes,
        cook_time_minutes=resolved_recipe.cook_time_minutes,
        difficulty=resolved_recipe.difficulty,
        dietary_tags=dietary_tags,
        meal_type=meal_type,
        cuisine=cuisine,
        source=resolved_recipe.source,
    )
    return normalized_candidate, normalized_resolved


def _spec_alignment_validation(spec: DishSpec, candidate: RecipeCandidate) -> ValidationReport:
    errors: list[str] = []
    warnings: list[str] = []
    error_codes: list[str] = []
    warning_codes: list[str] = []

    if normalize_text(candidate.title) != normalize_text(spec.title):
        errors.append(
            f"Generated title '{candidate.title}' does not match requested dish title '{spec.title}'."
        )
        error_codes.append("requested_title_mismatch")

    if spec.cuisine and candidate.cuisine and normalize_text(candidate.cuisine) != normalize_text(spec.cuisine):
        warnings.append(
            f"Generated cuisine '{candidate.cuisine}' differs from requested cuisine '{spec.cuisine}'."
        )
        warning_codes.append("requested_cuisine_mismatch")

    if spec.meal_type and candidate.meal_type and normalize_text(candidate.meal_type) != normalize_text(spec.meal_type):
        warnings.append(
            f"Generated meal type '{candidate.meal_type}' differs from requested meal type '{spec.meal_type}'."
        )
        warning_codes.append("requested_meal_type_mismatch")

    return ValidationReport(
        is_valid=not errors,
        errors=errors,
        warnings=warnings,
        error_codes=error_codes,
        warning_codes=warning_codes,
    )


def _merge_validation_reports(left: ValidationReport, right: ValidationReport) -> ValidationReport:
    return ValidationReport(
        is_valid=left.is_valid and right.is_valid,
        errors=[*left.errors, *right.errors],
        warnings=[*left.warnings, *right.warnings],
        error_codes=[*left.error_codes, *right.error_codes],
        warning_codes=[*left.warning_codes, *right.warning_codes],
    )


def _normalized_dietary_tags_for_resolved_recipe(resolved_recipe: ResolvedRecipeArtifact) -> list[str]:
    tags = list(dict.fromkeys(tag.strip() for tag in resolved_recipe.dietary_tags if tag and tag.strip()))
    if not tags:
        return []

    item_ids = {
        ingredient.catalog_item_id
        for ingredient in resolved_recipe.resolved_ingredients()
        if ingredient.catalog_item_id
    }
    categories = {ingredient.category for ingredient in resolved_recipe.resolved_ingredients()}

    normalized: list[str] = []
    for tag in tags:
        if tag == "Vegetarian" and item_ids & _NON_VEGETARIAN_ITEM_IDS:
            continue
        if tag == "Vegan" and ((item_ids & _NON_VEGAN_ITEM_IDS) or "Dairy" in categories or "Protein" in categories and "eggs" in item_ids):
            continue
        if tag == "Dairy-Free" and "Dairy" in categories:
            continue
        if tag == "Gluten-Free" and item_ids & _GLUTEN_ITEM_IDS:
            continue
        normalized.append(tag)
    return normalized