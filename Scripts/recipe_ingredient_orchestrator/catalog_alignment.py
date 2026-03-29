from __future__ import annotations

from .models import CatalogEntry, FacetDefinition, FacetSelection, FreshnessRange, IngredientReference, IngredientStorage, slugify


class CatalogAlignmentService:
    def align_entry(self, entry: CatalogEntry) -> CatalogEntry:
        canonical_name = _clean_display_name(entry.name)
        default_facets = list(entry.default_facets)
        aliases = _normalized_aliases(entry.aliases, canonical_name, default_facets)
        substitutes = [self.align_reference(reference, source_item_id=slugify(canonical_name)) for reference in entry.substitutes]
        freshness_by_storage = dict(entry.freshness_by_storage)
        if not freshness_by_storage and entry.storage is not None:
            freshness_by_storage = _freshness_from_storage(entry.storage)

        facet_definitions = _collect_facet_definitions(entry.facet_definitions, aliases, default_facets)
        default_quantity = entry.default_quantity if entry.default_quantity is not None else _suggest_default_quantity(entry.default_unit, entry.category)

        return CatalogEntry(
            item_id=slugify(canonical_name),
            name=canonical_name,
            category=entry.category,
            aliases=aliases,
            default_unit=entry.default_unit,
            default_quantity=default_quantity,
            facet_definitions=facet_definitions,
            default_facets=default_facets,
            unit_overrides={key: dict(value) for key, value in entry.unit_overrides.items()},
            notes=entry.notes,
            substitutes=substitutes,
            storage=entry.storage,
            freshness_by_storage=freshness_by_storage,
            quality_status=entry.quality_status,
            provenance=list(entry.provenance),
            evidence_count=entry.evidence_count,
            recipe_reference_count=entry.recipe_reference_count,
            first_seen_at=entry.first_seen_at,
            last_seen_at=entry.last_seen_at,
        )

    def align_reference(self, reference: IngredientReference, *, source_item_id: str | None = None) -> IngredientReference:
        canonical_name = _clean_display_name(reference.name)
        canonical_item_id = slugify(canonical_name)
        same_root = source_item_id == canonical_item_id
        return IngredientReference(
            item_id=canonical_item_id,
            name=canonical_name,
            rationale=reference.rationale,
            facets=list(reference.facets),
            ratio=reference.ratio or "1:1",
            taste_impact=reference.taste_impact or ("Slight" if same_root else "Moderate"),
            texture_impact=reference.texture_impact or ("Slight" if same_root else "Moderate"),
            cooking_impact=reference.cooking_impact or ("Slight Adjustment" if same_root else "Moderate Adjustment"),
            nutrition_impact=reference.nutrition_impact,
            notes=reference.notes or reference.rationale,
            dietary=list(reference.dietary),
        )


def _normalized_aliases(
    aliases: dict[str, list[FacetSelection]],
    canonical_name: str,
    default_facets: list[FacetSelection],
) -> dict[str, list[FacetSelection]]:
    normalized_aliases: dict[str, list[FacetSelection]] = {canonical_name: list(default_facets)}
    for alias, facets in aliases.items():
        cleaned_alias = _clean_display_name(alias)
        if not cleaned_alias:
            continue
        normalized_aliases[cleaned_alias] = list(facets or default_facets)
    return normalized_aliases


def _collect_facet_definitions(
    existing: list[FacetDefinition],
    aliases: dict[str, list[FacetSelection]],
    default_facets: list[FacetSelection],
) -> list[FacetDefinition]:
    options_by_key: dict[str, set[str]] = {}
    for definition in existing:
        options_by_key.setdefault(definition.key, set()).update(definition.options)
    for facets in [*aliases.values(), default_facets]:
        for facet in facets:
            options_by_key.setdefault(facet.key, set()).add(facet.value)
    return [
        FacetDefinition(key=key, options=sorted(values))
        for key, values in sorted(options_by_key.items())
        if values
    ]


def _clean_display_name(value: str) -> str:
    parts = [part for part in str(value).strip().split() if part]
    if not parts:
        return "Ingredient"
    return " ".join(part[:1].upper() + part[1:] for part in parts)


def _freshness_from_storage(storage: IngredientStorage) -> dict[str, FreshnessRange]:
    freshness: dict[str, FreshnessRange] = {}
    for storage_key, days in {
        "pantry": storage.pantry_days,
        "refrigerator": storage.refrigerator_days,
        "freezer": storage.freezer_days,
    }.items():
        if days is None:
            continue
        minimum = max(1, int(round(days * 0.75)))
        maximum = max(minimum, int(round(days * 1.25)))
        freshness[storage_key] = FreshnessRange(min_days=minimum, max_days=maximum)
    return freshness


def _suggest_default_quantity(default_unit: str | None, category: str) -> float | None:
    if default_unit is None:
        return None
    if default_unit in {"kg", "L", "loaf", "bunch", "can", "pkg"}:
        return 1.0
    if default_unit in {"piece", "whole", "slice", "clove"}:
        return 1.0
    if default_unit in {"g", "oz"}:
        if category in {"Baking Supplies", "Grains & Cereals"}:
            return 1000.0 if default_unit == "g" else 35.0
        return 500.0 if default_unit == "g" else 16.0
    if default_unit in {"ml", "fl oz"}:
        return 250.0 if default_unit == "ml" else 8.0
    if default_unit == "lb":
        return 1.0
    return None
