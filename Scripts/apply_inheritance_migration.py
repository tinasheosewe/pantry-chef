#!/usr/bin/env python3
"""Migrate catalog kind facets into inheritance links.

By default this is a dry-run and prints a summary.
Pass --write to persist catalog changes.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field

from catalog_lib import (
    facet_options,
    items_by_id,
    load_catalog,
    normalize_lookup_key,
    save_catalog,
    set_facet_options,
    slugify,
)

KIND_FACET_KEYS = {"variant"}

FAMILY_ORDER = [
    "nut",
    "oil",
    "cheese",
    "beef",
    "rice",
    "flour",
    "broth",
    "pasta",
    "bread",
    "sugar",
    "cream",
    "yogurt",
    "milk",
    "pork",
    "lamb",
    "turkey",
    "fish",
    "shrimp",
    "mushroom",
    "potato",
    "onion",
    "pepper",
    "tomato",
    "beans",
    "cured-meat",
]

# Parent-specific overrides for existing ids.
KNOWN_VARIANT_IDS: dict[str, dict[str, str]] = {
    "nut": {
        "black walnut": "black-walnut",
        "brazil": "brazil-nut",
        "ginkgo": "ginkgo-nut",
        "hickory": "hickory-nut",
        "macadamia": "macadamia-nut",
        "mixed": "mixed-nuts",
        "pine": "pine-nut",
    }
}


@dataclass
class MigrationSummary:
    families_processed: int = 0
    children_linked: int = 0
    children_created: int = 0
    parent_kind_facets_removed: int = 0
    child_kind_facets_removed: int = 0
    parent_aliases_reassigned: int = 0
    notes: list[str] = field(default_factory=list)


def canonical(text: str) -> str:
    return normalize_lookup_key(text)


def strip_kind_facets(item: dict) -> int:
    before = len(item.get("facets", []))
    item["facets"] = [f for f in item.get("facets", []) if f.get("key") not in KIND_FACET_KEYS]
    removed = before - len(item["facets"])
    if "defaultSelections" in item:
        item["defaultSelections"] = [
            s for s in item.get("defaultSelections", []) if s.get("key") not in KIND_FACET_KEYS
        ]
    return removed


def ensure_parent_link(child: dict, parent_id: str) -> bool:
    current = list(child.get("parentIds", []))
    if parent_id in current:
        return False
    current.append(parent_id)
    child["parentIds"] = sorted(set(current))
    return True


def enforce_additive_facets(child: dict, parent: dict) -> int:
    child_facets = {facet.get("key"): facet for facet in child.get("facets", [])}
    changed = 0
    for parent_facet in parent.get("facets", []):
        key = parent_facet.get("key")
        if key in KIND_FACET_KEYS:
            continue
        parent_options = list(parent_facet.get("options", []))
        if key not in child_facets:
            child.setdefault("facets", []).append({"key": key, "options": parent_options})
            changed += 1
            continue
        existing = child_facets[key]
        existing_options = set(existing.get("options", []))
        merged = list(existing.get("options", []))
        for option in parent_options:
            if option not in existing_options:
                merged.append(option)
                existing_options.add(option)
                changed += 1
        existing["options"] = merged
    return changed


def drop_legacy_fields(item: dict) -> None:
    for key in ("isGenericBase", "parentId", "parentFacets", "excludedFromGenericMatch"):
        item.pop(key, None)


def resolve_child_id(parent_id: str, option: str, by_id: dict[str, dict]) -> str:
    option_key = canonical(option)
    override = KNOWN_VARIANT_IDS.get(parent_id, {}).get(option_key)
    if override and override in by_id:
        return override

    slug = slugify(option)
    candidates = [slug, f"{slug}-{parent_id}", f"{slug}-oil" if parent_id == "oil" else ""]
    for candidate in candidates:
        if candidate and candidate in by_id:
            return candidate

    for item_id, item in by_id.items():
        if canonical(item.get("name", "")) == option_key:
            return item_id
    return slug


def create_child_from_parent(parent: dict, child_id: str, option: str) -> dict:
    child = {
        "id": child_id,
        "name": option,
        "category": parent["category"],
        "defaultUnit": parent.get("defaultUnit"),
        "defaultQuantity": parent.get("defaultQuantity"),
        "defaultStorage": parent["defaultStorage"],
        "aliases": [],
        "facets": [f for f in parent.get("facets", []) if f.get("key") not in KIND_FACET_KEYS],
        "defaultSelections": [
            s for s in parent.get("defaultSelections", []) if s.get("key") not in KIND_FACET_KEYS
        ],
        "freshnessByStorage": parent.get("freshnessByStorage", {}),
        "parentIds": [parent["id"]],
    }
    if parent.get("facetAliases"):
        child["facetAliases"] = parent["facetAliases"]
    return child


def migrate_family(parent_id: str, items: list[dict], summary: MigrationSummary) -> None:
    by_id = items_by_id(items)
    parent = by_id.get(parent_id)
    if not parent:
        summary.notes.append(f"skip {parent_id}: missing catalog entry")
        return
    variants = facet_options(parent, "variant")

    summary.families_processed += 1
    if variants:
        removed_parent_facets = strip_kind_facets(parent)
        summary.parent_kind_facets_removed += removed_parent_facets
    drop_legacy_fields(parent)

    if not variants:
        # Parent already migrated: only enforce additive inheritance and cleanup.
        for child in items:
            if parent_id in child.get("parentIds", []):
                enforce_additive_facets(child, parent)
                drop_legacy_fields(child)
        summary.notes.append(f"{parent_id}: refreshed existing linked children")
        return

    parent_aliases = list(parent.get("aliases", []))
    kept_parent_aliases: list[str] = []
    child_aliases: dict[str, list[str]] = {}

    for option in variants:
        child_id = resolve_child_id(parent_id, option, by_id)
        child = by_id.get(child_id)
        if child is None:
            child = create_child_from_parent(parent, child_id, option)
            items.append(child)
            by_id[child_id] = child
            summary.children_created += 1
        if ensure_parent_link(child, parent_id):
            summary.children_linked += 1

        summary.child_kind_facets_removed += strip_kind_facets(child)
        enforce_additive_facets(child, parent)
        drop_legacy_fields(child)
        child_aliases.setdefault(child_id, []).append(option)

    variant_keys = {canonical(v) for v in variants}
    for alias in parent_aliases:
        alias_key = canonical(alias)
        matched_child = None
        for option in variants:
            option_key = canonical(option)
            if option_key in alias_key:
                matched_child = resolve_child_id(parent_id, option, by_id)
                break
        if matched_child:
            child_aliases.setdefault(matched_child, []).append(alias)
            summary.parent_aliases_reassigned += 1
            continue
        if alias_key in variant_keys:
            continue
        kept_parent_aliases.append(alias)
    parent["aliases"] = sorted(set(kept_parent_aliases), key=str.lower)

    for child_id, aliases in child_aliases.items():
        child = by_id[child_id]
        merged = set(child.get("aliases", []))
        merged.update(a for a in aliases if canonical(a) != canonical(child["name"]))
        child["aliases"] = sorted(merged, key=str.lower)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply inheritance migration to catalog families.")
    parser.add_argument(
        "--families",
        nargs="*",
        default=[],
        help="Family ids to migrate (default: none unless --all is passed).",
    )
    parser.add_argument("--all", action="store_true", help="Migrate all known families.")
    parser.add_argument("--write", action="store_true", help="Persist catalog.json changes.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    selected_families = FAMILY_ORDER if args.all else args.families
    if not selected_families:
        print("No families selected. Pass --families ... or --all.")
        return 0

    items = load_catalog()
    summary = MigrationSummary()
    for family_id in selected_families:
        migrate_family(family_id, items, summary)

    print("Inheritance migration summary")
    print(f"- families_processed: {summary.families_processed}")
    print(f"- children_linked: {summary.children_linked}")
    print(f"- children_created: {summary.children_created}")
    print(f"- parent_kind_facets_removed: {summary.parent_kind_facets_removed}")
    print(f"- child_kind_facets_removed: {summary.child_kind_facets_removed}")
    print(f"- parent_aliases_reassigned: {summary.parent_aliases_reassigned}")
    if summary.notes:
        print("- notes:")
        for note in summary.notes:
            print(f"  - {note}")

    if args.write:
        save_catalog(items)
        print("Saved updated catalog.json")
    else:
        print("Dry-run only. Use --write to persist.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
