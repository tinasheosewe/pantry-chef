#!/usr/bin/env python3
"""Deduplicate facet values that appear under multiple facet keys for the
same catalog item.  When the same option string (e.g. "ground") sits in two
different facet key lists on one item the search engine can resolve the query
token to BOTH keys, producing display names like "Ground Ground Elk".

Strategy: for each conflict pair we define a *winner* key.  The duplicate
value is removed from the loser key's option list.  If removing a value would
leave a facet with zero options, the empty facet definition is removed too.
If the removed value was the item's defaultSelection for that key, the
defaultSelection is also pruned.

Rules are category-aware where needed (e.g. Protein keeps meat-cut words in
variant; Grains keeps them in form).
"""

import json
import sys
from collections import defaultdict
from pathlib import Path

CATALOG_PATH = Path(__file__).resolve().parent.parent / "PantryChef" / "Resources" / "catalog.json"

# ── Pair rules ──────────────────────────────────────────────────────────
# For each (keyA, keyB) conflict the winner is the key to KEEP the value in.
# Some rules are category-conditional.

# Category sets
PROTEIN_CATS = {"Protein"}
GRAIN_CATS = {"Grains & Cereals"}
LEGUME_CATS = {"Legumes & Beans"}


def winner_form_variant(item, _value):
    """form & variant — category dependent."""
    cat = item.get("category", "")
    if cat in PROTEIN_CATS:
        return "variant"
    if cat in GRAIN_CATS | LEGUME_CATS:
        return "form"
    # Dairy: whipped/clarified/white/powder are product types → variant
    # Baking: powdered/mini/paste/granulated → form for physical state
    if cat in {"Baking & Sweeteners"}:
        return "form"
    if cat in {"Dairy & Eggs"}:
        return "variant"
    # Produce: baby → variant, sliced/whole → form
    if cat == "Produce":
        if _value in {"baby"}:
            return "variant"
        return "form"
    # Default: variant (product identity wins)
    return "variant"


def winner_processing_variant(_item, _value):
    return "variant"


def winner_form_preservation(_item, _value):
    return "preservation"


def winner_preservation_variant(_item, _value):
    return "variant"


def winner_concentration_variant(_item, _value):
    return "variant"


def winner_preservation_processing(_item, _value):
    return "processing"


def winner_texture_variant(_item, _value):
    return "variant"


def winner_form_preparation(_item, _value):
    return "preparation"


def winner_form_processing(_item, _value):
    return "processing"


def winner_form_texture(_item, _value):
    return "form"


PAIR_RULES = {
    ("form", "variant"): winner_form_variant,
    ("processing", "variant"): winner_processing_variant,
    ("form", "preservation"): winner_form_preservation,
    ("preservation", "variant"): winner_preservation_variant,
    ("concentration", "variant"): winner_concentration_variant,
    ("preservation", "processing"): winner_preservation_processing,
    ("texture", "variant"): winner_texture_variant,
    ("form", "preparation"): winner_form_preparation,
    ("form", "processing"): winner_form_processing,
    ("form", "texture"): winner_form_texture,
}


def find_duplicates(item):
    """Yield (value, [key1, key2, ...]) for every value in >1 facet key."""
    value_to_keys = defaultdict(list)
    for facet in item.get("facets", []):
        for opt in facet["options"]:
            value_to_keys[opt.lower()].append(facet["key"])
    for value, keys in value_to_keys.items():
        if len(keys) > 1:
            yield value, keys


def resolve_winner(item, value, keys):
    """Given the conflicting keys, return the set of keys to REMOVE the value from."""
    losers = set()
    # Compare every pair and collect loser keys
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            pair = tuple(sorted([keys[i], keys[j]]))
            rule = PAIR_RULES.get(pair)
            if rule is None:
                # No rule — skip (shouldn't happen if PAIR_RULES is complete)
                print(f"  WARNING: no rule for {pair} on {item['id']}:{value}", file=sys.stderr)
                continue
            winner_key = rule(item, value)
            loser_key = keys[i] if keys[i] != winner_key else keys[j]
            losers.add(loser_key)
    return losers


def remove_option(item, facet_key, value):
    """Remove value from item's facet options (case-insensitive).
    Also prune defaultSelection if it points to the removed value.
    Returns True if anything was changed."""
    changed = False
    for facet in item.get("facets", []):
        if facet["key"] != facet_key:
            continue
        original_len = len(facet["options"])
        facet["options"] = [o for o in facet["options"] if o.lower() != value]
        if len(facet["options"]) < original_len:
            changed = True

    # Prune empty facet definitions
    item["facets"] = [f for f in item["facets"] if f["options"]]

    # Prune defaultSelection if it referenced the removed value
    if "defaultSelections" in item:
        item["defaultSelections"] = [
            s for s in item["defaultSelections"]
            if not (s["key"] == facet_key and s["value"].lower() == value)
        ]
        if not item["defaultSelections"]:
            del item["defaultSelections"]

    return changed


def main():
    if not CATALOG_PATH.exists():
        print(f"Error: catalog not found at {CATALOG_PATH}", file=sys.stderr)
        sys.exit(1)

    with open(CATALOG_PATH) as f:
        catalog = json.load(f)

    total_removals = 0
    items_touched = set()
    removal_log = []

    for item in catalog:
        for value, keys in find_duplicates(item):
            losers = resolve_winner(item, value, keys)
            for loser_key in losers:
                if remove_option(item, loser_key, value):
                    total_removals += 1
                    items_touched.add(item["id"])
                    winner_keys = [k for k in keys if k not in losers]
                    removal_log.append(
                        f"  {item['id']}: removed \"{value}\" from {loser_key} (kept in {', '.join(winner_keys)})"
                    )

    # Verify no duplicates remain
    remaining = 0
    for item in catalog:
        for value, keys in find_duplicates(item):
            remaining += 1
            print(f"  REMAINING: {item['id']}: \"{value}\" in {keys}", file=sys.stderr)

    print(f"Removed {total_removals} duplicate options across {len(items_touched)} items")
    if remaining:
        print(f"WARNING: {remaining} duplicates remain (no rule matched)", file=sys.stderr)
    else:
        print("All duplicates resolved successfully")

    print()
    for line in sorted(removal_log):
        print(line)

    # Write back
    with open(CATALOG_PATH, "w") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"\nWrote cleaned catalog to {CATALOG_PATH}")


if __name__ == "__main__":
    main()
