#!/usr/bin/env python3
"""Migrate catalog kind facets into inheritance links.

By default this is a dry-run and prints a summary.
Pass --write to persist catalog changes.
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, field
from pathlib import Path

from catalog_lib import (
    CATALOG_PATH,
    facet_options,
    items_by_id,
    load_catalog,
    normalize_lookup_key,
    save_catalog,
    slugify,
)

KIND_FACET_KEYS = {"variant"}
STATE_FACET_KEYS = {"form", "processing", "preservation", "preparation"}
SCRIPT_DIR = Path(__file__).resolve().parent
SEED_RECIPES_PATH = SCRIPT_DIR.parent / "PantryChef" / "Resources" / "seed_recipes.json"

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
    },
    "cheese": {
        "cheddar": "cheddar",
        "feta": "feta",
        "parmesan": "parmesan",
        "mozzarella": "mozzarella",
        "swiss": "swiss",
        "brie": "brie",
        "blue": "blue-cheese",
        "goat": "goat-cheese",
        "cream": "cream-cheese",
        "ricotta": "ricotta",
        "provolone": "provolone",
        "gouda": "gouda",
        "gruyere": "gruyere",
        "manchego": "manchego",
        "pecorino": "pecorino",
        "asiago": "asiago",
        "fontina": "fontina",
        "havarti": "havarti",
        "monterey jack": "monterey-jack",
        "pepper jack": "pepper-jack",
        "colby": "colby",
        "muenster": "muenster",
        "cottage": "cottage-cheese",
        "queso fresco": "queso-fresco",
        "cotija": "cotija",
        "halloumi": "halloumi",
        "mascarpone": "mascarpone",
        "burrata": "burrata",
        "string": "string-cheese",
        "american": "american-cheese",
        "vegan": "vegan-cheese",
    },
    "oil": {
        "olive": "olive-oil",
        "vegetable": "vegetable-oil",
        "canola": "canola-oil",
        "coconut": "coconut-oil",
        "sesame": "sesame-oil",
        "peanut": "peanut-oil",
        "avocado": "avocado-oil",
        "grapeseed": "grapeseed-oil",
        "sunflower": "sunflower-oil",
        "corn": "corn-oil",
        "walnut": "walnut-oil",
        "almond": "almond-oil",
        "truffle": "truffle-oil",
        "chili": "chili-oil",
    },
}

# Do not re-parent these as children of another family during migration.
PROTECTED_ROOT_IDS = set(FAMILY_ORDER)
NON_SHAREABLE_SHARED_CHILD_IDS = {
    "breast",
    "thigh",
    "wing",
    "drumstick",
    "leg",
    "loin",
    "shoulder",
    "shank",
    "chop",
    "rib",
    "tenderloin",
    "fillet",
    "neck",
    "belly",
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


def can_reuse_existing(existing_id: str, parent_id: str, parent: dict, by_id: dict[str, dict]) -> bool:
    existing = by_id.get(existing_id)
    if not existing:
        return False
    if existing_id == parent_id:
        return False
    # Never attach a family root as someone else's subclass.
    if existing_id in PROTECTED_ROOT_IDS:
        return False
    # Shared lexical cut names are not shared classes. Keep them scoped per parent.
    if existing_id in NON_SHAREABLE_SHARED_CHILD_IDS:
        return False
    if parent_id in existing.get("parentIds", []):
        return True
    # If a node already belongs to a different parent, do not reuse it by default.
    existing_parents = existing.get("parentIds", [])
    if existing_parents and parent_id not in existing_parents:
        return False
    if parent_id == "oil" and existing_id.endswith("-oil"):
        return True
    if parent_id == "nut" and existing.get("category") == parent.get("category"):
        return True
    return existing.get("category") == parent.get("category")


def resolve_child_id(parent_id: str, option: str, by_id: dict[str, dict]) -> str:
    parent = by_id[parent_id]
    option_key = canonical(option)
    override = KNOWN_VARIANT_IDS.get(parent_id, {}).get(option_key)
    if override and override in by_id:
        return override

    slug = slugify(option)
    scoped = f"{slug}-{parent_id}"

    if parent_id == "oil":
        oil_id = slug if slug.endswith("-oil") else f"{slug}-oil"
        if oil_id in by_id:
            return oil_id
        return oil_id

    candidates: list[str] = []
    if parent_id == "nut" and not slug.endswith("-nut"):
        candidates.extend([slug, f"{slug}-nut"])
    candidates.extend([scoped, slug])

    seen: set[str] = set()
    for candidate in candidates:
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        if candidate in by_id and can_reuse_existing(candidate, parent_id, parent, by_id):
            return candidate

    for item_id, item in by_id.items():
        if canonical(item.get("name", "")) != option_key:
            continue
        if can_reuse_existing(item_id, parent_id, parent, by_id):
            return item_id

    if slug in by_id and not can_reuse_existing(slug, parent_id, parent, by_id):
        return scoped
    if slug in PROTECTED_ROOT_IDS:
        return scoped
    return slug if slug not in by_id else scoped


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


def remaining_variant_parents(items: list[dict], skip: set[str]) -> list[str]:
    parents: list[str] = []
    for item in items:
        if item["id"] in skip:
            continue
        if facet_options(item, "variant"):
            parents.append(item["id"])
    return sorted(parents)


def repair_catalog(items: list[dict]) -> tuple[int, int]:
    """Strip invalid parent links and enforce additive facet inheritance."""
    by_id = items_by_id(items)
    stripped_links = 0
    merged_facets = 0

    for item in items:
        if item["id"] in PROTECTED_ROOT_IDS and item.get("parentIds"):
            item.pop("parentIds", None)
            stripped_links += 1

    for item in items:
        parent_ids = list(item.get("parentIds", []))
        cleaned: list[str] = []
        for parent_id in parent_ids:
            parent = by_id.get(parent_id)
            if not parent:
                stripped_links += 1
                continue
            if item["id"] in PROTECTED_ROOT_IDS:
                stripped_links += 1
                continue
            if parent.get("category") != item.get("category"):
                if not (parent_id == "oil" and item["id"].endswith("-oil")):
                    stripped_links += 1
                    continue
            cleaned.append(parent_id)
        if cleaned != parent_ids:
            if cleaned:
                item["parentIds"] = sorted(set(cleaned))
            else:
                item.pop("parentIds", None)

    for item in items:
        for parent_id in item.get("parentIds", []):
            parent = by_id.get(parent_id)
            if parent:
                merged_facets += enforce_additive_facets(item, parent)

    return stripped_links, merged_facets


def parent_alias_keys(parent: dict) -> set[str]:
    keys = {canonical(parent.get("name", ""))}
    keys.update(canonical(alias) for alias in parent.get("aliases", []))
    keys.discard("")
    return keys


def variant_matches_parent_alias(parent: dict, variant_value: str) -> bool:
    option_key = canonical(variant_value)
    if not option_key:
        return False
    for alias in parent_alias_keys(parent):
        if option_key == alias:
            return True
        if alias.startswith(f"{option_key} ") or alias.endswith(f" {option_key}"):
            return True
        if f" {option_key} " in f" {alias} ":
            return True
    return False


def state_facet_for_variant(parent: dict, variant_value: str) -> str | None:
    option_key = canonical(variant_value)
    for state_key in STATE_FACET_KEYS:
        for option in facet_options(parent, state_key):
            if canonical(option) == option_key:
                return state_key
    return None


def migrate_seed_recipes(items: list[dict], *, write: bool) -> tuple[int, int]:
    if not SEED_RECIPES_PATH.exists():
        return 0, 0
    by_id = items_by_id(items)
    with open(SEED_RECIPES_PATH, encoding="utf-8") as f:
        recipes = json.load(f)

    migrated_ingredients = 0
    unresolved = 0
    for recipe in recipes:
        for ingredient in recipe.get("ingredients", []):
            catalog_id = ingredient.get("catalogEntryId")
            if not catalog_id or catalog_id not in by_id:
                continue
            facets = ingredient.get("facetSelections", [])
            variant = next((f for f in facets if f.get("key") == "variant"), None)
            if not variant:
                continue
            parent = by_id[catalog_id]
            remaining = [f for f in facets if f.get("key") != "variant"]
            child_id = resolve_child_id(catalog_id, variant["value"], by_id)
            if child_id in by_id and child_id != catalog_id:
                ingredient["catalogEntryId"] = child_id
                ingredient["facetSelections"] = remaining
                migrated_ingredients += 1
                continue
            if canonical(variant["value"]) in parent_alias_keys(parent):
                ingredient["facetSelections"] = remaining
                migrated_ingredients += 1
                continue
            if variant_matches_parent_alias(parent, variant["value"]):
                ingredient["facetSelections"] = remaining
                migrated_ingredients += 1
                continue
            state_key = state_facet_for_variant(parent, variant["value"])
            if state_key and not any(f.get("key") == state_key for f in remaining):
                remaining.append({"key": state_key, "value": variant["value"]})
                ingredient["facetSelections"] = remaining
                migrated_ingredients += 1
                continue
            unresolved += 1

    if write:
        with open(SEED_RECIPES_PATH, "w", encoding="utf-8") as f:
            json.dump(recipes, f, indent=2, ensure_ascii=False)
            f.write("\n")
    return migrated_ingredients, unresolved


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply inheritance migration to catalog families.")
    parser.add_argument(
        "--families",
        nargs="*",
        default=[],
        help="Family ids to migrate (default: none unless --all is passed).",
    )
    parser.add_argument("--all", action="store_true", help="Migrate all known families.")
    parser.add_argument(
        "--remaining",
        action="store_true",
        help="Also migrate every catalog item that still has a variant facet.",
    )
    parser.add_argument(
        "--seed-recipes",
        action="store_true",
        help="Rewrite seed_recipes.json variant facets to subclass catalogEntryId values.",
    )
    parser.add_argument(
        "--repair",
        action="store_true",
        help="Repair invalid parent links and enforce additive facet inheritance.",
    )
    parser.add_argument("--write", action="store_true", help="Persist catalog.json changes.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    selected_families = list(FAMILY_ORDER if args.all else args.families)
    if not selected_families and not args.remaining and not args.seed_recipes and not args.repair:
        print("No work selected. Pass --families ..., --all, --remaining, --repair, and/or --seed-recipes.")
        return 0

    items = load_catalog()
    catalog_modified = False
    if args.repair:
        stripped, merged = repair_catalog(items)
        print(f"- repaired_parent_links_removed: {stripped}")
        print(f"- repaired_facet_merges: {merged}")
        catalog_modified = stripped > 0 or merged > 0
        if args.write and catalog_modified:
            save_catalog(items)
            print(f"Saved repaired {CATALOG_PATH.name}")
        elif not (selected_families or args.remaining or args.seed_recipes):
            print("Dry-run repair only. Use --write to persist.")
            return 0

    summary = MigrationSummary()
    for family_id in selected_families:
        migrate_family(family_id, items, summary)
        catalog_modified = True

    if args.remaining:
        skip = set(selected_families)
        for parent_id in remaining_variant_parents(items, skip):
            migrate_family(parent_id, items, summary)
        catalog_modified = True

    if summary.families_processed > 0 or summary.children_created > 0 or summary.children_linked > 0:
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

        stripped, merged = repair_catalog(items)
        if stripped or merged:
            print(f"- repaired_parent_links_removed: {stripped}")
            print(f"- repaired_facet_merges: {merged}")
            catalog_modified = True

    if args.seed_recipes:
        migrated, unresolved = migrate_seed_recipes(items, write=args.write)
        print(f"- seed_recipe_ingredients_migrated: {migrated}")
        print(f"- seed_recipe_ingredients_unresolved: {unresolved}")

    if catalog_modified:
        if args.write:
            save_catalog(items)
            print(f"Saved updated {CATALOG_PATH.name}")
        else:
            print("Dry-run only. Use --write to persist catalog changes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
