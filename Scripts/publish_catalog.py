#!/usr/bin/env python3
"""Publish staging enriched catalog → production catalog.json for the app bundle.

Staging:    Scripts/triage_output/enriched_catalog.json   (dict-keyed, lowercase storage, enriched category names)
Production: PantryChef/Resources/catalog.json             (array, Swift-compatible enum rawValues)

Run from repo root:
    python3 Scripts/publish_catalog.py
"""
import json, sys
from collections import OrderedDict
from pathlib import Path

STAGING  = Path("Scripts/triage_output/enriched_catalog.json")
PROD     = Path("PantryChef/Resources/catalog.json")

# Maps enriched catalog category names → FoodCategory rawValues (must stay in sync with Enums.swift)
CATEGORY_MAP = {
    "Alcohol & Spirits":   "Alcohol & Spirits",
    "Baking & Sweeteners": "Baking & Sweeteners",
    "Beverages":           "Beverages",
    "Breads & Bakery":     "Breads & Bakery",
    "Canned & Jarred":     "Canned & Jarred",
    "Condiments & Sauces": "Condiments & Sauces",
    "Dairy & Eggs":        "Dairy & Eggs",
    "Frozen Foods":        "Frozen Foods",
    "Grains & Cereals":    "Grains & Cereals",
    "Legumes & Beans":     "Legumes & Beans",
    "Nuts & Seeds":        "Nuts & Seeds",
    "Oils & Fats":         "Oils & Fats",
    "Other":               "Other",
    "Pasta & Noodles":     "Pasta & Noodles",
    "Produce":             "Produce",
    "Protein":             "Protein",
    "Snacks":              "Snacks",
    "Spices & Herbs":      "Spices & Herbs",
}

# Maps lowercase storage → PantryStorage rawValues
STORAGE_MAP = {
    "pantry":       "Pantry",
    "refrigerated": "Refrigerated",
    "frozen":       "Frozen",
}


def convert_item(raw: dict) -> dict:
    """Convert one enriched catalog item to production format."""
    item = OrderedDict()
    item["id"]              = raw["id"]
    item["name"]            = raw["name"]
    item["category"]        = CATEGORY_MAP[raw["category"]]
    item["defaultUnit"]     = raw.get("defaultUnit")
    item["defaultQuantity"] = raw.get("defaultQuantity")
    item["defaultStorage"]  = STORAGE_MAP[raw["defaultStorage"]]
    item["aliases"]         = raw.get("aliases", [])
    item["facets"]          = raw.get("facets", [])
    item["defaultSelections"] = raw.get("defaultSelections", [])

    # Convert freshnessByStorage keys to capitalized PantryStorage rawValues
    raw_freshness = raw.get("freshnessByStorage", {})
    freshness = OrderedDict()
    for key, val in raw_freshness.items():
        mapped_key = STORAGE_MAP.get(key, key)
        if isinstance(val, list) and len(val) == 2:
            freshness[mapped_key] = val
    item["freshnessByStorage"] = freshness

    return item


def main():
    if not STAGING.exists():
        print(f"ERROR: staging file not found: {STAGING}", file=sys.stderr)
        sys.exit(1)

    with open(STAGING) as f:
        staging = json.load(f)

    # Validate categories
    unknown = set()
    for name, raw in staging.items():
        cat = raw.get("category", "")
        if cat not in CATEGORY_MAP:
            unknown.add(cat)
    if unknown:
        print(f"ERROR: unknown categories: {unknown}", file=sys.stderr)
        sys.exit(1)

    # Convert dict → sorted array
    items = [convert_item(raw) for raw in staging.values()]
    items.sort(key=lambda x: x["id"])

    PROD.parent.mkdir(parents=True, exist_ok=True)
    with open(PROD, "w") as f:
        json.dump(items, f, indent=2, ensure_ascii=False)

    print(f"Published {len(items)} items → {PROD}")


if __name__ == "__main__":
    main()
