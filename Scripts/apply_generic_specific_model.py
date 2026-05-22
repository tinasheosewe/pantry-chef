#!/usr/bin/env python3
"""Apply generic↔specific catalog model: families, alias hygiene, corpus enrichment.

Run from repo root:
    python3 PantryChef/Scripts/apply_generic_specific_model.py
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

from catalog_lib import (
    GENERIC_ONLY_BARE_ALIASES,
    NUT_VARIANT_OVERRIDES,
    add_aliases,
    build_alias_index,
    facet_options,
    items_by_id,
    load_alias_candidates,
    load_catalog,
    normalize_lookup_key,
    regenerate_families,
    save_catalog,
    save_families,
    set_facet_options,
    variant_label_for_specific,
)

# Corpus alias enrichment thresholds.
MIN_CORPUS_COUNT = 50

# Extra tokens that indicate a compound product, not a nut/oil alias for the base entry.
SKIP_EXTRA_TOKENS = {
    "extract", "milk", "butter", "pudding", "liqueur", "flavoring", "flavouring",
    "brittle", "bark", "paste", "frosting", "mix", "cereal", "chip", "substitute",
    "dressing", "sauce", "spread", "candy", "crumb", "crumbs", "cookie", "cookies",
    "bar", "bars", "oil", "flour", "meal", "cream", "syrup", "essence", "imitation",
    "filling", "topping", "glaze", "fudge", "caramel", "nougat", "praline", "halvah",
    "marzipan", "nougat", "coconut", "frosting", "handful",
}

OIL_VARIANT_OVERRIDES = {
    "extra virgin": "olive-oil",
    "virgin": "olive-oil",
    "pure": "olive-oil",
    "light": "olive-oil",
    "pomace": "olive-oil",
    "vegetable": "vegetable-oil",
    "neutral": "vegetable-oil",
    "blended": "vegetable-oil",
    "soybean": "soybean-oil",
    "rice bran": "rice-bran-oil",
    "flaxseed": "flaxseed-oil",
}

# Items intentionally given corpus-style aliases by apply_coverage_phase12.py.
PHASE12_PROTECTED_IDS = {
    "lemon", "orange", "lime", "ginger", "pimento", "tomato", "beans", "cheese",
    "beef", "corn", "syrup", "yogurt", "banana", "cream-soup", "pasta-sauce",
    "curry-powder", "mustard", "gelatin", "brussels-sprout", "graham-cracker-crumb",
    "oil", "nut",
    "raisin", "cracker", "herb", "prune", "ice-cream", "cake-mix", "crescent-roll",
    "vanilla-wafer", "tortilla-chip", "graham-cracker", "pumpkin-pie-spice",
    "pie-shell", "canned-green-chile",
}

# Known alias moves between specific entries in the same family.
ALIAS_MOVES: list[tuple[str, str, str]] = [
    # (from_id, alias, to_id)
    ("walnut", "black walnut", "black-walnut"),
    ("walnut", "black walnut flavoring", "black-walnut"),
]

# Facet values to add when corpus aliases imply them.
CORPUS_FACET_HINTS: dict[str, dict[str, list[str]]] = {
    "walnut": {"form": ["half", "piece"], "processing": ["candied"]},
    "pecan": {"form": ["half", "piece"], "processing": ["candied"]},
    "cashew": {"form": ["half", "piece"]},
    "almond": {"form": ["slivered"]},
    "peanut": {"processing": ["cocktail"]},
    "pistachio": {"form": ["whole"]},
}


def remove_alias(item: dict, alias: str) -> bool:
    aliases = item.get("aliases", [])
    if alias in aliases:
        aliases.remove(alias)
        return True
    return False


def add_facet_options(item: dict, key: str, options: list[str]) -> list[str]:
    added = []
    for facet in item.get("facets", []):
        if facet.get("key") == key:
            for opt in options:
                if opt not in facet["options"]:
                    facet["options"].append(opt)
                    added.append(opt)
            return added
    item.setdefault("facets", []).append({"key": key, "options": options})
    return options


def corpus_alias_ok(
    item_id: str,
    item: dict,
    corpus_name: str,
    extra_tokens: list[str],
    count: int,
    alias_index: dict[str, str],
    *,
    block_tokens: set[str] | None = None,
) -> bool:
    if count < MIN_CORPUS_COUNT:
        return False
    if any(t in SKIP_EXTRA_TOKENS for t in extra_tokens):
        return False
    if block_tokens and any(t in block_tokens for t in extra_tokens):
        return False

    key = normalize_lookup_key(corpus_name)
    owner = alias_index.get(key)
    if owner and owner != item_id:
        return False

    base = normalize_lookup_key(item["name"])
    if base not in key:
        return False
    if key == base:
        return False
    return True


def strip_bulk_corpus_enrichment(
    items: list[dict],
    candidates: dict,
    enrich_ids: set[str],
    report: dict,
) -> None:
    """Remove corpus aliases mistakenly added to non-family items."""
    stripped: dict[str, list[str]] = {}
    protected = PHASE12_PROTECTED_IDS | enrich_ids
    for item in items:
        item_id = item["id"]
        if item_id in protected or item_id not in candidates:
            continue
        corpus_names = {
            row["corpus_name"]
            for row in candidates[item_id]
            if row.get("count", 0) >= MIN_CORPUS_COUNT
        }
        if not corpus_names:
            continue
        before = list(item.get("aliases", []))
        after = [a for a in before if a not in corpus_names]
        if len(after) < len(before):
            item["aliases"] = after
            stripped[item_id] = [a for a in before if a in corpus_names]
    if stripped:
        report["stripped_bulk_enrichment"] = stripped
        report["stripped_item_count"] = len(stripped)


def apply_alias_moves(items: list[dict], report: dict) -> None:
    by_id = items_by_id(items)
    for from_id, alias, to_id in ALIAS_MOVES:
        src = by_id.get(from_id)
        dst = by_id.get(to_id)
        if not src or not dst:
            continue
        if remove_alias(src, alias):
            if add_aliases(dst, [alias]):
                report.setdefault("alias_moves", []).append(f"{from_id} → {to_id}: {alias!r}")


def sync_generic_variants(items: list[dict], families_data: dict, report: dict) -> None:
    by_id = items_by_id(items)
    for family in families_data["families"]:
        gid = family.get("genericId")
        if not gid or family.get("genericOnly") or gid not in by_id:
            continue
        labels = sorted(family.get("variantToSpecificId", {}).keys())
        if labels:
            set_facet_options(by_id[gid], "variant", labels)
            report.setdefault("synced_variants", []).append(f"{gid}: {len(labels)} variants")


def enforce_generic_aliases(items: list[dict], families_data: dict, report: dict) -> None:
    by_id = items_by_id(items)
    for family in families_data["families"]:
        gid = family.get("genericId")
        if not gid or gid not in by_id:
            continue
        allowed = family.get("genericOnlyAliases")
        if not allowed and gid in GENERIC_ONLY_BARE_ALIASES:
            allowed = sorted(GENERIC_ONLY_BARE_ALIASES[gid])
        if allowed and family.get("allowGenericPantrySubstitution"):
            by_id[gid]["aliases"] = [a for a in allowed if normalize_lookup_key(a) != normalize_lookup_key(by_id[gid]["name"])]
            report.setdefault("generic_aliases_reset", []).append(gid)


def strip_generic_aliases_from_specifics(items: list[dict], families_data: dict, report: dict) -> None:
    """Specific entries must not claim bare generic aliases (e.g. cooking oil on vegetable-oil)."""
    by_id = items_by_id(items)
    for family in families_data["families"]:
        if not family.get("allowGenericPantrySubstitution"):
            continue
        gid = family.get("genericId")
        if not gid:
            continue
        blocked = {
            normalize_lookup_key(a)
            for a in family.get("genericOnlyAliases", GENERIC_ONLY_BARE_ALIASES.get(gid, []))
        }
        blocked.add(normalize_lookup_key(by_id[gid]["name"]))
        for sid in family.get("specificIds", []):
            item = by_id.get(sid)
            if not item:
                continue
            before = list(item.get("aliases", []))
            after = [a for a in before if normalize_lookup_key(a) not in blocked]
            if len(after) < len(before):
                item["aliases"] = after
                report.setdefault("specific_generic_alias_strip", {})[sid] = [
                    a for a in before if normalize_lookup_key(a) in blocked
                ]


def enrich_from_corpus(
    items: list[dict],
    families_data: dict,
    candidates: dict,
    report: dict,
) -> None:
    """Add corpus aliases only to generic-family specific members (nuts, oils, …)."""
    by_id = items_by_id(items)
    alias_index = build_alias_index(items)

    enrich_ids: set[str] = set()
    for family in families_data["families"]:
        if not family.get("allowGenericPantrySubstitution"):
            continue
        enrich_ids.update(family.get("specificIds", []))

    for item_id in sorted(enrich_ids):
        item = by_id.get(item_id)
        if not item or item_id not in candidates:
            continue

        block = set()
        if item_id == "walnut":
            block.add("black")
        if item_id == "black-walnut":
            block.add("flavoring")

        new_aliases = []
        for row in candidates[item_id]:
            if corpus_alias_ok(
                item_id,
                item,
                row["corpus_name"],
                row.get("extra_tokens", []),
                row.get("count", 0),
                alias_index,
                block_tokens=block,
            ):
                new_aliases.append(row["corpus_name"])

        if new_aliases:
            added = add_aliases(item, new_aliases)
            if added:
                report.setdefault("corpus_aliases", {})[item_id] = added
                for key in [normalize_lookup_key(a) for a in added]:
                    alias_index[key] = item_id

        hints = CORPUS_FACET_HINTS.get(item_id, {})
        for facet_key, opts in hints.items():
            added_opts = add_facet_options(item, facet_key, opts)
            if added_opts:
                report.setdefault("corpus_facets", {})[item_id] = {
                    **report.get("corpus_facets", {}).get(item_id, {}),
                    facet_key: added_opts,
                }

    report["corpus_enriched_count"] = len(report.get("corpus_aliases", {}))


def family_enrich_ids(families_data: dict) -> set[str]:
    enrich_ids: set[str] = set()
    for family in families_data.get("families", []):
        if family.get("allowGenericPantrySubstitution"):
            enrich_ids.update(family.get("specificIds", []))
    return enrich_ids


def apply_migration(*, strip_only: bool = False) -> dict:
    items = copy.deepcopy(load_catalog())
    report: dict = {}
    candidates = load_alias_candidates()

    families_data = regenerate_families(items)
    enrich_ids = family_enrich_ids(families_data)
    strip_bulk_corpus_enrichment(items, candidates, enrich_ids, report)
    if strip_only:
        save_catalog(items)
        report["mode"] = "strip_only"
        return report

    apply_alias_moves(items, report)

    families_data = regenerate_families(items)
    # Patch oil variant map with overrides after regenerate.
    for family in families_data["families"]:
        if family.get("genericId") == "oil":
            variant_map = dict(family.get("variantToSpecificId", {}))
            variant_map.update(OIL_VARIANT_OVERRIDES)
            family["variantToSpecificId"] = dict(sorted(variant_map.items()))

    sync_generic_variants(items, families_data, report)
    enforce_generic_aliases(items, families_data, report)
    strip_generic_aliases_from_specifics(items, families_data, report)

    enrich_from_corpus(items, families_data, candidates, report)

    # Rebuild families after enrichment (variant lists unchanged but keep in sync).
    families_data = regenerate_families(items)
    for family in families_data["families"]:
        if family.get("genericId") == "oil":
            variant_map = dict(family.get("variantToSpecificId", {}))
            variant_map.update(OIL_VARIANT_OVERRIDES)
            family["variantToSpecificId"] = dict(sorted(variant_map.items()))

    save_catalog(items)
    save_families(families_data)
    report["catalog_entries"] = len(items)
    report["families"] = len(families_data["families"])
    return report


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Apply generic↔specific catalog model.")
    parser.add_argument(
        "--strip-only",
        action="store_true",
        help="Only remove mistaken bulk corpus enrichment; skip re-enrichment.",
    )
    args = parser.parse_args()
    report = apply_migration(strip_only=args.strip_only)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
