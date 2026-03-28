from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, replace
from pathlib import Path
from threading import Lock

from .artifacts import ArtifactWriter
from .logging_utils import get_logger
from .models import AttemptTrace, CampaignItemState, CampaignSpec, CampaignState, DishSpec, make_identifier
from .promotion import IngredientPromotionStore


logger = get_logger("campaigns")


class CampaignStore:
    def __init__(self, campaign_dir: Path) -> None:
        self.campaign_dir = campaign_dir
        self.state_path = campaign_dir / "state.json"
        self.spec_path = campaign_dir / "campaign_spec.json"
        self.metrics_path = campaign_dir / "campaign_metrics.json"
        self._lock = Lock()

    def create(self, spec: CampaignSpec) -> CampaignState:
        self.campaign_dir.mkdir(parents=True, exist_ok=True)
        logger.info("Creating campaign state campaign_id=%s dish_count=%s", spec.campaign_id, len(spec.dishes))
        state = CampaignState(
            campaign_id=spec.campaign_id,
            name=spec.name,
            created_at=spec.created_at,
            updated_at=spec.created_at,
            status="pending",
            items=[CampaignItemState(spec=dish) for dish in spec.dishes],
        )
        self.spec_path.write_text(json.dumps(asdict(spec), indent=2, sort_keys=True) + "\n", encoding="utf-8")
        self.save(state)
        return state

    def load(self) -> CampaignState:
        payload = json.loads(self.state_path.read_text(encoding="utf-8"))
        return CampaignState(
            campaign_id=payload["campaign_id"],
            name=payload.get("name"),
            created_at=payload["created_at"],
            updated_at=payload["updated_at"],
            status=payload["status"],
            items=[self._item_from_dict(item) for item in payload.get("items", [])],
        )

    def save(self, state: CampaignState) -> None:
        with self._lock:
            self.state_path.write_text(json.dumps(asdict(state), indent=2, sort_keys=True) + "\n", encoding="utf-8")
            self.metrics_path.write_text(
                json.dumps(_build_metrics_report(state), indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
        logger.debug("Saved campaign state campaign_id=%s status=%s", state.campaign_id, state.status)

    def mark_item(self, state: CampaignState, item: CampaignItemState) -> None:
        for index, existing_item in enumerate(state.items):
            if existing_item.spec.dish_id == item.spec.dish_id:
                state.items[index] = item
                break
        state.updated_at = _utc_now()
        state.status = _campaign_status(state.items)
        self.save(state)

    @staticmethod
    def _item_from_dict(payload: dict) -> CampaignItemState:
        spec_payload = payload["spec"]
        return CampaignItemState(
            spec=DishSpec(
                title=spec_payload["title"],
                cuisine=spec_payload.get("cuisine"),
                meal_type=spec_payload.get("meal_type"),
                servings=spec_payload.get("servings", 4),
                goals=spec_payload.get("goals", []),
                pantry_focus=spec_payload.get("pantry_focus", []),
                avoid_titles=spec_payload.get("avoid_titles", []),
                notes=spec_payload.get("notes"),
                dish_id=spec_payload.get("dish_id") or make_identifier("dish"),
            ),
            status=payload.get("status", "pending"),
            attempts=payload.get("attempts", 0),
            run_id=payload.get("run_id"),
            run_dir=payload.get("run_dir"),
            pipeline_run_path=payload.get("pipeline_run_path"),
            exported_recipe_path=payload.get("exported_recipe_path"),
            app_seed_recipe_path=payload.get("app_seed_recipe_path"),
            promoted_item_ids=payload.get("promoted_item_ids", []),
            quarantine_path=payload.get("quarantine_path"),
            duration_seconds=payload.get("duration_seconds"),
            resolved_ingredient_count=payload.get("resolved_ingredient_count", 0),
            unresolved_ingredient_count=payload.get("unresolved_ingredient_count", 0),
            unresolved_ingredient_names=payload.get("unresolved_ingredient_names", []),
            generation_attempts=payload.get("generation_attempts", 0),
            failure_code=payload.get("failure_code"),
            review_status=payload.get("review_status"),
            review_issue_count=payload.get("review_issue_count", 0),
            attempt_history=[
                AttemptTrace(
                    attempt_number=int(attempt.get("attempt_number", 0)),
                    status=str(attempt.get("status", "failed")),
                    failure_code=attempt.get("failure_code"),
                    message=attempt.get("message"),
                    validation_error_codes=list(attempt.get("validation_error_codes", [])),
                    review_status=attempt.get("review_status"),
                    review_issue_codes=list(attempt.get("review_issue_codes", [])),
                )
                for attempt in payload.get("attempt_history", [])
            ],
            errors=payload.get("errors", []),
            warnings=payload.get("warnings", []),
            completed_at=payload.get("completed_at"),
        )


class RecipeCampaignRunner:
    def __init__(
        self,
        orchestrator,
        artifact_writer: ArtifactWriter,
        promotion_store: IngredientPromotionStore,
        root_dir: Path,
        accepted_root: Path | None = None,
        max_workers: int = 1,
    ) -> None:
        self._orchestrator = orchestrator
        self._artifact_writer = artifact_writer
        self._promotion_store = promotion_store
        self._root_dir = root_dir
        self._accepted_root = accepted_root
        self._max_workers = max(1, max_workers)

    def run_campaign(self, spec: CampaignSpec) -> CampaignState:
        normalized_spec = _apply_peer_avoid_titles(spec)
        logger.info("Starting campaign campaign_id=%s max_workers=%s", normalized_spec.campaign_id, self._max_workers)
        store = CampaignStore(self._root_dir / normalized_spec.campaign_id)
        state = store.create(normalized_spec)

        with ThreadPoolExecutor(max_workers=self._max_workers) as executor:
            futures = {}
            for item in state.items:
                running_item = CampaignItemState(spec=item.spec, status="running", attempts=item.attempts + 1)
                store.mark_item(state, running_item)
                futures[executor.submit(self._run_item, store.campaign_dir, running_item)] = running_item.spec.dish_id

            for future in as_completed(futures):
                completed_item = future.result()
                store.mark_item(state, completed_item)

        state.status = _campaign_status(state.items)
        state.updated_at = _utc_now()
        self._write_app_import_bundle(state, store.campaign_dir)
        store.save(state)
        logger.info("Campaign finished campaign_id=%s status=%s", state.campaign_id, state.status)
        return state

    def resume_campaign(self, campaign_dir: Path) -> CampaignState:
        store = CampaignStore(campaign_dir)
        state = store.load()
        logger.info("Resuming campaign campaign_id=%s", state.campaign_id)
        pending_items = [item for item in state.items if item.status in {"pending", "failed", "running"}]
        if not pending_items:
            return state

        with ThreadPoolExecutor(max_workers=self._max_workers) as executor:
            futures = {}
            for item in pending_items:
                running_item = CampaignItemState(spec=item.spec, status="running", attempts=item.attempts + 1)
                store.mark_item(state, running_item)
                futures[executor.submit(self._run_item, store.campaign_dir, running_item)] = running_item.spec.dish_id

            for future in as_completed(futures):
                completed_item = future.result()
                store.mark_item(state, completed_item)

        state.status = _campaign_status(state.items)
        state.updated_at = _utc_now()
        self._write_app_import_bundle(state, store.campaign_dir)
        store.save(state)
        logger.info("Resume finished campaign_id=%s status=%s", state.campaign_id, state.status)
        return state

    def _run_item(self, campaign_dir: Path, item: CampaignItemState) -> CampaignItemState:
        logger.info("Running campaign item dish_id=%s title=%s", item.spec.dish_id, item.spec.title)
        try:
            pipeline_run = self._orchestrator.run(item.spec)
            run_dir = campaign_dir / "runs" / item.spec.dish_id
            artifact_paths = self._artifact_writer.write(pipeline_run, run_dir)
            unresolved_ingredients = pipeline_run.resolved_recipe.unresolved_ingredients()
            resolved_ingredients = pipeline_run.resolved_recipe.resolved_ingredients()
            accepted = pipeline_run.validation.is_valid and (pipeline_run.review is None or pipeline_run.review.status == "accepted")
            recipe_export_path = None
            promotion_summary = None
            if accepted:
                recipe_export_path = self._artifact_writer.write_recipe_export(
                    pipeline_run.resolved_recipe,
                    campaign_dir / "recipes",
                )
                promotion_summary = self._promotion_store.promote(
                    pipeline_run,
                    campaign_dir / "ingredient_corpus",
                )

            status = "completed" if accepted else "failed"
            logger.info(
                "Campaign item finished dish_id=%s title=%s status=%s failure_code=%s",
                item.spec.dish_id,
                item.spec.title,
                status,
                pipeline_run.failure_code,
            )
            return CampaignItemState(
                spec=item.spec,
                status=status,
                attempts=item.attempts,
                run_id=pipeline_run.run_id,
                run_dir=str(run_dir),
                pipeline_run_path=artifact_paths["pipeline_run"],
                exported_recipe_path=recipe_export_path,
                app_seed_recipe_path=artifact_paths["app_seed_recipe"],
                promoted_item_ids=[] if promotion_summary is None else promotion_summary.promoted_item_ids,
                quarantine_path=None if promotion_summary is None else promotion_summary.quarantine_path,
                duration_seconds=pipeline_run.duration_seconds,
                resolved_ingredient_count=len(resolved_ingredients),
                unresolved_ingredient_count=len(unresolved_ingredients),
                unresolved_ingredient_names=sorted({ingredient.raw_name for ingredient in unresolved_ingredients}),
                generation_attempts=pipeline_run.generation_attempts,
                failure_code=pipeline_run.failure_code,
                review_status=None if pipeline_run.review is None else pipeline_run.review.status,
                review_issue_count=0 if pipeline_run.review is None else len(pipeline_run.review.issues),
                attempt_history=pipeline_run.attempt_history,
                errors=list(pipeline_run.validation.errors),
                warnings=list(pipeline_run.validation.warnings)
                + ([] if pipeline_run.review is None or pipeline_run.review.status == "accepted" else [pipeline_run.review.rationale]),
                completed_at=pipeline_run.generated_at,
            )
        except Exception as exc:
            logger.exception("Campaign item crashed dish_id=%s title=%s", item.spec.dish_id, item.spec.title)
            return CampaignItemState(
                spec=item.spec,
                status="failed",
                attempts=item.attempts,
                failure_code=getattr(exc, "failure_code", "pipeline_execution_failed"),
                attempt_history=getattr(exc, "attempt_history", []),
                errors=[str(exc)],
                completed_at=_utc_now(),
            )

    def _write_app_import_bundle(self, state: CampaignState, campaign_dir: Path) -> None:
        app_seed_recipe_paths = [
            item.app_seed_recipe_path
            for item in state.items
            if item.status == "completed" and item.app_seed_recipe_path
        ]
        if not app_seed_recipe_paths:
            return

        self._artifact_writer.write_campaign_app_import_bundle(
            app_seed_recipe_paths,
            campaign_dir / "app_import",
            campaign_id=state.campaign_id,
            campaign_name=state.name,
        )
        logger.info("Wrote campaign import bundle campaign_id=%s recipe_count=%s", state.campaign_id, len(app_seed_recipe_paths))
        if self._accepted_root is not None:
            self._artifact_writer.write_campaign_app_import_bundle(
                app_seed_recipe_paths,
                self._accepted_root / state.campaign_id,
                campaign_id=state.campaign_id,
                campaign_name=state.name,
            )
            logger.info("Mirrored accepted bundle campaign_id=%s accepted_root=%s", state.campaign_id, self._accepted_root)


def load_campaign_spec(spec_file: Path) -> CampaignSpec:
    payload = json.loads(spec_file.read_text(encoding="utf-8"))
    return CampaignSpec(
        name=payload.get("name"),
        max_concurrency=_normalize_max_concurrency(payload.get("max_concurrency")),
        campaign_id=payload.get("campaign_id") or make_identifier("campaign"),
        created_at=payload.get("created_at") or _utc_now(),
        dishes=[
            DishSpec(
                title=dish["title"],
                cuisine=dish.get("cuisine"),
                meal_type=dish.get("meal_type"),
                servings=dish.get("servings", 4),
                goals=dish.get("goals", []),
                pantry_focus=dish.get("pantry_focus", []),
                avoid_titles=dish.get("avoid_titles", []),
                notes=dish.get("notes"),
                dish_id=dish.get("dish_id") or make_identifier("dish"),
            )
            for dish in payload.get("dishes", [])
        ],
    )


def _apply_peer_avoid_titles(spec: CampaignSpec) -> CampaignSpec:
    titles = [dish.title for dish in spec.dishes]
    dishes = [
        replace(
            dish,
            avoid_titles=_merge_avoid_titles(dish.avoid_titles, [title for title in titles if title != dish.title]),
        )
        for dish in spec.dishes
    ]
    return CampaignSpec(
        name=spec.name,
        dishes=dishes,
        max_concurrency=spec.max_concurrency,
        campaign_id=spec.campaign_id,
        created_at=spec.created_at,
    )


def _merge_avoid_titles(existing: list[str], peer_titles: list[str]) -> list[str]:
    merged: list[str] = []
    seen: set[str] = set()
    for value in [*existing, *peer_titles]:
        normalized = value.strip().lower()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        merged.append(value)
    return merged


def load_campaign_spec_from_dir(campaign_dir: Path) -> CampaignSpec:
    return load_campaign_spec(campaign_dir / "campaign_spec.json")


def _campaign_status(items: list[CampaignItemState]) -> str:
    statuses = {item.status for item in items}
    if statuses == {"completed"}:
        return "completed"
    if "running" in statuses:
        return "running"
    if "failed" in statuses and len(statuses) == 1:
        return "failed"
    if "failed" in statuses:
        return "completed-with-errors"
    if "pending" in statuses:
        return "pending"
    return "running"


def _utc_now() -> str:
    from .models import utc_now_iso

    return utc_now_iso()


def _normalize_max_concurrency(value: object) -> int | None:
    if value in (None, ""):
        return None
    return max(1, int(value))


def _build_metrics_report(state: CampaignState) -> dict:
    status_counts: dict[str, int] = {}
    unique_promoted_items: set[str] = set()
    unresolved_ingredient_names: set[str] = set()
    duration_values: list[float] = []

    for item in state.items:
        status_counts[item.status] = status_counts.get(item.status, 0) + 1
        unique_promoted_items.update(item.promoted_item_ids)
        unresolved_ingredient_names.update(item.unresolved_ingredient_names)
        if item.duration_seconds is not None:
            duration_values.append(item.duration_seconds)

    item_count = len(state.items)
    completed_count = status_counts.get("completed", 0)
    failed_count = status_counts.get("failed", 0)

    return {
        "campaign_id": state.campaign_id,
        "name": state.name,
        "status": state.status,
        "created_at": state.created_at,
        "updated_at": state.updated_at,
        "summary": {
            "item_count": item_count,
            "completed_count": completed_count,
            "failed_count": failed_count,
            "pending_count": status_counts.get("pending", 0),
            "running_count": status_counts.get("running", 0),
            "success_rate": round(completed_count / item_count, 3) if item_count else 0.0,
            "total_attempts": sum(item.attempts for item in state.items),
            "generation_attempt_count": sum(item.generation_attempts for item in state.items),
            "resolved_ingredient_count": sum(item.resolved_ingredient_count for item in state.items),
            "unresolved_ingredient_count": sum(item.unresolved_ingredient_count for item in state.items),
            "promoted_item_count": len(unique_promoted_items),
            "quarantine_file_count": sum(1 for item in state.items if item.quarantine_path),
            "total_duration_seconds": round(sum(duration_values), 3),
            "average_duration_seconds": round(sum(duration_values) / len(duration_values), 3) if duration_values else None,
            "unique_promoted_items": sorted(unique_promoted_items),
            "unresolved_ingredient_names": sorted(unresolved_ingredient_names),
        },
        "items": [
            {
                "dish_id": item.spec.dish_id,
                "title": item.spec.title,
                "status": item.status,
                "attempts": item.attempts,
                "generation_attempts": item.generation_attempts,
                "run_id": item.run_id,
                "duration_seconds": item.duration_seconds,
                "resolved_ingredient_count": item.resolved_ingredient_count,
                "unresolved_ingredient_count": item.unresolved_ingredient_count,
                "unresolved_ingredient_names": item.unresolved_ingredient_names,
                "promoted_item_count": len(item.promoted_item_ids),
                "failure_code": item.failure_code,
                "review_status": item.review_status,
                "review_issue_count": item.review_issue_count,
                "error_count": len(item.errors),
                "warning_count": len(item.warnings),
                "completed_at": item.completed_at,
            }
            for item in state.items
        ],
    }