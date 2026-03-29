from __future__ import annotations

from dataclasses import asdict
import json
import math
from pathlib import Path
from typing import Any

from .catalog_alignment import CatalogAlignmentService
from .campaigns import RecipeCampaignRunner
from .corpus import RecipeCorpusIndex, load_recipe_records, normalize_text
from .models import CampaignSpec, CatalogEntry, DishSpec, FacetDefinition, FacetSelection, FreshnessRange, IngredientReference, IngredientStorage, utc_now_iso
from .openai_client import OpenAIChatClient
from .prompts import (
    APP_CUISINES,
    APP_MEAL_TYPES,
    FOOD_CATEGORIES,
    ingredient_corpus_batch_messages,
    ingredient_corpus_batch_schema,
    recipe_corpus_batch_messages,
    recipe_corpus_batch_schema,
)
from .services import build_default_catalog


_catalog_alignment_service = CatalogAlignmentService()


def analyze_ingredient_catalog(storage_dir: Path) -> dict:
    catalog = build_default_catalog(storage_dir=storage_dir)
    entries = catalog.entries()
    category_counts: dict[str, int] = {}
    quality_counts: dict[str, int] = {}
    substitute_count = 0
    storage_count = 0
    default_quantity_count = 0
    facet_definition_count = 0
    default_facet_count = 0
    freshness_range_count = 0

    for entry in entries:
        category_counts[entry.category] = category_counts.get(entry.category, 0) + 1
        quality_counts[entry.quality_status] = quality_counts.get(entry.quality_status, 0) + 1
        if entry.substitutes:
            substitute_count += 1
        if entry.storage is not None:
            storage_count += 1
        if entry.default_quantity is not None:
            default_quantity_count += 1
        if entry.facet_definitions:
            facet_definition_count += 1
        if entry.default_facets:
            default_facet_count += 1
        if entry.freshness_by_storage or entry.app_freshness_by_storage():
            freshness_range_count += 1

    enriched_entries = [entry for entry in entries if entry.quality_status == "enriched"]
    return {
        "generated_at": utc_now_iso(),
        "total_count": len(entries),
        "enriched_count": len(enriched_entries),
        "seed_count": quality_counts.get("seed", 0),
        "placeholder_count": quality_counts.get("placeholder", 0),
        "category_counts": dict(sorted(category_counts.items())),
        "quality_counts": dict(sorted(quality_counts.items())),
        "storage_coverage": 0.0 if not entries else round(storage_count / len(entries), 4),
        "substitute_coverage": 0.0 if not entries else round(substitute_count / len(entries), 4),
        "default_quantity_coverage": 0.0 if not entries else round(default_quantity_count / len(entries), 4),
        "facet_definition_coverage": 0.0 if not entries else round(facet_definition_count / len(entries), 4),
        "default_facet_coverage": 0.0 if not entries else round(default_facet_count / len(entries), 4),
        "freshness_range_coverage": 0.0 if not entries else round(freshness_range_count / len(entries), 4),
        "top_alias_rich_entries": [
            {
                "item_id": entry.item_id,
                "name": entry.name,
                "alias_count": len(entry.aliases),
            }
            for entry in sorted(entries, key=lambda value: (-len(value.aliases), value.name))[:20]
        ],
    }


def export_app_ingredient_catalog(storage_dir: Path, output_path: Path) -> dict:
    catalog = build_default_catalog(storage_dir=storage_dir)
    items = [entry.to_app_catalog_item_dict() for entry in sorted(catalog.entries(), key=lambda value: value.item_id)]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(items, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return {
        "generated_at": utc_now_iso(),
        "item_count": len(items),
        "output_path": str(output_path),
    }


def analyze_recipe_corpus(project_root: Path, output_root: Path, accepted_root: Path) -> dict:
    accepted_paths = sorted(accepted_root.rglob("seed_recipes.json")) if accepted_root.exists() else []
    records = []
    for path in accepted_paths:
        records.extend(load_recipe_records(path))

    cuisine_counts: dict[str, int] = {}
    meal_type_counts: dict[str, int] = {}
    normalized_titles: dict[str, int] = {}
    for record in records:
        cuisine = record.cuisine or "Other"
        meal_type = record.meal_type or "Unknown"
        cuisine_counts[cuisine] = cuisine_counts.get(cuisine, 0) + 1
        meal_type_counts[meal_type] = meal_type_counts.get(meal_type, 0) + 1
        normalized_titles[record.normalized_title] = normalized_titles.get(record.normalized_title, 0) + 1

    duplicate_titles = [title for title, count in normalized_titles.items() if count > 1]
    full_corpus = RecipeCorpusIndex.from_project_root(
        project_root,
        output_root=output_root,
        accepted_root=accepted_root,
        include_bundled_seed=False,
    )
    return {
        "generated_at": utc_now_iso(),
        "accepted_recipe_count": len(records),
        "full_corpus_recipe_count": full_corpus.recipe_count,
        "cuisine_counts": dict(sorted(cuisine_counts.items())),
        "meal_type_counts": dict(sorted(meal_type_counts.items())),
        "duplicate_title_count": len(duplicate_titles),
        "duplicate_titles": sorted(duplicate_titles)[:50],
    }


def analyze_corpus(project_root: Path, output_root: Path, accepted_root: Path) -> dict:
    return {
        "generated_at": utc_now_iso(),
        "ingredient_catalog": analyze_ingredient_catalog(output_root / "ingredient_catalog"),
        "recipe_corpus": analyze_recipe_corpus(project_root, output_root, accepted_root),
    }


class IngredientCorpusBuilder:
    def __init__(self, client: OpenAIChatClient, model: str | None = None) -> None:
        self._client = client
        self._model = model

    def build(
        self,
        *,
        target_count: int,
        batch_size: int,
        storage_dir: Path,
        report_path: Path,
        max_stalled_batches: int = 8,
    ) -> dict:
        catalog = build_default_catalog(storage_dir=storage_dir)
        stalled_batches = 0
        batches: list[dict] = []
        attempt_number = 0

        while _enriched_count(catalog.entries()) < target_count and stalled_batches < max_stalled_batches:
            entries = catalog.entries()
            metrics = analyze_ingredient_catalog(storage_dir)
            remaining = target_count - metrics["enriched_count"]
            current_batch_size = _effective_ingredient_batch_size(batch_size, remaining)
            focus_plan = _ingredient_focus_plan(entries, target_count=target_count, batch_size=current_batch_size, attempt_number=attempt_number)
            focus_categories = focus_plan["focus_categories"]
            existing_item_ids = sorted(entry.item_id for entry in entries)
            existing_names = sorted(entry.name for entry in entries)

            system_prompt, user_prompt = ingredient_corpus_batch_messages(
                batch_size=current_batch_size,
                existing_item_ids=_sample_existing_values(existing_item_ids, limit=80),
                existing_names=_sample_existing_values(existing_names, limit=80),
                focus_categories=focus_categories,
                category_targets=focus_plan["category_targets"],
                remaining_target=remaining,
                attempt_number=attempt_number + 1,
            )
            payload = self._client.complete_json(
                system_prompt=system_prompt,
                user_prompt=user_prompt,
                schema=ingredient_corpus_batch_schema(current_batch_size),
                schema_name="ingredient_corpus_batch",
                temperature=0.4,
                model=self._model,
            )

            before_ids = {entry.item_id for entry in entries}
            known_names = {normalize_text(entry.name) for entry in entries}
            generated_entries: list[CatalogEntry] = []
            rejected_entries: list[dict] = []
            seen_generated_ids: set[str] = set()
            seen_generated_names: set[str] = set()
            for item in payload.get("ingredients", []):
                entry = _catalog_entry_from_payload(item)
                quality_issue = _catalog_entry_quality_issue(
                    entry,
                    existing_item_ids=before_ids,
                    existing_names=known_names,
                    seen_generated_ids=seen_generated_ids,
                    seen_generated_names=seen_generated_names,
                )
                if quality_issue is not None:
                    rejected_entries.append({"name": entry.name, "reason": quality_issue})
                    continue
                generated_entries.append(entry)
                seen_generated_ids.add(entry.item_id)
                seen_generated_names.add(normalize_text(entry.name))
            catalog.upsert_entries(generated_entries)
            after_entries = catalog.entries()
            new_ids = sorted(entry.item_id for entry in after_entries if entry.item_id not in before_ids and entry.quality_status == "enriched")
            batches.append(
                {
                    "generated_at": utc_now_iso(),
                    "requested_batch_size": current_batch_size,
                    "attempt_number": attempt_number + 1,
                    "focus_categories": focus_categories,
                    "category_targets": focus_plan["category_targets"],
                    "generated_count": len(generated_entries),
                    "new_enriched_item_ids": new_ids,
                    "rejected_count": len(rejected_entries),
                    "rejected_entries": rejected_entries[:10],
                }
            )
            stalled_batches = 0 if new_ids else stalled_batches + 1
            attempt_number += 1

        report = {
            "generated_at": utc_now_iso(),
            "target_count": target_count,
            "batch_size": batch_size,
            "batches": batches,
            "metrics": analyze_ingredient_catalog(storage_dir),
        }
        _write_json(report_path, report)
        return report


class RecipeCorpusBuilder:
    def __init__(self, client: OpenAIChatClient, runner: RecipeCampaignRunner, model: str | None = None) -> None:
        self._client = client
        self._runner = runner
        self._model = model

    def build(
        self,
        *,
        project_root: Path,
        output_root: Path,
        accepted_root: Path,
        target_count: int,
        batch_size: int,
        report_path: Path,
        max_stalled_batches: int = 3,
    ) -> dict:
        stalled_batches = 0
        batches: list[dict] = []
        attempt_number = 0

        while _accepted_recipe_count(accepted_root) < target_count and stalled_batches < max_stalled_batches:
            recipe_metrics = analyze_recipe_corpus(project_root, output_root, accepted_root)
            current_count = recipe_metrics["accepted_recipe_count"]
            remaining = target_count - current_count
            current_batch_size = min(batch_size, remaining)
            corpus_index = RecipeCorpusIndex.from_project_root(
                project_root,
                output_root=output_root,
                accepted_root=accepted_root,
                include_bundled_seed=False,
            )
            plan = _plan_unique_recipe_batch(
                client=self._client,
                model=self._model,
                target_batch_size=current_batch_size,
                corpus_index=corpus_index,
                underrepresented_cuisines=_underrepresented_enum_values(recipe_metrics["cuisine_counts"], APP_CUISINES),
                underrepresented_meal_types=_underrepresented_enum_values(recipe_metrics["meal_type_counts"], APP_MEAL_TYPES),
                remaining_target=remaining,
                attempt_number=attempt_number,
            )
            filtered_spec = plan["spec"]
            if not filtered_spec.dishes:
                stalled_batches += 1
                batches.append(
                    {
                        "generated_at": utc_now_iso(),
                        "requested_batch_size": current_batch_size,
                        "attempt_number": attempt_number + 1,
                        "planner_attempts": plan["planner_attempts"],
                        "planner_batches": plan["planner_batches"],
                        "accepted_in_batch": 0,
                        "status": "no-unique-dishes",
                    }
                )
                attempt_number += 1
                continue

            state = self._runner.run_campaign(filtered_spec)
            accepted_in_batch = sum(1 for item in state.items if item.status == "completed")
            batches.append(
                {
                    "generated_at": utc_now_iso(),
                    "campaign_id": state.campaign_id,
                    "attempt_number": attempt_number + 1,
                    "requested_batch_size": current_batch_size,
                    "planned_batch_size": len(filtered_spec.dishes),
                    "planner_attempts": plan["planner_attempts"],
                    "planner_batches": plan["planner_batches"],
                    "accepted_in_batch": accepted_in_batch,
                    "campaign_status": state.status,
                }
            )
            stalled_batches = 0 if accepted_in_batch else stalled_batches + 1
            attempt_number += 1

        report = {
            "generated_at": utc_now_iso(),
            "target_count": target_count,
            "batch_size": batch_size,
            "batches": batches,
            "metrics": analyze_recipe_corpus(project_root, output_root, accepted_root),
        }
        _write_json(report_path, report)
        return report


def _accepted_recipe_count(accepted_root: Path) -> int:
    if not accepted_root.exists():
        return 0
    count = 0
    for path in accepted_root.rglob("seed_recipes.json"):
        count += len(load_recipe_records(path))
    return count


def _enriched_count(entries: list[CatalogEntry]) -> int:
    return sum(1 for entry in entries if entry.quality_status == "enriched")


def _underrepresented_categories(entries: list[CatalogEntry]) -> list[str]:
    counts = {category: 0 for category in FOOD_CATEGORIES}
    for entry in entries:
        if entry.quality_status == "enriched":
            counts[entry.category] = counts.get(entry.category, 0) + 1
    return [category for category, _ in sorted(counts.items(), key=lambda item: (item[1], item[0]))[:5]]


def _category_counts(entries: list[CatalogEntry]) -> dict[str, int]:
    counts = {category: 0 for category in FOOD_CATEGORIES}
    for entry in entries:
        if entry.quality_status == "enriched":
            counts[entry.category] = counts.get(entry.category, 0) + 1
    return counts


def _ingredient_focus_plan(entries: list[CatalogEntry], *, target_count: int, batch_size: int, attempt_number: int) -> dict:
    counts = _category_counts(entries)
    per_category_target = max(12, math.ceil(target_count / len(FOOD_CATEGORIES)))
    ordered_categories = sorted(
        FOOD_CATEGORIES,
        key=lambda category: (counts.get(category, 0) / per_category_target, counts.get(category, 0), category),
    )
    rotation_pool = ordered_categories[: max(6, min(len(ordered_categories), 9))]
    offset = attempt_number % len(rotation_pool)
    selected_categories: list[str] = []
    for index in range(len(rotation_pool)):
        category = rotation_pool[(offset + index) % len(rotation_pool)]
        if category in selected_categories:
            continue
        selected_categories.append(category)
        if len(selected_categories) >= min(3, len(rotation_pool)):
            break

    if not selected_categories:
        selected_categories = ordered_categories[:3]

    base_target = max(1, batch_size // len(selected_categories))
    remainder = batch_size % len(selected_categories)
    category_targets = {
        category: base_target + (1 if index < remainder else 0)
        for index, category in enumerate(selected_categories)
    }
    return {
        "focus_categories": selected_categories,
        "category_targets": category_targets,
    }


def _effective_ingredient_batch_size(requested_batch_size: int, remaining: int) -> int:
    return max(1, min(requested_batch_size, remaining, 24))


def _sample_existing_values(values: list[str], *, limit: int) -> list[str]:
    if len(values) <= limit:
        return list(values)

    sampled: list[str] = []
    seen: set[str] = set()
    step = (len(values) - 1) / max(1, limit - 1)
    for index in range(limit):
        value = values[round(index * step)]
        if value in seen:
            continue
        sampled.append(value)
        seen.add(value)

    if len(sampled) >= limit:
        return sampled[:limit]

    for value in values:
        if value in seen:
            continue
        sampled.append(value)
        if len(sampled) >= limit:
            break
    return sampled


def _plan_unique_recipe_batch(
    *,
    client: OpenAIChatClient,
    model: str | None,
    target_batch_size: int,
    corpus_index: RecipeCorpusIndex,
    underrepresented_cuisines: list[str],
    underrepresented_meal_types: list[str],
    remaining_target: int,
    attempt_number: int,
    max_planner_attempts: int = 4,
) -> dict[str, Any]:
    planned_dishes: list[DishSpec] = []
    planner_batches: list[dict[str, Any]] = []
    campaign_name: str | None = None
    existing_titles = _sample_existing_values(sorted(record.title for record in corpus_index._recipes), limit=120)

    planner_attempts = 0
    while len(planned_dishes) < target_batch_size and planner_attempts < max_planner_attempts:
        needed = target_batch_size - len(planned_dishes)
        system_prompt, user_prompt = recipe_corpus_batch_messages(
            batch_size=needed,
            existing_titles=existing_titles,
            underrepresented_cuisines=underrepresented_cuisines,
            underrepresented_meal_types=underrepresented_meal_types,
            remaining_target=remaining_target,
            attempt_number=attempt_number + planner_attempts + 1,
        )
        payload = client.complete_json(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            schema=recipe_corpus_batch_schema(needed),
            schema_name="recipe_corpus_batch",
            temperature=0.5,
            model=model,
        )

        if campaign_name is None:
            campaign_name = payload.get("name") or f"recipe-corpus-batch-{utc_now_iso()}"

        proposed_dishes = [
            DishSpec(
                title=str(dish["title"]).strip(),
                cuisine=dish.get("cuisine"),
                meal_type=dish.get("meal_type"),
                servings=max(1, int(dish.get("servings", 4))),
                goals=[str(value).strip() for value in dish.get("goals", []) if str(value).strip()],
                pantry_focus=[str(value).strip() for value in dish.get("pantry_focus", []) if str(value).strip()],
                notes=(None if dish.get("notes") is None else str(dish.get("notes")).strip() or None),
            )
            for dish in payload.get("dishes", [])
            if str(dish.get("title", "")).strip()
        ]
        merged_spec = CampaignSpec(
            name=campaign_name,
            dishes=[*planned_dishes, *proposed_dishes],
        )
        filtered_spec = _filter_unique_dishes(merged_spec, corpus_index, target_batch_size)
        added_count = max(0, len(filtered_spec.dishes) - len(planned_dishes))
        planner_batches.append(
            {
                "planner_attempt": planner_attempts + 1,
                "requested_batch_size": needed,
                "proposed_count": len(proposed_dishes),
                "added_unique_dishes": added_count,
                "accumulated_unique_dishes": len(filtered_spec.dishes),
            }
        )
        planned_dishes = filtered_spec.dishes
        planner_attempts += 1
        if added_count == 0 and planner_attempts >= 2:
            break

    return {
        "spec": CampaignSpec(name=campaign_name or f"recipe-corpus-batch-{utc_now_iso()}", dishes=planned_dishes),
        "planner_attempts": planner_attempts,
        "planner_batches": planner_batches,
    }


def _catalog_entry_quality_issue(
    entry: CatalogEntry,
    *,
    existing_item_ids: set[str],
    existing_names: set[str],
    seen_generated_ids: set[str],
    seen_generated_names: set[str],
) -> str | None:
    normalized_name = normalize_text(entry.name)
    if entry.item_id in existing_item_ids or entry.item_id in seen_generated_ids:
        return "duplicate item id"
    if normalized_name in existing_names or normalized_name in seen_generated_names:
        return "duplicate canonical name"
    if len(normalized_name.split()) >= 4 and any(token in normalized_name.split() for token in {"assorted", "variety", "mixed"}):
        return "overly generic family bucket"
    return None


def _underrepresented_enum_values(counts: dict[str, int], allowed_values: list[str]) -> list[str]:
    merged = {value: counts.get(value, 0) for value in allowed_values}
    return [value for value, _ in sorted(merged.items(), key=lambda item: (item[1], item[0]))[:5]]


def _catalog_entry_from_payload(payload: dict) -> CatalogEntry:
    name = str(payload["name"]).strip()
    aliases = {
        alias.strip(): []
        for alias in [name, *payload.get("aliases", [])]
        if str(alias).strip()
    }
    substitutes = []
    for substitute in payload.get("substitutes", []):
        substitute_name = str(substitute.get("name", "")).strip()
        if not substitute_name:
            continue
        sub_rationale = None if substitute.get("rationale") is None else str(substitute.get("rationale")).strip() or None
        sub_notes = None if substitute.get("notes") is None else str(substitute.get("notes")).strip() or None
        sub_ratio = None if substitute.get("ratio") is None else str(substitute.get("ratio")).strip() or None
        sub_dietary = [str(d).strip() for d in substitute.get("dietary", []) if str(d).strip()] if isinstance(substitute.get("dietary"), list) else []
        substitutes.append(
            IngredientReference(
                item_id=_slugify(substitute_name),
                name=substitute_name,
                rationale=sub_rationale,
                facets=_facet_selections_from_payload(substitute.get("facets")),
                ratio=sub_ratio,
                taste_impact=None if substitute.get("tasteImpact") is None else str(substitute.get("tasteImpact")).strip() or None,
                texture_impact=None if substitute.get("textureImpact") is None else str(substitute.get("textureImpact")).strip() or None,
                cooking_impact=None if substitute.get("cookingImpact") is None else str(substitute.get("cookingImpact")).strip() or None,
                nutrition_impact=None if substitute.get("nutritionImpact") is None else str(substitute.get("nutritionImpact")).strip() or None,
                notes=sub_notes,
                dietary=sub_dietary,
            )
        )

    storage_payload = payload.get("storage")
    storage = None
    if isinstance(storage_payload, dict):
        storage = IngredientStorage(
            preferred=None if storage_payload.get("preferred") is None else str(storage_payload.get("preferred")).strip() or None,
            pantry_days=_int_or_none(storage_payload.get("pantry_days")),
            refrigerator_days=_int_or_none(storage_payload.get("refrigerator_days")),
            freezer_days=_int_or_none(storage_payload.get("freezer_days")),
            notes=None if storage_payload.get("notes") is None else str(storage_payload.get("notes")).strip() or None,
        )

    freshness_by_storage = _freshness_ranges_from_payload(payload.get("freshness_by_storage"))

    return _catalog_alignment_service.align_entry(CatalogEntry(
        item_id=_slugify(name),
        name=name,
        category=str(payload["category"]).strip(),
        aliases=aliases,
        default_unit=None if payload.get("default_unit") is None else str(payload.get("default_unit")).strip() or None,
        default_quantity=_float_or_none(payload.get("default_quantity")),
        facet_definitions=_facet_definitions_from_payload(payload.get("facet_definitions")),
        default_facets=_facet_selections_from_payload(payload.get("default_facets")),
        unit_overrides=_unit_overrides_from_payload(payload.get("unit_overrides")),
        notes=str(payload.get("rationale", "")).strip() or None,
        substitutes=substitutes,
        storage=storage,
        freshness_by_storage=freshness_by_storage,
        quality_status="enriched",
        provenance=["ingredient_corpus_build"],
    ))


def _facet_selections_from_payload(value: object) -> list[FacetSelection]:
    if not isinstance(value, list):
        return []
    selections: list[FacetSelection] = []
    seen: set[tuple[str, str]] = set()
    for item in value:
        if not isinstance(item, dict):
            continue
        key = str(item.get("key", "")).strip()
        option = str(item.get("value", "")).strip()
        if not key or not option or (key, option) in seen:
            continue
        seen.add((key, option))
        selections.append(FacetSelection(key=key, value=option))
    return selections


def _facet_definitions_from_payload(value: object) -> list[FacetDefinition]:
    if not isinstance(value, list):
        return []
    definitions: list[FacetDefinition] = []
    seen: set[str] = set()
    for item in value:
        if not isinstance(item, dict):
            continue
        key = str(item.get("key", "")).strip()
        if not key or key in seen:
            continue
        options = [str(option).strip() for option in item.get("options", []) if str(option).strip()]
        if not options:
            continue
        seen.add(key)
        definitions.append(FacetDefinition(key=key, options=options))
    return definitions


def _unit_overrides_from_payload(value: object) -> dict[str, dict[str, str]]:
    if not isinstance(value, dict):
        return {}
    cleaned: dict[str, dict[str, str]] = {}
    for facet_key, overrides in value.items():
        if not isinstance(overrides, dict):
            continue
        key = str(facet_key).strip()
        if not key:
            continue
        option_overrides = {
            str(option).strip(): str(unit).strip()
            for option, unit in overrides.items()
            if str(option).strip() and str(unit).strip()
        }
        if option_overrides:
            cleaned[key] = option_overrides
    return cleaned


def _freshness_ranges_from_payload(value: object) -> dict[str, FreshnessRange]:
    if not isinstance(value, dict):
        return {}
    freshness: dict[str, FreshnessRange] = {}
    for storage_key, payload in value.items():
        if not isinstance(payload, dict):
            continue
        minimum = _int_or_none(payload.get("min_days") if "min_days" in payload else payload.get("minDays"))
        maximum = _int_or_none(payload.get("max_days") if "max_days" in payload else payload.get("maxDays"))
        if minimum is None or maximum is None:
            continue
        key = str(storage_key).strip()
        if not key:
            continue
        freshness[key] = FreshnessRange(min_days=minimum, max_days=max(maximum, minimum))
    return freshness


def _float_or_none(value: object) -> float | None:
    if value in (None, ""):
        return None
    return float(value)


def _filter_unique_dishes(spec: CampaignSpec, corpus_index: RecipeCorpusIndex, desired_count: int) -> CampaignSpec:
    unique: list[DishSpec] = []
    seen_titles: set[str] = set()

    for dish in spec.dishes:
        normalized_title = normalize_text(dish.title)
        if not normalized_title or normalized_title in seen_titles:
            continue
        if corpus_index.duplicate_reason_for_title(dish.title) is not None:
            continue
        if _peer_duplicate_reason(dish, unique) is not None:
            continue
        seen_titles.add(normalized_title)
        unique.append(dish)
        if len(unique) >= desired_count:
            break

    peer_titles = [dish.title for dish in unique]
    return CampaignSpec(
        name=spec.name,
        dishes=[
            DishSpec(
                title=dish.title,
                cuisine=dish.cuisine,
                meal_type=dish.meal_type,
                servings=dish.servings,
                goals=list(dish.goals),
                pantry_focus=list(dish.pantry_focus),
                avoid_titles=sorted(title for title in peer_titles if normalize_text(title) != normalize_text(dish.title)),
                notes=dish.notes,
                dish_id=dish.dish_id,
            )
            for dish in unique
        ],
        max_concurrency=spec.max_concurrency,
        campaign_id=spec.campaign_id,
        created_at=spec.created_at,
    )


def _peer_duplicate_reason(candidate: DishSpec, existing: list[DishSpec]) -> str | None:
    candidate_title_tokens = set(normalize_text(candidate.title).split())
    candidate_focus_tokens = {
        token
        for value in [*candidate.pantry_focus, *candidate.goals]
        for token in normalize_text(value).split()
        if token
    }
    for peer in existing:
        peer_title_tokens = set(normalize_text(peer.title).split())
        peer_focus_tokens = {
            token
            for value in [*peer.pantry_focus, *peer.goals]
            for token in normalize_text(value).split()
            if token
        }
        title_overlap = _jaccard(candidate_title_tokens, peer_title_tokens)
        focus_overlap = _jaccard(candidate_focus_tokens, peer_focus_tokens)
        if title_overlap >= 0.7:
            return f"title overlap with peer dish '{peer.title}' is too high"
        if title_overlap >= 0.45 and focus_overlap >= 0.5:
            return f"title and pantry overlap with peer dish '{peer.title}' is too high"
    return None


def _jaccard(left: set[str], right: set[str]) -> float:
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)


def _slugify(value: str) -> str:
    cleaned = "".join(character.lower() if character.isalnum() else "-" for character in value.strip())
    while "--" in cleaned:
        cleaned = cleaned.replace("--", "-")
    return cleaned.strip("-") or "item"


def _int_or_none(value: object) -> int | None:
    if value in (None, ""):
        return None
    return int(value)


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")