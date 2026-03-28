from __future__ import annotations

from dataclasses import asdict
import json
from pathlib import Path
from threading import Lock

from .models import IngredientPromotionSummary, PipelineRun, ResolvedIngredient


class IngredientPromotionStore:
    def __init__(self) -> None:
        self._lock = Lock()

    def promote(self, pipeline_run: PipelineRun, root_dir: Path) -> IngredientPromotionSummary:
        promoted_dir = root_dir / "promoted"
        quarantine_dir = root_dir / "quarantine"
        promoted_dir.mkdir(parents=True, exist_ok=True)
        quarantine_dir.mkdir(parents=True, exist_ok=True)

        promoted_paths: list[str] = []
        promoted_item_ids: list[str] = []
        unresolved_payload: list[dict] = []

        for ingredient in pipeline_run.resolved_recipe.ingredients:
            if ingredient.status == "resolved" and ingredient.catalog_item_id:
                promoted_paths.append(self._upsert_promoted_ingredient(ingredient, pipeline_run, promoted_dir))
                promoted_item_ids.append(ingredient.catalog_item_id)
            elif ingredient.status == "unresolved":
                unresolved_payload.append(self._serialize_unresolved(ingredient))

        quarantine_path = None
        if unresolved_payload:
            quarantine_path = str(quarantine_dir / f"{pipeline_run.run_id}.json")
            Path(quarantine_path).write_text(
                json.dumps(
                    {
                        "run_id": pipeline_run.run_id,
                        "generated_at": pipeline_run.generated_at,
                        "dish": pipeline_run.spec.title,
                        "recipe_title": pipeline_run.resolved_recipe.title,
                        "unresolved_ingredients": unresolved_payload,
                    },
                    indent=2,
                    sort_keys=True,
                ) + "\n",
                encoding="utf-8",
            )

        return IngredientPromotionSummary(
            promoted_item_ids=sorted(set(promoted_item_ids)),
            promoted_paths=promoted_paths,
            quarantine_path=quarantine_path,
        )

    def _upsert_promoted_ingredient(
        self,
        ingredient: ResolvedIngredient,
        pipeline_run: PipelineRun,
        promoted_dir: Path,
    ) -> str:
        path = promoted_dir / f"{ingredient.catalog_item_id}.json"
        with self._lock:
            if path.exists():
                payload = json.loads(path.read_text(encoding="utf-8"))
            else:
                ingredient_record = ingredient.ingredient_record
                payload = {
                    "item_id": ingredient.catalog_item_id,
                    "category": ingredient.category,
                    "display_name": ingredient.display_name,
                    "canonical_name": None if ingredient_record is None else ingredient_record.name,
                    "aliases": {} if ingredient_record is None else {
                        alias: [{"key": facet.key, "value": facet.value} for facet in facets]
                        for alias, facets in ingredient_record.aliases.items()
                    },
                    "default_unit": None if ingredient_record is None else ingredient_record.default_unit,
                    "substitutes": [] if ingredient_record is None else [asdict(reference) for reference in ingredient_record.substitutes],
                    "storage": None if ingredient_record is None or ingredient_record.storage is None else asdict(ingredient_record.storage),
                    "quality_status": "seed" if ingredient_record is None else ingredient_record.quality_status,
                    "provenance": [] if ingredient_record is None else list(ingredient_record.provenance),
                    "first_seen_at": pipeline_run.generated_at,
                    "last_seen_at": pipeline_run.generated_at,
                    "recipe_reference_count": 0,
                    "evidence_count": 0,
                    "observed_raw_names": {},
                    "observed_facets": {},
                    "evidence": [],
                }

            payload["last_seen_at"] = pipeline_run.generated_at
            payload["category"] = ingredient.category
            payload["display_name"] = ingredient.display_name
            ingredient_record = ingredient.ingredient_record
            if ingredient_record is not None:
                payload["canonical_name"] = ingredient_record.name
                payload["aliases"] = {
                    alias: [{"key": facet.key, "value": facet.value} for facet in facets]
                    for alias, facets in ingredient_record.aliases.items()
                }
                payload["default_unit"] = ingredient_record.default_unit
                payload["substitutes"] = [asdict(reference) for reference in ingredient_record.substitutes]
                payload["storage"] = None if ingredient_record.storage is None else asdict(ingredient_record.storage)
                payload["quality_status"] = ingredient_record.quality_status
                payload["provenance"] = list(dict.fromkeys([*payload.get("provenance", []), *ingredient_record.provenance]))
            payload["observed_raw_names"][ingredient.raw_name] = payload["observed_raw_names"].get(ingredient.raw_name, 0) + 1
            for facet in ingredient.facets:
                key = f"{facet.key}:{facet.value}"
                payload["observed_facets"][key] = payload["observed_facets"].get(key, 0) + 1

            payload["evidence"].append(
                {
                    "run_id": pipeline_run.run_id,
                    "dish": pipeline_run.spec.title,
                    "recipe_title": pipeline_run.resolved_recipe.title,
                    "raw_name": ingredient.raw_name,
                    "confidence": ingredient.confidence,
                    "generated_at": pipeline_run.generated_at,
                }
            )
            payload["evidence"] = payload["evidence"][-200:]
            payload["evidence_count"] = len(payload["evidence"])
            payload["recipe_reference_count"] = len({entry["recipe_title"] for entry in payload["evidence"]})

            path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return str(path)

    @staticmethod
    def _serialize_unresolved(ingredient: ResolvedIngredient) -> dict:
        return {
            "raw_name": ingredient.raw_name,
            "category": ingredient.category,
            "quantity": ingredient.quantity,
            "unit": ingredient.unit,
            "rationale": ingredient.rationale,
            "confidence": ingredient.confidence,
        }