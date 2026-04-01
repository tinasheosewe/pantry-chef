#!/usr/bin/env python3
"""
Extract all NER ingredient entities from RecipeNLG (2.2M recipes)
and output them sorted by frequency.

Reads dataset/full_dataset.csv, counts the NER column, writes
Scripts/ingredient_frequencies.json
"""

import ast
import csv
import json
import sys
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
CSV_PATH = REPO_ROOT / "dataset" / "full_dataset.csv"
OUTPUT_PATH = Path(__file__).parent / "ingredient_frequencies.json"


def main():
    if not CSV_PATH.exists():
        print(f"ERROR: {CSV_PATH} not found")
        sys.exit(1)

    print(f"Reading {CSV_PATH} ...")
    counter = Counter()
    total_entities = 0
    row_count = 0
    errors = 0

    with open(CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            row_count += 1
            ner_raw = row.get("NER", "")
            if not ner_raw:
                continue
            try:
                entities = ast.literal_eval(ner_raw)
                for entity in entities:
                    cleaned = entity.strip().lower()
                    if cleaned:
                        counter[cleaned] += 1
                        total_entities += 1
            except (ValueError, SyntaxError):
                errors += 1

            if row_count % 500_000 == 0:
                print(f"  {row_count:>10,} recipes | {total_entities:>12,} entities | {len(counter):>8,} unique")

    print(f"\nDone: {row_count:,} recipes, {total_entities:,} entities, {len(counter):,} unique, {errors:,} parse errors")

    # Sort by frequency descending
    sorted_items = counter.most_common()

    with open(OUTPUT_PATH, "w") as f:
        json.dump(sorted_items, f, indent=2)

    print(f"Saved to {OUTPUT_PATH}")

    # Top 50 preview
    print("\n=== TOP 50 INGREDIENTS ===")
    for rank, (name, count) in enumerate(sorted_items[:50], 1):
        pct = count / row_count * 100
        print(f"  {rank:3d}. {name:<40s} {count:>8,} ({pct:5.1f}%)")

    # Frequency distribution
    print(f"\n=== FREQUENCY DISTRIBUTION ===")
    for threshold, label in [(100_000, "100k+"), (10_000, "10k+"), (1_000, "1k+"), (100, "100+"), (10, "10+"), (1, "1+")]:
        n = sum(1 for _, c in sorted_items if c >= threshold)
        print(f"  {label:>8s}: {n:>6,} ingredients")


if __name__ == "__main__":
    main()
