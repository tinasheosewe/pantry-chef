#!/usr/bin/env python3
"""Quick check for how stale old recipes are vs new catalog."""
import json, pathlib

base = pathlib.Path(__file__).parent / "output"
cat = json.loads((base / "ingredient_catalog.json").read_text())
recs = json.loads((base / "recipes.json").read_text())

print(f"Catalog entries: {len(cat)}")
cats = {}
for e in cat:
    c = e.get("category", "?")
    cats[c] = cats.get(c, 0) + 1
for c, n in sorted(cats.items(), key=lambda x: -x[1]):
    print(f"  {c}: {n}")

print(f"\nStale recipes: {len(recs)}")

cat_ids = {e["id"] for e in cat}
missing = set()
total = 0
for r in recs:
    for ing in r.get("ingredients", []):
        total += 1
        cid = ing.get("catalog_entry_id")
        if cid and cid not in cat_ids:
            missing.add(cid)

unique_ids = set()
for r in recs:
    for ing in r.get("ingredients", []):
        cid = ing.get("catalog_entry_id")
        if cid:
            unique_ids.add(cid)

print(f"Total ingredient refs: {total}")
print(f"Unique catalog IDs used: {len(unique_ids)}")
print(f"Missing from new catalog: {len(missing)}")
if missing:
    for m in sorted(missing):
        print(f"  - {m}")
