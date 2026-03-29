"""Ingredient gap analysis — cross-reference recipes vs catalog."""
import json
from collections import Counter
from pathlib import Path

OUT = Path(__file__).parent / "recipe_ingredient_orchestrator" / "output"

recipes = json.loads((OUT / "recipes.json").read_text())
catalog = json.loads((OUT / "ingredient_catalog.json").read_text())

catalog_names = {e["name"].lower() for e in catalog}
catalog_ids = {e["id"] for e in catalog}

recipe_ingredients = Counter()
unmatched = Counter()
for r in recipes:
    for ing in r.get("ingredients", []):
        name = ing.get("name", "")
        cat_id = ing.get("catalog_entry_id", "")
        recipe_ingredients[name] += 1
        if cat_id not in catalog_ids and name.lower() not in catalog_names:
            unmatched[name] += 1

print(f"Unique ingredients in recipes: {len(recipe_ingredients)}")
print(f"Unmatched to catalog (by id or name): {len(unmatched)}")
print()
print("=== Top 40 UNMATCHED ingredients (used in recipes but missing from catalog) ===")
for name, count in unmatched.most_common(40):
    print(f"  {name}: {count} recipes")

print()
print("=== Top 30 MOST-USED ingredients overall ===")
for name, count in recipe_ingredients.most_common(30):
    flag = " [MISSING]" if name.lower() not in catalog_names and name not in catalog_ids else ""
    print(f"  {name}: {count}{flag}")

print()
print("=== Category distribution (current) ===")
by_cat = Counter()
for e in catalog:
    by_cat[e["category"]] += 1
for cat, count in by_cat.most_common():
    print(f"  {cat}: {count}")

# Common staples that should exist
EXPECTED_STAPLES = {
    "Protein": [
        "Chicken Breast", "Chicken Thigh", "Ground Beef", "Beef Steak",
        "Pork Chop", "Pork Tenderloin", "Ground Turkey", "Turkey Breast",
        "Shrimp", "Salmon", "Cod", "Tuna", "Lamb", "Duck", "Sausage",
        "Eggs", "Bacon", "Ham", "Tempeh",
    ],
    "Dairy": [
        "Milk", "Butter", "Heavy Cream", "Cheddar Cheese", "Mozzarella",
        "Parmesan Cheese", "Cream Cheese", "Yogurt", "Ricotta", "Swiss Cheese",
        "Goat Cheese", "Brie", "Eggs",
    ],
    "Produce": [
        "Onion", "Tomato", "Lemon", "Lime", "Avocado", "Mushrooms",
        "Corn", "Celery", "Lettuce", "Cucumber", "Sweet Potato",
        "Banana", "Mango", "Strawberry", "Blueberry", "Asparagus",
        "Green Onion", "Jalapeno", "Red Onion", "Cherry Tomatoes",
        "Fresh Parsley", "Fresh Basil", "Fresh Mint",
    ],
    "Pasta & Noodles": [
        "Spaghetti", "Fettuccine", "Penne", "Rice Noodles", "Egg Noodles",
        "Ramen Noodles", "Udon Noodles", "Lasagna Sheets", "Linguine",
    ],
    "Grains & Cereals": [
        "White Rice", "Brown Rice", "Bread", "Flour", "Tortilla",
        "Naan", "Jasmine Rice", "Basmati Rice",
    ],
}

print()
print("=== MISSING STAPLES per category ===")
for cat, staples in EXPECTED_STAPLES.items():
    missing = [s for s in staples if s.lower() not in catalog_names]
    if missing:
        print(f"\n  {cat} ({len(missing)} missing):")
        for m in missing:
            print(f"    - {m}")
