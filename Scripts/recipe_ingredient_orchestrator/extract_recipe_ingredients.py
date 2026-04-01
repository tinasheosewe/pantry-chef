#!/usr/bin/env python3
"""
Extract all NER ingredient entities from RecipeNLG (2.2M recipes)
and output them sorted by frequency.

Uses the HuggingFace datasets library to stream the data
(avoids downloading the entire ~2GB CSV to disk).
"""

import json
import sys
from collections import Counter
from pathlib import Path

OUTPUT_DIR = Path(__file__).parent / "ml_outputs"


def main():
    from datasets import load_dataset

    print("Loading RecipeNLG dataset (streaming)...")
    ds = load_dataset("mbien/recipe_nlg", split="train", trust_remote_code=True)

    print(f"Dataset loaded: {len(ds):,} recipes")

    # Count every NER entity (lowercased, stripped)
    counter = Counter()
    total_entities = 0

    for i, row in enumerate(ds):
        ner_list = row.get("ner", [])
        for entity in ner_list:
            cleaned = entity.strip().lower()
            if cleaned:
                counter[cleaned] += 1
                total_entities += 1

        if (i + 1) % 500_000 == 0:
            print(f"  Processed {i+1:,} recipes, {total_entities:,} entities so far, {len(counter):,} unique...")

    print(f"\nDone: {len(ds):,} recipes, {total_entities:,} total entities, {len(counter):,} unique")

    # Sort by frequency descending
    sorted_items = counter.most_common()

    # Save full list as JSON (array of [name, count])
    output_path = OUTPUT_DIR / "ingredient_frequencies.json"
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    with open(output_path, "w") as f:
        json.dump(sorted_items, f, indent=2)

    print(f"\nSaved {len(sorted_items):,} unique ingredients to {output_path}")

    # Print top 50 preview
    print("\n=== TOP 50 INGREDIENTS ===")
    for rank, (name, count) in enumerate(sorted_items[:50], 1):
        pct = count / len(ds) * 100
        print(f"  {rank:3d}. {name:<35s} {count:>8,} ({pct:5.1f}% of recipes)")

    # Print summary stats
    print(f"\n=== FREQUENCY DISTRIBUTION ===")
    brackets = [
        (10000, "10,000+"),
        (1000, "1,000-9,999"),
        (100, "100-999"),
        (10, "10-99"),
        (1, "1-9"),
    ]
    for threshold, label in brackets:
        n = sum(1 for _, c in sorted_items if c >= threshold)
        print(f"  {label:>15s}: {n:,} ingredients")


if __name__ == "__main__":
    main()
