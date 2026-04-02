#!/usr/bin/env python3
"""Merge new_bases_cleaned.json into catalog_bases.json and regenerate bases_by_aisle.json."""
import json, pathlib

OUT = pathlib.Path(__file__).resolve().parent / "triage_output"

catalog = json.loads((OUT / "catalog_bases.json").read_text())
new = json.loads((OUT / "new_bases_cleaned.json").read_text())

added = 0
for cat, bases in new.items():
    if cat not in catalog:
        catalog[cat] = []
    existing_names = {entry["base"].lower() for entry in catalog[cat]}
    for b in bases:
        if b.lower() not in existing_names:
            catalog[cat].append({"base": b})
            added += 1
    # Sort entries alphabetically by base name
    catalog[cat].sort(key=lambda e: e["base"].lower())

# Write updated catalog
(OUT / "catalog_bases.json").write_text(
    json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"
)

# Regenerate flat view
flat = {}
total = 0
for cat, entries in catalog.items():
    flat[cat] = sorted([e["base"] for e in entries], key=str.lower)
    total += len(flat[cat])

(OUT / "bases_by_aisle.json").write_text(
    json.dumps(flat, indent=2, ensure_ascii=False) + "\n"
)

print(f"Added {added} new bases → {total} total")
for cat in sorted(flat.keys()):
    print(f"  {cat}: {len(flat[cat])}")
