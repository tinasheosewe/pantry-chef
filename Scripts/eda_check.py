#!/usr/bin/env python3
"""Quick EDA on the ingredient catalog and recipe corpus."""
import json
import sys
from collections import Counter
from pathlib import Path

BASE = Path(__file__).parent / "recipe_ingredient_orchestrator" / "output"

def eda_catalog(path: Path) -> None:
    data = json.loads(path.read_text())
    print(f"=== Ingredient Catalog: {len(data)} entries ===")

    # Category distribution
    cats = Counter(e.get("category", "?") for e in data)
    for c, n in cats.most_common():
        print(f"  {c}: {n}")

    # Word-superset overlap check within same category
    overlaps = []
    for i, a in enumerate(data):
        for j, b in enumerate(data):
            if i >= j:
                continue
            if a.get("category") != b.get("category"):
                continue
            wa = set(a["name"].lower().split())
            wb = set(b["name"].lower().split())
            if wa < wb or wb < wa:
                overlaps.append((a["name"], b["name"], a.get("category")))

    if overlaps:
        print(f"\nOVERLAPS FOUND ({len(overlaps)}):")
        for a, b, c in overlaps:
            print(f"  {a} <-> {b} ({c})")
    else:
        print("\nNo same-category overlaps found!")

    # Facet richness
    variant_counts, form_counts, sub_counts = [], [], []
    for e in data:
        v_count = f_count = 0
        for f in e.get("facets", []):
            if f.get("key") == "variant":
                v_count = len(f.get("options", []))
            elif f.get("key") == "form":
                f_count = len(f.get("options", []))
        variant_counts.append(v_count)
        form_counts.append(f_count)
        sub_counts.append(len(e.get("substitution_suggestions", [])))

    n = len(data)
    print(f"\nFacet richness:")
    print(f"  Avg variant options: {sum(variant_counts)/n:.1f}")
    print(f"  Avg form options: {sum(form_counts)/n:.1f}")
    print(f"  Avg substitution suggestions: {sum(sub_counts)/n:.1f}")
    print(f"  Entries with 0 variants: {variant_counts.count(0)}")
    print(f"  Entries with 0 forms: {form_counts.count(0)}")


def eda_recipes(path: Path) -> None:
    data = json.loads(path.read_text())
    print(f"\n=== Recipe Corpus: {len(data)} recipes ===")

    cuisines = Counter(r.get("cuisine", "?") for r in data)
    print("Cuisine distribution:")
    for c, n in cuisines.most_common():
        print(f"  {c}: {n}")

    meals = Counter(r.get("meal_type", "?") for r in data)
    print("Meal type distribution:")
    for m, n in meals.most_common():
        print(f"  {m}: {n}")

    # Ingredient count stats
    ing_counts = [len(r.get("ingredients", [])) for r in data]
    step_counts = [len(r.get("steps", [])) for r in data]
    if ing_counts:
        print(f"\nIngredient count: avg={sum(ing_counts)/len(ing_counts):.1f}, min={min(ing_counts)}, max={max(ing_counts)}")
    if step_counts:
        print(f"Step count: avg={sum(step_counts)/len(step_counts):.1f}, min={min(step_counts)}, max={max(step_counts)}")

    # Duplicate titles
    titles = [r.get("title", "") for r in data]
    dupes = [t for t, c in Counter(titles).items() if c > 1]
    if dupes:
        print(f"\nDuplicate titles ({len(dupes)}): {dupes[:10]}")
    else:
        print("\nNo duplicate titles!")


if __name__ == "__main__":
    catalog_path = BASE / "ingredient_catalog.json"
    recipes_path = BASE / "seed_recipes.json"

    if catalog_path.exists():
        eda_catalog(catalog_path)

    if recipes_path.exists():
        eda_recipes(recipes_path)
    else:
        # Check for recipes.json too
        alt = BASE / "recipes.json"
        if alt.exists():
            eda_recipes(alt)
