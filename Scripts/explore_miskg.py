#!/usr/bin/env python3
"""Explore MISKG data to understand structure and coverage."""
import json
import csv
from collections import Counter, defaultdict

DATA_DIR = "Scripts/miskg_data/Competition-Dataset"

# 1. Substitution pairs
with open(f"{DATA_DIR}/substitution_pairs.json") as f:
    pairs = json.load(f)
print(f"Substitution pairs: {len(pairs)} total")
print(f"Sample pair: {pairs[0]}")
print(f"Sample pair: {pairs[100]}")

# 2. Unique ingredients
ingredients = set(p["ingredient"] for p in pairs)
substitutes = set(p["substitution"] for p in pairs)
print(f"\nUnique ingredients: {len(ingredients)}")
print(f"Unique substitutes: {len(substitutes)}")

# Count subs per ingredient
counts = Counter(p["ingredient"] for p in pairs)
print(f"\nTop 20 ingredients by sub count:")
for name, count in counts.most_common(20):
    print(f"  {name}: {count} substitutes")
print(f"\nAvg subs per ingredient: {len(pairs)/len(ingredients):.1f}")

# 3. Edamam nutrition sample
with open(f"{DATA_DIR}/edamam.json") as f:
    edamam = json.load(f)
print(f"\nEdamam entries: {len(edamam)}")
sample_key = list(edamam.keys())[0]
print(f"Sample edamam entry: {json.dumps(edamam[sample_key], indent=2)[:500]}")

# 4. Processed ingredients
with open(f"{DATA_DIR}/processed_ingredients_with_id.csv") as f:
    reader = csv.DictReader(f)
    processed = list(reader)
print(f"\nProcessed ingredients: {len(processed)}")
print(f"Sample: {processed[0]}")

# 5. Check common cooking ingredients coverage
common = [
    "butter", "milk", "egg", "flour", "sugar", "salt", "pepper",
    "olive oil", "garlic", "onion", "chicken", "beef", "rice", "pasta",
    "tomato", "cheese", "cream", "lemon", "ginger", "soy sauce",
    "vinegar", "honey", "yogurt", "bread", "potato", "carrot",
    "celery", "bell pepper", "mushroom", "spinach", "basil", "oregano",
    "cumin", "paprika", "cinnamon", "vanilla", "coconut milk",
    "broccoli", "avocado", "bacon", "shrimp", "salmon", "tofu",
    "corn", "beans", "lentils", "oats", "almonds", "walnuts",
    "chocolate", "cocoa powder", "baking powder", "baking soda",
    "cornstarch", "sesame oil", "fish sauce", "worcestershire sauce",
    "maple syrup", "brown sugar", "heavy cream", "sour cream",
    "cream cheese", "mozzarella", "parmesan", "cheddar",
    "ground beef", "chicken breast", "pork", "lamb", "turkey",
    "thyme", "rosemary", "cilantro", "parsley", "dill", "chili",
    "turmeric", "nutmeg", "cloves", "bay leaf", "fennel",
]

found = [i for i in common if i in ingredients]
missing = [i for i in common if i not in ingredients]
print(f"\nCommon ingredient coverage: {len(found)}/{len(common)}")
print(f"Missing common ingredients: {missing}")

# 6. Build a quick lookup for sub counts of common ingredients
print(f"\nCommon ingredient sub counts:")
for name in sorted(found)[:30]:
    print(f"  {name}: {counts.get(name, 0)} substitutes")
