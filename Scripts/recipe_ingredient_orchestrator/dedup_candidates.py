"""Deduplicate catalog_candidates: union facets for same (base_ingredient, category)."""
import json
from collections import defaultdict

with open("ml_outputs/filtered_groups.json") as f:
    groups = json.load(f)

merged = defaultdict(lambda: defaultdict(set))

for g in groups:
    base = g["base_ingredient"]
    cat = g["category"]
    key = (base, cat)
    for facet_type, values in g.get("suggested_facets", {}).items():
        for v in values:
            merged[key][facet_type].add(v)

result = []
for (base, cat), facets in merged.items():
    if not base.strip():
        continue
    result.append({
        "base_ingredient": base,
        "category": cat,
        "suggested_facets": {k: sorted(v) for k, v in facets.items()} if facets else {}
    })

result.sort(key=lambda x: (x["category"], x["base_ingredient"]))

with open("ml_outputs/catalog_candidates.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Before: 806 entries")
print(f"After:  {len(result)} unique (base, category) pairs")

for base in ["beef", "chicken", "cheese", "potato"]:
    entries = [r for r in result if r["base_ingredient"] == base]
    for e in entries:
        n_facets = sum(len(v) for v in e["suggested_facets"].values())
        print(f"  {base} [{e['category']}]: {n_facets} facet values")
