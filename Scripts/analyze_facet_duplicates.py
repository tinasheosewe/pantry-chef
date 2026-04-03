#!/usr/bin/env python3
"""Analyze duplicate facet patterns by category to build deduplication rules."""

import json
from collections import defaultdict
from pathlib import Path

CATALOG_PATH = Path(__file__).resolve().parent.parent / "PantryChef" / "Resources" / "catalog.json"

with open(CATALOG_PATH) as f:
    catalog = json.load(f)

pair_by_category = defaultdict(list)
for item in catalog:
    vals = {}
    for facet in item.get("facets", []):
        for opt in facet["options"]:
            n = opt.lower()
            if n in vals:
                pair = tuple(sorted([vals[n], facet["key"]]))
                pair_by_category[(pair, item.get("category", ""))].append((item["id"], n))
            else:
                vals[n] = facet["key"]

for pair_key in sorted(set(p for p, _ in pair_by_category.keys())):
    print(f"\n{'=' * 60}")
    print(f"{' & '.join(pair_key)} by category:")
    print(f"{'=' * 60}")
    for (pair, cat), items in sorted(pair_by_category.items()):
        if pair == pair_key:
            values = sorted(set(v for _, v in items))
            print(f"  {cat} ({len(items)}): {values}")
